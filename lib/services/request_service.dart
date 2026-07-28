import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../models/request_item.dart';
import '../models/user_summary.dart';
import '../state/session.dart';
import 'directus_client.dart';
import 'member_identity_service.dart';
import 'organization_service.dart';

class RequestPermissionException implements Exception {
  final String message;
  const RequestPermissionException(this.message);

  @override
  String toString() => message;
}

class RequestRoleUnavailableException implements Exception {
  final String message;
  const RequestRoleUnavailableException(this.message);

  @override
  String toString() => message;
}

class UserNotFoundException implements Exception {
  final String email;
  const UserNotFoundException(this.email);
}

class RequestCreateException implements Exception {
  final String message;
  const RequestCreateException(this.message);

  @override
  String toString() => message;
}

enum RequestCancellationFailure {
  unauthenticated,
  forbidden,
  notFound,
  conflict,
  network,
  unknown,
}

class RequestCancellationException implements Exception {
  final RequestCancellationFailure failure;
  final String message;

  const RequestCancellationException(this.failure, this.message);

  @override
  String toString() => message;
}

class RequestCreateResult {
  final RequestItem? request;

  const RequestCreateResult({required this.request});
}

enum RequestFieldAvailability { supported, unsupported, unknown }

class ScanRequestFieldSupport {
  final RequestFieldAvailability requiredMinReadiness;
  final RequestFieldAvailability note;
  final String? noteFieldName;

  const ScanRequestFieldSupport({
    required this.requiredMinReadiness,
    required this.note,
    required this.noteFieldName,
  });

  bool get supportsRequiredMinReadiness {
    return requiredMinReadiness != RequestFieldAvailability.unsupported;
  }

  bool get supportsNoteField {
    return note == RequestFieldAvailability.supported && noteFieldName != null;
  }
}

class RequestService {
  RequestService._();

  static final RequestService instance = RequestService._();
  static const String _scanRequestSafeFields =
      'id,status,request_type,business_profile,requested_by_user,requested_by_user.id,requested_by_user.email,requested_by_user.first_name,requested_by_user.last_name,target_member,department,due_at,requested_at,completed_scan,completed_at,cancelled';
  ScanRequestFieldSupport? _cachedFieldSupport;
  String? _cachedFieldSupportWorkspaceSignature;

  Dio get _client => DirectusClient.instance.client;

  void clearScanRequestFieldSupportCache() {
    _cachedFieldSupport = null;
    _cachedFieldSupportWorkspaceSignature = null;
  }

  Future<List<UserSummary>> fetchUsers({int limit = 100}) async {
    try {
      final response = await _client.get(
        '/users',
        queryParameters: {
          'limit': limit,
          'sort': 'email',
          'fields': 'id,email,first_name,last_name',
        },
      );
      final data = response.data['data'];
      if (data is! List) return const [];
      return data
          .whereType<Map<String, dynamic>>()
          .map(UserSummary.fromJson)
          .where((u) => u.email.isNotEmpty)
          .toList();
    } on DioException catch (e) {
      throw RequestPermissionException(_extractMessage(e));
    }
  }

  Future<List<RequestItem>> fetchRequests({int limit = 50}) async {
    final userId = Session.instance.userId?.trim();
    if (userId == null || userId.isEmpty) return const [];
    return _fetchScanRequests(
      limit: limit,
      query: {'filter[requested_by_user][_eq]': userId},
      includeCancelled: true,
    );
  }

  Future<List<RequestItem>> fetchIncomingRequests({
    required String userId,
    int limit = 50,
    String? statusFilter,
  }) async {
    final normalizedUserId = userId.trim();
    if (normalizedUserId.isEmpty) return const [];
    final workspace = await OrganizationService.instance
        .fetchActiveWorkspaceContext();
    if (workspace == null) return const [];
    if (workspace.memberRole == 'user') return const [];
    debugPrint(
      '[ROLE_DEBUG] has_current_user=${workspace.currentUserId.trim().isNotEmpty}',
    );
    debugPrint('[ROLE_DEBUG] has_incoming_user=${normalizedUserId.isNotEmpty}');
    debugPrint('[ROLE_DEBUG] directusRoleName=${workspace.directusRoleName}');
    debugPrint(
      '[ROLE_DEBUG] finalEffectiveRole=${workspace.finalEffectiveRole}',
    );
    final activeProfileId = workspace.businessProfileId.trim();
    final membershipId = workspace.membershipId.trim();
    if (membershipId.isEmpty || activeProfileId.isEmpty) return const [];

    final query = <String, dynamic>{
      'filter[business_profile][_eq]': activeProfileId,
      'filter[target_member][_eq]': membershipId,
    };
    if (statusFilter != null && statusFilter.trim().isNotEmpty) {
      query['filter[status][_eq]'] = statusFilter.trim();
    }
    debugPrint(
      '[SCAN_REQUESTS] canonical_assignee_field=target_member has_membership_id=${membershipId.isNotEmpty} scoped_profile=${activeProfileId.isNotEmpty}',
    );
    debugPrint(
      '[MOBILE_REQUESTS] has_member_id=${membershipId.isNotEmpty} scoped_profile=${activeProfileId.isNotEmpty}',
    );
    debugPrint(
      '[MOBILE_REQUESTS] scoped_profile=true scoped_member=true has_status_filter=${statusFilter != null && statusFilter.trim().isNotEmpty}',
    );
    try {
      return await _fetchScanRequests(limit: limit, query: query);
    } on RequestPermissionException catch (e) {
      final msg = e.toString().toLowerCase();
      if (!msg.contains('permission') && !msg.contains('unavailable')) rethrow;

      // Employee scope is strictly self. If the primary
      // business_profile+target_member query is rejected, retry ONCE with
      // target_member only. Never drop target_member — a workspace-wide
      // fallback would return other members' requests to an employee.
      debugPrint('[SCAN_REQUESTS] fallback=target_member_only');
      final targetOnly = <String, dynamic>{
        'filter[target_member][_eq]': membershipId,
        if (statusFilter != null && statusFilter.trim().isNotEmpty)
          'filter[status][_eq]': statusFilter.trim(),
      };
      return _fetchScanRequests(
        limit: limit,
        query: targetOnly,
        includeCancelled: true,
      );
    }
  }

  Future<List<RequestItem>> fetchHrRequests({
    int limit = 100,
    String? statusFilter,
  }) async {
    final workspace = await OrganizationService.instance
        .fetchActiveWorkspaceContext();
    if (workspace == null) return const [];
    final activeProfileId = workspace.businessProfileId.trim();
    if (activeProfileId.isEmpty) return const [];

    final query = <String, dynamic>{
      'filter[business_profile][_eq]': activeProfileId,
    };
    if (statusFilter != null && statusFilter.trim().isNotEmpty) {
      query['filter[status][_eq]'] = statusFilter.trim();
    }
    return _fetchScanRequests(
      limit: limit,
      query: query,
      includeCancelled: true,
    );
  }

  Future<List<RequestItem>> fetchManagerRequests({
    int limit = 50,
    String? statusFilter,
  }) async {
    final workspace = await OrganizationService.instance
        .fetchActiveWorkspaceContext();
    if (workspace == null) return const [];
    final activeProfileId = workspace.businessProfileId.trim();
    if (activeProfileId.isEmpty) return const [];
    final departmentId = workspace.departmentId?.trim() ?? '';
    final requestedByUserId = Session.instance.userId?.trim() ?? '';
    final membershipId = workspace.membershipId.trim();

    final query = <String, dynamic>{
      'filter[business_profile][_eq]': activeProfileId,
    };
    var scopeIndex = 0;
    if (departmentId.isNotEmpty) {
      query['filter[_or][$scopeIndex][department][_eq]'] = departmentId;
      scopeIndex++;
    }
    if (requestedByUserId.isNotEmpty) {
      query['filter[_or][$scopeIndex][requested_by_user][_eq]'] =
          requestedByUserId;
      scopeIndex++;
    }
    if (membershipId.isNotEmpty) {
      query['filter[_or][$scopeIndex][target_member][_eq]'] = membershipId;
    }
    if (statusFilter != null && statusFilter.trim().isNotEmpty) {
      query['filter[status][_eq]'] = statusFilter.trim();
    }
    return _fetchScanRequests(
      limit: limit,
      query: query,
      includeCancelled: true,
    );
  }

  Future<ScanRequestFieldSupport> fetchScanRequestFieldSupport({
    bool forceRefresh = false,
  }) async {
    final workspaceSignature = OrganizationService.instance.workspaceSignature;
    if (!forceRefresh &&
        _cachedFieldSupport != null &&
        _cachedFieldSupportWorkspaceSignature == workspaceSignature) {
      return _cachedFieldSupport!;
    }

    final requiredSupport = await _probeFieldSupport(
      collection: 'scan_requests',
      field: 'required_min_readiness',
    );
    final noteSupport = await _probeFieldSupport(
      collection: 'scan_requests',
      field: 'note',
    );
    final notesSupport = noteSupport == RequestFieldAvailability.supported
        ? RequestFieldAvailability.unsupported
        : await _probeFieldSupport(collection: 'scan_requests', field: 'notes');

    final noteFieldName = noteSupport == RequestFieldAvailability.supported
        ? 'note'
        : notesSupport == RequestFieldAvailability.supported
        ? 'notes'
        : null;
    final noteAvailability = noteSupport == RequestFieldAvailability.supported
        ? noteSupport
        : notesSupport;

    final support = ScanRequestFieldSupport(
      requiredMinReadiness: requiredSupport,
      note: noteAvailability,
      noteFieldName: noteFieldName,
    );
    _cachedFieldSupport = support;
    _cachedFieldSupportWorkspaceSignature = workspaceSignature;
    debugPrint(
      '[SCAN_REQUESTS] field_support required_min_readiness=${support.requiredMinReadiness.name} note=${support.note.name} note_field=${support.noteFieldName}',
    );
    return support;
  }

  Future<List<RequestItem>> fetchOwnerRequests({
    int limit = 100,
    String? statusFilter,
  }) async {
    final workspace = await OrganizationService.instance
        .fetchActiveWorkspaceContext();
    if (workspace == null) return const [];
    final activeProfileId = workspace.businessProfileId.trim();
    if (activeProfileId.isEmpty) return const [];

    final query = <String, dynamic>{
      'filter[business_profile][_eq]': activeProfileId,
    };
    if (statusFilter != null && statusFilter.trim().isNotEmpty) {
      query['filter[status][_eq]'] = statusFilter.trim();
    }
    return _fetchScanRequests(limit: limit, query: query);
  }

  Future<void> createHrScanRequest({
    required String businessProfileId,
    required String targetMemberId,
    DateTime? dueAt,
  }) async {
    await createPersonalScanRequest(
      businessProfileId: businessProfileId,
      targetMemberId: targetMemberId,
      dueAt: dueAt,
    );
  }

  Future<void> createManagerScanRequest({
    required String businessProfileId,
    required String targetMemberId,
    DateTime? dueAt,
  }) async {
    await createPersonalScanRequest(
      businessProfileId: businessProfileId,
      targetMemberId: targetMemberId,
      dueAt: dueAt,
    );
  }

  Future<void> createOwnerScanRequest({
    required String businessProfileId,
    required String targetMemberId,
    DateTime? dueAt,
  }) async {
    await createPersonalScanRequest(
      businessProfileId: businessProfileId,
      targetMemberId: targetMemberId,
      dueAt: dueAt,
    );
  }

  Future<RequestItem?> createPersonalScanRequest({
    required String businessProfileId,
    required String targetMemberId,
    DateTime? dueAt,
  }) async {
    final normalizedBusinessProfileId = businessProfileId.trim();
    final normalizedTargetMemberId = targetMemberId.trim();
    if (normalizedBusinessProfileId.isEmpty) {
      throw const RequestCreateException(
        'Workspace context is unavailable right now.',
      );
    }
    if (normalizedTargetMemberId.isEmpty) {
      throw const RequestCreateException(
        'Select a valid member before sending the request.',
      );
    }

    final payload = <String, dynamic>{
      'target_member_id': normalizedTargetMemberId,
      'request_type': 'manual',
      if (dueAt != null) 'due_at': dueAt.toUtc().toIso8601String(),
    };

    try {
      await _logRequest(
        method: 'POST',
        path: '/wellar/scan-requests',
        payload: payload,
      );
      final response = await _client.post(
        '/wellar/scan-requests',
        data: payload,
      );
      await _logResponse(
        method: 'POST',
        path: '/wellar/scan-requests',
        status: response.statusCode,
        body: response.data,
      );
      final createdRequest = _parseCreatedScanRequest(response.data);
      final createdRequestId = createdRequest?.id.trim() ?? '';
      final hasBusinessProfile =
          createdRequest?.businessProfileId?.trim().isNotEmpty == true;
      final hasTargetMember =
          createdRequest?.requestedForId?.trim().isNotEmpty == true;
      debugPrint(
        '[SCAN_REQUEST_CREATE_RESULT] has_request_id=${createdRequestId.isNotEmpty} has_business_profile=$hasBusinessProfile has_target_member=$hasTargetMember status=${response.statusCode ?? 0}',
      );
      debugPrint(
        '[SCAN_REQUEST_POST_VERIFY] request_id_present=${createdRequestId.isNotEmpty} readable_after_create=${createdRequest != null} active_profile_match=${createdRequest?.businessProfileId?.trim() == normalizedBusinessProfileId}',
      );
      debugPrint('[SCAN_REQUEST_CREATED] route=wellar_endpoint status=${response.statusCode}');
      return createdRequest;
    } on DioException catch (e, st) {
      final status = e.response?.statusCode ?? 0;
      debugPrint(
        '[SCAN_REQUEST_CREATE_FAILED] method=POST endpoint=/wellar/scan-requests status=$status has_target_membership=${normalizedTargetMemberId.isNotEmpty} has_business_profile=${normalizedBusinessProfileId.isNotEmpty} error_code=${_failureCodeForStatus(status)} safe_message=${_extractMessage(e)}',
      );
      await _logError(
        method: 'POST',
        path: '/wellar/scan-requests',
        e: e,
        query: {'payload_keys': payload.keys.toList()},
        stackTrace: st,
      );
      _throwCreateRequestException(e);
    }
  }

  Future<RequestItem?> fetchRequestById(String requestId) async {
    final id = requestId.trim();
    if (id.isEmpty) return null;
    final startRevision = OrganizationService.instance.workspaceRevision;
    final startSignature = OrganizationService.instance.workspaceSignature;
    try {
      final response = await _getScanRequestByIdWithFallback(id);
      await _logResponse(
        method: 'GET',
        path: '/items/scan_requests/$id',
        status: response.statusCode,
        body: response.data,
      );
      if (_isWorkspaceStale(startRevision, startSignature)) {
        _logStaleResult();
        return null;
      }
      final data = response.data['data'];
      if (data is Map<String, dynamic>) {
        final items = await _hydrateScanRequests([data]);
        if (_isWorkspaceStale(startRevision, startSignature)) {
          _logStaleResult();
          return null;
        }
        return items.isEmpty ? RequestItem.fromJson(data) : items.first;
      }
      return null;
    } on DioException catch (e, st) {
      if (e.response?.statusCode == 404) return null;
      await _logError(
        method: 'GET',
        path: '/items/scan_requests/$id',
        e: e,
        stackTrace: st,
      );
      return null;
    }
  }

  Future<Map<String, dynamic>?> fetchRequestDetailsRaw({
    required String requestId,
  }) async {
    final item = await fetchRequestById(requestId);
    if (item == null) return null;
    return {
      'id': item.id,
      'status': item.responseStatus,
      'request_type': item.requestType,
      'required_min_readiness': item.requiredMinReadiness,
      'completed_scan': item.scanId,
      'requested_by_user': {
        'id': item.requestedByUserId,
        'email': item.requestedByUserEmail,
        'first_name': item.requestedByUserName,
      },
      'target_member': {
        'id': item.requestedForId,
        'member_role': item.requestedForRole,
        'user': {
          'id': item.requestedForUserId,
          'email': item.requestedForEmail,
          'first_name': item.requestedForName,
        },
      },
      'department': {'id': item.departmentId, 'name': item.departmentName},
      'requested_at': item.timestamp?.toIso8601String(),
      'due_at': item.dueAt?.toIso8601String(),
    };
  }

  Future<RequestCreateResult?> createRequest({
    required String recipientEmail,
    String requestType = 'scan_request',
    String? requiredState,
    String? memberRole,
    String? scanId,
    Map<String, dynamic>? metadata,
  }) async {
    throw const RequestCreateException(
      'Mobile request creation is disabled. Use backend workflow for scan_requests assignment.',
    );
  }

  Future<void> updateRequestStatus({
    required String requestId,
    required String responseStatus,
    String? scanId,
    String? workflowStatus,
  }) async {
    final payload = <String, dynamic>{
      'status': workflowStatus?.trim().isNotEmpty == true
          ? workflowStatus!.trim()
          : responseStatus.trim(),
      if (scanId != null && scanId.trim().isNotEmpty)
        'wellness_scan': scanId.trim(),
      if ((workflowStatus?.trim().toLowerCase() == 'completed') ||
          (responseStatus.trim().toLowerCase() == 'completed'))
        'completed_at': DateTime.now().toUtc().toIso8601String(),
      if (scanId != null && scanId.trim().isNotEmpty)
        'completed_scan': scanId.trim(),
    };

    try {
      await _logRequest(
        method: 'PATCH',
        path: '/items/scan_requests/$requestId',
        payload: payload,
      );
      debugPrint(
        '[REQUEST_SCAN_FLOW] completed_scan update payload_keys=${payload.keys.toList()} has_scan_id=${scanId?.trim().isNotEmpty == true}',
      );
      await _client.patch('/items/scan_requests/$requestId', data: payload);
      await _logResponse(
        method: 'PATCH',
        path: '/items/scan_requests/$requestId',
        status: 200,
      );
    } on DioException catch (e, st) {
      await _logError(
        method: 'PATCH',
        path: '/items/scan_requests/$requestId',
        e: e,
        stackTrace: st,
      );
      final status = e.response?.statusCode ?? 0;
      if (status == 401 || status == 403) {
        throw const RequestPermissionException(
          'Permission denied to update request status. Backend workflow will continue.',
        );
      }
      rethrow;
    }
  }

  Future<RequestItem?> cancelScanRequest({required String requestId}) async {
    final userId = Session.instance.userId?.trim() ?? '';
    final accessToken = Session.instance.accessToken?.trim() ?? '';
    final id = requestId.trim();
    if (userId.isEmpty || accessToken.isEmpty) {
      throw const RequestCancellationException(
        RequestCancellationFailure.unauthenticated,
        'Session expired. Please login.',
      );
    }
    if (id.isEmpty) {
      throw const RequestCancellationException(
        RequestCancellationFailure.conflict,
        'Request id is missing.',
      );
    }

    final path = '/wellar/scan-requests/$id/cancel';
    try {
      await _logRequest(method: 'POST', path: path);
      final response = await _client.post(path);
      await _logResponse(
        method: 'POST',
        path: path,
        status: response.statusCode,
        body: response.data,
      );
      final data = response.data is Map<String, dynamic>
          ? response.data['data']
          : null;
      if (data is Map<String, dynamic>) {
        return RequestItem.fromJson(data);
      }
      return await fetchRequestById(id);
    } on DioException catch (e, st) {
      await _logError(method: 'POST', path: path, e: e, stackTrace: st);
      final status = e.response?.statusCode ?? 0;
      if (status == 401) {
        throw const RequestCancellationException(
          RequestCancellationFailure.unauthenticated,
          'Session expired. Please login.',
        );
      }
      if (status == 403) {
        throw const RequestCancellationException(
          RequestCancellationFailure.forbidden,
          'You are not allowed to cancel this request.',
        );
      }
      if (status == 404) {
        throw const RequestCancellationException(
          RequestCancellationFailure.notFound,
          'This request could not be found.',
        );
      }
      if (status == 409) {
        throw const RequestCancellationException(
          RequestCancellationFailure.conflict,
          'This request can no longer be cancelled.',
        );
      }
      if (status == 0 ||
          e.type == DioExceptionType.connectionError ||
          e.type == DioExceptionType.connectionTimeout ||
          e.type == DioExceptionType.receiveTimeout ||
          e.type == DioExceptionType.sendTimeout) {
        throw const RequestCancellationException(
          RequestCancellationFailure.network,
          'Network error. Please try again.',
        );
      }
      throw const RequestCancellationException(
        RequestCancellationFailure.unknown,
        'Unable to cancel request right now.',
      );
    }
  }

  Future<List<RequestItem>> _fetchScanRequests({
    required int limit,
    required Map<String, dynamic> query,
    bool includeCancelled = false,
  }) async {
    final startRevision = OrganizationService.instance.workspaceRevision;
    final startSignature = OrganizationService.instance.workspaceSignature;
    final qp = {
      'limit': limit,
      'sort': '-requested_at',
      'fields': _scanRequestFieldAttempts.first['fields'],
      ...query,
    };
    debugPrint(
      '[SCAN_REQUESTS_SCHEMA_SAFE_FIELDS] fields=$_scanRequestSafeFields sort=${qp['sort']}',
    );
    try {
      final response = await _getScanRequestsWithFallback(
        qp,
        _scanRequestFieldAttempts,
      );
      final data = response.data['data'];
      if (data is! List) return const [];
      final rows = data
          .whereType<Map<String, dynamic>>()
          .where((row) => includeCancelled || !_isCancelled(row))
          .toList();
      List<RequestItem> list;
      try {
        list = await _hydrateScanRequests(rows);
      } catch (e) {
        debugPrint('[SCAN_REQUESTS_PARSE_ERROR] $e');
        throw const RequestPermissionException(
          'Unable to load scan requests. Try again.',
        );
      }
      if (_isWorkspaceStale(startRevision, startSignature)) {
        _logStaleResult();
        return const [];
      }
      final workspace = await OrganizationService.instance
          .fetchActiveWorkspaceContext();
      if (_isWorkspaceStale(startRevision, startSignature)) {
        _logStaleResult();
        return const [];
      }
      debugPrint(
        '[SCAN_REQUESTS_DEBUG] endpoint=/items/scan_requests fields_present=${qp['fields'] != null} filter_keys=${query.keys.toList()} status=${response.statusCode} body_count=${list.length} effectiveRole=${workspace?.finalEffectiveRole} scoped_profile=${workspace?.businessProfileId.trim().isNotEmpty == true}',
      );
      debugPrint(
        '[SCAN_REQUESTS_QUERY_SUCCESS] status=${response.statusCode} count=${list.length} sort=${qp['sort']} fields=${qp['fields']}',
      );
      debugPrint(
        '[MOBILE_REQUESTS] status=${response.statusCode} body_count=${list.length}',
      );
      if (list.isEmpty) {
        debugPrint('[MOBILE_REQUESTS] empty');
      } else {
        debugPrint('[MOBILE_REQUESTS] success');
      }
      debugPrint('[SCAN_REQUESTS] response count=${list.length}');
      return list;
    } on DioException catch (e, st) {
      await _logError(
        method: 'GET',
        path: '/items/scan_requests',
        e: e,
        query: qp,
        stackTrace: st,
      );
      debugPrint(
        '[SCAN_REQUESTS_QUERY_FAILED] status=${e.response?.statusCode} query_keys=${qp.keys.toList()} error_type=${e.type}',
      );
      final status = e.response?.statusCode ?? 0;
      if (status == 403) {
        debugPrint('[MOBILE_REQUESTS] error=403');
        throw const RequestPermissionException(
          'Assigned requests are unavailable right now.',
        );
      }
      if (status == 401) {
        debugPrint('[MOBILE_REQUESTS] error=401');
        throw const RequestPermissionException(
          'Session expired. Please login.',
        );
      }
      if (status >= 500 ||
          e.type == DioExceptionType.connectionError ||
          e.type == DioExceptionType.connectionTimeout ||
          e.type == DioExceptionType.receiveTimeout ||
          e.type == DioExceptionType.sendTimeout) {
        throw const RequestPermissionException(
          'Unable to load scan requests. Try again.',
        );
      }
      if (status == 400 || status == 404 || status == 422) return const [];
      throw RequestPermissionException(_extractMessage(e));
    }
  }

  String _extractMessage(DioException e) {
    final data = e.response?.data;
    if (data is Map) {
      final errors = data['errors'];
      if (errors is List && errors.isNotEmpty) {
        final first = errors.first;
        if (first is Map && first['message'] != null) {
          return first['message'].toString();
        }
      }
      if (data['message'] != null) return data['message'].toString();
    }
    return e.message ?? 'Request failed';
  }

  RequestItem? _parseCreatedScanRequest(dynamic rawResponse) {
    Map<String, dynamic>? data;
    if (rawResponse is Map<String, dynamic>) {
      final nestedData = rawResponse['data'];
      if (nestedData is Map<String, dynamic>) {
        data = Map<String, dynamic>.from(nestedData);
      } else if (nestedData is Map) {
        data = Map<String, dynamic>.from(nestedData.cast<String, dynamic>());
      } else {
        data = Map<String, dynamic>.from(rawResponse);
      }
    }
    if (data == null) return null;

    final normalized = Map<String, dynamic>.from(data);
    final targetMemberId = _extractId(
      normalized['target_member_id'] ?? normalized['target_member'],
    );
    if (normalized['target_member'] == null && targetMemberId.isNotEmpty) {
      normalized['target_member'] = {'id': targetMemberId};
    }

    final requestedByUserId = _extractId(
      normalized['requested_by_user_id'] ?? normalized['requested_by_user'],
    );
    if (normalized['requested_by_user'] == null &&
        requestedByUserId.isNotEmpty) {
      normalized['requested_by_user'] = {'id': requestedByUserId};
    }

    final businessProfileId = _extractId(
      normalized['business_profile_id'] ?? normalized['business_profile'],
    );
    if (normalized['business_profile'] == null &&
        businessProfileId.isNotEmpty) {
      normalized['business_profile'] = {'id': businessProfileId};
    }

    final departmentId = _extractId(
      normalized['department_id'] ?? normalized['department'],
    );
    if (normalized['department'] == null && departmentId.isNotEmpty) {
      normalized['department'] = {'id': departmentId};
    }

    final completedScanId = _extractId(
      normalized['completed_scan_id'] ?? normalized['completed_scan'],
    );
    if (normalized['completed_scan'] == null && completedScanId.isNotEmpty) {
      normalized['completed_scan'] = {'id': completedScanId};
    }

    return RequestItem.fromJson(normalized);
  }

  Future<Response<dynamic>> _getScanRequestsWithFallback(
    Map<String, dynamic> query,
    List<Map<String, dynamic>> attempts,
  ) async {
    DioException? lastError;
    for (final attempt in attempts) {
      final currentQuery = Map<String, dynamic>.from(query)
        ..remove('sort')
        ..addAll(attempt);
      final fields = currentQuery['fields'];
      try {
        await _logRequest(
          method: 'GET',
          path: '/items/scan_requests',
          query: currentQuery,
        );
        if (fields != (query['fields']?.toString() ?? '')) {
          debugPrint(
            '[SCAN_REQUESTS] trying_query fields=$fields sort=${currentQuery['sort']}',
          );
        }
        final response = await _client.get(
          '/items/scan_requests',
          queryParameters: currentQuery,
        );
        await _logResponse(
          method: 'GET',
          path: '/items/scan_requests',
          status: response.statusCode,
          body: response.data,
        );
        return response;
      } on DioException catch (e, st) {
        lastError = e;
        await _logError(
          method: 'GET',
          path: '/items/scan_requests',
          e: e,
          query: currentQuery,
          stackTrace: st,
        );
        final status = e.response?.statusCode ?? 0;
        debugPrint(
          '[SCAN_REQUESTS] fields_failed status=$status fields_present=${fields != null} error_type=${e.type}',
        );
        if (status != 400 && status != 403 && status != 422) rethrow;
      }
    }
    if (lastError != null) throw lastError;
    throw DioException(
      requestOptions: RequestOptions(path: '/items/scan_requests'),
      error: 'Unable to load scan requests.',
    );
  }

  Future<List<RequestItem>> _hydrateScanRequests(
    List<Map<String, dynamic>> rows,
  ) async {
    if (rows.isEmpty) return const [];

    final memberIds = rows
        .map((row) => _extractId(row['target_member']))
        .where((value) => value.isNotEmpty)
        .toSet()
        .toList();

    final memberRowsById = await _fetchMembersByIds(memberIds);

    final items = <RequestItem>[];
    for (final row in rows) {
      final baseItem = RequestItem.fromJson(row);
      final targetMemberId = _extractId(row['target_member']);
      final targetMemberRow = targetMemberId.isNotEmpty
          ? memberRowsById[targetMemberId]
          : null;
      final targetDepartment = targetMemberRow?['department'];
      final targetDepartmentName = targetDepartment is Map
          ? targetDepartment['name']?.toString()
          : targetDepartment?.toString();
      final targetIdentity = targetMemberRow == null
          ? null
          : MemberIdentityService.instance.resolveFromUserRelation(
              targetMemberRow['user'],
              context: 'scan_requests_enrich',
              memberId: targetMemberId,
              role: targetMemberRow['member_role']?.toString(),
              departmentRaw: targetDepartment,
              employeeCode: targetMemberRow['employee_code']?.toString(),
            );
      final requesterId = _extractId(row['requested_by_user']);
      final requesterIdentity = MemberIdentityService.instance
          .resolveFromUserRelation(
            row['requested_by_user'],
            context: 'scan_requests_requester',
            memberId: requesterId.isEmpty ? baseItem.id : requesterId,
            role: 'requester',
          );

      items.add(
        baseItem.copyWith(
          requestedForUserId: targetIdentity?.userId,
          requestedForName: targetIdentity?.name,
          requestedForEmail: targetIdentity?.email,
          requestedForRole: targetMemberRow?['member_role']?.toString(),
          requestedByUserName:
              requesterIdentity.name ==
                  MemberIdentityService.memberProfileNeedsLinkingLabel
              ? baseItem.requestedByUserName
              : requesterIdentity.name,
          requestedByUserEmail:
              requesterIdentity.email ?? baseItem.requestedByUserEmail,
          departmentName: targetDepartmentName?.trim().isNotEmpty == true
              ? targetDepartmentName!.trim()
              : baseItem.departmentName,
          completedAt: _tryDate(row['completed_at']) ?? baseItem.completedAt,
        ),
      );
    }
    return items;
  }

  Future<Response<dynamic>> _getScanRequestByIdWithFallback(String id) async {
    DioException? lastError;
    for (final fields in _scanRequestDetailFieldCandidates) {
      final currentQuery = {'fields': fields};
      await _logRequest(
        method: 'GET',
        path: '/items/scan_requests/$id',
        query: currentQuery,
      );
      try {
        final response = await _client.get(
          '/items/scan_requests/$id',
          queryParameters: currentQuery,
        );
        await _logResponse(
          method: 'GET',
          path: '/items/scan_requests/$id',
          status: response.statusCode,
          body: response.data,
        );
        return response;
      } on DioException catch (e, st) {
        lastError = e;
        await _logError(
          method: 'GET',
          path: '/items/scan_requests/$id',
          e: e,
          query: currentQuery,
          stackTrace: st,
        );
        final status = e.response?.statusCode ?? 0;
        debugPrint(
          '[SCAN_REQUESTS] request_by_id_fields_failed status=$status fields_present=${fields.toString().isNotEmpty} error_type=${e.type}',
        );
        if (status != 400 && status != 403 && status != 422) rethrow;
      }
    }
    if (lastError != null) throw lastError;
    throw DioException(
      requestOptions: RequestOptions(path: '/items/scan_requests/$id'),
      error: 'Unable to load request details.',
    );
  }

  Future<RequestFieldAvailability> _probeFieldSupport({
    required String collection,
    required String field,
  }) async {
    try {
      final response = await _client.get('/fields/$collection/$field');
      return response.statusCode == 200
          ? RequestFieldAvailability.supported
          : RequestFieldAvailability.unknown;
    } on DioException catch (e) {
      final status = e.response?.statusCode ?? 0;
      if (status == 404) return RequestFieldAvailability.unsupported;
      if (status == 401 || status == 403 || status == 405) {
        return RequestFieldAvailability.unknown;
      }
      return RequestFieldAvailability.unknown;
    } catch (_) {
      return RequestFieldAvailability.unknown;
    }
  }

  bool _isUnsupportedOptionalFieldError(
    DioException error,
    List<String> optionalFieldKeys,
  ) {
    final body = error.response?.data;
    final message = body.toString().toLowerCase();
    if (message.contains('invalid payload') || message.contains('field')) {
      for (final key in optionalFieldKeys) {
        if (message.contains(key.toLowerCase())) return true;
      }
    }
    return false;
  }

  Never _throwCreateRequestException(DioException error) {
    final status = error.response?.statusCode ?? 0;
    if (status == 401) {
      throw const RequestCreateException('Session expired. Please login.');
    }
    if (status == 409) {
      throw const RequestCreateException(
        'This member already has an open scan request.',
      );
    }
    if (status == 403) {
      throw const RequestCreateException(
        'Unable to send scan request right now.',
      );
    }
    throw const RequestCreateException(
      'Unable to send scan request right now.',
    );
  }

  Future<Map<String, Map<String, dynamic>>> _fetchMembersByIds(
    List<String> memberIds,
  ) async {
    final startRevision = OrganizationService.instance.workspaceRevision;
    final startSignature = OrganizationService.instance.workspaceSignature;
    final ids = memberIds
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty)
        .toSet()
        .toList();
    if (ids.isEmpty) return const {};

    final workspace = await OrganizationService.instance
        .fetchActiveWorkspaceContext();
    final businessProfileId = workspace?.businessProfileId.trim() ?? '';
    if (businessProfileId.isNotEmpty) {
      try {
        final startRevision = OrganizationService.instance.workspaceRevision;
        final startSignature = OrganizationService.instance.workspaceSignature;
        final rows = await MemberIdentityService.instance
            .fetchBusinessProfileMembers(
              screen: 'RequestDetails',
              businessProfileId: businessProfileId,
              limit: ids.length.clamp(1, 500),
              memberIds: ids,
            );
        if (_isWorkspaceStale(startRevision, startSignature)) {
          _logStaleResult();
          return const {};
        }
        return {
          for (final row in rows)
            if ((row['id']?.toString().trim() ?? '').isNotEmpty)
              row['id'].toString().trim(): row,
        };
      } on DioException catch (e) {
        debugPrint(
          '[MemberDisplay] expanded member lookup failed status=${e.response?.statusCode} error_type=${e.type} required_permissions=business_profile_members.read departments.read member_identity_endpoint',
        );
        return const {};
      }
    }

    final query = <String, dynamic>{
      'limit': ids.length.clamp(1, 500),
      'fields': MemberIdentityService.memberFields,
      'filter[id][_in]': ids.join(','),
    };

    try {
      await _logRequest(
        method: 'GET',
        path: '/items/business_profile_members',
        query: query,
      );
      final response = await _client.get(
        '/items/business_profile_members',
        queryParameters: query,
      );
      await _logResponse(
        method: 'GET',
        path: '/items/business_profile_members',
        status: response.statusCode,
        body: response.data,
      );
      final data = response.data['data'];
      if (data is! List) return const {};
      if (_isWorkspaceStale(startRevision, startSignature)) {
        _logStaleResult();
        return const {};
      }
      return {
        for (final row in data.whereType<Map<String, dynamic>>())
          if ((row['id']?.toString().trim() ?? '').isNotEmpty)
            row['id'].toString().trim(): row,
      };
    } on DioException catch (e, st) {
      await _logError(
        method: 'GET',
        path: '/items/business_profile_members',
        e: e,
        query: query,
        stackTrace: st,
      );
      debugPrint(
        '[MemberDisplay] member relation lookup failed status=${e.response?.statusCode} error_type=${e.type} required_permissions=business_profile_members.read departments.read member_identity_endpoint',
      );
      return const {};
    }
  }

  bool _isCancelled(Map<String, dynamic> row) {
    final cancelled = row['cancelled'];
    if (cancelled is bool) return cancelled;
    final normalized = cancelled?.toString().trim().toLowerCase() ?? '';
    return normalized == 'true' || normalized == '1' || normalized == 'yes';
  }

  static const List<Map<String, dynamic>> _scanRequestFieldAttempts = [
    {'sort': '-requested_at', 'fields': _scanRequestSafeFields},
    {
      'sort': '-requested_at',
      'fields':
          'id,status,request_type,business_profile,requested_by_user,requested_by_user.id,requested_by_user.email,requested_by_user.first_name,requested_by_user.last_name,target_member,department,due_at,requested_at,completed_scan,completed_at,cancelled',
    },
    {
      'sort': '-requested_at',
      'fields':
          'id,status,request_type,business_profile,requested_by_user,requested_by_user.id,requested_by_user.email,requested_by_user.first_name,requested_by_user.last_name,target_member,department,due_at,requested_at,cancelled',
    },
    {'sort': '-requested_at', 'fields': 'id,status,business_profile'},
  ];

  static const List<String> _scanRequestDetailFieldCandidates = [
    _scanRequestSafeFields,
    'id,status,request_type,business_profile,requested_by_user,requested_by_user.id,requested_by_user.email,requested_by_user.first_name,requested_by_user.last_name,target_member,department,due_at,requested_at,completed_scan,completed_at',
    'id,status,request_type,business_profile,requested_by_user,requested_by_user.id,requested_by_user.email,requested_by_user.first_name,requested_by_user.last_name,target_member,department,requested_at,cancelled',
  ];

  String _extractId(dynamic value) {
    if (value is Map) {
      return value['id']?.toString().trim() ?? '';
    }
    return value?.toString().trim() ?? '';
  }

  DateTime? _tryDate(dynamic value) {
    if (value == null) return null;
    if (value is DateTime) return value;
    final text = value.toString().trim();
    if (text.isEmpty) return null;
    return DateTime.tryParse(text);
  }

  Future<void> _logRequest({
    required String method,
    required String path,
    Map<String, dynamic>? query,
    Map<String, dynamic>? payload,
  }) async {
    final workspace = await OrganizationService.instance
        .fetchActiveWorkspaceContext();
    final trace = OrganizationService.instance.activeSwitchTrace ?? 'none';
    final fields = query?['fields'];
    final logPath = _redactedLogPath(path);
    final scopedProfile =
        workspace?.businessProfileId.trim().isNotEmpty == true;
    final scopedDepartment = workspace?.departmentId?.trim().isNotEmpty == true;
    final hasActiveMember = workspace?.membershipId.trim().isNotEmpty == true;
    final feature = _scopedFeature(path);
    final operation = _scopedOperation(method, path);
    final filterSummary = _scopedFilterSummary(query);
    debugPrint(
      '[REQUESTS_API_REQ] method=$method path=$logPath has_query=${query != null && query.isNotEmpty} fields_present=${fields != null} payload_keys=${payload?.keys.toList()} effectiveRole=${workspace?.finalEffectiveRole} directusRole=${workspace?.directusRoleName} membershipRole=${workspace?.memberRole} scoped_profile=$scopedProfile scoped_department=$scopedDepartment',
    );
    debugPrint(
      '[API_REQ] method=$method path=$logPath query_keys=${query?.keys.toList()} payload_keys=${payload?.keys.toList()} has_active_member=$hasActiveMember active_member_role=${workspace?.memberRole} directus_role=${workspace?.directusRoleName} effective_role=${workspace?.finalEffectiveRole} scoped_profile=$scopedProfile',
    );
    debugPrint(
      '[SCOPED_DATA_REQUEST] feature=$feature operation=$operation method=$method endpoint_or_collection=$logPath membership_id=${workspace?.membershipId.trim() ?? ''} business_profile=${workspace?.businessProfileId.trim() ?? ''} department=${workspace?.departmentId?.trim() ?? ''} membership_role=${workspace?.memberRole ?? ''} context_source=${OrganizationService.instance.activeWorkspaceContextSource} workspace_revision=${OrganizationService.instance.workspaceRevision} filter_summary=$filterSummary started=true trace=$trace',
    );
  }

  Future<void> _logResponse({
    required String method,
    required String path,
    required int? status,
    dynamic body,
  }) async {
    final workspace = await OrganizationService.instance
        .fetchActiveWorkspaceContext();
    final trace = OrganizationService.instance.activeSwitchTrace ?? 'none';
    final logPath = _redactedLogPath(path);
    final scopedProfile =
        workspace?.businessProfileId.trim().isNotEmpty == true;
    final scopedDepartment = workspace?.departmentId?.trim().isNotEmpty == true;
    final hasActiveMember = workspace?.membershipId.trim().isNotEmpty == true;
    final feature = _scopedFeature(path);
    final operation = _scopedOperation(method, path);
    final resultCount = _responseCount(body);
    final ids = _responseIds(body);
    debugPrint(
      '[REQUESTS_API_RES] method=$method path=$logPath status=$status body_type=${body.runtimeType} effectiveRole=${workspace?.finalEffectiveRole} directusRole=${workspace?.directusRoleName} membershipRole=${workspace?.memberRole} scoped_profile=$scopedProfile scoped_department=$scopedDepartment',
    );
    debugPrint(
      '[API_RES] method=$method path=$logPath status=$status body_type=${body.runtimeType} has_active_member=$hasActiveMember active_member_role=${workspace?.memberRole} directus_role=${workspace?.directusRoleName} effective_role=${workspace?.finalEffectiveRole} scoped_profile=$scopedProfile',
    );
    debugPrint(
      '[SCOPED_DATA_RESPONSE] feature=$feature operation=$operation http_status=$status result_count=$resultCount duration_ms=0 membership_id=${workspace?.membershipId.trim() ?? ''} business_profile=${workspace?.businessProfileId.trim() ?? ''} workspace_revision_before=${OrganizationService.instance.workspaceRevision} workspace_revision_after=${OrganizationService.instance.workspaceRevision} context_unchanged=true returned_business_profile_ids=${ids.businessProfileIds} returned_membership_ids=${ids.membershipIds} empty_result=${resultCount == 0} trace=$trace',
    );
  }

  Future<void> _logError({
    required String method,
    required String path,
    required DioException e,
    Map<String, dynamic>? query,
    StackTrace? stackTrace,
  }) async {
    final workspace = await OrganizationService.instance
        .fetchActiveWorkspaceContext();
    final trace = OrganizationService.instance.activeSwitchTrace ?? 'none';
    final selectedShell = _shellName(workspace?.finalEffectiveRole);
    final logPath = _redactedLogPath(path);
    final scopedProfile =
        workspace?.businessProfileId.trim().isNotEmpty == true;
    final scopedDepartment = workspace?.departmentId?.trim().isNotEmpty == true;
    final hasActiveMember = workspace?.membershipId.trim().isNotEmpty == true;
    final feature = _scopedFeature(path);
    final operation = _scopedOperation(method, path);
    final filterSummary = _scopedFilterSummary(query);
    final failureCode = _failureCodeForStatus(e.response?.statusCode ?? 0);
    debugPrint(
      '[REQUESTS_API_ERR] method=$method path=$logPath status=${e.response?.statusCode} error_type=${e.type} has_query=${query != null && query.isNotEmpty} query_keys=${query?.keys.toList()} stack_present=${stackTrace != null} effectiveRole=${workspace?.finalEffectiveRole} directusRole=${workspace?.directusRoleName} membershipRole=${workspace?.memberRole} scoped_profile=$scopedProfile scoped_department=$scopedDepartment',
    );
    debugPrint(
      '[API_ERR] method=$method path=$logPath query_keys=${query?.keys.toList()} status=${e.response?.statusCode} error_type=${e.type} has_active_member=$hasActiveMember active_member_role=${workspace?.memberRole} directus_role=${workspace?.directusRoleName} effective_role=${workspace?.finalEffectiveRole} selected_shell=$selectedShell scoped_profile=$scopedProfile',
    );
    debugPrint(
      '[SCOPED_DATA_ERROR] feature=$feature operation=$operation http_status=${e.response?.statusCode ?? 0} error_type=${e.type} failure_code=$failureCode duration_ms=0 membership_id=${workspace?.membershipId.trim() ?? ''} business_profile=${workspace?.businessProfileId.trim() ?? ''} membership_role=${workspace?.memberRole ?? ''} workspace_revision_before=${OrganizationService.instance.workspaceRevision} workspace_revision_after=${OrganizationService.instance.workspaceRevision} context_unchanged=true trace=$trace',
    );
    if (filterSummary.isNotEmpty) {
      debugPrint(
        '[SCOPED_DATA_REQUEST] feature=$feature operation=$operation method=$method endpoint_or_collection=$logPath membership_id=${workspace?.membershipId.trim() ?? ''} business_profile=${workspace?.businessProfileId.trim() ?? ''} department=${workspace?.departmentId?.trim() ?? ''} membership_role=${workspace?.memberRole ?? ''} context_source=${OrganizationService.instance.activeWorkspaceContextSource} workspace_revision=${OrganizationService.instance.workspaceRevision} filter_summary=$filterSummary started=false trace=$trace',
      );
    }
    if (path == '/items/scan_requests') {
      debugPrint(
        '[SCAN_REQUESTS_DEBUG] endpoint=$logPath query_keys=${query?.keys.toList()} status=${e.response?.statusCode} error_type=${e.type} has_active_member=$hasActiveMember activeMemberRole=${workspace?.memberRole} directusRole=${workspace?.directusRoleName} effectiveRole=${workspace?.finalEffectiveRole} scoped_profile=$scopedProfile',
      );
      if ((e.response?.statusCode ?? 0) == 403) {
        debugPrint(
          '[SCAN_REQUESTS_DEBUG] permission_hint collection=scan_requests requested_fields_present=${query?['fields'] != null} missing_permissions_candidates=scan_requests.read,business_profile_members.read,departments.read,member_identity_endpoint',
        );
      }
    }
  }

  String _redactedLogPath(String path) {
    if (!path.startsWith('/items/')) return path;
    final parts = path.split('/');
    if (parts.length <= 3) return path;
    return '${parts.take(3).join('/')}/:id';
  }

  String _shellName(String? role) {
    switch (role) {
      case 'employee':
        return 'EmployeeShell';
      case 'manager':
        return 'ManagerShell';
      case 'hr':
        return 'HrShell';
      case 'owner':
        return 'OwnerShell';
      default:
        return 'WorkspaceAccess';
    }
  }

  bool _isWorkspaceStale(int startRevision, String startSignature) {
    return OrganizationService.instance.workspaceRevision != startRevision ||
        OrganizationService.instance.workspaceSignature != startSignature;
  }

  void _logStaleResult() {
    debugPrint(
      '[WORKSPACE_GUARD] stale_result_ignored=true service=RequestService',
    );
  }

  String _scopedFeature(String path) {
    if (path.startsWith('/items/scan_requests')) return 'requests';
    return 'requests';
  }

  String _scopedOperation(String method, String path) {
    if (path.startsWith('/items/scan_requests')) {
      if (method.toUpperCase() == 'GET') return 'fetch_requests';
      if (method.toUpperCase() == 'POST') return 'create_request';
      return '${method.toLowerCase()}_scan_requests';
    }
    return method.toLowerCase();
  }

  String _scopedFilterSummary(Map<String, dynamic>? query) {
    if (query == null || query.isEmpty) return '';
    final entries = <String>[];
    for (final entry in query.entries) {
      final key = entry.key.toString();
      if (!key.startsWith('filter[') &&
          key != 'limit' &&
          key != 'sort' &&
          key != 'fields') {
        continue;
      }
      final value = entry.value?.toString() ?? '';
      entries.add('$key=$value');
    }
    return entries.join(';');
  }

  int _responseCount(dynamic body) {
    final data = body is Map ? body['data'] : null;
    if (data is List) return data.length;
    if (data is Map) return 1;
    return 0;
  }

  ({List<String> businessProfileIds, List<String> membershipIds}) _responseIds(
    dynamic body,
  ) {
    final data = body is Map ? body['data'] : null;
    final businessProfileIds = <String>{};
    final membershipIds = <String>{};
    if (data is List) {
      for (final row in data.whereType<Map>()) {
        final map = row.map((key, value) => MapEntry(key.toString(), value));
        final businessProfile = map['business_profile'];
        if (businessProfile is Map) {
          final id = businessProfile['id']?.toString().trim() ?? '';
          if (id.isNotEmpty) businessProfileIds.add(id);
        } else {
          final id = businessProfile?.toString().trim() ?? '';
          if (id.isNotEmpty) businessProfileIds.add(id);
        }
        final membership = map['target_member'];
        final membershipId = membership is Map
            ? membership['id']?.toString().trim() ?? ''
            : membership?.toString().trim() ?? '';
        if (membershipId.isNotEmpty) membershipIds.add(membershipId);
      }
    }
    return (
      businessProfileIds: businessProfileIds.toList(),
      membershipIds: membershipIds.toList(),
    );
  }

  String _failureCodeForStatus(int status) {
    if (status == 401) return 'scoped_data_401';
    if (status == 403) return 'scoped_data_403';
    if (status == 0) return 'scoped_data_network_error';
    if (status == 400 || status == 404 || status == 422)
      return 'scoped_data_parse_error';
    return 'scoped_data_network_error';
  }
}

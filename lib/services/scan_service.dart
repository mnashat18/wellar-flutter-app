import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';

import '../config/app_config.dart';
import '../models/scan_result.dart';
import '../models/history_entry.dart';
import '../state/session.dart';
import '../utils/video_compress.dart';
import 'directus_client.dart';
import 'organization_service.dart';

class UnauthenticatedException implements Exception {
  final String message;
  const UnauthenticatedException([this.message = 'Unauthenticated']);

  @override
  String toString() => message;
}

class PermissionDeniedException implements Exception {
  final String message;
  const PermissionDeniedException([this.message = 'Permission denied']);

  @override
  String toString() => message;
}

class ScanServiceException implements Exception {
  final String method;
  final String path;
  final int? statusCode;
  final dynamic responseBody;
  final String message;

  const ScanServiceException({
    required this.method,
    required this.path,
    required this.message,
    this.statusCode,
    this.responseBody,
  });

  bool get isPermissionFailure {
    if (statusCode == 401 || statusCode == 403) return true;
    final m = message.toLowerCase();
    return m.contains('permission') ||
        m.contains('forbidden') ||
        m.contains('not allowed');
  }

  bool get isMissingWorkspace {
    final m = message.toLowerCase();
    return m.contains('no active workspace') ||
        m.contains('no business profile') ||
        m.contains('workspace');
  }

  bool get isUploadFailure {
    if (path == '/files') return true;
    final m = message.toLowerCase();
    return m.contains('upload') ||
        m.contains('/files') ||
        m.contains('multipart');
  }

  @override
  String toString() {
    return '$method $path failed status=$statusCode '
        'message=$message body=$responseBody';
  }
}

class ProcessTriggerResponse {
  final int statusCode;
  final Map<String, dynamic> body;

  const ProcessTriggerResponse({required this.statusCode, required this.body});
}

class ScanResultLookup {
  final ScanResult? result;
  final int count;
  final String? firstResultId;

  const ScanResultLookup({
    required this.result,
    required this.count,
    this.firstResultId,
  });
}

const List<String> scanResultAssessmentFieldNames = <String>[
  'ai_model_version',
  'baseline_used',
];

class HomeData {
  final List<ScanResult> results;

  const HomeData({required this.results});

  bool get isEmpty => results.isEmpty;
  ScanResult? get latest => results.isNotEmpty ? results.first : null;
  List<ScanResult> get recent => results.take(3).toList();
  int get total => results.length;

  Map<String, int> get countsByState {
    final Map<String, int> counts = {
      'Stable': 0,
      'Low Focus': 0,
      'Elevated Fatigue': 0,
      'High Risk': 0,
    };

    for (final r in results) {
      final key = _normalizeState(r.overallState);
      counts[key] = (counts[key] ?? 0) + 1;
    }
    return counts;
  }

  String _normalizeState(String value) {
    final v = value.trim().toLowerCase();
    if (v == 'stable') return 'Stable';
    if (v == 'low focus' || v == 'low_focus') return 'Low Focus';
    if (v == 'elevated fatigue' || v == 'elevated_fatigue') {
      return 'Elevated Fatigue';
    }
    if (v == 'high risk' || v == 'high_risk') return 'High Risk';
    return value.isEmpty ? 'Stable' : value;
  }
}

class ScanService {
  ScanService._();
  static final ScanService instance = ScanService._();
  static const String aiServerProcessUrl = AppConfig.aiServerUrl;
  static const String aiEngineName = 'Conntinuity Intelligence Engine v1.2';
  String? _cachedScanResultsFields;
  static const Duration _videoUploadConnectTimeout = Duration(seconds: 45);
  static const Duration _videoUploadSendTimeout = Duration(minutes: 3);
  static const Duration _videoUploadReceiveTimeout = Duration(minutes: 3);
  static const int _maxVideoUploadBytes = 80 * 1024 * 1024;
  static const int _maxPreferredVideoUploadBytes = 5 * 1024 * 1024;

  // ================================
  // HOME DATA
  // ================================
  Future<List<HistoryEntry>> fetchHistoryTimeline({
    int limit = 200,
    String? businessProfileId,
    bool completedResultsOnly = false,
  }) async {
    final userId = Session.instance.userId;
    if (userId == null || userId.isEmpty) return const [];
    final workspace = await OrganizationService.instance
        .fetchActiveWorkspaceContext();
    final profileId =
        (businessProfileId?.trim().isNotEmpty == true
                ? businessProfileId!.trim()
                : workspace?.businessProfileId.trim() ?? '')
            .trim();

    debugPrint('[HISTORY] load start');
    debugPrint(
      '[OWNER_SCAN_HISTORY] has_user=true scoped_profile=${profileId.isNotEmpty} limit=$limit completed_results_only=$completedResultsOnly',
    );
    debugPrint(
      '[HISTORY] wellness_scans has_user=true scoped_profile=${profileId.isNotEmpty} limit=$limit',
    );

    if (completedResultsOnly) {
      final resultEntries = await _fetchCompletedResultHistoryEntries(
        userId: userId,
        profileId: profileId,
        limit: limit,
      );
      debugPrint('[OWNER_SCAN_HISTORY] result_count=${resultEntries.length}');
      debugPrint(
        '[OWNER_SCAN_HISTORY] has_latest_scan_id=${resultEntries.isNotEmpty && resultEntries.first.scanId.trim().isNotEmpty}',
      );
      return resultEntries;
    }

    Response<dynamic> scansResponse;
    try {
      final queryParameters = <String, dynamic>{
        'filter[user][_eq]': userId,
        'sort': '-date_created',
        'limit': limit,
        'fields': 'id,status,started_at,completed_at,date_created',
      };
      if (profileId.isNotEmpty) {
        queryParameters['filter[business_profile][_eq]'] = profileId;
      }
      scansResponse = await DirectusClient.instance.client.get(
        '/items/wellness_scans',
        queryParameters: queryParameters,
      );
    } on DioException catch (e) {
      debugPrint(
        '[HISTORY] wellness_scans status=${e.response?.statusCode} body_count=0',
      );
      rethrow;
    }
    final scansData = scansResponse.data['data'];
    final scanRows = scansData is List
        ? scansData.whereType<Map<String, dynamic>>().toList()
        : <Map<String, dynamic>>[];
    debugPrint(
      '[HISTORY] wellness_scans status=${scansResponse.statusCode} body_count=${scanRows.length}',
    );
    debugPrint('[HISTORY_DATA] wellness_count=${scanRows.length}');
    debugPrint(
      '[HISTORY_DATA] result_query_scoped_profile=${profileId.isNotEmpty}',
    );

    if (scanRows.isEmpty) {
      debugPrint('[HISTORY] empty');
      debugPrint('[HISTORY_DATA] scan_results_status=200');
      debugPrint('[HISTORY_DATA] result_count=0');
      debugPrint('[HISTORY_DATA] completed_with_result=0');
      debugPrint('[HISTORY_DATA] processing_count=0');
      debugPrint('[HISTORY_DATA] failed_count=0');
      return const [];
    }

    final scanIds = scanRows
        .map((e) => e['id']?.toString() ?? '')
        .where((e) => e.isNotEmpty)
        .toList();

    final byScan = <String, ScanResult>{};
    var scanResultsStatus = 200;
    for (final scanId in scanIds) {
      try {
        final lookup = await fetchScanResultLookupForScan(scanId);
        if (lookup.result != null && lookup.result!.id.trim().isNotEmpty) {
          byScan[scanId] = lookup.result!;
        }
      } on DioException catch (e) {
        scanResultsStatus = e.response?.statusCode ?? 0;
        if (scanResultsStatus != 400 &&
            scanResultsStatus != 403 &&
            scanResultsStatus != 422) {
          rethrow;
        }
      }
    }
    debugPrint('[HISTORY_DATA] scan_results_status=$scanResultsStatus');
    debugPrint('[HISTORY_DATA] result_count=${byScan.length}');

    final entries = scanRows.map((row) {
      final id = row['id']?.toString() ?? '';
      return HistoryEntry(
        id: id,
        scanId: id,
        startedAt: _tryDate(row['started_at']),
        completedAt: _tryDate(row['completed_at']),
        dateCreated: _tryDate(row['date_created']),
        status: row['status']?.toString() ?? '',
        result: byScan[id],
      );
    }).toList();

    debugPrint('[HISTORY] success count=${entries.length}');
    final completedWithResult = entries
        .where(
          (entry) =>
              entry.hasResult &&
              entry.status.trim().toLowerCase() == 'completed',
        )
        .length;
    final processingCount = entries
        .where(
          (entry) =>
              _isHistoryProcessingStatus(entry.status) && !entry.hasResult,
        )
        .length;
    final failedCount = entries
        .where(
          (entry) => _isHistoryFailedStatus(entry.status) && !entry.hasResult,
        )
        .length;
    debugPrint('[OWNER_SCAN_HISTORY] result_count=${byScan.length}');
    debugPrint(
      '[OWNER_SCAN_HISTORY] has_latest_scan_id=${entries.isNotEmpty && entries.first.scanId.trim().isNotEmpty}',
    );
    debugPrint('[HISTORY_DATA] completed_with_result=$completedWithResult');
    debugPrint('[HISTORY_DATA] processing_count=$processingCount');
    debugPrint('[HISTORY_DATA] failed_count=$failedCount');
    return entries;
  }

  Future<List<HistoryEntry>> _fetchCompletedResultHistoryEntries({
    required String userId,
    required String profileId,
    required int limit,
  }) async {
    debugPrint(
      '[OWNER_SCAN_HISTORY] query_keys=[wellness_scans + per-scan lookup] scoped_profile=${profileId.isNotEmpty}',
    );
    try {
      final entries = await fetchHistoryTimeline(
        limit: limit,
        businessProfileId: profileId.isEmpty ? null : profileId,
        completedResultsOnly: false,
      );
      final rows = entries
          .where((entry) => entry.hasResult)
          .where((entry) => entry.status.trim().toLowerCase() == 'completed')
          .toList();
      debugPrint(
        '[OWNER_HISTORY_SOURCE] endpoint=/items/wellness_scans + /items/scan_results raw_count=${rows.length} has_latest_scan_id=${rows.isNotEmpty && rows.first.scanId.trim().isNotEmpty}',
      );
      final seenScanIds = <String>{};
      final seenResultIds = <String>{};
      final deduped = <HistoryEntry>[];
      for (final row in rows) {
        final scanId = row.scanId.trim();
        final resultId = row.result?.id.trim() ?? '';
        if (scanId.isEmpty) continue;
        if (seenScanIds.contains(scanId)) continue;
        if (resultId.isNotEmpty && seenResultIds.contains(resultId)) continue;
        final result = row.result!;
        debugPrint(
          '[OWNER_HISTORY_RESULT] has_scan_id=${result.scanId.trim().isNotEmpty} has_risk_level=${(result.riskLevel ?? result.overallState).trim().isNotEmpty == true} has_readiness_score=${result.readinessScore != null} has_date_created=${result.dateCreated != null}',
        );
        seenScanIds.add(scanId);
        if (resultId.isNotEmpty) seenResultIds.add(resultId);
        deduped.add(row);
      }
      return deduped;
    } on DioException catch (e) {
      final status = e.response?.statusCode ?? 0;
      debugPrint(
        '[OWNER_SCAN_HISTORY] result_count=0 direct_result_query_status=$status',
      );
      if (status == 400 || status == 403 || status == 422) {
        return const [];
      }
      rethrow;
    }
  }

  Future<HomeData> fetchHomeData({int limit = 50}) async {
    final userId = Session.instance.userId;
    if (userId == null) {
      return const HomeData(results: []);
    }
    debugPrint(
      '[HOME_DATA] start has_user=${userId.trim().isNotEmpty} limit=$limit',
    );

    try {
      final scanIds = await _fetchUserScanIds(userId: userId, limit: limit);

      if (scanIds.isEmpty) {
        debugPrint('[HOME_DATA] no scans found');
        return const HomeData(results: []);
      }

      final results = await _fetchResultsByScanIds(
        scanIds: scanIds,
        limit: limit,
      );

      if (results.isEmpty) {
        final fallback = await _fetchResultsByUser(
          userId: userId,
          limit: limit,
        );
        debugPrint('[HOME_DATA] fallback results count=${fallback.length}');
        return HomeData(results: fallback);
      }

      debugPrint('[HOME_DATA] success results count=${results.length}');
      return HomeData(results: results);
    } on DioException catch (e) {
      final status = e.response?.statusCode ?? 0;
      if (status == 401) {
        _logDioError('GET', '/items/wellness_scans|/items/scan_results', e);
        throw const UnauthenticatedException('Session expired. Please login.');
      }
      if (status == 403) {
        _logDioError('GET', '/items/wellness_scans|/items/scan_results', e);
        return const HomeData(results: []);
      }
      if (_isTransientNetworkError(e)) {
        debugPrint('[HOME_DATA] transient fail ${_extractMessage(e)}');
        return const HomeData(results: []);
      }
      _logDioError('GET', '/items/wellness_scans|/items/scan_results', e);
      debugPrint('[HOME_DATA] fail ${_extractMessage(e)}');
      rethrow;
    }
  }

  // ================================
  // SCANS
  // ================================
  Future<String> createWellnessScan({
    bool consentGranted = true,
    Map<String, dynamic>? deviceInfo,
    Map<String, dynamic>? environmentInfo,
    String? businessProfileId,
    String? scanRequestId,
    String? requestSource,
    String? memberId,
    String? departmentId,
    String? memberRoleSnapshot,
    String? departmentNameSnapshot,
    String? shiftTemplateNameSnapshot,
    Map<String, dynamic>? taskMetrics,
    String? devicePlatform,
  }) async {
    final userId = Session.instance.userId;
    if (userId == null || userId.trim().isEmpty) {
      throw const ScanServiceException(
        method: 'POST',
        path: '/items/wellness_scans',
        message: 'User not logged in',
        statusCode: 401,
      );
    }

    final workspace = await OrganizationService.instance
        .fetchActiveWorkspaceContext();
    final resolvedBusinessProfileId =
        (businessProfileId ??
                workspace?.businessProfileId ??
                await OrganizationService.instance
                    .fetchPrimaryBusinessProfileId() ??
                '')
            .trim();
    final resolvedMemberIdRaw = (memberId ?? workspace?.membershipId ?? '')
        .trim();
    final resolvedDepartmentId = (departmentId ?? workspace?.departmentId ?? '')
        .trim();
    final resolvedRequestId = (scanRequestId ?? '').trim();
    final resolvedRequestSource = _normalizeRequestSource(
      requestSource ??
          (resolvedRequestId.isNotEmpty ? 'manager_request' : 'self'),
    );
    if (resolvedBusinessProfileId.isEmpty) {
      throw const ScanServiceException(
        method: 'POST',
        path: '/items/wellness_scans',
        message: 'No active workspace found for this account.',
      );
    }
    if (resolvedMemberIdRaw.isEmpty) {
      throw const ScanServiceException(
        method: 'POST',
        path: '/items/wellness_scans',
        message: 'No active workspace found for this account.',
      );
    }

    final memberSnapshot = await _loadMemberSnapshot(
      memberId: resolvedMemberIdRaw,
    );
    final resolvedMemberRoleSnapshot =
        (memberRoleSnapshot ??
                memberSnapshot.memberRole ??
                workspace?.membershipRole ??
                workspace?.memberRole)
            ?.trim();
    final resolvedDepartmentNameSnapshot =
        (departmentNameSnapshot ??
                memberSnapshot.departmentName ??
                workspace?.departmentName)
            ?.trim();
    final resolvedShiftTemplateNameSnapshot =
        (shiftTemplateNameSnapshot ?? memberSnapshot.shiftTemplateName)?.trim();
    final nowIso = DateTime.now().toUtc().toIso8601String();
    final resolvedDevicePlatform = _normalizeDevicePlatform(
      devicePlatform ??
          (kIsWeb ? 'web' : defaultTargetPlatform.name.toLowerCase()),
    );
    final parsedMemberId = _parseMemberId(resolvedMemberIdRaw);

    final payload = <String, dynamic>{
      'status': 'pending',
      'user': userId.trim(),
      'business_profile': resolvedBusinessProfileId,
      'member': parsedMemberId,
      if (resolvedDepartmentId.isNotEmpty) 'department': resolvedDepartmentId,
      'request_source': resolvedRequestSource,
      'started_at': nowIso,
      'consent_granted': consentGranted,
      'device_platform': resolvedDevicePlatform,
      'device_info': deviceInfo ?? <String, dynamic>{},
      'environment_info': environmentInfo ?? <String, dynamic>{},
      'task_metrics': taskMetrics ?? <String, dynamic>{},
      if (resolvedMemberRoleSnapshot != null &&
          resolvedMemberRoleSnapshot.isNotEmpty)
        'member_role_snapshot': resolvedMemberRoleSnapshot,
      if (resolvedDepartmentNameSnapshot != null &&
          resolvedDepartmentNameSnapshot.isNotEmpty)
        'department_name_snapshot': resolvedDepartmentNameSnapshot,
      if (resolvedShiftTemplateNameSnapshot != null &&
          resolvedShiftTemplateNameSnapshot.isNotEmpty)
        'shift_template_name_snapshot': resolvedShiftTemplateNameSnapshot,
    };

    debugPrint(
      '[ScanFlow] create wellness_scan context has_user=${userId.trim().isNotEmpty} has_member=${resolvedMemberIdRaw.trim().isNotEmpty} scoped_profile=${resolvedBusinessProfileId.trim().isNotEmpty} scoped_department=${resolvedDepartmentId.trim().isNotEmpty}',
    );
    debugPrint(
      '[ScanFlow] create wellness_scan payload_keys=${payload.keys.toList()}',
    );

    try {
      await _logRequest(
        method: 'POST',
        path: '/items/wellness_scans',
        payload: payload,
      );
      final response = await DirectusClient.instance.client.post(
        '/items/wellness_scans',
        data: payload,
      );
      await _logResponse(
        method: 'POST',
        path: '/items/wellness_scans',
        status: response.statusCode,
        body: response.data,
      );
      debugPrint(
        '[ScanFlow] create wellness_scan status: ${response.statusCode}',
      );
      debugPrint(
        '[ScanFlow] create wellness_scan body_type=${response.data.runtimeType}',
      );
      return response.data['data']['id'].toString();
    } on DioException catch (e) {
      await _logError(method: 'POST', path: '/items/wellness_scans', e: e);
      debugPrint(
        '[ScanFlow] create wellness_scan status: ${e.response?.statusCode ?? 0}',
      );
      debugPrint('[ScanFlow] create wellness_scan error_type=${e.type}');
      throw ScanServiceException(
        method: 'POST',
        path: '/items/wellness_scans',
        statusCode: e.response?.statusCode,
        responseBody: e.response?.data,
        message: _extractMessage(e),
      );
    }
  }

  Future<void> markWellnessScanMediaReady({required String scanId}) async {
    final payload = <String, dynamic>{'status': 'media_ready'};
    debugPrint(
      '[ScanFlow] status changed to media_ready has_scan_id=${scanId.trim().isNotEmpty} payload_keys=${payload.keys.toList()}',
    );
    try {
      await _logRequest(
        method: 'PATCH',
        path: '/items/wellness_scans/$scanId',
        payload: payload,
      );
      final response = await DirectusClient.instance.client.patch(
        '/items/wellness_scans/$scanId',
        data: payload,
      );
      await _logResponse(
        method: 'PATCH',
        path: '/items/wellness_scans/$scanId',
        status: response.statusCode,
        body: response.data,
      );
      debugPrint(
        '[ScanFlow] status changed to media_ready has_scan_id=${scanId.trim().isNotEmpty} status=${response.statusCode} body_type=${response.data.runtimeType}',
      );
    } on DioException catch (e) {
      await _logError(
        method: 'PATCH',
        path: '/items/wellness_scans/$scanId',
        e: e,
      );
      throw ScanServiceException(
        method: 'PATCH',
        path: '/items/wellness_scans/$scanId',
        statusCode: e.response?.statusCode,
        responseBody: e.response?.data,
        message: _extractMessage(e),
      );
    }
  }

  Future<void> markWellnessScanFailed({
    required String scanId,
    required String failureReason,
  }) async {
    final payload = <String, dynamic>{
      'status': 'failed',
      'failure_reason': failureReason,
    };
    debugPrint(
      '[ScanFlow] status changed to failed has_scan_id=${scanId.trim().isNotEmpty} payload_keys=${payload.keys.toList()}',
    );
    try {
      await _logRequest(
        method: 'PATCH',
        path: '/items/wellness_scans/$scanId',
        payload: payload,
      );
      final response = await DirectusClient.instance.client.patch(
        '/items/wellness_scans/$scanId',
        data: payload,
      );
      await _logResponse(
        method: 'PATCH',
        path: '/items/wellness_scans/$scanId',
        status: response.statusCode,
        body: response.data,
      );
      debugPrint(
        '[ScanFlow] status changed to failed has_scan_id=${scanId.trim().isNotEmpty} status=${response.statusCode} body_type=${response.data.runtimeType}',
      );
    } on DioException catch (e) {
      await _logError(
        method: 'PATCH',
        path: '/items/wellness_scans/$scanId',
        e: e,
      );
      throw ScanServiceException(
        method: 'PATCH',
        path: '/items/wellness_scans/$scanId',
        statusCode: e.response?.statusCode,
        responseBody: e.response?.data,
        message: _extractMessage(e),
      );
    }
  }

  Future<ProcessTriggerResponse> triggerAiServerProcess({
    required String scanId,
  }) async {
    // Pre-flight check: require valid Directus access token
    final accessToken = Session.instance.accessToken;
    if (accessToken == null || accessToken.trim().isEmpty) {
      throw const UnauthenticatedException('Session expired. Please login.');
    }

    final payload = <String, dynamic>{'scan_id': scanId};
    final headers = <String, dynamic>{
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $accessToken',
    };

    final dio = Dio(
      BaseOptions(
        connectTimeout: const Duration(seconds: 15),
        receiveTimeout: const Duration(seconds: 30),
        sendTimeout: const Duration(seconds: 15),
        headers: headers,
      ),
    );
    debugPrint(
      '[ScanFlow] AI Server /process request has_scan_id=${scanId.trim().isNotEmpty}',
    );
    try {
      final response = await dio.post(aiServerProcessUrl, data: payload);
      final body = response.data is Map<String, dynamic>
          ? response.data as Map<String, dynamic>
          : <String, dynamic>{'data': response.data};
      debugPrint(
        '[ScanFlow] AI Server /process response status=${response.statusCode} body_type=${body.runtimeType}',
      );
      return ProcessTriggerResponse(
        statusCode: response.statusCode ?? 0,
        body: body,
      );
    } on DioException catch (e) {
      final status = e.response?.statusCode ?? 0;
      debugPrint(
        '[ScanFlow] AI Server /process response status=$status error_type=${e.type}',
      );
      // Convert 401 to authentication exception (consistent with fetchHomeData pattern)
      if (status == 401) {
        throw const UnauthenticatedException('Session expired. Please login.');
      }
      throw ScanServiceException(
        method: 'POST',
        path: aiServerProcessUrl,
        statusCode: status,
        responseBody: e.response?.data,
        message: _extractMessage(e),
      );
    }
  }

  Future<WellnessScanStatus> fetchWellnessScanStatus(String scanId) async {
    try {
      const requestedFields =
          'id,status,failure_reason,completed_at,date_updated';
      if (kDebugMode) {
        debugPrint(
          '[SCAN_STATUS] request ts=${DateTime.now().toIso8601String()} has_scan_id=${scanId.trim().isNotEmpty} fields_present=${requestedFields.isNotEmpty}',
        );
      }
      await _logRequest(
        method: 'GET',
        path: '/items/wellness_scans/$scanId',
        query: {'fields': requestedFields},
      );
      final response = await DirectusClient.instance.client.get(
        '/items/wellness_scans/$scanId',
        queryParameters: {'fields': requestedFields},
      );
      if (kDebugMode) {
        debugPrint(
          '[SCAN_STATUS] response ts=${DateTime.now().toIso8601String()} has_scan_id=${scanId.trim().isNotEmpty} http_status=${response.statusCode} body_type=${response.data.runtimeType}',
        );
      }
      await _logResponse(
        method: 'GET',
        path: '/items/wellness_scans/$scanId',
        status: response.statusCode,
        body: response.data,
      );
      final data = response.data['data'] as Map<String, dynamic>? ?? const {};
      final snapshot = WellnessScanStatus.fromJson(data);
      debugPrint(
        '[ScanFlow] polling status has_scan_id=${scanId.trim().isNotEmpty} status=${snapshot.status} has_failure_reason=${snapshot.failureReason?.trim().isNotEmpty == true} has_completed_at=${snapshot.completedAt != null}',
      );
      if (kDebugMode) {
        debugPrint(
          '[SCAN_STATUS] parsed ts=${DateTime.now().toIso8601String()} has_scan_id=${scanId.trim().isNotEmpty} status=${snapshot.status} has_failure_reason=${snapshot.failureReason?.trim().isNotEmpty == true} has_completed_at=${snapshot.completedAt != null} has_date_updated=${snapshot.dateUpdated != null}',
        );
      }
      return snapshot;
    } on DioException catch (e) {
      if (kDebugMode) {
        debugPrint(
          '[SCAN_STATUS] error ts=${DateTime.now().toIso8601String()} has_scan_id=${scanId.trim().isNotEmpty} http_status=${e.response?.statusCode ?? 0} error_type=${e.type}',
        );
      }
      await _logError(
        method: 'GET',
        path: '/items/wellness_scans/$scanId',
        e: e,
      );
      throw ScanServiceException(
        method: 'GET',
        path: '/items/wellness_scans/$scanId',
        statusCode: e.response?.statusCode,
        responseBody: e.response?.data,
        message: _extractMessage(e),
      );
    }
  }

  // ================================
  // FILE UPLOAD
  // ================================
  Future<String> uploadXFile(XFile file, {String? filename}) async {
    final name = filename ?? file.name;
    final requestUrl = _absoluteUrl('/files');
    final filePath = file.path;
    final fileLength = await _safeFileLength(file);
    final fileExists = fileLength != null && fileLength > 0;

    debugPrint('[ScanFlow] upload request path=/files');
    debugPrint('[ScanFlow] multipart field name: file');
    debugPrint('[ScanFlow] upload file name_present=${name.trim().isNotEmpty}');
    debugPrint(
      '[ScanFlow] upload file path_present=${filePath.trim().isNotEmpty}',
    );
    debugPrint('[ScanFlow] upload file exists: $fileExists');
    debugPrint('[ScanFlow] upload file size: ${fileLength ?? 0}');

    if (filePath.trim().isEmpty) {
      debugPrint(
        '[SCAN_FILE_UPLOAD_PRECHECK] filename_present=${name.trim().isNotEmpty} file_path_empty=true file_exists=false file_size=0',
      );
      throw const ScanServiceException(
        method: 'POST',
        path: '/files',
        message: 'Upload file path is empty.',
      );
    }
    if (!fileExists) {
      debugPrint(
        '[SCAN_FILE_UPLOAD_PRECHECK] filename_present=${name.trim().isNotEmpty} file_path_present=${filePath.trim().isNotEmpty} file_exists=$fileExists file_size=${fileLength ?? 0}',
      );
      throw ScanServiceException(
        method: 'POST',
        path: '/files',
        message: fileLength == null
            ? 'Upload file could not be read.'
            : 'Upload file is empty.',
      );
    }

    if (kIsWeb) {
      final bytes = await file.readAsBytes();
      return uploadBytes(bytes, filename: name);
    }

    final formData = FormData.fromMap({
      'file': await MultipartFile.fromFile(file.path, filename: name),
    });

    try {
      await _logRequest(
        method: 'POST',
        path: '/files',
        payload: {'file': name},
      );
      final response = await DirectusClient.instance.client.post(
        '/files',
        data: formData,
        options: Options(headers: {'Prefer': 'return=representation'}),
      );
      await _logResponse(
        method: 'POST',
        path: '/files',
        status: response.statusCode,
        body: response.data,
      );
      _logScanUploadResponse(response);
      _logScanFileContract(response);
      debugPrint(
        '[ScanFlow] upload media status=${response.statusCode} body_type=${response.data.runtimeType}',
      );

      final fileId = _extractUploadedFileId(response, requestPath: '/files');
      if (fileId != null) return fileId;
      throw ScanServiceException(
        method: 'POST',
        path: '/files',
        statusCode: response.statusCode,
        responseBody: response.data,
        message:
            'Upload to /files completed without a file id (status ${response.statusCode}).',
      );
    } on DioException catch (e, stackTrace) {
      await _logError(method: 'POST', path: '/files', e: e);
      _logFileUploadDiagnostics(
        requestUrl: requestUrl,
        fileName: name,
        filePath: filePath,
        fileExists: fileExists,
        fileSize: fileLength,
        multipartFields: const ['file'],
        error: e,
        stackTrace: stackTrace,
      );
      debugPrint(
        '[ScanFlow] upload media status=${e.response?.statusCode} error_type=${e.type}',
      );
      throw ScanServiceException(
        method: 'POST',
        path: '/files',
        statusCode: e.response?.statusCode,
        responseBody: e.response?.data,
        message: _extractMessage(e),
      );
    }
  }

  Future<String> uploadVideoFile({
    required XFile file,
    required String scanId,
  }) async {
    const uploadName = 'scan_video.mp4';
    final requestUrl = _absoluteUrl('/files');
    final originalPath = file.path;
    final detectedMimeType =
        file.mimeType ??
        MultipartFile.lookupMediaType(originalPath)?.mimeType ??
        'video/mp4';

    debugPrint('[ScanFlow] upload request path=/files');
    debugPrint('[ScanFlow] multipart field name: file');
    debugPrint(
      '[ScanFlow] video file path_present=${originalPath.trim().isNotEmpty}',
    );
    debugPrint('[ScanFlow] video mime type: $detectedMimeType');

    try {
      if (kIsWeb) {
        final bytes = await file.readAsBytes();
        debugPrint('[ScanFlow] video file exists: true');
        debugPrint('[ScanFlow] video file size: ${bytes.length}');
        if (bytes.isEmpty) {
          throw const ScanServiceException(
            method: 'POST',
            path: '/files',
            message: 'Video file is empty.',
          );
        }
        return uploadBytes(bytes, filename: uploadName);
      }

      final preparedVideo = await _prepareVideoUploadFile(
        file: file,
        scanId: scanId,
      );
      final videoExists = preparedVideo.exists;
      final videoSize = preparedVideo.sizeBytes ?? 0;

      debugPrint('[ScanFlow] video file exists: $videoExists');
      debugPrint('[ScanFlow] video file size: $videoSize');
      debugPrint('[ScanFlow] video safe file path_present=true');

      if (!videoExists) {
        throw const ScanServiceException(
          method: 'POST',
          path: '/files',
          message: 'Video file does not exist.',
        );
      }
      if (videoSize <= 0) {
        throw const ScanServiceException(
          method: 'POST',
          path: '/files',
          message: 'Video file is empty.',
        );
      }
      if (videoSize > _maxVideoUploadBytes) {
        throw const ScanServiceException(
          method: 'POST',
          path: '/files',
          message: 'Video file is too large after compression.',
        );
      }

      const retryDelays = <Duration>[
        Duration.zero,
        Duration(seconds: 2),
        Duration(seconds: 5),
      ];
      DioException? lastDioError;

      for (var attempt = 0; attempt < retryDelays.length; attempt++) {
        if (attempt > 0) {
          await Future.delayed(retryDelays[attempt]);
        }
        try {
          debugPrint(
            '[SCAN_VIDEO] upload attempt=${attempt + 1} '
            'has_scan_id=${scanId.trim().isNotEmpty} '
            'file_size=$videoSize '
            'file_path_present=true '
            'mime=video/mp4 '
            'compression_performed=${preparedVideo.wasCompressed}',
          );
          await _logRequest(
            method: 'POST',
            path: '/files',
            payload: {'file': uploadName, 'retry_count': attempt},
          );
          final formData = FormData.fromMap({
            'file': await MultipartFile.fromFile(
              preparedVideo.file.path,
              filename: uploadName,
              contentType: DioMediaType('video', 'mp4'),
            ),
          });
          final response = await DirectusClient.instance.client.post(
            '/files',
            data: formData,
            options: Options(
              headers: const {'Prefer': 'return=representation'},
              connectTimeout: _videoUploadConnectTimeout,
              sendTimeout: _videoUploadSendTimeout,
              receiveTimeout: _videoUploadReceiveTimeout,
              extra: {
                'video_source_path': preparedVideo.file.path,
                'video_file_exists': videoExists,
                'video_file_size': videoSize,
                'video_mime_type': 'video/mp4',
                'video_retry_count': attempt,
                'video_request_url': requestUrl,
                'video_compression_performed': preparedVideo.wasCompressed,
              },
            ),
          );
          await _logResponse(
            method: 'POST',
            path: '/files',
            status: response.statusCode,
            body: response.data,
          );
          _logScanUploadResponse(response);
          _logScanFileContract(response);
          debugPrint(
            '[ScanFlow] upload video status=${response.statusCode} body_type=${response.data.runtimeType}',
          );
          final fileId = _extractUploadedFileId(
            response,
            requestPath: '/files',
          );
          if (fileId != null) return fileId;
          throw ScanServiceException(
            method: 'POST',
            path: '/files',
            statusCode: response.statusCode,
            responseBody: response.data,
            message:
                'Upload to /files completed without a file id (status ${response.statusCode}).',
          );
        } on DioException catch (e, stackTrace) {
          lastDioError = e;
          await _logError(method: 'POST', path: '/files', e: e);
          _logVideoUploadDiagnostics(
            requestUrl: requestUrl,
            sourcePath:
                e.requestOptions.extra['video_source_path']?.toString() ??
                preparedVideo.file.path,
            fileExists: e.requestOptions.extra['video_file_exists'] == true,
            fileSize:
                (e.requestOptions.extra['video_file_size'] as int?) ??
                videoSize,
            mimeType:
                e.requestOptions.extra['video_mime_type']?.toString() ??
                'video/mp4',
            retryCount:
                (e.requestOptions.extra['video_retry_count'] as int?) ??
                attempt,
            compressionPerformed:
                e.requestOptions.extra['video_compression_performed'] == true,
            error: e,
            stackTrace: stackTrace,
          );
          final shouldRetry =
              e.response?.statusCode == 502 && attempt < retryDelays.length - 1;
          if (!shouldRetry) {
            rethrow;
          }
        }
      }

      if (lastDioError != null) {
        throw lastDioError;
      }
      throw const ScanServiceException(
        method: 'POST',
        path: '/files',
        message: 'Video upload failed before the request was completed.',
      );
    } on DioException catch (e, stackTrace) {
      await _logError(method: 'POST', path: '/files', e: e);
      _logVideoUploadDiagnostics(
        requestUrl: requestUrl,
        sourcePath:
            e.requestOptions.extra['video_source_path']?.toString() ??
            originalPath,
        fileExists: e.requestOptions.extra['video_file_exists'] == true,
        fileSize:
            (e.requestOptions.extra['video_file_size'] as int?) ??
            await _safeFileLength(file) ??
            0,
        mimeType:
            e.requestOptions.extra['video_mime_type']?.toString() ??
            'video/mp4',
        retryCount: (e.requestOptions.extra['video_retry_count'] as int?) ?? 0,
        compressionPerformed:
            e.requestOptions.extra['video_compression_performed'] == true,
        error: e,
        stackTrace: stackTrace,
      );
      throw ScanServiceException(
        method: 'POST',
        path: '/files',
        statusCode: e.response?.statusCode,
        responseBody: e.response?.data,
        message: _extractMessage(e),
      );
    } catch (e, stackTrace) {
      final fallbackSize = await _safeFileLength(file);
      _logVideoUploadUnexpectedFailure(
        requestUrl: requestUrl,
        sourcePath: originalPath,
        fileExists: fallbackSize != null && fallbackSize > 0,
        fileSize: fallbackSize ?? 0,
        mimeType: detectedMimeType,
        retryCount: 0,
        compressionPerformed: false,
        error: e,
        stackTrace: stackTrace,
      );
      throw ScanServiceException(
        method: 'POST',
        path: '/files',
        message: 'Video upload failed before the request was completed: $e',
      );
    }
  }

  Future<String> uploadBytes(
    Uint8List bytes, {
    required String filename,
  }) async {
    final requestUrl = _absoluteUrl('/files');
    debugPrint('[ScanFlow] upload request path=/files');
    debugPrint('[ScanFlow] multipart field name: file');
    debugPrint(
      '[ScanFlow] upload file name_present=${filename.trim().isNotEmpty}',
    );
    debugPrint('[ScanFlow] upload file source=bytes');
    debugPrint('[ScanFlow] upload file exists: ${bytes.isNotEmpty}');
    debugPrint('[ScanFlow] upload file size: ${bytes.length}');
    if (bytes.isEmpty) {
      debugPrint(
        '[SCAN_FILE_UPLOAD_PRECHECK] filename_present=${filename.trim().isNotEmpty} file_source=bytes file_exists=false file_size=0',
      );
      throw const ScanServiceException(
        method: 'POST',
        path: '/files',
        message: 'Upload bytes are empty.',
      );
    }

    final formData = FormData.fromMap({
      'file': MultipartFile.fromBytes(bytes, filename: filename),
    });

    try {
      await _logRequest(
        method: 'POST',
        path: '/files',
        payload: {'file': filename},
      );
      final response = await DirectusClient.instance.client.post(
        '/files',
        data: formData,
        options: Options(headers: {'Prefer': 'return=representation'}),
      );
      await _logResponse(
        method: 'POST',
        path: '/files',
        status: response.statusCode,
        body: response.data,
      );
      _logScanUploadResponse(response);
      _logScanFileContract(response);
      debugPrint(
        '[ScanFlow] upload media status=${response.statusCode} body_type=${response.data.runtimeType}',
      );

      final fileId = _extractUploadedFileId(response, requestPath: '/files');
      if (fileId != null) return fileId;
      throw ScanServiceException(
        method: 'POST',
        path: '/files',
        statusCode: response.statusCode,
        responseBody: response.data,
        message:
            'Upload to /files completed without a file id (status ${response.statusCode}).',
      );
    } on DioException catch (e, stackTrace) {
      await _logError(method: 'POST', path: '/files', e: e);
      _logFileUploadDiagnostics(
        requestUrl: requestUrl,
        fileName: filename,
        filePath: '<bytes>',
        fileExists: bytes.isNotEmpty,
        fileSize: bytes.length,
        multipartFields: const ['file'],
        error: e,
        stackTrace: stackTrace,
      );
      debugPrint(
        '[ScanFlow] upload media status=${e.response?.statusCode} error_type=${e.type}',
      );
      throw ScanServiceException(
        method: 'POST',
        path: '/files',
        statusCode: e.response?.statusCode,
        responseBody: e.response?.data,
        message: _extractMessage(e),
      );
    }
  }

  // ================================
  // RESULTS
  // ================================
  Future<ScanResult?> fetchScanResultForScan(String scanId) async {
    final lookup = await fetchScanResultLookupForScan(scanId);
    return lookup.result;
  }

  Future<ScanResult?> fetchScanResultById(String resultId) async {
    final fields = await _resolveScanResultsFields();
    final queryParameters = {'fields': fields};
    try {
      if (kDebugMode) {
        debugPrint(
          '[SCAN_RESULTS] direct_request ts=${DateTime.now().toIso8601String()} has_result_id=${resultId.trim().isNotEmpty} path=/items/scan_results/:id query_keys=${queryParameters.keys.toList()}',
        );
      }
      await _logRequest(
        method: 'GET',
        path: '/items/scan_results/$resultId',
        query: queryParameters,
      );
      final response = await DirectusClient.instance.client.get(
        '/items/scan_results/$resultId',
        queryParameters: queryParameters,
      );
      if (kDebugMode) {
        debugPrint(
          '[SCAN_RESULTS] direct_response ts=${DateTime.now().toIso8601String()} has_result_id=${resultId.trim().isNotEmpty} http_status=${response.statusCode} body_type=${response.data.runtimeType}',
        );
      }
      await _logResponse(
        method: 'GET',
        path: '/items/scan_results/$resultId',
        status: response.statusCode,
        body: response.data,
      );
      final data = response.data['data'] as Map<String, dynamic>? ?? const {};
      if (data.isEmpty) return null;
      return ScanResult.fromJson(data);
    } on DioException catch (e) {
      await _logError(
        method: 'GET',
        path: '/items/scan_results/$resultId',
        e: e,
      );
      final status = e.response?.statusCode ?? 0;
      if (status != 400 && status != 403 && status != 422) {
        if (kDebugMode) {
          debugPrint(
            '[SCAN_RESULTS] direct_error ts=${DateTime.now().toIso8601String()} has_result_id=${resultId.trim().isNotEmpty} http_status=$status error_type=${e.type}',
          );
        }
        rethrow;
      }
      final response = await DirectusClient.instance.client.get(
        '/items/scan_results/$resultId',
        queryParameters: {'fields': _scanResultFieldsMinimal},
      );
      if (kDebugMode) {
        debugPrint(
          '[SCAN_RESULTS] direct_fallback_response ts=${DateTime.now().toIso8601String()} has_result_id=${resultId.trim().isNotEmpty} http_status=${response.statusCode} body_type=${response.data.runtimeType}',
        );
      }
      await _logResponse(
        method: 'GET',
        path: '/items/scan_results/$resultId',
        status: response.statusCode,
        body: response.data,
      );
      final data = response.data['data'] as Map<String, dynamic>? ?? const {};
      if (data.isEmpty) return null;
      return ScanResult.fromJson(data);
    }
  }

  Future<ScanResultLookup> fetchScanResultLookupForScan(String scanId) async {
    Response<dynamic> response;
    final fields = await _resolveScanResultsFields();
    final queryParameters = {
      'filter[scan_id][_eq]': scanId,
      'limit': 1,
      'sort': '-date_created',
      'fields': fields,
    };
    try {
      if (kDebugMode) {
        debugPrint(
          '[SCAN_RESULTS] request ts=${DateTime.now().toIso8601String()} has_scan_id=${scanId.trim().isNotEmpty} path=/items/scan_results query_keys=${queryParameters.keys.toList()}',
        );
      }
      await _logRequest(
        method: 'GET',
        path: '/items/scan_results',
        query: queryParameters,
      );
      response = await DirectusClient.instance.client.get(
        '/items/scan_results',
        queryParameters: queryParameters,
      );
      if (kDebugMode) {
        debugPrint(
          '[SCAN_RESULTS] response ts=${DateTime.now().toIso8601String()} has_scan_id=${scanId.trim().isNotEmpty} http_status=${response.statusCode} body_type=${response.data.runtimeType}',
        );
      }
      await _logResponse(
        method: 'GET',
        path: '/items/scan_results',
        status: response.statusCode,
        body: response.data,
      );
    } on DioException catch (e) {
      await _logError(method: 'GET', path: '/items/scan_results', e: e);
      final status = e.response?.statusCode ?? 0;
      if (status != 400 && status != 403 && status != 422) {
        debugPrint(
          '[ScanFlow] wait for scan_results status=$status error_type=${e.type}',
        );
        rethrow;
      }
      response = await _fetchScanResultWithFallback(
        scanId: scanId,
        fields: _scanResultFieldsMinimal,
      );
    }

    final data = response.data['data'] as List<dynamic>;
    if (kDebugMode) {
      final first = data.isNotEmpty && data.first is Map
          ? data.first as Map<dynamic, dynamic>
          : null;
      debugPrint(
        '[SCAN_RESULTS] has_scan_id=${scanId.trim().isNotEmpty} status=${response.statusCode} count=${data.length} has_first_result_id=${(first?['id']?.toString().trim() ?? '').isNotEmpty}',
      );
      debugPrint(
        '[SCAN_RESULTS] parsed ts=${DateTime.now().toIso8601String()} has_scan_id=${scanId.trim().isNotEmpty} count=${data.length} has_first_id=${(first?['id']?.toString().trim() ?? '').isNotEmpty} has_risk_level=${(first?['risk_level']?.toString().trim() ?? '').isNotEmpty} has_readiness_score=${(first?['readiness_score']?.toString().trim() ?? '').isNotEmpty}',
      );
    }
    debugPrint(
      '[ScanFlow] wait for scan_results status/body: ${response.statusCode}/${data.length}',
    );
    if (data.isEmpty) {
      return const ScanResultLookup(result: null, count: 0);
    }

    debugPrint('[SCAN_FLOW] result ready');
    final firstRow = data.first is Map<String, dynamic>
        ? data.first as Map<String, dynamic>
        : data.first is Map
        ? (data.first as Map).map(
            (key, dynamic value) => MapEntry(key.toString(), value),
          )
        : <String, dynamic>{};
    final firstResultId = firstRow['id']?.toString();
    ScanResult? parsedResult;
    try {
      parsedResult = ScanResult.fromJson(firstRow);
    } catch (e, s) {
      if (kDebugMode) {
        debugPrint(
          '[SCAN_RESULTS] list_parse_failed ts=${DateTime.now().toIso8601String()} has_scan_id=${scanId.trim().isNotEmpty} has_first_result_id=${firstResultId?.trim().isNotEmpty == true} error_type=${e.runtimeType}',
        );
        debugPrint(
          '[SCAN_RESULTS] list_parse_stack_present=${s.toString().isNotEmpty}',
        );
      }
    }
    return ScanResultLookup(
      result: parsedResult,
      count: data.length,
      firstResultId: firstResultId,
    );
  }

  Future<void> updateScanResultTaskScore({
    required String resultId,
    required double taskScore,
  }) async {
    await DirectusClient.instance.client.patch(
      '/items/scan_results/$resultId',
      data: {'task_performance_score': taskScore},
    );
  }

  Future<String> createScanMedia({
    required String scanId,
    String? videoFileId,
    String? audioFileId,
    String? thumbnailFileId,
    required int durationSeconds,
    String? businessProfileId,
  }) async {
    final workspace = await OrganizationService.instance
        .fetchActiveWorkspaceContext();
    final resolvedBusinessProfileId =
        (businessProfileId ??
                workspace?.businessProfileId ??
                await _fetchWellnessScanBusinessProfile(scanId) ??
                '')
            .trim();
    if (resolvedBusinessProfileId.isEmpty) {
      throw const ScanServiceException(
        method: 'POST',
        path: '/items/scan_media',
        message: 'No active workspace found for this account.',
      );
    }

    final payload = <String, dynamic>{
      'scan_id': scanId,
      'business_profile': resolvedBusinessProfileId,
      'video_file': videoFileId,
      'audio_file': audioFileId,
      'thumbnail': thumbnailFileId,
      'duration_seconds': durationSeconds,
      'is_deleted': false,
    };

    debugPrint(
      '[ScanFlow] create scan_media payload_keys=${payload.keys.toList()} has_scan_id=${scanId.trim().isNotEmpty} has_video=${videoFileId?.trim().isNotEmpty == true} has_audio=${audioFileId?.trim().isNotEmpty == true} has_thumbnail=${thumbnailFileId?.trim().isNotEmpty == true} scoped_profile=${resolvedBusinessProfileId.isNotEmpty}',
    );
    try {
      await _logRequest(
        method: 'POST',
        path: '/items/scan_media',
        payload: payload,
      );
      final response = await DirectusClient.instance.client.post(
        '/items/scan_media',
        data: payload,
      );
      await _logResponse(
        method: 'POST',
        path: '/items/scan_media',
        status: response.statusCode,
        body: response.data,
      );
      debugPrint(
        '[ScanFlow] create scan_media status=${response.statusCode} body_type=${response.data.runtimeType}',
      );
      return response.data['data']['id'].toString();
    } on DioException catch (e) {
      await _logError(method: 'POST', path: '/items/scan_media', e: e);
      debugPrint(
        '[ScanFlow] create scan_media status=${e.response?.statusCode ?? 0} error_type=${e.type}',
      );
      throw ScanServiceException(
        method: 'POST',
        path: '/items/scan_media',
        statusCode: e.response?.statusCode,
        responseBody: e.response?.data,
        message: _extractMessage(e),
      );
    }
  }

  Future<String?> _fetchWellnessScanBusinessProfile(String scanId) async {
    try {
      await _logRequest(
        method: 'GET',
        path: '/items/wellness_scans/$scanId',
        query: {'fields': 'business_profile'},
      );
      final response = await DirectusClient.instance.client.get(
        '/items/wellness_scans/$scanId',
        queryParameters: {'fields': 'business_profile'},
      );
      await _logResponse(
        method: 'GET',
        path: '/items/wellness_scans/$scanId',
        status: response.statusCode,
        body: response.data,
      );
      final data = response.data['data'] as Map<String, dynamic>? ?? const {};
      final businessProfile = data['business_profile'];
      if (businessProfile is Map<String, dynamic>) {
        return businessProfile['id']?.toString().trim();
      }
      return businessProfile?.toString().trim();
    } on DioException catch (e) {
      await _logError(
        method: 'GET',
        path: '/items/wellness_scans/$scanId',
        e: e,
      );
      return null;
    }
  }

  // ================================
  // INTERNAL HELPERS
  // ================================
  Future<List<String>> _fetchUserScanIds({
    required String userId,
    required int limit,
    String? businessProfileId,
  }) async {
    final profileId = businessProfileId?.trim() ?? '';
    await _logRequest(
      method: 'GET',
      path: '/items/wellness_scans',
      query: {
        'filter[user][_eq]': userId,
        if (profileId.isNotEmpty) 'filter[business_profile][_eq]': profileId,
        'sort': '-date_created',
        'limit': limit,
        'fields': 'id',
      },
    );
    final queryParameters = <String, dynamic>{
      'filter[user][_eq]': userId,
      if (profileId.isNotEmpty) 'filter[business_profile][_eq]': profileId,
      'sort': '-date_created',
      'limit': limit,
      'fields': 'id',
    };
    final response = await DirectusClient.instance.client.get(
      '/items/wellness_scans',
      queryParameters: queryParameters,
    );
    await _logResponse(
      method: 'GET',
      path: '/items/wellness_scans',
      status: response.statusCode,
      body: response.data,
    );

    final data = (response.data['data'] as List<dynamic>)
        .cast<Map<String, dynamic>>();
    debugPrint('[WELLNESS_SCANS] query response count=${data.length}');

    return data.map((e) => e['id'].toString()).toList();
  }

  Future<List<ScanResult>> _fetchResultsByScanIds({
    required List<String> scanIds,
    required int limit,
  }) async {
    final fields = await _resolveScanResultsFields();
    await _logRequest(
      method: 'GET',
      path: '/items/scan_results',
      query: {
        'filter[scan_id][_in]': scanIds.join(','),
        'sort': '-date_created',
        'limit': limit,
        'fields': fields,
      },
    );
    Response<dynamic> response;
    try {
      response = await DirectusClient.instance.client.get(
        '/items/scan_results',
        queryParameters: {
          'filter[scan_id][_in]': scanIds.join(','),
          'sort': '-date_created',
          'limit': limit,
          'fields': fields,
        },
      );
      await _logResponse(
        method: 'GET',
        path: '/items/scan_results',
        status: response.statusCode,
        body: response.data,
      );
    } on DioException catch (e) {
      await _logError(method: 'GET', path: '/items/scan_results', e: e);
      final status = e.response?.statusCode ?? 0;
      if (status != 400 && status != 403 && status != 422) {
        rethrow;
      }
      response = await _fetchScanResultsByIdsWithFallback(
        scanIds: scanIds,
        limit: limit,
        fields: _scanResultFieldsMinimal,
      );
    }

    final data = (response.data['data'] as List<dynamic>)
        .cast<Map<String, dynamic>>();

    return data.map(ScanResult.fromJson).toList();
  }

  Future<List<ScanResult>> _fetchResultsByUser({
    required String userId,
    required int limit,
  }) async {
    final fields = await _resolveScanResultsFields();
    final baseQuery = <String, dynamic>{
      'sort': '-date_created',
      'limit': limit,
      'fields': fields,
    };

    try {
      Response<dynamic> response;
      try {
        await _logRequest(
          method: 'GET',
          path: '/items/scan_results',
          query: {...baseQuery, 'filter[scan_id][user][_eq]': userId},
        );
        response = await DirectusClient.instance.client.get(
          '/items/scan_results',
          queryParameters: {...baseQuery, 'filter[scan_id][user][_eq]': userId},
        );
        await _logResponse(
          method: 'GET',
          path: '/items/scan_results',
          status: response.statusCode,
          body: response.data,
        );
      } on DioException catch (error) {
        await _logError(method: 'GET', path: '/items/scan_results', e: error);
        final status = error.response?.statusCode ?? 0;
        if (status != 400 && status != 403 && status != 422) {
          rethrow;
        }
        response = await DirectusClient.instance.client.get(
          '/items/scan_results',
          queryParameters: {
            ...baseQuery,
            'fields': _scanResultFieldsMinimal,
            'filter[scan_id][user][_eq]': userId,
          },
        );
        await _logResponse(
          method: 'GET',
          path: '/items/scan_results',
          status: response.statusCode,
          body: response.data,
        );
      }

      final data = (response.data['data'] as List<dynamic>)
          .cast<Map<String, dynamic>>();
      return data.map(ScanResult.fromJson).toList();
    } on DioException catch (e) {
      await _logError(method: 'GET', path: '/items/scan_results', e: e);
      final status = e.response?.statusCode ?? 0;
      if (status != 400 && status != 403) rethrow;

      Response<dynamic> response;
      try {
        await _logRequest(
          method: 'GET',
          path: '/items/scan_results',
          query: {...baseQuery, 'filter[scan_id.user][_eq]': userId},
        );
        response = await DirectusClient.instance.client.get(
          '/items/scan_results',
          queryParameters: {...baseQuery, 'filter[scan_id.user][_eq]': userId},
        );
        await _logResponse(
          method: 'GET',
          path: '/items/scan_results',
          status: response.statusCode,
          body: response.data,
        );
      } on DioException catch (error) {
        await _logError(method: 'GET', path: '/items/scan_results', e: error);
        final retryStatus = error.response?.statusCode ?? 0;
        if (retryStatus != 400 && retryStatus != 403 && retryStatus != 422) {
          rethrow;
        }
        response = await DirectusClient.instance.client.get(
          '/items/scan_results',
          queryParameters: {
            ...baseQuery,
            'fields': _scanResultFieldsMinimal,
            'filter[scan_id.user][_eq]': userId,
          },
        );
        await _logResponse(
          method: 'GET',
          path: '/items/scan_results',
          status: response.statusCode,
          body: response.data,
        );
      }

      final data = (response.data['data'] as List<dynamic>)
          .cast<Map<String, dynamic>>();
      return data.map(ScanResult.fromJson).toList();
    }
  }

  // Keep this schema-safe to avoid leaking Directus field-permission errors in UI.
  static const String _scanResultFieldsFull =
      'id,scan_id,date_created,state,readiness_label,readiness_state,overall_state,'
      'risk_level,readiness_score,confidence,camera_confidence,voice_confidence,'
      'task_performance_score,confidence_drift,explanation,suggested_action,'
      'readiness_summary,operational_summary,recommended_action,ai_model_version,'
      'baseline_used,face_metrics,voice_metrics,reaction_metrics';

  static const String _scanResultFieldsMinimal =
      'id,scan_id,date_created,risk_level,readiness_score,confidence,'
      'camera_confidence,voice_confidence,task_performance_score,confidence_drift,'
      'explanation,suggested_action,ai_model_version,baseline_used,'
      'face_metrics,voice_metrics,reaction_metrics';

  static const String _scanResultFieldsLegacyMinimal =
      'id,scan_id,date_created,confidence,camera_confidence,voice_confidence,'
      'task_performance_score,confidence_drift';

  Future<String> _resolveScanResultsFields() async {
    if (_cachedScanResultsFields != null) return _cachedScanResultsFields!;
    final baseFields = <String>{
      'id',
      'scan_id',
      'date_created',
      'risk_level',
      'readiness_score',
      'confidence',
      'camera_confidence',
      'voice_confidence',
      'task_performance_score',
      'confidence_drift',
      'explanation',
      'suggested_action',
      'ai_model_version',
      'baseline_used',
      'face_metrics',
      'voice_metrics',
      'reaction_metrics',
    };
    final preferred = <String>[
      'state',
      'readiness_label',
      'readiness_state',
      'overall_state',
      'readiness_summary',
      'operational_summary',
      'recommended_action',
    ];

    try {
      final resp = await DirectusClient.instance.client.get(
        '/fields/scan_results',
      );
      final rows = resp.data['data'];
      if (rows is List) {
        final available = rows
            .whereType<Map<String, dynamic>>()
            .map((e) => (e['field'] ?? '').toString())
            .where((e) => e.isNotEmpty)
            .toSet();
        debugPrint(
          '[SCAN_RESULTS_SCHEMA] fields_found_count=${available.length}',
        );
        final selected = <String>{
          ...baseFields.where(available.contains),
          ...preferred.where(available.contains),
        }..addAll(scanResultAssessmentFieldNames);
        if (selected.contains('id') && selected.contains('scan_id')) {
          debugPrint(
            '[SCAN_RESULTS_SCHEMA] has_ai_model_version=${selected.contains('ai_model_version')} has_baseline_used=${selected.contains('baseline_used')}',
          );
          _cachedScanResultsFields = selected.join(',');
          debugPrint(
            '[SCAN_RESULTS_SCHEMA] selected_field_count=${selected.length}',
          );
          return _cachedScanResultsFields!;
        }
      }
    } on DioException catch (e) {
      debugPrint(
        '[SCAN_RESULTS_SCHEMA] unable_to_read_fields status=${e.response?.statusCode} error_type=${e.type}',
      );
    } catch (e) {
      debugPrint(
        '[SCAN_RESULTS_SCHEMA] unexpected_error_type=${e.runtimeType}',
      );
    }

    _cachedScanResultsFields = _scanResultFieldsMinimal;
    debugPrint(
      '[SCAN_RESULTS_SCHEMA] fallback_field_count=${_cachedScanResultsFields!.split(',').length}',
    );
    return _cachedScanResultsFields!;
  }

  Future<Response<dynamic>> _fetchScanResultWithFallback({
    required String scanId,
    required String fields,
  }) async {
    try {
      final response = await DirectusClient.instance.client.get(
        '/items/scan_results',
        queryParameters: {
          'filter[scan_id][_eq]': scanId,
          'limit': 1,
          'sort': '-date_created',
          'fields': fields,
        },
      );
      await _logResponse(
        method: 'GET',
        path: '/items/scan_results',
        status: response.statusCode,
        body: response.data,
      );
      return response;
    } on DioException catch (error) {
      await _logError(method: 'GET', path: '/items/scan_results', e: error);
      final status = error.response?.statusCode ?? 0;
      if (status != 400 && status != 403 && status != 422) rethrow;
      final response = await DirectusClient.instance.client.get(
        '/items/scan_results',
        queryParameters: {
          'filter[scan_id][_eq]': scanId,
          'limit': 1,
          'sort': '-date_created',
          'fields': _scanResultFieldsLegacyMinimal,
        },
      );
      await _logResponse(
        method: 'GET',
        path: '/items/scan_results',
        status: response.statusCode,
        body: response.data,
      );
      return response;
    }
  }

  Future<Response<dynamic>> _fetchScanResultsByIdsWithFallback({
    required List<String> scanIds,
    required int limit,
    required String fields,
  }) async {
    try {
      final response = await DirectusClient.instance.client.get(
        '/items/scan_results',
        queryParameters: {
          'filter[scan_id][_in]': scanIds.join(','),
          'sort': '-date_created',
          'limit': limit,
          'fields': fields,
        },
      );
      await _logResponse(
        method: 'GET',
        path: '/items/scan_results',
        status: response.statusCode,
        body: response.data,
      );
      return response;
    } on DioException catch (error) {
      await _logError(method: 'GET', path: '/items/scan_results', e: error);
      final status = error.response?.statusCode ?? 0;
      if (status != 400 && status != 403 && status != 422) rethrow;
      final response = await DirectusClient.instance.client.get(
        '/items/scan_results',
        queryParameters: {
          'filter[scan_id][_in]': scanIds.join(','),
          'sort': '-date_created',
          'limit': limit,
          'fields': _scanResultFieldsLegacyMinimal,
        },
      );
      await _logResponse(
        method: 'GET',
        path: '/items/scan_results',
        status: response.statusCode,
        body: response.data,
      );
      return response;
    }
  }

  Future<_MemberSnapshot> _loadMemberSnapshot({
    required String memberId,
  }) async {
    final normalizedMemberId = memberId.trim();
    if (normalizedMemberId.isEmpty) return const _MemberSnapshot();

    const fieldAttempts = <String>[
      'member_role,department,department.id,department.name,shift_template,shift_template.id,shift_template.name',
      'member_role,department,department.name,shift_template,shift_template.name',
      'member_role,department,shift_template',
    ];
    for (final fields in fieldAttempts) {
      try {
        final response = await DirectusClient.instance.client.get(
          '/items/business_profile_members/$normalizedMemberId',
          queryParameters: {'fields': fields},
        );
        final data = response.data['data'];
        if (data is Map<String, dynamic>) {
          return _MemberSnapshot.fromJson(data);
        }
      } on DioException catch (e) {
        final status = e.response?.statusCode ?? 0;
        if (status == 400 || status == 403 || status == 404 || status == 422) {
          continue;
        }
        break;
      }
    }
    return const _MemberSnapshot();
  }

  dynamic _parseMemberId(String rawMemberId) {
    final numeric = int.tryParse(rawMemberId.trim());
    return numeric ?? rawMemberId.trim();
  }

  String _normalizeRequestSource(String rawValue) {
    final value = rawValue.trim().toLowerCase();
    switch (value) {
      case 'self':
      case 'manager_request':
      case 'scheduled':
      case 'bulk_request':
        return value;
      default:
        return 'self';
    }
  }

  String _normalizeDevicePlatform(String rawValue) {
    final value = rawValue.trim().toLowerCase();
    if (value.contains('android')) return 'android';
    if (value.contains('ios') || value.contains('iphone')) return 'ios';
    return 'web';
  }

  Future<_PreparedUploadFile> _prepareVideoUploadFile({
    required XFile file,
    required String scanId,
  }) async {
    final sourcePath = file.path.trim();
    final sourceSize = await _safeFileLength(file);
    if (sourcePath.isEmpty || sourceSize == null || sourceSize <= 0) {
      return _PreparedUploadFile(
        file: file,
        exists: false,
        sizeBytes: sourceSize,
        wasCompressed: false,
      );
    }

    final processedSource = await compressVideo(file);
    final processedSourceSize = await _safeFileLength(processedSource);
    final processedSizeValue = processedSourceSize ?? 0;
    final compressionPerformed =
        processedSource.path.trim() != sourcePath ||
        (processedSizeValue > 0 && processedSizeValue < sourceSize);

    debugPrint(
      '[SCAN_VIDEO] upload source selected '
      'has_scan_id=${scanId.trim().isNotEmpty} '
      'original_size=$sourceSize '
      'processed_size=$processedSizeValue '
      'compression_performed=$compressionPerformed',
    );

    final directory = await getTemporaryDirectory();
    final safeScanId = scanId.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
    final separator =
        directory.path.endsWith('\\') || directory.path.endsWith('/')
        ? ''
        : '/';
    final safePath =
        '${directory.path}$separator'
        'scan_video_$safeScanId.mp4';

    await processedSource.saveTo(safePath);

    final safeFile = XFile(
      safePath,
      mimeType: 'video/mp4',
      name: 'scan_video_$safeScanId.mp4',
    );
    final safeSize = await _safeFileLength(safeFile);

    return _PreparedUploadFile(
      file: safeFile,
      exists: safeSize != null && safeSize > 0,
      sizeBytes: safeSize,
      wasCompressed:
          compressionPerformed ||
          (safeSize != null && safeSize > _maxPreferredVideoUploadBytes),
    );
  }

  Future<int?> _safeFileLength(XFile file) async {
    try {
      return await file.length();
    } catch (_) {
      return null;
    }
  }

  String _absoluteUrl(String path) {
    final baseUrl = DirectusClient.instance.client.options.baseUrl;
    if (baseUrl.endsWith('/') && path.startsWith('/')) {
      return '${baseUrl.substring(0, baseUrl.length - 1)}$path';
    }
    if (!baseUrl.endsWith('/') && !path.startsWith('/')) {
      return '$baseUrl/$path';
    }
    return '$baseUrl$path';
  }

  void _logVideoUploadDiagnostics({
    required String requestUrl,
    required String sourcePath,
    required bool fileExists,
    required int fileSize,
    required String mimeType,
    required int retryCount,
    required bool compressionPerformed,
    required DioException error,
    required StackTrace stackTrace,
  }) {
    debugPrint('[ScanFlow] video file exists: $fileExists');
    debugPrint('[ScanFlow] video file size: $fileSize');
    debugPrint(
      '[ScanFlow] video file path_present=${sourcePath.trim().isNotEmpty}',
    );
    debugPrint('[ScanFlow] video mime type: $mimeType');
    debugPrint('[ScanFlow] video retry count: $retryCount');
    debugPrint('[ScanFlow] video compression performed: $compressionPerformed');
    debugPrint('[ScanFlow] multipart field name: file');
    debugPrint(
      '[ScanFlow] upload request path=/files request_url_present=${requestUrl.trim().isNotEmpty}',
    );
    debugPrint('[ScanFlow] video upload exception type: ${error.runtimeType}');
    debugPrint('[ScanFlow] video upload dio type: ${error.type}');
    debugPrint(
      '[ScanFlow] video upload timeout details: '
      'connect=${error.requestOptions.connectTimeout} '
      'send=${error.requestOptions.sendTimeout} '
      'receive=${error.requestOptions.receiveTimeout}',
    );
    debugPrint(
      '[ScanFlow] upload video status=${error.response?.statusCode ?? 0} error_type=${error.type}',
    );
    debugPrint(
      '[ScanFlow] video upload stack_present=${stackTrace.toString().isNotEmpty}',
    );
  }

  void _logVideoUploadUnexpectedFailure({
    required String requestUrl,
    required String sourcePath,
    required bool fileExists,
    required int fileSize,
    required String mimeType,
    required int retryCount,
    required bool compressionPerformed,
    required Object error,
    required StackTrace stackTrace,
  }) {
    debugPrint('[ScanFlow] video file exists: $fileExists');
    debugPrint('[ScanFlow] video file size: $fileSize');
    debugPrint(
      '[ScanFlow] video file path_present=${sourcePath.trim().isNotEmpty}',
    );
    debugPrint('[ScanFlow] video mime type: $mimeType');
    debugPrint('[ScanFlow] video retry count: $retryCount');
    debugPrint('[ScanFlow] video compression performed: $compressionPerformed');
    debugPrint('[ScanFlow] multipart field name: file');
    debugPrint(
      '[ScanFlow] upload request path=/files request_url_present=${requestUrl.trim().isNotEmpty}',
    );
    debugPrint('[ScanFlow] video upload exception type: ${error.runtimeType}');
    debugPrint('[ScanFlow] upload video status=0');
    debugPrint(
      '[ScanFlow] video upload stack_present=${stackTrace.toString().isNotEmpty}',
    );
  }

  void _logFileUploadDiagnostics({
    required String requestUrl,
    required String fileName,
    required String filePath,
    required bool fileExists,
    required int fileSize,
    required List<String> multipartFields,
    required DioException error,
    required StackTrace stackTrace,
  }) {
    debugPrint(
      '[SCAN_FILE_UPLOAD_ERROR] request_path=/files request_url_present=${requestUrl.trim().isNotEmpty} filename_present=${fileName.trim().isNotEmpty} file_path_present=${filePath.trim().isNotEmpty} file_exists=$fileExists file_size=$fileSize multipart_field_count=${multipartFields.length} dio_type=${error.type} status=${error.response?.statusCode}',
    );
    debugPrint(
      '[SCAN_FILE_UPLOAD_ERROR] timeouts connect=${error.requestOptions.connectTimeout} send=${error.requestOptions.sendTimeout} receive=${error.requestOptions.receiveTimeout}',
    );
    debugPrint(
      '[SCAN_FILE_UPLOAD_ERROR] stack_present=${stackTrace.toString().isNotEmpty}',
    );
  }

  bool _isTransientNetworkError(DioException e) {
    if (e.response != null) return false;
    switch (e.type) {
      case DioExceptionType.connectionError:
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.receiveTimeout:
      case DioExceptionType.sendTimeout:
        return true;
      default:
        return false;
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
      if (data['message'] != null) {
        return data['message'].toString();
      }
    }
    return e.message ?? 'Request failed';
  }

  String? _extractUploadedFileId(
    Response<dynamic> response, {
    required String requestPath,
  }) {
    final body = response.data;
    if (body is Map) {
      final nested = body['data'];
      if (nested is Map) {
        final id = nested['id']?.toString().trim();
        if (id != null && id.isNotEmpty) return id;
      }
      final directId = body['id']?.toString().trim();
      if (directId != null && directId.isNotEmpty) return directId;
    }

    final headerId = _extractFileIdFromHeaders(response.headers);
    if (headerId != null && headerId.isNotEmpty) return headerId;

    if (response.statusCode == 204 ||
        body == null ||
        body is String && body.trim().isEmpty) {
      return null;
    }

    return null;
  }

  String? _extractFileIdFromHeaders(Headers headers) {
    const headerNames = <String>['location', 'content-location', 'content-uri'];
    for (final name in headerNames) {
      final values = headers.map[name];
      if (values == null || values.isEmpty) continue;
      for (final raw in values) {
        final text = raw.trim();
        if (text.isEmpty) continue;
        final uri = Uri.tryParse(text);
        final segments = uri?.pathSegments ?? text.split('/');
        for (var i = segments.length - 1; i >= 0; i--) {
          final segment = segments[i].trim();
          if (segment.isNotEmpty) {
            return segment;
          }
        }
      }
    }
    return null;
  }

  DateTime? _tryDate(dynamic raw) {
    if (raw == null) return null;
    return DateTime.tryParse(raw.toString());
  }

  bool _isHistoryProcessingStatus(String status) {
    final normalized = status.trim().toLowerCase();
    return normalized == 'processing' ||
        normalized == 'in_progress' ||
        normalized == 'pending' ||
        normalized == 'media_ready' ||
        normalized == 'completed';
  }

  bool _isHistoryFailedStatus(String status) {
    final normalized = status.trim().toLowerCase();
    return normalized == 'failed' ||
        normalized == 'error' ||
        normalized == 'rejected' ||
        normalized == 'cancelled';
  }

  void _logDioError(String method, String endpoint, DioException e) {
    final status = e.response?.statusCode;
    debugPrint(
      '[API_ERROR] method=$method endpoint=$endpoint collection=wellness_scans/scan_results status=$status',
    );
  }

  Future<void> _logRequest({
    required String method,
    required String path,
    Map<String, dynamic>? query,
    Map<String, dynamic>? payload,
  }) async {
    final workspace = await OrganizationService.instance
        .fetchActiveWorkspaceContext();
    final logPath = _redactedLogPath(path);
    debugPrint(
      '[ScanFlow] has_current_user=${Session.instance.userId?.trim().isNotEmpty == true}',
    );
    debugPrint(
      '[ScanFlow] scoped_profile=${workspace?.businessProfileId.trim().isNotEmpty == true}',
    );
    debugPrint(
      '[ScanFlow] role=${workspace?.finalEffectiveRole ?? workspace?.memberRole ?? Session.instance.roleName}',
    );
    debugPrint('[ScanFlow] directus role=${workspace?.directusRoleName}');
    debugPrint(
      '[API_REQ] method=$method path=$logPath query_keys=${query?.keys.toList()} payload_keys=${payload?.keys.toList()} '
      'has_user=${Session.instance.userId?.trim().isNotEmpty == true} '
      'scoped_profile=${workspace?.businessProfileId.trim().isNotEmpty == true} has_membership=${workspace?.membershipId.trim().isNotEmpty == true} '
      'membership_role=${workspace?.memberRole} effective_role=${workspace?.finalEffectiveRole} '
      'directus_role=${workspace?.directusRoleName}',
    );
  }

  Future<void> _logResponse({
    required String method,
    required String path,
    required int? status,
    dynamic body,
  }) async {
    final session = Session.instance;
    final workspace = await OrganizationService.instance
        .fetchActiveWorkspaceContext();
    final bodyType = body?.runtimeType.toString() ?? 'null';
    final bodyKeys = body is Map ? body.keys.toList() : null;
    final logPath = _redactedLogPath(path);
    debugPrint(
      '[ScanFlow] response method=$method path=$logPath status=$status body_type=$bodyType',
    );
    debugPrint(
      '[API_RES] method=$method path=$logPath status=$status body_type=$bodyType body_keys=$bodyKeys '
      'has_user=${session.userId?.trim().isNotEmpty == true} '
      'scoped_profile=${workspace?.businessProfileId.trim().isNotEmpty == true} has_membership=${workspace?.membershipId.trim().isNotEmpty == true} '
      'membership_role=${workspace?.memberRole} effective_role=${workspace?.finalEffectiveRole} '
      'directus_role=${workspace?.directusRoleName}',
    );
  }

  void _logScanUploadResponse(Response<dynamic> response) {
    if (!kDebugMode) return;
    final hasFileId =
        _extractUploadedFileId(response, requestPath: '/files') != null;
    debugPrint(
      '[SCAN_UPLOAD_RESPONSE] status=${response.statusCode} body_type=${response.data.runtimeType} has_file_id=$hasFileId',
    );
  }

  void _logScanFileContract(Response<dynamic> response) {
    if (!kDebugMode) return;
    final requestHeaders = response.requestOptions.headers;
    final responseHeaders = response.headers;
    final hasFileId =
        _extractUploadedFileId(response, requestPath: '/files') != null;
    debugPrint(
      '[SCAN_FILE_CONTRACT] '
      'request_prefer=${_headerLogValue(requestHeaders, 'Prefer')} '
      'request_accept=${_headerLogValue(requestHeaders, 'Accept')} '
      'request_fields=${_queryLogValue(response.requestOptions, 'fields')} '
      'response_status=${response.statusCode} '
      'response_body_type=${response.data.runtimeType} '
      'response_location_present=${_responseHeaderPresent(responseHeaders, 'location')} '
      'response_content_location_present=${_responseHeaderPresent(responseHeaders, 'content-location')} '
      'response_content_uri_present=${_responseHeaderPresent(responseHeaders, 'content-uri')} '
      'response_has_file_id=$hasFileId',
    );
  }

  String _headerLogValue(Map<String, dynamic> headers, String name) {
    for (final entry in headers.entries) {
      if (entry.key.toLowerCase() == name.toLowerCase()) {
        final value = entry.value?.toString().trim();
        return value == null || value.isEmpty ? 'absent' : value;
      }
    }
    return 'absent';
  }

  String _queryLogValue(RequestOptions options, String name) {
    final value = options.queryParameters[name]?.toString().trim();
    return value == null || value.isEmpty ? 'absent' : value;
  }

  bool _responseHeaderPresent(Headers headers, String name) {
    final values = headers.map[name.toLowerCase()];
    if (values == null) return false;
    return values.any((value) => value.trim().isNotEmpty);
  }

  Future<void> _logError({
    required String method,
    required String path,
    required DioException e,
  }) async {
    final session = Session.instance;
    final workspace = await OrganizationService.instance
        .fetchActiveWorkspaceContext();
    final logPath = _redactedLogPath(path);
    debugPrint(
      '[ScanFlow] error method=$method path=$logPath status=${e.response?.statusCode} error_type=${e.type}',
    );
    debugPrint(
      '[API_ERR] method=$method path=$logPath status=${e.response?.statusCode} error_type=${e.type} '
      'has_user=${session.userId?.trim().isNotEmpty == true} '
      'scoped_profile=${workspace?.businessProfileId.trim().isNotEmpty == true} has_membership=${workspace?.membershipId.trim().isNotEmpty == true} '
      'membership_role=${workspace?.memberRole} effective_role=${workspace?.finalEffectiveRole} '
      'directus_role=${workspace?.directusRoleName}',
    );
  }

  String _redactedLogPath(String path) {
    if (!path.startsWith('/items/')) return path;
    final parts = path.split('/');
    if (parts.length <= 3) return path;
    return '${parts.take(3).join('/')}/:id';
  }
}

class _MemberSnapshot {
  final String? memberRole;
  final String? departmentId;
  final String? departmentName;
  final String? shiftTemplateName;

  const _MemberSnapshot({
    this.memberRole,
    this.departmentId,
    this.departmentName,
    this.shiftTemplateName,
  });

  factory _MemberSnapshot.fromJson(Map<String, dynamic> json) {
    final department = json['department'];
    final shiftTemplate = json['shift_template'];

    String? departmentId;
    String? departmentName;
    if (department is Map) {
      departmentId = department['id']?.toString().trim();
      departmentName = department['name']?.toString().trim();
    } else if (department != null) {
      departmentId = department.toString().trim();
    }

    String? shiftTemplateName;
    if (shiftTemplate is Map) {
      shiftTemplateName = shiftTemplate['name']?.toString().trim();
    }

    return _MemberSnapshot(
      memberRole: json['member_role']?.toString().trim(),
      departmentId: departmentId,
      departmentName: departmentName,
      shiftTemplateName: shiftTemplateName,
    );
  }
}

class WellnessScanStatus {
  final String id;
  final String status;
  final String? failureReason;
  final DateTime? completedAt;
  final DateTime? dateUpdated;

  const WellnessScanStatus({
    required this.id,
    required this.status,
    required this.failureReason,
    required this.completedAt,
    required this.dateUpdated,
  });

  bool get isCompleted => status == 'completed';
  bool get isFailed =>
      status == 'failed' ||
      status == 'error' ||
      status == 'rejected' ||
      status == 'cancelled';

  factory WellnessScanStatus.fromJson(Map<String, dynamic> json) {
    return WellnessScanStatus(
      id: json['id']?.toString() ?? '',
      status: json['status']?.toString().trim().toLowerCase() ?? '',
      failureReason: json['failure_reason']?.toString().trim(),
      completedAt: json['completed_at'] == null
          ? null
          : DateTime.tryParse(json['completed_at'].toString()),
      dateUpdated: json['date_updated'] == null
          ? null
          : DateTime.tryParse(json['date_updated'].toString()),
    );
  }
}

class _PreparedUploadFile {
  final XFile file;
  final bool exists;
  final int? sizeBytes;
  final bool wasCompressed;

  const _PreparedUploadFile({
    required this.file,
    required this.exists,
    required this.sizeBytes,
    required this.wasCompressed,
  });
}

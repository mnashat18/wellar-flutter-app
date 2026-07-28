import 'dart:io';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import '../models/report_export.dart';
import '../state/session.dart';
import 'directus_client.dart';
import 'organization_service.dart';
import 'scan_service.dart';

class ReportService {
  ReportService._();

  static final ReportService instance = ReportService._();

  Dio get _client => DirectusClient.instance.client;

  Future<String> createExport({
    required String format,
    Map<String, dynamic>? filters,
  }) async {
    final userId = Session.instance.userId;
    if (userId == null || userId.isEmpty) {
      throw Exception('User not logged in');
    }
    final businessProfileId = await OrganizationService.instance
        .fetchPrimaryBusinessProfileId();
    final workspace = await OrganizationService.instance.fetchActiveWorkspaceContext();
    final trace = OrganizationService.instance.activeSwitchTrace ?? 'none';

    final payload = <String, dynamic>{
      'user': userId,
      if (businessProfileId != null && businessProfileId.isNotEmpty)
        'business_profile': businessProfileId,
      'format': format.toLowerCase(),
      'status': 'pending',
      if (filters != null) 'filters': filters,
    };
    debugPrint(
      '[SCOPED_DATA_REQUEST] feature=reports operation=create_export method=POST endpoint_or_collection=/items/reports_exports membership_id=${workspace?.membershipId.trim() ?? ''} business_profile=${businessProfileId ?? ''} department=${workspace?.departmentId?.trim() ?? ''} membership_role=${workspace?.memberRole ?? ''} context_source=${OrganizationService.instance.activeWorkspaceContextSource} workspace_revision=${OrganizationService.instance.workspaceRevision} filter_summary=format=$format;status=pending started=true trace=$trace',
    );
    Response response;
    try {
      response = await _client.post('/items/reports_exports', data: payload);
    } on DioException catch (e) {
      final message = _extractMessage(e).toLowerCase();
      if (message.contains('business_profile') &&
          message.contains('does not exist')) {
        final fallback = Map<String, dynamic>.from(payload)
          ..remove('business_profile');
        response = await _client.post('/items/reports_exports', data: fallback);
      } else {
        rethrow;
      }
    }
    final data = response.data['data'] as Map<String, dynamic>;
    debugPrint(
      '[SCOPED_DATA_RESPONSE] feature=reports operation=create_export http_status=${response.statusCode ?? 0} result_count=1 duration_ms=0 membership_id=${workspace?.membershipId.trim() ?? ''} business_profile=${businessProfileId ?? ''} workspace_revision_before=${OrganizationService.instance.workspaceRevision} workspace_revision_after=${OrganizationService.instance.workspaceRevision} context_unchanged=true returned_business_profile_ids=[${businessProfileId ?? ''}] returned_membership_ids=[${workspace?.membershipId.trim() ?? ''}] empty_result=false trace=$trace',
    );
    return data['id'].toString();
  }

  Future<String> uploadFileBytes({
    required Uint8List bytes,
    required String filename,
  }) async {
    final formData = FormData.fromMap({
      'file': MultipartFile.fromBytes(bytes, filename: filename),
    });
    final response = await _client.post('/files', data: formData);
    final data = response.data['data'] as Map<String, dynamic>;
    return data['id'].toString();
  }

  Future<void> finalizeExport({
    required String exportId,
    required String status,
    String? fileId,
    String? errorMessage,
  }) async {
    final payload = {
      'status': status,
      if (fileId != null) 'file': fileId,
      if (status.toLowerCase() == 'ready')
        'completed_at': DateTime.now().toUtc().toIso8601String(),
      if (errorMessage != null) 'error_message': errorMessage,
    };
    try {
      await _client.patch('/items/reports_exports/$exportId', data: payload);
    } on DioException catch (e) {
      final message = _extractMessage(e).toLowerCase();
      if (message.contains('error_message') &&
          message.contains('does not exist')) {
        final fallback = Map<String, dynamic>.from(payload)
          ..remove('error_message');
        await _client.patch('/items/reports_exports/$exportId', data: fallback);
        return;
      }
      rethrow;
    }
  }

  Future<List<ReportExport>> fetchExports({int limit = 20}) async {
    final userId = Session.instance.userId;
    final isAdmin = Session.instance.isAdmin;
    final businessProfileId = await OrganizationService.instance
        .fetchPrimaryBusinessProfileId();
    final workspace = await OrganizationService.instance.fetchActiveWorkspaceContext();
    final trace = OrganizationService.instance.activeSwitchTrace ?? 'none';
    final query = <String, dynamic>{
      'sort': '-date_created',
      'limit': limit,
      'fields':
          'id,format,status,file,file.id,user,user.id,business_profile,business_profile.id,'
          'filters,date_created,completed_at',
    };
    if (businessProfileId != null && businessProfileId.isNotEmpty) {
      query['filter[business_profile][_eq]'] = businessProfileId;
    }
    if (!isAdmin && userId != null && userId.isNotEmpty) {
      if (query.containsKey('filter[business_profile][_eq]')) {
        query['filter[_or][0][user][_eq]'] = userId;
        query['filter[_or][1][user][id][_eq]'] = userId;
      } else {
        query['filter[user][_eq]'] = userId;
      }
    }
    debugPrint(
      '[SCOPED_DATA_REQUEST] feature=reports operation=fetch_exports method=GET endpoint_or_collection=/items/reports_exports membership_id=${workspace?.membershipId.trim() ?? ''} business_profile=${businessProfileId ?? ''} department=${workspace?.departmentId?.trim() ?? ''} membership_role=${workspace?.memberRole ?? ''} context_source=${OrganizationService.instance.activeWorkspaceContextSource} workspace_revision=${OrganizationService.instance.workspaceRevision} filter_summary=${query.entries.map((e) => '${e.key}=${e.value}').toList()} started=true trace=$trace',
    );
    try {
      final response = await _client.get(
        '/items/reports_exports',
        queryParameters: query,
      );
      final data = response.data['data'];
      if (data is List) {
        debugPrint(
          '[SCOPED_DATA_RESPONSE] feature=reports operation=fetch_exports http_status=${response.statusCode ?? 0} result_count=${data.length} duration_ms=0 membership_id=${workspace?.membershipId.trim() ?? ''} business_profile=${businessProfileId ?? ''} workspace_revision_before=${OrganizationService.instance.workspaceRevision} workspace_revision_after=${OrganizationService.instance.workspaceRevision} context_unchanged=true returned_business_profile_ids=${data.whereType<Map<String, dynamic>>().map((row) => row['business_profile']?.toString().trim() ?? '').where((v) => v.isNotEmpty).toSet().toList()} returned_membership_ids=${data.whereType<Map<String, dynamic>>().map((row) => row['user']?.toString().trim() ?? '').where((v) => v.isNotEmpty).toSet().toList()} empty_result=${data.isEmpty} trace=$trace',
        );
        return data
            .whereType<Map<String, dynamic>>()
            .map(ReportExport.fromJson)
            .toList();
      }
      debugPrint(
        '[SCOPED_DATA_RESPONSE] feature=reports operation=fetch_exports http_status=${response.statusCode ?? 0} result_count=0 duration_ms=0 membership_id=${workspace?.membershipId.trim() ?? ''} business_profile=${businessProfileId ?? ''} workspace_revision_before=${OrganizationService.instance.workspaceRevision} workspace_revision_after=${OrganizationService.instance.workspaceRevision} context_unchanged=true returned_business_profile_ids=[] returned_membership_ids=[] empty_result=true trace=$trace',
      );
      return const [];
    } on DioException catch (e) {
      final status = e.response?.statusCode ?? 0;
      debugPrint(
        '[SCOPED_DATA_ERROR] feature=reports operation=fetch_exports http_status=$status error_type=${e.type} failure_code=${status == 403 ? 'scoped_data_403' : status == 401 ? 'scoped_data_401' : 'scoped_data_network_error'} duration_ms=0 membership_id=${workspace?.membershipId.trim() ?? ''} business_profile=${businessProfileId ?? ''} membership_role=${workspace?.memberRole ?? ''} workspace_revision_before=${OrganizationService.instance.workspaceRevision} workspace_revision_after=${OrganizationService.instance.workspaceRevision} context_unchanged=true trace=$trace',
      );
      if (status == 400 || status == 403 || status == 404 || status == 405) {
        return const [];
      }
      rethrow;
    }
  }

  Future<ReportExport?> fetchExportById(String exportId) async {
    final workspace = await OrganizationService.instance.fetchActiveWorkspaceContext();
    final trace = OrganizationService.instance.activeSwitchTrace ?? 'none';
    try {
      debugPrint(
        '[SCOPED_DATA_REQUEST] feature=reports operation=fetch_export_by_id method=GET endpoint_or_collection=/items/reports_exports/$exportId membership_id=${workspace?.membershipId.trim() ?? ''} business_profile=${workspace?.businessProfileId.trim() ?? ''} department=${workspace?.departmentId?.trim() ?? ''} membership_role=${workspace?.memberRole ?? ''} context_source=${OrganizationService.instance.activeWorkspaceContextSource} workspace_revision=${OrganizationService.instance.workspaceRevision} filter_summary=fields=id,format,status,file,user,business_profile started=true trace=$trace',
      );
      final response = await _client.get(
        '/items/reports_exports/$exportId',
        queryParameters: {
          'fields':
              'id,format,status,file,file.id,user,user.id,business_profile,business_profile.id,'
              'filters,date_created,completed_at',
        },
      );
      final data = response.data['data'];
      if (data is Map<String, dynamic>) {
        debugPrint(
          '[SCOPED_DATA_RESPONSE] feature=reports operation=fetch_export_by_id http_status=${response.statusCode ?? 0} result_count=1 duration_ms=0 membership_id=${workspace?.membershipId.trim() ?? ''} business_profile=${workspace?.businessProfileId.trim() ?? ''} workspace_revision_before=${OrganizationService.instance.workspaceRevision} workspace_revision_after=${OrganizationService.instance.workspaceRevision} context_unchanged=true returned_business_profile_ids=${data['business_profile'] == null ? const [] : [data['business_profile'].toString().trim()]} returned_membership_ids=${data['user'] == null ? const [] : [data['user'].toString().trim()]} empty_result=false trace=$trace',
        );
        return ReportExport.fromJson(data);
      }
      debugPrint(
        '[SCOPED_DATA_RESPONSE] feature=reports operation=fetch_export_by_id http_status=${response.statusCode ?? 0} result_count=0 duration_ms=0 membership_id=${workspace?.membershipId.trim() ?? ''} business_profile=${workspace?.businessProfileId.trim() ?? ''} workspace_revision_before=${OrganizationService.instance.workspaceRevision} workspace_revision_after=${OrganizationService.instance.workspaceRevision} context_unchanged=true returned_business_profile_ids=[] returned_membership_ids=[] empty_result=true trace=$trace',
      );
      return null;
    } on DioException catch (e) {
      final status = e.response?.statusCode ?? 0;
      debugPrint(
        '[SCOPED_DATA_ERROR] feature=reports operation=fetch_export_by_id http_status=$status error_type=${e.type} failure_code=${status == 403 ? 'scoped_data_403' : status == 401 ? 'scoped_data_401' : 'scoped_data_network_error'} duration_ms=0 membership_id=${workspace?.membershipId.trim() ?? ''} business_profile=${workspace?.businessProfileId.trim() ?? ''} membership_role=${workspace?.memberRole ?? ''} workspace_revision_before=${OrganizationService.instance.workspaceRevision} workspace_revision_after=${OrganizationService.instance.workspaceRevision} context_unchanged=true trace=$trace',
      );
      if (status == 400 || status == 403 || status == 404 || status == 405) {
        return null;
      }
      rethrow;
    }
  }

  Future<void> openPrivateFile(String fileId) async {
    final resolvedFileId = fileId.trim();
    if (resolvedFileId.isEmpty) {
      throw const ReportFileOpenException('Unable to open export file');
    }

    final metadata = await _fetchFileMetadata(resolvedFileId);
    final bytes = await _downloadFileBytes(resolvedFileId);
    final localFile = await _writeTempFile(
      fileId: resolvedFileId,
      bytes: bytes,
      metadata: metadata,
    );

    final result = await OpenFilex.open(localFile.path);
    if (result.type != ResultType.done) {
      throw const ReportFileOpenException('Unable to open export file');
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

  Future<_DirectusFileMetadata?> _fetchFileMetadata(String fileId) async {
    try {
      final response = await _client.get(
        '/files/$fileId',
        queryParameters: {
          'fields': 'id,filename_download,title,type,charset,filesize',
        },
      );
      final data = response.data['data'];
      if (data is! Map<String, dynamic>) {
        return null;
      }
      return _DirectusFileMetadata.fromJson(data);
    } on DioException catch (e) {
      final status = e.response?.statusCode ?? 0;
      if (status == 401) {
        throw const UnauthenticatedException('Session expired. Please login.');
      }
      if (status == 403 || status == 404) {
        throw const ReportFileOpenException('Export file is not available.');
      }
      if (_isNetworkError(e)) {
        throw const ReportFileOpenException(
          'Unable to download export file. Check your connection and try again.',
        );
      }
      throw const ReportFileOpenException('Unable to open export file');
    }
  }

  Future<Uint8List> _downloadFileBytes(String fileId) async {
    final assetPath = '/assets/$fileId';
    try {
      final response = await _client.get<List<int>>(
        assetPath,
        options: Options(responseType: ResponseType.bytes),
      );
      final data = response.data;
      if (data == null || data.isEmpty) {
        throw const ReportFileOpenException('Export file is empty.');
      }
      return Uint8List.fromList(data);
    } on DioException catch (e) {
      final status = e.response?.statusCode ?? 0;
      if (status == 401) {
        throw const UnauthenticatedException('Session expired. Please login.');
      }
      if (status == 403) {
        throw const ReportFileOpenException('You do not have access to this export file.');
      }
      if (status == 404) {
        throw const ReportFileOpenException('Export file was not found.');
      }
      if (_isNetworkError(e)) {
        throw const ReportFileOpenException(
          'Unable to download export file. Check your connection and try again.',
        );
      }
      throw const ReportFileOpenException('Unable to download export file.');
    }
  }

  Future<File> _writeTempFile({
    required String fileId,
    required Uint8List bytes,
    required _DirectusFileMetadata? metadata,
  }) async {
    final directory = await getTemporaryDirectory();
    final filename = _resolveDownloadFilename(fileId: fileId, metadata: metadata);
    final file = File('${directory.path}${Platform.pathSeparator}$filename');
    await file.writeAsBytes(bytes, flush: true);
    return file;
  }

  String _resolveDownloadFilename({
    required String fileId,
    required _DirectusFileMetadata? metadata,
  }) {
    final preferred = metadata?.filenameDownload ?? metadata?.title;
    final sanitizedBase = _sanitizeFilename(preferred);
    if (sanitizedBase != null) {
      return sanitizedBase;
    }

    final extension = _extensionFromMimeType(metadata?.type) ?? 'bin';
    return 'report_$fileId.$extension';
  }

  String? _sanitizeFilename(String? value) {
    final trimmed = value?.trim();
    if (trimmed == null || trimmed.isEmpty) return null;
    final sanitized = trimmed.replaceAll(RegExp(r'[<>:"/\\|?*]'), '_');
    return sanitized.isEmpty ? null : sanitized;
  }

  String? _extensionFromMimeType(String? mimeType) {
    switch (mimeType?.toLowerCase().trim()) {
      case 'application/pdf':
        return 'pdf';
      case 'text/csv':
        return 'csv';
      case 'text/plain':
        return 'txt';
      case 'application/json':
        return 'json';
      default:
        return null;
    }
  }

  bool _isNetworkError(DioException e) {
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
}

class ReportFileOpenException implements Exception {
  final String message;

  const ReportFileOpenException(this.message);

  @override
  String toString() => message;
}

class _DirectusFileMetadata {
  final String? filenameDownload;
  final String? title;
  final String? type;

  const _DirectusFileMetadata({
    required this.filenameDownload,
    required this.title,
    required this.type,
  });

  factory _DirectusFileMetadata.fromJson(Map<String, dynamic> json) {
    return _DirectusFileMetadata(
      filenameDownload: json['filename_download']?.toString(),
      title: json['title']?.toString(),
      type: json['type']?.toString(),
    );
  }
}

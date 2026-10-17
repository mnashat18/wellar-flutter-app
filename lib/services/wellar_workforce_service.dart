import 'package:dio/dio.dart';

import '../utils/safe_debug_log.dart';
import 'directus_client.dart';

class WellarWorkforceResult {
  final int httpStatus;
  final Map<String, dynamic> active;
  final Map<String, dynamic> permissions;
  final List<Map<String, dynamic>> departments;
  final List<Map<String, dynamic>> rows;
  final List<Map<String, dynamic>> eligibleScanTargets;
  final List<Map<String, dynamic>> scanRequestRows;
  final Map<String, dynamic> scanRequestSummary;
  final Map<String, dynamic> summary;
  final bool networkError;

  const WellarWorkforceResult({
    required this.httpStatus,
    required this.active,
    required this.permissions,
    required this.departments,
    required this.rows,
    required this.eligibleScanTargets,
    required this.scanRequestRows,
    required this.scanRequestSummary,
    required this.summary,
    required this.networkError,
  });

  int get memberRowCount =>
      rows.where((row) => row['type']?.toString() == 'member').length;

  List<Map<String, dynamic>> get memberRows => rows
      .where((row) => row['type']?.toString() == 'member')
      .toList(growable: false);

  bool get isSuccessful => httpStatus >= 200 && httpStatus < 300;

  int get activeMemberCount {
    final value = summary['activeMembers'];
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  int summaryCount(String key) {
    final value = summary[key];
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  DioException asFailure() => DioException(
    requestOptions: RequestOptions(path: '/wellar/workforce'),
    response: Response<dynamic>(
      requestOptions: RequestOptions(path: '/wellar/workforce'),
      statusCode: httpStatus == 0 ? null : httpStatus,
    ),
    type: DioExceptionType.badResponse,
  );
}

class WellarWorkforceService {
  WellarWorkforceService._();

  static final WellarWorkforceService instance = WellarWorkforceService._();

  Future<WellarWorkforceResult> fetchWorkforceFromWellar() async {
    try {
      final response = await DirectusClient.instance.client.get(
        '/wellar/workforce',
      );
      final result = _parse(response.data, response.statusCode ?? 0);
      _logResult(result);
      return result;
    } on DioException catch (error) {
      final result = _parse(
        error.response?.data,
        error.response?.statusCode ?? 0,
        networkError: error.response == null && _isNetworkError(error),
      );
      _logResult(result);
      return result;
    } catch (_) {
      const result = WellarWorkforceResult(
        httpStatus: 0,
        active: <String, dynamic>{},
        permissions: <String, dynamic>{},
        departments: <Map<String, dynamic>>[],
        rows: <Map<String, dynamic>>[],
        eligibleScanTargets: <Map<String, dynamic>>[],
        scanRequestRows: <Map<String, dynamic>>[],
        scanRequestSummary: <String, dynamic>{},
        summary: <String, dynamic>{},
        networkError: false,
      );
      _logResult(result);
      return result;
    }
  }

  WellarWorkforceResult _parse(
    dynamic raw,
    int status, {
    bool networkError = false,
  }) {
    final root = _asMap(raw) ?? const <String, dynamic>{};
    final data = _asMap(root['data']) ?? const <String, dynamic>{};
    final scanRequests =
        _asMap(data['scan_requests']) ?? const <String, dynamic>{};
    return WellarWorkforceResult(
      httpStatus: status,
      active: _asMap(data['active']) ?? const <String, dynamic>{},
      permissions: _asMap(data['permissions']) ?? const <String, dynamic>{},
      departments: _asMapList(data['departments']),
      rows: _asMapList(data['rows']),
      eligibleScanTargets: _asMapList(data['eligible_scan_targets']),
      scanRequestRows: _asMapList(scanRequests['rows']),
      scanRequestSummary:
          _asMap(scanRequests['summary']) ?? const <String, dynamic>{},
      summary: _asMap(data['summary']) ?? const <String, dynamic>{},
      networkError: networkError,
    );
  }

  void _logResult(WellarWorkforceResult result) {
    safeDebugLog(
      '[WELLAR_WORKFORCE] http_status=${result.httpStatus} rows=${result.rows.length} member_rows=${result.memberRowCount} summary_active=${result.activeMemberCount}',
    );
  }

  Map<String, dynamic>? _asMap(dynamic value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) {
      final converted = <String, dynamic>{};
      for (final entry in value.entries) {
        if (entry.key is String) {
          converted[entry.key as String] = entry.value;
        }
      }
      return converted;
    }
    return null;
  }

  List<Map<String, dynamic>> _asMapList(dynamic value) {
    if (value is! List) return const [];
    return value.map(_asMap).whereType<Map<String, dynamic>>().toList();
  }

  bool _isNetworkError(DioException error) {
    return switch (error.type) {
      DioExceptionType.connectionError ||
      DioExceptionType.connectionTimeout ||
      DioExceptionType.receiveTimeout ||
      DioExceptionType.sendTimeout => true,
      _ => false,
    };
  }
}

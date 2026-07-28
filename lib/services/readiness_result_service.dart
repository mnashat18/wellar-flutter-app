import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import 'directus_client.dart';

class ReadinessResultService {
  ReadinessResultService._();
  static final ReadinessResultService instance = ReadinessResultService._();

  Dio get _client => DirectusClient.instance.client;
  bool _scanResultsReadDenied = false;

  static const List<String> _fieldCandidates = [
    'scan_id,readiness_label,date_created',
    'scan_id,readiness_state,date_created',
    'scan_id,overall_state,date_created',
    'scan_id,state,date_created',
  ];

  Future<Map<String, String>> fetchLabelByScanIds(List<String> scanIds) async {
    final ids = scanIds.where((e) => e.trim().isNotEmpty).toList();
    if (ids.isEmpty || _scanResultsReadDenied) return const {};

    for (final fields in _fieldCandidates) {
      try {
        final response = await _client.get(
          '/items/scan_results',
          queryParameters: {
            'limit': 800,
            'sort': '-date_created',
            'fields': fields,
            'filter[scan_id][_in]': ids.join(','),
          },
        );
        final data = response.data['data'];
        if (data is! List) return const {};
        final map = <String, String>{};
        for (final row in data.whereType<Map<String, dynamic>>()) {
          final scanId = row['scan_id']?.toString() ?? '';
          if (scanId.isEmpty || map.containsKey(scanId)) continue;
          final raw = _extractLabel(row);
          final normalized = normalizeReadinessLabel(raw);
          if (normalized.isNotEmpty) {
            map[scanId] = normalized;
          }
        }
        return map;
      } on DioException catch (e) {
        final status = e.response?.statusCode ?? 0;
        final recoverable = status == 400 || status == 403 || status == 404;
        if (status == 403) {
          _scanResultsReadDenied = true;
          debugPrint(
            '[SCAN_RESULTS] permission unavailable status=403 fields=$fields',
          );
          return const {};
        }
        debugPrint(
          '[SCAN_RESULTS] label attempt failed fields=$fields status=$status',
        );
        if (!recoverable) rethrow;
      }
    }
    return const {};
  }

  String _extractLabel(Map<String, dynamic> row) {
    final keys = ['readiness_label', 'readiness_state', 'overall_state', 'state'];
    for (final key in keys) {
      final value = row[key]?.toString().trim() ?? '';
      if (value.isNotEmpty) return value;
    }
    return '';
  }

  static String normalizeReadinessLabel(String value) {
    final v = value.trim().toLowerCase();
    if (v == 'stable') return 'Stable';
    if (v == 'low focus' || v == 'low_focus') return 'Low Focus';
    if (v == 'elevated fatigue' || v == 'elevated_fatigue') {
      return 'Elevated Fatigue';
    }
    if (v == 'high risk' || v == 'high_risk') return 'High Risk';
    return '';
  }
}

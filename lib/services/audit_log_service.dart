import 'dart:convert';

import 'package:dio/dio.dart';

import '../models/audit_log.dart';
import '../state/session.dart';
import 'directus_client.dart';

class AuditLogService {
  AuditLogService._();

  static final AuditLogService instance = AuditLogService._();
  static const String _endpoint = '/items/audit_logs';

  Future<List<AuditLog>> fetchLogs({
    int limit = 20,
    bool includeSystemLogs = false,
  }) async {
    final userId = Session.instance.userId;
    if (userId == null || userId.isEmpty) {
      return const [];
    }

    final baseFilter = <String, dynamic>{'filter[user][_eq]': userId};
    final typeFilter = !includeSystemLogs
        ? <String, dynamic>{'filter[type][_nstarts_with]': 'request_'}
        : const <String, dynamic>{};

    final queryAttempts = <Map<String, dynamic>>[
      {
        'sort': '-timestamp',
        'limit': limit,
        'fields':
            'id,user,user.id,user.email,type,description,metadata,timestamp',
        ...baseFilter,
        ...typeFilter,
      },
      {
        'sort': '-timestamp',
        'limit': limit,
        'fields': 'id,user,type,description,metadata,timestamp',
        ...baseFilter,
        ...typeFilter,
      },
      {
        'limit': limit,
        'fields': 'id,user,type,description,metadata,timestamp',
        'filter[user][id][_eq]': userId,
        ...typeFilter,
      },
      {
        'sort': '-timestamp',
        'limit': limit,
        'fields':
            'id,user,user.id,user.email,type,description,metadata,timestamp',
        ...baseFilter,
      },
      {
        'sort': '-timestamp',
        'limit': limit,
        'fields': 'id,user,type,description,metadata,timestamp',
        ...baseFilter,
      },
      {
        'limit': limit,
        'fields': 'id,user,type,description,metadata,timestamp',
        'filter[user][id][_eq]': userId,
      },
    ];

    DioException? lastError;
    for (final query in queryAttempts) {
      try {
        final response = await DirectusClient.instance.client.get(
          _endpoint,
          queryParameters: query,
        );
        return _filterVisibleLogs(
          _parseLogs(response.data['data']),
          includeSystemLogs: includeSystemLogs,
        );
      } on DioException catch (e) {
        lastError = e;
        final status = e.response?.statusCode ?? 0;
        if (status == 401 || status == 403) {
          return const [];
        }
        if (_isQueryFieldIssue(e)) {
          continue;
        }
        rethrow;
      }
    }

    if (lastError != null) {
      final status = lastError.response?.statusCode ?? 0;
      if (status == 401 || status == 403) {
        return const [];
      }
    }
    return const [];
  }

  Future<void> createLog({
    required String type,
    required String description,
    String? metadataJson,
  }) async {
    final userId = Session.instance.userId;
    if (userId == null) {
      throw Exception('User not logged in');
    }

    Map<String, dynamic>? metadata;
    if (metadataJson != null && metadataJson.trim().isNotEmpty) {
      metadata = jsonDecode(metadataJson) as Map<String, dynamic>;
    }

    await DirectusClient.instance.client.post(
      _endpoint,
      data: {
        'user': userId,
        'type': type,
        'description': description,
        'metadata': metadata,
        'timestamp': DateTime.now().toUtc().toIso8601String(),
      },
    );
  }

  Future<void> replyToLog({
    required AuditLog log,
    required String reply,
  }) async {
    final metadata = Map<String, dynamic>.from(log.metadata ?? {});
    metadata['admin_reply'] = reply;
    metadata['admin_reply_at'] = DateTime.now().toUtc().toIso8601String();
    metadata['admin_reply_by'] = Session.instance.userId;

    await DirectusClient.instance.client.patch(
      '$_endpoint/${log.id}',
      data: {'metadata': metadata},
    );
  }

  List<AuditLog> _parseLogs(dynamic raw) {
    if (raw is! List) return const [];
    return raw
        .whereType<Map<String, dynamic>>()
        .map(AuditLog.fromJson)
        .toList();
  }

  List<AuditLog> _filterVisibleLogs(
    List<AuditLog> logs, {
    required bool includeSystemLogs,
  }) {
    if (includeSystemLogs) return logs;
    return logs.where((log) {
      final type = log.type.trim().toLowerCase();
      if (type.isEmpty) return true;
      if (type.startsWith('request_')) return false;
      if (type == 'request') return false;
      return true;
    }).toList();
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

  bool _isQueryFieldIssue(DioException e) {
    final message = _extractMessage(e).toLowerCase();
    return message.contains('field') ||
        message.contains('does not exist') ||
        message.contains('unknown') ||
        message.contains('invalid query');
  }
}

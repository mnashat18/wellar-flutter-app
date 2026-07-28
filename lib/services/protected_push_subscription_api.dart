import 'package:dio/dio.dart';

import 'directus_client.dart';

class ProtectedPushSubscriptionPayload {
  final String token;
  final String userId;
  final String businessProfileId;
  final String deviceId;
  final String platform;
  final String deviceLabel;
  final String? appVersion;
  final String? osVersion;

  const ProtectedPushSubscriptionPayload({
    required this.token,
    required this.userId,
    required this.businessProfileId,
    required this.deviceId,
    required this.platform,
    required this.deviceLabel,
    this.appVersion,
    this.osVersion,
  });

  Map<String, dynamic> toJson() {
    return {
      'token': token.trim(),
      'device_id': deviceId.trim(),
      'platform': platform.trim(),
      'device_label': deviceLabel.trim(),
      if (appVersion != null && appVersion!.trim().isNotEmpty)
        'app_version': appVersion!.trim(),
      if (osVersion != null && osVersion!.trim().isNotEmpty)
        'os_version': osVersion!.trim(),
    };
  }
}

class PushSubscriptionSyncResult {
  final int? statusCode;
  final String subscriptionResult;
  final bool lastSeenUpdated;
  final bool ok;

  const PushSubscriptionSyncResult({
    required this.statusCode,
    required this.subscriptionResult,
    required this.lastSeenUpdated,
    required this.ok,
  });
}

class ProtectedPushSubscriptionApiException implements Exception {
  final String path;
  final int? statusCode;
  final String message;

  const ProtectedPushSubscriptionApiException({
    required this.path,
    required this.statusCode,
    required this.message,
  });

  bool get isUnavailable => statusCode == 404;
  bool get isAccessDenied => statusCode == 401 || statusCode == 403;

  @override
  String toString() =>
      'ProtectedPushSubscriptionApiException($statusCode): $message';
}

class ProtectedPushSubscriptionApi {
  static const String syncPath = '/wellar-push-subscriptions/sync';
  static const String revokePath = '/wellar-push-subscriptions/revoke';

  final Dio _client;

  ProtectedPushSubscriptionApi({Dio? client})
      : _client = client ?? DirectusClient.instance.client;

  Future<PushSubscriptionSyncResult> sync(
    ProtectedPushSubscriptionPayload payload,
  ) async {
    try {
      final response = await _client.post(
        syncPath,
        data: payload.toJson(),
      );
      final ok = _responseBodyConfirmsOk(response.data);
      if (!ok) {
        throw ProtectedPushSubscriptionApiException(
          path: syncPath,
          statusCode: response.statusCode,
          message: 'SYNC_RESPONSE_MISSING_OK',
        );
      }
      return PushSubscriptionSyncResult(
        statusCode: response.statusCode,
        subscriptionResult: 'synced',
        lastSeenUpdated: _responseWasSuccessful(response) && ok,
        ok: ok,
      );
    } on DioException catch (e) {
      throw ProtectedPushSubscriptionApiException(
        path: syncPath,
        statusCode: e.response?.statusCode,
        message: _extractMessage(e),
      );
    }
  }

  Future<void> revoke({required String deviceId}) async {
    try {
      final response = await _client.post(
        revokePath,
        data: <String, dynamic>{
          'device_id': deviceId.trim(),
        },
      );
      if (!_responseBodyConfirmsOk(response.data)) {
        throw ProtectedPushSubscriptionApiException(
          path: revokePath,
          statusCode: response.statusCode,
          message: 'REVOKE_RESPONSE_MISSING_OK',
        );
      }
    } on DioException catch (e) {
      throw ProtectedPushSubscriptionApiException(
        path: revokePath,
        statusCode: e.response?.statusCode,
        message: _extractMessage(e),
      );
    }
  }

  bool _responseWasSuccessful(Response<dynamic> response) {
    final status = response.statusCode ?? 0;
    return status >= 200 && status < 300;
  }

  bool _responseBodyConfirmsOk(dynamic body) {
    if (body is Map) {
      final directOk = body['ok'];
      if (directOk is bool) return directOk;

      final nestedData = body['data'];
      if (nestedData is Map) {
        final nestedOk = nestedData['ok'];
        if (nestedOk is bool) return nestedOk;
      }
    }
    return false;
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
    return e.message ?? 'Push sync failed';
  }
}

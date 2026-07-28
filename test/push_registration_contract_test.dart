import 'package:flutter_test/flutter_test.dart';

import 'package:waller_app/config/app_config.dart';
import 'package:waller_app/services/protected_push_subscription_api.dart';
import 'package:waller_app/services/push_sync_controller.dart';

void main() {
  group('Push registration contract', () {
    test('preconditions reject missing token or auth', () {
      expect(
        PushRegistrationPreconditions.canSync(
          token: null,
          isAuthenticated: true,
        ),
        isFalse,
      );
      expect(
        PushRegistrationPreconditions.canSync(
          token: 'token-1',
          isAuthenticated: false,
        ),
        isFalse,
      );
      expect(
        PushRegistrationPreconditions.canSync(
          token: 'token-1',
          isAuthenticated: true,
        ),
        isTrue,
      );
      expect(
        PushRegistrationPreconditions.canSync(
          token: '  ',
          isAuthenticated: true,
        ),
        isFalse,
      );
    });

    test('lifecycle resume sync is throttled after the first run', () async {
      final controller = PushSyncController(
        lifecycleThrottle: const Duration(minutes: 2),
      );
      var runs = 0;

      final first = await controller.syncOnLifecycleResume(
        DateTime.parse('2026-06-30T10:00:00Z'),
        () async {
          runs++;
        },
      );
      final second = await controller.syncOnLifecycleResume(
        DateTime.parse('2026-06-30T10:01:00Z'),
        () async {
          runs++;
        },
      );

      expect(first, isTrue);
      expect(second, isFalse);
      expect(runs, 1);
    });

    test('push gate defaults to disabled', () {
      expect(AppConfig.enablePushSubscriptionWrites, isFalse);
    });

    test('protected payload omits user and workspace fields', () {
      final payload = ProtectedPushSubscriptionPayload(
        token: '  token-1  ',
        deviceId: '  device-1  ',
        platform: 'android',
        deviceLabel: 'Android device',
        appVersion: ' 1.0.0 ',
        osVersion: ' Android 15 ',
        businessProfileId: 'test-business-profile-id',
        userId: 'test-user-id',
      ).toJson();

      expect(payload, containsPair('token', 'token-1'));
      expect(payload, containsPair('device_id', 'device-1'));
      expect(payload, containsPair('platform', 'android'));
      expect(payload, containsPair('device_label', 'Android device'));
      expect(payload, containsPair('app_version', '1.0.0'));
      expect(payload, containsPair('os_version', 'Android 15'));
      expect(payload.containsKey('user'), isFalse);
      expect(payload.containsKey('business_profile'), isFalse);
      expect(payload.containsKey('last_seen_at'), isFalse);
      expect(payload.containsKey('is_active'), isFalse);
    });

    test('protected endpoints are the only registered push paths', () {
      expect(
        ProtectedPushSubscriptionApi.syncPath,
        '/wellar/push-subscriptions/sync',
      );
      expect(
        ProtectedPushSubscriptionApi.revokePath,
        '/wellar/push-subscriptions/revoke',
      );
    });

    test('404 push responses are classified as unavailable', () {
      const unavailable = ProtectedPushSubscriptionApiException(
        path: ProtectedPushSubscriptionApi.syncPath,
        statusCode: 404,
        message: 'Not found',
      );
      expect(unavailable.isUnavailable, isTrue);
      expect(unavailable.isAccessDenied, isFalse);
    });

    test('tap parser resolves scan request routes safely', () {
      final action = parsePushNotificationOpenAction({
        'route': 'scan_requests',
        'scan_request_id': 'req-123',
      });

      expect(action.shouldNavigate, isTrue);
      expect(action.target, PushNotificationOpenTarget.scanRequests);
      expect(action.scanRequestId, 'req-123');
    });

    test('tap parser ignores malformed payloads', () {
      final action = parsePushNotificationOpenAction({
        'route': 'scan_requests',
      });

      expect(action.shouldNavigate, isFalse);
      expect(action.target, PushNotificationOpenTarget.none);
      expect(action.scanRequestId, isNull);
    });

    test('debug diagnostics are hidden when debug mode is false', () {
      expect(shouldShowPushDiagnostics(debugMode: false), isFalse);
      expect(shouldShowPushDiagnostics(debugMode: true), isTrue);
    });
  });
}

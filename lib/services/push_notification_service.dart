import 'dart:async';
import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:dio/dio.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../config/app_config.dart';
import '../services/organization_service.dart';
import '../services/notification_service.dart';
import '../services/push_sync_controller.dart';
import '../state/app_providers.dart';
import '../state/session.dart';
import '../utils/platform_os_version.dart';
import 'protected_push_subscription_api.dart';

class PushNotificationService {
  PushNotificationService._();

  static final PushNotificationService instance = PushNotificationService._();

  static const String channelId = 'waller_alerts';
  static const String channelName = 'Waller Alerts';
  static const String channelDescription =
      'Pre-shift checks, assignment alerts, and depot updates.';
  static const String _deviceIdStorageKey = 'push_install_device_id';
  static const FlutterSecureStorage _storage = FlutterSecureStorage();

  final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();

  bool _initialized = false;
  bool _localReady = false;
  bool _firebaseInitialized = false;
  bool _foregroundHandlerRegistered = false;
  bool _backgroundHandlerRegistered = false;
  String? _currentToken;
  String? _permissionStatus;
  DateTime? _lastSuccessfulSyncAt;
  String? _lastSuccessfulSyncStatus;
  String? _lastLifecycleSyncStatus;
  String? _lastSyncTrigger;
  String? _lastSuccessfulSyncSignature;
  PushSyncOutcome? _lastSyncOutcome;
  ProviderContainer? _container;
  void Function(Map<String, dynamic> data)? _openHandler;
  Map<String, dynamic>? _pendingOpenPayload;
  Future<PushSyncOutcome>? _registrationInFlight;
  bool _registrationRequestedAgain = false;
  final ProtectedPushSubscriptionApi _pushApi =
      ProtectedPushSubscriptionApi();

  FirebaseMessaging get _messaging => FirebaseMessaging.instance;

  bool get firebaseInitialized => _firebaseInitialized;
  bool get foregroundHandlerRegistered => _foregroundHandlerRegistered;
  bool get backgroundHandlerRegistered => _backgroundHandlerRegistered;
  bool get hasCurrentToken =>
      _currentToken != null && _currentToken!.isNotEmpty;
  String get currentTokenStatus =>
      hasCurrentToken ? 'available' : 'unavailable';
  String get permissionStatusLabel =>
      _permissionStatus?.trim().isNotEmpty == true
      ? _permissionStatus!.trim()
      : 'unknown';
  DateTime? get lastSuccessfulSyncAt => _lastSuccessfulSyncAt;
  String get lastSuccessfulSyncStatus =>
      _lastSuccessfulSyncStatus?.trim().isNotEmpty == true
      ? _lastSuccessfulSyncStatus!.trim()
      : 'Not synced yet';
  String get lastLifecycleSyncStatus =>
      _lastLifecycleSyncStatus?.trim().isNotEmpty == true
      ? _lastLifecycleSyncStatus!.trim()
      : 'idle';
  String get lastSyncTrigger => _lastSyncTrigger?.trim().isNotEmpty == true
      ? _lastSyncTrigger!.trim()
      : 'none';
  PushSyncOutcome? get lastSyncOutcome => _lastSyncOutcome;
  String? get currentToken => _currentToken;

  void markBackgroundHandlerRegistered() {
    _backgroundHandlerRegistered = true;
  }

  void markForegroundHandlerRegistered() {
    _foregroundHandlerRegistered = true;
  }

  void clearSyncFingerprint() {
    _lastSuccessfulSyncSignature = null;
    _lastSuccessfulSyncAt = null;
    _lastSuccessfulSyncStatus = null;
    _lastLifecycleSyncStatus = null;
    _lastSyncTrigger = null;
    _lastSyncOutcome = null;
  }

  @visibleForTesting
  void resetForTesting() {
    _initialized = false;
    _localReady = false;
    _firebaseInitialized = false;
    _foregroundHandlerRegistered = false;
    _backgroundHandlerRegistered = false;
    _currentToken = null;
    _permissionStatus = null;
    _lastSuccessfulSyncAt = null;
    _lastSuccessfulSyncStatus = null;
    _lastLifecycleSyncStatus = null;
    _lastSyncTrigger = null;
    _lastSuccessfulSyncSignature = null;
    _lastSyncOutcome = null;
    _registrationInFlight = null;
    _registrationRequestedAgain = false;
  }

  Future<void> syncOnAppResumed() async {
    if (kIsWeb) return;
    if (!_initialized) {
      await _initialize();
    }
    if (!Session.instance.isLoggedIn) {
      _lastLifecycleSyncStatus = 'skipped_not_authenticated';
      return;
    }
    await syncCurrentDevice(trigger: 'resume');
  }

  Future<void> syncOnAppStarted() async {
    if (kIsWeb) return;
    if (!_initialized) {
      await _initialize();
    }
    if (!Session.instance.isLoggedIn) {
      _lastLifecycleSyncStatus = 'skipped_not_authenticated';
      return;
    }
    await syncCurrentDevice(trigger: 'startup');
  }

  void attachContainer(ProviderContainer container) {
    _container = container;
  }

  void attachOpenHandler(void Function(Map<String, dynamic> data) handler) {
    _openHandler = handler;
    _flushPendingOpenPayload();
  }

  Future<void> initialize() async {
    await _initialize();
  }

  Future<void> _initialize() async {
    if (kIsWeb || _initialized) return;
    _initialized = true;

    try {
      _firebaseInitialized = true;
      await _requestPermission();
      await _ensureLocalNotificationsReady();
      _listenForegroundMessages();
      _listenTokenRefresh();
      await _handleInitialMessage();
      await _refreshToken(source: 'initialize');
    } catch (error) {
      debugPrint(
        '[PUSH] initialization failed non-fatally: ${error.runtimeType}',
      );
    }
  }

  Future<void> registerDevice() async {
    await registerCurrentDevice(trigger: 'register_device');
  }

  Future<PushSyncOutcome> registerCurrentDevice({
    String trigger = 'register_current',
    ActiveWorkspaceContext? workspaceContext,
  }) {
    if (kIsWeb) {
      return Future<PushSyncOutcome>.value(PushSyncOutcome.failed);
    }
    final active = _registrationInFlight;
    if (active != null) {
      _registrationRequestedAgain = true;
      return active;
    }
    final future = _registerCurrentDeviceInternal(
      trigger: trigger,
      workspaceContext: workspaceContext,
    );
    _registrationInFlight = future;
    future.whenComplete(() {
      if (identical(_registrationInFlight, future)) {
        _registrationInFlight = null;
        if (_registrationRequestedAgain) {
          _registrationRequestedAgain = false;
          unawaited(registerCurrentDevice(trigger: 'coalesced'));
        }
      }
    });
    return future;
  }

  Future<PushSyncOutcome> syncCurrentDevice({
    String trigger = 'sync_current',
    ActiveWorkspaceContext? workspaceContext,
  }) {
    return registerCurrentDevice(
      trigger: trigger,
      workspaceContext: workspaceContext,
    );
  }

  Future<PushSyncOutcome> _registerCurrentDeviceInternal({
    required String trigger,
    ActiveWorkspaceContext? workspaceContext,
  }) async {
    if (kIsWeb) return PushSyncOutcome.failed;
    if (!_initialized) {
      await _initialize();
    }
    await _refreshToken(source: trigger);
    final resolvedWorkspace =
        workspaceContext ?? await _resolveWorkspaceContext();
    return _registerTokenIfPossible(
      trigger: trigger,
      workspaceContext: resolvedWorkspace,
    );
  }

  Future<void> unregisterDevice() async {
    await revokeCurrentDevice(trigger: 'logout');
  }

  Future<void> revokeCurrentDevice({String trigger = 'revoke_current'}) async {
    if (kIsWeb) return;

    try {
      final deviceId = await _loadOrCreateDeviceId();
      await _pushApi.revoke(deviceId: deviceId);
      debugPrint('[PUSH_SUBSCRIPTION_REVOKE] trigger=$trigger success=true');
      _lastLifecycleSyncStatus = 'revoked';
      _lastSuccessfulSyncSignature = null;
    } on ProtectedPushSubscriptionApiException catch (e) {
      if (e.isUnavailable) {
        debugPrint(
          '[PUSH_SUBSCRIPTION_REVOKE] trigger=$trigger unavailable status=404',
        );
        _lastLifecycleSyncStatus = 'revoke_unavailable';
        return;
      }
      debugPrint(
        '[PUSH_SUBSCRIPTION_REVOKE_FAILED] trigger=$trigger status=${e.statusCode} error_type=protected_api',
      );
    } on DioException catch (e) {
      debugPrint(
        '[PUSH_SUBSCRIPTION_REVOKE_FAILED] trigger=$trigger status=${e.response?.statusCode} error_type=${e.type}',
      );
    } catch (e) {
      debugPrint(
        '[PUSH_SUBSCRIPTION_REVOKE_FAILED] trigger=$trigger error_type=${e.runtimeType}',
      );
    }
  }

  Future<void> showRemoteNotification(RemoteMessage message) async {
    if (kIsWeb) return;
    await _ensureLocalNotificationsReady();
    await _showLocalNotification(message);
  }

  Future<void> showLocalNotification({
    required String title,
    required String body,
    Map<String, dynamic>? payload,
  }) async {
    if (kIsWeb) return;
    await _ensureLocalNotificationsReady();
    if (title.trim().isEmpty && body.trim().isEmpty) return;

    final details = NotificationDetails(
      android: AndroidNotificationDetails(
        channelId,
        channelName,
        channelDescription: channelDescription,
        importance: Importance.high,
        priority: Priority.high,
      ),
      iOS: const DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
      ),
    );

    await _localNotifications.show(
      DateTime.now().millisecondsSinceEpoch % 100000,
      title,
      body,
      details,
      payload: payload == null ? null : jsonEncode(payload),
    );
  }

  Future<void> scheduleDailyReminder() async {
    if (kIsWeb) return;
    await _ensureLocalNotificationsReady();
    const details = NotificationDetails(
      android: AndroidNotificationDetails(
        channelId,
        channelName,
        channelDescription: channelDescription,
        importance: Importance.high,
        priority: Priority.high,
      ),
      iOS: DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
      ),
    );

    await _localNotifications.periodicallyShow(
      91001,
      'Pre-shift scan reminder',
      "Keep your shift readiness on track. Run today's scan.",
      RepeatInterval.daily,
      details,
      androidAllowWhileIdle: true,
    );
  }

  Future<void> _requestPermission() async {
    final settings = await _messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );
    _permissionStatus = settings.authorizationStatus.name;
  }

  Future<void> _ensureLocalNotificationsReady() async {
    if (_localReady) return;
    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosInit = DarwinInitializationSettings();
    const settings = InitializationSettings(android: androidInit, iOS: iosInit);
    await _localNotifications.initialize(
      settings,
      onDidReceiveNotificationResponse: (response) {
        _handleNotificationPayload(response.payload);
      },
    );

    final androidPlugin = _localNotifications
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    if (androidPlugin != null) {
      const channel = AndroidNotificationChannel(
        channelId,
        channelName,
        description: channelDescription,
        importance: Importance.high,
      );
      await androidPlugin.createNotificationChannel(channel);
      await androidPlugin.requestNotificationsPermission();
    }

    _localReady = true;
  }

  void _listenForegroundMessages() {
    markForegroundHandlerRegistered();
    FirebaseMessaging.onMessage.listen((message) {
      final type = message.data['type']?.toString() ?? '';
      final scanRequestId = message.data['scan_request_id']?.toString() ?? '';
      debugPrint(
        '[PUSH_FOREGROUND_RECEIVED] type=$type has_scan_request_id=${scanRequestId.isNotEmpty}',
      );
      debugPrint('[NOTIFICATIONS_REFRESH] reason=push_foreground');
      _container?.read(refreshTickProvider.notifier).state++;
      _container?.invalidate(notificationsProvider);
      showRemoteNotification(message);
    });

    FirebaseMessaging.onMessageOpenedApp.listen((message) {
      _handleNotificationData(message.data);
    });
  }

  Future<void> _handleInitialMessage() async {
    try {
      final message = await _messaging.getInitialMessage();
      if (message == null) return;
      _handleNotificationData(message.data);
    } catch (error) {
      debugPrint(
        '[PUSH_INITIAL_MESSAGE] unavailable error=${error.runtimeType}',
      );
    }
  }

  void _listenTokenRefresh() {
    _messaging.onTokenRefresh.listen((token) {
      _currentToken = token;
      _logToken('[FCM_TOKEN_REFRESH]', token);
      unawaited(syncCurrentDevice(trigger: 'token_refresh'));
    });
  }

  Future<void> _refreshToken({required String source}) async {
    try {
      final token = await _messaging.getToken();
      _currentToken = token;
      if (token != null && token.isNotEmpty) {
        _logToken('[FCM_TOKEN]', token);
      } else {
        debugPrint('[FCM_TOKEN] source=$source available=false');
      }
    } catch (error) {
      debugPrint(
        '[FCM_TOKEN] source=$source available=false error=${error.runtimeType}',
      );
    }
  }

  Future<PushSyncOutcome> _registerTokenIfPossible({
    required String trigger,
    required ActiveWorkspaceContext? workspaceContext,
  }) async {
    final token = _currentToken;
    _logPushSync('trigger=$trigger');
    _logPushSync('token_available=${token != null && token.trim().isNotEmpty}');
    if (!PushRegistrationPreconditions.canSync(
      token: token,
      isAuthenticated: Session.instance.isLoggedIn,
    )) {
      if (token == null || token.trim().isEmpty) {
        _lastSyncOutcome = PushSyncOutcome.skippedNoToken;
        _lastSyncTrigger = trigger;
        _lastLifecycleSyncStatus = 'skipped_no_token';
        _logPushSync('response_status=none');
        _logPushSync('subscription_result=failed');
        _logPushSync('last_seen_updated=false');
        _logPushSync('failure_reason=no_token');
        return PushSyncOutcome.skippedNoToken;
      }
      _lastSyncOutcome = PushSyncOutcome.skippedNoSession;
      _lastSyncTrigger = trigger;
      _lastLifecycleSyncStatus = 'skipped_no_session';
      _logPushSync('response_status=none');
      _logPushSync('subscription_result=failed');
      _logPushSync('last_seen_updated=false');
      _logPushSync('failure_reason=no_session');
      return PushSyncOutcome.skippedNoSession;
    }
    if (workspaceContext == null ||
        workspaceContext.businessProfileId.trim().isEmpty ||
        workspaceContext.currentUserId.trim().isEmpty ||
        workspaceContext.currentUserId.trim() !=
            (Session.instance.userId?.trim() ?? '')) {
      _lastSyncOutcome = PushSyncOutcome.skippedNoSession;
      _lastSyncTrigger = trigger;
      _lastLifecycleSyncStatus = 'skipped_no_workspace';
      _logPushSync('response_status=none');
      _logPushSync('subscription_result=failed');
      _logPushSync('last_seen_updated=false');
      _logPushSync('failure_reason=no_workspace');
      return PushSyncOutcome.skippedNoSession;
    }

    final currentToken = token!.trim();
    final syncSignature = _buildSyncSignature(
      token: currentToken,
      workspaceContext: workspaceContext,
    );
    final platform = _platformLabel();
    final deviceId = await _loadOrCreateDeviceId();
    final osVersion = currentOsVersion().trim();

    try {
      final payload = ProtectedPushSubscriptionPayload(
        token: currentToken,
        userId: workspaceContext.currentUserId.trim(),
        businessProfileId: workspaceContext.businessProfileId.trim(),
        deviceId: deviceId,
        platform: platform,
        deviceLabel: _deviceLabel(platform),
        appVersion: AppConfig.appVersion.trim().isEmpty
            ? null
            : AppConfig.appVersion.trim(),
        osVersion: osVersion.isEmpty ? null : osVersion,
      );
      _logPushSync('request_started=true');
      final result = await _pushApi.sync(payload);
      _lastSuccessfulSyncAt = DateTime.now().toUtc();
      _lastSuccessfulSyncStatus = 'success';
      _lastSuccessfulSyncSignature = syncSignature;
      _lastSyncOutcome = PushSyncOutcome.success;
      _lastSyncTrigger = trigger;
      _lastLifecycleSyncStatus = 'synced';
      _logPushSync('response_status=${result.statusCode ?? "none"}');
      _logPushSync('subscription_result=${result.subscriptionResult}');
      _logPushSync('last_seen_updated=${result.lastSeenUpdated}');
      _logPushSync('failure_reason=none');
      return PushSyncOutcome.success;
    } on ProtectedPushSubscriptionApiException catch (e) {
      if (e.isUnavailable) {
        _lastSyncOutcome = PushSyncOutcome.failed;
        _lastSyncTrigger = trigger;
        _lastLifecycleSyncStatus = 'failed';
        _logPushSync('response_status=${e.statusCode ?? "none"}');
        _logPushSync('subscription_result=failed');
        _logPushSync('last_seen_updated=false');
        _logPushSync('failure_reason=unavailable');
        return PushSyncOutcome.failed;
      }
      _lastSyncOutcome = PushSyncOutcome.failed;
      _lastSyncTrigger = trigger;
      _lastLifecycleSyncStatus = 'failed';
      _lastSuccessfulSyncStatus = 'failed';
      _logPushSync('response_status=${e.statusCode ?? "none"}');
      _logPushSync('subscription_result=failed');
      _logPushSync('last_seen_updated=false');
      _logPushSync('failure_reason=api_status_${e.statusCode ?? 0}');
    } on DioException catch (e) {
      _lastSyncOutcome = PushSyncOutcome.failed;
      _lastSyncTrigger = trigger;
      _lastLifecycleSyncStatus = 'failed';
      _lastSuccessfulSyncStatus = 'failed';
      _logPushSync('response_status=${e.response?.statusCode ?? "none"}');
      _logPushSync('subscription_result=failed');
      _logPushSync('last_seen_updated=false');
      _logPushSync(
        'failure_reason=dio_${e.type.name}_${e.response?.statusCode ?? 0}',
      );
    } catch (e) {
      _lastSyncOutcome = PushSyncOutcome.failed;
      _lastSyncTrigger = trigger;
      _lastLifecycleSyncStatus = 'failed';
      _lastSuccessfulSyncStatus = 'failed';
      _logPushSync('response_status=none');
      _logPushSync('subscription_result=failed');
      _logPushSync('last_seen_updated=false');
      _logPushSync('failure_reason=${e.runtimeType}');
    }
    return PushSyncOutcome.failed;
  }

  Future<ActiveWorkspaceContext?> _resolveWorkspaceContext() async {
    if (!Session.instance.isLoggedIn) return null;
    try {
      return await OrganizationService.instance.fetchActiveWorkspaceContext(
        forceRefresh: true,
      );
    } catch (_) {
      return null;
    }
  }

  String _buildSyncSignature({
    required String token,
    required ActiveWorkspaceContext workspaceContext,
  }) {
    final userId = Session.instance.userId?.trim() ?? '';
    final workspaceId = workspaceContext.businessProfileId.trim();
    final membershipId = workspaceContext.membershipId.trim();
    final effectiveRole = workspaceContext.finalEffectiveRole.trim();
    return '$userId|$workspaceId|$membershipId|$effectiveRole|$token';
  }

  Future<String> _loadOrCreateDeviceId() async {
    final existing = await _storage.read(key: _deviceIdStorageKey);
    if (existing != null && existing.trim().isNotEmpty) {
      return existing.trim();
    }
    final random = Random.secure();
    final bytes = List<int>.generate(24, (_) => random.nextInt(256));
    final id = 'install_${base64UrlEncode(bytes).replaceAll('=', '')}';
    await _storage.write(key: _deviceIdStorageKey, value: id);
    return id;
  }

  void _logToken(String label, String token) {
    debugPrint('$label available=${token.isNotEmpty}');
  }

  void _logPushSync(String message) {
    debugPrint('[PUSH_SYNC] $message');
  }

  Future<void> _showLocalNotification(RemoteMessage message) async {
    final notification = message.notification;
    final title =
        notification?.title ?? message.data['title']?.toString() ?? 'Waller AI';
    final body = notification?.body ?? message.data['body']?.toString() ?? '';
    if (body.isEmpty && title.isEmpty) return;

    final details = NotificationDetails(
      android: AndroidNotificationDetails(
        channelId,
        channelName,
        channelDescription: channelDescription,
        importance: Importance.high,
        priority: Priority.high,
      ),
      iOS: const DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
      ),
    );

    await _localNotifications.show(
      DateTime.now().millisecondsSinceEpoch % 100000,
      title,
      body,
      details,
      payload: jsonEncode(message.data),
    );
  }

  String _platformLabel() {
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return 'android';
      case TargetPlatform.iOS:
        return 'ios';
      case TargetPlatform.macOS:
        return 'macos';
      case TargetPlatform.windows:
        return 'windows';
      case TargetPlatform.linux:
        return 'linux';
      case TargetPlatform.fuchsia:
        return 'fuchsia';
    }
  }

  String _deviceLabel(String platform) {
    switch (platform) {
      case 'android':
        return 'Android device';
      case 'ios':
        return 'iOS device';
      case 'macos':
        return 'macOS device';
      case 'windows':
        return 'Windows device';
      case 'linux':
        return 'Linux device';
      case 'fuchsia':
        return 'Fuchsia device';
      default:
        return '$platform device';
    }
  }

  void _handleNotificationPayload(String? payload) {
    if (payload == null || payload.trim().isEmpty) return;
    try {
      final decoded = jsonDecode(payload);
      if (decoded is Map) {
        _handleNotificationData(
          decoded.map(
            (key, value) => MapEntry(key.toString(), value.toString()),
          ),
        );
      }
    } catch (_) {}
  }

  void _handleNotificationData(Map<String, dynamic> data) {
    if (!_isScanRequestOpenPayload(data)) return;
    final requestId = _scanRequestIdFromPayload(data);
    if (requestId.isEmpty) return;

    final notificationId = _stringField(data, 'notification_id');
    final businessProfileId = _stringField(data, 'business_profile');

    unawaited(
      NotificationService.instance.markScanRequestNotificationsRead(
        scanRequestId: requestId,
        notificationId: notificationId.isNotEmpty ? notificationId : null,
        businessProfileId:
            businessProfileId.isNotEmpty ? businessProfileId : null,
      ),
    );

    _container?.read(refreshTickProvider.notifier).state++;
    _container?.invalidate(notificationsProvider);
    _container?.invalidate(incomingRequestsProvider);
    _dispatchOpenPayload({...data, 'scan_request_id': requestId});
  }

  bool _isScanRequestOpenPayload(Map<String, dynamic> data) {
    final event = _stringField(data, 'event');
    final screen = _stringField(data, 'screen');
    final route = _stringField(data, 'route');
    final linkType = _stringField(data, 'link_type');
    final fallbackType = _stringField(data, 'type');
    final requestId = _scanRequestIdFromPayload(data);

    return requestId.isNotEmpty &&
        (event == 'scan_request_created' ||
            screen == 'scan_request_open' ||
            route == 'scan_requests' ||
            linkType == 'scan_request' ||
            fallbackType == 'scan_request');
  }

  String _scanRequestIdFromPayload(Map<String, dynamic> data) {
    final linkId = _stringField(data, 'link_id');
    if (linkId.isNotEmpty) return linkId;
    final scanRequestId = _stringField(data, 'scan_request_id');
    if (scanRequestId.isNotEmpty) return scanRequestId;
    final requestId = _stringField(data, 'request_id');
    if (requestId.isNotEmpty) return requestId;
    return '';
  }

  String _stringField(Map<String, dynamic> data, String key) {
    return data[key]?.toString().trim() ?? '';
  }

  void _dispatchOpenPayload(Map<String, dynamic> data) {
    final handler = _openHandler;
    if (handler == null) {
      _pendingOpenPayload = data;
      return;
    }
    handler(data);
  }

  void _flushPendingOpenPayload() {
    final payload = _pendingOpenPayload;
    final handler = _openHandler;
    if (payload == null || handler == null) return;
    _pendingOpenPayload = null;
    handler(payload);
  }
}

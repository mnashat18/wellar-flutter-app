enum PushSyncOutcome {
  success,
  skippedNoToken,
  skippedNoSession,
  skippedUnchanged,
  failed,
}

class PushSyncController {
  PushSyncController({Duration lifecycleThrottle = const Duration(minutes: 2)})
    : _lifecycleThrottle = lifecycleThrottle;

  final Duration _lifecycleThrottle;
  DateTime? _lastLifecycleSyncAt;

  Future<void> syncOnStartup(Future<void> Function() action) async {
    await action();
  }

  Future<void> syncOnTokenRefresh(Future<void> Function() action) async {
    await action();
  }

  Future<void> syncOnWorkspaceSwitch(Future<void> Function() action) async {
    await action();
  }

  Future<bool> syncOnLifecycleResume(
    DateTime now,
    Future<void> Function() action,
  ) async {
    if (!shouldSyncOnLifecycleResume(now)) {
      return false;
    }
    _lastLifecycleSyncAt = now;
    await action();
    return true;
  }

  bool shouldSyncOnLifecycleResume(DateTime now) {
    final last = _lastLifecycleSyncAt;
    if (last == null) return true;
    return now.difference(last) >= _lifecycleThrottle;
  }

  void resetLifecycleThrottle() {
    _lastLifecycleSyncAt = null;
  }
}

class PushRegistrationPreconditions {
  static bool canSync({required String? token, required bool isAuthenticated}) {
    return token != null && token.trim().isNotEmpty && isAuthenticated;
  }
}

enum PushNotificationOpenTarget { none, scanRequests }

class PushNotificationOpenAction {
  final PushNotificationOpenTarget target;
  final String? scanRequestId;

  const PushNotificationOpenAction._(this.target, this.scanRequestId);

  const PushNotificationOpenAction.none()
    : this._(PushNotificationOpenTarget.none, null);

  const PushNotificationOpenAction.scanRequest(String id)
    : this._(PushNotificationOpenTarget.scanRequests, id);

  bool get shouldNavigate => target != PushNotificationOpenTarget.none;
}

PushNotificationOpenAction parsePushNotificationOpenAction(
  Map<String, dynamic> data,
) {
  final route = data['route']?.toString() ?? '';
  final linkType =
      data['link_type']?.toString() ?? data['type']?.toString() ?? '';
  final requestId =
      data['scan_request_id']?.toString().trim() ??
      data['link_id']?.toString().trim() ??
      data['request_id']?.toString().trim() ??
      '';

  if ((route == 'scan_requests' || linkType == 'scan_request') &&
      requestId.isNotEmpty) {
    return PushNotificationOpenAction.scanRequest(requestId);
  }

  return const PushNotificationOpenAction.none();
}

bool shouldShowPushDiagnostics({required bool debugMode}) => debugMode;

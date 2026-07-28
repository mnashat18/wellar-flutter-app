import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'app_language_state.dart';

import '../services/auth_service.dart';
import '../services/audit_log_service.dart';
import '../services/activity_service.dart';
import '../services/alert_service.dart';
import '../services/business_center_service.dart';
import '../services/notification_service.dart';
import '../services/organization_invitation_service.dart';
import '../services/organization_service.dart';
import '../services/request_service.dart';
import '../services/report_service.dart';
import '../services/scan_service.dart';
import '../services/subscription_service.dart';

import '../models/activity_event.dart';
import '../models/alert_item.dart';
import '../models/notification_item.dart';
import '../models/organization_invitation.dart';
import '../models/user_profile.dart';
import '../models/scan_result.dart';
import '../models/history_entry.dart';
import '../models/request_item.dart';
import '../models/user_summary.dart';
import '../models/report_export.dart';
import '../models/plan.dart';
import '../models/user_subscription.dart';

import 'session.dart';

// ============================================================
// CORE SESSION
// ============================================================

final sessionProvider = Provider<Session>((ref) => Session.instance);

final activeWorkspaceContextProvider = StateProvider<ActiveWorkspaceContext?>(
  (ref) => null,
);

final appLanguageControllerProvider =
    ChangeNotifierProvider<AppLanguageController>((ref) {
      final controller = AppLanguageController();
      return controller;
    });

// ============================================================
// GLOBAL REFRESH TICK (SINGLE SOURCE OF TRUTH)
// ============================================================

final refreshTickProvider = StateProvider<int>((ref) => 0);

// Latest scan result override (optimistic UI update)
final latestScanResultProvider = StateProvider<ScanResult?>((ref) => null);

// ============================================================
// SERVICES
// ============================================================

final authServiceProvider = Provider<AuthService>(
  (ref) => AuthService.instance,
);

final auditLogServiceProvider = Provider<AuditLogService>(
  (ref) => AuditLogService.instance,
);

final activityServiceProvider = Provider<ActivityService>(
  (ref) => ActivityService.instance,
);

final businessCenterServiceProvider = Provider<BusinessCenterService>(
  (ref) => BusinessCenterService.instance,
);

final notificationServiceProvider = Provider<NotificationService>(
  (ref) => NotificationService.instance,
);
final organizationInvitationServiceProvider =
    Provider<OrganizationInvitationService>(
      (ref) => OrganizationInvitationService.instance,
    );
final alertServiceProvider = Provider<AlertService>(
  (ref) => AlertService.instance,
);

final requestServiceProvider = Provider<RequestService>(
  (ref) => RequestService.instance,
);

final reportServiceProvider = Provider<ReportService>(
  (ref) => ReportService.instance,
);

final scanServiceProvider = Provider<ScanService>(
  (ref) => ScanService.instance,
);

final subscriptionServiceProvider = Provider<SubscriptionService>(
  (ref) => SubscriptionService.instance,
);

// Notifications (local read overrides for UX consistency)
final notificationReadOverrideProvider = StateProvider<Set<String>>(
  (ref) => <String>{},
);

// Local notifications (optimistic fallback if backend blocks writes)
final localNotificationsProvider = StateProvider<List<NotificationItem>>(
  (ref) => const [],
);

// ============================================================
// HOME (LATEST SCANS – FAST & CONSISTENT)
// ============================================================

final homeDataProvider = FutureProvider<HomeData>((ref) async {
  ref.watch(refreshTickProvider);
  final latestOverride = ref.watch(latestScanResultProvider);

  final scanService = ref.read(scanServiceProvider);
  final data = await scanService.fetchHomeData(limit: 50);
  if (latestOverride == null) return data;
  return HomeData(results: _mergeLatest(data.results, latestOverride));
});

final homeScansProvider = FutureProvider<List<ScanResult>>((ref) async {
  ref.watch(refreshTickProvider);
  final latestOverride = ref.watch(latestScanResultProvider);

  final scanService = ref.read(scanServiceProvider);

  // Same source as history, smaller window
  final data = await scanService.fetchHomeData(limit: 50);
  if (latestOverride == null) return data.results;
  return _mergeLatest(data.results, latestOverride);
});

// ============================================================
// HISTORY (AUTHORITATIVE SOURCE)
// ============================================================

final historyProvider = FutureProvider<List<ScanResult>>((ref) async {
  ref.watch(refreshTickProvider);
  final latestOverride = ref.watch(latestScanResultProvider);

  final scanService = ref.read(scanServiceProvider);

  // Larger window, same endpoint
  final data = await scanService.fetchHomeData(limit: 200);
  if (latestOverride == null) return data.results;
  return _mergeLatest(data.results, latestOverride);
});

final historyTimelineProvider = FutureProvider<List<HistoryEntry>>((ref) async {
  ref.watch(refreshTickProvider);
  return ref.read(scanServiceProvider).fetchHistoryTimeline(limit: 200);
});

final ownerHistoryTimelineProvider = FutureProvider<List<HistoryEntry>>((
  ref,
) async {
  ref.watch(refreshTickProvider);
  final latestOverride = ref.watch(latestScanResultProvider);
  final workspace = ref.watch(activeWorkspaceContextProvider);
  final profileId = workspace?.businessProfileId.trim() ?? '';
  final entries = await ref
      .read(scanServiceProvider)
      .fetchHistoryTimeline(
        limit: 200,
        businessProfileId: profileId.isEmpty ? null : profileId,
        completedResultsOnly: true,
      );
  if (latestOverride == null) return entries;
  return _mergeLatestHistory(entries, latestOverride);
});

List<ScanResult> _mergeLatest(List<ScanResult> results, ScanResult latest) {
  final merged = <ScanResult>[latest];
  for (final r in results) {
    if (r.id == latest.id || r.scanId == latest.scanId) continue;
    merged.add(r);
  }
  return merged;
}

List<HistoryEntry> _mergeLatestHistory(
  List<HistoryEntry> entries,
  ScanResult latest,
) {
  final scanId = latest.scanId.trim();
  if (scanId.isEmpty) return entries;
  final latestEntry = HistoryEntry(
    id: scanId,
    scanId: scanId,
    startedAt: null,
    completedAt: latest.completedAt ?? latest.dateCreated,
    dateCreated: latest.dateCreated,
    status: 'completed',
    result: latest,
  );
  final merged = <HistoryEntry>[latestEntry];
  for (final entry in entries) {
    if (entry.scanId == scanId || entry.result?.id == latest.id) continue;
    merged.add(entry);
  }
  return merged;
}

// ============================================================
// PROFILE / USERS
// ============================================================

final profileProvider = FutureProvider<UserProfile>((ref) async {
  ref.watch(refreshTickProvider);
  return ref.read(authServiceProvider).fetchProfile();
});

final usersProvider = FutureProvider<List<UserSummary>>((ref) async {
  ref.watch(refreshTickProvider);
  return ref.read(requestServiceProvider).fetchUsers();
});

// ============================================================
// REQUESTS
// ============================================================

final sentRequestsProvider = FutureProvider<List<RequestItem>>((ref) async {
  ref.watch(refreshTickProvider);
  return ref.read(requestServiceProvider).fetchRequests(limit: 50);
});

final incomingRequestsProvider = FutureProvider<List<RequestItem>>((ref) async {
  ref.watch(refreshTickProvider);

  final userId = Session.instance.userId;
  if (userId == null || userId.isEmpty) return const [];

  return ref.read(requestServiceProvider).fetchIncomingRequests(userId: userId);
});

// ============================================================
// REPORTS / EXPORTS
// ============================================================

final exportsProvider = FutureProvider<List<ReportExport>>((ref) async {
  ref.watch(refreshTickProvider);
  return ref.read(reportServiceProvider).fetchExports();
});

// ============================================================
// NOTIFICATIONS
// ============================================================

final notificationsProvider = FutureProvider<List<NotificationItem>>((
  ref,
) async {
  ref.watch(refreshTickProvider);
  final readOverrides = ref.watch(notificationReadOverrideProvider);
  final localItems = ref.watch(localNotificationsProvider);
  final serverItems = await ref
      .read(notificationServiceProvider)
      .fetchNotifications();
  final items = _mergeNotifications(serverItems, localItems);
  if (readOverrides.isEmpty) return items;
  return items.map((item) {
    final linkKey = item.linkId?.trim();
    final isRead =
        readOverrides.contains(item.id) ||
        (linkKey != null &&
            linkKey.isNotEmpty &&
            readOverrides.contains('link:$linkKey'));
    return isRead ? item.copyAsRead() : item;
  }).toList();
});

final organizationInvitationsProvider =
    FutureProvider<List<OrganizationInvitation>>((ref) async {
      ref.watch(refreshTickProvider);
      ref.watch(
        activeWorkspaceContextProvider.select((workspace) => workspace?.membershipId),
      );
      return ref
          .read(organizationInvitationServiceProvider)
          .fetchPendingInvitations();
    });

final alertsProvider = FutureProvider<List<AlertItem>>((ref) async {
  ref.watch(refreshTickProvider);
  return ref.read(alertServiceProvider).fetchAlerts();
});

List<NotificationItem> _mergeNotifications(
  List<NotificationItem> serverItems,
  List<NotificationItem> localItems,
) {
  final merged = <NotificationItem>[];
  final seenIds = <String>{};
  final seenLinks = <String>{};

  void add(NotificationItem item) {
    final id = item.id.trim();
    if (id.isNotEmpty && seenIds.contains(id)) return;
    final linkKey = item.linkId?.trim();
    if (linkKey != null && linkKey.isNotEmpty) {
      if (seenLinks.contains(linkKey)) return;
      seenLinks.add(linkKey);
    }
    if (id.isNotEmpty) seenIds.add(id);
    merged.add(item);
  }

  for (final item in serverItems) {
    add(item);
  }
  for (final item in localItems) {
    add(item);
  }

  merged.sort((a, b) {
    final aDate = a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
    final bDate = b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
    return bDate.compareTo(aDate);
  });

  return merged;
}

final unreadNotificationsProvider = Provider<int>((ref) {
  final async = ref.watch(notificationsProvider);
  return async.maybeWhen(
    data: (items) => items.where((e) => e.isUnread).length,
    orElse: () => 0,
  );
});

final openAlertsCountProvider = Provider<int>((ref) {
  final async = ref.watch(alertsProvider);
  return async.maybeWhen(
    data: (items) => items.where((e) => e.isOpen).length,
    orElse: () => 0,
  );
});

// ============================================================
// ACTIVITY EVENTS
// ============================================================

final activityEventsProvider = FutureProvider<List<ActivityEvent>>((ref) async {
  ref.watch(refreshTickProvider);
  return ref.read(activityServiceProvider).fetchEvents();
});

// ============================================================
// SUBSCRIPTIONS / PLANS
// ============================================================

final plansProvider = FutureProvider<List<Plan>>((ref) async {
  ref.watch(refreshTickProvider);
  return ref.read(subscriptionServiceProvider).fetchPlans();
});

final activeSubscriptionProvider = FutureProvider<UserSubscription?>((
  ref,
) async {
  ref.watch(refreshTickProvider);
  return ref.read(subscriptionServiceProvider).fetchActiveSubscription();
});

final subscriptionAccessProvider = Provider<AsyncValue<PlanAccess>>((ref) {
  final subscriptionAsync = ref.watch(activeSubscriptionProvider);
  final service = ref.read(subscriptionServiceProvider);
  return subscriptionAsync.whenData(service.accessForSubscription);
});

final canUseBusinessProvider = Provider<bool>((ref) {
  final async = ref.watch(subscriptionAccessProvider);
  return async.maybeWhen(
    data: (access) => access.canUseBusiness,
    orElse: () => false,
  );
});

final shouldShowExpiredSubscriptionBannerProvider = Provider<bool>((ref) {
  final async = ref.watch(subscriptionAccessProvider);
  return async.maybeWhen(
    data: (access) => access.showExpiredBanner,
    orElse: () => false,
  );
});

final businessMembersCountProvider = FutureProvider<int>((ref) async {
  ref.watch(refreshTickProvider);
  final profileId = await OrganizationService.instance
      .fetchPrimaryBusinessProfileId();
  if (profileId == null || profileId.trim().isEmpty) return 0;
  return ref
      .read(subscriptionServiceProvider)
      .fetchCurrentMembersCount(profileId);
});

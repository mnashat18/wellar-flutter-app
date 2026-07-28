import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/scan_result.dart';
import '../models/notification_item.dart';
import '../services/scan_service.dart';
import '../services/notification_service.dart';
import '../state/app_providers.dart';

class ScanSyncService {
  ScanSyncService._();

  static final ScanSyncService instance = ScanSyncService._();

  // ============================================================
  // STEP 1 — WAIT FOR RESULT (BACKEND WORKFLOW)
  // ============================================================

  Future<ScanResult?> waitForScanResult(String scanId) async {
    const maxAttempts = 60;
    const delay = Duration(seconds: 2);

    for (int attempt = 0; attempt < maxAttempts; attempt++) {
      try {
        debugPrint(
          '[SCAN_RESULT_POLL] step=8 poll attempt=${attempt + 1} scan_id=$scanId',
        );
        final scan = await ScanService.instance.fetchWellnessScanStatus(scanId);
        if (scan.isFailed) {
          debugPrint(
            '[ScanFlow] final failed state scan_id=$scanId failure_reason=${scan.failureReason}',
          );
          return null;
        }
        if (scan.isCompleted) {
          final result = await ScanService.instance.fetchScanResultForScan(
            scanId,
          );
          if (result != null) {
            debugPrint(
              '[SCAN_RESULT_POLL] step=8 poll success scan_id=$scanId result_id=${result.id}',
            );
            debugPrint('[ScanFlow] final completed state scan_id=$scanId');
            return result;
          }
        }
      } catch (_) {}

      await Future.delayed(delay);
    }

    return null;
  }

  // ============================================================
  // STEP 2 — WAIT UNTIL IT APPEARS IN HOME / HISTORY
  // ============================================================

  Future<void> waitUntilScanAppearsInHomeHistory(String scanId) async {
    const maxAttempts = 30;
    const delay = Duration(seconds: 2);

    for (int attempt = 0; attempt < maxAttempts; attempt++) {
      try {
        debugPrint(
          '[SCAN_HISTORY_POLL] attempt=${attempt + 1} scan_id=$scanId',
        );
        final home = await ScanService.instance.fetchHomeData(limit: 50);
        if (home.results.any((e) => e.scanId == scanId)) return;

        final history = await ScanService.instance.fetchHomeData(limit: 200);
        if (history.results.any((e) => e.scanId == scanId)) return;
      } on UnauthenticatedException {
        return;
      } on DioException catch (e) {
        if (!_isTransientNetworkError(e)) {
          debugPrint('[SCAN_SYNC_WAIT_FAILED] ${e.message}');
        }
      } catch (e) {
        debugPrint('[SCAN_SYNC_WAIT_FAILED] $e');
      }

      await Future.delayed(delay);
    }
  }

  // ============================================================
  // OPTIMISTIC REFRESH — UI FIRST
  // ============================================================

  void optimisticRefresh(ProviderContainer container) {
    container.read(refreshTickProvider.notifier).state++;

    container.invalidate(homeDataProvider);
    container.invalidate(homeScansProvider);
    container.invalidate(historyProvider);
    container.invalidate(ownerHistoryTimelineProvider);
    container.invalidate(profileProvider);
    container.invalidate(usersProvider);
    container.invalidate(sentRequestsProvider);
    container.invalidate(incomingRequestsProvider);
    container.invalidate(notificationsProvider);
    container.invalidate(unreadNotificationsProvider);
    container.invalidate(alertsProvider);
    container.invalidate(exportsProvider);
    container.invalidate(activityEventsProvider);
  }

  // ============================================================
  // FULL SYNC — BACKGROUND SOURCE OF TRUTH
  // ============================================================

  Future<void> syncScanAndRefresh({
    required String scanId,
    required ProviderContainer container,
  }) async {
    try {
      ScanResult? result = await waitForScanResult(scanId);
      await _maybeCreateScanNotification(result, container);
      if (result == null) {
        final scan = await ScanService.instance.fetchWellnessScanStatus(scanId);
        if (scan.isCompleted) {
          await waitUntilScanAppearsInHomeHistory(scanId);
          result = await ScanService.instance.fetchScanResultForScan(scanId);
          await _maybeCreateScanNotification(result, container);
        }
      }
      await _refreshAll(container);
    } catch (e, s) {
      debugPrint('[SCAN_SYNC_FAILED] $e\n$s');
    }
  }

  // ============================================================
  // HARD REFRESH — EVERYTHING RELEVANT
  // ============================================================

  Future<void> _refreshAll(ProviderContainer container) async {
    container.read(refreshTickProvider.notifier).state++;

    container.invalidate(homeDataProvider);
    container.invalidate(homeScansProvider);
    container.invalidate(historyProvider);
    container.invalidate(ownerHistoryTimelineProvider);
    container.invalidate(profileProvider);
    container.invalidate(usersProvider);
    container.invalidate(sentRequestsProvider);
    container.invalidate(incomingRequestsProvider);
    container.invalidate(notificationsProvider);
    container.invalidate(unreadNotificationsProvider);
    container.invalidate(alertsProvider);
    container.invalidate(exportsProvider);
    container.invalidate(activityEventsProvider);

    try {
      await Future.wait([
        container.read(homeDataProvider.future),
        container.read(homeScansProvider.future),
        container.read(historyProvider.future),
        container.read(activityEventsProvider.future),
      ]);
    } catch (e) {
      debugPrint('[SCAN_SYNC_REFRESH_FAILED] $e');
    }
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

  Future<void> _maybeCreateScanNotification(
    ScanResult? result,
    ProviderContainer container,
  ) async {
    if (result == null) return;
    final scanId = result.scanId;
    if (scanId.isEmpty) return;
    final exists = await NotificationService.instance.hasNotificationForLinkId(
      scanId,
    );
    if (exists) return;
    final state = result.overallState.trim();
    final title = 'New readiness result';
    final body = state.isEmpty
        ? 'Your pre-shift readiness result is ready.'
        : 'Readiness status: $state';
    _addLocalNotification(container, scanId, title, body);
    try {
      await NotificationService.instance.createNotification(
        title: title,
        body: body,
        linkType: 'result',
        linkId: scanId,
        type: 'result',
        status: 'unread',
      );
    } on DioException catch (e) {
      if ((e.response?.statusCode ?? 0) == 403) {
        debugPrint(
          '[SCAN_RESULT_NOTIFICATION] ignored notifications 403 scan_id=$scanId',
        );
        return;
      }
      rethrow;
    } catch (e) {
      debugPrint('[SCAN_RESULT_NOTIFICATION] ignored error scan_id=$scanId $e');
    }
  }

  void _addLocalNotification(
    ProviderContainer container,
    String scanId,
    String title,
    String body,
  ) {
    final current = container.read(localNotificationsProvider);
    if (current.any((item) => item.linkId == scanId)) return;

    final item = NotificationItem(
      id: 'local:$scanId',
      title: title,
      body: body,
      type: 'result',
      status: 'unread',
      linkType: 'result',
      linkId: scanId,
      createdAt: DateTime.now(),
    );

    container.read(localNotificationsProvider.notifier).state = [
      item,
      ...current,
    ];
  }
}

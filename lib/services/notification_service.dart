import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import '../models/notification_item.dart';
import '../state/session.dart';
import 'directus_client.dart';
import 'organization_service.dart';

class NotificationService {
  NotificationService._();

  static final NotificationService instance = NotificationService._();

  Dio get _client => DirectusClient.instance.client;

  Future<List<NotificationItem>> fetchNotifications({int limit = 200}) async {
    final workspace = await OrganizationService.instance
        .fetchActiveWorkspaceContext();
    final trace = OrganizationService.instance.activeSwitchTrace ?? 'none';
    final profileId = workspace?.businessProfileId.trim() ?? '';
    final cappedLimit = limit.clamp(1, 50).toInt();
    debugPrint(
      '[SCOPED_DATA_REQUEST] feature=notifications operation=fetch_notifications method=GET endpoint_or_collection=/items/notifications membership_id=${workspace?.membershipId.trim() ?? ''} business_profile=$profileId department=${workspace?.departmentId?.trim() ?? ''} membership_role=${workspace?.memberRole ?? ''} context_source=${OrganizationService.instance.activeWorkspaceContextSource} workspace_revision=${OrganizationService.instance.workspaceRevision} filter_summary=business_profile=$profileId;limit=$cappedLimit started=true trace=$trace',
    );
    final records = await _fetchNotificationRecords(
      limit: cappedLimit,
      businessProfileId: profileId.isNotEmpty ? profileId : null,
    );
    final notifications = records
        .map(NotificationItem.fromJson)
        .map(_normalizeNotification)
        .toList();
    debugPrint(
      '[SCOPED_DATA_RESPONSE] feature=notifications operation=fetch_notifications http_status=200 result_count=${notifications.length} duration_ms=0 membership_id=${workspace?.membershipId.trim() ?? ''} business_profile=$profileId workspace_revision_before=${OrganizationService.instance.workspaceRevision} workspace_revision_after=${OrganizationService.instance.workspaceRevision} context_unchanged=true returned_business_profile_ids=${records.map((row) => row['business_profile']?.toString().trim() ?? '').where((v) => v.isNotEmpty).toSet().toList()} returned_membership_ids=${records.map((row) => row['target_member']?.toString().trim() ?? '').where((v) => v.isNotEmpty).toSet().toList()} empty_result=${notifications.isEmpty} trace=$trace',
    );
    return notifications;
  }

  Future<List<Map<String, dynamic>>> _fetchNotificationRecords({
    required int limit,
    String? businessProfileId,
  }) async {
    final userId = Session.instance.userId;
    if (userId == null || userId.isEmpty) return const [];
    final query = <String, dynamic>{
      'sort': '-date_created',
      'limit': limit.clamp(1, 200),
      'fields':
          'id,date_created,user,title,body,type,status,link_type,link_id,meta,business_profile,read_at',
      'filter[user][_eq]': userId,
    };
    final normalizedBusinessProfileId = businessProfileId?.trim() ?? '';
    if (normalizedBusinessProfileId.isNotEmpty) {
      query['filter[business_profile][_eq]'] = normalizedBusinessProfileId;
    }
    try {
      final response = await _client.get(
        '/items/notifications',
        queryParameters: query,
      );
      final data = response.data['data'];
      if (data is! List) {
        return const [];
      }
      return data
          .whereType<Map>()
          .map(
            (row) => row.map(
              (key, value) => MapEntry(key.toString(), value),
            ),
          )
          .toList(growable: false);
    } on DioException catch (error) {
      final status = error.response?.statusCode ?? 0;
      if (status != 403 && status != 400) rethrow;
      return const [];
    }
  }

  Future<void> markScanRequestNotificationsRead({
    required String scanRequestId,
    String? notificationId,
    String? businessProfileId,
  }) async {
    final normalizedScanRequestId = scanRequestId.trim();
    if (normalizedScanRequestId.isEmpty) return;

    final normalizedNotificationId = notificationId?.trim() ?? '';
    final normalizedBusinessProfileId = businessProfileId?.trim() ?? '';

    if (normalizedNotificationId.isNotEmpty) {
      try {
        await markRead(normalizedNotificationId);
      } catch (_) {}
    }

    final records = await _fetchNotificationRecords(
      limit: 200,
      businessProfileId: normalizedBusinessProfileId.isNotEmpty
          ? normalizedBusinessProfileId
          : null,
    );

    for (final row in records) {
      final rowId = row['id']?.toString().trim() ?? '';
      if (rowId.isEmpty || rowId == normalizedNotificationId) continue;

      final rowType = row['type']?.toString().trim().toLowerCase() ?? '';
      final rowLinkType = row['link_type']?.toString().trim().toLowerCase() ?? '';
      final rowLinkId = row['link_id']?.toString().trim() ?? '';
      final rowStatus = row['status']?.toString().trim().toLowerCase() ?? '';
      final rowBusinessProfile = row['business_profile']?.toString().trim() ?? '';

      if (rowType != 'scan_request' ||
          rowLinkType != 'scan_request' ||
          rowLinkId != normalizedScanRequestId ||
          rowStatus == 'read') {
        continue;
      }

      if (normalizedBusinessProfileId.isNotEmpty &&
          rowBusinessProfile.isNotEmpty &&
          rowBusinessProfile != normalizedBusinessProfileId) {
        continue;
      }

      try {
        await markRead(rowId);
      } catch (_) {}
    }
  }

  Future<void> markRead(String id) async {
    if (id.startsWith('local:')) return;
    if (id.startsWith('alert:')) return;
    final now = DateTime.now().toUtc().toIso8601String();
    debugPrint(
      '[NOTIFICATION_MARK_READ_START] has_id=${id.trim().isNotEmpty}',
    );
    try {
      await _client.patch(
        '/items/notifications/$id',
        data: {'status': 'read', 'read_at': now},
      );
      debugPrint('[NOTIFICATION_MARK_READ_SUCCESS] success=true');
    } on DioException catch (error) {
      final status = error.response?.statusCode ?? 0;
      debugPrint(
        '[NOTIFICATIONS] mark_read status=$status error_type=${error.type}',
      );
      if (status == 403 || status == 404 || status == 405) return;
      rethrow;
    }
  }

  Future<void> markAllRead() async {
    final userId = Session.instance.userId;
    if (userId == null || userId.isEmpty) return;
    try {
      await _client.patch(
        '/items/notifications',
        queryParameters: {
          'filter[user][_eq]': userId,
          'filter[status][_neq]': 'read',
        },
        data: {
          'status': 'read',
          'read_at': DateTime.now().toUtc().toIso8601String(),
        },
      );
      debugPrint('[NOTIFICATIONS] mark_read status=200 body=bulk');
    } on DioException catch (error) {
      final status = error.response?.statusCode ?? 0;
      debugPrint(
        '[NOTIFICATIONS] mark_read status=$status error_type=${error.type}',
      );
      if (status != 403 && status != 405) {
        rethrow;
      }
    }

    await _ensureAllRead();
  }

  Future<bool> hasNotificationForLinkId(String linkId) async {
    final userId = Session.instance.userId;
    if (userId == null || userId.isEmpty) return false;
    try {
      final response = await _client.get(
        '/items/notifications',
        queryParameters: {
          'filter[user][_eq]': userId,
          'filter[link_id][_eq]': linkId,
          'limit': 1,
          'fields': 'id',
        },
      );
      final data = response.data['data'];
      return data is List && data.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  Future<bool> createNotification({
    required String title,
    required String body,
    required String linkType,
    required String linkId,
    String type = 'result',
    String status = 'unread',
    String? userId,
    String? businessProfileId,
    Map<String, dynamic>? meta,
  }) async {
    final targetUserId = userId ?? Session.instance.userId;
    if (targetUserId == null || targetUserId.isEmpty) return false;
    final workspace = await OrganizationService.instance.fetchActiveWorkspaceContext();
    final trace = OrganizationService.instance.activeSwitchTrace ?? 'none';
    final profileId = businessProfileId?.trim().isNotEmpty == true
        ? businessProfileId!.trim()
        : workspace?.businessProfileId.trim() ?? '';
    if (profileId.isEmpty) return false;
    try {
      debugPrint(
        '[SCOPED_DATA_REQUEST] feature=notifications operation=create_notification method=POST endpoint_or_collection=/items/notifications membership_id=${workspace?.membershipId.trim() ?? ''} business_profile=$profileId department=${workspace?.departmentId?.trim() ?? ''} membership_role=${workspace?.memberRole ?? ''} context_source=${OrganizationService.instance.activeWorkspaceContextSource} workspace_revision=${OrganizationService.instance.workspaceRevision} filter_summary=business_profile=$profileId;status=$status;type=$type started=true trace=$trace',
      );
      await _client.post(
        '/items/notifications',
        data: {
          'user': targetUserId,
          'business_profile': profileId,
          'title': title,
          'body': body,
          'type': type,
          'status': status,
          'link_type': linkType,
          'link_id': linkId,
          if (meta != null) 'meta': meta,
          'read_at': null,
        },
      );
      debugPrint(
        '[SCOPED_DATA_RESPONSE] feature=notifications operation=create_notification http_status=200 result_count=1 duration_ms=0 membership_id=${workspace?.membershipId.trim() ?? ''} business_profile=$profileId workspace_revision_before=${OrganizationService.instance.workspaceRevision} workspace_revision_after=${OrganizationService.instance.workspaceRevision} context_unchanged=true returned_business_profile_ids=[$profileId] returned_membership_ids=[] empty_result=false trace=$trace',
      );
      return true;
    } on DioException catch (e) {
      debugPrint(
        '[NOTIFICATIONS_CREATE_FAILED] status=${e.response?.statusCode} error_type=${e.type}',
      );
      return false;
    } catch (e) {
      debugPrint(
        '[NOTIFICATIONS_CREATE_FAILED] status=- error_type=${e.runtimeType}',
      );
      return false;
    }
  }

  Future<void> _ensureAllRead() async {
    final items = await fetchNotifications(limit: 200);
    for (final item in items) {
      if (!item.isUnread) continue;
      try {
        await markRead(item.id);
      } catch (_) {}
    }
  }

  NotificationItem _normalizeNotification(NotificationItem item) {
    final normalizedType = item.type.trim().toLowerCase();
    final title = item.title.trim().isNotEmpty
        ? item.title
        : _defaultTitleForType(normalizedType);
    final body = item.body.trim().isNotEmpty
        ? item.body
        : _defaultBodyForType(normalizedType);
    return NotificationItem(
      id: item.id,
      title: title,
      body: body,
      type: normalizedType.isEmpty ? 'general' : normalizedType,
      status: item.status,
      linkType: item.linkType,
      linkId: item.linkId,
      meta: item.meta,
      createdAt: item.createdAt,
    );
  }

  String _defaultTitleForType(String type) {
    switch (type) {
      case 'scan_request_created':
      case 'scan_request_assigned':
        return 'New readiness request';
      case 'scan_result_ready':
        return 'Your readiness result is ready';
      case 'scan_result_pending':
        return 'Result is still being prepared';
      case 'alert_created':
        return 'Action required';
      case 'invite_accepted':
        return 'Invite accepted';
      case 'missed_scan':
        return 'Missed readiness check';
      default:
        return 'Operational update';
    }
  }

  String _defaultBodyForType(String type) {
    switch (type) {
      case 'scan_result_pending':
        return 'Please try again shortly.';
      default:
        return 'Open this notification to review details.';
    }
  }
}

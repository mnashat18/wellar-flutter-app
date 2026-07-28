import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../models/alert_item.dart';
import '../state/session.dart';
import 'directus_client.dart';
import 'organization_service.dart';

class AlertService {
  AlertService._();
  static final AlertService instance = AlertService._();
  static const List<String> _fields = [
    'id',
    'title',
    'message',
    'status',
    'severity',
    'action_type',
    'business_profile',
    'department',
    'target_user',
    'target_user.id',
    'target_user.email',
    'target_user.first_name',
    'target_user.last_name',
    'target_member',
    'target_member.id',
    'target_member.member_role',
    'target_member.user',
    'target_member.user.id',
    'target_member.user.email',
    'target_member.user.first_name',
    'target_member.user.last_name',
    'scan',
    'scan.id',
    'scan.status',
    'scan.date_created',
    'scan.completed_at',
    'date_created',
  ];

  Dio get _client => DirectusClient.instance.client;

  Future<List<AlertItem>> fetchAlerts({int limit = 200}) async {
    final userId = Session.instance.userId;
    if (userId == null || userId.isEmpty) return const [];
    final workspace = await OrganizationService.instance
        .fetchActiveWorkspaceContext();
    final trace = OrganizationService.instance.activeSwitchTrace ?? 'none';
    final role =
        workspace?.finalEffectiveRole ?? workspace?.memberRole ?? 'unknown';
    final profileId = workspace?.businessProfileId.trim() ?? '';
    final departmentId = workspace?.departmentId?.trim() ?? '';
    final membershipId = workspace?.membershipId.trim() ?? '';

    final query = <String, dynamic>{
      'sort': '-date_created',
      'limit': limit,
      'fields': _fields.join(','),
      if (profileId.isNotEmpty) 'filter[business_profile][_eq]': profileId,
    };
    if (role == 'employee') {
      query['filter[user][_eq]'] = userId;
    } else if (role == 'manager' && departmentId.isNotEmpty) {
      query['filter[department][_eq]'] = departmentId;
    }
    debugPrint(
      '[SCOPED_DATA_REQUEST] feature=notifications operation=alerts_fetch method=GET endpoint_or_collection=/items/alerts membership_id=$membershipId business_profile=$profileId department=$departmentId membership_role=$role context_source=${OrganizationService.instance.activeWorkspaceContextSource} workspace_revision=${OrganizationService.instance.workspaceRevision} filter_summary=business_profile=$profileId;department=$departmentId;limit=$limit started=true trace=$trace',
    );

    debugPrint('[ALERTS_CONTEXT] business_profile=$profileId');
    debugPrint('[ALERTS_CONTEXT] membership_id=$membershipId');
    debugPrint('[ALERTS_CONTEXT] role=$role');
    debugPrint('[ALERTS] role=$role');
    debugPrint('[ALERTS] fields=${_fields.join(',')}');
    debugPrint('[ALERTS] query=$query');
    try {
      final response = await _client.get(
        '/items/alerts',
        queryParameters: query,
      );
      final data = response.data['data'];
      final rows = data is List
          ? data.whereType<Map<String, dynamic>>().toList()
          : <Map<String, dynamic>>[];
      debugPrint(
        '[ALERTS] status=${response.statusCode} body_count=${rows.length} fields=${_fields.join(",")}',
      );
      debugPrint(
        '[SCOPED_DATA_RESPONSE] feature=notifications operation=alerts_fetch http_status=${response.statusCode ?? 0} result_count=${rows.length} duration_ms=0 membership_id=$membershipId business_profile=$profileId workspace_revision_before=${OrganizationService.instance.workspaceRevision} workspace_revision_after=${OrganizationService.instance.workspaceRevision} context_unchanged=true returned_business_profile_ids=${rows.map((row) => row['business_profile']?.toString().trim() ?? '').where((v) => v.isNotEmpty).toSet().toList()} returned_membership_ids=${rows.map((row) => row['target_member']?.toString().trim() ?? '').where((v) => v.isNotEmpty).toSet().toList()} empty_result=${rows.isEmpty} trace=$trace',
      );
      return rows.map(AlertItem.fromJson).toList();
    } on DioException catch (e) {
      final status = e.response?.statusCode ?? 0;
      debugPrint(
        '[ALERTS] status=$status body=${e.response?.data} fields=${_fields.join(",")}',
      );
      debugPrint(
        '[SCOPED_DATA_ERROR] feature=notifications operation=alerts_fetch http_status=$status error_type=${e.type} failure_code=${status == 403 ? 'scoped_data_403' : status == 401 ? 'scoped_data_401' : 'scoped_data_network_error'} duration_ms=0 membership_id=$membershipId business_profile=$profileId membership_role=$role workspace_revision_before=${OrganizationService.instance.workspaceRevision} workspace_revision_after=${OrganizationService.instance.workspaceRevision} context_unchanged=true trace=$trace',
      );
      if (status == 403 || status == 404 || status == 400) return const [];
      rethrow;
    }
  }

  Future<bool> markAlertClosed(String alertId) async {
    if (alertId.trim().isEmpty) return false;
    try {
      await _client.patch('/items/alerts/$alertId', data: {'status': 'closed'});
      return true;
    } on DioException catch (e) {
      final status = e.response?.statusCode ?? 0;
      if (status == 403 || status == 404 || status == 405) return false;
      if (status == 400 || status == 422) {
        try {
          await _client.patch(
            '/items/alerts/$alertId',
            data: {'status': 'resolved'},
          );
          return true;
        } catch (_) {
          return false;
        }
      }
      return false;
    }
  }
}

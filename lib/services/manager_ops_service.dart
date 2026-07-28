import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import 'directus_client.dart';
import 'member_identity_service.dart';
import 'organization_service.dart';
import 'readiness_result_service.dart';
import 'request_service.dart';

class ManagerMemberView {
  final String memberId;
  final String userId;
  final String name;
  final String email;
  final String role;
  final String status;
  final String? departmentName;
  final String? departmentId;
  final String? latestReadiness;
  final DateTime? lastCheckAt;
  final bool needsAttention;
  final bool missingCheck;

  const ManagerMemberView({
    required this.memberId,
    required this.userId,
    required this.name,
    required this.email,
    required this.role,
    required this.status,
    required this.departmentName,
    required this.departmentId,
    required this.latestReadiness,
    required this.lastCheckAt,
    required this.needsAttention,
    required this.missingCheck,
  });
}

class ManagerSnapshot {
  final int teamMembers;
  final int pendingRequests;
  final int checksCompletedToday;
  final int missingChecks;
  final int attentionOutcomes;
  final int openAlerts;
  final Map<String, int> readinessDistribution;

  const ManagerSnapshot({
    required this.teamMembers,
    required this.pendingRequests,
    required this.checksCompletedToday,
    required this.missingChecks,
    required this.attentionOutcomes,
    required this.openAlerts,
    required this.readinessDistribution,
  });
}

class ManagerOpsService {
  ManagerOpsService._();
  static final ManagerOpsService instance = ManagerOpsService._();

  Dio get _client => DirectusClient.instance.client;

  void clearOrganizationScopedCaches() {}

  Future<List<ManagerMemberView>> fetchTeam() async {
    final startRevision = OrganizationService.instance.workspaceRevision;
    final startSignature = OrganizationService.instance.workspaceSignature;
    final workspace = await OrganizationService.instance
        .fetchActiveWorkspaceContext();
    if (workspace == null || workspace.businessProfileId.trim().isEmpty) {
      return const [];
    }
    final profileId = workspace.businessProfileId.trim();
    final scopedDepartmentId = workspace.departmentId?.trim();
    final trace = OrganizationService.instance.activeSwitchTrace ?? 'none';
    debugPrint(
      '[MANAGER] team load start business_profile=$profileId department=$scopedDepartmentId',
    );
    debugPrint(
      '[SCOPED_DATA_REQUEST] feature=workforce operation=manager_team method=GET endpoint_or_collection=/items/business_profile_members membership_id=${workspace.membershipId} business_profile=$profileId department=$scopedDepartmentId membership_role=${workspace.memberRole} context_source=${OrganizationService.instance.activeWorkspaceContextSource} workspace_revision=$startRevision filter_summary=business_profile=$profileId;department=${scopedDepartmentId ?? ''};status=active;limit=200 started=true trace=$trace',
    );

    try {
      final memberRows = await MemberIdentityService.instance
          .fetchBusinessProfileMembers(
            screen: 'ManagerTeam',
            businessProfileId: profileId,
            limit: 200,
            sort: '-date_created',
            activeOnly: true,
            departmentId: scopedDepartmentId,
            role: 'manager',
            membershipId: workspace?.membershipId,
          );
      debugPrint(
        '[SCOPED_DATA_RESPONSE] feature=workforce operation=manager_team http_status=200 result_count=${memberRows.length} duration_ms=0 membership_id=${workspace.membershipId} business_profile=$profileId workspace_revision_before=$startRevision workspace_revision_after=${OrganizationService.instance.workspaceRevision} context_unchanged=${OrganizationService.instance.workspaceRevision == startRevision && OrganizationService.instance.workspaceSignature == startSignature} returned_business_profile_ids=[$profileId] returned_membership_ids=${memberRows.map((row) => row['id']?.toString() ?? '').where((v) => v.isNotEmpty).toSet().toList()} empty_result=${memberRows.isEmpty} trace=$trace',
      );

      // Optional enrichment: wellness_scans + scan_results are used only to
      // hydrate "latest readiness" and "last check" for each member. If these
      // collections are unavailable to the Manager role (403/404/500), the
      // team roster must still render — degrade to unknown readiness rather
      // than blank the whole page.
      final scanRows = <Map<String, dynamic>>[];
      try {
        final scansQuery = <String, dynamic>{
          'limit': 300,
          'sort': '-date_created',
          'fields': 'id,user,status,completed_at,date_created',
          'filter[business_profile][_eq]': profileId,
        };
        final scansRes = await _client.get(
          '/items/wellness_scans',
          queryParameters: scansQuery,
        );
        final scansData = scansRes.data['data'];
        if (scansData is List) {
          scanRows.addAll(scansData.whereType<Map<String, dynamic>>());
        }
      } on DioException catch (e) {
        debugPrint(
          '[MANAGER] wellness_scans enrichment skipped status=${e.response?.statusCode} type=${e.type}',
        );
      }

      final scanIds = scanRows
          .map((e) => e['id']?.toString() ?? '')
          .where((e) => e.isNotEmpty)
          .toList();

      Map<String, String> resultByScan = const {};
      try {
        resultByScan = await ReadinessResultService.instance
            .fetchLabelByScanIds(scanIds);
      } on DioException catch (e) {
        debugPrint(
          '[MANAGER] scan_results enrichment skipped status=${e.response?.statusCode} type=${e.type}',
        );
      }

      final latestCompletedByUser = <String, Map<String, dynamic>>{};
      final latestAnyByUser = <String, Map<String, dynamic>>{};
      for (final scan in scanRows) {
        final user = scan['user'];
        final userId = user is Map
            ? user['id']?.toString() ?? ''
            : user?.toString() ?? '';
        if (userId.isEmpty) continue;
        latestAnyByUser.putIfAbsent(userId, () => scan);
        if (_isCompletedScanRow(scan)) {
          latestCompletedByUser.putIfAbsent(userId, () => scan);
        }
      }

      final now = DateTime.now();
      final list = <ManagerMemberView>[];
      for (final row in memberRows) {
        final user = row['user'];
        final dept = row['department'];
        final deptName = dept is Map ? dept['name']?.toString() : null;
        final deptId = dept is Map ? dept['id']?.toString() : dept?.toString();
        final identity = MemberIdentityService.instance.resolveFromUserRelation(
          user,
          context: 'manager_team',
          memberId: row['id']?.toString() ?? '',
          role: row['member_role']?.toString(),
          departmentRaw: dept,
          employeeCode: row['employee_code']?.toString(),
        );
        final userId = identity.userId;

        final latestScan =
            latestCompletedByUser[userId] ?? latestAnyByUser[userId];
        final scanId = latestScan?['id']?.toString() ?? '';
        final latestState = scanId.isNotEmpty ? resultByScan[scanId] : null;
        final needsAttention =
            latestState == 'Elevated Fatigue' || latestState == 'High Risk';
        final lastCheck = _parseDate(
          latestScan?['completed_at'] ?? latestScan?['date_created'],
        );
        final missingCheck =
            lastCheck == null ||
            !(lastCheck.toLocal().year == now.year &&
                lastCheck.toLocal().month == now.month &&
                lastCheck.toLocal().day == now.day);

        list.add(
          ManagerMemberView(
            memberId: row['id']?.toString() ?? '',
            userId: userId,
            name: identity.name,
            email: identity.email ?? '',
            role: row['member_role']?.toString() ?? '',
            status: row['status']?.toString() ?? '',
            departmentName: deptName,
            departmentId: deptId,
            latestReadiness: latestState,
            lastCheckAt: lastCheck,
            needsAttention: needsAttention,
            missingCheck: missingCheck,
          ),
        );
      }
      debugPrint('[MANAGER] team load success count=${list.length}');
      if (_isWorkspaceStale(startRevision, startSignature)) {
        _logStaleResult();
        return const [];
      }
      return list;
    } on DioException catch (e) {
      debugPrint(
        '[MANAGER] team load fail status=${e.response?.statusCode} body=${e.response?.data}',
      );
      rethrow;
    }
  }

  Future<ManagerSnapshot> fetchSnapshot() async {
    final startRevision = OrganizationService.instance.workspaceRevision;
    final startSignature = OrganizationService.instance.workspaceSignature;
    final team = await fetchTeam();
    final workspace = await OrganizationService.instance
        .fetchActiveWorkspaceContext();
    final profileId = workspace?.businessProfileId.trim() ?? '';
    final departmentId = workspace?.departmentId?.trim() ?? '';
    final currentUserId = workspace?.currentUserId.trim() ?? '';
    final trace = OrganizationService.instance.activeSwitchTrace ?? 'none';
    if (workspace == null ||
        profileId.isEmpty ||
        departmentId.isEmpty ||
        currentUserId.isEmpty) {
      debugPrint(
        '[MANAGER] snapshot unavailable workspace=${workspace != null} profile=$profileId department=$departmentId current_user=${currentUserId.isNotEmpty}',
      );
      return const ManagerSnapshot(
        teamMembers: -1,
        pendingRequests: -1,
        checksCompletedToday: -1,
        missingChecks: -1,
        attentionOutcomes: -1,
        openAlerts: -1,
        readinessDistribution: {
          'Stable': 0,
          'Low Focus': 0,
          'Elevated Fatigue': 0,
          'High Risk': 0,
        },
      );
    }
    if (_isWorkspaceStale(startRevision, startSignature)) {
      _logStaleResult();
      return const ManagerSnapshot(
        teamMembers: -1,
        pendingRequests: -1,
        checksCompletedToday: -1,
        missingChecks: -1,
        attentionOutcomes: -1,
        openAlerts: -1,
        readinessDistribution: {
          'Stable': 0,
          'Low Focus': 0,
          'Elevated Fatigue': 0,
          'High Risk': 0,
        },
      );
    }
    debugPrint(
      '[SCOPED_DATA_REQUEST] feature=reports operation=manager_snapshot method=GET endpoint_or_collection=/items/scan_results membership_id=${workspace?.membershipId.trim() ?? ''} business_profile=${workspace?.businessProfileId.trim() ?? ''} department=${workspace?.departmentId?.trim() ?? ''} membership_role=${workspace?.memberRole ?? ''} context_source=${OrganizationService.instance.activeWorkspaceContextSource} workspace_revision=$startRevision filter_summary=business_profile=${workspace?.businessProfileId.trim() ?? ''};scan_results;alerts;scan_requests started=true trace=${OrganizationService.instance.activeSwitchTrace ?? 'none'}',
    );
    final activeMembers = team
        .where((m) => m.status.toLowerCase() == 'active')
        .length;
    final checksToday = team.where((m) => !m.missingCheck).length;
    final missing = team.where((m) => m.missingCheck).length;
    final attention = team.where((m) => m.needsAttention).length;

    int openAlerts = -1;
    int pendingRequests = -1;
    try {
      if (profileId.isNotEmpty) {
        debugPrint(
          '[SCOPED_DATA_REQUEST] feature=alerts operation=manager_snapshot_alerts method=GET endpoint_or_collection=/items/alerts membership_id=${workspace?.membershipId.trim() ?? ''} business_profile=$profileId department=$departmentId membership_role=${workspace?.memberRole ?? ''} context_source=${OrganizationService.instance.activeWorkspaceContextSource} workspace_revision=$startRevision filter_summary=business_profile=$profileId;department=$departmentId;limit=100 started=true trace=${OrganizationService.instance.activeSwitchTrace ?? 'none'}',
        );
        final alerts = await _client.get(
          '/items/alerts',
          queryParameters: {
            'limit': 100,
            'fields': 'id,status,business_profile,department',
            'filter[business_profile][_eq]': profileId,
            if (departmentId.isNotEmpty)
              'filter[department][_eq]': departmentId,
          },
        );
        final data = alerts.data['data'];
        if (data is List) {
          openAlerts = data.whereType<Map<String, dynamic>>().where((e) {
            final s = e['status']?.toString().toLowerCase() ?? '';
            return s != 'resolved' && s != 'closed';
          }).length;
        }
        debugPrint(
          '[SCOPED_DATA_RESPONSE] feature=alerts operation=manager_snapshot_alerts http_status=${alerts.statusCode ?? 0} result_count=$openAlerts duration_ms=0 membership_id=${workspace?.membershipId.trim() ?? ''} business_profile=$profileId workspace_revision_before=$startRevision workspace_revision_after=${OrganizationService.instance.workspaceRevision} context_unchanged=${OrganizationService.instance.workspaceRevision == startRevision && OrganizationService.instance.workspaceSignature == startSignature} returned_business_profile_ids=[$profileId] returned_membership_ids=[${workspace?.membershipId.trim() ?? ''}] empty_result=${openAlerts == 0} trace=${OrganizationService.instance.activeSwitchTrace ?? 'none'}',
        );
      }
    } catch (_) {
      openAlerts = -1;
    }
    try {
      final pending = await RequestService.instance.fetchManagerRequests(
        statusFilter: 'pending',
      );
      pendingRequests = pending.length;
      debugPrint(
        '[SCOPED_DATA_RESPONSE] feature=requests operation=manager_snapshot_requests http_status=200 result_count=$pendingRequests duration_ms=0 membership_id=${workspace?.membershipId.trim() ?? ''} business_profile=$profileId workspace_revision_before=$startRevision workspace_revision_after=${OrganizationService.instance.workspaceRevision} context_unchanged=${OrganizationService.instance.workspaceRevision == startRevision && OrganizationService.instance.workspaceSignature == startSignature} returned_business_profile_ids=[$profileId] returned_membership_ids=[${workspace?.membershipId.trim() ?? ''}] empty_result=${pendingRequests == 0} trace=${OrganizationService.instance.activeSwitchTrace ?? 'none'}',
      );
    } catch (_) {
      pendingRequests = -1;
    }
    if (_isWorkspaceStale(startRevision, startSignature)) {
      _logStaleResult();
      return const ManagerSnapshot(
        teamMembers: -1,
        pendingRequests: -1,
        checksCompletedToday: -1,
        missingChecks: -1,
        attentionOutcomes: -1,
        openAlerts: -1,
        readinessDistribution: {
          'Stable': 0,
          'Low Focus': 0,
          'Elevated Fatigue': 0,
          'High Risk': 0,
        },
      );
    }

    final readinessDistribution = <String, int>{
      'Stable': 0,
      'Low Focus': 0,
      'Elevated Fatigue': 0,
      'High Risk': 0,
    };
    for (final member in team) {
      if (currentUserId.isNotEmpty && member.userId.trim() == currentUserId) {
        continue;
      }
      final label = member.latestReadiness;
      if (label != null && readinessDistribution.containsKey(label)) {
        readinessDistribution[label] = (readinessDistribution[label] ?? 0) + 1;
      }
    }

    debugPrint('[MANAGER_READINESS_DISTRIBUTION] source=/items/scan_results');
    debugPrint('[MANAGER_READINESS_DISTRIBUTION] business_profile=$profileId');
    debugPrint(
      '[MANAGER_READINESS_DISTRIBUTION] department=${departmentId.isEmpty ? 'none' : departmentId}',
    );
    debugPrint(
      '[MANAGER_READINESS_DISTRIBUTION] raw_count=${team.where((member) => member.latestReadiness != null).length}',
    );
    debugPrint(
      '[MANAGER_READINESS_DISTRIBUTION] normalized_counts={stable:${readinessDistribution['Stable'] ?? 0},low_focus:${readinessDistribution['Low Focus'] ?? 0},elevated_fatigue:${readinessDistribution['Elevated Fatigue'] ?? 0},high_risk:${readinessDistribution['High Risk'] ?? 0}}',
    );

    return ManagerSnapshot(
      teamMembers: activeMembers,
      pendingRequests: pendingRequests,
      checksCompletedToday: checksToday,
      missingChecks: missing,
      attentionOutcomes: attention,
      openAlerts: openAlerts,
      readinessDistribution: readinessDistribution,
    );
  }

  DateTime? _parseDate(dynamic raw) {
    if (raw == null) return null;
    return DateTime.tryParse(raw.toString());
  }

  bool _isWorkspaceStale(int startRevision, String startSignature) {
    return OrganizationService.instance.workspaceRevision != startRevision ||
        OrganizationService.instance.workspaceSignature != startSignature;
  }

  void _logStaleResult() {
    debugPrint(
      '[WORKSPACE_GUARD] stale_result_ignored=true service=ManagerOpsService',
    );
  }

  bool _isCompletedScanRow(Map<String, dynamic> row) {
    final status = row['status']?.toString().trim().toLowerCase() ?? '';
    if (status == 'completed') return true;
    if (status == 'complete' || status == 'done') return true;
    return row['completed_at'] != null;
  }
}

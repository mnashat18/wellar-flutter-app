import '../utils/safe_debug_log.dart';
import 'package:dio/dio.dart';

import 'directus_client.dart';
import 'member_identity_service.dart';
import 'organization_service.dart';
import 'readiness_result_service.dart';
import 'request_service.dart';
import 'wellar_workforce_service.dart';

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
  final DateTime? joinedAt;
  final String? lastReadinessScore;
  final bool? todaysScan;
  final String? presenceStatus;

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
    this.joinedAt,
    this.lastReadinessScore,
    this.todaysScan,
    this.presenceStatus,
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
  final String? workforceUnavailableMessage;
  final bool noDepartmentAssigned;

  const ManagerSnapshot({
    required this.teamMembers,
    required this.pendingRequests,
    required this.checksCompletedToday,
    required this.missingChecks,
    required this.attentionOutcomes,
    required this.openAlerts,
    required this.readinessDistribution,
    this.workforceUnavailableMessage,
    this.noDepartmentAssigned = false,
  });
}

class ManagerWorkforceData {
  final List<ManagerMemberView> members;
  final Map<String, dynamic> summary;

  const ManagerWorkforceData({required this.members, this.summary = const {}});
}

class ManagerOpsService {
  ManagerOpsService._();
  static final ManagerOpsService instance = ManagerOpsService._();

  Dio get _client => DirectusClient.instance.client;

  void clearOrganizationScopedCaches() {}

  Future<List<ManagerMemberView>> fetchTeam() async {
    return (await fetchWorkforceData()).members;
  }

  Future<ManagerWorkforceData> fetchWorkforceData() async {
    final workspace = await OrganizationService.instance
        .fetchActiveWorkspaceContext();
    final businessProfileId = workspace?.businessProfileId.trim() ?? '';
    final membershipId = workspace?.membershipId.trim() ?? '';
    final role = (workspace?.finalEffectiveRole ?? workspace?.memberRole ?? '')
        .trim()
        .toLowerCase();
    if (businessProfileId.isEmpty ||
        membershipId.isEmpty ||
        (role.isNotEmpty && role != 'manager')) {
      return const ManagerWorkforceData(members: []);
    }
    final result = await WellarWorkforceService.instance
        .fetchWorkforceFromWellar();
    if (result.networkError) {
      return ManagerWorkforceData(members: await _fetchTeamLegacy());
    }
    if (!result.isSuccessful) throw result.asFailure();
    final members = result.memberRows.map((row) {
      final risk = _normalizeWorkforceRisk(row['last_risk_level']);
      final userId = row['user_id']?.toString().trim() ?? '';
      final departmentId = row['department_id']?.toString().trim() ?? '';
      final departmentName = row['department_name']?.toString().trim() ?? '';
      return ManagerMemberView(
        memberId: _rowString(row['member_id']).isNotEmpty
            ? _rowString(row['member_id'])
            : _rowString(row['id']),
        userId: userId,
        name: _rowString(row['display_name']),
        email: _rowString(row['email']),
        role: _rowString(row['member_role']),
        status: _rowString(row['status']),
        departmentName: departmentName.isEmpty ? null : departmentName,
        departmentId: departmentId.isEmpty ? null : departmentId,
        latestReadiness: risk,
        lastCheckAt: _parseDate(row['last_scan_at']),
        needsAttention: risk == 'Elevated Fatigue' || risk == 'High Risk',
        missingCheck: _workforceMissing(row),
        joinedAt: _parseDate(row['joined_at']),
        lastReadinessScore: _rowString(row['last_readiness_score']).isEmpty
            ? null
            : _rowString(row['last_readiness_score']),
        todaysScan: row['todays_scan'] is bool
            ? row['todays_scan'] as bool
            : null,
        presenceStatus: _rowString(row['presence_status']).isEmpty
            ? null
            : _rowString(row['presence_status']),
      );
    }).toList();
    return ManagerWorkforceData(members: members, summary: result.summary);
  }

  String _rowString(dynamic value) => value?.toString().trim() ?? '';

  String? _normalizeWorkforceRisk(dynamic value) {
    final normalized = _rowString(value).toLowerCase().replaceAll('_', ' ');
    return switch (normalized) {
      'stable' => 'Stable',
      'low focus' => 'Low Focus',
      'elevated fatigue' => 'Elevated Fatigue',
      'high risk' => 'High Risk',
      _ => null,
    };
  }

  bool _workforceMissing(Map<String, dynamic> row) {
    if (row['todays_scan'] is bool) return row['todays_scan'] != true;
    final presence = _rowString(row['presence_status']).toLowerCase();
    return presence == 'missing' ||
        presence == 'missing_scan' ||
        presence == 'not_scanned';
  }

  int _summaryInt(
    Map<String, dynamic> summary,
    String key, {
    required int fallback,
  }) {
    if (!summary.containsKey(key)) return fallback;
    final value = summary[key];
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  Future<List<ManagerMemberView>> _fetchTeamLegacy() async {
    final startRevision = OrganizationService.instance.workspaceRevision;
    final startSignature = OrganizationService.instance.workspaceSignature;
    ActiveWorkspaceContext? workspace;
    try {
      workspace = await OrganizationService.instance
          .fetchActiveWorkspaceContext();
    } on DioException catch (error) {
      safeDebugLog(
        '[MANAGER] step=workspace_check status=${error.response?.statusCode ?? 0} dio_type=${error.type.name} error_type=${error.runtimeType}',
      );
      rethrow;
    } catch (error) {
      safeDebugLog(
        '[MANAGER] step=workspace_check status=0 dio_type=none error_type=${error.runtimeType}',
      );
      rethrow;
    }
    if (workspace == null || workspace.businessProfileId.trim().isEmpty) {
      safeDebugLog(
        '[MANAGER] step=workspace_check status=0 dio_type=none error_type=missing_context',
      );
      return const [];
    }
    final profileId = workspace.businessProfileId.trim();
    final scopedDepartmentId = workspace.departmentId?.trim();
    final trace = OrganizationService.instance.activeSwitchTrace ?? 'none';
    safeDebugLog('[MANAGER] step=team status=0 dio_type=none error_type=none');
    safeDebugLog(
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
      safeDebugLog(
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
        safeDebugLog(
          '[MANAGER] step=wellness_scans status=${e.response?.statusCode ?? 0} dio_type=${e.type.name} error_type=${e.runtimeType}',
        );
      } catch (error) {
        safeDebugLog(
          '[MANAGER] step=wellness_scans status=0 dio_type=none error_type=${error.runtimeType}',
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
        safeDebugLog(
          '[MANAGER] step=scan_results status=${e.response?.statusCode ?? 0} dio_type=${e.type.name} error_type=${e.runtimeType}',
        );
      } catch (error) {
        safeDebugLog(
          '[MANAGER] step=scan_results status=0 dio_type=none error_type=${error.runtimeType}',
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
      safeDebugLog(
        '[MANAGER] step=team status=200 dio_type=none error_type=none result_count=${list.length}',
      );
      if (_isWorkspaceStale(startRevision, startSignature)) {
        _logStaleResult();
        return const [];
      }
      return list;
    } on DioException catch (e) {
      safeDebugLog(
        '[MANAGER] step=team status=${e.response?.statusCode ?? 0} dio_type=${e.type.name} error_type=${e.runtimeType}',
      );
      rethrow;
    } catch (error) {
      safeDebugLog(
        '[MANAGER] step=team status=0 dio_type=none error_type=${error.runtimeType}',
      );
      rethrow;
    }
  }

  Future<ManagerSnapshot> fetchSnapshot() async {
    final startRevision = OrganizationService.instance.workspaceRevision;
    final startSignature = OrganizationService.instance.workspaceSignature;
    ActiveWorkspaceContext? workspace;
    try {
      workspace = await OrganizationService.instance
          .fetchActiveWorkspaceContext();
    } on DioException catch (error) {
      safeDebugLog(
        '[MANAGER] step=workspace_check status=${error.response?.statusCode ?? 0} dio_type=${error.type.name} error_type=${error.runtimeType}',
      );
      rethrow;
    } catch (error) {
      safeDebugLog(
        '[MANAGER] step=workspace_check status=0 dio_type=none error_type=${error.runtimeType}',
      );
      rethrow;
    }
    final profileId = workspace?.businessProfileId.trim() ?? '';
    final membershipId = workspace?.membershipId.trim() ?? '';
    final departmentId = workspace?.departmentId?.trim() ?? '';
    final currentUserId = workspace?.currentUserId.trim() ?? '';
    final role = (workspace?.finalEffectiveRole ?? workspace?.memberRole ?? '')
        .trim()
        .toLowerCase();
    final missingFields = <String>[
      if (workspace == null) 'workspace',
      if (profileId.isEmpty) 'business_profile_id',
      if (membershipId.isEmpty) 'membership_id',
      if (currentUserId.isEmpty) 'current_user_id',
      if (role == 'manager' && departmentId.isEmpty) 'department_id',
    ];
    safeDebugLog(
      '[MANAGER_OPEN] missing_fields=${missingFields.isEmpty ? 'none' : missingFields.join(',')} workspace_present=${workspace != null} business_profile_present=${profileId.isNotEmpty} membership_present=${membershipId.isNotEmpty} current_user_present=${currentUserId.isNotEmpty} manager_role=${role == 'manager'} department_present=${departmentId.isNotEmpty}',
    );
    if (role == 'manager' && departmentId.isEmpty) {
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
        noDepartmentAssigned: true,
      );
    }
    List<ManagerMemberView> team = const [];
    Map<String, dynamic> workforceSummary = const {};
    String? workforceUnavailableMessage;
    try {
      final workforce = await fetchWorkforceData();
      team = workforce.members;
      workforceSummary = workforce.summary;
    } catch (error) {
      final status = error is DioException
          ? error.response?.statusCode ?? 0
          : 0;
      safeDebugLog(
        '[MANAGER_SNAPSHOT_SECTION_FAILED] step=workforce http_status=$status error_type=${error.runtimeType}',
      );
      workforceUnavailableMessage =
          'Workforce data is unavailable right now. Other dashboard data is still available.';
    }
    final trace = OrganizationService.instance.activeSwitchTrace ?? 'none';
    if (workspace == null ||
        profileId.isEmpty ||
        departmentId.isEmpty ||
        currentUserId.isEmpty) {
      safeDebugLog(
        '[MANAGER] step=workspace_check status=0 dio_type=none error_type=incomplete_context',
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
    safeDebugLog(
      '[SCOPED_DATA_REQUEST] feature=reports operation=manager_snapshot method=GET endpoint_or_collection=/items/scan_results membership_id=${workspace?.membershipId.trim() ?? ''} business_profile=${workspace?.businessProfileId.trim() ?? ''} department=${workspace?.departmentId?.trim() ?? ''} membership_role=${workspace?.memberRole ?? ''} context_source=${OrganizationService.instance.activeWorkspaceContextSource} workspace_revision=$startRevision filter_summary=business_profile=${workspace?.businessProfileId.trim() ?? ''};scan_results;alerts;scan_requests started=true trace=${OrganizationService.instance.activeSwitchTrace ?? 'none'}',
    );
    final activeMembers = workforceUnavailableMessage != null
        ? -1
        : _summaryInt(
            workforceSummary,
            'activeMembers',
            fallback: team
                .where((m) => m.status.toLowerCase() == 'active')
                .length,
          );
    final checksToday = workforceUnavailableMessage != null
        ? -1
        : _summaryInt(
            workforceSummary,
            'completedToday',
            fallback: team.where((m) => !m.missingCheck).length,
          );
    final missing = workforceUnavailableMessage != null
        ? -1
        : _summaryInt(
            workforceSummary,
            'missingScans',
            fallback: team.where((m) => m.missingCheck).length,
          );
    final attention = workforceUnavailableMessage != null
        ? -1
        : _summaryInt(
            workforceSummary,
            'needsAttention',
            fallback: team.where((m) => m.needsAttention).length,
          );

    int openAlerts = -1;
    int pendingRequests = -1;
    try {
      if (profileId.isNotEmpty) {
        safeDebugLog(
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
        safeDebugLog(
          '[SCOPED_DATA_RESPONSE] feature=alerts operation=manager_snapshot_alerts http_status=${alerts.statusCode ?? 0} result_count=$openAlerts duration_ms=0 membership_id=${workspace?.membershipId.trim() ?? ''} business_profile=$profileId workspace_revision_before=$startRevision workspace_revision_after=${OrganizationService.instance.workspaceRevision} context_unchanged=${OrganizationService.instance.workspaceRevision == startRevision && OrganizationService.instance.workspaceSignature == startSignature} returned_business_profile_ids=[$profileId] returned_membership_ids=[${workspace?.membershipId.trim() ?? ''}] empty_result=${openAlerts == 0} trace=${OrganizationService.instance.activeSwitchTrace ?? 'none'}',
        );
      }
    } on DioException catch (error) {
      safeDebugLog(
        '[MANAGER] step=alerts status=${error.response?.statusCode ?? 0} dio_type=${error.type.name} error_type=${error.runtimeType}',
      );
      openAlerts = -1;
    } catch (error) {
      safeDebugLog(
        '[MANAGER] step=alerts status=0 dio_type=none error_type=${error.runtimeType}',
      );
      openAlerts = -1;
    }
    try {
      final pending = await RequestService.instance.fetchManagerRequests(
        statusFilter: 'pending',
      );
      pendingRequests = pending.length;
      safeDebugLog(
        '[SCOPED_DATA_RESPONSE] feature=requests operation=manager_snapshot_requests http_status=200 result_count=$pendingRequests duration_ms=0 membership_id=${workspace?.membershipId.trim() ?? ''} business_profile=$profileId workspace_revision_before=$startRevision workspace_revision_after=${OrganizationService.instance.workspaceRevision} context_unchanged=${OrganizationService.instance.workspaceRevision == startRevision && OrganizationService.instance.workspaceSignature == startSignature} returned_business_profile_ids=[$profileId] returned_membership_ids=[${workspace?.membershipId.trim() ?? ''}] empty_result=${pendingRequests == 0} trace=${OrganizationService.instance.activeSwitchTrace ?? 'none'}',
      );
    } on DioException catch (error) {
      safeDebugLog(
        '[MANAGER] step=requests status=${error.response?.statusCode ?? 0} dio_type=${error.type.name} error_type=${error.runtimeType}',
      );
      pendingRequests = -1;
    } catch (error) {
      safeDebugLog(
        '[MANAGER] step=requests status=0 dio_type=none error_type=${error.runtimeType}',
      );
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

    safeDebugLog('[MANAGER_READINESS_DISTRIBUTION] source=/items/scan_results');
    safeDebugLog(
      '[MANAGER_READINESS_DISTRIBUTION] business_profile=$profileId',
    );
    safeDebugLog(
      '[MANAGER_READINESS_DISTRIBUTION] department=${departmentId.isEmpty ? 'none' : departmentId}',
    );
    safeDebugLog(
      '[MANAGER_READINESS_DISTRIBUTION] raw_count=${team.where((member) => member.latestReadiness != null).length}',
    );
    safeDebugLog(
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
      workforceUnavailableMessage: workforceUnavailableMessage,
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
    safeDebugLog(
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

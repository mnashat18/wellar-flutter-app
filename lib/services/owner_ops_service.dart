import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../models/scan_result.dart';
import '../models/workspace_department.dart';
import 'alert_service.dart';
import 'directus_client.dart';
import 'hr_ops_service.dart';
import 'member_identity_service.dart';
import 'organization_service.dart';
import 'readiness_result_service.dart';
import 'request_service.dart';
import '../state/session.dart';
import '../utils/request_status_normalizer.dart';

class OwnerCompanySummary {
  final String workspaceName;
  final bool? isActive;
  final String? planCode;
  final String? billingStatus;
  final int teamSize;
  final int activeMembers;
  final int departmentsCount;

  const OwnerCompanySummary({
    required this.workspaceName,
    required this.isActive,
    required this.planCode,
    required this.billingStatus,
    required this.teamSize,
    required this.activeMembers,
    required this.departmentsCount,
  });
}

class OwnerMemberView {
  final String memberId;
  final String userId;
  final String name;
  final String email;
  final String role;
  final String status;
  final String? departmentId;
  final String? departmentName;
  final String? latestReadiness;
  final DateTime? lastCheckAt;
  final bool needsAttention;
  final bool missingCheck;
  final bool hasOpenAlert;
  final bool hasOverdueRequest;
  final bool requiresLinking;

  const OwnerMemberView({
    required this.memberId,
    required this.userId,
    required this.name,
    required this.email,
    required this.role,
    required this.status,
    required this.departmentId,
    required this.departmentName,
    required this.latestReadiness,
    required this.lastCheckAt,
    required this.needsAttention,
    required this.missingCheck,
    required this.hasOpenAlert,
    required this.hasOverdueRequest,
    required this.requiresLinking,
  });

  bool get isActive => status.trim().toLowerCase() == 'active';

  String get displayName {
    final rawName = name.trim();
    if (rawName.isNotEmpty) return rawName;
    return MemberIdentityService.memberProfileUnavailableLabel;
  }

  String get displayEmail {
    final rawEmail = email.trim();
    if (rawEmail.isNotEmpty) return rawEmail;
    return MemberIdentityService.memberProfileUnavailableLabel;
  }

  String get departmentLabel {
    final value = departmentName?.trim() ?? '';
    if (value.isNotEmpty) return value;
    return MemberIdentityService.noDepartmentLabel;
  }

  String get roleKey => _normalizeRoleKey(role);

  String get roleLabel => _roleLabel(roleKey);
}

class OwnerWorkforceDirectoryData {
  final List<OwnerMemberView> members;
  final List<WorkspaceDepartment> departments;

  const OwnerWorkforceDirectoryData({
    required this.members,
    required this.departments,
  });
}

class OwnerSnapshot {
  final int activeMembers;
  final int departmentsCount;
  final int scanRequestsToday;
  final int checksCompletedToday;
  final int missingChecks;
  final int pendingScans;
  final int attentionOutcomes;
  final int openAlerts;
  final int pendingRequests;
  final String complianceRate;
  final Map<String, int> readinessDistribution;

  const OwnerSnapshot({
    required this.activeMembers,
    required this.departmentsCount,
    required this.scanRequestsToday,
    required this.checksCompletedToday,
    required this.missingChecks,
    required this.pendingScans,
    required this.attentionOutcomes,
    required this.openAlerts,
    required this.pendingRequests,
    required this.complianceRate,
    required this.readinessDistribution,
  });
}

class OwnerReportSummary {
  final int todayCompleted;
  final int last7DaysCompleted;
  final String completionRate;
  final int missingChecks;
  final int attentionOutcomes;
  final int openAlerts;
  final Map<String, int> readinessDistribution;

  const OwnerReportSummary({
    required this.todayCompleted,
    required this.last7DaysCompleted,
    required this.completionRate,
    required this.missingChecks,
    required this.attentionOutcomes,
    required this.openAlerts,
    required this.readinessDistribution,
  });
}

class OwnerRequestCounts {
  final int pending;
  final int completed;
  final int overdue;

  const OwnerRequestCounts({
    required this.pending,
    required this.completed,
    required this.overdue,
  });
}

class OwnerAssessmentResult {
  final String scanId;
  final String? outcome;
  final String? readinessScore;
  final DateTime? completedAt;

  const OwnerAssessmentResult({
    required this.scanId,
    required this.outcome,
    required this.readinessScore,
    required this.completedAt,
  });
}

class WorkspaceReadinessSummary {
  final Map<String, int> distribution;
  final Map<String, OwnerAssessmentResult> resultsByScanId;
  final bool queryFailed;

  const WorkspaceReadinessSummary({
    required this.distribution,
    required this.resultsByScanId,
    required this.queryFailed,
  });

  int get totalCount =>
      distribution.values.fold(0, (sum, value) => sum + value);
}

class OwnerAssessmentLookupResult {
  final Map<String, OwnerAssessmentResult> resultsByScanId;
  final bool queryFailed;

  const OwnerAssessmentLookupResult({
    required this.resultsByScanId,
    required this.queryFailed,
  });
}

class OwnerOpsService {
  OwnerOpsService._();
  static final OwnerOpsService instance = OwnerOpsService._();

  Dio get _client => DirectusClient.instance.client;
  ActiveWorkspaceContext? _cachedWorkspaceContext;
  Future<ActiveWorkspaceContext?>? _workspaceContextFuture;
  String? _cachedWorkspaceSignature;
  OwnerWorkforceDirectoryData? _cachedWorkforceBundle;
  Future<OwnerWorkforceDirectoryData>? _workforceBundleFuture;

  void clearOrganizationScopedCaches() {
    _cachedWorkspaceContext = null;
    _workspaceContextFuture = null;
    _cachedWorkforceBundle = null;
    _cachedWorkspaceSignature = null;
    _workforceBundleFuture = null;
  }

  String _workspaceRole(ActiveWorkspaceContext? workspace) {
    final explicit = (workspace?.finalEffectiveRole ?? '').trim().toLowerCase();
    if (explicit.isNotEmpty) return explicit;
    return (workspace?.memberRole ?? '').trim().toLowerCase();
  }

  Future<List<WorkspaceDepartment>> fetchDepartments({
    bool forceRefresh = false,
  }) async {
    final data = await fetchWorkforceDirectory(forceRefresh: forceRefresh);
    return data.departments;
  }

  Future<List<OwnerMemberView>> fetchWorkforce({
    bool forceRefresh = false,
  }) async {
    final data = await fetchWorkforceDirectory(forceRefresh: forceRefresh);
    return data.members;
  }

  Future<OwnerWorkforceDirectoryData> fetchWorkforceDirectory({
    bool forceRefresh = false,
  }) async {
    final startRevision = OrganizationService.instance.workspaceRevision;
    final startSignature = OrganizationService.instance.workspaceSignature;
    final workspace = await _activeWorkspace(forceRefresh: forceRefresh);
    final profileId = workspace?.businessProfileId.trim() ?? '';
    final membershipId = workspace?.membershipId.trim() ?? '';
    final activeRole = _workspaceRole(workspace);
    if (activeRole.isNotEmpty && activeRole != 'owner') {
      debugPrint(
        '[ROLE_SERVICE_GUARD] service=OwnerOpsService expected=owner actual=${activeRole.isEmpty ? "unknown" : activeRole} ignored=true',
      );
      debugPrint(
        '[STALE_ROLE_RESULT_IGNORED] service=OwnerOpsService expected_role=owner actual_role=${activeRole.isEmpty ? "unknown" : activeRole}',
      );
      return const OwnerWorkforceDirectoryData(members: [], departments: []);
    }
    if (_isWorkspaceStale(startRevision, startSignature)) {
      _logStaleResult();
      return const OwnerWorkforceDirectoryData(members: [], departments: []);
    }
    if (workspace == null ||
        profileId.isEmpty ||
        !_isActiveBusiness(workspace)) {
      return const OwnerWorkforceDirectoryData(members: [], departments: []);
    }
    final trace = OrganizationService.instance.activeSwitchTrace ?? 'none';
    final stopwatch = Stopwatch()..start();
    debugPrint(
      '[SCOPED_DATA_REQUEST] feature=workforce operation=fetch_directory method=GET endpoint_or_collection=/items/business_profile_members membership_id=$membershipId business_profile=$profileId department=${workspace.departmentId?.trim() ?? ''} membership_role=$activeRole context_source=${OrganizationService.instance.activeWorkspaceContextSource} workspace_revision=$startRevision filter_summary=business_profile=$profileId;status=active;limit=500 started=true trace=$trace',
    );

    if (!forceRefresh &&
        _cachedWorkforceBundle != null &&
        _cachedWorkspaceSignature == startSignature) {
      return _cachedWorkforceBundle!;
    }
    if (!forceRefresh &&
        _workforceBundleFuture != null &&
        _cachedWorkspaceSignature == startSignature) {
      return _workforceBundleFuture!;
    }

    _cachedWorkspaceSignature = startSignature;
    final future = _buildWorkforceDirectory(
      profileId,
      membershipId,
      workspace?.finalEffectiveRole ?? workspace?.memberRole ?? 'unknown',
    );
    _workforceBundleFuture = future;
    try {
      final data = await future;
      stopwatch.stop();
      debugPrint(
        '[SCOPED_DATA_RESPONSE] feature=workforce operation=fetch_directory http_status=200 result_count=${data.members.length} duration_ms=${stopwatch.elapsedMilliseconds} membership_id=$membershipId business_profile=$profileId workspace_revision_before=$startRevision workspace_revision_after=${OrganizationService.instance.workspaceRevision} context_unchanged=${OrganizationService.instance.workspaceRevision == startRevision && OrganizationService.instance.workspaceSignature == startSignature} returned_business_profile_ids=[$profileId] returned_membership_ids=${data.members.map((m) => m.memberId).where((v) => v.isNotEmpty).toSet().toList()} empty_result=${data.members.isEmpty} trace=$trace',
      );
      if (_isWorkspaceStale(startRevision, startSignature)) {
        _logStaleResult();
        return const OwnerWorkforceDirectoryData(members: [], departments: []);
      }
      _cachedWorkforceBundle = data;
      return data;
    } finally {
      if (stopwatch.isRunning) {
        stopwatch.stop();
      }
      if (identical(_workforceBundleFuture, future)) {
        _workforceBundleFuture = null;
      }
    }
  }

  Future<OwnerWorkforceDirectoryData> _buildWorkforceDirectory(
    String profileId,
    String membershipId,
    String role,
  ) async {
    debugPrint(
      '[OWNER] workforce load start scoped_profile=${profileId.trim().isNotEmpty}',
    );
    final results = await Future.wait<dynamic>([
      _fetchWorkforceMembersForProfile(profileId, membershipId, role),
      _fetchDepartmentsForProfile(profileId),
    ]);
    return OwnerWorkforceDirectoryData(
      members: results[0] as List<OwnerMemberView>,
      departments: results[1] as List<WorkspaceDepartment>,
    );
  }

  Future<ActiveWorkspaceContext?> _activeWorkspace({
    bool forceRefresh = false,
  }) async {
    final currentSignature = OrganizationService.instance.workspaceSignature;
    if (!forceRefresh &&
        _cachedWorkspaceContext != null &&
        _cachedWorkspaceSignature == currentSignature) {
      return _cachedWorkspaceContext;
    }
    if (!forceRefresh &&
        _workspaceContextFuture != null &&
        _cachedWorkspaceSignature == currentSignature) {
      return _workspaceContextFuture;
    }
    final startRevision = OrganizationService.instance.workspaceRevision;
    final startSignature = currentSignature;
    final future = OrganizationService.instance.fetchActiveWorkspaceContext(
      forceRefresh: forceRefresh,
    );
    _workspaceContextFuture = future;
    try {
      final context = await future;
      if (_isWorkspaceStale(startRevision, startSignature)) {
        _logStaleResult();
        return null;
      }
      _cachedWorkspaceContext = context;
      _cachedWorkspaceSignature =
          OrganizationService.instance.workspaceSignature;
      return context;
    } finally {
      if (identical(_workspaceContextFuture, future)) {
        _workspaceContextFuture = null;
      }
    }
  }

  bool _isActiveBusiness(ActiveWorkspaceContext workspace) {
    final rawStatus = workspace.businessProfileStatus?.trim().toLowerCase();
    return rawStatus != 'false' && rawStatus != '0' && rawStatus != 'inactive';
  }

  Future<List<WorkspaceDepartment>> _fetchDepartmentsForProfile(
    String profileId,
  ) async {
    try {
      final response = await _client.get(
        '/items/departments',
        queryParameters: {
          'limit': 300,
          'sort': 'name',
          'fields': 'id,name',
          'filter[business_profile][_eq]': profileId,
        },
      );
      final data = response.data['data'];
      if (data is! List) return const [];
      final items = data
          .whereType<Map<String, dynamic>>()
          .map(
            (row) => WorkspaceDepartment(
              id: row['id']?.toString() ?? '',
              name: row['name']?.toString() ?? '',
            ),
          )
          .where((item) => item.id.trim().isNotEmpty)
          .toList();
      items.sort(
        (a, b) =>
            a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase()),
      );
      return items;
    } catch (_) {
      return const [];
    }
  }

  Future<List<OwnerMemberView>> _fetchWorkforceMembersForProfile(
    String profileId,
    String membershipId,
    String role,
  ) async {
    try {
      final results = await Future.wait<dynamic>([
        MemberIdentityService.instance.fetchBusinessProfileMembers(
          screen: 'OwnerWorkforce',
          businessProfileId: profileId,
          limit: 500,
          sort: '-date_created',
          activeOnly: true,
          role: role,
          membershipId: membershipId,
        ),
        _client.get(
          '/items/wellness_scans',
          queryParameters: {
            'limit': 800,
            'sort': '-date_created',
            'fields': 'id,user,status,completed_at,date_created',
            'filter[business_profile][_eq]': profileId,
          },
        ),
      ]);

      final memberRows = (results[0] as List<Map<String, dynamic>>).toList();
      final scansData = (results[1] as Response).data['data'];
      final scanRows = scansData is List
          ? scansData.whereType<Map<String, dynamic>>().toList()
          : <Map<String, dynamic>>[];
      final requestRows = await _fetchRequestRows(profileId);
      final alertRows = await _fetchAlertRows(profileId);

      final scanIds = scanRows
          .map((row) => row['id']?.toString() ?? '')
          .where((id) => id.isNotEmpty)
          .toList();
      final resultByScan = await ReadinessResultService.instance
          .fetchLabelByScanIds(scanIds);

      final latestCompletedByUser = <String, Map<String, dynamic>>{};
      final latestAnyByUser = <String, Map<String, dynamic>>{};
      for (final scan in scanRows) {
        final userId = _relationId(scan['user']);
        if (userId.isEmpty) continue;
        latestAnyByUser.putIfAbsent(userId, () => scan);
        if (_isCompletedScanRow(scan)) {
          latestCompletedByUser.putIfAbsent(userId, () => scan);
        }
      }

      final overdueMemberIds = _extractOverdueMemberIds(requestRows);
      final openAlertUserIds = _extractOpenAlertUserIds(alertRows);
      final now = DateTime.now();
      final members = <OwnerMemberView>[];

      for (final row in memberRows) {
        final memberId = row['id']?.toString() ?? '';
        final departmentRaw = row['department'];
        final departmentName = MemberIdentityService.instance
            .resolveDepartmentName(departmentRelation: departmentRaw);
        final identity = MemberIdentityService.instance.resolveFromUserRelation(
          row['user'],
          context: 'owner_workforce',
          memberId: memberId,
          role: row['member_role']?.toString(),
          departmentRaw: departmentRaw,
          employeeCode: row['employee_code']?.toString(),
        );
        final userId = identity.userId;
        final latestScan =
            latestCompletedByUser[userId] ?? latestAnyByUser[userId];
        final scanId = latestScan?['id']?.toString() ?? '';
        final latestState = scanId.isNotEmpty ? resultByScan[scanId] : null;
        final lastCheck = _parseDate(
          latestScan?['completed_at'] ?? latestScan?['date_created'],
        );

        members.add(
          OwnerMemberView(
            memberId: memberId,
            userId: userId,
            name: identity.name,
            email: identity.email ?? '',
            role: row['member_role']?.toString() ?? '',
            status: row['status']?.toString() ?? '',
            departmentId: MemberIdentityService.instance.resolveDepartmentId(
              departmentRaw,
            ),
            departmentName: departmentName,
            latestReadiness: latestState,
            lastCheckAt: lastCheck,
            needsAttention:
                latestState == 'Elevated Fatigue' || latestState == 'High Risk',
            missingCheck: !_isSameLocalDay(lastCheck, now),
            hasOpenAlert:
                userId.isNotEmpty && openAlertUserIds.contains(userId),
            hasOverdueRequest: overdueMemberIds.contains(memberId),
            requiresLinking: identity.requiresLinking,
          ),
        );
      }

      members.sort((a, b) {
        if (a.isActive != b.isActive) {
          return a.isActive ? -1 : 1;
        }
        return a.displayName.toLowerCase().compareTo(
          b.displayName.toLowerCase(),
        );
      });
      debugPrint('[OWNER] workforce load success count=${members.length}');
      return members;
    } on DioException catch (e) {
      debugPrint(
        '[OWNER] workforce load fail status=${e.response?.statusCode} error_type=${e.type}',
      );
      rethrow;
    }
  }

  Future<OwnerCompanySummary> fetchCompanySummary() async {
    final startRevision = OrganizationService.instance.workspaceRevision;
    final startSignature = OrganizationService.instance.workspaceSignature;
    final workspace = await _activeWorkspace();
    final profileId = workspace?.businessProfileId.trim() ?? '';
    final trace = OrganizationService.instance.activeSwitchTrace ?? 'none';
    if (_isWorkspaceStale(startRevision, startSignature)) {
      _logStaleResult();
      return const OwnerCompanySummary(
        workspaceName: 'Workspace',
        isActive: null,
        planCode: null,
        billingStatus: null,
        teamSize: 0,
        activeMembers: 0,
        departmentsCount: 0,
      );
    }
    if (profileId.isEmpty ||
        workspace == null ||
        !_isActiveBusiness(workspace)) {
      return const OwnerCompanySummary(
        workspaceName: 'Workspace',
        isActive: null,
        planCode: null,
        billingStatus: null,
        teamSize: 0,
        activeMembers: 0,
        departmentsCount: 0,
      );
    }
    final stopwatch = Stopwatch()..start();
    debugPrint(
      '[SCOPED_DATA_REQUEST] feature=reports operation=company_summary method=GET endpoint_or_collection=/items/business_profiles/$profileId membership_id=${workspace.membershipId} business_profile=$profileId department=${workspace.departmentId?.trim() ?? ''} membership_role=${workspace.memberRole} context_source=${OrganizationService.instance.activeWorkspaceContextSource} workspace_revision=$startRevision filter_summary=fields=id,company_name,is_active,plan_code,billing_status started=true trace=$trace',
    );
    final profileRes = await _client.get(
      '/items/business_profiles/$profileId',
      queryParameters: {
        'fields': 'id,company_name,is_active,plan_code,billing_status',
      },
    );
    final profile =
        (profileRes.data['data'] as Map?)?.cast<String, dynamic>() ??
        <String, dynamic>{};
    final members = await fetchWorkforce();
    final departments = await fetchDepartments();
    stopwatch.stop();
    debugPrint(
      '[SCOPED_DATA_RESPONSE] feature=reports operation=company_summary http_status=${profileRes.statusCode ?? 0} result_count=1 duration_ms=${stopwatch.elapsedMilliseconds} membership_id=${workspace.membershipId} business_profile=$profileId workspace_revision_before=$startRevision workspace_revision_after=${OrganizationService.instance.workspaceRevision} context_unchanged=${OrganizationService.instance.workspaceRevision == startRevision && OrganizationService.instance.workspaceSignature == startSignature} returned_business_profile_ids=[$profileId] returned_membership_ids=[${workspace.membershipId}] empty_result=false trace=$trace',
    );

    return OwnerCompanySummary(
      workspaceName:
          profile['company_name']?.toString().trim().isNotEmpty == true
          ? profile['company_name'].toString()
          : 'Workspace',
      isActive: profile['is_active'] as bool?,
      planCode: profile['plan_code']?.toString(),
      billingStatus: profile['billing_status']?.toString(),
      teamSize: members.length,
      activeMembers: members.where((member) => member.isActive).length,
      departmentsCount: departments.length,
    );
  }

  Future<OwnerSnapshot> fetchSnapshot({
    bool forceRefresh = false,
    ScanResult? latestHistoryResult,
  }) async {
    final startRevision = OrganizationService.instance.workspaceRevision;
    final startSignature = OrganizationService.instance.workspaceSignature;
    final totalStopwatch = Stopwatch()..start();
    final workspace = await _activeWorkspace(forceRefresh: forceRefresh);
    final profileId = workspace?.businessProfileId.trim() ?? '';
    final activeRole = _workspaceRole(workspace);
    final trace = OrganizationService.instance.activeSwitchTrace ?? 'none';
    if (activeRole.isNotEmpty && activeRole != 'owner') {
      debugPrint(
        '[ROLE_SERVICE_GUARD] service=OwnerOpsService expected=owner actual=${activeRole.isEmpty ? "unknown" : activeRole} ignored=true',
      );
      debugPrint(
        '[STALE_ROLE_RESULT_IGNORED] service=OwnerOpsService expected_role=owner actual_role=${activeRole.isEmpty ? "unknown" : activeRole}',
      );
      return const OwnerSnapshot(
        activeMembers: 0,
        departmentsCount: 0,
        scanRequestsToday: 0,
        checksCompletedToday: 0,
        missingChecks: 0,
        pendingScans: 0,
        attentionOutcomes: 0,
        openAlerts: 0,
        pendingRequests: 0,
        complianceRate: '0%',
        readinessDistribution: {
          'Stable': 0,
          'Low Focus': 0,
          'Elevated Fatigue': 0,
          'High Risk': 0,
        },
      );
    }
    debugPrint(
      '[SCOPED_DATA_REQUEST] feature=reports operation=owner_snapshot method=GET endpoint_or_collection=/items/scan_results membership_id=${workspace?.membershipId ?? ''} business_profile=$profileId department=${workspace?.departmentId?.trim() ?? ''} membership_role=${workspace?.memberRole ?? ''} context_source=${OrganizationService.instance.activeWorkspaceContextSource} workspace_revision=$startRevision filter_summary=business_profile=$profileId;scan_results;alerts;scan_requests;departments started=true trace=$trace',
    );
    final workforceStopwatch = Stopwatch()..start();
    final team = await fetchWorkforce(forceRefresh: forceRefresh);
    _logOwnerHomeLoadSection('workforce', workforceStopwatch);
    if (_isWorkspaceStale(startRevision, startSignature)) {
      _logStaleResult();
      return const OwnerSnapshot(
        activeMembers: 0,
        departmentsCount: 0,
        scanRequestsToday: 0,
        checksCompletedToday: 0,
        missingChecks: 0,
        pendingScans: 0,
        attentionOutcomes: 0,
        openAlerts: 0,
        pendingRequests: 0,
        complianceRate: '0%',
        readinessDistribution: {
          'Stable': 0,
          'Low Focus': 0,
          'Elevated Fatigue': 0,
          'High Risk': 0,
        },
      );
    }
    final activeMembers = team.where((member) => member.isActive).length;
    final checksToday = team.where((member) => !member.missingCheck).length;
    final missing = team.where((member) => member.missingCheck).length;
    final attention = team.where((member) => member.needsAttention).length;
    final compliance = activeMembers == 0
        ? '0%'
        : '${((checksToday / activeMembers) * 100).toStringAsFixed(0)}%';
    debugPrint('[OWNER_HOME_CONTEXT] business_profile=$profileId');
    debugPrint(
      '[OWNER_HOME_CONTEXT] membership_id=${workspace?.membershipId.trim() ?? ''}',
    );
    debugPrint(
      '[OWNER_HOME_CONTEXT] member_role=${workspace?.finalEffectiveRole ?? workspace?.memberRole ?? ''}',
    );
    if (_isWorkspaceStale(startRevision, startSignature)) {
      _logStaleResult();
      return const OwnerSnapshot(
        activeMembers: 0,
        departmentsCount: 0,
        scanRequestsToday: 0,
        checksCompletedToday: 0,
        missingChecks: 0,
        pendingScans: 0,
        attentionOutcomes: 0,
        openAlerts: 0,
        pendingRequests: 0,
        complianceRate: '0%',
        readinessDistribution: {
          'Stable': 0,
          'Low Focus': 0,
          'Elevated Fatigue': 0,
          'High Risk': 0,
        },
      );
    }
    final sectionResults = await Future.wait<dynamic>([
      _timedOwnerHomeSection(
        'readiness_distribution',
        () => _fetchOwnerReadinessDistribution(
          userId: Session.instance.userId?.trim() ?? '',
          profileId: profileId,
          latestHistoryResult: latestHistoryResult,
        ),
      ),
      _timedOwnerHomeSection('alerts', () async {
        try {
          final alerts = await AlertService.instance.fetchAlerts(limit: 200);
          return alerts.where((item) => item.isOpen).length;
        } catch (_) {
          return 0;
        }
      }),
      _timedOwnerHomeSection(
        'request_counts',
        () => _fetchRequestRowsForProfile(profileId, limit: 300),
      ),
      _timedOwnerHomeSection(
        'departments',
        () => fetchDepartments(forceRefresh: forceRefresh),
      ),
    ]);
    final readinessDistribution = sectionResults[0] as Map<String, int>;
    final openAlerts = sectionResults[1] as int;
    final requestRows = (sectionResults[2] as List<Map<String, dynamic>>);
    final departments = (sectionResults[3] as List<WorkspaceDepartment>);
    if (_isWorkspaceStale(startRevision, startSignature)) {
      _logStaleResult();
      return const OwnerSnapshot(
        activeMembers: 0,
        departmentsCount: 0,
        scanRequestsToday: 0,
        checksCompletedToday: 0,
        missingChecks: 0,
        pendingScans: 0,
        attentionOutcomes: 0,
        openAlerts: 0,
        pendingRequests: 0,
        complianceRate: '0%',
        readinessDistribution: {
          'Stable': 0,
          'Low Focus': 0,
          'Elevated Fatigue': 0,
          'High Risk': 0,
        },
      );
    }
    final requestCounts = _countRequests(requestRows);
    int scanRequestsToday = 0;
    final now = DateTime.now();
    scanRequestsToday = requestRows.where((row) {
      final requestedAt = _parseDate(row['requested_at']);
      if (requestedAt == null) return false;
      final local = requestedAt.toLocal();
      return local.year == now.year &&
          local.month == now.month &&
          local.day == now.day;
    }).length;

    final departmentsCount = departments.length;
    debugPrint(
      '[OWNER_HOME_LOAD] total_duration_ms=${totalStopwatch.elapsedMilliseconds}',
    );
    debugPrint(
      '[SCOPED_DATA_RESPONSE] feature=reports operation=owner_snapshot http_status=200 result_count=${readinessDistribution.values.fold<int>(0, (a, b) => a + b)} duration_ms=${totalStopwatch.elapsedMilliseconds} membership_id=${workspace?.membershipId ?? ''} business_profile=$profileId workspace_revision_before=$startRevision workspace_revision_after=${OrganizationService.instance.workspaceRevision} context_unchanged=${OrganizationService.instance.workspaceRevision == startRevision && OrganizationService.instance.workspaceSignature == startSignature} returned_business_profile_ids=[$profileId] returned_membership_ids=[${workspace?.membershipId ?? ''}] empty_result=${readinessDistribution.values.every((value) => value == 0)} trace=$trace',
    );

    return OwnerSnapshot(
      activeMembers: activeMembers,
      departmentsCount: departmentsCount,
      scanRequestsToday: scanRequestsToday,
      checksCompletedToday: checksToday,
      missingChecks: missing,
      pendingScans: missing,
      attentionOutcomes: attention,
      openAlerts: openAlerts,
      pendingRequests: requestCounts.pending,
      complianceRate: compliance,
      readinessDistribution: readinessDistribution,
    );
  }

  Future<Map<String, int>> _fetchOwnerReadinessDistribution({
    required String userId,
    required String profileId,
    ScanResult? latestHistoryResult,
  }) async {
    const labels = <String, int>{
      'Stable': 0,
      'Low Focus': 0,
      'Elevated Fatigue': 0,
      'High Risk': 0,
    };
    final normalized = Map<String, int>.from(labels);
    if (userId.trim().isEmpty || profileId.trim().isEmpty) {
      debugPrint(
        '[OWNER_READINESS_DISTRIBUTION_SCOPE] scope=self scoped_profile=${profileId.trim().isNotEmpty} has_user=${userId.trim().isNotEmpty}',
      );
      debugPrint(
        '[OWNER_READINESS_DISTRIBUTION] has_current_user=${userId.trim().isNotEmpty} scoped_profile=${profileId.trim().isNotEmpty} query=skipped',
      );
      debugPrint('[OWNER_READINESS_DISTRIBUTION] scan_results_raw_count=0');
      debugPrint('[OWNER_READINESS_DISTRIBUTION] failed_scans_raw_count=0');
      debugPrint(
        '[OWNER_READINESS_DISTRIBUTION] normalized_counts=$normalized',
      );
      return normalized;
    }

    // Owner Home shows company-scoped completed scan_results.
    debugPrint(
      '[OWNER_READINESS_DISTRIBUTION_SCOPE] scope=self scoped_profile=true has_user=true',
    );
    var resultQueryFailed = false;
    final resultQuery = {
      'filter[scan_id][business_profile][_eq]': profileId,
      'sort': '-date_created',
      'limit': 500,
      'fields': 'id,scan_id,risk_level,readiness_score,date_created',
    };
    debugPrint(
      '[OWNER_READINESS_DISTRIBUTION_SOURCE] endpoint=/items/scan_results query_keys=${resultQuery.keys.toList()}',
    );
    debugPrint(
      '[OWNER_READINESS_DISTRIBUTION] query_keys=${resultQuery.keys.toList()}',
    );
    final resultRows = <Map<String, dynamic>>[];
    try {
      final response = await _client.get(
        '/items/scan_results',
        queryParameters: resultQuery,
      );
      final data = response.data['data'];
      final rows = data is List
          ? data.whereType<Map<String, dynamic>>().toList()
          : <Map<String, dynamic>>[];
      debugPrint('[OWNER_READINESS_DISTRIBUTION] raw_count=${rows.length}');
      resultRows.addAll(rows);
    } on DioException catch (e) {
      resultQueryFailed = true;
      final status = e.response?.statusCode ?? 0;
      debugPrint(
        '[OWNER_READINESS_DISTRIBUTION] direct_result_query_status=$status error_type=${e.type}',
      );
      if (status != 400 && status != 403 && status != 422) {
        debugPrint(
          '[OWNER_READINESS_DISTRIBUTION] normalized_counts=$normalized',
        );
      }
    } catch (e) {
      resultQueryFailed = true;
      debugPrint(
        '[OWNER_READINESS_DISTRIBUTION] result_query_error_type=${e.runtimeType}',
      );
    }

    if (resultRows.isNotEmpty) {
      final latestScanId = _latestScanIdFromResultRows(resultRows);
      debugPrint(
        '[OWNER_READINESS_DISTRIBUTION] has_latest_scan_id=${latestScanId.isNotEmpty}',
      );
      debugPrint(
        '[OWNER_READINESS_DISTRIBUTION_SOURCE] endpoint=/items/scan_results query_keys=${resultQuery.keys.toList()} raw_count=${resultRows.length} has_latest_scan_id=${latestScanId.isNotEmpty}',
      );
      final countedScanIds = <String>{};
      for (final row in resultRows) {
        final scanId = _relationId(row['scan_id']);
        final label = _normalizeOwnerReadinessLabel(row);
        if (label == null) continue;
        if (scanId.isNotEmpty) countedScanIds.add(scanId);
        normalized[label] = (normalized[label] ?? 0) + 1;
      }
      _mergeLatestHistoryResultIntoDistribution(
        latestHistoryResult: latestHistoryResult,
        normalized: normalized,
        countedScanIds: countedScanIds,
      );
      debugPrint(
        '[OWNER_READINESS_DISTRIBUTION] normalized_counts=$normalized',
      );
      return normalized;
    }

    final scansQuery = {
      'filter[business_profile][_eq]': profileId,
      'sort': '-date_created',
      'limit': 500,
      'fields': 'id,status,failure_reason',
    };
    debugPrint(
      '[OWNER_READINESS_DISTRIBUTION] query_keys=${scansQuery.keys.toList()}',
    );
    debugPrint(
      '[OWNER_READINESS_DISTRIBUTION] has_current_user=true scoped_profile=true',
    );

    List<Map<String, dynamic>> scanRows = const [];
    try {
      final response = await _client.get(
        '/items/wellness_scans',
        queryParameters: scansQuery,
      );
      final data = response.data['data'];
      scanRows = data is List
          ? data.whereType<Map<String, dynamic>>().toList()
          : const [];
    } catch (e) {
      debugPrint(
        '[OWNER_READINESS_DISTRIBUTION] raw_count=0 error_type=${e.runtimeType}',
      );
      debugPrint(
        '[OWNER_READINESS_DISTRIBUTION] normalized_counts=$normalized',
      );
      return normalized;
    }

    debugPrint(
      '[OWNER_READINESS_DISTRIBUTION] failed_scans_raw_count=${_countFailedScans(scanRows)}',
    );
    if (scanRows.isEmpty) {
      debugPrint('[OWNER_READINESS_DISTRIBUTION] scan_results_raw_count=0');
      debugPrint(
        '[OWNER_READINESS_DISTRIBUTION] normalized_counts=$normalized',
      );
      return normalized;
    }

    final scanIds = scanRows
        .map((row) => row['id']?.toString() ?? '')
        .where((id) => id.isNotEmpty)
        .toList();
    if (scanIds.isEmpty) {
      debugPrint('[OWNER_READINESS_DISTRIBUTION] scan_results_raw_count=0');
      debugPrint(
        '[OWNER_READINESS_DISTRIBUTION] normalized_counts=$normalized',
      );
      return normalized;
    }

    final fallbackResultRows = <Map<String, dynamic>>[];
    try {
      final fallbackResultQuery = {
        'filter[scan_id][_in]': scanIds.join(','),
        'sort': '-date_created',
        'limit': 500,
        'fields': 'id,scan_id,risk_level,readiness_score,date_created',
      };
      debugPrint(
        '[OWNER_READINESS_DISTRIBUTION] query_keys=${fallbackResultQuery.keys.toList()} scan_count=${scanIds.length}',
      );
      final response = await _client.get(
        '/items/scan_results',
        queryParameters: fallbackResultQuery,
      );
      final data = response.data['data'];
      fallbackResultRows.addAll(
        data is List
            ? data.whereType<Map<String, dynamic>>().toList()
            : const [],
      );
    } catch (e) {
      debugPrint(
        '[OWNER_READINESS_DISTRIBUTION] result_query_error_type=${e.runtimeType}',
      );
      debugPrint('[OWNER_READINESS_DISTRIBUTION] scan_results_raw_count=0');
      debugPrint(
        '[OWNER_READINESS_DISTRIBUTION] normalized_counts=$normalized',
      );
      return normalized;
    }

    debugPrint(
      '[OWNER_READINESS_DISTRIBUTION] scan_results_raw_count=${fallbackResultRows.length}',
    );
    debugPrint(
      '[OWNER_READINESS_DISTRIBUTION] raw_count=${fallbackResultRows.length}',
    );

    final resultByScanId = <String, Map<String, dynamic>>{};
    for (final row in fallbackResultRows) {
      final scanId = row['scan_id']?.toString().trim() ?? '';
      if (scanId.isEmpty || resultByScanId.containsKey(scanId)) continue;
      resultByScanId[scanId] = row;
    }

    for (final row in resultByScanId.values) {
      final label = _normalizeOwnerReadinessLabel(row);
      if (label == null) continue;
      normalized[label] = (normalized[label] ?? 0) + 1;
    }

    debugPrint('[OWNER_READINESS_DISTRIBUTION] normalized_counts=$normalized');
    if (resultQueryFailed) {
      debugPrint(
        '[OWNER_READINESS_DISTRIBUTION] direct_result_query_failed_visible=true',
      );
    }
    return normalized;
  }

  void _mergeLatestHistoryResultIntoDistribution({
    required ScanResult? latestHistoryResult,
    required Map<String, int> normalized,
    required Set<String> countedScanIds,
  }) {
    final scanId = latestHistoryResult?.scanId.trim() ?? '';
    if (scanId.isEmpty) {
      debugPrint(
        '[OWNER_READINESS_DISTRIBUTION_COMPARE] has_latest_history_scan_id=false included_in_distribution=false reason=no_latest_history_result',
      );
      return;
    }
    if (countedScanIds.contains(scanId)) {
      debugPrint(
        '[OWNER_READINESS_DISTRIBUTION_COMPARE] has_latest_history_scan_id=true included_in_distribution=true reason=backend_query',
      );
      return;
    }
    final label = _normalizeReadinessKey(
      latestHistoryResult?.riskLevel ?? latestHistoryResult?.overallState,
    );
    if (label == null) {
      debugPrint(
        '[OWNER_READINESS_DISTRIBUTION_COMPARE] has_latest_history_scan_id=true included_in_distribution=false reason=missing_valid_risk_level',
      );
      return;
    }
    normalized[label] = (normalized[label] ?? 0) + 1;
    countedScanIds.add(scanId);
    debugPrint(
      '[OWNER_READINESS_DISTRIBUTION_COMPARE] has_latest_history_scan_id=true included_in_distribution=true reason=latest_history_merge',
    );
  }

  String? _normalizeOwnerReadinessLabel(Map<String, dynamic> row) {
    return _normalizeReadinessKey(_readinessRawLabel(row));
  }

  String? _readinessRawLabel(Map<String, dynamic> row) {
    final value = row['risk_level']?.toString().trim() ?? '';
    if (value.isEmpty) return null;
    return value;
  }

  String? _normalizeReadinessKey(String? rawValue) {
    final raw = rawValue?.trim() ?? '';
    if (raw.isEmpty) return null;
    final lowered = raw.toLowerCase();
    if (lowered == 'stable') return 'Stable';
    if (lowered == 'low_focus' ||
        lowered == 'low focus' ||
        lowered == 'low-focus') {
      return 'Low Focus';
    }
    if (lowered == 'elevated_fatigue' ||
        lowered == 'elevated fatigue' ||
        lowered == 'elevated-fatigue') {
      return 'Elevated Fatigue';
    }
    if (lowered == 'high_risk' ||
        lowered == 'high risk' ||
        lowered == 'high-risk' ||
        lowered == 'high' ||
        lowered == 'critical') {
      return 'High Risk';
    }
    return null;
  }

  bool _isFailedOwnerScan(Map<String, dynamic> row) {
    final status = row['status']?.toString().trim().toLowerCase() ?? '';
    final failureReason = row['failure_reason']?.toString().trim() ?? '';
    if (failureReason.isNotEmpty) return true;
    return status == 'failed' ||
        status == 'error' ||
        status == 'rejected' ||
        status == 'cancelled';
  }

  bool _isCompletedScanRow(Map<String, dynamic> row) {
    final status = row['status']?.toString().trim().toLowerCase() ?? '';
    if (status == 'completed') return true;
    if (status == 'complete' || status == 'done') return true;
    return row['completed_at'] != null;
  }

  int _countFailedScans(List<Map<String, dynamic>> scanRows) {
    return scanRows.where(_isFailedOwnerScan).length;
  }

  Future<OwnerReportSummary> fetchReportsSummary() async {
    final startRevision = OrganizationService.instance.workspaceRevision;
    final startSignature = OrganizationService.instance.workspaceSignature;
    final team = await fetchWorkforce();
    if (_isWorkspaceStale(startRevision, startSignature)) {
      _logStaleResult();
      return const OwnerReportSummary(
        todayCompleted: 0,
        last7DaysCompleted: 0,
        completionRate: '0%',
        missingChecks: 0,
        attentionOutcomes: 0,
        openAlerts: 0,
        readinessDistribution: {
          'Stable': 0,
          'Low Focus': 0,
          'Elevated Fatigue': 0,
          'High Risk': 0,
        },
      );
    }
    final now = DateTime.now();
    final sevenDaysAgo = now.subtract(const Duration(days: 7));

    final todayCompleted = team.where((member) => !member.missingCheck).length;
    int last7 = 0;
    final distribution = <String, int>{
      'Stable': 0,
      'Low Focus': 0,
      'Elevated Fatigue': 0,
      'High Risk': 0,
    };
    for (final member in team) {
      if (member.lastCheckAt != null &&
          member.lastCheckAt!.isAfter(sevenDaysAgo)) {
        last7 += 1;
      }
      final label = member.latestReadiness;
      if (label != null && distribution.containsKey(label)) {
        distribution[label] = (distribution[label] ?? 0) + 1;
      }
    }
    int openAlerts = 0;
    try {
      final alerts = await AlertService.instance.fetchAlerts(limit: 200);
      openAlerts = alerts.where((item) => item.isOpen).length;
    } catch (_) {}
    final activeMembers = team.where((member) => member.isActive).length;
    final missing = team.where((member) => member.missingCheck).length;
    final attention = team.where((member) => member.needsAttention).length;
    final completionRate = activeMembers == 0
        ? '0%'
        : '${((todayCompleted / activeMembers) * 100).toStringAsFixed(0)}%';

    return OwnerReportSummary(
      todayCompleted: todayCompleted,
      last7DaysCompleted: last7,
      completionRate: completionRate,
      missingChecks: missing,
      attentionOutcomes: attention,
      openAlerts: openAlerts,
      readinessDistribution: distribution,
    );
  }

  Future<int> fetchOverdueRequestsCount() async {
    final startRevision = OrganizationService.instance.workspaceRevision;
    final startSignature = OrganizationService.instance.workspaceSignature;
    final workspace = await _activeWorkspace();
    final profileId = workspace?.businessProfileId.trim() ?? '';
    if (_isWorkspaceStale(startRevision, startSignature)) {
      _logStaleResult();
      return 0;
    }
    if (profileId.isEmpty) return 0;
    try {
      final rows = await _fetchRequestRowsForProfile(profileId, limit: 300);
      final counts = _countRequests(rows, complianceLog: true);
      return counts.overdue;
    } catch (_) {
      return 0;
    }
  }

  Future<Map<String, int>> fetchWorkspaceReadinessDistribution({
    String? departmentId,
  }) async {
    final summary = await fetchWorkspaceReadinessSummary(
      departmentId: departmentId,
    );
    return summary.distribution;
  }

  Future<WorkspaceReadinessSummary> fetchWorkspaceReadinessSummary({
    String? departmentId,
    DateTime? start,
    DateTime? end,
  }) async {
    final startRevision = OrganizationService.instance.workspaceRevision;
    final startSignature = OrganizationService.instance.workspaceSignature;
    final workspace = await _activeWorkspace();
    final profileId = workspace?.businessProfileId.trim() ?? '';
    if (_isWorkspaceStale(startRevision, startSignature)) {
      _logStaleResult();
      return WorkspaceReadinessSummary(
        distribution: const {
          'Stable': 0,
          'Low Focus': 0,
          'Elevated Fatigue': 0,
          'High Risk': 0,
        },
        resultsByScanId: const <String, OwnerAssessmentResult>{},
        queryFailed: false,
      );
    }
    final normalized = <String, int>{
      'Stable': 0,
      'Low Focus': 0,
      'Elevated Fatigue': 0,
      'High Risk': 0,
    };
    final department = departmentId?.trim() ?? '';
    debugPrint(
      '[COMPLIANCE_READINESS_DISTRIBUTION_SCOPE] scope=${department.isEmpty ? "workspace" : "department"} scoped_profile=${profileId.isNotEmpty} scoped_department=${department.isNotEmpty}',
    );
    if (profileId.isEmpty) {
      debugPrint('[COMPLIANCE_READINESS_DISTRIBUTION] query=skipped');
      debugPrint('[COMPLIANCE_READINESS_DISTRIBUTION] raw_count=0');
      debugPrint(
        '[COMPLIANCE_READINESS_DISTRIBUTION] normalized_counts=$normalized',
      );
      return WorkspaceReadinessSummary(
        distribution: normalized,
        resultsByScanId: const <String, OwnerAssessmentResult>{},
        queryFailed: false,
      );
    }

    final resultQuery = {
      'filter[scan_id][business_profile][_eq]': profileId,
      'sort': '-date_created',
      'limit': 800,
      'fields': 'id,scan_id,risk_level,readiness_score,date_created',
    };
    debugPrint(
      '[COMPLIANCE_READINESS_DISTRIBUTION] query_keys=${resultQuery.keys.toList()}',
    );
    try {
      final response = await _client.get(
        '/items/scan_results',
        queryParameters: resultQuery,
      );
      final data = response.data['data'];
      final rows = data is List
          ? data.whereType<Map<String, dynamic>>().toList()
          : <Map<String, dynamic>>[];
      debugPrint(
        '[COMPLIANCE_READINESS_DISTRIBUTION] raw_count=${rows.length}',
      );
      final filteredRows = rows.where((row) {
        final createdAt = _parseDate(row['date_created']);
        if (createdAt == null) return false;
        final local = createdAt.toLocal();
        if (start != null && local.isBefore(start)) return false;
        if (end != null && !local.isBefore(end)) return false;
        return true;
      }).toList();
      final visibilityRole = _workspaceRole(workspace);
      final isHrVisibility = visibilityRole == 'hr';
      final hrMemberByUserId = <String, HrMemberView>{};
      final hrMemberByMembershipId = <String, HrMemberView>{};
      final scanUserByScanId = <String, String>{};
      final requestMemberByScanId = <String, String>{};
      final requestUserByScanId = <String, String>{};
      if (isHrVisibility) {
        try {
          final directory = await HrOpsService.instance
              .fetchWorkforceDirectory();
          for (final member in directory.members) {
            final userKey = member.userId.trim().toLowerCase();
            if (userKey.isNotEmpty) {
              hrMemberByUserId[userKey] = member;
            }
            final membershipKey = member.memberId.trim();
            if (membershipKey.isNotEmpty) {
              hrMemberByMembershipId[membershipKey] = member;
            }
          }
        } catch (_) {
          debugPrint(
            '[COMPLIANCE_READINESS_DISTRIBUTION] hr_directory_query_failed=true',
          );
        }
        try {
          final requests = await RequestService.instance.fetchHrRequests();
          for (final request in requests) {
            final scanId = request.scanId?.trim() ?? '';
            if (scanId.isEmpty) continue;
            final requestedMemberId = request.requestedForId?.trim() ?? '';
            final requestedUserId = request.requestedForUserId?.trim() ?? '';
            if (requestedMemberId.isNotEmpty) {
              requestMemberByScanId.putIfAbsent(
                scanId,
                () => requestedMemberId,
              );
            }
            if (requestedUserId.isNotEmpty) {
              requestUserByScanId.putIfAbsent(scanId, () => requestedUserId);
            }
          }
        } catch (_) {
          debugPrint(
            '[COMPLIANCE_READINESS_DISTRIBUTION] hr_request_query_failed=true',
          );
        }
        try {
          final scanIds = filteredRows
              .map((row) => _relationId(row['scan_id']))
              .where((id) => id.isNotEmpty)
              .toSet()
              .toList();
          if (scanIds.isNotEmpty) {
            final scansResponse = await _client.get(
              '/items/wellness_scans',
              queryParameters: {
                'limit': scanIds.length,
                'filter[business_profile][_eq]': profileId,
                'filter[id][_in]': scanIds.join(','),
                'fields': 'id,user',
              },
            );
            final scansData = scansResponse.data['data'];
            final scanRows = scansData is List
                ? scansData.whereType<Map<String, dynamic>>().toList()
                : const <Map<String, dynamic>>[];
            for (final row in scanRows) {
              final scanId = row['id']?.toString().trim() ?? '';
              if (scanId.isEmpty) continue;
              final userId = _relationId(row['user']);
              if (userId.isNotEmpty) {
                scanUserByScanId[scanId] = userId;
              }
            }
          }
        } catch (_) {
          debugPrint(
            '[COMPLIANCE_READINESS_DISTRIBUTION] hr_scan_membership_query_failed=true',
          );
        }
      }
      final resultsByScanId = <String, OwnerAssessmentResult>{};
      for (final row in filteredRows) {
        final scanId = _relationId(row['scan_id']);
        if (scanId.isEmpty || resultsByScanId.containsKey(scanId)) continue;
        final label = _normalizeReadinessDisplayLabel(_readinessRawLabel(row));
        if (label == null) continue;
        if (isHrVisibility) {
          final resolvedMember = _resolveHrReadinessMember(
            byUserId: hrMemberByUserId,
            byMembershipId: hrMemberByMembershipId,
            scanUserId: scanUserByScanId[scanId],
            requestMembershipId: requestMemberByScanId[scanId],
            requestUserId: requestUserByScanId[scanId],
          );
          if (resolvedMember == null ||
              resolvedMember.roleKey.toLowerCase() == 'owner') {
            continue;
          }
        }
        normalized[label] = (normalized[label] ?? 0) + 1;
        resultsByScanId[scanId] = OwnerAssessmentResult(
          scanId: scanId,
          outcome: label,
          readinessScore: _stringOrNull(row['readiness_score']),
          completedAt: _parseDate(row['date_created']),
        );
      }
      debugPrint(
        '[COMPLIANCE_READINESS_DISTRIBUTION] filtered_count=${resultsByScanId.length}',
      );
      debugPrint(
        '[COMPLIANCE_READINESS_DISTRIBUTION] normalized_counts=$normalized',
      );
      return WorkspaceReadinessSummary(
        distribution: normalized,
        resultsByScanId: resultsByScanId,
        queryFailed: false,
      );
    } on DioException catch (e) {
      debugPrint(
        '[COMPLIANCE_READINESS_DISTRIBUTION] raw_count=0 error_status=${e.response?.statusCode} reason=query failed',
      );
      debugPrint(
        '[COMPLIANCE_READINESS_DISTRIBUTION] normalized_counts=hidden_due_to_query_failure',
      );
      return WorkspaceReadinessSummary(
        distribution: normalized,
        resultsByScanId: const <String, OwnerAssessmentResult>{},
        queryFailed: true,
      );
    } catch (e) {
      debugPrint(
        '[COMPLIANCE_READINESS_DISTRIBUTION] raw_count=0 reason=query failed error_type=${e.runtimeType}',
      );
      debugPrint(
        '[COMPLIANCE_READINESS_DISTRIBUTION] normalized_counts=hidden_due_to_query_failure',
      );
      return WorkspaceReadinessSummary(
        distribution: normalized,
        resultsByScanId: const <String, OwnerAssessmentResult>{},
        queryFailed: true,
      );
    }
  }

  Future<OwnerAssessmentLookupResult> fetchAssessmentResultsByScanIds({
    required List<String> scanIds,
    bool forceRefresh = false,
  }) async {
    final startRevision = OrganizationService.instance.workspaceRevision;
    final startSignature = OrganizationService.instance.workspaceSignature;
    final workspace = await _activeWorkspace(forceRefresh: forceRefresh);
    final profileId = workspace?.businessProfileId.trim() ?? '';
    if (_isWorkspaceStale(startRevision, startSignature)) {
      _logStaleResult();
      return const OwnerAssessmentLookupResult(
        resultsByScanId: <String, OwnerAssessmentResult>{},
        queryFailed: false,
      );
    }
    if (workspace == null ||
        profileId.isEmpty ||
        !_isActiveBusiness(workspace) ||
        scanIds.isEmpty) {
      return const OwnerAssessmentLookupResult(
        resultsByScanId: <String, OwnerAssessmentResult>{},
        queryFailed: false,
      );
    }

    final normalizedScanIds = scanIds
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty)
        .toSet()
        .toList();
    if (normalizedScanIds.isEmpty) {
      return const OwnerAssessmentLookupResult(
        resultsByScanId: <String, OwnerAssessmentResult>{},
        queryFailed: false,
      );
    }

    try {
      final rows = await _loadOwnerAssessmentRows(
        profileId: profileId,
        scanIds: normalizedScanIds,
      );
      final resultsByScanId = <String, OwnerAssessmentResult>{};
      for (final row in rows) {
        final scanId = _relationId(row['scan_id']);
        if (scanId.isEmpty || resultsByScanId.containsKey(scanId)) continue;
        final label = _normalizeReadinessDisplayLabel(_readinessRawLabel(row));
        if (label == null) continue;
        resultsByScanId[scanId] = OwnerAssessmentResult(
          scanId: scanId,
          outcome: label,
          readinessScore: _stringOrNull(row['readiness_score']),
          completedAt: _parseDate(row['date_created']),
        );
      }
      return OwnerAssessmentLookupResult(
        resultsByScanId: resultsByScanId,
        queryFailed: false,
      );
    } catch (e) {
      debugPrint(
        '[OWNER_REQUEST_RESULTS] query_failed error_type=${e.runtimeType}',
      );
      return const OwnerAssessmentLookupResult(
        resultsByScanId: <String, OwnerAssessmentResult>{},
        queryFailed: true,
      );
    }
  }

  String? _stringOrNull(dynamic raw) {
    final value = raw?.toString().trim() ?? '';
    if (value.isEmpty || value.toLowerCase() == 'null') return null;
    return value;
  }

  String? _normalizeReadinessDisplayLabel(dynamic rawValue) {
    return _normalizeReadinessKey(rawValue?.toString());
  }

  Map<String, dynamic> _ownerAssessmentQuery({
    required String profileId,
    required List<String> scanIds,
    String? departmentId,
  }) {
    return {
      'filter[scan_id][business_profile][_eq]': profileId,
      if (departmentId != null && departmentId.trim().isNotEmpty)
        'filter[scan_id][department][_eq]': departmentId.trim(),
      if (scanIds.isNotEmpty) 'filter[scan_id][_in]': scanIds.join(','),
      'sort': '-date_created',
      'limit': 800,
      'fields': 'id,scan_id,risk_level,readiness_score,date_created',
    };
  }

  HrMemberView? _resolveHrReadinessMember({
    required Map<String, HrMemberView> byUserId,
    required Map<String, HrMemberView> byMembershipId,
    String? scanUserId,
    String? requestMembershipId,
    String? requestUserId,
  }) {
    final scanUserKey = (scanUserId ?? '').trim().toLowerCase();
    if (scanUserKey.isNotEmpty) {
      final member = byUserId[scanUserKey];
      if (member != null) return member;
    }

    final requestMembershipKey = (requestMembershipId ?? '').trim();
    if (requestMembershipKey.isNotEmpty) {
      final member = byMembershipId[requestMembershipKey];
      if (member != null) return member;
    }

    final requestUserKey = (requestUserId ?? '').trim().toLowerCase();
    if (requestUserKey.isNotEmpty) {
      final member = byUserId[requestUserKey];
      if (member != null) return member;
    }

    return null;
  }

  Future<List<Map<String, dynamic>>> _loadOwnerAssessmentRows({
    required String profileId,
    required List<String> scanIds,
    String? departmentId,
  }) async {
    final query = _ownerAssessmentQuery(
      profileId: profileId,
      scanIds: scanIds,
      departmentId: departmentId,
    );
    debugPrint(
      '[OWNER_REQUEST_RESULTS] endpoint=/items/scan_results query_keys=${query.keys.toList()}',
    );
    final response = await _client.get(
      '/items/scan_results',
      queryParameters: query,
    );
    final data = response.data['data'];
    return data is List
        ? data.whereType<Map<String, dynamic>>().toList()
        : <Map<String, dynamic>>[];
  }

  Future<List<Map<String, dynamic>>> _fetchRequestRows(String profileId) async {
    return _fetchRequestRowsForProfile(profileId, limit: 400);
  }

  Future<List<Map<String, dynamic>>> _fetchRequestRowsForProfile(
    String profileId, {
    required int limit,
  }) async {
    if (profileId.trim().isEmpty) return const [];
    try {
      final response = await _client.get(
        '/items/scan_requests',
        queryParameters: {
          'limit': limit,
          'fields':
              'id,status,requested_at,due_at,completed_scan,business_profile,target_member,target_member.id',
          'filter[business_profile][_eq]': profileId,
        },
      );
      final data = response.data['data'];
      if (data is! List) return const [];
      return data.whereType<Map<String, dynamic>>().toList();
    } catch (_) {
      return const [];
    }
  }

  OwnerRequestCounts _countRequests(
    List<Map<String, dynamic>> rows, {
    bool complianceLog = false,
  }) {
    var pending = 0;
    var completed = 0;
    var overdue = 0;
    for (final row in rows) {
      final normalized = RequestStatusNormalizer.normalizeRaw(
        requestId: row['id']?.toString() ?? '',
        rawStatus: row['status']?.toString(),
        dueAt: _parseDate(row['due_at'] ?? row['due_date'] ?? row['deadline']),
        completedScanId: _relationId(row['completed_scan']),
      );
      if (complianceLog) {
        debugPrint(
          '[COMPLIANCE_REQUEST_STATUS] has_request_id=${(row['id']?.toString().trim() ?? '').isNotEmpty} raw_status=${row['status']?.toString() ?? '-'} normalized_status=${normalized.label}',
        );
      }
      switch (normalized) {
        case NormalizedRequestStatus.pending:
          pending += 1;
          break;
        case NormalizedRequestStatus.completed:
          completed += 1;
          break;
        case NormalizedRequestStatus.overdue:
          overdue += 1;
          break;
        case NormalizedRequestStatus.cancelled:
          break;
      }
    }
    if (complianceLog) {
      debugPrint(
        '[COMPLIANCE_REQUEST_COUNTS] pending=$pending completed=$completed overdue=$overdue',
      );
    } else {
      debugPrint(
        '[OWNER_REQUEST_COUNTS] pending=$pending completed=$completed overdue=$overdue',
      );
    }
    return OwnerRequestCounts(
      pending: pending,
      completed: completed,
      overdue: overdue,
    );
  }

  Future<List<Map<String, dynamic>>> _fetchAlertRows(String profileId) async {
    try {
      final response = await _client.get(
        '/items/alerts',
        queryParameters: {
          'limit': 400,
          'fields': 'id,status,user,date_created',
          'filter[business_profile][_eq]': profileId,
        },
      );
      final data = response.data['data'];
      if (data is! List) return const [];
      return data.whereType<Map<String, dynamic>>().toList();
    } catch (_) {
      return const [];
    }
  }

  Set<String> _extractOverdueMemberIds(List<Map<String, dynamic>> requestRows) {
    final overdue = <String>{};
    for (final row in requestRows) {
      final status = RequestStatusNormalizer.normalizeRaw(
        requestId: row['id']?.toString() ?? '',
        rawStatus: row['status']?.toString(),
        dueAt: _parseDate(row['due_at']),
        completedScanId: _relationId(row['completed_scan']),
      );
      debugPrint(
        '[COMPLIANCE_REQUEST_STATUS] has_request_id=${(row['id']?.toString().trim() ?? '').isNotEmpty} raw_status=${row['status']?.toString() ?? '-'} normalized_status=${status.label}',
      );
      if (status != NormalizedRequestStatus.overdue) {
        continue;
      }
      final memberId = _relationId(row['target_member']);
      if (memberId.isNotEmpty) overdue.add(memberId);
    }
    return overdue;
  }

  Set<String> _extractOpenAlertUserIds(List<Map<String, dynamic>> alertRows) {
    final userIds = <String>{};
    for (final row in alertRows) {
      final status = row['status']?.toString().trim().toLowerCase() ?? '';
      if (status == 'closed' || status == 'resolved') continue;
      final userId = _relationId(row['user']);
      if (userId.isNotEmpty) userIds.add(userId);
    }
    return userIds;
  }

  bool _isSameLocalDay(DateTime? value, DateTime now) {
    if (value == null) return false;
    final local = value.toLocal();
    return local.year == now.year &&
        local.month == now.month &&
        local.day == now.day;
  }

  DateTime? _parseDate(dynamic raw) {
    if (raw == null) return null;
    return DateTime.tryParse(raw.toString());
  }

  void _logOwnerHomeLoadSection(String section, Stopwatch stopwatch) {
    final duration = stopwatch.elapsedMilliseconds;
    debugPrint('[OWNER_HOME_LOAD] section=$section duration_ms=$duration');
    if (duration > 2000) {
      debugPrint(
        '[OWNER_HOME_SLOW_SECTION] section=$section duration_ms=$duration',
      );
    }
  }

  Future<T> _timedOwnerHomeSection<T>(
    String section,
    Future<T> Function() load,
  ) async {
    final stopwatch = Stopwatch()..start();
    try {
      return await load();
    } finally {
      _logOwnerHomeLoadSection(section, stopwatch);
    }
  }

  String _latestScanIdFromResultRows(List<Map<String, dynamic>> rows) {
    if (rows.isEmpty) return '-';
    final raw = rows.first['scan_id'];
    return _relationId(raw).isEmpty ? '-' : _relationId(raw);
  }

  bool _isWorkspaceStale(int startRevision, String startSignature) {
    return OrganizationService.instance.workspaceRevision != startRevision ||
        OrganizationService.instance.workspaceSignature != startSignature;
  }

  void _logStaleResult() {
    debugPrint(
      '[WORKSPACE_GUARD] stale_result_ignored=true service=OwnerOpsService',
    );
  }
}

String _normalizeRoleKey(String rawRole) {
  final value = rawRole.trim().toLowerCase();
  if (value == 'owner') return 'owner';
  if (value == 'admin' || value == 'hr') return 'hr';
  if (value == 'manager' || value == 'manger') return 'manager';
  if (value == 'member' || value == 'employee' || value == 'user') {
    return 'employee';
  }
  return value.isEmpty ? 'employee' : value;
}

String _roleLabel(String roleKey) {
  switch (roleKey) {
    case 'owner':
      return 'Owner';
    case 'hr':
      return 'HR';
    case 'manager':
      return 'Manager';
    case 'employee':
      return 'Employee';
    default:
      if (roleKey.isEmpty) return 'Employee';
      return roleKey[0].toUpperCase() + roleKey.substring(1);
  }
}

String _relationId(dynamic value) {
  if (value == null) return '';
  if (value is Map) {
    return value['id']?.toString().trim() ?? '';
  }
  return value.toString().trim();
}

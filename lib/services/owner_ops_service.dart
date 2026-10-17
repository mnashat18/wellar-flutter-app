import '../utils/safe_debug_log.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../models/scan_result.dart';
import '../models/workspace_department.dart';
import 'alert_service.dart';
import 'directus_client.dart';
import 'member_identity_service.dart';
import 'organization_service.dart';
import 'readiness_result_service.dart';
import 'request_service.dart';
import 'wellar_workforce_service.dart';
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
  final DateTime? joinedAt;
  final String? lastReadinessScore;
  final bool? todaysScan;
  final String? presenceStatus;

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
    this.joinedAt,
    this.lastReadinessScore,
    this.todaysScan,
    this.presenceStatus,
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
  final Map<String, dynamic> summary;

  const OwnerWorkforceDirectoryData({
    required this.members,
    required this.departments,
    this.summary = const {},
  });
}

class OwnerSnapshot {
  final int activeMembers;
  final String? workforceUnavailableMessage;
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
    this.workforceUnavailableMessage,
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
      safeDebugLog(
        '[ROLE_SERVICE_GUARD] service=OwnerOpsService expected=owner actual=${activeRole.isEmpty ? "unknown" : activeRole} ignored=true',
      );
      safeDebugLog(
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
    safeDebugLog(
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
      safeDebugLog(
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
    final result = await WellarWorkforceService.instance
        .fetchWorkforceFromWellar();
    if (result.networkError) {
      return _buildLegacyWorkforceDirectory(profileId, membershipId, role);
    }
    if (!result.isSuccessful) throw result.asFailure();

    final members = result.memberRows.map((row) {
      final departmentId = _workforceString(row['department_id']);
      final departmentName = _workforceString(row['department_name']);
      final risk = _normalizeWorkforceRisk(
        _workforceString(row['last_risk_level']),
      );
      final userId = _workforceString(row['user_id']);
      return OwnerMemberView(
        memberId: _workforceString(row['member_id']).isNotEmpty
            ? _workforceString(row['member_id'])
            : _workforceString(row['id']),
        userId: userId,
        name: _workforceString(row['display_name']),
        email: _workforceString(row['email']),
        role: _workforceString(row['member_role']),
        status: _workforceString(row['status']),
        departmentId: departmentId.isEmpty ? null : departmentId,
        departmentName: departmentName.isEmpty ? null : departmentName,
        latestReadiness: risk,
        lastCheckAt: _parseDate(row['last_scan_at']),
        needsAttention: risk == 'Elevated Fatigue' || risk == 'High Risk',
        missingCheck: _workforceMissing(row),
        hasOpenAlert: false,
        hasOverdueRequest: false,
        requiresLinking: userId.isEmpty,
        joinedAt: _parseDate(row['joined_at']),
        lastReadinessScore:
            _workforceString(row['last_readiness_score']).isEmpty
            ? null
            : _workforceString(row['last_readiness_score']),
        todaysScan: row['todays_scan'] is bool
            ? row['todays_scan'] as bool
            : null,
        presenceStatus: _workforceString(row['presence_status']).isEmpty
            ? null
            : _workforceString(row['presence_status']),
      );
    }).toList();
    final departments = result.departments
        .map(
          (row) => WorkspaceDepartment(
            id: _workforceString(row['id']),
            name: _workforceString(row['name']),
          ),
        )
        .where((item) => item.id.trim().isNotEmpty)
        .toList();
    return OwnerWorkforceDirectoryData(
      members: members,
      departments: departments,
      summary: result.summary,
    );
  }

  Future<OwnerWorkforceDirectoryData> _buildLegacyWorkforceDirectory(
    String profileId,
    String membershipId,
    String role,
  ) async {
    safeDebugLog(
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

  String _workforceString(dynamic value) => value?.toString().trim() ?? '';

  String? _normalizeWorkforceRisk(String value) {
    final normalized = value.trim().toLowerCase().replaceAll('_', ' ');
    return switch (normalized) {
      'stable' => 'Stable',
      'low focus' => 'Low Focus',
      'elevated fatigue' => 'Elevated Fatigue',
      'high risk' => 'High Risk',
      _ => null,
    };
  }

  bool _workforceMissing(Map<String, dynamic> row) {
    final today = row['todays_scan'];
    if (today is bool) return !today;
    final status = _workforceString(row['presence_status']).toLowerCase();
    return status == 'missing' ||
        status == 'missing_scan' ||
        status == 'not_scanned';
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
      safeDebugLog('[OWNER] workforce load success count=${members.length}');
      return members;
    } on DioException catch (e) {
      safeDebugLog(
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
    safeDebugLog(
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
    final workforce = await fetchWorkforceDirectory();
    final members = workforce.members;
    final departments = workforce.departments;
    stopwatch.stop();
    safeDebugLog(
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
      activeMembers: _summaryInt(
        workforce.summary,
        'activeMembers',
        fallback: members.where((member) => member.isActive).length,
      ),
      departmentsCount: _summaryInt(
        workforce.summary,
        'departments',
        fallback: departments.length,
      ),
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
      safeDebugLog(
        '[ROLE_SERVICE_GUARD] service=OwnerOpsService expected=owner actual=${activeRole.isEmpty ? "unknown" : activeRole} ignored=true',
      );
      safeDebugLog(
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
    safeDebugLog(
      '[SCOPED_DATA_REQUEST] feature=reports operation=owner_snapshot method=GET endpoint_or_collection=/items/scan_results membership_id=${workspace?.membershipId ?? ''} business_profile=$profileId department=${workspace?.departmentId?.trim() ?? ''} membership_role=${workspace?.memberRole ?? ''} context_source=${OrganizationService.instance.activeWorkspaceContextSource} workspace_revision=$startRevision filter_summary=business_profile=$profileId;scan_results;alerts;scan_requests;departments started=true trace=$trace',
    );
    final workforceStopwatch = Stopwatch()..start();
    var team = <OwnerMemberView>[];
    Map<String, dynamic> workforceSummary = const {};
    String? workforceUnavailableMessage;
    try {
      final workforce = await fetchWorkforceDirectory(
        forceRefresh: forceRefresh,
      );
      team = workforce.members;
      workforceSummary = workforce.summary;
    } catch (error) {
      final status = error is DioException
          ? error.response?.statusCode ?? 0
          : 0;
      safeDebugLog(
        '[OWNER_SNAPSHOT_SECTION_FAILED] step=workforce http_status=$status error_type=${error.runtimeType}',
      );
      workforceUnavailableMessage =
          'Workforce data is unavailable right now. Other dashboard data is still available.';
    }
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
    final activeMembers = workforceUnavailableMessage != null
        ? -1
        : _summaryInt(
            workforceSummary,
            'activeMembers',
            fallback: team.where((member) => member.isActive).length,
          );
    final checksToday = workforceUnavailableMessage != null
        ? -1
        : _summaryInt(
            workforceSummary,
            'completedToday',
            fallback: team.where((member) => !member.missingCheck).length,
          );
    final missing = workforceUnavailableMessage != null
        ? -1
        : _summaryInt(
            workforceSummary,
            'missingScans',
            fallback: team.where((member) => member.missingCheck).length,
          );
    final attention = workforceUnavailableMessage != null
        ? -1
        : _summaryInt(
            workforceSummary,
            'needsAttention',
            fallback: team.where((member) => member.needsAttention).length,
          );
    final compliance = activeMembers == 0
        ? '0%'
        : '${((checksToday / activeMembers) * 100).toStringAsFixed(0)}%';
    safeDebugLog('[OWNER_HOME_CONTEXT] business_profile=$profileId');
    safeDebugLog(
      '[OWNER_HOME_CONTEXT] membership_id=${workspace?.membershipId.trim() ?? ''}',
    );
    safeDebugLog(
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

    final departmentsCount = _summaryInt(
      workforceSummary,
      'departments',
      fallback: departments.length,
    );
    safeDebugLog(
      '[OWNER_HOME_LOAD] total_duration_ms=${totalStopwatch.elapsedMilliseconds}',
    );
    safeDebugLog(
      '[SCOPED_DATA_RESPONSE] feature=reports operation=owner_snapshot http_status=200 result_count=${readinessDistribution.values.fold<int>(0, (a, b) => a + b)} duration_ms=${totalStopwatch.elapsedMilliseconds} membership_id=${workspace?.membershipId ?? ''} business_profile=$profileId workspace_revision_before=$startRevision workspace_revision_after=${OrganizationService.instance.workspaceRevision} context_unchanged=${OrganizationService.instance.workspaceRevision == startRevision && OrganizationService.instance.workspaceSignature == startSignature} returned_business_profile_ids=[$profileId] returned_membership_ids=[${workspace?.membershipId ?? ''}] empty_result=${readinessDistribution.values.every((value) => value == 0)} trace=$trace',
    );

    return OwnerSnapshot(
      activeMembers: activeMembers,
      workforceUnavailableMessage: workforceUnavailableMessage,
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
      if (profileId.trim().isNotEmpty) {
        // TEMP_READINESS_DEBUG
        await _logReadinessDebugProbes(
          profileId: profileId,
          source: 'owner',
          appQueryCount: 0,
          scanResultRows: const [],
        );
      }
      safeDebugLog(
        '[OWNER_READINESS_DISTRIBUTION_SCOPE] scope=self scoped_profile=${profileId.trim().isNotEmpty} has_user=${userId.trim().isNotEmpty}',
      );
      safeDebugLog(
        '[OWNER_READINESS_DISTRIBUTION] has_current_user=${userId.trim().isNotEmpty} scoped_profile=${profileId.trim().isNotEmpty} query=skipped',
      );
      safeDebugLog('[OWNER_READINESS_DISTRIBUTION] scan_results_raw_count=0');
      safeDebugLog('[OWNER_READINESS_DISTRIBUTION] failed_scans_raw_count=0');
      safeDebugLog(
        '[OWNER_READINESS_DISTRIBUTION] normalized_counts=$normalized',
      );
      return normalized;
    }

    // Owner Home shows company-scoped completed scan_results.
    safeDebugLog(
      '[OWNER_READINESS_DISTRIBUTION_SCOPE] scope=self scoped_profile=true has_user=true',
    );
    var resultQueryFailed = false;
    final resultQuery = {
      'filter[scan_id][business_profile][_eq]': profileId,
      'sort': '-date_created',
      'limit': 500,
      'fields': 'id,scan_id,risk_level,readiness_score,date_created',
    };
    safeDebugLog(
      '[OWNER_READINESS_DISTRIBUTION_SOURCE] endpoint=/items/scan_results query_keys=${resultQuery.keys.toList()}',
    );
    safeDebugLog(
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
      safeDebugLog('[OWNER_READINESS_DISTRIBUTION] raw_count=${rows.length}');
      resultRows.addAll(rows);
    } on DioException catch (e) {
      resultQueryFailed = true;
      final status = e.response?.statusCode ?? 0;
      safeDebugLog(
        '[OWNER_READINESS_DISTRIBUTION] direct_result_query_status=$status error_type=${e.type}',
      );
      if (status != 400 && status != 403 && status != 422) {
        safeDebugLog(
          '[OWNER_READINESS_DISTRIBUTION] normalized_counts=$normalized',
        );
      }
    } catch (e) {
      resultQueryFailed = true;
      safeDebugLog(
        '[OWNER_READINESS_DISTRIBUTION] result_query_error_type=${e.runtimeType}',
      );
    }
    // TEMP_READINESS_DEBUG
    await _logReadinessDebugProbes(
      profileId: profileId,
      source: 'owner',
      appQueryCount: resultRows.length,
      scanResultRows: resultRows,
    );
    _logReadinessDateHistogram(
      profileId: profileId,
      workspaceRole: _workspaceRole(
        OrganizationService.instance.cachedActiveWorkspaceContext,
      ),
      source: 'owner_home_distribution',
      rows: resultRows,
      periodStart: null,
      periodEnd: null,
    );

    if (resultRows.isNotEmpty) {
      final latestScanId = _latestScanIdFromResultRows(resultRows);
      safeDebugLog(
        '[OWNER_READINESS_DISTRIBUTION] has_latest_scan_id=${latestScanId.isNotEmpty}',
      );
      safeDebugLog(
        '[OWNER_READINESS_DISTRIBUTION_SOURCE] endpoint=/items/scan_results query_keys=${resultQuery.keys.toList()} raw_count=${resultRows.length} has_latest_scan_id=${latestScanId.isNotEmpty}',
      );
      final countedScanIds = <String>{};
      var ownerFilteredCount = 0;
      var invalidReadinessStatusCount = 0;
      for (final row in resultRows) {
        final scanId = _relationId(row['scan_id']);
        final label = _normalizeOwnerReadinessLabel(row);
        if (label == null) {
          invalidReadinessStatusCount++;
          continue;
        }
        ownerFilteredCount++;
        if (scanId.isNotEmpty) countedScanIds.add(scanId);
        normalized[label] = (normalized[label] ?? 0) + 1;
      }
      _mergeLatestHistoryResultIntoDistribution(
        latestHistoryResult: latestHistoryResult,
        normalized: normalized,
        countedScanIds: countedScanIds,
      );
      if (kDebugMode) {
        final profilePrefix = _readinessDebugProfilePrefix(profileId);
        final workspaceRole = _readinessDebugRole(
          _workspaceRole(
            OrganizationService.instance.cachedActiveWorkspaceContext,
          ),
        );
        final displayedCount = normalized.values.fold<int>(
          0,
          (sum, count) => sum + count,
        );
        readinessDebugLog(
          '[READINESS_DEBUG] profile_prefix=$profilePrefix workspace_role=$workspaceRole path=owner_home_distribution raw_count=${resultRows.length} matched_rows=$ownerFilteredCount filtered_count=$displayedCount reject_invalid_readiness_status=$invalidReadinessStatusCount reject_missing_scan_id=0 reject_duplicate_scan_result=0 reject_workspace=0 reject_period=0 reject_department=0 department_filter_applied=false period_start=none period_end=none period_basis=unbounded_owner_home',
        );
      }
      safeDebugLog(
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
    safeDebugLog(
      '[OWNER_READINESS_DISTRIBUTION] query_keys=${scansQuery.keys.toList()}',
    );
    safeDebugLog(
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
      safeDebugLog(
        '[OWNER_READINESS_DISTRIBUTION] raw_count=0 error_type=${e.runtimeType}',
      );
      safeDebugLog(
        '[OWNER_READINESS_DISTRIBUTION] normalized_counts=$normalized',
      );
      return normalized;
    }

    safeDebugLog(
      '[OWNER_READINESS_DISTRIBUTION] failed_scans_raw_count=${_countFailedScans(scanRows)}',
    );
    if (scanRows.isEmpty) {
      safeDebugLog('[OWNER_READINESS_DISTRIBUTION] scan_results_raw_count=0');
      safeDebugLog(
        '[OWNER_READINESS_DISTRIBUTION] normalized_counts=$normalized',
      );
      return normalized;
    }

    final scanIds = scanRows
        .map((row) => row['id']?.toString() ?? '')
        .where((id) => id.isNotEmpty)
        .toList();
    if (scanIds.isEmpty) {
      safeDebugLog('[OWNER_READINESS_DISTRIBUTION] scan_results_raw_count=0');
      safeDebugLog(
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
      safeDebugLog(
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
      safeDebugLog(
        '[OWNER_READINESS_DISTRIBUTION] result_query_error_type=${e.runtimeType}',
      );
      safeDebugLog('[OWNER_READINESS_DISTRIBUTION] scan_results_raw_count=0');
      safeDebugLog(
        '[OWNER_READINESS_DISTRIBUTION] normalized_counts=$normalized',
      );
      return normalized;
    }

    safeDebugLog(
      '[OWNER_READINESS_DISTRIBUTION] scan_results_raw_count=${fallbackResultRows.length}',
    );
    safeDebugLog(
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

    safeDebugLog(
      '[OWNER_READINESS_DISTRIBUTION] normalized_counts=$normalized',
    );
    if (resultQueryFailed) {
      safeDebugLog(
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
      safeDebugLog(
        '[OWNER_READINESS_DISTRIBUTION_COMPARE] has_latest_history_scan_id=false included_in_distribution=false reason=no_latest_history_result',
      );
      return;
    }
    if (countedScanIds.contains(scanId)) {
      safeDebugLog(
        '[OWNER_READINESS_DISTRIBUTION_COMPARE] has_latest_history_scan_id=true included_in_distribution=true reason=backend_query',
      );
      return;
    }
    final label = _normalizeReadinessKey(
      latestHistoryResult?.riskLevel ?? latestHistoryResult?.overallState,
    );
    if (label == null) {
      safeDebugLog(
        '[OWNER_READINESS_DISTRIBUTION_COMPARE] has_latest_history_scan_id=true included_in_distribution=false reason=missing_valid_risk_level',
      );
      return;
    }
    normalized[label] = (normalized[label] ?? 0) + 1;
    countedScanIds.add(scanId);
    safeDebugLog(
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
    if (raw.isEmpty) return 'Unavailable - please retake the scan';
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
        lowered == 'high risk') {
      return 'High Risk';
    }
    return 'Unavailable - please retake the scan';
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
    final workforce = await fetchWorkforceDirectory();
    final team = workforce.members;
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

    final todayCompleted = _summaryInt(
      workforce.summary,
      'completedToday',
      fallback: team.where((member) => !member.missingCheck).length,
    );
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
    final activeMembers = _summaryInt(
      workforce.summary,
      'activeMembers',
      fallback: team.where((member) => member.isActive).length,
    );
    final missing = _summaryInt(
      workforce.summary,
      'missingScans',
      fallback: team.where((member) => member.missingCheck).length,
    );
    final attention = _summaryInt(
      workforce.summary,
      'needsAttention',
      fallback: team.where((member) => member.needsAttention).length,
    );
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
    final organization = OrganizationService.instance;
    var startRevision = organization.workspaceRevision;
    var startSignature = organization.workspaceSignature;
    final activeWorkspaceAtCall = organization.cachedActiveWorkspaceContext;
    final workspace =
        activeWorkspaceAtCall ??
        await organization.fetchActiveWorkspaceContext(forceRefresh: true);
    final profileSource = activeWorkspaceAtCall == null
        ? 'canonical_context_refresh'
        : 'active_workspace_state';
    if (activeWorkspaceAtCall == null) {
      startRevision = organization.workspaceRevision;
      startSignature = organization.workspaceSignature;
    }
    final profileId = workspace?.businessProfileId.trim() ?? '';
    final workspaceRole = _readinessDebugRole(_workspaceRole(workspace));
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
        queryFailed: true,
      );
    }
    final normalized = <String, int>{
      'Stable': 0,
      'Low Focus': 0,
      'Elevated Fatigue': 0,
      'High Risk': 0,
    };
    final department = departmentId?.trim() ?? '';
    safeDebugLog(
      '[COMPLIANCE_READINESS_DISTRIBUTION_SCOPE] scope=${department.isEmpty ? "workspace" : "department"} scoped_profile=${profileId.isNotEmpty} scoped_department=${department.isNotEmpty}',
    );
    if (profileId.isEmpty) {
      safeDebugLog('[COMPLIANCE_READINESS_DISTRIBUTION] query=skipped');
      safeDebugLog('[COMPLIANCE_READINESS_DISTRIBUTION] raw_count=0');
      safeDebugLog(
        '[COMPLIANCE_READINESS_DISTRIBUTION] normalized_counts=$normalized',
      );
      return WorkspaceReadinessSummary(
        distribution: normalized,
        resultsByScanId: const <String, OwnerAssessmentResult>{},
        queryFailed: true,
      );
    }

    final resultQuery = {
      'filter[scan_id][business_profile][_eq]': profileId,
      'sort': '-date_created',
      'limit': 800,
      'fields':
          'id,scan_id.id,scan_id.business_profile,risk_level,readiness_score,date_created',
    };
    final activeProfileAtRequest =
        organization.cachedActiveWorkspaceContext?.businessProfileId.trim() ??
        '';
    final queryProfileMatchesActive =
        profileId.isNotEmpty && profileId == activeProfileAtRequest;
      safeDebugLog(
        '[READINESS_FILTER] query_profile_matches_active=$queryProfileMatchesActive profile_source=$profileSource profile_source_cached=${activeWorkspaceAtCall != null} cached_profile_is_current=$queryProfileMatchesActive outgoing_profile_present=${profileId.isNotEmpty} active_profile_present=${activeProfileAtRequest.isNotEmpty}',
      );
    if (!queryProfileMatchesActive ||
        _isWorkspaceStale(startRevision, startSignature)) {
      safeDebugLog(
        '[READINESS_FILTER] summary condition=workspace_context_mismatch rejected=0 raw_rows_workspace_mismatch=0',
      );
      return WorkspaceReadinessSummary(
        distribution: normalized,
        resultsByScanId: const <String, OwnerAssessmentResult>{},
        queryFailed: true,
      );
    }
    safeDebugLog(
      '[COMPLIANCE_READINESS_DISTRIBUTION] query_keys=${resultQuery.keys.toList()}',
    );
    var readinessDebugProbesLogged = false;
    try {
      final response = await _client.get(
        '/items/scan_results',
        queryParameters: resultQuery,
      );
      final statusCode = response.statusCode ?? 0;
      if (statusCode < 200 || statusCode >= 300) {
        _logReadinessRequestFailure(
          dioType: 'none',
          statusCode: statusCode,
          responseData: response.data,
          fallbackMessage: 'non_2xx_response',
        );
        safeDebugLog(
          '[COMPLIANCE_READINESS_DISTRIBUTION] request_failed status=$statusCode',
        );
        return WorkspaceReadinessSummary(
          distribution: normalized,
          resultsByScanId: const <String, OwnerAssessmentResult>{},
          queryFailed: true,
        );
      }
      if (_isWorkspaceStale(startRevision, startSignature)) {
        _logStaleResult();
        return WorkspaceReadinessSummary(
          distribution: normalized,
          resultsByScanId: const <String, OwnerAssessmentResult>{},
          queryFailed: true,
        );
      }
      final data = response.data['data'];
      final rows = data is List
          ? data.whereType<Map<String, dynamic>>().toList()
          : <Map<String, dynamic>>[];
      safeDebugLog(
        '[COMPLIANCE_READINESS_DISTRIBUTION] raw_count=${rows.length}',
      );
      final periodStart = start == null ? 'none' : _readinessDebugDate(start);
      final periodEnd = end == null ? 'none' : _readinessDebugDate(end);
      _logReadinessDateHistogram(
        profileId: profileId,
        workspaceRole: workspaceRole,
        source: 'company_readiness',
        rows: rows,
        periodStart: periodStart,
        periodEnd: periodEnd,
      );
      // TEMP_READINESS_DEBUG
      await _logReadinessDebugProbes(
        profileId: profileId,
        source: 'hr_compliance',
        appQueryCount: rows.length,
        scanResultRows: rows,
      );
      readinessDebugProbesLogged = true;
      final filteredRows = <Map<String, dynamic>>[];
      final rejectCounts = <String, int>{};
      final activeWorkspaceId = profileId;
      var rawWorkspaceMismatchCount = 0;
      var rawWorkspaceMissingCount = 0;
      var identityDataIncomplete = false;
      final periodBoundsBasis = start == null && end == null
          ? 'unbounded'
          : 'caller_bounds_start_inclusive_end_exclusive';
      for (final row in rows) {
        final failed = <String>[];
        final scanRelation = row['scan_id'];
        final scanMap = scanRelation is Map
            ? scanRelation
            : const <dynamic, dynamic>{};
        final rowProfileId = _relationId(scanMap['business_profile']);
        if (rowProfileId.isEmpty) {
          rawWorkspaceMissingCount++;
          identityDataIncomplete = true;
          failed.add('workspace_id_missing');
        } else if (rowProfileId != profileId) {
          rawWorkspaceMismatchCount++;
          identityDataIncomplete = true;
          failed.add('workspace_mismatch');
        }
        final createdAt = _parseDate(row['date_created']);
        if (createdAt == null) {
          failed.add('invalid_date');
        } else {
          final local = createdAt.toLocal();
          if (start != null && local.isBefore(start)) {
            failed.add('before_period');
          }
          if (end != null && !local.isBefore(end)) {
            failed.add('after_period');
          }
        }
        if (failed.isEmpty) {
          filteredRows.add(row);
          continue;
        }
        for (final condition in failed) {
          rejectCounts[condition] = (rejectCounts[condition] ?? 0) + 1;
        }
        final rowUser = scanMap['user'];
        safeDebugLog(
          '[READINESS_FILTER] rejected=true failed=${failed.join('+')} row_workspace_id_present=${rowProfileId.isNotEmpty} row_workspace_matches_active=${rowProfileId.isNotEmpty && rowProfileId == activeWorkspaceId} row_member_id_present=${_relationId(row['member_id']).isNotEmpty || _relationId(scanMap['member_id']).isNotEmpty} row_user_id_present=${_relationId(rowUser).isNotEmpty} active_workspace_id_present=${activeWorkspaceId.isNotEmpty} period_start=$periodStart period_end=$periodEnd',
        );
      }
      final visibilityRole = _workspaceRole(workspace);
      final isHrVisibility = visibilityRole == 'hr';
      final hrMemberByUserId = <String, String>{};
      final hrMemberByMembershipId = <String, String>{};
      final hrMemberIdPresentByUserId = <String, bool>{};
      final hrMembershipCountByUserId = <String, int>{};
      final scanUserByScanId = <String, String>{};
      final scanWorkspacePresenceByScanId = <String, bool>{};
      final requestMemberByScanId = <String, String>{};
      final requestUserByScanId = <String, String>{};
      String scopedIdentityKey(String value) =>
          '$profileId::${value.trim().toLowerCase()}';
      if (isHrVisibility) {
        try {
          final workforce = await WellarWorkforceService.instance
              .fetchWorkforceFromWellar();
          if (_isWorkspaceStale(startRevision, startSignature)) {
            _logStaleResult();
            return WorkspaceReadinessSummary(
              distribution: normalized,
              resultsByScanId: const <String, OwnerAssessmentResult>{},
              queryFailed: true,
            );
          }
          if (!workforce.isSuccessful) throw workforce.asFailure();
          final workforceProfileId =
              _relationId(workforce.active['workspace']);
          if (workforceProfileId.isEmpty) {
            // TEMP_READINESS_DEBUG
            if (kDebugMode) {
              readinessDebugLog(
                '[READINESS_DEBUG] profile_prefix=${_readinessDebugProfilePrefix(profileId)} workspace_role=$workspaceRole workforce_active_workspace_key_missing=true',
              );
            }
          } else if (workforceProfileId != profileId) {
            identityDataIncomplete = true;
            safeDebugLog(
              '[READINESS_FILTER] identity_lookup_failed=true source=wellar_workforce_active_workspace active_profile_matches_requested=false',
            );
          }
          if (workforceProfileId.isEmpty || workforceProfileId == profileId) {
            for (final member in workforce.memberRows) {
              final userKey =
                  member['user_id']?.toString().trim().toLowerCase() ?? '';
              if (userKey.isNotEmpty) {
                final scopedUserKey = scopedIdentityKey(userKey);
                hrMemberByUserId[scopedUserKey] =
                    member['member_role']?.toString().trim().toLowerCase() ??
                    '';
                hrMemberIdPresentByUserId[scopedUserKey] =
                    (member['member_id'] ?? member['id'])
                        ?.toString()
                        .trim()
                        .isNotEmpty ==
                    true;
                hrMembershipCountByUserId[scopedUserKey] =
                    (hrMembershipCountByUserId[scopedUserKey] ?? 0) + 1;
              }
              final membershipKey =
                  (member['member_id'] ?? member['id'])
                      ?.toString()
                      .trim() ??
                  '';
              if (membershipKey.isNotEmpty) {
                hrMemberByMembershipId[scopedIdentityKey(membershipKey)] =
                    member['member_role']?.toString().trim().toLowerCase() ??
                    '';
              }
            }
          }
        } catch (_) {
          identityDataIncomplete = true;
          safeDebugLog(
            '[READINESS_FILTER] identity_lookup_failed=true source=wellar_workforce',
          );
        }
        try {
          final requests = await RequestService.instance.fetchHrRequests();
          if (_isWorkspaceStale(startRevision, startSignature)) {
            _logStaleResult();
            return WorkspaceReadinessSummary(
              distribution: normalized,
              resultsByScanId: const <String, OwnerAssessmentResult>{},
              queryFailed: true,
            );
          }
          for (final request in requests) {
            final scanId = request.scanId?.trim() ?? '';
            if (scanId.isEmpty) continue;
            final requestedMemberId = request.requestedForId?.trim() ?? '';
            final requestedUserId = request.requestedForUserId?.trim() ?? '';
            final scopedScanKey = scopedIdentityKey(scanId);
            if (requestedMemberId.isNotEmpty) {
              requestMemberByScanId.putIfAbsent(
                scopedScanKey,
                () => requestedMemberId,
              );
            }
            if (requestedUserId.isNotEmpty) {
              requestUserByScanId.putIfAbsent(
                scopedScanKey,
                () => requestedUserId,
              );
            }
          }
        } catch (_) {
          identityDataIncomplete = true;
          safeDebugLog(
            '[READINESS_FILTER] identity_lookup_failed=true source=scan_requests',
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
                'fields': 'id,user,business_profile',
              },
            );
            if (_isWorkspaceStale(startRevision, startSignature)) {
              _logStaleResult();
              return WorkspaceReadinessSummary(
                distribution: normalized,
                resultsByScanId: const <String, OwnerAssessmentResult>{},
                queryFailed: true,
              );
            }
            final scansData = scansResponse.data['data'];
            final scanRows = scansData is List
                ? scansData.whereType<Map<String, dynamic>>().toList()
                : const <Map<String, dynamic>>[];
            for (final row in scanRows) {
              final scanId = row['id']?.toString().trim() ?? '';
              if (scanId.isEmpty) continue;
              final scopedScanKey = scopedIdentityKey(scanId);
              final userId = _relationId(row['user']);
              scanWorkspacePresenceByScanId[scopedScanKey] = _relationId(
                row['business_profile'],
              ).isNotEmpty;
              if (userId.isNotEmpty) {
                scanUserByScanId[scopedScanKey] = userId;
              }
            }
          }
        } catch (_) {
          identityDataIncomplete = true;
          safeDebugLog(
            '[READINESS_FILTER] identity_lookup_failed=true source=wellness_scans',
          );
        }
      }
      final resultsByScanId = <String, OwnerAssessmentResult>{};
      final memberRejectCounts = <String, int>{};
      for (final row in filteredRows) {
        final scanId = _relationId(row['scan_id']);
        if (scanId.isEmpty || resultsByScanId.containsKey(scanId)) {
          if (scanId.isEmpty) {
            identityDataIncomplete = true;
            memberRejectCounts['missing_scan_id'] =
                (memberRejectCounts['missing_scan_id'] ?? 0) + 1;
            safeDebugLog(
              '[READINESS_FILTER] rejected=true failed=missing_scan_id row_workspace_id_present=false row_member_id_present=false row_user_id_present=false active_workspace_id_present=${activeWorkspaceId.isNotEmpty} period_start=$periodStart period_end=$periodEnd',
            );
          } else if (resultsByScanId.containsKey(scanId)) {
            memberRejectCounts['duplicate_scan_result'] =
                (memberRejectCounts['duplicate_scan_result'] ?? 0) + 1;
          }
          continue;
        }
        final label = _normalizeReadinessDisplayLabel(_readinessRawLabel(row));
        final scopedScanKey = scopedIdentityKey(scanId);
        if (label == null) {
          final rawRiskLevel = row['risk_level'];
          final rawReadinessScore = row['readiness_score'];
          memberRejectCounts['invalid_readiness_status'] =
              (memberRejectCounts['invalid_readiness_status'] ?? 0) + 1;
          safeDebugLog(
            '[READINESS_FILTER] invalid_status risk_level_type=${_rawDiagnosticType(rawRiskLevel)} risk_level_category=${_readinessDiagnosticCategory(rawRiskLevel)} readiness_score_type=${_rawDiagnosticType(rawReadinessScore)} readiness_score_category=${_readinessDiagnosticCategory(rawReadinessScore, numeric: true)}',
          );
          safeDebugLog(
            '[READINESS_FILTER] rejected=true failed=invalid_readiness_status row_workspace_id_present=${scanWorkspacePresenceByScanId[scopedScanKey] == true} row_member_id_present=false row_user_id_present=${scanUserByScanId[scopedScanKey]?.isNotEmpty == true} active_workspace_id_present=${activeWorkspaceId.isNotEmpty} period_start=$periodStart period_end=$periodEnd',
          );
          continue;
        }
        if (isHrVisibility) {
          final scanUserId = scanUserByScanId[scopedScanKey];
          final requestMembershipId = requestMemberByScanId[scopedScanKey];
          final requestUserId = requestUserByScanId[scopedScanKey];
          final scanUserRole = scanUserId == null
              ? null
              : hrMemberByUserId[scopedIdentityKey(scanUserId)];
          final requestMembershipRole = requestMembershipId == null
              ? null
              : hrMemberByMembershipId[
                  scopedIdentityKey(requestMembershipId)
                ];
          final requestUserRole = requestUserId == null
              ? null
              : hrMemberByUserId[scopedIdentityKey(requestUserId)];
          final memberRole =
              scanUserRole ?? requestMembershipRole ?? requestUserRole;
          if (memberRole == null || memberRole == 'owner') {
            final reason = memberRole == null
                ? 'member_unmatched'
                : 'owner_excluded';
            memberRejectCounts[reason] = (memberRejectCounts[reason] ?? 0) + 1;
            if (reason == 'member_unmatched') identityDataIncomplete = true;
            final resolvedRoleSource = memberRole == null
                ? 'other'
                : 'workforce_active_company';
            final activeCompanyRole =
                (scanUserId == null
                    ? null
                    : hrMemberByUserId[scopedIdentityKey(scanUserId)]) ??
                (requestUserId == null
                    ? null
                    : hrMemberByUserId[scopedIdentityKey(requestUserId)]) ??
                (requestMembershipId == null
                    ? null
                    : hrMemberByMembershipId[
                        scopedIdentityKey(requestMembershipId)
                      ]);
            final membershipUserId = scanUserId ?? requestUserId;
            final activeMembershipCount = membershipUserId == null
                ? 0
                : hrMembershipCountByUserId[
                      scopedIdentityKey(membershipUserId)
                    ] ??
                    0;
            safeDebugLog(
              '[READINESS_FILTER] rejected=true failed=$reason row_workspace_id_present=${scanWorkspacePresenceByScanId[scopedScanKey] == true} row_member_id_present=${requestMembershipId?.isNotEmpty == true || hrMemberIdPresentByUserId[scopedIdentityKey(scanUserId ?? requestUserId ?? '')] == true} row_user_id_present=${scanUserId?.isNotEmpty == true || requestUserId?.isNotEmpty == true} active_workspace_id_present=${activeWorkspaceId.isNotEmpty} period_start=$periodStart period_end=$periodEnd resolved_role_source=$resolvedRoleSource resolved_role=${memberRole ?? 'unknown'} active_company_membership_count=$activeMembershipCount user_has_multiple_memberships_in_workforce_data=${activeMembershipCount > 1} active_company_role=${activeCompanyRole ?? 'unknown'} resolved_role_differs_from_active_company_membership=${activeCompanyRole != null && memberRole != activeCompanyRole}',
            );
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
      safeDebugLog(
        '[COMPLIANCE_READINESS_DISTRIBUTION] filtered_count=${resultsByScanId.length}',
      );
      if (kDebugMode) {
        final debugRejectCounts = <String, int>{
          'workspace_mismatch': rejectCounts['workspace_mismatch'] ?? 0,
          'workspace_id_missing': rejectCounts['workspace_id_missing'] ?? 0,
          'invalid_date': rejectCounts['invalid_date'] ?? 0,
          'before_period': rejectCounts['before_period'] ?? 0,
          'after_period': rejectCounts['after_period'] ?? 0,
          'missing_scan_id': memberRejectCounts['missing_scan_id'] ?? 0,
          'duplicate_scan_result':
              memberRejectCounts['duplicate_scan_result'] ?? 0,
          'invalid_readiness_status':
              memberRejectCounts['invalid_readiness_status'] ?? 0,
          'member_unmatched': memberRejectCounts['member_unmatched'] ?? 0,
          'owner_excluded': memberRejectCounts['owner_excluded'] ?? 0,
          'department': 0,
        };
        readinessDebugLog(
          '[READINESS_DEBUG] profile_prefix=${_readinessDebugProfilePrefix(profileId)} workspace_role=$workspaceRole path=company_readiness raw_count=${rows.length} filtered_count=${resultsByScanId.length} reject_counts=${_readinessDebugRejectCounts(debugRejectCounts)} department_filter_applied=false identity_lookup_failed=${identityDataIncomplete} period_start=$periodStart period_end=$periodEnd period_basis=$periodBoundsBasis',
        );
      }
      final aggregateRejectCounts = <String, int>{
        'workspace_mismatch': rejectCounts['workspace_mismatch'] ?? 0,
        'workspace_id_missing': rejectCounts['workspace_id_missing'] ?? 0,
        'invalid_date': rejectCounts['invalid_date'] ?? 0,
        'before_period': rejectCounts['before_period'] ?? 0,
        'after_period': rejectCounts['after_period'] ?? 0,
        'missing_scan_id': memberRejectCounts['missing_scan_id'] ?? 0,
        'duplicate_scan_result':
            memberRejectCounts['duplicate_scan_result'] ?? 0,
        'invalid_readiness_status':
            memberRejectCounts['invalid_readiness_status'] ?? 0,
        'member_unmatched': memberRejectCounts['member_unmatched'] ?? 0,
        'owner_excluded': memberRejectCounts['owner_excluded'] ?? 0,
      };
      for (final entry in aggregateRejectCounts.entries) {
        safeDebugLog(
          '[READINESS_FILTER] summary condition=${entry.key} rejected=${entry.value} raw_rows_workspace_mismatch=$rawWorkspaceMismatchCount raw_rows_workspace_id_missing=$rawWorkspaceMissingCount period_start=$periodStart period_end=$periodEnd active_workspace_id_present=${activeWorkspaceId.isNotEmpty}',
        );
      }
      safeDebugLog(
        '[READINESS_FILTER] summary condition=identity_lookup_failed rejected=${identityDataIncomplete ? 1 : 0} raw_rows_workspace_mismatch=$rawWorkspaceMismatchCount raw_rows_workspace_id_missing=$rawWorkspaceMissingCount period_start=$periodStart period_end=$periodEnd active_workspace_id_present=${activeWorkspaceId.isNotEmpty}',
      );
      safeDebugLog(
        '[COMPLIANCE_READINESS_DISTRIBUTION] normalized_counts=$normalized',
      );
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
          queryFailed: true,
        );
      }
      return WorkspaceReadinessSummary(
        distribution: normalized,
        resultsByScanId: resultsByScanId,
        queryFailed: false,
      );
    } on DioException catch (e) {
      if (!readinessDebugProbesLogged) {
        // TEMP_READINESS_DEBUG
        await _logReadinessDebugProbes(
          profileId: profileId,
          source: 'hr_compliance',
          appQueryCount: null,
          scanResultRows: const [],
        );
      }
      _logReadinessRequestFailure(
        dioType: e.type.toString(),
        statusCode: e.response?.statusCode ?? 0,
        responseData: e.response?.data,
        fallbackMessage: e.message,
      );
      safeDebugLog(
        '[COMPLIANCE_READINESS_DISTRIBUTION] raw_count=0 error_status=${e.response?.statusCode} reason=query failed',
      );
      safeDebugLog(
        '[COMPLIANCE_READINESS_DISTRIBUTION] normalized_counts=hidden_due_to_query_failure',
      );
      return WorkspaceReadinessSummary(
        distribution: normalized,
        resultsByScanId: const <String, OwnerAssessmentResult>{},
        queryFailed: true,
      );
    } catch (e) {
      if (!readinessDebugProbesLogged) {
        // TEMP_READINESS_DEBUG
        await _logReadinessDebugProbes(
          profileId: profileId,
          source: 'hr_compliance',
          appQueryCount: null,
          scanResultRows: const [],
        );
      }
      _logReadinessRequestFailure(
        dioType: 'none',
        statusCode: 0,
        fallbackMessage: e.runtimeType.toString(),
      );
      safeDebugLog(
        '[COMPLIANCE_READINESS_DISTRIBUTION] raw_count=0 reason=query failed error_type=${e.runtimeType}',
      );
      safeDebugLog(
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
      safeDebugLog(
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

  // TEMP_READINESS_DEBUG
  Future<void> _logReadinessDebugProbes({
    required String profileId,
    required String source,
    required int? appQueryCount,
    required List<Map<String, dynamic>> scanResultRows,
  }) async {
    if (!kDebugMode) return;
    final profilePrefix = _readinessDebugProfilePrefix(profileId);
    final workspaceRole = _readinessDebugRole(
      _workspaceRole(
        OrganizationService.instance.cachedActiveWorkspaceContext,
      ),
    );
    final debugContext =
        'profile_prefix=$profilePrefix workspace_role=$workspaceRole';
    if (profileId.trim().isEmpty) {
      readinessDebugLog(
        '[READINESS_DEBUG] $debugContext probes_skipped source=$source active_profile_present=false',
      );
      return;
    }
    Future<void> isolateProbe(
      String name,
      Future<void> Function() run,
    ) async {
      try {
        await run();
      } catch (_) {
        _readinessDebugProbeFailed(
          name: name,
          status: 0,
          debugContext: debugContext,
        );
      }
    }

    // TEMP_READINESS_DEBUG: probe result visibility without logging row values.
    await isolateProbe('A', () async {
    final probeA = await _readinessDebugGet(
      name: 'A',
      path: '/items/scan_results',
      debugContext: debugContext,
      query: const {
        'limit': 200,
        'sort': '-date_created',
        'fields': 'id,date_created,scan_id.business_profile',
      },
    );
    if (probeA != null) {
      final rows = _readinessDebugRows(probeA.data);
      final profiles = <String>{};
      var matching = 0;
      var other = 0;
      DateTime? newestActiveDate;
      for (final row in rows) {
        final scan = _readinessDebugMap(row['scan_id']);
        final rowProfile = _relationId(scan['business_profile']);
        if (rowProfile.isEmpty) continue;
        profiles.add(rowProfile);
        if (rowProfile == profileId) {
          matching++;
          final date = DateTime.tryParse(row['date_created']?.toString() ?? '');
          if (date != null &&
              (newestActiveDate == null || date.isAfter(newestActiveDate))) {
            newestActiveDate = date;
          }
        } else {
          other++;
        }
      }
      readinessDebugLog(
        '[READINESS_DEBUG] $debugContext probe=A status=${probeA.statusCode ?? 0} visible_total=${rows.length} matching_active_profile=$matching other_profiles=$other distinct_profiles=${profiles.length} newest_date_in_active_profile=${newestActiveDate == null ? 'none' : _readinessDebugDate(newestActiveDate)}',
      );
    }
    });

    // TEMP_READINESS_DEBUG: compare the Directus aggregate with the app query.
    await isolateProbe('B', () async {
    final probeB = await _readinessDebugGet(
      name: 'B',
      path: '/items/scan_results',
      debugContext: debugContext,
      query: {
        'aggregate[count]': '*',
        'filter[scan_id][business_profile][_eq]': profileId,
      },
    );
    if (probeB != null) {
      final aggregateRows = _readinessDebugRows(probeB.data);
      final count = aggregateRows.isEmpty
          ? null
          : int.tryParse(aggregateRows.first['count']?.toString() ?? '');
      readinessDebugLog(
        '[READINESS_DEBUG] $debugContext probe=B status=${probeB.statusCode ?? 0} server_count=${count ?? 'unknown'} app_query_count=${appQueryCount ?? 'unknown'} source=$source',
      );
    }
    });

    // TEMP_READINESS_DEBUG: summarize scan counts by anonymized profile group.
    await isolateProbe('C', () async {
    final probeC = await _readinessDebugGet(
      name: 'C',
      path: '/items/wellness_scans',
      debugContext: debugContext,
      query: const {
        'limit': 100,
        'sort': '-date_created',
        'fields': 'business_profile,date_created',
      },
    );
    if (probeC != null) {
      final rows = _readinessDebugRows(probeC.data);
      final profileCounts = <String, int>{};
      final newestByProfile = <String, DateTime>{};
      for (final row in rows) {
        final rowProfile = _relationId(row['business_profile']);
        if (rowProfile.isEmpty) continue;
        profileCounts[rowProfile] = (profileCounts[rowProfile] ?? 0) + 1;
        final created = DateTime.tryParse(
          row['date_created']?.toString() ?? '',
        );
        final currentNewest = newestByProfile[rowProfile];
        if (created != null &&
            (currentNewest == null || created.isAfter(currentNewest))) {
          newestByProfile[rowProfile] = created;
        }
      }
      final activeCount = profileCounts[profileId] ?? 0;
      readinessDebugLog(
        '[READINESS_DEBUG] $debugContext probe=C status=${probeC.statusCode ?? 0} profile_group=active count=$activeCount newest_date=${newestByProfile[profileId] == null ? 'none' : _readinessDebugDate(newestByProfile[profileId]!)}',
      );
      final otherProfiles = profileCounts.keys
          .where((value) => value != profileId)
          .toList(growable: false);
      final otherGroupsToLog = otherProfiles.take(4).toList(growable: false);
      for (var index = 0; index < otherGroupsToLog.length; index++) {
        final otherProfile = otherGroupsToLog[index];
        final newest = newestByProfile[otherProfile];
        readinessDebugLog(
          '[READINESS_DEBUG] $debugContext probe=C profile_group=other_${index + 1} count=${profileCounts[otherProfile] ?? 0} newest_date=${newest == null ? 'none' : _readinessDebugDate(newest)}',
        );
      }
      readinessDebugLog(
        '[READINESS_DEBUG] $debugContext probe=C total=${rows.length} distinct_profiles=${profileCounts.length} other_profiles=${otherProfiles.length} unlogged_other_profiles=${otherProfiles.length > otherGroupsToLog.length}',
      );
    }
    });

    // TEMP_READINESS_DEBUG: inspect workforce schema keys and role counts.
    Map<String, dynamic> workforceActive = const {};
    List<Map<String, dynamic>> memberRows = const [];
    await isolateProbe('D', () async {
    final probeD = await _readinessDebugGet(
      name: 'D',
      path: '/wellar/workforce',
      debugContext: debugContext,
    );
    if (probeD != null) {
      final root = _readinessDebugMap(probeD.data);
      final data = _readinessDebugMap(root['data']);
      workforceActive = _readinessDebugMap(data['active']);
      final rawRows = data['rows'];
      final allRows = rawRows is List
          ? rawRows.map(_readinessDebugMap).toList(growable: false)
          : const <Map<String, dynamic>>[];
      memberRows = allRows
          .where((row) => row['type']?.toString() == 'member')
          .toList(growable: false);
      final rawWorkspace = workforceActive['workspace'];
      final workspaceType = rawWorkspace == null
          ? 'null'
          : rawWorkspace is String
          ? 'String'
          : rawWorkspace is Map
          ? 'Map'
          : 'other';
      final activeProfile = _relationId(rawWorkspace);
      if (activeProfile.isEmpty) {
              readinessDebugLog(
                '[READINESS_DEBUG] profile_prefix=${_readinessDebugProfilePrefix(profileId)} workspace_role=$workspaceRole workforce_active_workspace_key_missing=true',
              );
      }
      final roleCounts = <String, int>{
        'owner': 0,
        'hr': 0,
        'manager': 0,
        'employee': 0,
        'unknown': 0,
      };
      final seenUsers = <String>{};
      final duplicateUsers = <String>{};
      var emptyUsers = 0;
      for (final row in memberRows) {
        final role = _readinessDebugRole(row['member_role']);
        roleCounts[role] = (roleCounts[role] ?? 0) + 1;
        final user = _relationId(row['user_id']).toLowerCase();
        if (user.isEmpty) {
          emptyUsers++;
        } else if (!seenUsers.add(user)) {
          duplicateUsers.add(user);
        }
      }
      readinessDebugLog(
        '[READINESS_DEBUG] $debugContext probe=D status=${probeD.statusCode ?? 0} top_level_keys=${_readinessDebugKeys(root)} active_keys=${_readinessDebugKeys(workforceActive)} active_workspace_type=$workspaceType first_member_row_keys=${memberRows.isEmpty ? 'none' : _readinessDebugKeys(memberRows.first)} member_roles=${_readinessDebugRoleCounts(roleCounts)} empty_user_id_count=$emptyUsers duplicate_user_id_present=${duplicateUsers.isNotEmpty} active_profile_matches_requested=${activeProfile.isEmpty ? 'unknown' : activeProfile == profileId}',
      );
    }
    });

    // TEMP_READINESS_DEBUG: log only the Directus role name from /users/me.
    await isolateProbe('E', () async {
    final probeE = await _readinessDebugGet(
      name: 'E',
      path: '/users/me',
      debugContext: debugContext,
      query: const {'fields': 'role.name'},
    );
    if (probeE != null) {
      final root = _readinessDebugMap(probeE.data);
      final rawData = root['data'];
      final data = rawData is List && rawData.isNotEmpty
          ? rawData.first
          : rawData;
      final user = _readinessDebugMap(data);
      final role = _readinessDebugMap(user['role']);
      final roleName = role['name']?.toString().trim();
      readinessDebugLog(
        '[READINESS_DEBUG] $debugContext probe=E status=${probeE.statusCode ?? 0} directus_role=${_readinessDebugRoleName(roleName)}',
      );
    }
    });

    // TEMP_READINESS_DEBUG: resolve every raw result against active workforce.
    await isolateProbe('F', () async {
    final scanIds = scanResultRows
        .map((row) => _relationId(row['scan_id']))
        .where((id) => id.isNotEmpty)
        .toSet()
        .toList(growable: false);
    final scanUsers = <String, String>{};
    var identityStatus = 'not_requested';
    if (scanIds.isNotEmpty) {
      final probeFIdentity = await _readinessDebugGet(
        name: 'F_scan_identity',
        path: '/items/wellness_scans',
        debugContext: debugContext,
        query: {
          'limit': scanIds.length,
          'filter[business_profile][_eq]': profileId,
          'filter[id][_in]': scanIds.join(','),
          'fields': 'id,user,business_profile',
        },
      );
      if (probeFIdentity != null) {
        identityStatus = '${probeFIdentity.statusCode ?? 0}';
        for (final row in _readinessDebugRows(probeFIdentity.data)) {
          final scanId = row['id']?.toString().trim() ?? '';
          final userId = _relationId(row['user']);
          if (scanId.isNotEmpty && userId.isNotEmpty) {
            scanUsers[scanId] = userId.toLowerCase();
          }
        }
      } else {
        identityStatus = 'failed';
      }
    }
    final activeWorkspace = _relationId(workforceActive['workspace']);
    final workforceWorkspaceMismatch =
        activeWorkspace.isNotEmpty && activeWorkspace != profileId;
    final workforceUserRoles = <String, String>{};
    if (!workforceWorkspaceMismatch) {
      for (final row in memberRows) {
        final userId = _relationId(row['user_id']).toLowerCase();
        if (userId.isEmpty) continue;
        workforceUserRoles['$profileId::$userId'] =
            _readinessDebugRole(row['member_role']);
      }
    }
    final roleHistogram = <String, int>{
      'owner': 0,
      'hr': 0,
      'manager': 0,
      'employee': 0,
      'unknown': 0,
    };
    var scanUserPresentRows = 0;
    var scanUserAbsentRows = 0;
    for (final row in scanResultRows) {
      final scanId = _relationId(row['scan_id']);
      final userId = scanUsers[scanId];
      final role = userId == null
          ? 'unknown'
          : workforceUserRoles['$profileId::$userId'] ?? 'unknown';
      roleHistogram[role] = (roleHistogram[role] ?? 0) + 1;
      if (userId != null &&
          workforceUserRoles.containsKey('$profileId::$userId')) {
        scanUserPresentRows++;
      } else {
        scanUserAbsentRows++;
      }
    }
    readinessDebugLog(
      '[READINESS_DEBUG] $debugContext probe=F source=$source identity_status=$identityStatus raw_rows=${scanResultRows.length} resolved_roles=${_readinessDebugRoleCounts(roleHistogram)} scan_user_present_rows=$scanUserPresentRows scan_user_absent_rows=$scanUserAbsentRows',
    );
    });
  }

  // TEMP_READINESS_DEBUG
  Future<Response<dynamic>?> _readinessDebugGet({
    required String name,
    required String path,
    required String debugContext,
    Map<String, dynamic>? query,
  }) async {
    try {
      final response = await DirectusClient.instance.client.get(
        path,
        queryParameters: query,
      );
      final status = response.statusCode ?? 0;
      if (status < 200 || status >= 300) {
        _readinessDebugProbeFailed(
          name: name,
          status: status,
          debugContext: debugContext,
          responseData: response.data,
        );
        return null;
      }
      return response;
    } on DioException catch (error) {
      _readinessDebugProbeFailed(
        name: name,
        status: error.response?.statusCode ?? 0,
        debugContext: debugContext,
        responseData: error.response?.data,
      );
      return null;
    } catch (_) {
      _readinessDebugProbeFailed(
        name: name,
        status: 0,
        debugContext: debugContext,
      );
      return null;
    }
  }

  // TEMP_READINESS_DEBUG
  void _readinessDebugProbeFailed({
    required String name,
    required int status,
    required String debugContext,
    dynamic responseData,
  }) {
    final root = _readinessDebugMap(responseData);
    final errors = root['errors'];
    final first = errors is List && errors.isNotEmpty
        ? _readinessDebugMap(errors.first)
        : const <String, dynamic>{};
    final extensions = _readinessDebugMap(first['extensions']);
    final rawCode = extensions['code']?.toString() ?? 'unknown';
    final code = RegExp(r'^[A-Za-z0-9_.-]{1,64}$').hasMatch(rawCode)
        ? rawCode
        : 'unknown';
    readinessDebugLog(
      '[READINESS_DEBUG] $debugContext probe_failed name=$name status=$status directus_code=$code',
    );
  }

  // TEMP_READINESS_DEBUG
  Map<String, dynamic> _readinessDebugMap(dynamic value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) {
      return value.map((key, value) => MapEntry(key.toString(), value));
    }
    return const <String, dynamic>{};
  }

  // TEMP_READINESS_DEBUG
  List<Map<String, dynamic>> _readinessDebugRows(dynamic responseData) {
    final data = _readinessDebugMap(responseData)['data'];
    if (data is! List) return const [];
    return data.map(_readinessDebugMap).toList(growable: false);
  }

  // TEMP_READINESS_DEBUG
  String _readinessDebugKeys(Map<String, dynamic> value) {
    final keys = value.keys.toList()..sort();
    return keys.isEmpty ? 'none' : keys.join(',');
  }

  // TEMP_READINESS_DEBUG
  String _readinessDebugRole(dynamic value) {
    final normalized = value?.toString().trim().toLowerCase() ?? '';
    return const {'owner', 'hr', 'manager', 'employee'}.contains(normalized)
        ? normalized
        : 'unknown';
  }

  // TEMP_READINESS_DEBUG
  String _readinessDebugRoleCounts(Map<String, int> counts) =>
      'owner:${counts['owner'] ?? 0},hr:${counts['hr'] ?? 0},manager:${counts['manager'] ?? 0},employee:${counts['employee'] ?? 0},unknown:${counts['unknown'] ?? 0}';

  // TEMP_READINESS_DEBUG
  String _readinessDebugRoleName(String? value) {
    if (value == null || value.isEmpty) return 'unknown';
    final cleaned = value.replaceAll(RegExp(r'[^A-Za-z0-9 _.-]'), '');
    if (cleaned.isEmpty) return 'unknown';
    final end = cleaned.length > 64 ? 64 : cleaned.length;
    return cleaned.substring(0, end);
  }

  // TEMP_READINESS_DEBUG
  String _readinessDebugDate(DateTime value) {
    final local = value.toLocal();
    return '${local.year.toString().padLeft(4, '0')}-${local.month.toString().padLeft(2, '0')}-${local.day.toString().padLeft(2, '0')}';
  }

  // TEMP_READINESS_DEBUG
  String _readinessDebugProfilePrefix(String profileId) {
    final safe = profileId.replaceAll(RegExp(r'[^A-Za-z0-9]'), '');
    if (safe.isEmpty) return 'none';
    return safe.substring(0, safe.length < 8 ? safe.length : 8);
  }

  // TEMP_READINESS_DEBUG
  String _readinessDebugRejectCounts(Map<String, int> counts) =>
      counts.entries.map((entry) => '${entry.key}:${entry.value}').join(',');

  // TEMP_READINESS_DEBUG
  void _logReadinessDateHistogram({
    required String profileId,
    required String workspaceRole,
    required String source,
    required List<Map<String, dynamic>> rows,
    required String? periodStart,
    required String? periodEnd,
  }) {
    if (!kDebugMode) return;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    var todayCount = 0;
    var last7DaysCount = 0;
    var last30DaysCount = 0;
    var olderCount = 0;
    var invalidDateCount = 0;
    for (final row in rows) {
      final parsed = _parseDate(row['date_created']);
      if (parsed == null) {
        invalidDateCount++;
        continue;
      }
      final local = parsed.toLocal();
      final localDay = DateTime(local.year, local.month, local.day);
      final daysBeforeToday = today.difference(localDay).inDays;
      if (daysBeforeToday == 0) {
        todayCount++;
      } else if (daysBeforeToday >= 1 && daysBeforeToday <= 7) {
        last7DaysCount++;
      } else if (daysBeforeToday >= 8 && daysBeforeToday <= 30) {
        last30DaysCount++;
      } else {
        olderCount++;
      }
    }
    readinessDebugLog(
      '[READINESS_DEBUG] profile_prefix=${_readinessDebugProfilePrefix(profileId)} workspace_role=${_readinessDebugRole(workspaceRole)} source=$source raw_date_histogram raw_count=${rows.length} filtered_count=not_applicable today=$todayCount last_7_days=$last7DaysCount last_30_days=$last30DaysCount older=$olderCount invalid_date=$invalidDateCount period_start=${periodStart ?? 'none'} period_end=${periodEnd ?? 'none'} period_basis=${periodStart == null && periodEnd == null ? 'unbounded' : 'caller_bounds_start_inclusive_end_exclusive'}',
    );
  }

  void _logReadinessRequestFailure({
    required String dioType,
    required int statusCode,
    dynamic responseData,
    String? fallbackMessage,
  }) {
    String? code;
    String? message;
    if (responseData is Map) {
      final errors = responseData['errors'];
      if (errors is List && errors.isNotEmpty && errors.first is Map) {
        final first = errors.first as Map;
        final extensions = first['extensions'];
        code = (extensions is Map ? extensions['code'] : null)?.toString() ??
            first['code']?.toString();
        message = first['message']?.toString();
      }
    }
    message ??= fallbackMessage;
    safeDebugLog(
      '[READINESS_FILTER] request_failed dio_type=${_safeReadinessLogText(dioType)} http_status=$statusCode directus_code=${code == null ? 'none' : _safeReadinessLogText(code)} directus_message=${message == null ? 'none' : _safeReadinessLogText(message)}',
    );
  }

  String _safeReadinessLogText(String value) {
    return value
        .replaceAll(RegExp(r'Bearer\s+\S+', caseSensitive: false), 'Bearer [redacted]')
        .replaceAll(
          RegExp(r'eyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.?[A-Za-z0-9_-]*'),
          '[redacted-token]',
        )
        .replaceAll(
          RegExp(
            r'\b[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}\b',
          ),
          '[redacted-id]',
        )
        .replaceAll(
          RegExp(r'[\w.+-]+@[\w.-]+\.[A-Za-z]{2,}'),
          '[redacted-email]',
        )
        .replaceAll(RegExp(r'\b\d{7,}\b'), '[redacted-id]')
        .replaceAll(RegExp(r'[\r\n\t]+'), ' ')
        .trim();
  }

  String _rawDiagnosticType(dynamic raw) =>
      raw == null ? 'null' : raw.runtimeType.toString();

  String _readinessDiagnosticCategory(dynamic raw, {bool numeric = false}) {
    if (raw == null) return 'null';
    final text = raw.toString().trim();
    if (text.isEmpty) return 'empty';
    if (numeric) {
      final score = num.tryParse(text);
      if (score == null) return raw is String ? 'unknown_string' : 'unknown_type';
      return score < 0 || score > 100 ? 'out_of_range' : 'valid';
    }
    if (_normalizeReadinessKey(text) != null) return 'valid';
    return raw is String ? 'unknown_string' : 'unknown_type';
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
    safeDebugLog(
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
        safeDebugLog(
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
      safeDebugLog(
        '[COMPLIANCE_REQUEST_COUNTS] pending=$pending completed=$completed overdue=$overdue',
      );
    } else {
      safeDebugLog(
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
      safeDebugLog(
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
    safeDebugLog('[OWNER_HOME_LOAD] section=$section duration_ms=$duration');
    if (duration > 2000) {
      safeDebugLog(
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
    safeDebugLog(
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

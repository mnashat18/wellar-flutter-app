import '../utils/safe_debug_log.dart';
import 'package:dio/dio.dart';

import '../models/workspace_department.dart';
import 'directus_client.dart';
import 'member_identity_service.dart';
import 'organization_service.dart';
import 'readiness_result_service.dart';
import 'request_service.dart';
import 'wellar_workforce_service.dart';
import '../state/session.dart';

class HrMemberView {
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
  final bool hasOpenAlert;
  final bool hasOverdueRequest;
  final bool requiresLinking;
  final DateTime? joinedAt;
  final String? lastReadinessScore;
  final bool? todaysScan;
  final String? presenceStatus;

  const HrMemberView({
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

  bool get isHrReadyScopeMember {
    if (!isActive || requiresLinking) return false;
    switch (roleKey) {
      case 'hr':
      case 'manager':
      case 'employee':
        return true;
      default:
        return false;
    }
  }
}

class HrWorkforceDirectoryData {
  final List<HrMemberView> members;
  final List<WorkspaceDepartment> departments;
  final Map<String, dynamic> summary;

  const HrWorkforceDirectoryData({
    required this.members,
    required this.departments,
    this.summary = const {},
  });
}

class HrSnapshot {
  final int workforceTotal;
  final int activeMembers;
  final int pendingRequests;
  final int checksCompletedToday;
  final int missingChecks;
  final int attentionOutcomes;
  final int openAlerts;
  final int departmentsCount;
  final String? workforceUnavailableMessage;

  const HrSnapshot({
    required this.workforceTotal,
    required this.activeMembers,
    required this.pendingRequests,
    required this.checksCompletedToday,
    required this.missingChecks,
    required this.attentionOutcomes,
    required this.openAlerts,
    required this.departmentsCount,
    this.workforceUnavailableMessage,
  });
}

class HrComplianceSummary {
  final int completed;
  final int missing;
  final int attention;
  final int overdue;

  const HrComplianceSummary({
    required this.completed,
    required this.missing,
    required this.attention,
    required this.overdue,
  });
}

class HrOpsService {
  HrOpsService._();

  static final HrOpsService instance = HrOpsService._();

  Dio get _client => DirectusClient.instance.client;
  ActiveWorkspaceContext? _cachedWorkspaceContext;
  Future<ActiveWorkspaceContext?>? _workspaceContextFuture;
  String? _cachedWorkspaceSignature;
  HrWorkforceDirectoryData? _cachedWorkforceBundle;
  Future<HrWorkforceDirectoryData>? _workforceBundleFuture;

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

  Future<List<HrMemberView>> fetchWorkforce({bool forceRefresh = false}) async {
    final data = await fetchWorkforceDirectory(forceRefresh: forceRefresh);
    return data.members;
  }

  Future<HrWorkforceDirectoryData> fetchWorkforceDirectory({
    bool forceRefresh = false,
  }) async {
    final startRevision = OrganizationService.instance.workspaceRevision;
    final startSignature = OrganizationService.instance.workspaceSignature;
    final workspace = await _activeWorkspace(forceRefresh: forceRefresh);
    final profileId = workspace?.businessProfileId.trim() ?? '';
    final membershipId = workspace?.membershipId.trim() ?? '';
    final activeRole = _workspaceRole(workspace);
    final trace = OrganizationService.instance.activeSwitchTrace ?? 'none';
    if (activeRole.isNotEmpty && activeRole != 'hr') {
      safeDebugLog(
        '[ROLE_SERVICE_GUARD] service=HrOpsService expected=hr actual=${activeRole.isEmpty ? "unknown" : activeRole} ignored=true',
      );
      safeDebugLog(
        '[STALE_ROLE_RESULT_IGNORED] service=HrOpsService expected_role=hr actual_role=${activeRole.isEmpty ? "unknown" : activeRole}',
      );
      return const HrWorkforceDirectoryData(members: [], departments: []);
    }
    if (_isWorkspaceStale(startRevision, startSignature)) {
      _logStaleResult();
      return const HrWorkforceDirectoryData(members: [], departments: []);
    }
    if (workspace == null ||
        profileId.isEmpty ||
        !_isActiveBusiness(workspace)) {
      return const HrWorkforceDirectoryData(members: [], departments: []);
    }
    final stopwatch = Stopwatch()..start();
    safeDebugLog(
      '[SCOPED_DATA_REQUEST] feature=workforce operation=fetch_directory method=GET endpoint_or_collection=/items/business_profile_members membership_id=$membershipId business_profile=$profileId department=${workspace.departmentId?.trim() ?? ''} membership_role=$activeRole context_source=${OrganizationService.instance.activeWorkspaceContextSource} workspace_revision=$startRevision filter_summary=business_profile=$profileId;status=active;limit=500 started=true trace=$trace',
    );
    safeDebugLog(
      '[HR_WORKFORCE_CLIENT_STATE] trace=$trace client_instance_id=${DirectusClient.instance.instanceId} dio_instance_id=${DirectusClient.instance.dioInstanceId} membership_id=$membershipId business_profile=$profileId membership_role=$activeRole workspace_revision=$startRevision',
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
      activeRole.isNotEmpty ? activeRole : 'hr',
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
        return const HrWorkforceDirectoryData(members: [], departments: []);
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

  Future<HrWorkforceDirectoryData> _buildWorkforceDirectory(
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
      return HrMemberView(
        memberId: _workforceString(row['member_id']).isNotEmpty
            ? _workforceString(row['member_id'])
            : _workforceString(row['id']),
        userId: userId,
        name: _workforceString(row['display_name']),
        email: _workforceString(row['email']),
        role: _workforceString(row['member_role']),
        status: _workforceString(row['status']),
        departmentName: departmentName.isEmpty ? null : departmentName,
        departmentId: departmentId.isEmpty ? null : departmentId,
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
    return HrWorkforceDirectoryData(
      members: members,
      departments: departments,
      summary: result.summary,
    );
  }

  Future<HrWorkforceDirectoryData> _buildLegacyWorkforceDirectory(
    String profileId,
    String membershipId,
    String role,
  ) async {
    safeDebugLog(
      '[HR] workforce load start business_profile=$profileId membership_id=$membershipId role=$role',
    );
    final results = await Future.wait<dynamic>([
      _fetchWorkforceMembersForProfile(profileId, membershipId, role),
      _fetchDepartmentsForProfile(profileId),
    ]);
    return HrWorkforceDirectoryData(
      members: results[0] as List<HrMemberView>,
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

  Future<List<HrMemberView>> _fetchWorkforceMembersForProfile(
    String profileId,
    String membershipId,
    String role,
  ) async {
    try {
      final memberRows = await MemberIdentityService.instance
          .fetchBusinessProfileMembers(
            screen: 'HrWorkforce',
            businessProfileId: profileId,
            limit: 200,
            sort: '-date_created',
            activeOnly: true,
            role: role,
            membershipId: membershipId,
          );
      final requestRows = await _fetchRequestRows(profileId);
      final alertRows = await _fetchAlertRows(profileId);
      final overdueMemberIds = _extractOverdueMemberIds(requestRows);
      final openAlertUserIds = _extractOpenAlertUserIds(alertRows);

      final scansRes = await _client.get(
        '/items/wellness_scans',
        queryParameters: {
          'limit': 300,
          'sort': '-date_created',
          'fields': 'id,user,status,completed_at,date_created',
          'filter[business_profile][_eq]': profileId,
        },
      );
      final scansData = scansRes.data['data'];
      final scanRows = scansData is List
          ? scansData.whereType<Map<String, dynamic>>().toList()
          : <Map<String, dynamic>>[];
      final scanIds = scanRows
          .map((e) => e['id']?.toString() ?? '')
          .where((e) => e.isNotEmpty)
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

      final list = <HrMemberView>[];
      final now = DateTime.now();
      for (final row in memberRows) {
        final memberId = row['id']?.toString() ?? '';
        final departmentRaw = row['department'];
        final departmentName = MemberIdentityService.instance
            .resolveDepartmentName(departmentRelation: departmentRaw);
        final identity = MemberIdentityService.instance.resolveFromUserRelation(
          row['user'],
          context: 'hr_workforce',
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

        list.add(
          HrMemberView(
            memberId: memberId,
            userId: userId,
            name: identity.name,
            email: identity.email ?? '',
            role: row['member_role']?.toString() ?? '',
            status: row['status']?.toString() ?? '',
            departmentName: departmentName,
            departmentId: MemberIdentityService.instance.resolveDepartmentId(
              departmentRaw,
            ),
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

      list.sort((a, b) {
        if (a.isActive != b.isActive) {
          return a.isActive ? -1 : 1;
        }
        return a.displayName.toLowerCase().compareTo(
          b.displayName.toLowerCase(),
        );
      });
      safeDebugLog('[HR] workforce load success count=${list.length}');
      return list;
    } on DioException catch (e) {
      safeDebugLog(
        '[HR] workforce load fail status=${e.response?.statusCode} body=${e.response?.data}',
      );
      rethrow;
    }
  }

  Future<HrSnapshot> fetchSnapshot({bool forceRefresh = false}) async {
    final startRevision = OrganizationService.instance.workspaceRevision;
    final startSignature = OrganizationService.instance.workspaceSignature;
    final workspace = await _activeWorkspace();
    final profileId = workspace?.businessProfileId.trim() ?? '';
    final membershipId = workspace?.membershipId.trim() ?? '';
    final currentUserId = workspace?.currentUserId.trim() ?? '';
    final activeRole = _workspaceRole(workspace);
    if (activeRole.isNotEmpty && activeRole != 'hr') {
      safeDebugLog(
        '[ROLE_SERVICE_GUARD] service=HrOpsService expected=hr actual=${activeRole.isEmpty ? "unknown" : activeRole} ignored=true',
      );
      safeDebugLog(
        '[STALE_ROLE_RESULT_IGNORED] service=HrOpsService expected_role=hr actual_role=${activeRole.isEmpty ? "unknown" : activeRole}',
      );
      return const HrSnapshot(
        workforceTotal: -1,
        activeMembers: -1,
        pendingRequests: -1,
        checksCompletedToday: -1,
        missingChecks: -1,
        attentionOutcomes: -1,
        openAlerts: -1,
        departmentsCount: -1,
      );
    }
    if (workspace == null ||
        profileId.isEmpty ||
        membershipId.isEmpty ||
        currentUserId.isEmpty) {
      safeDebugLog(
        '[HR] snapshot unavailable workspace=${workspace != null} profile=$profileId membership=$membershipId current_user=${currentUserId.isNotEmpty}',
      );
      return const HrSnapshot(
        workforceTotal: -1,
        activeMembers: -1,
        pendingRequests: -1,
        checksCompletedToday: -1,
        missingChecks: -1,
        attentionOutcomes: -1,
        openAlerts: -1,
        departmentsCount: -1,
      );
    }
    if (_isWorkspaceStale(startRevision, startSignature)) {
      _logStaleResult();
      return const HrSnapshot(
        workforceTotal: -1,
        activeMembers: -1,
        pendingRequests: -1,
        checksCompletedToday: -1,
        missingChecks: -1,
        attentionOutcomes: -1,
        openAlerts: -1,
        departmentsCount: -1,
      );
    }
    final trace = OrganizationService.instance.activeSwitchTrace ?? 'none';
    final stopwatch = Stopwatch()..start();
    safeDebugLog(
      '[SCOPED_DATA_REQUEST] feature=reports operation=hr_snapshot method=GET endpoint_or_collection=/items/scan_results membership_id=${workspace?.membershipId.trim() ?? ''} business_profile=$profileId department=${workspace?.departmentId?.trim() ?? ''} membership_role=${workspace?.memberRole ?? ''} context_source=${OrganizationService.instance.activeWorkspaceContextSource} workspace_revision=$startRevision filter_summary=business_profile=$profileId;scan_results;alerts;scan_requests;departments started=true trace=$trace',
    );
    List<HrMemberView> members = const [];
    Map<String, dynamic> workforceSummary = const {};
    int workforceDepartmentsCount = -1;
    String? workforceUnavailableMessage;
    try {
      final workforce = await fetchWorkforceDirectory(
        forceRefresh: forceRefresh,
      );
      members = workforce.members;
      workforceSummary = workforce.summary;
      workforceDepartmentsCount = workforce.departments.length;
    } catch (error) {
      final status = error is DioException
          ? error.response?.statusCode ?? 0
          : 0;
      safeDebugLog(
        '[HR_SNAPSHOT_SECTION_FAILED] step=workforce http_status=$status error_type=${error.runtimeType}',
      );
      workforceUnavailableMessage =
          'Workforce data is unavailable right now. Other dashboard data is still available.';
    }
    if (_isWorkspaceStale(startRevision, startSignature)) {
      _logStaleResult();
      return const HrSnapshot(
        workforceTotal: -1,
        activeMembers: -1,
        pendingRequests: -1,
        checksCompletedToday: -1,
        missingChecks: -1,
        attentionOutcomes: -1,
        openAlerts: -1,
        departmentsCount: -1,
      );
    }
    final scopedMembers = members.where((m) => m.isHrReadyScopeMember).toList();
    final workforceTotal = workforceUnavailableMessage != null
        ? -1
        : _summaryInt(
            workforceSummary,
            'eligibleMembers',
            fallback: scopedMembers.length,
          );
    final active = workforceUnavailableMessage != null
        ? -1
        : _summaryInt(
            workforceSummary,
            'activeMembers',
            fallback: scopedMembers.length,
          );
    final now = DateTime.now();
    final completedToday = workforceUnavailableMessage != null
        ? -1
        : workforceSummary.containsKey('completedToday')
        ? _summaryInt(workforceSummary, 'completedToday', fallback: 0)
        : scopedMembers.where((m) {
            final d = m.lastCheckAt?.toLocal();
            return d != null &&
                d.year == now.year &&
                d.month == now.month &&
                d.day == now.day;
          }).length;
    final missing = workforceUnavailableMessage != null
        ? -1
        : workforceSummary.containsKey('missingScans')
        ? _summaryInt(workforceSummary, 'missingScans', fallback: 0)
        : scopedMembers.where((m) {
            final d = m.lastCheckAt?.toLocal();
            return d == null ||
                d.year != now.year ||
                d.month != now.month ||
                d.day != now.day;
          }).length;
    final attention = workforceUnavailableMessage != null
        ? -1
        : workforceSummary.containsKey('needsAttention')
        ? _summaryInt(workforceSummary, 'needsAttention', fallback: 0)
        : scopedMembers.where((m) => m.needsAttention).length;

    int openAlerts = -1;
    int pendingRequests = -1;
    int departmentsCount = workforceUnavailableMessage == null
        ? _summaryInt(
            workforceSummary,
            'departments',
            fallback: workforceDepartmentsCount,
          )
        : -1;
    try {
      if (profileId.isNotEmpty) {
        final alerts = await _client.get(
          '/items/alerts',
          queryParameters: {
            'limit': 100,
            'fields': 'id,status,business_profile',
            'filter[business_profile][_eq]': profileId,
          },
        );
        final data = alerts.data['data'];
        if (data is List) {
          openAlerts = data.whereType<Map<String, dynamic>>().where((e) {
            final s = e['status']?.toString().toLowerCase() ?? '';
            return s != 'resolved' && s != 'closed';
          }).length;
        }
      }
    } catch (_) {
      openAlerts = -1;
    }
    try {
      if (profileId.isNotEmpty) {
        pendingRequests = (await RequestService.instance.fetchHrRequests(
          statusFilter: 'pending',
        )).length;
      }
    } catch (_) {
      pendingRequests = -1;
    }
    try {
      if (departmentsCount < 0 && profileId.isNotEmpty) {
        final dep = await _client.get(
          '/items/departments',
          queryParameters: {
            'limit': 300,
            'fields': 'id',
            'filter[business_profile][_eq]': profileId,
          },
        );
        final data = dep.data['data'];
        if (data is List) departmentsCount = data.length;
      }
    } catch (_) {
      departmentsCount = -1;
    }
    if (_isWorkspaceStale(startRevision, startSignature)) {
      _logStaleResult();
      return const HrSnapshot(
        workforceTotal: -1,
        activeMembers: -1,
        pendingRequests: -1,
        checksCompletedToday: -1,
        missingChecks: -1,
        attentionOutcomes: -1,
        openAlerts: -1,
        departmentsCount: -1,
      );
    }
    stopwatch.stop();
    safeDebugLog(
      '[SCOPED_DATA_RESPONSE] feature=reports operation=hr_snapshot http_status=200 result_count=$workforceTotal duration_ms=${stopwatch.elapsedMilliseconds} membership_id=${workspace?.membershipId.trim() ?? ''} business_profile=$profileId workspace_revision_before=$startRevision workspace_revision_after=${OrganizationService.instance.workspaceRevision} context_unchanged=${OrganizationService.instance.workspaceRevision == startRevision && OrganizationService.instance.workspaceSignature == startSignature} returned_business_profile_ids=[$profileId] returned_membership_ids=[${workspace?.membershipId.trim() ?? ''}] empty_result=${workforceTotal == 0} trace=$trace',
    );

    return HrSnapshot(
      workforceTotal: workforceTotal,
      activeMembers: active,
      pendingRequests: pendingRequests,
      checksCompletedToday: completedToday,
      missingChecks: missing,
      attentionOutcomes: attention,
      openAlerts: openAlerts,
      departmentsCount: departmentsCount,
      workforceUnavailableMessage: workforceUnavailableMessage,
    );
  }

  Future<HrComplianceSummary> fetchCompliance() async {
    final startRevision = OrganizationService.instance.workspaceRevision;
    final startSignature = OrganizationService.instance.workspaceSignature;
    final workspace = await _activeWorkspace();
    final profileId = workspace?.businessProfileId.trim() ?? '';
    final activeRole = _workspaceRole(workspace);
    final trace = OrganizationService.instance.activeSwitchTrace ?? 'none';
    if (activeRole.isNotEmpty && activeRole != 'hr') {
      safeDebugLog(
        '[ROLE_SERVICE_GUARD] service=HrOpsService expected=hr actual=${activeRole.isEmpty ? "unknown" : activeRole} ignored=true',
      );
      safeDebugLog(
        '[STALE_ROLE_RESULT_IGNORED] service=HrOpsService expected_role=hr actual_role=${activeRole.isEmpty ? "unknown" : activeRole}',
      );
      return const HrComplianceSummary(
        completed: -1,
        missing: -1,
        attention: -1,
        overdue: -1,
      );
    }
    if (_isWorkspaceStale(startRevision, startSignature)) {
      _logStaleResult();
      return const HrComplianceSummary(
        completed: -1,
        missing: -1,
        attention: -1,
        overdue: -1,
      );
    }
    safeDebugLog(
      '[SCOPED_DATA_REQUEST] feature=compliance operation=hr_compliance method=GET endpoint_or_collection=/items/scan_requests membership_id=${workspace?.membershipId.trim() ?? ''} business_profile=$profileId department=${workspace?.departmentId?.trim() ?? ''} membership_role=${workspace?.memberRole ?? ''} context_source=${OrganizationService.instance.activeWorkspaceContextSource} workspace_revision=$startRevision filter_summary=business_profile=$profileId;status=active;scan_requests started=true trace=$trace',
    );
    final workforce = await fetchWorkforceDirectory();
    final members = workforce.members;
    if (_isWorkspaceStale(startRevision, startSignature)) {
      _logStaleResult();
      return const HrComplianceSummary(
        completed: -1,
        missing: -1,
        attention: -1,
        overdue: -1,
      );
    }
    final now = DateTime.now();
    final scopedMembers = members
        .where((member) => member.isHrReadyScopeMember)
        .toList();
    final completed = workforce.summary.containsKey('completedToday')
        ? _summaryInt(workforce.summary, 'completedToday', fallback: 0)
        : scopedMembers.where((member) {
            final lastCheck = member.lastCheckAt?.toLocal();
            return lastCheck != null &&
                lastCheck.year == now.year &&
                lastCheck.month == now.month &&
                lastCheck.day == now.day;
          }).length;
    final activeMembers = _summaryInt(
      workforce.summary,
      'activeMembers',
      fallback: scopedMembers.length,
    );
    final missing = _summaryInt(
      workforce.summary,
      'missingScans',
      fallback: activeMembers > completed ? activeMembers - completed : 0,
    );
    final attention = _summaryInt(
      workforce.summary,
      'needsAttention',
      fallback: scopedMembers.where((member) => member.needsAttention).length,
    );

    int overdue = 0;
    if (profileId.isNotEmpty) {
      try {
        final req = await _client.get(
          '/items/scan_requests',
          queryParameters: {
            'limit': 300,
            'fields': 'id,status,due_at,business_profile',
            'filter[business_profile][_eq]': profileId,
          },
        );
        final data = req.data['data'];
        if (data is List) {
          overdue = data.whereType<Map<String, dynamic>>().where((row) {
            final status = row['status']?.toString().toLowerCase() ?? '';
            if (status == 'completed' || status == 'cancelled') return false;
            final due = _parseDate(row['due_at']);
            return due != null && due.isBefore(DateTime.now());
          }).length;
        }
      } catch (_) {}
    }
    if (_isWorkspaceStale(startRevision, startSignature)) {
      _logStaleResult();
      return const HrComplianceSummary(
        completed: -1,
        missing: -1,
        attention: -1,
        overdue: -1,
      );
    }
    safeDebugLog(
      '[SCOPED_DATA_RESPONSE] feature=compliance operation=hr_compliance http_status=200 result_count=$completed duration_ms=0 membership_id=${workspace?.membershipId.trim() ?? ''} business_profile=$profileId workspace_revision_before=$startRevision workspace_revision_after=${OrganizationService.instance.workspaceRevision} context_unchanged=${OrganizationService.instance.workspaceRevision == startRevision && OrganizationService.instance.workspaceSignature == startSignature} returned_business_profile_ids=[$profileId] returned_membership_ids=[${workspace?.membershipId.trim() ?? ''}] empty_result=${completed == 0 && missing == 0 && attention == 0 && overdue == 0} trace=$trace',
    );

    return HrComplianceSummary(
      completed: completed,
      missing: missing,
      attention: attention,
      overdue: overdue,
    );
  }

  DateTime? _parseDate(dynamic value) {
    if (value == null) return null;
    return DateTime.tryParse(value.toString());
  }

  Future<List<Map<String, dynamic>>> _fetchRequestRows(String profileId) async {
    try {
      final response = await _client.get(
        '/items/scan_requests',
        queryParameters: {
          'limit': 400,
          'fields': 'id,status,due_at,target_member,target_member.id',
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
    final now = DateTime.now().toUtc();
    final overdue = <String>{};
    for (final row in requestRows) {
      final dueAt = _parseDate(row['due_at']);
      if (dueAt == null || !dueAt.isBefore(now)) continue;
      final status = row['status']?.toString().trim().toLowerCase() ?? '';
      if (status.isEmpty || status == 'completed' || status == 'cancelled') {
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

  String _relationId(dynamic value) {
    if (value == null) return '';
    if (value is Map) {
      return value['id']?.toString().trim() ?? '';
    }
    return value.toString().trim();
  }

  bool _isSameLocalDay(DateTime? value, DateTime now) {
    if (value == null) return false;
    final local = value.toLocal();
    return local.year == now.year &&
        local.month == now.month &&
        local.day == now.day;
  }

  bool _isCompletedScanRow(Map<String, dynamic> row) {
    final status = row['status']?.toString().trim().toLowerCase() ?? '';
    if (status == 'completed') return true;
    if (status == 'complete' || status == 'done') return true;
    return row['completed_at'] != null;
  }

  bool _isWorkspaceStale(int startRevision, String startSignature) {
    return OrganizationService.instance.workspaceRevision != startRevision ||
        OrganizationService.instance.workspaceSignature != startSignature;
  }

  void _logStaleResult() {
    safeDebugLog(
      '[WORKSPACE_GUARD] stale_result_ignored=true service=HrOpsService',
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

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import '../models/business_profile.dart';
import '../models/business_profile_member.dart';
import '../models/organization.dart';
import '../state/session.dart';
import 'directus_client.dart';
import 'hr_ops_service.dart';
import 'owner_ops_service.dart';

class OrganizationServiceException implements Exception {
  final String message;
  const OrganizationServiceException(this.message);

  @override
  String toString() => message;
}

class ActiveWorkspaceContext {
  final String currentUserId;
  final String? currentUserEmail;
  final String? currentUserFirstName;
  final String? currentUserLastName;
  final String? directusRoleId;
  final String? directusRoleName;
  final String membershipUserId;
  final String businessProfileId;
  final String businessProfileName;
  final String? businessProfileStatus;
  final String? businessPlanCode;
  final String? businessBillingStatus;
  final String membershipId;
  final String memberRole;
  final String membershipRole;
  final String finalEffectiveRole;
  final String membershipStatus;
  final String? departmentId;
  final String? departmentName;
  final String scopeLabel;

  const ActiveWorkspaceContext({
    required this.currentUserId,
    required this.currentUserEmail,
    required this.currentUserFirstName,
    required this.currentUserLastName,
    required this.directusRoleId,
    required this.directusRoleName,
    required this.membershipUserId,
    required this.businessProfileId,
    required this.businessProfileName,
    required this.businessProfileStatus,
    required this.businessPlanCode,
    required this.businessBillingStatus,
    required this.membershipId,
    required this.memberRole,
    required this.membershipRole,
    required this.finalEffectiveRole,
    required this.membershipStatus,
    required this.departmentId,
    required this.departmentName,
    required this.scopeLabel,
  });
}

enum WorkspaceResolveStatus {
  ok,
  unauthenticated,
  forbidden,
  noMembership,
  error,
}

class WorkspaceResolveResult {
  final WorkspaceResolveStatus status;
  final ActiveWorkspaceContext? context;
  final String? message;

  const WorkspaceResolveResult({
    required this.status,
    this.context,
    this.message,
  });
}

class AuthenticatedCurrentUserProfile {
  final String id;
  final String email;
  final String? firstName;
  final String? lastName;
  final String? roleId;
  final String? roleName;

  const AuthenticatedCurrentUserProfile({
    required this.id,
    required this.email,
    required this.firstName,
    required this.lastName,
    required this.roleId,
    required this.roleName,
  });
}

class WorkspaceMembershipChoice {
  final String membershipId;
  final String businessProfileId;
  final String companyName;
  final String memberRole;
  final String? departmentId;
  final String? departmentName;
  final String? businessProfileStatus;
  final String? businessPlanCode;
  final String? businessBillingStatus;
  final String status;
  final bool isCurrent;

  const WorkspaceMembershipChoice({
    required this.membershipId,
    required this.businessProfileId,
    required this.companyName,
    required this.memberRole,
    required this.departmentId,
    required this.departmentName,
    required this.businessProfileStatus,
    required this.businessPlanCode,
    required this.businessBillingStatus,
    required this.status,
    required this.isCurrent,
  });
}

class CanonicalWorkspaceContextSnapshot {
  final String currentUserId;
  final String currentUserEmail;
  final String? currentUserFirstName;
  final String? currentUserLastName;
  final String? directusRoleId;
  final String? directusRoleName;
  final String activeMembershipId;
  final List<WorkspaceMembershipChoice> memberships;
  final ActiveWorkspaceContext? activeContext;

  const CanonicalWorkspaceContextSnapshot({
    required this.currentUserId,
    required this.currentUserEmail,
    required this.currentUserFirstName,
    required this.currentUserLastName,
    required this.directusRoleId,
    required this.directusRoleName,
    required this.activeMembershipId,
    required this.memberships,
    required this.activeContext,
  });

  WorkspaceMembershipChoice? get activeMembership {
    final activeId = activeMembershipId.trim();
    if (activeId.isEmpty) return null;
    for (final membership in memberships) {
      if (membership.membershipId == activeId) return membership;
    }
    return null;
  }
}

enum CanonicalWorkspaceContextStatus {
  ok,
  unauthenticated,
  forbidden,
  error,
}

class CanonicalWorkspaceContextResult {
  final CanonicalWorkspaceContextStatus status;
  final CanonicalWorkspaceContextSnapshot? snapshot;
  final String? message;

  const CanonicalWorkspaceContextResult({
    required this.status,
    this.snapshot,
    this.message,
  });
}

class _WorkspaceContextWorkspace {
  final String id;
  final String companyName;
  final bool isActive;
  final String? planCode;
  final String? billingStatus;

  const _WorkspaceContextWorkspace({
    required this.id,
    required this.companyName,
    required this.isActive,
    required this.planCode,
    required this.billingStatus,
  });
}

class _WorkspaceContextDepartment {
  final String id;
  final String name;

  const _WorkspaceContextDepartment({
    required this.id,
    required this.name,
  });
}

class _WorkspaceContextMembership {
  final String id;
  final String status;
  final String memberRole;

  const _WorkspaceContextMembership({
    required this.id,
    required this.status,
    required this.memberRole,
  });
}

class _PostSwitchProbeResult {
  final int statusCode;
  final int memberCount;

  const _PostSwitchProbeResult({
    required this.statusCode,
    required this.memberCount,
  });
}

class OrganizationService {
  OrganizationService._();

  static final OrganizationService instance = OrganizationService._();

  Dio get _client => DirectusClient.instance.client;
  int _workspaceRevision = 0;
  BusinessProfile? _cachedBusinessProfile;
  String? _cachedBusinessProfileUserId;
  String? _lastProfileResolveError;
  String? _workspaceSessionSyncSignature;
  Future<ActiveWorkspaceContext>? _workspaceSessionSyncInFlight;
  String? _activeSwitchTrace;

  String? get lastProfileResolveError => _lastProfileResolveError;
  ActiveWorkspaceContext? _cachedWorkspaceContext;
  String _activeWorkspaceContextSource = 'none';
  String? _lastResolvedRole;
  String? _lastResolvedUserId;
  int get workspaceRevision => _workspaceRevision;
  String get activeWorkspaceContextSource => _activeWorkspaceContextSource;
  String? get activeSwitchTrace => _activeSwitchTrace;
  String get workspaceSignature {
    final context = _cachedWorkspaceContext;
    if (context == null) return '';
    final departmentId = context.departmentId?.trim() ?? '';
    return [
      context.currentUserId.trim(),
      context.membershipId.trim(),
      context.businessProfileId.trim(),
      context.finalEffectiveRole.trim().toLowerCase(),
      departmentId,
    ].join(':');
  }

  void clearActiveWorkspaceContext() {
    final previousSignature = workspaceSignature;
    if (_cachedWorkspaceContext != null || previousSignature.isNotEmpty) {
      _workspaceRevision++;
      debugPrint('[WORKSPACE_GUARD] revision_incremented=true');
      debugPrint(
        '[WORKSPACE_GUARD] signature_changed=${previousSignature.isNotEmpty}',
      );
    }
    _cachedWorkspaceContext = null;
    _activeWorkspaceContextSource = 'none';
    _lastResolvedRole = null;
    _lastResolvedUserId = null;
    clearWorkspaceSessionSyncState();
  }

  void clearProfileCache() {
    _cachedBusinessProfile = null;
    _cachedBusinessProfileUserId = null;
    _lastProfileResolveError = null;
    _cachedWorkspaceContext = null;
    _activeWorkspaceContextSource = 'none';
    clearWorkspaceSessionSyncState();
  }

  void clearWorkspaceSessionSyncState() {
    _workspaceSessionSyncSignature = null;
    _workspaceSessionSyncInFlight = null;
  }

  void _setActiveSwitchTrace(String? trace) {
    _activeSwitchTrace = trace;
  }

  String _nextSwitchTrace() => 'ws_${DateTime.now().microsecondsSinceEpoch}';

  void _wsDebug(String message) {
    if (kDebugMode) {
      debugPrint(message);
    }
  }

  void applyActiveWorkspaceContext(
    ActiveWorkspaceContext context, {
    String source = 'service_apply',
  }) {
    final previousSignature = workspaceSignature;
    final revisionBefore = _workspaceRevision;
    final nextSignature = _signatureFromContext(context);
    if (previousSignature != nextSignature) {
      _workspaceRevision++;
      debugPrint('[WORKSPACE_GUARD] revision_incremented=true');
      debugPrint('[WORKSPACE_GUARD] signature_changed=true');
    }
    final previousBusinessProfileId =
        _cachedWorkspaceContext?.businessProfileId.trim();
    final nextBusinessProfileId = context.businessProfileId.trim();
    final activeProfileChanged =
        previousBusinessProfileId != nextBusinessProfileId;

    _cachedWorkspaceContext = context;
    _activeWorkspaceContextSource = source;
    _lastResolvedRole = context.memberRole;
    _lastResolvedUserId = context.currentUserId;
    Session.instance.roleName = context.finalEffectiveRole;
    _cachedBusinessProfile = null;
    _cachedBusinessProfileUserId = null;
    _lastProfileResolveError = null;

    OwnerOpsService.instance.clearOrganizationScopedCaches();
    HrOpsService.instance.clearOrganizationScopedCaches();

    debugPrint(
      '[ORG_SWITCH_CACHE] owner_ops_cleared=true hr_ops_cleared=true '
      'active_profile_changed=$activeProfileChanged',
    );
    debugPrint(
      '[ACTIVE_CONTEXT_AFTER_SWITCH] business_profile=${context.businessProfileId}',
    );
    debugPrint(
      '[ACTIVE_CONTEXT_AFTER_SWITCH] membership_id=${context.membershipId}',
    );
    debugPrint(
      '[ACTIVE_CONTEXT_AFTER_SWITCH] member_role=${context.memberRole}',
    );
    debugPrint('[ACTIVE_CONTEXT_AFTER_SWITCH] source=$source');
    debugPrint(
      '[ACTIVE_CONTEXT_AFTER_SWITCH] services_role=${context.finalEffectiveRole}',
    );
    debugPrint(
      '[ACTIVE_CONTEXT_AFTER_SWITCH] directus_role=${context.directusRoleName ?? ''}',
    );
    _wsDebug(
      '[WS_CONTEXT_APPLY] trace=${_activeSwitchTrace ?? 'none'} applied=true membership_id=${context.membershipId} business_profile=${context.businessProfileId} department=${context.departmentId ?? ''} membership_role=${context.memberRole} directus_role=${context.directusRoleName ?? ''} source=$source workspace_revision_before=$revisionBefore workspace_revision_after=$_workspaceRevision',
    );
  }

  String _signatureFromContext(ActiveWorkspaceContext context) {
    final departmentId = context.departmentId?.trim() ?? '';
    return [
      context.currentUserId.trim(),
      context.membershipId.trim(),
      context.businessProfileId.trim(),
      context.finalEffectiveRole.trim().toLowerCase(),
      departmentId,
    ].join(':');
  }

  Future<ActiveWorkspaceContext?> fetchActiveWorkspaceContext({
    bool forceRefresh = false,
  }) async {
    if (!forceRefresh) {
      final cached = _cachedWorkspaceContext;
      final sessionUserId = Session.instance.userId?.trim() ?? '';
      if (cached != null &&
          sessionUserId.isNotEmpty &&
          cached.currentUserId == sessionUserId) {
        debugPrint(
          '[WorkspaceResolver] using cached workspace context user=$sessionUserId business_profile=${cached.businessProfileId}',
        );
        return cached;
      }
    }
    final result = await resolveCanonicalActiveWorkspace(
      forceRefresh: forceRefresh,
    );
    return result.context;
  }

  Future<AuthenticatedCurrentUserProfile?> fetchAuthenticatedCurrentUserProfile() async {
    final me = await _loadCurrentUser();
    if (me == null) return null;
    return AuthenticatedCurrentUserProfile(
      id: me.id,
      email: me.email,
      firstName: me.firstName,
      lastName: me.lastName,
      roleId: me.roleId,
      roleName: me.role,
    );
  }

  Future<CanonicalWorkspaceContextResult> fetchCanonicalWorkspaceContext({
    bool forceRefresh = false,
  }) async {
    final canonicalStopwatch = Stopwatch()..start();
    _wsDebug(
      '[WS_CONTEXT_NETWORK] trace=${_activeSwitchTrace ?? 'none'} force_refresh=$forceRefresh network_requested=true status= pending duration_ms=0 root_keys=[] active_keys=[] membership_keys=[]',
    );
    try {
      final me = await _loadCurrentUser();
      if (me == null) {
        canonicalStopwatch.stop();
        return const CanonicalWorkspaceContextResult(
          status: CanonicalWorkspaceContextStatus.unauthenticated,
        );
      }
      final response = await _client.get('/wellar/workspaces/context');
      canonicalStopwatch.stop();
      final root = _asMap(response.data);
      final map = _asMap(root?['data']);
      if (map == null) {
        _wsDebug(
          '[WS_HTTP] trace=${_activeSwitchTrace ?? 'none'} stage=canonical_context method=GET endpoint=/wellar/workspaces/context started=true status=${response.statusCode ?? 0} duration_ms=${canonicalStopwatch.elapsedMilliseconds} network_error_type=none network_error_status=0',
        );
        _wsDebug(
          '[WS_CONTEXT_NETWORK] trace=${_activeSwitchTrace ?? 'none'} force_refresh=$forceRefresh network_requested=true status=${response.statusCode ?? 0} duration_ms=${canonicalStopwatch.elapsedMilliseconds} root_keys=${root?.keys.toList() ?? const []} active_keys=[] membership_keys=[]',
        );
        return const CanonicalWorkspaceContextResult(
          status: CanonicalWorkspaceContextStatus.error,
          message: 'Organization context response was invalid.',
        );
      }
      final activeMap = _asMap(map['active']);
      final membershipsList = _asArray(map['memberships']);
      final firstMembershipKeys = membershipsList.isNotEmpty
          ? _asMap(membershipsList.first)?.keys.toList() ?? const []
          : const [];
      _wsDebug(
        '[WS_HTTP] trace=${_activeSwitchTrace ?? 'none'} stage=canonical_context method=GET endpoint=/wellar/workspaces/context started=true status=${response.statusCode ?? 0} duration_ms=${canonicalStopwatch.elapsedMilliseconds} network_error_type=none network_error_status=0',
      );
      _wsDebug(
        '[WS_CONTEXT_NETWORK] trace=${_activeSwitchTrace ?? 'none'} force_refresh=$forceRefresh network_requested=true status=${response.statusCode ?? 0} duration_ms=${canonicalStopwatch.elapsedMilliseconds} root_keys=${root?.keys.toList() ?? const []} active_keys=${activeMap?.keys.toList() ?? const []} membership_keys=$firstMembershipKeys',
      );
      final snapshot = _buildCanonicalWorkspaceSnapshot(map, currentUser: me);
      return CanonicalWorkspaceContextResult(
        status: CanonicalWorkspaceContextStatus.ok,
        snapshot: snapshot,
      );
    } on DioException catch (e) {
      canonicalStopwatch.stop();
      final status = e.response?.statusCode ?? 0;
      _wsDebug(
        '[WS_HTTP] trace=${_activeSwitchTrace ?? 'none'} stage=canonical_context method=GET endpoint=/wellar/workspaces/context started=true status=$status duration_ms=${canonicalStopwatch.elapsedMilliseconds} network_error_type=${e.type} network_error_status=$status',
      );
      if (status == 401) {
        return const CanonicalWorkspaceContextResult(
          status: CanonicalWorkspaceContextStatus.unauthenticated,
          message: 'Session expired. Please login.',
        );
      }
      if (status == 403) {
        return const CanonicalWorkspaceContextResult(
          status: CanonicalWorkspaceContextStatus.forbidden,
          message:
              'Workspace context is unavailable because this account cannot read organization data.',
        );
      }
      return CanonicalWorkspaceContextResult(
        status: CanonicalWorkspaceContextStatus.error,
        message: _extractMessage(e),
      );
    } catch (e) {
      return CanonicalWorkspaceContextResult(
        status: CanonicalWorkspaceContextStatus.error,
        message: e.toString(),
      );
    }
  }

  Future<WorkspaceResolveResult> resolveCanonicalActiveWorkspace({
    bool forceRefresh = false,
  }) async {
    final canonical = await fetchCanonicalWorkspaceContext(
      forceRefresh: forceRefresh,
    );
    switch (canonical.status) {
      case CanonicalWorkspaceContextStatus.unauthenticated:
        clearActiveWorkspaceContext();
        return WorkspaceResolveResult(
          status: WorkspaceResolveStatus.unauthenticated,
          message: canonical.message ?? 'Session expired. Please login.',
        );
      case CanonicalWorkspaceContextStatus.forbidden:
        clearActiveWorkspaceContext();
        return WorkspaceResolveResult(
          status: WorkspaceResolveStatus.forbidden,
          message:
              canonical.message ??
              'Workspace context is unavailable because this account cannot read organization data.',
        );
      case CanonicalWorkspaceContextStatus.error:
        return WorkspaceResolveResult(
          status: WorkspaceResolveStatus.error,
          message:
              canonical.message ??
              'We could not verify workspace access right now.',
        );
      case CanonicalWorkspaceContextStatus.ok:
        break;
    }

    final snapshot = canonical.snapshot;
    final context = snapshot?.activeContext;
    if (context == null ||
        context.currentUserId.trim().isEmpty ||
        context.membershipUserId.trim() != context.currentUserId.trim() ||
        context.membershipId.trim().isEmpty ||
        context.businessProfileId.trim().isEmpty ||
        (context.membershipStatus != 'active' &&
            context.membershipStatus != 'accepted')) {
      clearActiveWorkspaceContext();
      return const WorkspaceResolveResult(
        status: WorkspaceResolveStatus.noMembership,
      );
    }

    applyActiveWorkspaceContext(context, source: 'canonical_context');
    return WorkspaceResolveResult(
      status: WorkspaceResolveStatus.ok,
      context: context,
    );
  }

  Future<ActiveWorkspaceContext> syncWorkspaceSession({
    required String membershipId,
    String trigger = 'workspace_sync',
    WorkspaceMembershipChoice? expectedMembership,
  }) async {
    final normalizedMembershipId = membershipId.trim();
    if (normalizedMembershipId.isEmpty) {
      throw const OrganizationServiceException(
        'Workspace membership is required.',
      );
    }

    final currentUserId = Session.instance.userId?.trim() ?? '';
    final signature = '$currentUserId|$normalizedMembershipId';
    final switchTrace = _nextSwitchTrace();
    _setActiveSwitchTrace(switchTrace);
    final currentContext = _cachedWorkspaceContext;
    final targetBusinessProfileId =
        expectedMembership?.businessProfileId.trim() ?? '';
    final targetDepartmentId = expectedMembership?.departmentId?.trim() ?? '';
    final targetMembershipRole = _normalizeRole(expectedMembership?.memberRole);
    _wsDebug(
      '[WS_SWITCH_START] trace=$switchTrace from_membership=${currentContext?.membershipId.trim() ?? ''} from_business_profile=${currentContext?.businessProfileId.trim() ?? ''} from_department=${currentContext?.departmentId?.trim() ?? ''} from_membership_role=${currentContext?.memberRole.trim() ?? ''} target_membership=$normalizedMembershipId target_business_profile=$targetBusinessProfileId target_department=$targetDepartmentId target_membership_role=$targetMembershipRole',
    );

    while (true) {
      final cached = _cachedWorkspaceContext;
      if (_workspaceSessionSyncSignature == signature &&
          cached != null &&
          cached.membershipId == normalizedMembershipId &&
          cached.currentUserId == currentUserId) {
        return cached;
      }

      final inFlight = _workspaceSessionSyncInFlight;
      if (inFlight == null) break;
      if (_workspaceSessionSyncSignature == signature) {
        return inFlight;
      }

      try {
        await inFlight;
      } catch (_) {
        // Ignore the incompatible request and retry our own switch.
      }
    }

    final future = _syncWorkspaceSessionInternal(
      membershipId: normalizedMembershipId,
      trigger: trigger,
      expectedMembership: expectedMembership,
      trace: switchTrace,
    );
    _workspaceSessionSyncSignature = signature;
    _workspaceSessionSyncInFlight = future;
    try {
      return await future;
    } finally {
      if (identical(_workspaceSessionSyncInFlight, future)) {
        _workspaceSessionSyncInFlight = null;
      }
    }
  }

  Future<ActiveWorkspaceContext> _syncWorkspaceSessionInternal({
    required String membershipId,
    required String trigger,
    WorkspaceMembershipChoice? expectedMembership,
    required String trace,
  }) async {
    final response = await _postWorkspaceSwitchRequest(
      membershipId: membershipId,
      trace: trace,
    );

    final switchResponseRoot = _asMap(response.data);
    final switchResponseData = _asMap(switchResponseRoot?['data']) ?? switchResponseRoot;
    final switchResponseWorkspace = _asMap(switchResponseData?['workspace']) ??
        _asMap(switchResponseData?['business_profile']) ??
        _asMap(switchResponseData?['businessProfile']);
    final switchResponseMembership = _asMap(switchResponseData?['membership']) ??
        _asMap(switchResponseData?['active_membership']) ??
        _asMap(switchResponseData?['business_profile_member']) ??
        _asMap(switchResponseData?['member']);
    final switchResponseDepartment =
        _asMap(switchResponseData?['department']) ??
        _asMap(switchResponseData?['active_department']);
    _wsDebug(
      '[WS_SWITCH_RESPONSE] trace=$trace membership_id=${_stringValue(switchResponseMembership?['id']) ?? _stringValue(switchResponseData?['membership']) ?? ''} business_profile=${_stringValue(switchResponseWorkspace?['id']) ?? _stringValue(switchResponseData?['workspace']) ?? _stringValue(switchResponseData?['business_profile']) ?? ''} department=${_stringValue(switchResponseDepartment?['id']) ?? _stringValue(switchResponseData?['department']) ?? ''} membership_role=${_stringValue(switchResponseData?['memberRole']) ?? _stringValue(switchResponseData?['member_role']) ?? ''} response_shape_valid=${switchResponseRoot != null && switchResponseData != null} root_keys=${switchResponseRoot?.keys.toList() ?? const []}',
    );
    final switchAccessTokenPresent =
        _stringValue(switchResponseRoot?['access_token']) != null ||
        _stringValue(switchResponseData?['access_token']) != null;
    final switchRefreshTokenPresent =
        _stringValue(switchResponseRoot?['refresh_token']) != null ||
        _stringValue(switchResponseData?['refresh_token']) != null;
    final preSwitchAccessToken = Session.instance.accessToken;
    final preSwitchRefreshToken = Session.instance.refreshToken;
    final switchCredentialsInstalled =
        await _installPostSwitchSessionCredentials(response.data);
    debugPrint('[WORKSPACE_SWITCH] web_parity_payload=true');
    debugPrint(
      '[WORKSPACE_SWITCH] tokens_rotated=$switchCredentialsInstalled',
    );
    debugPrint(
      '[WORKSPACE_SWITCH_SESSION] switch_access_token_present=$switchAccessTokenPresent switch_refresh_token_present=$switchRefreshTokenPresent fresh_session_attempted=true',
    );
    final postSwitchAccessToken = Session.instance.accessToken;
    final postSwitchRefreshToken = Session.instance.refreshToken;
    bool tokenChanged(String? before, String? after) {
      return (before?.trim() ?? '') != (after?.trim() ?? '');
    }
    final normalizedPostSwitchAccessToken =
        postSwitchAccessToken?.trim() ?? '';
    final liveAuthHeaderValue =
        DirectusClient.instance.client.options.headers['Authorization']
            ?.toString()
            .trim();
    final authHeaderMatchesSession =
        normalizedPostSwitchAccessToken.isNotEmpty &&
        liveAuthHeaderValue == 'Bearer $normalizedPostSwitchAccessToken';
    debugPrint(
      '[WORKSPACE_SWITCH_SESSION] fresh_session_installed=$switchCredentialsInstalled access_token_present_after=${postSwitchAccessToken?.trim().isNotEmpty == true} access_token_replaced=${tokenChanged(preSwitchAccessToken, postSwitchAccessToken)} refresh_token_present_after=${postSwitchRefreshToken?.trim().isNotEmpty == true} refresh_token_replaced=${tokenChanged(preSwitchRefreshToken, postSwitchRefreshToken)} auth_header_matches_session=$authHeaderMatchesSession',
    );
    _wsDebug(
      '[WS_HTTP] trace=$trace stage=session_issue method=POST endpoint=/auth/google/mobile-exchange/session started=true status=${switchCredentialsInstalled ? 200 : 0} duration_ms=0 network_error_type=${switchCredentialsInstalled ? 'none' : 'session_issue_failed'} network_error_status=${switchCredentialsInstalled ? 0 : 0}',
    );
    _wsDebug(
      '[WS_TOKEN_REFRESH] trace=$trace success=$switchCredentialsInstalled access_token_present_before=${preSwitchAccessToken?.trim().isNotEmpty == true} access_token_present_after=${postSwitchAccessToken?.trim().isNotEmpty == true} access_token_replaced=${tokenChanged(preSwitchAccessToken, postSwitchAccessToken)} refresh_token_present_before=${preSwitchRefreshToken?.trim().isNotEmpty == true} refresh_token_present_after=${postSwitchRefreshToken?.trim().isNotEmpty == true} refresh_token_replaced=${tokenChanged(preSwitchRefreshToken, postSwitchRefreshToken)} auth_header_matches_session=$authHeaderMatchesSession',
    );
    if (!switchCredentialsInstalled) {
      clearActiveWorkspaceContext();
      debugPrint('[WORKSPACE_SWITCH] target_verified=false');
      debugPrint('[WORKSPACE_SWITCH] context_applied=false');
      throw const OrganizationServiceException(
        'We could not verify your organization switch right now.',
      );
    }

    var currentUser = await _loadCurrentUser(
      includeActiveWorkspaceFields: true,
    );
    debugPrint(
      '[WORKSPACE_SWITCH] user_active_fields_reloaded=${currentUser != null}',
    );

    final expectedBusinessProfileId =
        expectedMembership?.businessProfileId.trim() ?? '';
    final expectedDepartmentId =
        expectedMembership?.departmentId?.trim() ?? '';
    final expectedRole = _normalizeRole(expectedMembership?.memberRole);

    ({
      bool directusRoleAvailable,
      String directusRoleMatch,
      bool activeBusinessProfileAvailable,
      String activeBusinessProfileMatch,
      bool activeDepartmentAvailable,
      String activeDepartmentMatch,
      bool activeMemberRoleAvailable,
      String activeMemberRoleMatch,
      bool mismatch,
    }) evaluateUserFields(_CurrentUser? user) {
      final directusRoleName = _normalizeRole(user?.role);
      final directusRoleId = user?.roleId?.trim() ?? '';
      final directusRoleAvailable =
          directusRoleName.isNotEmpty || directusRoleId.isNotEmpty;
      final directusRoleMatch = directusRoleName.isNotEmpty
          ? (directusRoleName == expectedRole ? 'true' : 'false')
          : 'not_available';
      final activeBusinessProfileValue =
          user?.activeBusinessProfileId?.trim() ?? '';
      final activeBusinessProfileAvailable =
          activeBusinessProfileValue.isNotEmpty;
      final activeBusinessProfileMatch = activeBusinessProfileAvailable
          ? (_verifyActiveFieldMatch(
                  user?.activeBusinessProfileId,
                  expectedBusinessProfileId,
                )
              ? 'true'
              : 'false')
          : 'not_available';
      final activeDepartmentValue = user?.activeDepartmentId?.trim() ?? '';
      final activeDepartmentAvailable = expectedDepartmentId.isEmpty
          ? true
          : activeDepartmentValue.isNotEmpty;
      final activeDepartmentMatch = expectedDepartmentId.isEmpty
          ? 'true'
          : (activeDepartmentAvailable
              ? (_verifyActiveFieldMatch(
                      user?.activeDepartmentId,
                      expectedDepartmentId,
                    )
                  ? 'true'
                  : 'false')
              : 'not_available');
      final activeMemberRoleValue =
          (user?.activeMemberRole ?? user?.activeRole)?.trim() ?? '';
      final activeMemberRoleAvailable = activeMemberRoleValue.isNotEmpty;
      final activeMemberRoleMatch = activeMemberRoleAvailable
          ? (_verifyActiveRoleMatch(user, expectedRole) ? 'true' : 'false')
          : 'not_available';
      final mismatch = directusRoleMatch == 'false' ||
          activeBusinessProfileMatch == 'false' ||
          activeDepartmentMatch == 'false' ||
          activeMemberRoleMatch == 'false';
      return (
        directusRoleAvailable: directusRoleAvailable,
        directusRoleMatch: directusRoleMatch,
        activeBusinessProfileAvailable: activeBusinessProfileAvailable,
        activeBusinessProfileMatch: activeBusinessProfileMatch,
        activeDepartmentAvailable: activeDepartmentAvailable,
        activeDepartmentMatch: activeDepartmentMatch,
        activeMemberRoleAvailable: activeMemberRoleAvailable,
        activeMemberRoleMatch: activeMemberRoleMatch,
        mismatch: mismatch,
      );
    }

    var userState = evaluateUserFields(currentUser);
    debugPrint(
      '[WORKSPACE_SWITCH_USER_VERIFY] directus_role_available=${userState.directusRoleAvailable} directus_role_match=${userState.directusRoleMatch} active_business_profile_available=${userState.activeBusinessProfileAvailable} active_business_profile_match=${userState.activeBusinessProfileMatch} active_department_available=${userState.activeDepartmentAvailable} active_department_match=${userState.activeDepartmentMatch} active_member_role_available=${userState.activeMemberRoleAvailable} active_member_role_match=${userState.activeMemberRoleMatch}',
    );
    final responseCurrentUser = currentUser;
    final switchResponseSnapshot = responseCurrentUser == null
        ? null
        : _extractCanonicalWorkspaceSnapshotFromSwitchResponse(
            response.data,
            currentUser: responseCurrentUser,
          );
    final switchResponseContext = _verifiedCanonicalContext(
      switchResponseSnapshot,
      expectedMembershipId: membershipId,
      expectedBusinessProfileId: '',
      expectedDepartmentId: '',
      expectedEffectiveRole: '',
    );
    final canonicalResult = await fetchCanonicalWorkspaceContext(
      forceRefresh: true,
    );
    final canonicalContext = _verifiedCanonicalContext(
      canonicalResult.snapshot,
      expectedMembershipId: membershipId,
      expectedBusinessProfileId: '',
      expectedDepartmentId: '',
      expectedEffectiveRole: '',
    );

    final selectedMembershipId =
        switchResponseContext?.membershipId.trim() ?? membershipId.trim();
    final selectedBusinessProfileId =
        switchResponseContext?.businessProfileId.trim() ??
        expectedBusinessProfileId.trim();
    final switchDepartmentId =
        switchResponseContext?.departmentId?.trim() ?? '';
    final selectedDepartmentId =
        switchDepartmentId.isNotEmpty ? switchDepartmentId : expectedDepartmentId;
    final selectedRole = _normalizeRole(
      switchResponseContext?.membershipRole ??
          switchResponseContext?.finalEffectiveRole ??
          expectedRole,
    );

    final canonicalMembershipId =
        canonicalContext?.membershipId.trim() ?? '';
    final canonicalBusinessProfileId =
        canonicalContext?.businessProfileId.trim() ?? '';
    final canonicalDepartmentId =
        canonicalContext?.departmentId?.trim() ?? '';
    final canonicalRole = _normalizeRole(canonicalContext?.finalEffectiveRole);
    final canonicalMembershipMatch = canonicalMembershipId.isNotEmpty &&
        canonicalMembershipId == selectedMembershipId;
    final canonicalBusinessProfileMatch =
        canonicalBusinessProfileId.isNotEmpty &&
        canonicalBusinessProfileId == selectedBusinessProfileId;
    final canonicalRoleMatch = canonicalRole == selectedRole;
    final canonicalDepartmentMatch =
        canonicalDepartmentId == selectedDepartmentId;
    final switchResponseMembershipMatch =
        switchResponseContext?.membershipId.trim() == selectedMembershipId;
    final switchResponseBusinessProfileMatch =
        switchResponseContext?.businessProfileId.trim() ==
            selectedBusinessProfileId;
    final switchResponseRoleMatch =
        _normalizeRole(switchResponseContext?.membershipRole) == selectedRole;
    final switchResponseDepartmentMatch =
        switchResponseContext?.departmentId?.trim() == selectedDepartmentId;
    var canonicalContextVerified = canonicalMembershipMatch &&
        canonicalBusinessProfileMatch &&
        canonicalRoleMatch &&
        canonicalDepartmentMatch;

    _wsDebug(
      '[WS_VERIFY] trace=$trace membership_match=${selectedMembershipId.isNotEmpty && selectedMembershipId == membershipId.trim()} business_profile_match=${selectedBusinessProfileId.isNotEmpty && selectedBusinessProfileId == expectedBusinessProfileId} department_match=${selectedDepartmentId == expectedDepartmentId} membership_role_match=${selectedRole == expectedRole} directus_role_available=${userState.directusRoleAvailable} directus_role_match=${userState.directusRoleMatch} explicit_user_field_mismatch=${userState.mismatch} canonical_context_verified=$canonicalContextVerified',
    );

    debugPrint(
      '[WORKSPACE_SWITCH_VERIFY] expected_membership_id=$selectedMembershipId',
    );
    debugPrint('[WORKSPACE_SWITCH_VERIFY] expected_role=$selectedRole');
    debugPrint(
      '[WORKSPACE_SWITCH_VERIFY] canonical_membership_id=${canonicalMembershipId.isEmpty ? 'missing' : canonicalMembershipId}',
    );
    debugPrint(
      '[WORKSPACE_SWITCH_VERIFY] canonical_role=${canonicalMembershipId.isEmpty ? 'missing' : canonicalRole}',
    );
    debugPrint(
      '[WORKSPACE_SWITCH_VERIFY] canonical_membership_match=$canonicalMembershipMatch',
    );
    debugPrint(
      '[WORKSPACE_SWITCH_VERIFY] canonical_role_match=$canonicalRoleMatch',
    );
    debugPrint(
      '[WORKSPACE_SWITCH_VERIFY] switch_response_membership_match=$switchResponseMembershipMatch',
    );
    debugPrint(
      '[WORKSPACE_SWITCH_VERIFY] canonical_business_profile_match=$canonicalBusinessProfileMatch',
    );
    debugPrint(
      '[WORKSPACE_SWITCH_VERIFY] canonical_department_match=$canonicalDepartmentMatch',
    );
    debugPrint(
      '[WORKSPACE_SWITCH_VERIFY] switch_response_business_profile_match=$switchResponseBusinessProfileMatch',
    );
    debugPrint(
      '[WORKSPACE_SWITCH_VERIFY] switch_response_role_match=$switchResponseRoleMatch',
    );
    debugPrint(
      '[WORKSPACE_SWITCH_VERIFY] switch_response_department_match=$switchResponseDepartmentMatch',
    );
    debugPrint(
      '[WORKSPACE_SWITCH] switch_response_context_verified=${switchResponseContext != null}',
    );

    ActiveWorkspaceContext? verifiedContext;
    String finalVerifiedContextSource = 'none';
    if (canonicalContextVerified) {
      verifiedContext = canonicalContext;
      finalVerifiedContextSource = 'canonical_context';
    }

    debugPrint(
      '[WORKSPACE_SWITCH] final_verified_context_source=$finalVerifiedContextSource',
    );
    var probeResult = verifiedContext == null
        ? const _PostSwitchProbeResult(statusCode: 0, memberCount: 0)
        : await _probePostSwitchBusinessProfileMembers(
            businessProfileId: verifiedContext.businessProfileId,
            selectedMembershipId: selectedMembershipId,
          );
    var selectedMembershipVisible = probeResult.memberCount > 0;
    var membershipScopeVerified =
        probeResult.statusCode >= 200 &&
        probeResult.statusCode < 300 &&
        selectedMembershipVisible;

    var retryReason = '';
    if (!canonicalContextVerified) {
      retryReason = 'canonical_context_mismatch';
    }

    if (retryReason.isNotEmpty) {
      debugPrint(
        '[WORKSPACE_SWITCH_SESSION_RETRY] reason=$retryReason attempt=2',
      );
      final retrySucceeded = await _installPostSwitchSessionCredentials(
        response.data,
      );
      debugPrint(
        '[WORKSPACE_SWITCH_SESSION] fresh_session_reissued_retry=$retrySucceeded',
      );
      if (!retrySucceeded) {
        clearActiveWorkspaceContext();
        debugPrint('[WORKSPACE_SWITCH] target_verified=false');
        debugPrint('[WORKSPACE_SWITCH] context_applied=false');
        throw const OrganizationServiceException(
          'We could not verify your organization switch right now.',
        );
      }

      currentUser = await _loadCurrentUser(
        includeActiveWorkspaceFields: true,
      );
      debugPrint(
        '[WORKSPACE_SWITCH] user_active_fields_reloaded=${currentUser != null}',
      );
      userState = evaluateUserFields(currentUser);
      debugPrint(
        '[WORKSPACE_SWITCH_USER_VERIFY] directus_role_available=${userState.directusRoleAvailable} directus_role_match=${userState.directusRoleMatch} active_business_profile_available=${userState.activeBusinessProfileAvailable} active_business_profile_match=${userState.activeBusinessProfileMatch} active_department_available=${userState.activeDepartmentAvailable} active_department_match=${userState.activeDepartmentMatch} active_member_role_available=${userState.activeMemberRoleAvailable} active_member_role_match=${userState.activeMemberRoleMatch}',
      );
      final retryResponseCurrentUser = currentUser;
      final retrySwitchResponseSnapshot = retryResponseCurrentUser == null
          ? null
          : _extractCanonicalWorkspaceSnapshotFromSwitchResponse(
              response.data,
              currentUser: retryResponseCurrentUser,
            );
      final retrySwitchResponseContext = _verifiedCanonicalContext(
        retrySwitchResponseSnapshot,
        expectedMembershipId: membershipId,
        expectedBusinessProfileId: '',
        expectedDepartmentId: '',
        expectedEffectiveRole: '',
      );
      final retryCanonicalResult = await fetchCanonicalWorkspaceContext(
        forceRefresh: true,
      );
      final retryCanonicalContext = _verifiedCanonicalContext(
        retryCanonicalResult.snapshot,
        expectedMembershipId: membershipId,
        expectedBusinessProfileId: '',
        expectedDepartmentId: '',
        expectedEffectiveRole: '',
      );

      final retrySelectedMembershipId =
          retrySwitchResponseContext?.membershipId.trim() ?? membershipId.trim();
      final retrySelectedBusinessProfileId =
          retrySwitchResponseContext?.businessProfileId.trim() ??
          expectedBusinessProfileId.trim();
      final retrySwitchDepartmentId =
          retrySwitchResponseContext?.departmentId?.trim() ?? '';
      final retrySelectedDepartmentId = retrySwitchDepartmentId.isNotEmpty
          ? retrySwitchDepartmentId
          : expectedDepartmentId;
      final retrySelectedRole = _normalizeRole(
        retrySwitchResponseContext?.membershipRole ??
            retrySwitchResponseContext?.finalEffectiveRole ??
            expectedRole,
      );

      final retryCanonicalMembershipId =
          retryCanonicalContext?.membershipId.trim() ?? '';
      final retryCanonicalBusinessProfileId =
          retryCanonicalContext?.businessProfileId.trim() ?? '';
      final retryCanonicalDepartmentId =
          retryCanonicalContext?.departmentId?.trim() ?? '';
      final retryCanonicalRole =
          _normalizeRole(retryCanonicalContext?.finalEffectiveRole);
      final retryCanonicalMembershipMatch =
          retryCanonicalMembershipId.isNotEmpty &&
          retryCanonicalMembershipId == retrySelectedMembershipId;
      final retryCanonicalBusinessProfileMatch =
          retryCanonicalBusinessProfileId.isNotEmpty &&
          retryCanonicalBusinessProfileId == retrySelectedBusinessProfileId;
      final retryCanonicalRoleMatch = retryCanonicalRole == retrySelectedRole;
      final retryCanonicalDepartmentMatch =
          retryCanonicalDepartmentId == retrySelectedDepartmentId;
      canonicalContextVerified = retryCanonicalMembershipMatch &&
          retryCanonicalBusinessProfileMatch &&
          retryCanonicalRoleMatch &&
          retryCanonicalDepartmentMatch;

      _wsDebug(
        '[WS_VERIFY] trace=$trace membership_match=${retrySelectedMembershipId.isNotEmpty && retrySelectedMembershipId == membershipId.trim()} business_profile_match=${retrySelectedBusinessProfileId.isNotEmpty && retrySelectedBusinessProfileId == expectedBusinessProfileId} department_match=${retrySelectedDepartmentId == expectedDepartmentId} membership_role_match=${retrySelectedRole == expectedRole} directus_role_available=${userState.directusRoleAvailable} directus_role_match=${userState.directusRoleMatch} explicit_user_field_mismatch=${userState.mismatch} canonical_context_verified=$canonicalContextVerified',
      );

      final retrySwitchResponseMembershipMatch =
          retrySwitchResponseContext?.membershipId.trim() ==
              retrySelectedMembershipId;
      final retrySwitchResponseBusinessProfileMatch =
          retrySwitchResponseContext?.businessProfileId.trim() ==
              retrySelectedBusinessProfileId;
      final retrySwitchResponseRoleMatch =
          _normalizeRole(retrySwitchResponseContext?.membershipRole) ==
              retrySelectedRole;
      final retrySwitchResponseDepartmentMatch =
          retrySwitchResponseContext?.departmentId?.trim() ==
              retrySelectedDepartmentId;

      if (retryCanonicalMembershipMatch &&
          retryCanonicalBusinessProfileMatch &&
          retryCanonicalRoleMatch &&
          retryCanonicalDepartmentMatch) {
        verifiedContext = retryCanonicalContext;
        finalVerifiedContextSource = 'canonical_context';
      }

      final retryVerifiedBusinessProfileId =
          verifiedContext?.businessProfileId.trim() ?? '';
      final retryProbeBusinessProfileId =
          retryVerifiedBusinessProfileId.isNotEmpty
              ? retryVerifiedBusinessProfileId
              : retrySelectedBusinessProfileId;
      probeResult = await _probePostSwitchBusinessProfileMembers(
        businessProfileId: retryProbeBusinessProfileId,
        selectedMembershipId: retrySelectedMembershipId,
      );
      selectedMembershipVisible = probeResult.memberCount > 0;
      membershipScopeVerified =
          probeResult.statusCode >= 200 &&
          probeResult.statusCode < 300 &&
          selectedMembershipVisible;

      if (!canonicalContextVerified || verifiedContext == null) {
        clearActiveWorkspaceContext();
        debugPrint('[WORKSPACE_SWITCH] target_verified=false');
        debugPrint('[WORKSPACE_SWITCH] context_applied=false');
        throw const OrganizationServiceException(
          'We could not verify your organization switch right now.',
        );
      }
    }

    final accessSessionInstalled =
        normalizedPostSwitchAccessToken.isNotEmpty && authHeaderMatchesSession;
    final directusRoleVerified =
        userState.directusRoleAvailable && userState.directusRoleMatch == 'true';
    final userFieldsVerified = !userState.mismatch;
    final authReady = accessSessionInstalled &&
        canonicalContextVerified &&
        verifiedContext != null &&
        directusRoleVerified &&
        userFieldsVerified;
    debugPrint(
      '[WORKSPACE_SWITCH_AUTH_READY] membership_id=$selectedMembershipId role=$selectedRole access_session_installed=$accessSessionInstalled directus_role_verified=$directusRoleVerified user_fields_verified=$userFieldsVerified canonical_context_verified=$canonicalContextVerified membership_scope_verified=$membershipScopeVerified ready=$authReady',
    );

    if (!authReady) {
      if (!directusRoleVerified) {
        _wsDebug(
          '[WS_SWITCH_RESULT] trace=$trace success=false failure_stage=post_switch_session_verification failure_code=DIRECTUS_ROLE_NOT_SWITCHED membership_id=$selectedMembershipId business_profile=$selectedBusinessProfileId membership_role=$selectedRole directus_role=${userState.directusRoleMatch} canonical_verified=$canonicalContextVerified membership_visible=$selectedMembershipVisible membership_probe_warning=${selectedMembershipVisible ? 'none' : 'selected_membership_not_visible'} context_applied=false duration_ms=0',
        );
      } else {
        _wsDebug(
          '[WS_SWITCH_RESULT] trace=$trace success=false failure_stage=post_switch_session_verification failure_code=POST_SWITCH_SESSION_NOT_VERIFIED membership_id=$selectedMembershipId business_profile=$selectedBusinessProfileId membership_role=$selectedRole directus_role=${userState.directusRoleMatch} canonical_verified=$canonicalContextVerified membership_visible=$selectedMembershipVisible membership_probe_warning=${selectedMembershipVisible ? 'none' : 'selected_membership_not_visible'} context_applied=false duration_ms=0',
        );
      }
      clearActiveWorkspaceContext();
      debugPrint('[WORKSPACE_SWITCH] target_verified=false');
      debugPrint('[WORKSPACE_SWITCH] context_applied=false');
      throw const OrganizationServiceException(
        'We could not verify your organization switch right now.',
      );
    }

    final verifiedWorkspaceContext = verifiedContext;
    if (verifiedWorkspaceContext == null) {
      clearActiveWorkspaceContext();
      debugPrint('[WORKSPACE_SWITCH] target_verified=false');
      debugPrint('[WORKSPACE_SWITCH] context_applied=false');
      throw const OrganizationServiceException(
        'We could not verify your organization switch right now.',
      );
    }

    debugPrint(
      '[WORKSPACE_SWITCH] trace=$trace final_role=${verifiedWorkspaceContext.memberRole}',
    );
    debugPrint('[WORKSPACE_SWITCH] trace=$trace target_verified=true');
    debugPrint('[WORKSPACE_SWITCH] trace=$trace context_applied=true');
    applyActiveWorkspaceContext(
      verifiedWorkspaceContext,
      source: finalVerifiedContextSource,
    );
    DirectusClient.instance.syncAuthorizationHeaderFromSession();
    debugPrint('[WORKSPACE_SWITCH_PROBE] trace=$trace diagnostic_only=true');
    debugPrint(
      '[WORKSPACE_SWITCH_PROBE] trace=$trace business_profile=${verifiedWorkspaceContext.businessProfileId}',
    );
    debugPrint('[WORKSPACE_SWITCH_PROBE] trace=$trace status=${probeResult.statusCode}');
    debugPrint(
      '[WORKSPACE_SWITCH_PROBE] trace=$trace selected_membership_visible=$selectedMembershipVisible',
    );
    debugPrint('[WORKSPACE_SWITCH_PROBE] trace=$trace member_count=${probeResult.memberCount}');
    debugPrint('[WORKSPACE_SWITCH] trace=$trace expected_membership_id=$selectedMembershipId');
    debugPrint(
      '[WORKSPACE_SWITCH] trace=$trace final_business_profile=${verifiedWorkspaceContext.businessProfileId}',
    );
    debugPrint(
      '[WORKSPACE_SWITCH] trace=$trace membership_probe_warning=${selectedMembershipVisible ? 'none' : 'selected_membership_not_visible'}',
    );
    debugPrint(
      '[WORKSPACE_SWITCH] trace=$trace trigger=$trigger membership_id=$membershipId',
    );
    _wsDebug(
      '[WS_SWITCH_RESULT] trace=$trace success=true failure_stage=none failure_code=none membership_id=${verifiedWorkspaceContext.membershipId} business_profile=${verifiedWorkspaceContext.businessProfileId} membership_role=${verifiedWorkspaceContext.memberRole} directus_role=${verifiedWorkspaceContext.directusRoleName ?? ''} canonical_verified=$canonicalContextVerified membership_visible=$selectedMembershipVisible membership_probe_warning=${selectedMembershipVisible ? 'none' : 'selected_membership_not_visible'} context_applied=true duration_ms=0',
    );
    return verifiedWorkspaceContext;
  }

  Future<WorkspaceResolveResult> resolveActiveWorkspace({
    bool forceRefresh = false,
  }) async {
    if (forceRefresh) {
      _cachedWorkspaceContext = null;
    }
    final me = await _loadCurrentUser();
    if (me == null) {
      return const WorkspaceResolveResult(
        status: WorkspaceResolveStatus.unauthenticated,
      );
    }
    final userId = me.id;
    final userEmail = me.email;
    if (_cachedWorkspaceContext != null &&
        _cachedWorkspaceContext!.currentUserId != userId) {
      debugPrint(
        '[WorkspaceResolver] cached context user mismatch -> clearing cache old=${_cachedWorkspaceContext!.currentUserId} new=$userId',
      );
      _cachedWorkspaceContext = null;
    }
    debugPrint('[AUTH] currentUserId=$userId');
    debugPrint('[AUTH] currentUserEmail=$userEmail');

    final query = <String, dynamic>{
      'limit': 50,
      'sort': '-date_created',
      'fields':
          'id,member_role,status,date_created,department,department.id,department.name,'
              'business_profile,business_profile.id,business_profile.company_name,business_profile.is_active,'
              'business_profile.plan_code,business_profile.billing_status,'
              'user,user.id,user.email,user.first_name,user.last_name',
      'filter[_and][0][user][_eq]': userId,
      'filter[status][_eq]': 'active',
    };
    debugPrint(
      '[WORKSPACE] membership query URL=${DirectusClient.instance.client.options.baseUrl}/items/business_profile_members',
    );
    debugPrint('[WORKSPACE] membership query params=$query');
    final qs = query.entries
        .map((e) => '${Uri.encodeQueryComponent(e.key)}=${Uri.encodeQueryComponent(e.value.toString())}')
        .join('&');
    debugPrint('[WORKSPACE] membership query full_url=${DirectusClient.instance.client.options.baseUrl}/items/business_profile_members?$qs');
    try {
      final response = await _client.get(
        '/items/business_profile_members',
        queryParameters: query,
      );
      debugPrint('[WORKSPACE] response status=${response.statusCode}');
      debugPrint('[WORKSPACE] response body=${response.data}');
      final data = response.data['data'];
      final rows = data is List
          ? data.whereType<Map<String, dynamic>>().toList()
          : const <Map<String, dynamic>>[];
      debugPrint('[WORKSPACE] raw membership count=${rows.length}');

      final validRows = rows.where((row) {
        final status = row['status']?.toString().trim().toLowerCase() ?? '';
        if (status != 'active') return false;
        final membershipUser = row['user'];
        final membershipUserId = membershipUser is Map
            ? membershipUser['id']?.toString().trim() ?? ''
            : membershipUser?.toString().trim() ?? '';
        if (membershipUserId != userId) return false;
        final bp = row['business_profile'];
        if (bp is Map && bp.containsKey('is_active')) {
          final active = bp['is_active'];
          if (active == false || active?.toString().toLowerCase() == 'false') {
            return false;
          }
        }
        return true;
      }).toList();
      debugPrint(
        '[WorkspaceResolver] membership ids and user ids=${validRows.map((e) => '${e['id']}:${e['user'] is Map ? e['user']['id'] : e['user']}').join(',')}',
      );
      for (final row in validRows) {
        final userRaw = row['user'];
        final normalizedUserId = userRaw is Map
            ? userRaw['id']?.toString().trim() ?? ''
            : userRaw?.toString().trim() ?? '';
        final bp = row['business_profile'];
        final bpId = bp is Map ? bp['id']?.toString() ?? '' : bp?.toString() ?? '';
        final bpName = bp is Map
            ? (bp['company_name']?.toString() ?? '')
            : '';
        final dept = row['department'];
        final deptId = dept is Map ? dept['id']?.toString() ?? '' : dept?.toString() ?? '';
        final deptName = dept is Map ? dept['name']?.toString() ?? '' : '';
        debugPrint(
          '[WorkspaceResolver] membership item id=${row['id']} status=${row['status']} role=${row['member_role']} user_raw=$userRaw normalized_user_id=$normalizedUserId business_profile_id=$bpId business_profile_name=$bpName department_id=$deptId department_name=$deptName',
        );
      }
      debugPrint(
        '[WorkspaceResolver] fetched memberships=${validRows.map((e) => '{id:${e['id']},user_id:${e['user'] is Map ? e['user']['id'] : e['user']},user_email:${e['user'] is Map ? e['user']['email'] : '-'},role:${e['member_role']},status:${e['status']}}').join(' | ')}',
      );
      if (validRows.isEmpty) {
        clearActiveWorkspaceContext();
        return const WorkspaceResolveResult(
          status: WorkspaceResolveStatus.noMembership,
        );
      }
      Map<String, dynamic> selected = validRows.first;
      final cached = _cachedWorkspaceContext;
      if (cached != null &&
          cached.currentUserId == userId &&
          cached.businessProfileId.isNotEmpty) {
        final matched = validRows.where((row) {
          final bp = row['business_profile'];
          final bpId = bp is Map
              ? bp['id']?.toString().trim() ?? ''
              : bp?.toString().trim() ?? '';
          return bpId == cached.businessProfileId;
        }).toList();
        if (matched.isNotEmpty) {
          selected = matched.first;
          debugPrint(
            '[WorkspaceResolver] selected cached workspace membership for same user business_profile=${cached.businessProfileId}',
          );
        } else {
          debugPrint(
            '[WorkspaceResolver] cached workspace not found in fresh memberships. selecting first valid membership.',
          );
        }
      }

      final business = selected['business_profile'];
      final businessId = business is Map
          ? business['id']?.toString().trim() ?? ''
          : selected['business_profile']?.toString().trim() ?? '';
      if (businessId.isEmpty) {
        clearActiveWorkspaceContext();
        return const WorkspaceResolveResult(
          status: WorkspaceResolveStatus.noMembership,
        );
      }
      final businessName = business is Map
          ? (business['company_name']?.toString().trim().isNotEmpty == true
                ? business['company_name'].toString().trim()
                : 'Workspace')
          : 'Workspace';
      final businessStatus = business is Map
          ? business['is_active']?.toString().trim()
          : null;
      final businessPlanCode = business is Map
          ? business['plan_code']?.toString().trim()
          : null;
      final businessBillingStatus = business is Map
          ? business['billing_status']?.toString().trim()
          : null;

      final department = selected['department'];
      final departmentId = department is Map
          ? department['id']?.toString()
          : department?.toString();
      final departmentName = department is Map ? department['name']?.toString() : null;
      final membershipUser = selected['user'];
      final membershipUserId = membershipUser is Map
          ? membershipUser['id']?.toString().trim() ?? ''
          : membershipUser?.toString().trim() ?? '';
      final membershipRole = _normalizeMembershipRole(
        selected['member_role']?.toString(),
      );
      if (membershipRole == null) {
        clearActiveWorkspaceContext();
        return WorkspaceResolveResult(
          status: WorkspaceResolveStatus.error,
          message: 'Selected workspace membership role is unavailable.',
        );
      }
      final directusRole = _normalizeRole(me.role);
      final finalEffectiveRole = membershipRole;
      final status = selected['status']?.toString().trim().toLowerCase() ?? 'unknown';
      final scope = departmentName?.trim().isNotEmpty == true
          ? '${finalEffectiveRole.toUpperCase()} - ${departmentName!.trim()}'
          : finalEffectiveRole.toUpperCase();

        final context = ActiveWorkspaceContext(
          currentUserId: userId,
          currentUserEmail: Session.instance.userEmail,
          currentUserFirstName: me.firstName,
          currentUserLastName: me.lastName,
          directusRoleId: me.roleId,
          directusRoleName: me.role,
          membershipUserId: membershipUserId,
          businessProfileId: businessId,
          businessProfileName: businessName,
          businessProfileStatus: businessStatus,
          businessPlanCode: businessPlanCode,
          businessBillingStatus: businessBillingStatus,
          membershipId: selected['id']?.toString() ?? '',
          memberRole: membershipRole,
          membershipRole: membershipRole,
          finalEffectiveRole: finalEffectiveRole,
          membershipStatus: status,
          departmentId: departmentId?.trim().isEmpty == true
              ? null
              : departmentId,
          departmentName: departmentName?.trim().isEmpty == true
              ? null
              : departmentName,
          scopeLabel: scope,
        );
        applyActiveWorkspaceContext(context, source: 'legacy_resolver');
        debugPrint(
          '[WORKSPACE] selected membership id=${context.membershipId}',
        );
        debugPrint('[WORKSPACE] selected member_role=${context.membershipRole}');
        debugPrint(
          '[WORKSPACE] selected business_profile=${context.businessProfileId}',
        );
        debugPrint(
          '[WORKSPACE] selected department=${context.departmentId ?? "-"}',
        );
        debugPrint('[ROLE_DEBUG] usersMe.id=${context.currentUserId}');
        debugPrint('[ROLE_DEBUG] usersMe.email=${context.currentUserEmail}');
        debugPrint('[ROLE_DEBUG] directusRoleName=${context.directusRoleName}');
        debugPrint('[ROLE_DEBUG] membership.id=${context.membershipId}');
        debugPrint('[ROLE_DEBUG] membership.member_role=${context.membershipRole}');
        debugPrint('[ROLE_DEBUG] membership.status=${context.membershipStatus}');
        debugPrint('[ROLE_DEBUG] membership.business_profile=${context.businessProfileId}');
        debugPrint('[ROLE_DEBUG] finalEffectiveRole=${context.finalEffectiveRole}');
        if (directusRole != context.membershipRole) {
          debugPrint(
            '[ROLE_CONFLICT] directusRole=$directusRole membershipRole=${context.membershipRole} finalEffectiveRole=${context.finalEffectiveRole}',
          );
        }
        debugPrint(
          'ROLE_CONTEXT_FINAL: currentUserId=${context.currentUserId} currentUserEmail=${context.currentUserEmail} directusRole=${context.directusRoleName} membershipRole=${context.membershipRole} effectiveRole=${context.finalEffectiveRole} memberId=${context.membershipId} businessProfileId=${context.businessProfileId} businessProfileName=${context.businessProfileName} departmentId=${context.departmentId} departmentName=${context.departmentName} shell=${context.finalEffectiveRole}',
        );
        return WorkspaceResolveResult(
          status: WorkspaceResolveStatus.ok,
          context: context,
        );
    } on DioException catch (e) {
      final status = e.response?.statusCode;
      debugPrint('[WORKSPACE] response status=$status');
      debugPrint('[WORKSPACE] response body=${e.response?.data}');
      debugPrint(
        '[API_ERROR] method=GET endpoint=/items/business_profile_members collection=business_profile_members status=$status body=${e.response?.data}',
      );
      if (status == 401) {
        clearActiveWorkspaceContext();
        return const WorkspaceResolveResult(
          status: WorkspaceResolveStatus.unauthenticated,
          message: 'Session expired. Please login.',
        );
      }
      if (status == 403) {
        debugPrint('[WorkspaceResolver] 403 forbidden while reading memberships');
        debugPrint(
          'DIRECTUS PERMISSION ERROR: current Directus role cannot read business_profile_members for this user. role_id=${me.roleId} user_id=$userId',
        );
        clearActiveWorkspaceContext();
        return const WorkspaceResolveResult(
          status: WorkspaceResolveStatus.forbidden,
          message:
              'Workspace membership exists may be unavailable because this mobile role cannot read membership data. Check Directus permissions.',
        );
      }
      return WorkspaceResolveResult(
        status: WorkspaceResolveStatus.error,
        message: _extractMessage(e),
      );
    } catch (e) {
      debugPrint('[WORKSPACE] membership parse failed: $e');
      return WorkspaceResolveResult(
        status: WorkspaceResolveStatus.error,
        message: e.toString(),
      );
    }
  }

  String? get lastResolvedRole => _lastResolvedRole;
  String? get lastResolvedUserId => _lastResolvedUserId;

  Future<_CurrentUser?> _loadCurrentUser({
    bool includeActiveWorkspaceFields = false,
  }) async {
    final fields = includeActiveWorkspaceFields
        ? 'id,email,first_name,last_name,role,role.id,role.name,status,'
              'active_business_profile,active_business_profile.id,'
              'active_department,active_department.id,'
              'active_member_role,active_role'
        : 'id,email,first_name,last_name,role,role.id,role.name';
    final usersMeStopwatch = Stopwatch()..start();
    try {
      final response = await _client.get(
        '/users/me',
        queryParameters: {'fields': fields},
      );
      usersMeStopwatch.stop();
      final data = response.data['data'];
      if (data is! Map<String, dynamic>) return null;
      final id = data['id']?.toString().trim() ?? '';
      final email = data['email']?.toString().trim() ?? '';
      final roleRaw = data['role'];
      final roleId = roleRaw is Map ? roleRaw['id']?.toString().trim() : null;
      final role = roleRaw is Map
          ? roleRaw['name']?.toString().trim()
          : roleRaw?.toString().trim();
      final firstName = data['first_name']?.toString().trim();
      final lastName = data['last_name']?.toString().trim();
      final status = data['status']?.toString().trim();
      final activeBusinessProfileId = _extractRelationId(
        data['active_business_profile'],
      );
      final activeDepartmentId = _extractRelationId(data['active_department']);
      final activeMemberRole = _stringValue(data['active_member_role']);
      final activeRole = _stringValue(data['active_role']);
      if (id.isEmpty) return null;
      _wsDebug(
        '[WS_HTTP] trace=${_activeSwitchTrace ?? 'none'} stage=users_me method=GET endpoint=/users/me started=true status=${response.statusCode ?? 0} duration_ms=${usersMeStopwatch.elapsedMilliseconds} network_error_type=none network_error_status=0',
      );
      _wsDebug(
        '[WS_CLIENT_STATE] trace=${_activeSwitchTrace ?? 'none'} label=users_me client_instance_id=${DirectusClient.instance.instanceId} dio_instance_id=${DirectusClient.instance.dioInstanceId} token_fp=${DirectusClient.tokenFingerprint(Session.instance.accessToken)}',
      );
      _wsDebug(
        '[WS_USERS_ME] trace=${_activeSwitchTrace ?? 'none'} loaded=true role_source=${roleRaw is Map ? (roleRaw['name'] != null ? 'role_name' : 'role_id') : (roleRaw != null ? 'scalar' : 'missing')} directus_role_id=${roleId ?? ''} directus_role_name=${role ?? ''} active_business_profile=${activeBusinessProfileId ?? ''} active_department=${activeDepartmentId ?? ''} active_member_role=${activeMemberRole ?? ''} active_role=${activeRole ?? ''} status=${status ?? ''}',
      );
      if (Session.instance.userId != id) {
        clearActiveWorkspaceContext();
      }
      await Session.instance.setAuth(
        accessToken: Session.instance.accessToken ?? '',
        refreshToken: Session.instance.refreshToken,
        userId: id,
        userEmail: email,
        userName: Session.instance.userName,
        roleName: role,
      );
      return _CurrentUser(
        id: id,
        email: email,
        firstName: firstName,
        lastName: lastName,
        roleId: roleId,
        role: role,
        status: status,
        activeBusinessProfileId: activeBusinessProfileId,
        activeDepartmentId: activeDepartmentId,
        activeMemberRole: activeMemberRole,
        activeRole: activeRole,
      );
    } on DioException catch (e) {
      usersMeStopwatch.stop();
      final status = e.response?.statusCode ?? 0;
      _wsDebug(
        '[WS_HTTP] trace=${_activeSwitchTrace ?? 'none'} stage=users_me method=GET endpoint=/users/me started=true status=$status duration_ms=${usersMeStopwatch.elapsedMilliseconds} network_error_type=${e.type} network_error_status=$status',
      );
      debugPrint(
        '[WorkspaceResolver] /users/me failed status=$status body=${e.response?.data}',
      );
      return null;
    }
  }

  Future<Organization?> fetchPrimaryOrganization() async {
    final business = await fetchPrimaryBusinessProfile();
    if (business != null && business.id.trim().isNotEmpty) {
      return Organization(
        id: business.id,
        name: business.displayName,
        industry: business.industry?.trim() ?? '',
      );
    }
    return null;
  }

  Future<String?> fetchPrimaryBusinessProfileId() async {
    final profile = await fetchPrimaryBusinessProfile();
    if (profile == null || profile.id.trim().isEmpty) return null;
    return profile.id.trim();
  }

  Future<BusinessProfile?> fetchPrimaryBusinessProfile({
    bool forceRefresh = false,
  }) async {
    _lastProfileResolveError = null;
    final userId = Session.instance.userId?.trim();
    if (userId == null || userId.isEmpty) {
      clearProfileCache();
      return null;
    }

    if (_cachedBusinessProfileUserId != null &&
        _cachedBusinessProfileUserId != userId) {
      _cachedBusinessProfile = null;
      _cachedBusinessProfileUserId = null;
    }

    if (!forceRefresh &&
        _cachedBusinessProfileUserId == userId &&
        _cachedBusinessProfile != null &&
        _cachedBusinessProfile!.id.trim().isNotEmpty) {
      return _cachedBusinessProfile;
    }

    final context = await fetchActiveWorkspaceContext(forceRefresh: forceRefresh);
    if (context != null && context.businessProfileId.trim().isNotEmpty) {
      final direct = await _fetchBusinessProfileById(context.businessProfileId);
      if (direct != null) {
        _cachedBusinessProfile = direct;
        _cachedBusinessProfileUserId = userId;
        return direct;
      }
      final fallback = BusinessProfile.fromJson({
        'id': context.businessProfileId,
        'business_name': context.businessProfileName,
        'company_name': context.businessProfileName,
      });
      _cachedBusinessProfile = fallback;
      _cachedBusinessProfileUserId = userId;
      return fallback;
    }

    try {
      final memberProfile = await _fetchBusinessProfileFromMembership(userId);
      if (memberProfile != null) {
        _lastProfileResolveError = null;
        _cachedBusinessProfile = memberProfile;
        _cachedBusinessProfileUserId = userId;
        return memberProfile;
      }
    } on DioException catch (e) {
      _lastProfileResolveError = _extractMessage(e);
      // Try next strategy.
    }
    return null;
  }

  Future<List<BusinessProfileMember>> fetchBusinessMembers({
    String? businessProfileId,
    int limit = 100,
  }) async {
    final profileId =
        businessProfileId ?? await fetchPrimaryBusinessProfileId();
    if (profileId == null || profileId.isEmpty) return const [];

    final fields =
        'id,member_role,status,business_profile,user,user.id,user.email,user.first_name,user.last_name';
    final baseQuery = <String, dynamic>{
      'limit': limit,
      'filter[business_profile][_eq]': profileId,
      'fields': fields,
    };

    try {
      final sorted = await _client.get(
        '/items/business_profile_members',
        queryParameters: {...baseQuery, 'sort': 'member_role'},
      );
      return _decodeMembersList(sorted.data['data']);
    } on DioException catch (e) {
      if (!_isProfileQueryFieldIssue(e)) rethrow;
      final plain = await _client.get(
        '/items/business_profile_members',
        queryParameters: baseQuery,
      );
      return _decodeMembersList(plain.data['data']);
    }
  }

  Future<BusinessProfileMember> upsertBusinessMemberByEmail({
    required String email,
    required String memberRole,
    String status = 'active',
    String? businessProfileId,
  }) async {
    final rawEmail = email.trim();
    final normalizedEmail = rawEmail.toLowerCase();
    if (rawEmail.isEmpty) {
      throw const OrganizationServiceException('Member email is required.');
    }

    final profileId =
        businessProfileId ?? await fetchPrimaryBusinessProfileId();
    if (profileId == null || profileId.trim().isEmpty) {
      throw const OrganizationServiceException(
        'No business profile found for current user.',
      );
    }

    final userId = await _resolveUserIdByEmail(rawEmail);
    if (userId == null || userId.trim().isEmpty) {
      throw const OrganizationServiceException(
        'User not found or not visible for your role. Ensure the email is registered and /users lookup permission is allowed.',
      );
    }

    final roleValue = _normalizeMemberRole(memberRole);
    final statusValue = status.trim().isEmpty ? 'active' : status.trim();
    final existing = await _findMembership(
      businessProfileId: profileId,
      userId: userId,
    );

    if (existing != null && existing.id.trim().isNotEmpty) {
      final payload = {'member_role': roleValue, 'status': statusValue};
      try {
        final response = await _client.patch(
          '/items/business_profile_members/${existing.id}',
          data: payload,
        );
        final updated = _decodeMemberFromResponse(response.data);
        if (updated != null) return updated;
        return await _fetchMembershipById(existing.id) ?? existing;
      } on DioException catch (e) {
        // Some setups lock status updates; retry with role only.
        if (_isFieldIssue(e, 'status')) {
          final response = await _client.patch(
            '/items/business_profile_members/${existing.id}',
            data: {'member_role': roleValue},
          );
          final updated = _decodeMemberFromResponse(response.data);
          if (updated != null) return updated;
          return await _fetchMembershipById(existing.id) ?? existing;
        }
        throw OrganizationServiceException(_extractMessage(e));
      }
    }

    final payload = {
      'business_profile': profileId,
      'user': userId,
      'member_role': roleValue,
      'status': statusValue,
    };
    try {
      final response = await _client.post(
        '/items/business_profile_members',
        data: payload,
      );
      final created = _decodeMemberFromResponse(response.data);
      if (created != null) return created;
      final createdId = _extractCreatedId(response.data);
      if (createdId != null) {
        final fetched = await _fetchMembershipById(createdId);
        if (fetched != null) return fetched;
      }
      return BusinessProfileMember(
        id: createdId ?? '',
        businessProfileId: profileId,
        userId: userId,
        userEmail: normalizedEmail,
        userFirstName: null,
        userLastName: null,
        memberRole: roleValue,
        status: statusValue,
      );
    } on DioException catch (e) {
      if (_isFieldIssue(e, 'status')) {
        final response = await _client.post(
          '/items/business_profile_members',
          data: {
            'business_profile': profileId,
            'user': userId,
            'member_role': roleValue,
          },
        );
        final created = _decodeMemberFromResponse(response.data);
        if (created != null) return created;
        final createdId = _extractCreatedId(response.data);
        if (createdId != null) {
          final fetched = await _fetchMembershipById(createdId);
          if (fetched != null) return fetched;
        }
      }
      throw OrganizationServiceException(_extractMessage(e));
    }
  }

  Future<List<BusinessProfileMember>> fetchMyBusinessMemberships({
    int limit = 100,
  }) async {
    final userId = Session.instance.userId?.trim();
    if (userId == null || userId.isEmpty) return const [];
    final fields =
        'id,member_role,status,business_profile,user,user.id,user.email,user.first_name,user.last_name';
    final queryAttempts = <Map<String, dynamic>>[
      {'limit': limit, 'filter[user][_eq]': userId, 'fields': fields},
      {'limit': limit, 'filter[user][id][_eq]': userId, 'fields': fields},
    ];

    DioException? lastError;
    for (final baseQuery in queryAttempts) {
      try {
        final sorted = await _client.get(
          '/items/business_profile_members',
          queryParameters: {...baseQuery, 'sort': '-date_created'},
        );
        return _decodeMembersList(sorted.data['data']);
      } on DioException catch (e) {
        lastError = e;
        if (!_isProfileQueryFieldIssue(e)) rethrow;
        try {
          final plain = await _client.get(
            '/items/business_profile_members',
            queryParameters: baseQuery,
          );
          return _decodeMembersList(plain.data['data']);
        } on DioException catch (inner) {
          lastError = inner;
          if (!_isProfileQueryFieldIssue(inner)) rethrow;
        }
      }
    }

    if (lastError != null) throw lastError;
    return const [];
  }

  Future<List<String>> fetchBusinessTeamUserIds({
    String? businessProfileId,
    int limit = 200,
  }) async {
    final ids = <String>{};

    final profile = await fetchPrimaryBusinessProfile();
    final profileId =
        businessProfileId ??
        (profile != null && profile.id.trim().isNotEmpty ? profile.id : null);
    final ownerId = profile?.ownerUserId?.trim();
    if (ownerId != null && ownerId.isNotEmpty) {
      ids.add(ownerId);
    }

    if (profileId != null && profileId.isNotEmpty) {
      try {
        final members = await fetchBusinessMembers(
          businessProfileId: profileId,
          limit: limit,
        );
        for (final member in members) {
          final status = member.status.trim().toLowerCase();
          if (status.isNotEmpty &&
              status != 'active' &&
              status != 'pending' &&
              status != 'invited') {
            continue;
          }
          final userId = member.userId.trim();
          if (userId.isEmpty) continue;
          ids.add(userId);
        }
      } on DioException {
        // Best-effort team enrichment.
      }
    }

    final self = Session.instance.userId?.trim();
    if (self != null && self.isNotEmpty) {
      ids.add(self);
    }

    return ids.toList();
  }

  Future<BusinessProfile?> _fetchOwnedBusinessProfile(String userId) async {
    final attempts = <Map<String, dynamic>>[
      {'limit': 1, 'filter[owner_user][_eq]': userId},
      {'limit': 1, 'filter[owner_user][id][_eq]': userId},
    ];

    for (final query in attempts) {
      final profile = await _fetchFirstProfileWithFieldsFallback(
        queryParameters: query,
      );
      if (profile != null) return profile;
    }
    return null;
  }

  Future<String?> _resolveUserIdByEmail(String email) async {
    final target = email.trim();
    if (target.isEmpty) return null;
    final normalized = target.toLowerCase();

    Future<String?> tryQuery(Map<String, dynamic> query) async {
      final response = await _client.get('/users', queryParameters: query);
      return _extractMatchingUserIdByEmail(
        data: response.data['data'],
        email: normalized,
      );
    }

    final eqCandidates = <String>{target, normalized};
    for (final value in eqCandidates) {
      final id = await tryQuery({
        'limit': 10,
        'filter[email][_eq]': value,
        'fields': 'id,email',
      });
      if (id != null && id.isNotEmpty) return id;
    }

    try {
      final id = await tryQuery({
        'limit': 10,
        'filter[email][_icontains]': normalized,
        'fields': 'id,email',
      });
      if (id != null && id.isNotEmpty) return id;
    } on DioException {
      // Operator availability differs by setup, so continue to search fallback.
    }

    final id = await tryQuery({
      'limit': 25,
      'search': target,
      'fields': 'id,email',
    });
    if (id != null && id.isNotEmpty) return id;
    return null;
  }

  String? _extractMatchingUserIdByEmail({
    required dynamic data,
    required String email,
  }) {
    String? pick(dynamic row) {
      if (row is! Map) return null;
      final id = row['id']?.toString().trim() ?? '';
      if (id.isEmpty) return null;
      final rowEmail = row['email']?.toString().trim().toLowerCase() ?? '';
      if (rowEmail == email) return id;
      return null;
    }

    if (data is List) {
      for (final row in data) {
        final id = pick(row);
        if (id != null) return id;
      }
    }
    return pick(data);
  }

  Future<BusinessProfileMember?> _findMembership({
    required String businessProfileId,
    required String userId,
  }) async {
    final response = await _client.get(
      '/items/business_profile_members',
      queryParameters: {
        'limit': 1,
        'filter[business_profile][_eq]': businessProfileId,
        'filter[user][_eq]': userId,
        'fields':
            'id,member_role,status,business_profile,user,user.id,user.email,user.first_name,user.last_name',
      },
    );
    final data = response.data['data'];
    if (data is List && data.isNotEmpty) {
      final first = data.first;
      if (first is Map<String, dynamic>) {
        return BusinessProfileMember.fromJson(first);
      }
    }
    return null;
  }

  Future<BusinessProfileMember?> _fetchMembershipById(String id) async {
    final response = await _client.get(
      '/items/business_profile_members/$id',
      queryParameters: {
        'fields':
            'id,member_role,status,business_profile,user,user.id,user.email,user.first_name,user.last_name',
      },
    );
    final data = response.data['data'];
    if (data is Map<String, dynamic>) {
      return BusinessProfileMember.fromJson(data);
    }
    return null;
  }

  Future<BusinessProfile?> _fetchBusinessProfileFromMembership(
    String userId,
  ) async {
    final baseAttempts = <Map<String, dynamic>>[
      {
        'limit': 1,
        'filter[user][_eq]': userId,
        'filter[status][_eq]': 'active',
      },
      {
        'limit': 1,
        'filter[user][id][_eq]': userId,
        'filter[status][_eq]': 'active',
      },
      {'limit': 1, 'filter[user][_eq]': userId},
      {'limit': 1, 'filter[user][id][_eq]': userId},
    ];

    for (final baseQuery in baseAttempts) {
      final records = await _fetchMembershipProfileRecords(
        baseQuery: baseQuery,
      );
      final profile = await _extractProfileFromMembershipRecords(records);
      if (profile != null) return profile;
    }
    return null;
  }

  Future<BusinessProfile?> _fetchBusinessProfileById(String id) async {
    try {
      final response = await _client.get(
        '/items/business_profiles/$id',
        queryParameters: {'fields': _businessProfileFields},
      );
      return _decodeBusinessProfile(response.data['data']);
    } on DioException catch (e) {
      if (!_isProfileQueryFieldIssue(e)) rethrow;
      final fallback = await _client.get(
        '/items/business_profiles/$id',
        queryParameters: {'fields': _businessProfileFallbackFields},
      );
      return _decodeBusinessProfile(fallback.data['data']);
    }
  }

  BusinessProfile? _firstProfile(dynamic data) {
    if (data is! List || data.isEmpty) return null;
    for (final item in data.whereType<Map<String, dynamic>>()) {
      final profile = BusinessProfile.fromJson(item);
      if (profile.id.trim().isNotEmpty) return profile;
    }
    return null;
  }

  BusinessProfileMember? _decodeMemberFromResponse(dynamic data) {
    if (data is Map && data['data'] is Map<String, dynamic>) {
      return BusinessProfileMember.fromJson(
        data['data'] as Map<String, dynamic>,
      );
    }
    if (data is Map && data['data'] is List && data['data'].isNotEmpty) {
      final first = data['data'].first;
      if (first is Map<String, dynamic>) {
        return BusinessProfileMember.fromJson(first);
      }
    }
    return null;
  }

  Future<BusinessProfile?> _fetchFirstProfileWithFieldsFallback({
    required Map<String, dynamic> queryParameters,
  }) async {
    final withoutSort = Map<String, dynamic>.from(queryParameters)
      ..remove('sort');
    final attempts = <Map<String, dynamic>>[
      {...queryParameters, 'fields': _businessProfileFields},
      {...queryParameters, 'fields': _businessProfileFallbackFields},
      {...withoutSort, 'fields': _businessProfileFields},
      {...withoutSort, 'fields': _businessProfileFallbackFields},
    ];

    DioException? lastError;
    for (final query in attempts) {
      try {
        final response = await _client.get(
          '/items/business_profiles',
          queryParameters: query,
        );
        final profile = _firstProfile(response.data['data']);
        if (profile != null) return profile;
      } on DioException catch (e) {
        lastError = e;
        if (!_isProfileQueryFieldIssue(e)) rethrow;
      }
    }
    if (lastError != null) {
      // Keep current nullable contract but do not hide non-query failures above.
      return null;
    }
    return null;
  }

  Future<dynamic> _fetchMembershipProfileRecords({
    required Map<String, dynamic> baseQuery,
  }) async {
    final withoutSort = Map<String, dynamic>.from(baseQuery)..remove('sort');
    final attempts = <Map<String, dynamic>>[
      {
        ...baseQuery,
        'sort': '-date_created',
        'fields': _membershipBusinessProfileFields,
      },
      {...baseQuery, 'fields': _membershipBusinessProfileFields},
      {...baseQuery, 'fields': _membershipBusinessProfileFallbackFields},
      {...withoutSort, 'fields': _membershipBusinessProfileFields},
      {...withoutSort, 'fields': _membershipBusinessProfileFallbackFields},
      {
        ...withoutSort,
        'fields': 'id,status,business_profile,business_profile.id',
      },
    ];

    DioException? lastError;
    for (final query in attempts) {
      try {
        final response = await _client.get(
          '/items/business_profile_members',
          queryParameters: query,
        );
        return response.data['data'];
      } on DioException catch (e) {
        lastError = e;
        if (!_isProfileQueryFieldIssue(e)) rethrow;
      }
    }
    if (lastError != null) return null;
    return null;
  }

  Future<BusinessProfile?> _extractProfileFromMembershipRecords(
    dynamic data,
  ) async {
    if (data is! List || data.isEmpty) return null;
    for (final record in data.whereType<Map<String, dynamic>>()) {
      final status = record['status']?.toString().trim().toLowerCase() ?? '';
      if (status.isNotEmpty && status != 'active') continue;
      final business = record['business_profile'];
      if (business is Map<String, dynamic>) {
        final profile = BusinessProfile.fromJson(business);
        if (profile.id.trim().isNotEmpty) return profile;
      } else if (business != null) {
        final id = business.toString().trim();
        if (id.isEmpty) continue;
        final direct = await _fetchBusinessProfileById(id);
        if (direct != null) return direct;
        return BusinessProfile.fromJson({'id': id});
      }
    }
    return null;
  }

  List<BusinessProfileMember> _decodeMembersList(dynamic data) {
    if (data is List) {
      return data
          .whereType<Map<String, dynamic>>()
          .map(BusinessProfileMember.fromJson)
          .toList();
    }
    return const [];
  }

  BusinessProfile? _decodeBusinessProfile(dynamic data) {
    if (data is Map<String, dynamic>) {
      final profile = BusinessProfile.fromJson(data);
      if (profile.id.trim().isNotEmpty) return profile;
    }
    return null;
  }

  String? _extractCreatedId(dynamic data) {
    if (data is Map && data['data'] is Map && data['data']['id'] != null) {
      return data['data']['id'].toString();
    }
    if (data is Map && data['data'] is List && data['data'].isNotEmpty) {
      final first = data['data'].first;
      if (first is Map && first['id'] != null) {
        return first['id'].toString();
      }
    }
    return null;
  }

  String _normalizeMemberRole(String role) {
    final normalized = role.trim().toLowerCase();
    if (normalized.isEmpty) return 'member';
    if (normalized == 'owner') return 'owner';
    if (normalized == 'admin') return 'admin';
    if (normalized == 'manager') return 'manager';
    return 'member';
  }

  bool _isFieldIssue(DioException e, String fieldName) {
    final message = _extractMessage(e).toLowerCase();
    final normalizedField = fieldName.toLowerCase();
    return message.contains('field') && message.contains(normalizedField);
  }

  bool _isProfileQueryFieldIssue(DioException e) {
    final message = _extractMessage(e).toLowerCase();
    return message.contains('field') ||
        message.contains('invalid query') ||
        message.contains('unknown') ||
        message.contains('doesn\'t exist') ||
        message.contains('not found');
  }

  String _extractMessage(DioException e) {
    final data = e.response?.data;
    if (data is Map) {
      final errors = data['errors'];
      if (errors is List && errors.isNotEmpty) {
        final first = errors.first;
        if (first is Map && first['message'] != null) {
          return first['message'].toString();
        }
      }
      if (data['message'] != null) {
        return data['message'].toString();
      }
    }
    return e.message ?? 'Request failed';
  }

  String _normalizeRole(String? role) {
    final value = role?.trim().toLowerCase() ?? '';
    if (value == 'owner') return 'owner';
    if (value == 'hr') return 'hr';
    if (value == 'manager' || value == 'manger') return 'manager';
    if (value == 'employee') return 'employee';
    if (value == 'user') return 'user';
    return 'user';
  }

  String? _normalizeMembershipRole(String? role) {
    final normalized = _normalizeRole(role);
    if (normalized == 'user') return null;
    return normalized;
  }

  String _resolveFinalEffectiveRole({
    required String directusRole,
    required String membershipRole,
  }) {
    const order = <String, int>{
      'employee': 1,
      'manager': 2,
      'hr': 3,
      'owner': 4,
    };
    final direct = order[directusRole];
    final member = order[membershipRole];
    if (direct == null && member == null) return 'user';
    if (direct == null) return membershipRole;
    if (member == null) return directusRole;
    return direct <= member ? directusRole : membershipRole;
  }

  CanonicalWorkspaceContextSnapshot _buildCanonicalWorkspaceSnapshot(
    Map<String, dynamic> map, {
    required _CurrentUser currentUser,
  }) {
    final active = _parseActiveWorkspace(
      map['active'],
      currentUser: currentUser,
    );
    final activeMembershipId = active?.membershipId ?? '';
    final memberships = _parseWorkspaceMemberships(
      map['memberships'],
      activeMembershipId: activeMembershipId,
    );

    return CanonicalWorkspaceContextSnapshot(
      currentUserId: currentUser.id,
      currentUserEmail: currentUser.email,
      currentUserFirstName: currentUser.firstName,
      currentUserLastName: currentUser.lastName,
      directusRoleId: currentUser.roleId,
      directusRoleName: currentUser.role,
      activeMembershipId: activeMembershipId,
      memberships: memberships,
      activeContext: active,
    );
  }

  List<WorkspaceMembershipChoice> _parseWorkspaceMemberships(
    dynamic value, {
    required String activeMembershipId,
  }) {
    final list = _asArray(value);
    return list
        .map(_asMap)
        .whereType<Map<String, dynamic>>()
        .map(
          (record) => _parseWorkspaceMembership(
            record,
            activeMembershipId: activeMembershipId,
          ),
        )
        .whereType<WorkspaceMembershipChoice>()
        .toList();
  }

  WorkspaceMembershipChoice? _parseWorkspaceMembership(
    Map<String, dynamic> record, {
    required String activeMembershipId,
  }) {
    final id = _stringValue(record['id']);
    final status = _stringValue(record['status']) ?? 'active';
    final memberRole = _stringValue(record['memberRole'])?.toLowerCase() ?? '';
    final workspace = _parseWorkspace(record['workspace']);
    final normalizedMemberRole = _normalizeMembershipRole(memberRole);
    if (id == null || normalizedMemberRole == null || workspace == null) {
      return null;
    }
    final department = _parseDepartment(record['department']);
    return WorkspaceMembershipChoice(
      membershipId: id,
      businessProfileId: workspace.id,
      companyName: workspace.companyName,
      memberRole: normalizedMemberRole,
      departmentId: department?.id,
      departmentName: department?.name,
      businessProfileStatus: workspace.isActive ? 'true' : 'false',
      businessPlanCode: workspace.planCode,
      businessBillingStatus: workspace.billingStatus,
      status: status,
      isCurrent: id == activeMembershipId,
    );
  }

  ActiveWorkspaceContext? _parseActiveWorkspace(
    dynamic value, {
    required _CurrentUser currentUser,
  }) {
    final record = _asMap(value);
    if (record == null) return null;
    final workspace = _parseWorkspace(record['workspace']);
    final membership = _parseActiveMembership(
      record['membership'],
      fallbackMemberRole:
          _stringValue(record['memberRole']) ?? _stringValue(record['member_role']),
    );
    if (workspace == null || membership == null) return null;
    final department = _parseDepartment(record['department']);
    final directusRole = _normalizeRole(currentUser.role);
    final finalEffectiveRole = membership.memberRole;
    final roleConsistent = directusRole == membership.memberRole;
    final scopeLabel = department?.name.trim().isNotEmpty == true
        ? '${finalEffectiveRole.toUpperCase()} - ${department!.name.trim()}'
        : finalEffectiveRole.toUpperCase();
    _wsDebug(
      '[WS_CONTEXT_PARSE] trace=${_activeSwitchTrace ?? 'none'} membership_id=${membership.id} business_profile=${workspace.id} department=${department?.id ?? ''} raw_membership_role=${_stringValue(record['memberRole']) ?? _stringValue(record['member_role']) ?? membership.memberRole} normalized_membership_role=${membership.memberRole} raw_directus_role=${currentUser.role ?? ''} normalized_directus_role=$directusRole authoritative_role_source=membership.member_role constructed_member_role=${membership.memberRole} role_consistent=$roleConsistent context_source=canonical_context',
    );
    _wsDebug(
      '[WS_ROLE_DECISION] trace=${_activeSwitchTrace ?? 'none'} membership_role=${membership.memberRole} directus_role=$directusRole workspace_role=${membership.memberRole} workspace_role_source=membership directus_role_used_as_workspace_role=false role_consistent=$roleConsistent',
    );
    return ActiveWorkspaceContext(
      currentUserId: currentUser.id,
      currentUserEmail: currentUser.email,
      currentUserFirstName: currentUser.firstName,
      currentUserLastName: currentUser.lastName,
      directusRoleId: currentUser.roleId,
      directusRoleName: currentUser.role,
      membershipUserId: currentUser.id,
      businessProfileId: workspace.id,
      businessProfileName: workspace.companyName,
      businessProfileStatus: workspace.isActive ? 'true' : 'false',
      businessPlanCode: workspace.planCode,
      businessBillingStatus: workspace.billingStatus,
      membershipId: membership.id,
      memberRole: membership.memberRole,
      membershipRole: membership.memberRole,
      finalEffectiveRole: finalEffectiveRole,
      membershipStatus: membership.status,
      departmentId: department?.id,
      departmentName: department?.name,
      scopeLabel: scopeLabel,
    );
  }

  _WorkspaceContextWorkspace? _parseWorkspace(dynamic value) {
    final record = _asMap(value);
    if (record == null) {
      final id = _stringValue(value);
      if (id == null) return null;
      return _WorkspaceContextWorkspace(
        id: id,
        companyName: 'Workspace',
        isActive: false,
        planCode: null,
        billingStatus: null,
      );
    }
    final id = _stringValue(record['id']) ??
        _stringValue(record['businessProfileId']) ??
        _stringValue(record['business_profile']) ??
        _stringValue(record['business_profile_id']);
    final companyName = _stringValue(record['companyName']) ??
        _stringValue(record['company_name']) ??
        _stringValue(record['businessName']) ??
        _stringValue(record['business_name']) ??
        _stringValue(record['name']) ??
        'Workspace';
    if (id == null) return null;
    return _WorkspaceContextWorkspace(
      id: id,
      companyName: companyName,
      isActive: _isTruthy(
            record['isActive'] ?? record['is_active'] ?? record['active'],
          ) ||
          record['isActive'] == true ||
          record['is_active'] == true,
      planCode: _stringValue(record['planCode']) ??
          _stringValue(record['plan_code']),
      billingStatus: _stringValue(record['billingStatus']) ??
          _stringValue(record['billing_status']),
    );
  }

  _WorkspaceContextDepartment? _parseDepartment(dynamic value) {
    final record = _asMap(value);
    if (record == null) {
      final id = _stringValue(value);
      if (id == null) return null;
      return _WorkspaceContextDepartment(id: id, name: 'Department');
    }
    final id = _stringValue(record['id']) ??
        _stringValue(record['department_id']);
    final name = _stringValue(record['name']) ??
        _stringValue(record['department_name']) ??
        _stringValue(record['departmentName']) ??
        'Department';
    if (id == null) return null;
    return _WorkspaceContextDepartment(id: id, name: name);
  }

  _WorkspaceContextMembership? _parseActiveMembership(
    dynamic value, {
    String? fallbackMemberRole,
  }) {
    final record = _asMap(value);
    if (record == null) {
      final id = _stringValue(value);
      final memberRole = _normalizeMembershipRole(fallbackMemberRole);
      if (id == null || memberRole == null) return null;
      return _WorkspaceContextMembership(
        id: id,
        status: 'active',
        memberRole: memberRole,
      );
    }
    final id = _stringValue(record['id']) ??
        _stringValue(record['membershipId']) ??
        _stringValue(record['membership_id']);
    final status = _stringValue(record['status']) ?? 'active';
    final memberRole = _normalizeMembershipRole(
      _stringValue(record['memberRole']) ??
          _stringValue(record['member_role']) ??
          _stringValue(record['role']) ??
          fallbackMemberRole,
    );
    if (id == null || memberRole == null) return null;
    return _WorkspaceContextMembership(
      id: id,
      status: status,
      memberRole: memberRole,
    );
  }

  Map<String, dynamic>? _asMap(dynamic value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) {
      return value.map((key, val) => MapEntry(key.toString(), val));
    }
    return null;
  }

  List<dynamic> _asArray(dynamic value) {
    if (value is List) return value;
    return const <dynamic>[];
  }

  Map<String, dynamic>? _mapValue(
    Map<String, dynamic> source,
    List<String> path,
  ) {
    final value = _valueAtPath(source, path);
    return _asMap(value);
  }

  List<Map<String, dynamic>> _firstMapListFromPaths(
    Map<String, dynamic> source,
    List<List<String>> paths,
  ) {
    for (final path in paths) {
      final value = _valueAtPath(source, path);
      if (value is List) {
        final result = <Map<String, dynamic>>[];
        for (final item in value) {
          final map = _asMap(item);
          if (map != null) result.add(map);
        }
        if (result.isNotEmpty) return result;
      }
    }
    return const [];
  }

  String? _firstStringFromPaths(
    Map<String, dynamic> source,
    List<List<String>> paths,
  ) {
    for (final path in paths) {
      final value = _valueAtPath(source, path);
      final text = _stringValue(value);
      if (text != null && text.isNotEmpty) return text;
    }
    return null;
  }

  dynamic _valueAtPath(dynamic root, List<String> path) {
    dynamic current = root;
    for (final segment in path) {
      final map = _asMap(current);
      if (map == null) return null;
      current = map[segment];
    }
    return current;
  }

  String? _stringValue(dynamic value) {
    if (value == null) return null;
    final text = value.toString().trim();
    return text.isEmpty ? null : text;
  }

  bool _isTruthy(dynamic value) {
    if (value is bool) return value;
    if (value is num) return value != 0;
    if (value is String) {
      final normalized = value.trim().toLowerCase();
      return normalized == 'true' ||
          normalized == '1' ||
          normalized == 'yes' ||
          normalized == 'active';
    }
    return false;
  }

  CanonicalWorkspaceContextSnapshot?
  _extractCanonicalWorkspaceSnapshotFromSwitchResponse(
    dynamic raw, {
    required _CurrentUser currentUser,
  }) {
    final root = _asMap(raw);
    if (root == null) return null;
    final data = _asMap(root['data']) ?? root;
    final exactWorkspace = _asMap(data['workspace']) ??
        _asMap(data['business_profile']) ??
        _asMap(data['businessProfile']);
    final exactMembership = _asMap(data['membership']) ??
        _asMap(data['active_membership']) ??
        _asMap(data['business_profile_member']) ??
        _asMap(data['member']);
    final exactDepartment =
        _asMap(data['department']) ?? _asMap(data['active_department']);
    final exactMemberRole = _stringValue(data['memberRole']) ??
        _stringValue(data['member_role']);
    final candidate =
        data.containsKey('active') || data.containsKey('memberships')
            ? data
            : (exactWorkspace != null || exactMembership != null
                ? <String, dynamic>{
                    'active': <String, dynamic>{
                      'workspace': exactWorkspace ?? <String, dynamic>{
                        'id': _stringValue(data['workspace']) ??
                            _stringValue(data['business_profile']) ??
                            _stringValue(data['businessProfile']),
                        'companyName': _stringValue(
                              _asMap(data['workspace'])?['companyName'],
                            ) ??
                            _stringValue(
                              _asMap(data['workspace'])?['company_name'],
                            ) ??
                            _stringValue(
                              _asMap(data['workspace'])?['name'],
                            ),
                      },
                      'membership': exactMembership ??
                          <String, dynamic>{
                            'id': _stringValue(data['membership']) ??
                                _stringValue(data['active_membership']) ??
                                _stringValue(data['business_profile_member']) ??
                                _stringValue(data['member']),
                            'status': _stringValue(
                                  _asMap(data['membership'])?['status'],
                                ) ??
                                _stringValue(
                                  _asMap(data['active_membership'])?['status'],
                                ) ??
                                'active',
                            'memberRole': _stringValue(
                                  _asMap(data['membership'])?['memberRole'],
                                ) ??
                                _stringValue(
                                  _asMap(data['membership'])?['member_role'],
                                ) ??
                                _stringValue(
                                  _asMap(data['membership'])?['role'],
                                ) ??
                                exactMemberRole,
                          },
                      'department': exactDepartment,
                      'memberRole': exactMemberRole,
                      'member_role': exactMemberRole,
                    },
                    'memberships': data['memberships'] ?? const [],
                  }
                : null);
    if (candidate == null) return null;
    return _buildCanonicalWorkspaceSnapshot(candidate, currentUser: currentUser);
  }

  ActiveWorkspaceContext? _verifiedCanonicalContext(
    CanonicalWorkspaceContextSnapshot? snapshot, {
    required String expectedMembershipId,
    required String expectedBusinessProfileId,
    required String expectedDepartmentId,
    required String expectedEffectiveRole,
  }) {
    if (snapshot == null) return null;
    final context = snapshot.activeContext;
    if (context == null) return null;
    final normalizedExpectedMembershipId = expectedMembershipId.trim();
    final normalizedExpectedBusinessProfileId = expectedBusinessProfileId.trim();
    final normalizedExpectedDepartmentId = expectedDepartmentId.trim();
    final normalizedExpectedEffectiveRole = expectedEffectiveRole.trim().toLowerCase();
    final normalizedContextMembershipId = context.membershipId.trim();
    final normalizedCurrentUserId = context.currentUserId.trim();
    final normalizedMembershipUserId = context.membershipUserId.trim();
    final normalizedBusinessProfileId = context.businessProfileId.trim();
    final normalizedDepartmentId = context.departmentId?.trim() ?? '';
    final normalizedMembershipStatus = context.membershipStatus.trim().toLowerCase();
    final normalizedMembershipRole = context.membershipRole.trim().toLowerCase();
    if (normalizedCurrentUserId.isEmpty ||
        normalizedMembershipUserId != normalizedCurrentUserId ||
        normalizedContextMembershipId.isEmpty ||
        normalizedBusinessProfileId.isEmpty ||
        normalizedContextMembershipId != normalizedExpectedMembershipId ||
        (normalizedExpectedBusinessProfileId.isNotEmpty &&
            normalizedBusinessProfileId != normalizedExpectedBusinessProfileId) ||
        (normalizedExpectedDepartmentId.isNotEmpty &&
            normalizedDepartmentId != normalizedExpectedDepartmentId) ||
        (normalizedExpectedEffectiveRole.isNotEmpty &&
            normalizedMembershipRole !=
                normalizedExpectedEffectiveRole) ||
        (normalizedMembershipStatus != 'active' &&
            normalizedMembershipStatus != 'accepted')) {
      return null;
    }
    return context;
  }

  Future<_PostSwitchProbeResult> _probePostSwitchBusinessProfileMembers({
    required String businessProfileId,
    required String selectedMembershipId,
  }) async {
    final normalizedBusinessProfileId = businessProfileId.trim();
    final normalizedSelectedMembershipId = selectedMembershipId.trim();
    final trace = _activeSwitchTrace ?? 'none';
    if (normalizedBusinessProfileId.isEmpty) {
      _wsDebug(
        '[WS_HTTP] trace=$trace stage=membership_probe method=GET endpoint=/items/business_profile_members started=true status=0 duration_ms=0 network_error_type=none network_error_status=0',
      );
      _wsDebug(
        '[WS_MEMBERSHIP_PROBE] trace=$trace business_profile= membership_id=$normalizedSelectedMembershipId status_filter=active limit=1 http_status=0 member_count=0 visible=false duration_ms=0 returned_membership_ids=[] returned_business_profile_ids=[] returned_statuses=[]',
      );
      return const _PostSwitchProbeResult(statusCode: 0, memberCount: 0);
    }

    final probeStopwatch = Stopwatch()..start();
    try {
      final response = await _client.get(
        '/items/business_profile_members',
        queryParameters: {
          'filter[business_profile][_eq]': normalizedBusinessProfileId,
          if (normalizedSelectedMembershipId.isNotEmpty)
            'filter[id][_eq]': normalizedSelectedMembershipId,
          'filter[status][_eq]': 'active',
          'limit': 1,
          'fields': 'id,status,member_role,business_profile',
        },
      );
      probeStopwatch.stop();
      _wsDebug(
        '[WS_CLIENT_STATE] trace=$trace label=membership_probe client_instance_id=${DirectusClient.instance.instanceId} dio_instance_id=${DirectusClient.instance.dioInstanceId} token_fp=${DirectusClient.tokenFingerprint(Session.instance.accessToken)}',
      );
      final data = response.data;
      final rows = data is Map ? data['data'] : null;
      final count = rows is List ? rows.length : 0;
      final returnedMembershipIds = <String>{};
      final returnedBusinessProfileIds = <String>{};
      final returnedStatuses = <String>{};
      if (rows is List) {
        for (final row in rows.whereType<Map>()) {
          final map = row.map((key, value) => MapEntry(key.toString(), value));
          final membershipId = _stringValue(map['id']);
          final profileId = _stringValue(map['business_profile']);
          final status = _stringValue(map['status']);
          if (membershipId != null) returnedMembershipIds.add(membershipId);
          if (profileId != null) returnedBusinessProfileIds.add(profileId);
          if (status != null) returnedStatuses.add(status);
        }
      }
      _wsDebug(
        '[WS_HTTP] trace=$trace stage=membership_probe method=GET endpoint=/items/business_profile_members started=true status=${response.statusCode ?? 0} duration_ms=${probeStopwatch.elapsedMilliseconds} network_error_type=none network_error_status=0',
      );
      _wsDebug(
        '[WS_MEMBERSHIP_PROBE] trace=$trace business_profile=$normalizedBusinessProfileId membership_id=$normalizedSelectedMembershipId status_filter=active limit=1 http_status=${response.statusCode ?? 0} member_count=$count visible=${count > 0} duration_ms=${probeStopwatch.elapsedMilliseconds} returned_membership_ids=${returnedMembershipIds.toList()} returned_business_profile_ids=${returnedBusinessProfileIds.toList()} returned_statuses=${returnedStatuses.toList()}',
      );
      return _PostSwitchProbeResult(
        statusCode: response.statusCode ?? 0,
        memberCount: count,
      );
    } on DioException catch (e) {
      probeStopwatch.stop();
      final status = e.response?.statusCode ?? 0;
      _wsDebug(
        '[WS_CLIENT_STATE] trace=$trace label=membership_probe client_instance_id=${DirectusClient.instance.instanceId} dio_instance_id=${DirectusClient.instance.dioInstanceId} token_fp=${DirectusClient.tokenFingerprint(Session.instance.accessToken)}',
      );
      _wsDebug(
        '[WS_HTTP] trace=$trace stage=membership_probe method=GET endpoint=/items/business_profile_members started=true status=$status duration_ms=${probeStopwatch.elapsedMilliseconds} network_error_type=${e.type} network_error_status=$status',
      );
      _wsDebug(
        '[WS_MEMBERSHIP_PROBE] trace=$trace business_profile=$normalizedBusinessProfileId membership_id=$normalizedSelectedMembershipId status_filter=active limit=1 http_status=$status member_count=0 visible=false duration_ms=${probeStopwatch.elapsedMilliseconds} returned_membership_ids=[] returned_business_profile_ids=[] returned_statuses=[]',
      );
      return _PostSwitchProbeResult(statusCode: status, memberCount: 0);
    }
  }

  ActiveWorkspaceContext _withSelectedMembershipWinningContext(
    ActiveWorkspaceContext context,
  ) {
    final selectedRole = _normalizeRole(
      context.membershipRole.isNotEmpty
          ? context.membershipRole
          : context.finalEffectiveRole,
    );
    final departmentName = context.departmentName?.trim();
    final scopeLabel = departmentName != null && departmentName.isNotEmpty
        ? '${selectedRole.toUpperCase()} - $departmentName'
        : selectedRole.toUpperCase();
    return ActiveWorkspaceContext(
      currentUserId: context.currentUserId,
      currentUserEmail: context.currentUserEmail,
      currentUserFirstName: context.currentUserFirstName,
      currentUserLastName: context.currentUserLastName,
      directusRoleId: context.directusRoleId,
      directusRoleName: context.directusRoleName,
      membershipUserId: context.membershipUserId,
      businessProfileId: context.businessProfileId,
      businessProfileName: context.businessProfileName,
      businessProfileStatus: context.businessProfileStatus,
      businessPlanCode: context.businessPlanCode,
      businessBillingStatus: context.businessBillingStatus,
      membershipId: context.membershipId,
      memberRole: selectedRole,
      membershipRole: selectedRole,
      finalEffectiveRole: selectedRole,
      membershipStatus: context.membershipStatus,
      departmentId: context.departmentId,
      departmentName: context.departmentName,
      scopeLabel: scopeLabel,
    );
  }

  Future<bool> _applySwitchSessionCredentials(dynamic raw) async {
    final root = _asMap(raw);
    if (root == null) return false;
    final data = _asMap(root['data']);
    final accessToken =
        _stringValue(root['access_token']) ?? _stringValue(data?['access_token']);
    final refreshToken =
        _stringValue(root['refresh_token']) ??
        _stringValue(data?['refresh_token']);
    if (accessToken == null || accessToken.isEmpty) {
      return false;
    }
    if (refreshToken != null) {
      await Session.instance.setAuth(
        accessToken: accessToken,
        refreshToken: refreshToken,
      );
    } else {
      await Session.instance.setAuth(accessToken: accessToken);
    }
    return true;
  }

  Future<bool> _installPostSwitchSessionCredentials(dynamic raw) async {
    final installedFromSwitch = await _applySwitchSessionCredentials(raw);
    if (!installedFromSwitch) {
      return false;
    }

    DirectusClient.instance.syncAuthorizationHeaderFromSession();
    return true;
  }

  ActiveWorkspaceContext _buildFallbackSwitchedWorkspaceContext({
    required _CurrentUser currentUser,
    required WorkspaceMembershipChoice membership,
  }) {
    final membershipRole = _normalizeRole(membership.memberRole);
    final directusRole = _normalizeRole(currentUser.role);
    final finalEffectiveRole = membershipRole;
    final departmentName = membership.departmentName?.trim();
    final scopeLabel = departmentName != null && departmentName.isNotEmpty
        ? '${finalEffectiveRole.toUpperCase()} - $departmentName'
        : finalEffectiveRole.toUpperCase();
    return ActiveWorkspaceContext(
      currentUserId: currentUser.id,
      currentUserEmail: currentUser.email,
      currentUserFirstName: currentUser.firstName,
      currentUserLastName: currentUser.lastName,
      directusRoleId: currentUser.roleId,
      directusRoleName: currentUser.role,
      membershipUserId: currentUser.id,
      businessProfileId: membership.businessProfileId,
      businessProfileName: membership.companyName,
      businessProfileStatus: membership.businessProfileStatus,
      businessPlanCode: membership.businessPlanCode,
      businessBillingStatus: membership.businessBillingStatus,
      membershipId: membership.membershipId,
      memberRole: membershipRole,
      membershipRole: membershipRole,
      finalEffectiveRole: finalEffectiveRole,
      membershipStatus: membership.status.trim().isEmpty
          ? 'active'
          : membership.status.trim().toLowerCase(),
      departmentId: membership.departmentId,
      departmentName: departmentName,
      scopeLabel: scopeLabel,
    );
  }

  static const String _businessProfileFields =
      'id,owner_user,source_request,company_name,business_name,'
      'work_email,phone,industry,team_size,country,city,address,website,'
      'plan_code,billing_status,trial_started_at,trial_expires_at,is_active';

  static const String _businessProfileFallbackFields =
      'id,owner_user,company_name,business_name,work_email,plan_code,'
      'billing_status,is_active';

  static const String _membershipBusinessProfileFields =
      'id,status,business_profile,business_profile.id,business_profile.owner_user,business_profile.source_request,'
      'business_profile.company_name,business_profile.business_name,business_profile.work_email,'
      'business_profile.phone,business_profile.industry,business_profile.team_size,business_profile.country,'
      'business_profile.city,business_profile.address,business_profile.website,business_profile.plan_code,'
      'business_profile.billing_status,business_profile.trial_started_at,business_profile.trial_expires_at,business_profile.is_active';

  static const String _membershipBusinessProfileFallbackFields =
      'id,status,business_profile,business_profile.id,business_profile.owner_user,'
      'business_profile.company_name,business_profile.business_name,business_profile.work_email,'
      'business_profile.plan_code,business_profile.billing_status,business_profile.is_active';

  bool _verifyActiveFieldMatch(String? actual, String expected) {
    final normalizedExpected = expected.trim();
    if (normalizedExpected.isEmpty) return false;
    final normalizedActual = actual?.trim() ?? '';
    return normalizedActual == normalizedExpected;
  }

  bool _verifyActiveRoleMatch(_CurrentUser? currentUser, String expectedRole) {
    final normalizedExpected = expectedRole.trim().toLowerCase();
    if (normalizedExpected.isEmpty) return false;
    final actual = _normalizeRole(
      currentUser?.activeMemberRole ?? currentUser?.activeRole,
    );
    if (actual == 'user') return false;
    return actual == normalizedExpected;
  }

  bool _verifyDirectusRoleMatch(_CurrentUser? currentUser, String expectedRole) {
    final normalizedExpected = expectedRole.trim().toLowerCase();
    if (normalizedExpected.isEmpty || currentUser == null) return false;

    final directusRoleName = _normalizeRole(currentUser.role);
    if (directusRoleName == normalizedExpected) {
      return true;
    }

    final directusRoleId = currentUser.roleId?.trim() ?? '';
    if (directusRoleId.isEmpty) return false;

    final activeRole = _normalizeRole(
      currentUser.activeRole ?? currentUser.activeMemberRole,
    );
    return activeRole == normalizedExpected;
  }

  String? _extractRelationId(dynamic value) {
    if (value is Map) {
      return value['id']?.toString().trim();
    }
    final normalized = value?.toString().trim();
    return normalized?.isEmpty == true ? null : normalized;
  }

  Future<Response<dynamic>> _postWorkspaceSwitchRequest({
    required String membershipId,
    required String trace,
  }) async {
    Response<dynamic> response;
    final switchStopwatch = Stopwatch()..start();
    try {
      response = await _client.post(
        '/wellar/workspaces/switch',
        data: {'membership_id': membershipId},
      );
    } on DioException catch (e) {
      switchStopwatch.stop();
      _wsDebug(
        '[WS_HTTP] trace=$trace stage=switch method=POST endpoint=/wellar/workspaces/switch started=true status=${e.response?.statusCode ?? 0} duration_ms=${switchStopwatch.elapsedMilliseconds} network_error_type=${e.type} network_error_status=${e.response?.statusCode ?? 0}',
      );
      final status = e.response?.statusCode ?? 0;
      if (status == 401) {
        throw const OrganizationServiceException(
          'Your session expired. Please sign in again.',
        );
      }
      if (status == 403) {
        throw const OrganizationServiceException(
          'You are not allowed to switch organizations from this account.',
        );
      }
      if (status == 409) {
        throw const OrganizationServiceException(
          'This organization switch could not be completed right now.',
        );
      }
      throw OrganizationServiceException(_extractMessage(e));
    }
    switchStopwatch.stop();
    _wsDebug(
      '[WS_HTTP] trace=$trace stage=switch method=POST endpoint=/wellar/workspaces/switch started=true status=${response.statusCode ?? 0} duration_ms=${switchStopwatch.elapsedMilliseconds} network_error_type=none network_error_status=0',
    );
    return response;
  }

}

class _CurrentUser {
  final String id;
  final String email;
  final String? firstName;
  final String? lastName;
  final String? roleId;
  final String? role;
  final String? status;
  final String? activeBusinessProfileId;
  final String? activeDepartmentId;
  final String? activeMemberRole;
  final String? activeRole;

  const _CurrentUser({
    required this.id,
    required this.email,
    required this.firstName,
    required this.lastName,
    required this.roleId,
    required this.role,
    required this.status,
    required this.activeBusinessProfileId,
    required this.activeDepartmentId,
    required this.activeMemberRole,
    required this.activeRole,
  });
}

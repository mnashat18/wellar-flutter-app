import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../models/organization_invitation.dart';
import '../state/session.dart';
import 'directus_client.dart';
import 'organization_service.dart';

class OrganizationInvitationException implements Exception {
  final String message;
  const OrganizationInvitationException(this.message);

  @override
  String toString() => message;
}

class OrganizationInvitationActionResult {
  final String message;
  final ActiveWorkspaceContext? activeWorkspaceContext;
  final bool restoredOriginalWorkspace;

  const OrganizationInvitationActionResult({
    required this.message,
    required this.activeWorkspaceContext,
    required this.restoredOriginalWorkspace,
  });
}

class OrganizationInvitationService {
  OrganizationInvitationService._();

  static final OrganizationInvitationService instance =
      OrganizationInvitationService._();
  static const int _acceptRefreshAttempts = 6;
  static const Duration _acceptRefreshDelay = Duration(milliseconds: 400);

  Dio get _client => DirectusClient.instance.client;

  Future<List<OrganizationInvitation>> fetchPendingInvitations({
    int limit = 50,
  }) async {
    final currentUser =
        await OrganizationService.instance.fetchAuthenticatedCurrentUserProfile();
    final email =
        currentUser?.email.trim().toLowerCase() ??
        Session.instance.userEmail?.trim().toLowerCase() ??
        '';
    if (email.isEmpty) {
      return const <OrganizationInvitation>[];
    }

    final query = <String, dynamic>{
      'sort': '-date_created',
      'limit': limit.clamp(1, 100),
      'fields':
          'id,email,status,invite_type,member_role,date_created,sent_at,'
          'business_profile,business_profile.id,business_profile.company_name,business_profile.business_name,'
          'department,department.id,department.name,'
          'requested_by_user,requested_by_user.id,requested_by_user.first_name,requested_by_user.last_name,requested_by_user.email',
      'filter[email][_eq]': email,
      'filter[invite_type][_eq]': 'in_app',
      'filter[status][_in]': 'pending,sent,invited,Pending,Sent,Invited',
    };

    try {
      final response = await _client.get(
        '/items/request_invites',
        queryParameters: query,
      );
      final data = response.data['data'];
      if (data is! List) {
        return const <OrganizationInvitation>[];
      }

      return data
          .whereType<Map<String, dynamic>>()
          .map(OrganizationInvitation.fromJson)
          .where(
            (invite) =>
                invite.id.trim().isNotEmpty &&
                invite.inviteType.trim().toLowerCase() == 'in_app' &&
                invite.isPendingState &&
                invite.email.trim().toLowerCase() == email,
          )
          .toList(growable: false);
    } on DioException catch (error) {
      throw OrganizationInvitationException(_extractMessage(error));
    }
  }

  Future<OrganizationInvitationActionResult> acceptInvitation(
    OrganizationInvitation invitation,
  ) async {
    final user = await _requireCurrentUser();
    _validateInvitationRecipient(invitation, user.email);

    final beforeCanonical = await OrganizationService.instance
        .fetchCanonicalWorkspaceContext(forceRefresh: true);
    final originalMembershipId = _restorableMembershipId(beforeCanonical);

    try {
      await _client.patch(
        '/items/request_invites/${invitation.id}',
        data: <String, dynamic>{
          'status': 'claimed',
          'accepted_user': user.id,
          'claimed_at': DateTime.now().toUtc().toIso8601String(),
        },
      );
    } on DioException catch (error) {
      throw OrganizationInvitationException(_extractMessage(error));
    }

    final refreshed = await _refreshWorkspaceStateAfterAccept(
      invitedBusinessProfileId: invitation.businessProfileId,
      restoreMembershipId: originalMembershipId,
    );

    return OrganizationInvitationActionResult(
      message: refreshed.invitedMembershipVisible
          ? 'Invitation accepted. The organization is now available in Switch Organization.'
          : 'Invitation accepted. Organization access is still syncing. Refresh Switch Organization in a moment.',
      activeWorkspaceContext: refreshed.context,
      restoredOriginalWorkspace: refreshed.restored,
    );
  }

  Future<OrganizationInvitationActionResult> declineInvitation(
    OrganizationInvitation invitation,
  ) async {
    final user = await _requireCurrentUser();
    _validateInvitationRecipient(invitation, user.email);

    try {
      await _client.patch(
        '/items/request_invites/${invitation.id}',
        data: const <String, dynamic>{'status': 'declined'},
      );
    } on DioException catch (error) {
      throw OrganizationInvitationException(_extractMessage(error));
    }

    OrganizationService.instance.clearWorkspaceSessionSyncState();
    final canonical = await OrganizationService.instance
        .fetchCanonicalWorkspaceContext(forceRefresh: true);
    final refreshed =
        canonical.status == CanonicalWorkspaceContextStatus.ok &&
            canonical.snapshot != null &&
            _isValidActiveContext(canonical.snapshot!.activeContext)
        ? _RefreshWorkspaceResult(
            context: canonical.snapshot!.activeContext,
            restored: false,
            invitedMembershipVisible: false,
          )
        : const _RefreshWorkspaceResult(
            context: null,
            restored: false,
            invitedMembershipVisible: false,
          );
    if (refreshed.context != null) {
      OrganizationService.instance.applyActiveWorkspaceContext(
        refreshed.context!,
      );
    } else {
      OrganizationService.instance.clearActiveWorkspaceContext();
    }

    return OrganizationInvitationActionResult(
      message: 'Invitation declined.',
      activeWorkspaceContext: refreshed.context,
      restoredOriginalWorkspace: false,
    );
  }

  Future<_RefreshWorkspaceResult> _refreshWorkspaceStateAfterAccept({
    required String invitedBusinessProfileId,
    required String? restoreMembershipId,
  }) async {
    OrganizationService.instance.clearWorkspaceSessionSyncState();
    CanonicalWorkspaceContextResult canonical = await OrganizationService
        .instance
        .fetchCanonicalWorkspaceContext(forceRefresh: true);
    CanonicalWorkspaceContextSnapshot? snapshot = canonical.snapshot;
    var invitedMembershipVisible = _hasEligibleMembershipForBusinessProfile(
      snapshot?.memberships ?? const <WorkspaceMembershipChoice>[],
      invitedBusinessProfileId,
    );

    for (var attempt = 1;
        attempt < _acceptRefreshAttempts && !invitedMembershipVisible;
        attempt++) {
      await Future<void>.delayed(_acceptRefreshDelay);
      canonical = await OrganizationService.instance.fetchCanonicalWorkspaceContext(
        forceRefresh: true,
      );
      snapshot = canonical.snapshot;
      invitedMembershipVisible = _hasEligibleMembershipForBusinessProfile(
        snapshot?.memberships ?? const <WorkspaceMembershipChoice>[],
        invitedBusinessProfileId,
      );
    }

    if (canonical.status != CanonicalWorkspaceContextStatus.ok ||
        snapshot == null) {
      return _RefreshWorkspaceResult(
        context: null,
        restored: false,
        invitedMembershipVisible: invitedMembershipVisible,
      );
    }

    final activeContext = snapshot.activeContext;
    final hasValidCurrent = _isValidActiveContext(activeContext);

    if (restoreMembershipId != null &&
        restoreMembershipId.isNotEmpty &&
        invitedMembershipVisible &&
        hasValidCurrent &&
        snapshot.activeMembershipId.trim().isNotEmpty &&
        snapshot.activeMembershipId.trim() != restoreMembershipId &&
        _isMembershipEligible(snapshot.memberships, restoreMembershipId)) {
      try {
        final restored = await OrganizationService.instance.syncWorkspaceSession(
          membershipId: restoreMembershipId,
          trigger: 'organization_invitation_accept_restore',
        );
        return _RefreshWorkspaceResult(
          context: restored,
          restored: true,
          invitedMembershipVisible: true,
        );
      } on OrganizationServiceException catch (error) {
        debugPrint('[ORG_INVITE_RESTORE_FAILED] message=${error.message}');
      } catch (error) {
        debugPrint('[ORG_INVITE_RESTORE_FAILED] error=$error');
      }
    }

    if (hasValidCurrent) {
      OrganizationService.instance.applyActiveWorkspaceContext(activeContext!);
      return _RefreshWorkspaceResult(
        context: activeContext,
        restored: false,
        invitedMembershipVisible: invitedMembershipVisible,
      );
    }

    OrganizationService.instance.clearActiveWorkspaceContext();
    return _RefreshWorkspaceResult(
      context: null,
      restored: false,
      invitedMembershipVisible: invitedMembershipVisible,
    );
  }

  bool _isMembershipEligible(
    List<WorkspaceMembershipChoice> memberships,
    String membershipId,
  ) {
    for (final membership in memberships) {
      final status = membership.status.trim().toLowerCase();
      if (membership.membershipId == membershipId &&
          membership.businessProfileId.trim().isNotEmpty &&
          (status.isEmpty || status == 'active' || status == 'accepted')) {
        return true;
      }
    }
    return false;
  }

  bool _hasEligibleMembershipForBusinessProfile(
    List<WorkspaceMembershipChoice> memberships,
    String businessProfileId,
  ) {
    final normalizedBusinessProfileId = businessProfileId.trim();
    if (normalizedBusinessProfileId.isEmpty) return false;
    for (final membership in memberships) {
      final status = membership.status.trim().toLowerCase();
      if (membership.businessProfileId == normalizedBusinessProfileId &&
          membership.membershipId.trim().isNotEmpty &&
          (status.isEmpty || status == 'active' || status == 'accepted')) {
        return true;
      }
    }
    return false;
  }

  bool _isValidActiveContext(ActiveWorkspaceContext? context) {
    if (context == null) return false;
    final membershipStatus = context.membershipStatus.trim().toLowerCase();
    return context.currentUserId.trim().isNotEmpty &&
        context.membershipUserId.trim() == context.currentUserId.trim() &&
        context.membershipId.trim().isNotEmpty &&
        context.businessProfileId.trim().isNotEmpty &&
        (membershipStatus == 'active' || membershipStatus == 'accepted');
  }

  String? _restorableMembershipId(CanonicalWorkspaceContextResult canonical) {
    final snapshot = canonical.snapshot;
    final context = snapshot?.activeContext;
    if (canonical.status != CanonicalWorkspaceContextStatus.ok ||
        snapshot == null ||
        !_isValidActiveContext(context)) {
      return null;
    }
    final membershipId = snapshot.activeMembershipId.trim();
    if (membershipId.isEmpty) return null;
    return _isMembershipEligible(snapshot.memberships, membershipId)
        ? membershipId
        : null;
  }

  Future<AuthenticatedCurrentUserProfile> _requireCurrentUser() async {
    final user =
        await OrganizationService.instance.fetchAuthenticatedCurrentUserProfile();
    if (user == null ||
        user.id.trim().isEmpty ||
        user.email.trim().isEmpty) {
      throw const OrganizationInvitationException(
        'Your session expired. Please sign in again.',
      );
    }
    return user;
  }

  void _validateInvitationRecipient(
    OrganizationInvitation invitation,
    String currentUserEmail,
  ) {
    final normalizedCurrent = currentUserEmail.trim().toLowerCase();
    final normalizedInvite = invitation.email.trim().toLowerCase();
    if (normalizedCurrent.isEmpty ||
        normalizedInvite.isEmpty ||
        normalizedCurrent != normalizedInvite) {
      throw const OrganizationInvitationException(
        'This invitation was sent to another email account.',
      );
    }
  }

  String _extractMessage(DioException error) {
    final data = error.response?.data;
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
    final status = error.response?.statusCode ?? 0;
    if (status == 401) {
      return 'Your session expired. Please sign in again.';
    }
    if (status == 403) {
      return 'This invitation action is not allowed for the current account.';
    }
    return error.message ?? 'We could not update this invitation right now.';
  }
}

class _RefreshWorkspaceResult {
  final ActiveWorkspaceContext? context;
  final bool restored;
  final bool invitedMembershipVisible;

  const _RefreshWorkspaceResult({
    required this.context,
    required this.restored,
    required this.invitedMembershipVisible,
  });
}

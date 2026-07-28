import 'dart:async';

import 'package:flutter/material.dart';

import '../models/plan.dart';
import '../services/organization_service.dart';
import '../services/push_notification_service.dart';
import '../state/session.dart';
import '../utils/app_colors.dart';
import '../utils/page_transition.dart';
import '../widgets/animated_space_background.dart';
import '../widgets/app_buttons.dart';
import '../widgets/app_cards.dart';
import 'business_profile_wizard_screen.dart';
import 'invite_screen.dart';
import 'login_screen.dart';
import 'role_based_shells.dart';

const Plan _defaultCreateCompanyPlan = Plan(
  id: 'business',
  name: 'Business',
  code: 'business',
  description: 'Team collaboration and premium reporting.',
  monthlyPrice: 29,
  yearlyPrice: 299,
  trialDays: 14,
  maxMembers: 25,
  isBusiness: true,
  features: [
    'Add and manage members',
    'Business reports and exports',
    'Priority support',
  ],
  isPopular: true,
  isActive: true,
  sortOrder: 2,
);

enum WorkspaceAccessViewState {
  noWorkspace,
  pendingInvite,
  restrictedWorkspace,
  sessionExpired,
  workspaceNotActivated,
  accessResolutionError,
}

class WorkspaceAccessScreen extends StatefulWidget {
  final String? message;
  final WorkspaceAccessViewState? state;

  const WorkspaceAccessScreen({super.key, this.message, this.state});

  @override
  State<WorkspaceAccessScreen> createState() => _WorkspaceAccessScreenState();
}

class _WorkspaceAccessScreenState extends State<WorkspaceAccessScreen> {
  final _tokenController = TextEditingController();
  bool _checking = false;
  String? _statusMessage;
  WorkspaceResolveStatus? _lastStatus;
  late WorkspaceAccessViewState _state;

  @override
  void initState() {
    super.initState();
    final hasPendingInvite =
        Session.instance.pendingInviteToken?.trim().isNotEmpty == true;
    _state =
        widget.state ??
        (hasPendingInvite
            ? WorkspaceAccessViewState.pendingInvite
            : WorkspaceAccessViewState.noWorkspace);
    _statusMessage = widget.message;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _guardAuthenticated();
    });
  }

  void _guardAuthenticated() {
    if (!mounted) return;
    if (Session.instance.isLoggedIn) return;
    debugPrint('[WORKSPACE_ACCESS] authenticated_user_required=true');
    OrganizationService.instance.clearActiveWorkspaceContext();
    Navigator.pushReplacement(
      context,
      fadeSlideRoute(const LoginScreen()),
    );
  }

  @override
  void dispose() {
    _tokenController.dispose();
    super.dispose();
  }

  Future<void> _refreshMembership() async {
    debugPrint('[WorkspaceAccess] refresh requested');
    setState(() => _checking = true);
    try {
      final canonical = await OrganizationService.instance
          .fetchCanonicalWorkspaceContext(forceRefresh: true);
      if (!mounted) return;

      if (canonical.status == CanonicalWorkspaceContextStatus.unauthenticated) {
        setState(() {
          _lastStatus = WorkspaceResolveStatus.unauthenticated;
          _state = WorkspaceAccessViewState.sessionExpired;
          _statusMessage =
              canonical.message ?? 'Your session expired. Sign in again.';
        });
        return;
      }

      if (canonical.status == CanonicalWorkspaceContextStatus.forbidden ||
          canonical.status == CanonicalWorkspaceContextStatus.error) {
        setState(() {
          _lastStatus = canonical.status == CanonicalWorkspaceContextStatus.forbidden
              ? WorkspaceResolveStatus.forbidden
              : WorkspaceResolveStatus.error;
          _state = WorkspaceAccessViewState.accessResolutionError;
          _statusMessage = canonical.message?.trim().isNotEmpty == true
              ? canonical.message!.trim()
              : 'We could not verify workspace access right now. Try again.';
        });
        return;
      }

      final snapshot = canonical.snapshot;
      if (snapshot == null) {
        setState(() {
          _lastStatus = WorkspaceResolveStatus.noMembership;
          _state = WorkspaceAccessViewState.noWorkspace;
          _statusMessage =
              'No active workspace memberships were found for this account.';
        });
        return;
      }

      final activeContext = snapshot.activeContext;
      if (_hasValidActiveContext(activeContext)) {
        final workspaceContext = activeContext!;
        OrganizationService.instance.applyActiveWorkspaceContext(
          workspaceContext,
        );
        if (!mounted) return;
        Navigator.pushReplacement(
          context,
          fadeSlideRoute(RoleShellRouter(initialContext: workspaceContext)),
        );
        return;
      }

      final memberships = _eligibleMemberships(snapshot.memberships);
      if (memberships.isEmpty) {
        OrganizationService.instance.clearActiveWorkspaceContext();
        setState(() {
          _lastStatus = WorkspaceResolveStatus.noMembership;
          _state = WorkspaceAccessViewState.noWorkspace;
          _statusMessage =
              'No active workspace memberships were found for this account.';
        });
        return;
      }

      OrganizationService.instance.clearActiveWorkspaceContext();
      final selected = await showModalBottomSheet<WorkspaceMembershipChoice>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (_) => _WorkspaceAccessMembershipSheet(
          memberships: memberships,
        ),
      );
      if (selected == null || !mounted) return;

      final synced = await OrganizationService.instance.syncWorkspaceSession(
        membershipId: selected.membershipId,
        trigger: 'workspace_access_refresh',
        expectedMembership: selected,
      );
      unawaited(
        PushNotificationService.instance.syncCurrentDevice(
          trigger: 'workspace_switch',
          workspaceContext: synced,
        ),
      );
      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        fadeSlideRoute(RoleShellRouter(initialContext: synced)),
      );
    } on OrganizationServiceException catch (e) {
      if (!mounted) return;
      setState(() {
        _lastStatus = WorkspaceResolveStatus.error;
        _state = WorkspaceAccessViewState.accessResolutionError;
        _statusMessage = e.message;
      });
    } finally {
      if (mounted) {
        setState(() => _checking = false);
      }
    }
  }

  Future<void> _debugWorkspaceLookup() async {
    debugPrint('[WorkspaceAccess] debug workspace lookup started');
    OrganizationService.instance.clearActiveWorkspaceContext();
    final result = await OrganizationService.instance
        .resolveCanonicalActiveWorkspace(forceRefresh: true);
    debugPrint(
      '[WorkspaceAccess] debug result status=${result.status.name} message=${result.message}',
    );
    if (result.status == WorkspaceResolveStatus.forbidden) {
      debugPrint('[WorkspaceAccess] debug classification=403 forbidden');
    } else if (result.status == WorkspaceResolveStatus.unauthenticated) {
      debugPrint('[WorkspaceAccess] debug classification=401 unauthenticated');
    } else if (result.status == WorkspaceResolveStatus.noMembership) {
      debugPrint('[WorkspaceAccess] debug classification=200 empty');
    } else if (result.status == WorkspaceResolveStatus.ok) {
      debugPrint('[WorkspaceAccess] debug classification=200 with membership');
    } else {
      debugPrint('[WorkspaceAccess] debug classification=unexpected_error');
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Workspace diagnostics printed to console.'),
      ),
    );
    debugPrint('[WorkspaceAccess] debug workspace lookup completed');
  }

  bool _hasValidActiveContext(ActiveWorkspaceContext? context) {
    if (context == null) return false;
    return context.currentUserId.trim().isNotEmpty &&
        context.membershipUserId.trim() == context.currentUserId.trim() &&
        context.membershipId.trim().isNotEmpty &&
        context.businessProfileId.trim().isNotEmpty &&
        (context.membershipStatus == 'active' ||
            context.membershipStatus == 'accepted');
  }

  List<WorkspaceMembershipChoice> _eligibleMemberships(
    List<WorkspaceMembershipChoice> memberships,
  ) {
    return memberships
        .where((membership) {
          final status = membership.status.trim().toLowerCase();
          return membership.membershipId.trim().isNotEmpty &&
              membership.businessProfileId.trim().isNotEmpty &&
              (status.isEmpty || status == 'active' || status == 'accepted');
        })
        .toList(growable: false);
  }

  bool get _isNewCompanyMode {
    if (!Session.instance.isLoggedIn) return false;
    return _state == WorkspaceAccessViewState.noWorkspace;
  }

  @override
  Widget build(BuildContext context) {
    final newCompanyMode = _isNewCompanyMode;
    debugPrint(
      newCompanyMode
          ? '[WORKSPACE_ACCESS] mode=new_company'
          : '[WORKSPACE_ACCESS] mode=access_failed',
    );
    debugPrint(
      '[WORKSPACE_ACCESS] create_company_allowed=$newCompanyMode',
    );
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Stack(
        children: [
          const AnimatedSpaceBackground(),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: AppCard(
                padding: const EdgeInsets.all(18),
                child: newCompanyMode
                    ? _buildNewCompanyMode()
                    : _buildAccessFailedMode(),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNewCompanyMode() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Create your company',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w700,
            fontSize: 20,
          ),
        ),
        const SizedBox(height: 8),
        const Text(
          'Set up your company workspace to start using Wellar.',
          style: TextStyle(color: AppColors.textSecondary, height: 1.4),
        ),
        const SizedBox(height: 18),
        PrimaryButton(
          text: 'Create company',
          onPressed: _checking
              ? null
              : () {
                  Navigator.push(
                    context,
                    fadeSlideRoute(
                      const BusinessProfileWizardScreen(
                        plan: _defaultCreateCompanyPlan,
                        billingCycle: 'monthly',
                      ),
                    ),
                  );
                },
        ),
        const SizedBox(height: 22),
        const Divider(color: Colors.white12, height: 1),
        const SizedBox(height: 16),
        const Text(
          'Have an invite code?',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w700,
            fontSize: 14,
          ),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _tokenController,
          decoration: const InputDecoration(hintText: 'Invite code'),
        ),
        const SizedBox(height: 10),
        PrimaryButton(
          text: 'Join with invite',
          onPressed: _checking
              ? null
              : () {
                  final token = _tokenController.text.trim();
                  if (token.isEmpty) return;
                  Navigator.push(
                    context,
                    fadeSlideRoute(InviteScreen(token: token)),
                  );
                },
        ),
        const SizedBox(height: 14),
        SecondaryButton(
          text: 'Use another account',
          onPressed: () {
            OrganizationService.instance.clearActiveWorkspaceContext();
            Navigator.pushReplacement(
              context,
              fadeSlideRoute(const LoginScreen()),
            );
          },
        ),
      ],
    );
  }

  Widget _buildAccessFailedMode() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'We could not verify your company access',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w700,
            fontSize: 20,
            height: 1.25,
          ),
        ),
        const SizedBox(height: 8),
        const Text(
          'Check your connection, then try again.',
          style: TextStyle(color: AppColors.textSecondary, height: 1.4),
        ),
        const SizedBox(height: 18),
        PrimaryButton(
          text: _checking ? 'Checking...' : 'Try again',
          onPressed: _checking ? null : _refreshMembership,
        ),
        const SizedBox(height: 10),
        SecondaryButton(
          text: 'Use another account',
          onPressed: () {
            OrganizationService.instance.clearActiveWorkspaceContext();
            Navigator.pushReplacement(
              context,
              fadeSlideRoute(const LoginScreen()),
            );
          },
        ),
      ],
    );
  }
}

class _WorkspaceAccessMembershipSheet extends StatelessWidget {
  final List<WorkspaceMembershipChoice> memberships;

  const _WorkspaceAccessMembershipSheet({required this.memberships});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Container(
        decoration: const BoxDecoration(
          color: AppColors.background,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.fromLTRB(18, 14, 18, 18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 42,
              height: 4,
              margin: const EdgeInsets.only(bottom: 14),
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(999),
              ),
            ),
            const Text(
              'Choose an organization',
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Select the company you want to activate. Nothing switches until you tap one.',
              style: TextStyle(color: AppColors.textSecondary),
            ),
            const SizedBox(height: 12),
            ...memberships.map(
              (membership) => Card(
                color: AppColors.card,
                margin: const EdgeInsets.only(bottom: 10),
                child: ListTile(
                  title: Text(
                    membership.companyName,
                    style: const TextStyle(color: Colors.white),
                  ),
                  subtitle: Text(
                    membership.departmentName?.trim().isNotEmpty == true
                        ? '${membership.memberRole.toUpperCase()} - ${membership.departmentName!.trim()}'
                        : membership.memberRole.toUpperCase(),
                    style: const TextStyle(color: AppColors.textSecondary),
                  ),
                  trailing: const Icon(
                    Icons.chevron_right_rounded,
                    color: Colors.white70,
                  ),
                  onTap: () => Navigator.of(context).pop(membership),
                ),
              ),
            ),
            const SizedBox(height: 4),
          ],
        ),
      ),
    );
  }
}

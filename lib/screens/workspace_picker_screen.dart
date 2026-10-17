import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/organization_service.dart';
import '../services/workspace_selection_service.dart';
import '../state/app_providers.dart';
import '../theme/app_theme.dart';
import '../widgets/wellar_card.dart';
import 'role_based_shells.dart';

class WorkspacePickerScreen extends ConsumerStatefulWidget {
  const WorkspacePickerScreen({
    super.key,
    required this.memberships,
    this.mandatory = true,
  });

  final List<WorkspaceMembershipChoice> memberships;
  final bool mandatory;

  @override
  ConsumerState<WorkspacePickerScreen> createState() =>
      _WorkspacePickerScreenState();
}

class _WorkspacePickerScreenState extends ConsumerState<WorkspacePickerScreen> {
  String? _selectingMembershipId;
  String? _error;

  ActiveWorkspaceContext? get _activeContext =>
      ref.read(activeWorkspaceContextProvider);

  Future<void> _select(WorkspaceMembershipChoice membership) async {
    if (_selectingMembershipId != null) return;
    setState(() {
      _selectingMembershipId = membership.membershipId;
      _error = null;
    });
    try {
      final current = _activeContext;
      final selectedContext = current?.membershipId == membership.membershipId
          ? current!
          : await OrganizationService.instance.syncWorkspaceSession(
              membershipId: membership.membershipId,
              trigger: 'workspace_picker',
              expectedMembership: membership,
            );
      await WorkspaceSelectionStore.instance.save(
        userId: selectedContext.currentUserId,
        membershipId: membership.membershipId,
      );
      if (!mounted) return;
      _invalidateWorkspaceData();
      ref.read(activeWorkspaceContextProvider.notifier).state = selectedContext;
      Navigator.of(context, rootNavigator: true).pushAndRemoveUntil<void>(
        MaterialPageRoute<void>(
          builder: (_) => RoleShellRouter(initialContext: selectedContext),
        ),
        (_) => false,
      );
    } on OrganizationServiceException catch (error) {
      if (!mounted) return;
      _applyReconciledWorkspace();
      setState(() => _error = error.message);
    } catch (_) {
      if (!mounted) return;
      _applyReconciledWorkspace();
      setState(
        () => _error =
            'Workspace switching failed. The active workspace was refreshed if the server confirmed it.',
      );
    } finally {
      if (mounted) setState(() => _selectingMembershipId = null);
    }
  }

  void _applyReconciledWorkspace() {
    final context = OrganizationService.instance.cachedActiveWorkspaceContext;
    if (context == null) return;
    _invalidateWorkspaceData();
    ref.read(activeWorkspaceContextProvider.notifier).state = context;
  }

  void _invalidateWorkspaceData() {
    ref.read(refreshTickProvider.notifier).state++;
    ref.invalidate(homeDataProvider);
    ref.invalidate(homeScansProvider);
    ref.invalidate(historyProvider);
    ref.invalidate(historyTimelineProvider);
    ref.invalidate(ownerHistoryTimelineProvider);
    ref.invalidate(usersProvider);
    ref.invalidate(sentRequestsProvider);
    ref.invalidate(incomingRequestsProvider);
    ref.invalidate(alertsProvider);
    ref.invalidate(notificationsProvider);
    ref.invalidate(organizationInvitationsProvider);
    ref.invalidate(exportsProvider);
    ref.invalidate(activityEventsProvider);
    ref.invalidate(businessMembersCountProvider);
  }

  @override
  Widget build(BuildContext context) {
    final activeMembershipId = _activeContext?.membershipId;
    return PopScope(
      canPop: !widget.mandatory,
      child: Scaffold(
        backgroundColor: WellarTheme.bg,
        appBar: widget.mandatory
            ? null
            : AppBar(
                backgroundColor: WellarTheme.bg,
                foregroundColor: WellarTheme.text,
                title: const Text('Switch workspace'),
              ),
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  if (widget.mandatory) ...[
                    const SizedBox(height: 42),
                    const Icon(
                      Icons.business_center_outlined,
                      color: WellarTheme.primary,
                      size: 38,
                    ),
                    const SizedBox(height: 18),
                    Text(
                      'Choose a workspace',
                      textAlign: TextAlign.center,
                      style: WellarTheme.heading.copyWith(fontSize: 25),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Select the company and role you want to use.',
                      textAlign: TextAlign.center,
                      style: WellarTheme.body.copyWith(
                        color: WellarTheme.textMuted,
                      ),
                    ),
                    const SizedBox(height: 24),
                  ],
                  if (_error != null) ...[
                    Text(
                      _error!,
                      style: const TextStyle(color: WellarTheme.danger),
                    ),
                    const SizedBox(height: 12),
                  ],
                  for (final membership in widget.memberships) ...[
                    _WorkspaceChoiceCard(
                      membership: membership,
                      isCurrent: membership.membershipId == activeMembershipId,
                      isLoading:
                          membership.membershipId == _selectingMembershipId,
                      disabled: _selectingMembershipId != null,
                      onTap: () => _select(membership),
                    ),
                    const SizedBox(height: 10),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _WorkspaceChoiceCard extends StatelessWidget {
  const _WorkspaceChoiceCard({
    required this.membership,
    required this.isCurrent,
    required this.isLoading,
    required this.disabled,
    required this.onTap,
  });

  final WorkspaceMembershipChoice membership;
  final bool isCurrent;
  final bool isLoading;
  final bool disabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return WellarCard(
      padding: EdgeInsets.zero,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: disabled ? null : onTap,
          borderRadius: BorderRadius.circular(18),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                const Icon(
                  Icons.apartment_outlined,
                  color: WellarTheme.primary,
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        membership.companyName,
                        style: WellarTheme.body.copyWith(
                          color: WellarTheme.text,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _roleLabel(membership.memberRole),
                        style: WellarTheme.caption.copyWith(
                          color: WellarTheme.textMuted,
                        ),
                      ),
                    ],
                  ),
                ),
                if (isLoading)
                  const SizedBox.square(
                    dimension: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                else if (isCurrent)
                  const Icon(Icons.check_circle, color: WellarTheme.primary),
                if (isCurrent && !isLoading) const SizedBox(width: 5),
                if (isCurrent && !isLoading)
                  const Text(
                    'Current',
                    style: TextStyle(color: WellarTheme.primary),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _roleLabel(String role) {
    final normalized = role.trim().toLowerCase();
    if (normalized == 'manger') return 'Manager';
    if (normalized.isEmpty) return 'Member';
    return '${normalized[0].toUpperCase()}${normalized.substring(1)}';
  }
}

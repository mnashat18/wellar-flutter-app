import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/organization_invitation.dart';
import '../state/app_providers.dart';
import '../services/organization_service.dart';
import '../theme/app_theme.dart';
import '../widgets/animated_wellar_card.dart';
import '../widgets/animated_wellar_screen.dart';
import '../widgets/status_chip.dart';
import '../widgets/wellar_button.dart';
import '../widgets/wellar_card.dart';
import '../widgets/wellar_header.dart';

class OrganizationInvitationScreen extends ConsumerStatefulWidget {
  final OrganizationInvitation invitation;

  const OrganizationInvitationScreen({super.key, required this.invitation});

  @override
  ConsumerState<OrganizationInvitationScreen> createState() =>
      _OrganizationInvitationScreenState();
}

class _OrganizationInvitationScreenState
    extends ConsumerState<OrganizationInvitationScreen> {
  bool _accepting = false;
  bool _declining = false;
  String? _errorMessage;

  bool get _busy => _accepting || _declining;

  @override
  Widget build(BuildContext context) {
    final invitation = widget.invitation;
    final date = invitation.sentAt ?? invitation.createdAt;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: AnimatedWellarScreen(
        showBackground: false,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            const WellarHeader(
              title: 'Organization invitation',
              subtitle: 'Review the invitation before you respond.',
            ),
            const SizedBox(height: WellarTheme.sectionGap),
            AnimatedWellarCard(
              delay: const Duration(milliseconds: 40),
              child: WellarCard(
                highlighted: true,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Text(
                            invitation.organizationName,
                            style: const TextStyle(
                              color: WellarTheme.text,
                              fontSize: 20,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        const StatusChip('Pending'),
                      ],
                    ),
                    const SizedBox(height: 10),
                    const Text(
                      'Accepting adds this organization to Switch Organization. It does not intentionally switch you into it automatically.',
                      style: TextStyle(
                        color: WellarTheme.textMuted,
                        height: 1.35,
                      ),
                    ),
                    const SizedBox(height: 16),
                    _detailRow('Role', invitation.roleLabel),
                    _detailRow(
                      'Department',
                      invitation.departmentName?.trim().isNotEmpty == true
                          ? invitation.departmentName!.trim()
                          : 'Unassigned',
                    ),
                    _detailRow('Sent by', invitation.senderLabel),
                    _detailRow('Invited email', invitation.email),
                    if (date != null) _detailRow('Sent', _formatDate(date)),
                  ],
                ),
              ),
            ),
            if (_errorMessage != null && _errorMessage!.trim().isNotEmpty) ...[
              const SizedBox(height: 12),
              AnimatedWellarCard(
                delay: const Duration(milliseconds: 80),
                child: WellarCard(
                  child: Text(
                    _errorMessage!,
                    style: const TextStyle(color: WellarTheme.danger),
                  ),
                ),
              ),
            ],
            const SizedBox(height: 12),
            AnimatedWellarCard(
              delay: const Duration(milliseconds: 120),
              child: WellarCard(
                child: Column(
                  children: [
                    WellarButton.primary(
                      text: _accepting ? 'Accepting...' : 'Accept invitation',
                      onPressed: _busy ? null : _acceptInvitation,
                    ),
                    const SizedBox(height: 10),
                    WellarButton.secondary(
                      text: _declining ? 'Declining...' : 'Decline invitation',
                      onPressed: _busy ? null : _confirmDecline,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _detailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 96,
            child: Text(
              label,
              style: const TextStyle(color: WellarTheme.textMuted),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(color: WellarTheme.text),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _acceptInvitation() async {
    setState(() {
      _accepting = true;
      _errorMessage = null;
    });
    try {
      final result = await ref
          .read(organizationInvitationServiceProvider)
          .acceptInvitation(widget.invitation);
      _applyWorkspaceRefresh(result.activeWorkspaceContext);
      if (!mounted) return;
      Navigator.of(context).pop(result.message);
    } catch (error) {
      if (!mounted) return;
      setState(() => _errorMessage = _readError(error));
    } finally {
      if (mounted) setState(() => _accepting = false);
    }
  }

  Future<void> _confirmDecline() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: WellarTheme.surface,
        title: const Text(
          'Decline invitation?',
          style: TextStyle(color: WellarTheme.text),
        ),
        content: const Text(
          'Declining removes this invitation from your list. You can only join later if the organization sends a new invitation.',
          style: TextStyle(color: WellarTheme.textMuted),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Decline'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() {
      _declining = true;
      _errorMessage = null;
    });
    try {
      final result = await ref
          .read(organizationInvitationServiceProvider)
          .declineInvitation(widget.invitation);
      _applyWorkspaceRefresh(result.activeWorkspaceContext);
      if (!mounted) return;
      Navigator.of(context).pop(result.message);
    } catch (error) {
      if (!mounted) return;
      setState(() => _errorMessage = _readError(error));
    } finally {
      if (mounted) setState(() => _declining = false);
    }
  }

  void _applyWorkspaceRefresh(ActiveWorkspaceContext? workspace) {
    ref.read(activeWorkspaceContextProvider.notifier).state = workspace;
    ref.read(refreshTickProvider.notifier).state++;
    ref.invalidate(organizationInvitationsProvider);
    ref.invalidate(notificationsProvider);
    ref.invalidate(unreadNotificationsProvider);
    ref.invalidate(profileProvider);
    ref.invalidate(usersProvider);
    ref.invalidate(sentRequestsProvider);
    ref.invalidate(incomingRequestsProvider);
  }

  String _readError(Object error) {
    final message = error.toString().trim();
    if (message.isEmpty) {
      return 'We could not update this invitation right now. Please try again.';
    }
    return message;
  }

  String _formatDate(DateTime date) {
    final local = date.toLocal();
    return '${local.day}/${local.month}/${local.year} ${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
  }
}

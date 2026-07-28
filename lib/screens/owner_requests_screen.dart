import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

import '../models/request_item.dart';
import '../services/organization_service.dart';
import '../services/owner_ops_service.dart';
import '../services/request_service.dart';
import '../state/session.dart';
import '../utils/app_colors.dart';
import '../widgets/animated_space_background.dart';
import '../widgets/app_buttons.dart';
import '../widgets/app_cards.dart';
import '../widgets/lux_header.dart';
import '../widgets/state_views.dart';

class OwnerRequestsScreen extends StatefulWidget {
  const OwnerRequestsScreen({super.key});

  @override
  State<OwnerRequestsScreen> createState() => _OwnerRequestsScreenState();
}

class _OwnerRequestsScreenState extends State<OwnerRequestsScreen> {
  late Future<List<RequestItem>> _future;
  bool _createUnavailable = false;
  String? _cancellingRequestId;

  @override
  void initState() {
    super.initState();
    _future = RequestService.instance.fetchOwnerRequests();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Stack(
        children: [
          const AnimatedSpaceBackground(),
          SafeArea(
            child: FutureBuilder<List<RequestItem>>(
              future: _future,
              builder: (context, snap) {
                if (snap.connectionState != ConnectionState.done) {
                  return ListView(
                    padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
                    children: const [
                      LuxHeader(
                        title: 'Requests',
                        subtitle: 'Company scan request operations',
                        icon: Icons.assignment_outlined,
                      ),
                      SizedBox(height: 14),
                      SkeletonList(),
                    ],
                  );
                }
                if (snap.hasError) {
                  final err = snap.error;
                  final forbidden =
                      err is DioException && err.response?.statusCode == 403;
                  return ListView(
                    padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
                    children: [
                      LuxHeader(
                        title: 'Requests',
                        subtitle: 'Company scan request operations',
                        icon: Icons.assignment_outlined,
                        onBack: () => Navigator.pop(context),
                      ),
                      const SizedBox(height: 14),
                      StatusCard(
                        title: 'Unable to load requests',
                        message: forbidden
                            ? 'Requests are unavailable for your role.'
                            : 'Unable to load requests right now.',
                        icon: Icons.warning_amber_rounded,
                        iconColor: AppColors.highRisk,
                        actionText: 'Retry',
                        onAction: () => setState(() {
                          _future = RequestService.instance
                              .fetchOwnerRequests();
                        }),
                      ),
                    ],
                  );
                }
                final data = snap.data ?? const [];
                return RefreshIndicator(
                  color: AppColors.primarySoft,
                  onRefresh: () async {
                    setState(
                      () => _future = RequestService.instance
                          .fetchOwnerRequests(),
                    );
                  },
                  child: ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
                    children: [
                      LuxHeader(
                        title: 'Requests',
                        subtitle: 'Company scan request tracking',
                        icon: Icons.assignment_outlined,
                        onBack: () => Navigator.pop(context),
                        trailing: SecondaryButton(
                          text: 'Send Scan Request',
                          onPressed: _createUnavailable
                              ? null
                              : _openRequestForm,
                        ),
                      ),
                      if (_createUnavailable)
                        const Padding(
                          padding: EdgeInsets.only(top: 10),
                          child: AppCard(
                            padding: EdgeInsets.all(12),
                            child: Text(
                              'Request creation is unavailable for your role right now.',
                              style: TextStyle(
                                color: AppColors.textSecondary,
                                fontSize: 12,
                              ),
                            ),
                          ),
                        ),
                      const SizedBox(height: 14),
                      if (data.isEmpty)
                        const EmptyStateCard(
                          title: 'No scan requests yet.',
                          message:
                              'Create a readiness request to assign a check.',
                        )
                      else
                        ...data.map(_requestCard),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _reload() async {
    if (!mounted) return;
    setState(() {
      _future = RequestService.instance.fetchOwnerRequests();
    });
    await _future;
  }

  Widget _requestCard(RequestItem item) {
    final hasCompletedScan = item.scanId?.trim().isNotEmpty == true;
    final isCompleted = item.displayStatus.trim().toLowerCase() == 'completed';
    final completedAt = item.completedAt;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: AppCard(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Status: ${item.displayStatus}',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Target member: ${item.requestedForName ?? 'Workspace member'}',
              style: const TextStyle(color: AppColors.textSecondary),
            ),
            if ((item.requestedForEmail ?? '').trim().isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                'Email: ${item.requestedForEmail}',
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 12,
                ),
              ),
            ],
            const SizedBox(height: 4),
            Text(
              'Role: ${_roleLabel(item.requestedForRole)}',
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 12,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Department: ${item.departmentId == null ? 'Workspace' : 'Assigned department'}',
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 12,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Requested by: ${item.requestedByUserName ?? 'Workspace admin'}',
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 12,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Requested at: ${_formatDateTime(item.timestamp)}',
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 12,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Due at: ${_formatDateTime(item.dueAt)}',
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 12,
              ),
            ),
            const SizedBox(height: 4),
            if (isCompleted && !hasCompletedScan) ...[
              const SizedBox(height: 4),
              const Text(
                'Assessment processing',
                style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
              ),
            ],
            if (completedAt != null) ...[
              const SizedBox(height: 4),
              Text(
                'Completed at: ${_formatDateTime(completedAt)}',
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 12,
                ),
              ),
            ],
            Text(
              'Completed scan: ${hasCompletedScan ? 'Completed' : (isCompleted ? 'Processing assessment' : 'Pending')}',
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 12,
              ),
            ),
            if (_canCancel(item)) ...[
              const SizedBox(height: 12),
              SolidButton(
                text: _cancellingRequestId == item.id
                    ? 'Cancelling...'
                    : 'Cancel request',
                color: AppColors.highRisk,
                onPressed: _cancellingRequestId == item.id
                    ? null
                    : () => _confirmCancelRequest(item),
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _roleLabel(String? role) {
    final normalized = role?.trim().toLowerCase() ?? '';
    switch (normalized) {
      case 'employee':
        return 'Employee';
      case 'hr':
        return 'HR';
      case 'manager':
        return 'Manager';
      case 'owner':
        return 'Owner';
      default:
        return normalized.isEmpty ? 'Workspace member' : role!.trim();
    }
  }

  String _formatDateTime(DateTime? date) {
    if (date == null) return '-';
    final local = date.toLocal();
    return '${local.day.toString().padLeft(2, '0')}/${local.month.toString().padLeft(2, '0')}/${local.year} ${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
  }

  bool _canCancel(RequestItem item) {
    final currentUserId = Session.instance.userId?.trim() ?? '';
    final requestedByUserId = item.requestedByUserId?.trim() ?? '';
    if (currentUserId.isEmpty || requestedByUserId.isEmpty) return false;
    if (requestedByUserId != currentUserId) return false;
    if (item.scanId?.trim().isNotEmpty == true) return false;
    final status = item.displayStatus.trim().toLowerCase();
    return status == 'pending' || status == 'sent';
  }

  Future<void> _confirmCancelRequest(RequestItem item) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: AppColors.card,
        title: const Text(
          'Cancel this request?',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
        ),
        content: const Text(
          'The recipient will no longer be able to complete this request. This action cannot be undone.',
          style: TextStyle(color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Keep request'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Cancel request'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() {
      _cancellingRequestId = item.id;
    });

    try {
      await RequestService.instance.cancelScanRequest(requestId: item.id);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Request cancelled.')));
      await _reload();
    } on RequestCancellationException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(_cancelErrorMessage(error))));
      await _reload();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Unable to cancel request right now.')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _cancellingRequestId = null;
        });
      }
    }
  }

  String _cancelErrorMessage(RequestCancellationException error) {
    switch (error.failure) {
      case RequestCancellationFailure.unauthenticated:
        return 'Session expired. Please login.';
      case RequestCancellationFailure.forbidden:
        return 'You are not allowed to cancel this request.';
      case RequestCancellationFailure.notFound:
        return 'This request could not be found.';
      case RequestCancellationFailure.conflict:
        return 'This request can no longer be cancelled.';
      case RequestCancellationFailure.network:
        return 'Network error. Please try again.';
      case RequestCancellationFailure.unknown:
        return 'Unable to cancel request right now.';
    }
  }

  Future<void> _openRequestForm() async {
    final members = await OwnerOpsService.instance.fetchWorkforce();
    if (!mounted) return;
    if (members.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No workforce members available.')),
      );
      return;
    }
    final eligibleMembers = members
        .where(
          (member) =>
              member.memberId.trim().isNotEmpty &&
              member.userId.trim().isNotEmpty &&
              member.isActive &&
              member.roleKey.toLowerCase() != 'owner' &&
              !member.requiresLinking,
        )
        .toList();
    if (eligibleMembers.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No eligible members available.')),
      );
      return;
    }
    OwnerMemberView? selected = eligibleMembers.first;
    DateTime? dueAt;
    final workspace = await OrganizationService.instance
        .fetchActiveWorkspaceContext();
    if (!mounted) return;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.card,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setStateModal) {
            return Padding(
              padding: EdgeInsets.only(
                left: 16,
                right: 16,
                top: 16,
                bottom: MediaQuery.of(ctx).viewInsets.bottom + 16,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Send Scan Request',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<OwnerMemberView>(
                    initialValue: selected,
                    dropdownColor: AppColors.cardAlt,
                    items: eligibleMembers
                        .map(
                          (m) => DropdownMenuItem(
                            value: m,
                            child: Text(
                              m.name,
                              style: const TextStyle(color: Colors.white),
                            ),
                          ),
                        )
                        .toList(),
                    onChanged: (v) => setStateModal(() => selected = v),
                    decoration: const InputDecoration(
                      labelText: 'Target employee/member',
                    ),
                  ),
                  const SizedBox(height: 10),
                  SecondaryButton(
                    text: dueAt == null
                        ? 'Set due time'
                        : 'Due: ${dueAt!.toLocal()}',
                    onPressed: () async {
                      final date = await showDatePicker(
                        context: ctx,
                        firstDate: DateTime.now(),
                        lastDate: DateTime.now().add(const Duration(days: 30)),
                        initialDate: DateTime.now(),
                      );
                      if (date != null) {
                        setStateModal(() => dueAt = date);
                      }
                    },
                  ),
                  const SizedBox(height: 12),
                  SolidButton(
                    text: 'Submit',
                    color: AppColors.primarySoft,
                    onPressed: () async {
                      try {
                        await RequestService.instance.createPersonalScanRequest(
                          businessProfileId: workspace?.businessProfileId ?? '',
                          targetMemberId: selected!.memberId,
                          dueAt: dueAt,
                        );
                        if (!mounted) return;
                        Navigator.pop(ctx);
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Scan request sent.')),
                        );
                        await _reload();
                      } on RequestCreateException {
                        if (!mounted) return;
                        setState(() => _createUnavailable = true);
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text(
                              'Unable to send scan request right now.',
                            ),
                          ),
                        );
                      } catch (_) {
                        if (!mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text(
                              'Unable to send scan request right now.',
                            ),
                          ),
                        );
                      }
                    },
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}

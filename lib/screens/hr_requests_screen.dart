import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/request_item.dart';
import '../services/hr_ops_service.dart';
import '../services/organization_service.dart';
import '../services/request_service.dart';
import '../state/app_providers.dart';
import '../state/session.dart';
import '../utils/app_colors.dart';
import '../widgets/animated_space_background.dart';
import '../widgets/app_buttons.dart';
import '../widgets/app_cards.dart';
import '../widgets/lux_header.dart';
import '../widgets/state_views.dart';
import '../widgets/scan_request_action_card.dart';
import 'scan_flow_impl_normalized.dart';
import 'scan_request_details_screen.dart';
import '../utils/page_transition.dart';

class HrRequestsScreen extends ConsumerStatefulWidget {
  const HrRequestsScreen({super.key});

  @override
  ConsumerState<HrRequestsScreen> createState() => _HrRequestsScreenState();
}

class _HrRequestsScreenState extends ConsumerState<HrRequestsScreen> {
  late Future<List<RequestItem>> _future;
  String? _cancellingRequestId;
  ProviderSubscription<int>? _refreshSubscription;

  @override
  void initState() {
    super.initState();
    _future = RequestService.instance.fetchHrRequests();
    _refreshSubscription = ref.listenManual<int>(refreshTickProvider, (_, __) {
      if (!mounted) return;
      _reload();
    });
  }

  @override
  void dispose() {
    _refreshSubscription?.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final workspace = ref.watch(activeWorkspaceContextProvider);
    final membershipId = workspace?.membershipId.trim() ?? '';
    final currentUserId = Session.instance.userId?.trim() ?? '';
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
                        title: 'HR Requests',
                        subtitle: 'Scan request operations',
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
                        title: 'HR Requests',
                        subtitle: 'Scan request operations',
                        icon: Icons.assignment_outlined,
                        onBack: () => Navigator.pop(context),
                      ),
                      const SizedBox(height: 14),
                      StatusCard(
                        title: 'Unable to load scan requests',
                        message: forbidden
                            ? 'Scan request data is unavailable for your role.'
                            : 'Unable to load scan requests right now.',
                        icon: Icons.warning_amber_rounded,
                        iconColor: AppColors.highRisk,
                        actionText: 'Retry',
                        onAction: () => setState(() {
                          _future = RequestService.instance.fetchHrRequests();
                        }),
                      ),
                    ],
                  );
                }

                final data = snap.data ?? const [];
                return RefreshIndicator(
                  color: AppColors.primarySoft,
                  onRefresh: _reload,
                  child: ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
                    children: [
                      LuxHeader(
                        title: 'HR Requests',
                        subtitle: 'Manage workforce scan requests',
                        icon: Icons.assignment_outlined,
                        onBack: () => Navigator.pop(context),
                        trailing: SecondaryButton(
                          text: 'Send Scan Request',
                          onPressed: _openRequestForm,
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
                        ...data.map(
                          (item) => _requestCard(
                            item,
                            currentUserId: currentUserId,
                            membershipId: membershipId,
                          ),
                        ),
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

  Widget _requestCard(
    RequestItem item, {
    required String currentUserId,
    required String membershipId,
  }) {
    final assignedToYou = item.isAssignedToCurrentUser(
      currentUserId: currentUserId,
      currentMembershipId: membershipId,
    );
    final canStart = assignedToYou && item.isActionableCanonical;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ScanRequestActionCard(
            key: ValueKey(item.id),
            item: item,
            scope: assignedToYou
                ? ScanRequestCardScope.personal
                : ScanRequestCardScope.organization,
            canStartScan: canStart,
            onStartScan: canStart
                ? () => Navigator.push(
                    context,
                    fadeSlideRoute(
                      ScanFlowScreen(requestId: item.id, forceCompletion: true),
                    ),
                  )
                : null,
            onViewDetails: () => Navigator.push(
              context,
              fadeSlideRoute(
                ScanRequestDetailsScreen(item: item, canStartScan: canStart),
              ),
            ),
          ),
          if (_canCancel(item)) ...[
            const SizedBox(height: 10),
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
    );
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

  Future<void> _reload() async {
    if (!mounted) return;
    setState(() {
      _future = RequestService.instance.fetchHrRequests();
    });
    await _future;
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
      setState(() {
        _future = RequestService.instance.fetchHrRequests();
      });
    } on RequestCancellationException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(_cancelErrorMessage(error))));
      setState(() {
        _future = RequestService.instance.fetchHrRequests();
      });
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
    final members = await HrOpsService.instance.fetchWorkforce();
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
    HrMemberView? selected = eligibleMembers.first;
    DateTime? dueAt;
    final workspace = await OrganizationService.instance
        .fetchActiveWorkspaceContext();
    if (!mounted) return;
    var submitting = false;
    String? submitError;
    var dismissed = false;

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
                  DropdownButtonFormField<HrMemberView>(
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
                  if (submitError != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      submitError!,
                      style: const TextStyle(
                        color: AppColors.highRisk,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                  const SizedBox(height: 12),
                  SolidButton(
                    text: submitting ? 'Sending...' : 'Submit',
                    color: AppColors.primarySoft,
                    onPressed: submitting
                        ? null
                        : () async {
                            if (selected == null) return;
                            setStateModal(() {
                              submitting = true;
                              submitError = null;
                            });
                            try {
                              await RequestService.instance
                                  .createPersonalScanRequest(
                                    businessProfileId:
                                        workspace?.businessProfileId ?? '',
                                    targetMemberId: selected!.memberId,
                                    dueAt: dueAt,
                                  );
                              if (!mounted) return;
                              dismissed = true;
                              Navigator.pop(ctx);
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('Scan request sent.'),
                                ),
                              );
                              await _reload();
                            } on RequestCreateException catch (error) {
                              if (!mounted) return;
                              setStateModal(() {
                                submitError = error.message;
                              });
                            } catch (_) {
                              if (!mounted) return;
                              setStateModal(() {
                                submitError =
                                    'Unable to send scan request right now.';
                              });
                            } finally {
                              if (mounted && !dismissed) {
                                setStateModal(() {
                                  submitting = false;
                                });
                              }
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

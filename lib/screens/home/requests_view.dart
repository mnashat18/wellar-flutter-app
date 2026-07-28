import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/request_item.dart';
import '../../services/request_service.dart';
import '../../state/app_providers.dart';
import '../../utils/app_colors.dart';
import '../../utils/page_transition.dart';
import '../../widgets/app_buttons.dart';
import '../../widgets/app_cards.dart';
import '../../widgets/state_views.dart';
import '../scan_flow_impl_normalized.dart';

class RequestsHomeView extends StatelessWidget {
  const RequestsHomeView({super.key});

  @override
  Widget build(BuildContext context) {
    return const _RequestsView();
  }
}

class _RequestsView extends ConsumerStatefulWidget {
  const _RequestsView();

  @override
  ConsumerState<_RequestsView> createState() => _RequestsViewState();
}

class _RequestsViewState extends ConsumerState<_RequestsView> {
  bool _updating = false;
  static const Duration _pollInterval = Duration(seconds: 1);
  Timer? _pollTimer;
  ProviderSubscription<AsyncValue<List<RequestItem>>>? _requestsSub;
  final Map<String, String> _statusOverrides = {};
  final Set<String> _notifiedRequestIds = {};

  @override
  void initState() {
    super.initState();
    _startPolling();
    _requestsSub = ref.listenManual<AsyncValue<List<RequestItem>>>(
      incomingRequestsProvider,
      (_, next) {
        next.whenData((items) {
          _syncRequestNotifications(items);
          _pruneOverrides(items);
        });
      },
    );
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _requestsSub?.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final requestsAsync = ref.watch(incomingRequestsProvider);
    return RefreshIndicator(
      color: AppColors.primarySoft,
      onRefresh: () async {
        ref.invalidate(incomingRequestsProvider);
        await ref.read(incomingRequestsProvider.future);
      },
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Scan Requests',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 22,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      SizedBox(height: 6),
                      Text(
                        'Assigned scan requests',
                        style: TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            requestsAsync.when(
              loading: () => const InlineLoadingCard(
                message: 'Loading scan requests...',
              ),
              error: (error, _) {
                final message = error is RequestPermissionException
                    ? error.message
                    : 'Failed to load requests.';
                return StatusCard(
                  title: 'Unable to load requests',
                  message: message,
                  icon: Icons.warning_amber_rounded,
                  iconColor: AppColors.highRisk,
                  actionText: 'Retry',
                  onAction: () {
                    ref.invalidate(incomingRequestsProvider);
                  },
                );
              },
              data: (requests) {
                final display = _applyOverrides(requests);
                return RequestsView(
                  requests: display,
                  isUpdating: _updating,
                  onAction: _handleAction,
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _handleAction(RequestItem item, RequestAction action) async {
    if (_updating) return;
    setState(() => _updating = true);
    if (action == RequestAction.startScan) {
      final requestId = item.id;
      if (mounted) {
        setState(() => _updating = false);
        Navigator.push(
          context,
          fadeSlideRoute(
            ScanFlowScreen(requestId: item.id, forceCompletion: true),
          ),
        ).then((_) {
          if (!mounted) return;
          _setOverride(requestId, 'Approved');
          ref.invalidate(incomingRequestsProvider);
          ref.invalidate(sentRequestsProvider);
          ref.invalidate(notificationsProvider);
          ref.invalidate(unreadNotificationsProvider);
        });
      }
      return;
    }

    final status = action == RequestAction.deny ? 'Denied' : 'Delayed';
    _setOverride(item.id, status);
    try {
      await RequestService.instance.updateRequestStatus(
        requestId: item.id,
        responseStatus: status,
      );
      if (mounted) {
        _showSnack(
          action == RequestAction.deny ? 'Request denied' : 'Request delayed',
        );
        ref.invalidate(incomingRequestsProvider);
        ref.invalidate(sentRequestsProvider);
        ref.invalidate(notificationsProvider);
        ref.invalidate(unreadNotificationsProvider);
      }
    } catch (_) {
      _clearOverride(item.id);
      if (mounted) {
        _showDialog(
          title: 'Update failed',
          message: 'Unable to update request status.',
        );
      }
    } finally {
      if (mounted) setState(() => _updating = false);
    }
  }

  void _startPolling() {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(_pollInterval, (_) {
      if (!mounted) return;
      ref.invalidate(incomingRequestsProvider);
    });
  }

  List<RequestItem> _applyOverrides(List<RequestItem> items) {
    if (_statusOverrides.isEmpty) return items;
    return items.map((item) {
      final override = _statusOverrides[item.id];
      if (override == null || override.isEmpty) return item;
      return item.copyWith(responseStatus: override);
    }).toList();
  }

  void _setOverride(String requestId, String status) {
    final current = _statusOverrides[requestId];
    if (current == status) return;
    _statusOverrides[requestId] = status;
    if (mounted) setState(() {});
  }

  void _clearOverride(String requestId) {
    if (_statusOverrides.remove(requestId) == null) return;
    if (mounted) setState(() {});
  }

  void _pruneOverrides(List<RequestItem> items) {
    if (_statusOverrides.isEmpty) return;
    var changed = false;
    for (final item in items) {
      final override = _statusOverrides[item.id];
      if (override == null) continue;
      if (item.displayStatus.toLowerCase() == override.toLowerCase()) {
        _statusOverrides.remove(item.id);
        changed = true;
      }
    }
    if (changed && mounted) setState(() {});
  }

  void _syncRequestNotifications(List<RequestItem> items) {
    if (items.isEmpty) return;
    for (final item in items) {
      final requestId = item.id.trim();
      if (requestId.isEmpty) continue;
      _notifiedRequestIds.add(requestId);
    }
  }

  void _showSnack(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: AppColors.cardAlt,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _showDialog({required String title, required String message}) {
    showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: Text(
          title,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w700,
          ),
        ),
        content: Text(
          message,
          style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text(
              'OK',
              style: TextStyle(
                color: AppColors.primarySoft,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

enum RequestAction { startScan, delay, deny }

class RequestsView extends StatelessWidget {
  final List<RequestItem> requests;
  final bool isUpdating;
  final void Function(RequestItem item, RequestAction action) onAction;
  final String? highlightId;
  final GlobalKey? highlightKey;

  const RequestsView({
    super.key,
    required this.requests,
    required this.isUpdating,
    required this.onAction,
    this.highlightId,
    this.highlightKey,
  });

  @override
  Widget build(BuildContext context) {
    if (requests.isEmpty) {
      return const EmptyStateCard(
        title: 'No assigned scan requests yet',
        message: 'Requests from your owner or HR will appear here.',
      );
    }
    return Column(children: _buildCards());
  }

  List<Widget> _buildCards() {
    final items = <Widget>[];
    final target = highlightId?.trim();
    var used = false;
    for (final item in requests) {
      final shouldHighlight = !used && target != null && item.id == target;
      if (shouldHighlight) {
        used = true;
      }
      Widget card = _RequestCard(
        item: item,
        isUpdating: isUpdating,
        emphasize: shouldHighlight,
        onAction: onAction,
      );
      if (shouldHighlight) {
        final wrapped = _RequestHighlightFrame(child: card);
        card = highlightKey != null
            ? KeyedSubtree(key: highlightKey, child: wrapped)
            : wrapped;
      }
      items.add(
        Padding(padding: const EdgeInsets.only(bottom: 12), child: card),
      );
    }
    return items;
  }
}

class _RequestCard extends StatelessWidget {
  final RequestItem item;
  final bool isUpdating;
  final bool emphasize;
  final void Function(RequestItem item, RequestAction action) onAction;

  const _RequestCard({
    required this.item,
    required this.isUpdating,
    this.emphasize = false,
    required this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    final status = item.displayStatus;
    final statusColor = _statusColor(status);
    final normalized = status.toLowerCase();
    final hasCompletedScan = (item.scanId ?? '').trim().isNotEmpty;
    final isCompleted = hasCompletedScan || normalized == 'completed';
    final dueAt = item.dueAt;
    final isOverdue = !isCompleted &&
        dueAt != null &&
        dueAt.toUtc().isBefore(DateTime.now().toUtc());
    final requestType = (item.requiredState ?? 'pre_shift').trim();
    final requestedBy = (item.requestedByUserName ?? item.requestedByUserId ?? '-').trim();
    final department = (item.departmentId ?? '-').trim();
    return AppCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: statusColor.withValues(alpha: 0.4),
                  ),
                ),
                child: Icon(
                  Icons.assignment_turned_in_outlined,
                  color: statusColor,
                  size: 18,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Readiness check request',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: statusColor.withValues(alpha: 0.45)),
                ),
                child: Text(
                  isOverdue ? 'Overdue' : (isCompleted ? 'Completed' : status),
                  style: TextStyle(
                    color: statusColor,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Request type: $requestType',
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Requested by: $requestedBy',
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Department: $department',
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Requested at: ${item.timestamp?.toLocal().toString() ?? '-'}',
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Due at: ${item.dueAt?.toLocal().toString() ?? '-'}',
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 12,
            ),
          ),
          if (hasCompletedScan) ...[
            const SizedBox(height: 4),
            Text(
              'Completed scan: ${item.scanId}',
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 12,
              ),
            ),
          ],
          const SizedBox(height: 12),
          if (emphasize) ...[
            Row(
              children: const [
                Icon(Icons.bolt, color: AppColors.accentGold, size: 16),
                SizedBox(width: 6),
                Text(
                  'Status updated',
                  style: TextStyle(
                    color: AppColors.accentGold,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
          ],
          if (!isCompleted) ...[
            SolidButton(
              text: 'Start Pre-Shift Scan',
              color: AppColors.primary,
              onPressed: isUpdating
                  ? null
                  : () => onAction(item, RequestAction.startScan),
            ),
            const SizedBox(height: 8),
            SolidButton(
              text: 'Delay',
              color: AppColors.elevated,
              onPressed: isUpdating
                  ? null
                  : () => onAction(item, RequestAction.delay),
            ),
            const SizedBox(height: 8),
            SolidButton(
              text: 'Deny',
              color: AppColors.highRisk,
              onPressed: isUpdating
                  ? null
                  : () => onAction(item, RequestAction.deny),
            ),
          ] else ...[
            SolidButton(
              text: 'Completed',
              color: AppColors.stable,
              onPressed: null,
            ),
          ],
        ],
      ),
    );
  }

  Color _statusColor(String status) {
    switch (status.toLowerCase()) {
      case 'approved':
        return AppColors.stable;
      case 'completed':
        return AppColors.stable;
      case 'denied':
        return AppColors.highRisk;
      case 'delayed':
        return AppColors.elevated;
      case 'overdue':
        return AppColors.highRisk;
      case 'pending':
        return AppColors.lowFocus;
      default:
        return AppColors.textSecondary;
    }
  }
}

class _RequestHighlightFrame extends StatefulWidget {
  final Widget child;

  const _RequestHighlightFrame({required this.child});

  @override
  State<_RequestHighlightFrame> createState() => _RequestHighlightFrameState();
}

class _RequestHighlightFrameState extends State<_RequestHighlightFrame>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final t = Curves.easeInOut.transform(_controller.value);
        final border = 1.6 + 2.0 * t;
        final glow = 0.18 + 0.35 * t;
        return Container(
          padding: const EdgeInsets.all(2),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: AppColors.accentGold.withValues(alpha: 0.75 + 0.2 * t),
              width: border,
            ),
            boxShadow: [
              BoxShadow(
                color: AppColors.accentGold.withValues(alpha: glow),
                blurRadius: 18 + 14 * t,
                spreadRadius: 1 + 2 * t,
              ),
            ],
          ),
          child: widget.child,
        );
      },
    );
  }
}


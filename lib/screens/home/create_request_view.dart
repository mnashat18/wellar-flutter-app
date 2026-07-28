import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/request_item.dart';
import '../../services/organization_service.dart';
import '../../services/owner_ops_service.dart';
import '../../services/request_service.dart';
import '../../state/app_providers.dart';
import '../../utils/app_colors.dart';
import '../../utils/page_transition.dart';
import '../../widgets/app_buttons.dart';
import '../../widgets/app_cards.dart';
import '../../widgets/state_views.dart';
import '../scan_flow_impl_normalized.dart';
import 'requests_view.dart';

class CreateRequestView extends StatelessWidget {
  const CreateRequestView({super.key});

  @override
  Widget build(BuildContext context) {
    return const _CreateRequestView();
  }
}

class _CreateRequestView extends ConsumerStatefulWidget {
  const _CreateRequestView();

  @override
  ConsumerState<_CreateRequestView> createState() => _CreateRequestViewState();
}

class _CreateRequestViewState extends ConsumerState<_CreateRequestView> {
  static const Duration _pollInterval = Duration(seconds: 1);

  final _recipientController = TextEditingController();
  static const List<String> _memberRoles = ['Member', 'Manager', 'Admin'];
  static const List<String> _requiredStates = [
    'Stable',
    'Readiness Concern',
    'Action Required',
  ];

  String _selectedRole = _memberRoles.first;
  String _selectedRequiredState = _requiredStates.first;
  bool _submitting = false;
  String? _error;
  bool _incomingUpdating = false;
  Timer? _pollTimer;
  ProviderSubscription<AsyncValue<List<RequestItem>>>? _incomingSub;
  final Map<String, String> _incomingStatusOverrides = {};

  @override
  void initState() {
    super.initState();
    _incomingSub = ref.listenManual<AsyncValue<List<RequestItem>>>(
      incomingRequestsProvider,
      (_, next) {
        next.whenData(_pruneIncomingOverrides);
      },
    );
    _startPolling();
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _incomingSub?.close();
    _recipientController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      color: AppColors.primarySoft,
      onRefresh: _refreshData,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: const [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Create & Requests',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 22,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      SizedBox(height: 6),
                      Text(
                        'Create readiness check requests and review incoming actions.',
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
            _buildCreateCard(),
            const SizedBox(height: 16),
            _buildIncomingRequestsCard(),
          ],
        ),
      ),
    );
  }

  bool _looksLikeEmail(String value) {
    final exp = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');
    return exp.hasMatch(value);
  }

  Widget _buildCreateCard() {
    return AppCard(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Create Scan Request',
            style: TextStyle(
              color: Colors.white,
              fontSize: 24,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Send by email and choose role + required state.',
            style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              const Text(
                'Recipient Email',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: AppColors.backgroundAlt,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.white12),
            ),
            child: TextField(
              controller: _recipientController,
              keyboardType: TextInputType.emailAddress,
              textInputAction: TextInputAction.done,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(
                border: InputBorder.none,
                hintText: 'name@email.com',
                hintStyle: TextStyle(color: AppColors.textSecondary),
              ),
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Backend flow resolves the user and sets all relations.',
            style: TextStyle(color: AppColors.textSecondary, fontSize: 11),
          ),
          const SizedBox(height: 14),
          _buildDropdownField(
            label: 'Member Role',
            value: _selectedRole,
            items: _memberRoles,
            onChanged: (value) {
              if (value == null) return;
              setState(() => _selectedRole = value);
            },
          ),
          const SizedBox(height: 12),
          _buildDropdownField(
            label: 'Required State',
            value: _selectedRequiredState,
            items: _requiredStates,
            onChanged: (value) {
              if (value == null) return;
              setState(() => _selectedRequiredState = value);
            },
          ),
          if (_error != null) ...[
            const SizedBox(height: 10),
            Text(
              _error!,
              style: const TextStyle(
                color: AppColors.highRisk,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
          const SizedBox(height: 16),
          PrimaryButton(
            text: 'Send Request',
            icon: Icons.send,
            isLoading: _submitting,
            onPressed: _submitting ? null : _submit,
          ),
        ],
      ),
    );
  }

  Widget _buildDropdownField({
    required String label,
    required String value,
    required List<String> items,
    required ValueChanged<String?> onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: AppColors.backgroundAlt,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.white12),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: value,
              dropdownColor: AppColors.card,
              isExpanded: true,
              iconEnabledColor: Colors.white70,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w600,
              ),
              items: items
                  .map(
                    (item) => DropdownMenuItem<String>(
                      value: item,
                      child: Text(item),
                    ),
                  )
                  .toList(),
              onChanged: onChanged,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildIncomingRequestsCard() {
    return AppCard(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Scan Requests',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.refresh, color: Colors.white70),
                onPressed: () {
                  ref.invalidate(incomingRequestsProvider);
                },
              ),
            ],
          ),
          const SizedBox(height: 6),
          const Text(
            'Review assigned readiness check requests and update status.',
            style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
          ),
          const SizedBox(height: 12),
          ref
              .watch(incomingRequestsProvider)
              .when(
                loading: () => const InlineLoadingCard(
                  message: 'Loading incoming requests...',
                ),
                error: (error, _) {
                  final message = error is RequestPermissionException
                      ? error.message
                      : 'Failed to load requests.';
                  return StatusCard(
                    title: 'Unable to load incoming requests',
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
                  final display = _applyIncomingOverrides(requests);
                  return RequestsView(
                    requests: display,
                    isUpdating: _incomingUpdating,
                    onAction: _handleIncomingAction,
                  );
                },
              ),
        ],
      ),
    );
  }

  Future<void> _handleIncomingAction(
    RequestItem item,
    RequestAction action,
  ) async {
    if (_incomingUpdating) return;
    setState(() => _incomingUpdating = true);

    if (action == RequestAction.startScan) {
      final requestId = item.id;
      if (mounted) {
        setState(() => _incomingUpdating = false);
      }
      Navigator.push(
        context,
        fadeSlideRoute(
          ScanFlowScreen(requestId: item.id, forceCompletion: true),
        ),
      ).then((_) {
        if (!mounted) return;
        _setIncomingOverride(requestId, 'Approved');
        _invalidateRequestSources();
      });
      return;
    }

    final status = action == RequestAction.deny ? 'Denied' : 'Delayed';
    _setIncomingOverride(item.id, status);
    try {
      await RequestService.instance.updateRequestStatus(
        requestId: item.id,
        responseStatus: status,
      );
      if (mounted) {
        _showSnack(
          action == RequestAction.deny ? 'Request denied' : 'Request delayed',
        );
        _invalidateRequestSources();
      }
    } catch (_) {
      _clearIncomingOverride(item.id);
      if (mounted) {
        _showDialog(
          title: 'Update failed',
          message: 'Unable to update request status.',
        );
      }
    } finally {
      if (mounted) setState(() => _incomingUpdating = false);
    }
  }

  void _invalidateRequestSources() {
    ref.invalidate(incomingRequestsProvider);
    ref.invalidate(sentRequestsProvider);
    ref.invalidate(notificationsProvider);
    ref.invalidate(unreadNotificationsProvider);
  }

  List<RequestItem> _applyIncomingOverrides(List<RequestItem> items) {
    if (_incomingStatusOverrides.isEmpty) return items;
    return items.map((item) {
      final override = _incomingStatusOverrides[item.id];
      if (override == null || override.isEmpty) return item;
      return item.copyWith(responseStatus: override);
    }).toList();
  }

  void _setIncomingOverride(String requestId, String status) {
    final current = _incomingStatusOverrides[requestId];
    if (current == status) return;
    _incomingStatusOverrides[requestId] = status;
    if (mounted) setState(() {});
  }

  void _clearIncomingOverride(String requestId) {
    if (_incomingStatusOverrides.remove(requestId) == null) return;
    if (mounted) setState(() {});
  }

  void _pruneIncomingOverrides(List<RequestItem> items) {
    if (_incomingStatusOverrides.isEmpty) return;
    var changed = false;
    for (final item in items) {
      final override = _incomingStatusOverrides[item.id];
      if (override == null) continue;
      if (item.displayStatus.toLowerCase() == override.toLowerCase()) {
        _incomingStatusOverrides.remove(item.id);
        changed = true;
      }
    }
    if (changed && mounted) setState(() {});
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

  Future<void> _refreshData() async {
    ref.invalidate(incomingRequestsProvider);
    try {
      await ref.read(incomingRequestsProvider.future);
    } catch (_) {
      // best-effort
    }
  }

  void _startPolling() {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(_pollInterval, (_) {
      if (!mounted) return;
      ref.invalidate(incomingRequestsProvider);
    });
  }

  Future<void> _submit() async {
    final recipient = _recipientController.text.trim().toLowerCase();
    if (recipient.isEmpty) {
      setState(() => _error = 'Recipient email is required.');
      return;
    }
    if (!_looksLikeEmail(recipient)) {
      setState(() => _error = 'Enter a valid email address.');
      return;
    }
    setState(() {
      _submitting = true;
      _error = null;
    });

    try {
      final members = await OwnerOpsService.instance.fetchWorkforce();
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
      final target = eligibleMembers
          .where((m) => m.email.trim().toLowerCase() == recipient)
          .toList();
      if (target.isEmpty) {
        if (!mounted) return;
        _showDialog(
          title: 'Request failed',
          message: 'Recipient employee was not found in this workspace.',
        );
        return;
      }
      final workspace = await OrganizationService.instance.fetchActiveWorkspaceContext();
      if (workspace == null || workspace.businessProfileId.trim().isEmpty) {
        if (!mounted) return;
        _showDialog(
          title: 'Request failed',
          message: 'Workspace context is unavailable right now.',
        );
        return;
      }
      await RequestService.instance.createPersonalScanRequest(
        businessProfileId: workspace.businessProfileId,
        targetMemberId: target.first.memberId,
        dueAt: null,
      );

      ref.invalidate(sentRequestsProvider);

      if (!mounted) return;
      setState(() => _recipientController.clear());
      _showDialog(title: 'Request sent', message: 'Scan request sent.');
    } on UserNotFoundException {
      if (mounted) {
        _showDialog(
          title: 'Request failed',
          message: 'Recipient account was not found.',
        );
      }
    } on RequestPermissionException catch (e) {
      if (mounted) {
        _showDialog(title: 'Request failed', message: e.message);
      }
    } on RequestCreateException catch (e) {
      if (mounted) {
        _showDialog(title: 'Request failed', message: e.message);
      }
    } catch (_) {
      if (mounted) {
        _showDialog(
          title: 'Request failed',
          message: 'Unable to send scan request right now.',
        );
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
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


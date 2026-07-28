import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../i18n/tr.dart';
import '../models/request_item.dart';
import '../state/app_providers.dart';
import '../state/session.dart';
import '../theme/app_theme.dart';
import '../utils/page_transition.dart';
import '../widgets/animated_wellar_screen.dart';
import '../widgets/readiness_chip.dart';
import '../widgets/wellar_button.dart';
import '../widgets/wellar_card.dart';
import '../widgets/wellar_header.dart';
import 'scan_details_screen.dart';
import 'scan_flow_impl_normalized.dart';

class ScanRequestDetailsScreen extends ConsumerWidget {
  final RequestItem item;
  final bool canStartScan;

  const ScanRequestDetailsScreen({
    super.key,
    required this.item,
    this.canStartScan = false,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lang = ref.watch(appLanguageControllerProvider).language;
    final status = item.displayStatus.toLowerCase();
    final isPending =
        status == 'pending' || status == 'requested' || status == 'assigned';
    final isCompleted = status == 'completed' || item.scanId != null;
    final hasCompletedScan = item.scanId?.trim().isNotEmpty == true;
    final isCompletedProcessing = isCompleted && !hasCompletedScan;
    final workspace = ref.watch(activeWorkspaceContextProvider);
    final effectiveCanStartScan =
        canStartScan ||
        (item.isAssignedToCurrentUser(
              currentUserId: Session.instance.userId,
              currentMembershipId: workspace?.membershipId,
            ) &&
            isPending);
    return Scaffold(
      backgroundColor: WellarTheme.bg,
      body: AnimatedWellarScreen(
        child: ListView(
          children: [
            Row(
              children: [
                IconButton(
                  onPressed: () => Navigator.maybePop(context),
                  icon: const Icon(Icons.arrow_back, color: WellarTheme.text),
                ),
                Expanded(
                  child: WellarHeader(
                    title: Tr.t(lang, 'request_details'),
                    subtitle: Tr.t(lang, 'readiness_requests_subtitle'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            WellarCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ReadinessChip(_statusLabel(lang, item)),
                  const SizedBox(height: 10),
                  _kv(Tr.t(lang, 'target_member_label'), item.displayUser),
                  if ((item.requestedForEmail ?? '').trim().isNotEmpty)
                    _kv(Tr.t(lang, 'email'), item.requestedForEmail!.trim()),
                  if ((item.requestedForRole ?? '').trim().isNotEmpty)
                    _kv(Tr.t(lang, 'role'), item.requestedForRole!.trim()),
                  _kv(
                    Tr.t(lang, 'requested_by'),
                    item.requestedByUserName ?? Tr.t(lang, 'workspace_admin'),
                  ),
                  if ((item.requestedByUserEmail ?? '').trim().isNotEmpty)
                    _kv(Tr.t(lang, 'email'), item.requestedByUserEmail!.trim()),
                  _kv(
                    Tr.t(lang, 'requested_at'),
                    item.timestamp?.toLocal().toString() ?? '-',
                  ),
                  _kv(
                    Tr.t(lang, 'due_date'),
                    item.dueAt?.toLocal().toString() ?? '-',
                  ),
                  _kv(Tr.t(lang, 'department'), item.displayDepartment),
                  if (item.requiredMinReadinessLabel != null)
                    _kv(
                      Tr.t(lang, 'required_min_readiness'),
                      item.requiredMinReadinessLabel!,
                    ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            if (effectiveCanStartScan && isPending)
              WellarButton.primary(
                text: Tr.t(lang, 'start_scan'),
                onPressed: () {
                  Navigator.push(
                    context,
                    fadeSlideRoute(
                      ScanFlowScreen(requestId: item.id, forceCompletion: true),
                    ),
                  );
                },
              ),
            if (isCompletedProcessing)
              WellarButton.secondary(
                text: 'Assessment processing',
                onPressed: null,
              ),
            if (isCompleted && hasCompletedScan)
              WellarButton.secondary(
                text: 'View assessment',
                onPressed: () {
                  Navigator.push(
                    context,
                    fadeSlideRoute(ScanDetailsScreen(scanId: item.scanId)),
                  );
                },
              ),
          ],
        ),
      ),
    );
  }

  String _statusLabel(dynamic lang, RequestItem item) {
    final s = item.displayStatus.toLowerCase();
    if (s == 'completed' || item.scanId != null) return Tr.t(lang, 'completed');
    if (item.dueAt != null && item.dueAt!.isBefore(DateTime.now())) {
      return Tr.t(lang, 'overdue');
    }
    return Tr.t(lang, 'pending');
  }

  Widget _kv(String k, String v) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          SizedBox(
            width: 130,
            child: Text(
              k,
              style: const TextStyle(
                color: WellarTheme.textMuted,
                fontSize: 12,
              ),
            ),
          ),
          Expanded(
            child: Text(v, style: const TextStyle(color: WellarTheme.text)),
          ),
        ],
      ),
    );
  }
}

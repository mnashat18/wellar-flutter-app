import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../i18n/tr.dart';
import '../state/session.dart';
import '../models/history_entry.dart';
import '../services/organization_service.dart';
import '../services/manager_ops_service.dart';
import '../utils/page_transition.dart';
import '../state/app_providers.dart';
import '../state/app_language_state.dart';
import 'manager_scan_requests_screen.dart';
import 'notifications_screen.dart';
import 'history_screen.dart';
import 'wellness_check_screen.dart';
import '../theme/app_theme.dart';
import '../widgets/animated_wellar_card.dart';
import '../widgets/animated_wellar_screen.dart';
import '../widgets/page_header_actions.dart';
import '../widgets/status_chip.dart';
import '../widgets/wellar_card.dart';
import '../widgets/wellar_empty_state.dart';
import '../widgets/wellar_error_state.dart';
import '../widgets/wellar_header.dart';
import '../widgets/wellar_metric_card.dart';
import '../widgets/wellar_skeleton_shimmer.dart';
import '../widgets/wellar_button.dart';
import '../widgets/responsive_card_grid.dart';
import '../widgets/readiness_distribution_card.dart';
import '../utils/readiness_distribution.dart';

class ManagerHomeScreen extends ConsumerStatefulWidget {
  const ManagerHomeScreen({super.key});

  @override
  ConsumerState<ManagerHomeScreen> createState() => _ManagerHomeScreenState();
}

class _ManagerHomeScreenState extends ConsumerState<ManagerHomeScreen> {
  late Future<ManagerSnapshot> _snapshotFuture;

  @override
  void initState() {
    super.initState();
    _snapshotFuture = ManagerOpsService.instance.fetchSnapshot();
  }

  void _reloadSnapshot() {
    if (!mounted) return;
    setState(() {
      _snapshotFuture = ManagerOpsService.instance.fetchSnapshot();
    });
  }

  @override
  Widget build(BuildContext context) {
    final profileAsync = ref.watch(profileProvider);
    final workspace = ref.watch(activeWorkspaceContextProvider);
    final lang = ref.watch(appLanguageControllerProvider).language;
    final unreadNotifications = ref.watch(unreadNotificationsProvider);
    final personalHistoryAsync = ref.watch(ownerHistoryTimelineProvider);
    final scope = workspace?.departmentName?.trim() ?? '';
    final workspaceName =
        workspace?.businessProfileName.trim().isNotEmpty == true
        ? workspace!.businessProfileName.trim()
        : Tr.t(lang, 'workspace_default');
    final displayName = _displayIdentity(profileAsync, workspace, lang);

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: AnimatedWellarScreen(
        showBackground: false,
        child: RefreshIndicator(
          onRefresh: () async {
            ref.read(refreshTickProvider.notifier).state++;
            ref.invalidate(profileProvider);
            ref.invalidate(notificationsProvider);
            ref.invalidate(ownerHistoryTimelineProvider);
            _reloadSnapshot();
          },
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            children: [
              WellarHeader(
                title: 'Manager Home',
                subtitle: 'Team readiness and pending actions',
                trailing: Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: PageHeaderActions(
                    unreadCount: unreadNotifications,
                    showAlertsTab: false,
                  ),
                ),
              ),
              const SizedBox(height: WellarTheme.sectionGap),
              AnimatedWellarCard(
                delay: const Duration(milliseconds: 40),
                child: WellarCard(
                  child: profileAsync.when(
                    loading: () => const WellarSkeletonShimmer(height: 72),
                    error: (_, __) => Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          displayName,
                          style: const TextStyle(
                            color: WellarTheme.text,
                            fontSize: 20,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _displayEmail(profileAsync, lang),
                          style: const TextStyle(color: WellarTheme.textMuted),
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          children: [
                            StatusChip(Tr.t(lang, 'manager')),
                            StatusChip(
                              scope.isEmpty ? Tr.t(lang, 'team_scope') : scope,
                            ),
                            StatusChip(workspaceName),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Some profile information is unavailable right now.',
                          style: const TextStyle(
                            color: WellarTheme.textMuted,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                    data: (p) => Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          p.name.isEmpty ? p.email : p.name,
                          style: const TextStyle(
                            color: WellarTheme.text,
                            fontSize: 20,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          p.email,
                          style: const TextStyle(color: WellarTheme.textMuted),
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          children: [
                            StatusChip(Tr.t(lang, 'manager')),
                            StatusChip(
                              scope.isEmpty ? Tr.t(lang, 'team_scope') : scope,
                            ),
                            StatusChip(workspaceName),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: WellarTheme.sectionGap),
              FutureBuilder<ManagerSnapshot>(
                future: _snapshotFuture,
                builder: (context, snap) {
                  if (snap.connectionState != ConnectionState.done) {
                    return const WellarCard(
                      child: WellarSkeletonShimmer(height: 120),
                    );
                  }
                  final d = snap.data;
                  if (snap.hasError ||
                      d == null ||
                      d.teamMembers < 0 ||
                      d.pendingRequests < 0 ||
                      d.checksCompletedToday < 0 ||
                      d.missingChecks < 0 ||
                      d.attentionOutcomes < 0 ||
                      d.openAlerts < 0) {
                    return WellarErrorState(
                      title: Tr.t(lang, 'snapshot_unavailable'),
                      body: Tr.t(lang, 'team_overview_unavailable'),
                      onRetry: _reloadSnapshot,
                    );
                  }
                  return AnimatedWellarCard(
                    delay: const Duration(milliseconds: 90),
                    child: Column(
                      children: [
                        ResponsiveCardGrid(
                          spacing: 10,
                          runSpacing: 10,
                          children: [
                            ResponsiveCardGridItem(
                              child: WellarMetricCard(
                                label: Tr.t(lang, 'team_members'),
                                value: _countLabel(d.teamMembers),
                                icon: Icons.groups_2_outlined,
                              ),
                            ),
                            ResponsiveCardGridItem(
                              child: WellarMetricCard(
                                label: Tr.t(lang, 'pending_requests'),
                                value: _countLabel(d.pendingRequests),
                                icon: Icons.assignment_late_outlined,
                              ),
                            ),
                            ResponsiveCardGridItem(
                              child: WellarMetricCard(
                                label: Tr.t(lang, 'missing_scans'),
                                value: _countLabel(d.missingChecks),
                                icon: Icons.pending_actions_rounded,
                              ),
                            ),
                            ResponsiveCardGridItem(
                              child: WellarMetricCard(
                                label: Tr.t(lang, 'open_alerts'),
                                value: _countLabel(d.openAlerts),
                                icon: Icons.notifications_active_outlined,
                              ),
                            ),
                            ResponsiveCardGridItem(
                              child: WellarMetricCard(
                                label: Tr.t(lang, 'attention_outcomes'),
                                value: _countLabel(d.attentionOutcomes),
                                icon: Icons.warning_amber_rounded,
                              ),
                            ),
                            ResponsiveCardGridItem(
                              child: WellarMetricCard(
                                label: Tr.t(lang, 'notifications'),
                                value: '$unreadNotifications',
                                icon: Icons.notifications_outlined,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        personalHistoryAsync.when(
                          loading: () => const WellarCard(
                            child: WellarSkeletonShimmer(height: 112),
                          ),
                          error: (error, stackTrace) => ReadinessDistributionCard(
                            title: 'My readiness distribution',
                            counts: null,
                            emptyMessage:
                                'No accepted readiness results are available yet.',
                            unavailableMessage:
                                'Readiness distribution is unavailable right now.',
                          ),
                          data: (entries) {
                            final distribution =
                                ReadinessDistributionNormalizer.countsFromHistoryEntries(
                                  entries,
                                );
                            return ReadinessDistributionCard(
                              title: 'My readiness distribution',
                              counts: distribution,
                              emptyMessage:
                                  'No accepted readiness results are available yet.',
                              unavailableMessage:
                                  'Readiness distribution is unavailable right now.',
                            );
                          },
                        ),
                        const SizedBox(height: 10),
                      ],
                    ),
                  );
                },
              ),
              const SizedBox(height: WellarTheme.sectionGap),
              AnimatedWellarCard(
                delay: const Duration(milliseconds: 120),
                child: WellarCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        Tr.t(lang, 'quick_actions'),
                        style: const TextStyle(
                          color: WellarTheme.text,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 10),
                      WellarButton.primary(
                        text: Tr.t(lang, 'start_self_readiness_scan'),
                        onPressed: () => Navigator.push(
                          context,
                          fadeSlideRoute(const WellnessCheckScreen()),
                        ),
                      ),
                      const SizedBox(height: 8),
                      WellarButton.secondary(
                        text: Tr.t(lang, 'my_scan_history'),
                        onPressed: () => Navigator.push(
                          context,
                          fadeSlideRoute(const HistoryScreen()),
                        ),
                      ),
                      const SizedBox(height: 8),
                      WellarButton.secondary(
                        text: Tr.t(lang, 'requests'),
                        onPressed: () => Navigator.push(
                          context,
                          fadeSlideRoute(
                            const ManagerScanRequestsScreen(
                              initialFilter: 'pending',
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        Tr.t(lang, 'self_scan_admin_note'),
                        style: const TextStyle(
                          color: WellarTheme.textMuted,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: WellarTheme.sectionGap),
              AnimatedWellarCard(
                delay: const Duration(milliseconds: 140),
                child: WellarEmptyState(
                  icon: Icons.timeline_outlined,
                  title: Tr.t(lang, 'no_recent_team_activity_yet'),
                  body: Tr.t(lang, 'team_updates_appear_here'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _displayIdentity(
    AsyncValue profileAsync,
    ActiveWorkspaceContext? workspace,
    AppLanguage lang,
  ) {
    return profileAsync.maybeWhen(
      data: (profile) {
        final name = profile.name.trim();
        if (name.isNotEmpty) return name;
        final email = profile.email.trim();
        if (email.isNotEmpty) return email;
        return _sessionIdentityFallback(lang);
      },
      orElse: () => _sessionIdentityFallback(lang),
    );
  }

  String _displayEmail(AsyncValue profileAsync, AppLanguage lang) {
    return profileAsync.maybeWhen(
      data: (profile) {
        final email = profile.email.trim();
        if (email.isNotEmpty) return email;
        return _sessionEmailFallback(lang);
      },
      orElse: () => _sessionEmailFallback(lang),
    );
  }

  String _sessionIdentityFallback(AppLanguage lang) {
    final sessionName = Session.instance.userName?.trim() ?? '';
    if (sessionName.isNotEmpty) return sessionName;
    final sessionEmail = Session.instance.userEmail?.trim() ?? '';
    if (sessionEmail.isNotEmpty) return sessionEmail;
    return Tr.t(lang, 'manager');
  }

  String _sessionEmailFallback(AppLanguage lang) {
    final sessionEmail = Session.instance.userEmail?.trim() ?? '';
    if (sessionEmail.isNotEmpty) return sessionEmail;
    return 'Identity unavailable right now';
  }

  String _countLabel(int count) => count < 0 ? '--' : '$count';

  String _latestReadinessSummary({
    required AppLanguage lang,
    required HistoryEntry entry,
  }) {
    final result = entry.result;
    final summary = result?.readinessSummary?.trim();
    if (summary != null && summary.isNotEmpty) return summary;
    final operational = result?.operationalSummary?.trim();
    if (operational != null && operational.isNotEmpty) return operational;
    final explanation = result?.explanation?.trim();
    if (explanation != null && explanation.isNotEmpty) return explanation;
    final status = entry.status.trim().toLowerCase();
    if (status == 'processing' ||
        status == 'in_progress' ||
        status == 'pending' ||
        status == 'media_ready') {
      return 'Processing assessment';
    }
    if (status == 'failed' ||
        status == 'error' ||
        status == 'rejected' ||
        status == 'cancelled') {
      return 'Assessment could not be completed.';
    }
    if (result != null) {
      final label = entry.readinessLabel.trim();
      if (label.isNotEmpty) return label;
    }
    return 'No completed readiness result yet.';
  }

  String _formatDateTime(DateTime? date) {
    if (date == null) return '-';
    final local = date.toLocal();
    final day = local.day.toString().padLeft(2, '0');
    final month = local.month.toString().padLeft(2, '0');
    final year = local.year.toString();
    final hour = local.hour.toString().padLeft(2, '0');
    final minute = local.minute.toString().padLeft(2, '0');
    return '$day/$month/$year $hour:$minute';
  }
}

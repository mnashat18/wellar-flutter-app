import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../i18n/tr.dart';
import '../utils/page_transition.dart';
import '../services/owner_ops_service.dart';
import '../services/hr_ops_service.dart';
import 'hr_requests_screen.dart';
import 'wellness_check_screen.dart';
import '../state/app_providers.dart';
import '../state/session.dart';
import '../theme/app_theme.dart';
import '../widgets/animated_wellar_card.dart';
import '../widgets/animated_wellar_screen.dart';
import '../widgets/page_header_actions.dart';
import '../widgets/status_chip.dart';
import '../widgets/wellar_card.dart';
import '../widgets/wellar_error_state.dart';
import '../widgets/wellar_header.dart';
import '../widgets/wellar_metric_card.dart';
import '../widgets/wellar_skeleton_shimmer.dart';
import '../widgets/wellar_button.dart';
import '../widgets/responsive_card_grid.dart';
import '../widgets/owner/owner_design_system.dart';
import '../widgets/readiness_distribution_card.dart';
import '../utils/readiness_distribution.dart';
import 'company_readiness_results_screen.dart';
import 'notifications_screen.dart';
import 'history_screen.dart';
import 'profile_screen.dart';

class HrHomeScreen extends ConsumerStatefulWidget {
  const HrHomeScreen({super.key});

  @override
  ConsumerState<HrHomeScreen> createState() => _HrHomeScreenState();
}

class _HrHomeScreenState extends ConsumerState<HrHomeScreen> {
  late Future<_HrHomeSnapshot> _snapshotFuture;

  @override
  void initState() {
    super.initState();
    _snapshotFuture = _loadSnapshot(forceRefresh: false);
  }

  Future<_HrHomeSnapshot> _loadSnapshot({required bool forceRefresh}) async {
    final results = await Future.wait([
      HrOpsService.instance.fetchSnapshot(forceRefresh: forceRefresh),
      OwnerOpsService.instance.fetchWorkspaceReadinessSummary(),
    ]);
    return _HrHomeSnapshot(
      snapshot: results[0] as HrSnapshot,
      readinessSummary: results[1] as WorkspaceReadinessSummary,
    );
  }

  void _reloadSnapshot() {
    if (!mounted) return;
    setState(() {
      _snapshotFuture = _loadSnapshot(forceRefresh: true);
    });
  }

  @override
  Widget build(BuildContext context) {
    final profileAsync = ref.watch(profileProvider);
    final workspace = ref.watch(activeWorkspaceContextProvider);
    final lang = ref.watch(appLanguageControllerProvider).language;
    final unreadNotifications = ref.watch(unreadNotificationsProvider);
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: AnimatedWellarScreen(
        showBackground: false,
        child: RefreshIndicator(
          onRefresh: () async {
            ref.read(refreshTickProvider.notifier).state++;
            ref.invalidate(profileProvider);
            ref.invalidate(notificationsProvider);
            _reloadSnapshot();
          },
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            children: [
              WellarHeader(
                title: 'HR Home',
                subtitle: 'Workforce readiness and requests',
                trailing: Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: PageHeaderActions(
                    unreadCount: unreadNotifications,
                    showAlertsTab: true,
                  ),
                ),
              ),
              const SizedBox(height: WellarTheme.sectionGap),
              AnimatedWellarCard(
                delay: const Duration(milliseconds: 40),
                child: WellarCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      profileAsync.when(
                        loading: () => const WellarSkeletonShimmer(height: 48),
                        error: (_, __) => Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _displayIdentity(profileAsync, lang),
                              style: const TextStyle(
                                color: WellarTheme.text,
                                fontSize: 20,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              _displayEmail(profileAsync),
                              style: const TextStyle(
                                color: WellarTheme.textMuted,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                StatusChip(Tr.t(lang, 'hr')),
                                StatusChip(Tr.t(lang, 'workforce_scope')),
                                StatusChip(
                                  workspace?.businessProfileName.isNotEmpty ==
                                          true
                                      ? workspace!.businessProfileName
                                      : Tr.t(lang, 'workspace_default'),
                                ),
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
                              _displayEmail(profileAsync),
                              style: const TextStyle(
                                color: WellarTheme.textMuted,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                StatusChip(Tr.t(lang, 'hr')),
                                StatusChip(Tr.t(lang, 'workforce_scope')),
                                StatusChip(
                                  workspace?.businessProfileName.isNotEmpty ==
                                          true
                                      ? workspace!.businessProfileName
                                      : Tr.t(lang, 'workspace_default'),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: WellarTheme.sectionGap),
              FutureBuilder<_HrHomeSnapshot>(
                future: _snapshotFuture,
                builder: (context, snap) {
                  if (snap.connectionState != ConnectionState.done) {
                    return const WellarCard(
                      child: WellarSkeletonShimmer(height: 120),
                    );
                  }
                  final bundle = snap.data;
                  final snapshotData = bundle?.snapshot;
                  if (snap.hasError ||
                      snapshotData == null ||
                      snapshotData.workforceTotal < 0 ||
                      snapshotData.activeMembers < 0 ||
                      snapshotData.pendingRequests < 0 ||
                      snapshotData.checksCompletedToday < 0 ||
                      snapshotData.missingChecks < 0 ||
                      snapshotData.attentionOutcomes < 0 ||
                      snapshotData.openAlerts < 0 ||
                      snapshotData.departmentsCount < 0) {
                    return WellarErrorState(
                      title: Tr.t(lang, 'snapshot_unavailable'),
                      body: Tr.t(lang, 'hr_overview_unavailable'),
                      onRetry: _reloadSnapshot,
                    );
                  }
                  final bundleData = bundle!;
                  final readiness = bundleData.readinessSummary;
                  final d = bundleData.snapshot;
                  final compliance = d.activeMembers <= 0
                      ? '--'
                      : '${((d.checksCompletedToday / d.activeMembers) * 100).toStringAsFixed(0)}%';
                  return AnimatedWellarCard(
                    delay: const Duration(milliseconds: 90),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SectionHeader(
                          title: 'Today',
                          subtitle:
                              'Workforce health, requests, and readiness.',
                        ),
                        const SizedBox(height: 10),
                        ResponsiveCardGrid(
                          spacing: 10,
                          runSpacing: 10,
                          children: [
                            ResponsiveCardGridItem(
                              child: WellarMetricCard(
                                label: Tr.t(lang, 'active_members'),
                                value: _countLabel(d.activeMembers),
                                icon: Icons.people_alt_outlined,
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
                          ],
                        ),
                        const SizedBox(height: 18),
                        const SectionHeader(
                          title: 'Primary actions',
                          subtitle:
                              'Valid HR actions for the active workspace.',
                        ),
                        const SizedBox(height: 10),
                        ResponsiveCardGrid(
                          spacing: 10,
                          runSpacing: 10,
                          children: [
                            ResponsiveCardGridItem(
                              child: QuickActionButton(
                                title: 'Send readiness request',
                                icon: Icons.assignment_add,
                                onTap: () => Navigator.push(
                                  context,
                                  fadeSlideRoute(const HrRequestsScreen()),
                                ),
                              ),
                            ),
                            ResponsiveCardGridItem(
                              child: QuickActionButton(
                                title: 'Start my scan',
                                icon: Icons.play_circle_outline_rounded,
                                onTap: () => Navigator.push(
                                  context,
                                  fadeSlideRoute(const WellnessCheckScreen()),
                                ),
                              ),
                            ),
                            ResponsiveCardGridItem.fullWidth(
                              child: QuickActionButton(
                                title: 'My results / scan history',
                                subtitle:
                                    'Review your previous readiness checks',
                                icon: Icons.history_rounded,
                                onTap: () => Navigator.push(
                                  context,
                                  fadeSlideRoute(const HistoryScreen()),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 18),
                        const SectionHeader(
                          title: 'Readiness summary',
                          subtitle:
                              'Organization-wide coverage for the active workspace.',
                        ),
                        const SizedBox(height: 10),
                        OwnerSurfaceCard(
                          child: ResponsiveCardGrid(
                            spacing: 10,
                            runSpacing: 10,
                            children: [
                              ResponsiveCardGridItem(
                                child: _miniStat(
                                  Tr.t(lang, 'compliance_rate'),
                                  compliance,
                                ),
                              ),
                              ResponsiveCardGridItem(
                                child: _miniStat(
                                  Tr.t(lang, 'department_count'),
                                  _countLabel(d.departmentsCount),
                                ),
                              ),
                              ResponsiveCardGridItem.fullWidth(
                                child: _miniStat(
                                  Tr.t(lang, 'notifications'),
                                  '$unreadNotifications',
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 18),
                        ReadinessDistributionCard(
                          title: 'Readiness distribution',
                          counts: readiness.queryFailed
                              ? null
                              : readiness.distribution,
                          onTap: () => Navigator.push(
                            context,
                            fadeSlideRoute(
                              const CompanyReadinessResultsScreen(),
                            ),
                          ),
                          subtitle:
                              'Tap to inspect workspace members and completed scans.',
                          emptyMessage:
                              'No completed assessments in this period.',
                          unavailableMessage:
                              'Readiness distribution is unavailable right now.',
                          showChevron: true,
                        ),
                        const SizedBox(height: 18),
                        const SectionHeader(
                          title: 'Recent activity',
                          subtitle: 'Counts that need attention this morning.',
                        ),
                        const SizedBox(height: 10),
                        _activityCards(d, unreadNotifications),
                      ],
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _miniStat(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value,
            style: const TextStyle(
              color: WellarTheme.text,
              fontWeight: FontWeight.w700,
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: const TextStyle(color: WellarTheme.textMuted, fontSize: 11),
          ),
        ],
      ),
    );
  }

  Widget _activityCards(HrSnapshot data, int unreadNotifications) {
    final entries = <_ActivityEntry>[
      _ActivityEntry(
        title: 'Pending requests',
        value: _countLabel(data.pendingRequests),
        icon: Icons.assignment_late_outlined,
      ),
      _ActivityEntry(
        title: 'Open alerts',
        value: _countLabel(data.openAlerts),
        icon: Icons.notifications_active_outlined,
      ),
      _ActivityEntry(
        title: 'Missing scans',
        value: _countLabel(data.missingChecks),
        icon: Icons.warning_amber_rounded,
      ),
      _ActivityEntry(
        title: 'Notifications',
        value: '$unreadNotifications',
        icon: Icons.notifications_outlined,
      ),
    ];

    return Column(
      children: entries
          .map(
            (entry) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: OwnerSurfaceCard(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 12,
                ),
                child: Row(
                  children: [
                    Icon(entry.icon, color: WellarTheme.primary, size: 20),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        entry.title,
                        style: const TextStyle(
                          color: WellarTheme.text,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    Text(
                      entry.value,
                      style: const TextStyle(
                        color: WellarTheme.textMuted,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          )
          .toList(),
    );
  }

  String _displayIdentity(AsyncValue profileAsync, dynamic lang) {
    return profileAsync.maybeWhen(
      data: (profile) {
        final name = profile.name?.toString().trim() ?? '';
        if (name.isNotEmpty) return name;
        final email = profile.email?.toString().trim() ?? '';
        if (email.isNotEmpty) return email;
        return _sessionIdentityFallback(lang);
      },
      orElse: () => _sessionIdentityFallback(lang),
    );
  }

  String _displayEmail(AsyncValue profileAsync) {
    return profileAsync.maybeWhen(
      data: (profile) {
        final email = profile.email?.toString().trim() ?? '';
        if (email.isNotEmpty) return email;
        return _sessionEmailFallback();
      },
      orElse: () => _sessionEmailFallback(),
    );
  }

  String _sessionIdentityFallback(dynamic lang) {
    final sessionName = Session.instance.userName?.trim() ?? '';
    if (sessionName.isNotEmpty) return sessionName;
    final sessionEmail = Session.instance.userEmail?.trim() ?? '';
    if (sessionEmail.isNotEmpty) return sessionEmail;
    return Tr.t(lang, 'hr');
  }

  String _sessionEmailFallback() {
    final sessionEmail = Session.instance.userEmail?.trim() ?? '';
    if (sessionEmail.isNotEmpty) return sessionEmail;
    return 'Identity unavailable right now';
  }

  String _countLabel(int count) => count < 0 ? '--' : '$count';
}

class _HrHomeSnapshot {
  final HrSnapshot snapshot;
  final WorkspaceReadinessSummary readinessSummary;

  const _HrHomeSnapshot({
    required this.snapshot,
    required this.readinessSummary,
  });
}

class _ActivityEntry {
  final String title;
  final String value;
  final IconData icon;

  const _ActivityEntry({
    required this.title,
    required this.value,
    required this.icon,
  });
}

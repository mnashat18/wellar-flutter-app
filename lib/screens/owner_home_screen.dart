import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../i18n/tr.dart';
import '../services/owner_ops_service.dart';
import '../services/organization_service.dart';
import '../state/app_providers.dart';
import '../theme/app_theme.dart';
import '../utils/page_transition.dart';
import '../widgets/animated_wellar_screen.dart';
import '../widgets/notification_bell_button.dart';
import '../widgets/owner/owner_design_system.dart';
import '../widgets/responsive_card_grid.dart';
import 'admin_scan_requests_screen.dart';
import 'company_readiness_results_screen.dart';
import 'notifications_screen.dart';
import 'history_screen.dart';
import 'profile_screen.dart';
import 'wellness_check_screen.dart';

class OwnerHomeScreen extends ConsumerStatefulWidget {
  const OwnerHomeScreen({super.key});

  @override
  ConsumerState<OwnerHomeScreen> createState() => _OwnerHomeScreenState();
}

class _OwnerHomeScreenState extends ConsumerState<OwnerHomeScreen> {
  late Future<OwnerSnapshot> _future;
  ProviderSubscription<int>? _refreshSubscription;

  @override
  void initState() {
    super.initState();
    _future = _loadSnapshotForCurrentRole();
    _refreshSubscription = ref.listenManual<int>(refreshTickProvider, (
      previousValue,
      nextValue,
    ) {
      if (!mounted) return;
      if (_workspaceRole(ref.read(activeWorkspaceContextProvider)) != 'owner') {
        setState(() {
          _future = _idleSnapshotFuture();
        });
        return;
      }
      setState(() {
        _future = _loadSnapshotForCurrentRole(forceRefresh: true);
      });
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
    final activeRole = _workspaceRole(workspace);
    if (activeRole != 'owner') {
      debugPrint(
        '[STALE_ROLE_WIDGET_BLOCKED] widget=OwnerHomeScreen expected=owner actual=$activeRole',
      );
      return const Scaffold(
        backgroundColor: Colors.transparent,
        body: Center(
          child: CircularProgressIndicator(
            strokeWidth: 2.2,
            color: WellarTheme.primary,
          ),
        ),
      );
    }
    final profileAsync = ref.watch(profileProvider);
    final lang = ref.watch(appLanguageControllerProvider).language;
    final unread = ref.watch(unreadNotificationsProvider);
    final openAlertsCount = ref.watch(openAlertsCountProvider);
    final role = _roleLabel(workspace?.finalEffectiveRole);
    final workspaceValue = workspace?.businessProfileName ?? '';
    final workspaceName = workspaceValue.trim().isNotEmpty
        ? workspaceValue.trim()
        : Tr.t(lang, 'workspace_default');
    final displayName = profileAsync.maybeWhen(
      data: (profile) {
        final value = profile.name.trim();
        if (value.isNotEmpty) return value;
        return profile.email.trim();
      },
      orElse: () => role,
    );

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: AnimatedWellarScreen(
        showBackground: false,
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
        child: FutureBuilder<OwnerSnapshot>(
          future: _future,
          builder: (context, snap) {
            final data = snap.data;
            final isLoading = snap.connectionState != ConnectionState.done;
            final effectiveOpenAlerts = openAlertsCount > 0
                ? openAlertsCount
                : (data?.openAlerts ?? 0);
            return RefreshIndicator(
              onRefresh: () async {
                ref.read(refreshTickProvider.notifier).state++;
              },
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: EdgeInsets.zero,
                children: [
                  OwnerSurfaceCard(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                workspaceName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: WellarTheme.textMuted,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                displayName,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                textDirection: _containsArabic(displayName)
                                    ? TextDirection.rtl
                                    : TextDirection.ltr,
                                style: const TextStyle(
                                  color: WellarTheme.text,
                                  fontSize: 25,
                                  fontWeight: FontWeight.w800,
                                  height: 1.1,
                                ),
                              ),
                              const SizedBox(height: 8),
                              RoleChip(role),
                              const SizedBox(height: 8),
                              const Text(
                                'Operational overview',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: WellarTheme.textMuted,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 10),
                        NotificationBellButton(
                          unreadCount: unread,
                          onTap: () => _openNotificationCenter(role: role),
                        ),
                        IconButton(
                          tooltip: 'Account',
                          onPressed: () => Navigator.push(
                            context,
                            fadeSlideRoute(const ProfileScreen()),
                          ),
                          icon: const Icon(
                            Icons.account_circle_outlined,
                            color: WellarTheme.text,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 22),
                  if (isLoading || data == null)
                    const OwnerSurfaceCard(
                      child: SizedBox(
                        height: 130,
                        child: Center(
                          child: CircularProgressIndicator(
                            strokeWidth: 2.2,
                            color: WellarTheme.primary,
                          ),
                        ),
                      ),
                    )
                  else
                    _primaryMetricsGrid(data, role, effectiveOpenAlerts),
                  const SizedBox(height: 22),
                  const _SectionTitle('Priority items'),
                  const SizedBox(height: 10),
                  if (isLoading || data == null)
                    const OwnerSurfaceCard(
                      child: Center(
                        child: CircularProgressIndicator(
                          strokeWidth: 2.2,
                          color: WellarTheme.primary,
                        ),
                      ),
                    )
                  else
                    Column(
                      children: [
                        AlertSummaryCard(
                          title: Tr.t(lang, 'pending_requests'),
                          count: data.pendingRequests,
                          icon: Icons.assignment_late_outlined,
                        ),
                        const SizedBox(height: 10),
                        AlertSummaryCard(
                          title: Tr.t(lang, 'open_alerts'),
                          count: effectiveOpenAlerts,
                          icon: Icons.notification_important_outlined,
                          onTap: () => _openNotificationCenter(
                            role: role,
                            openAlerts: true,
                          ),
                        ),
                        const SizedBox(height: 10),
                        AlertSummaryCard(
                          title: Tr.t(lang, 'high_risk_today'),
                          count: data.attentionOutcomes,
                          icon: Icons.warning_amber_rounded,
                        ),
                      ],
                    ),
                  const SizedBox(height: 22),
                  const _SectionTitle('Primary actions'),
                  const SizedBox(height: 10),
                  ResponsiveCardGrid(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      ResponsiveCardGridItem(
                        child: QuickActionButton(
                          title: 'Send request',
                          icon: Icons.assignment_add,
                          onTap: () => Navigator.push(
                            context,
                            fadeSlideRoute(const AdminScanRequestsScreen()),
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
                          subtitle: 'Review your previous readiness checks',
                          icon: Icons.history_rounded,
                          onTap: () => Navigator.push(
                            context,
                            fadeSlideRoute(const HistoryScreen()),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 22),
                  const _SectionTitle('Readiness summary'),
                  const SizedBox(height: 10),
                  if (isLoading || data == null)
                    const OwnerSurfaceCard(
                      child: Center(
                        child: CircularProgressIndicator(
                          strokeWidth: 2.2,
                          color: WellarTheme.primary,
                        ),
                      ),
                    )
                  else
                    _readinessDistributionCard(data),
                  const SizedBox(height: 22),
                  const _SectionTitle('Recent activity'),
                  const SizedBox(height: 10),
                  if (snap.hasError)
                    SmartEmptyState(
                      icon: Icons.error_outline_rounded,
                      title: Tr.t(lang, 'snapshot_unavailable'),
                      subtitle: Tr.t(lang, 'company_overview_unavailable'),
                      actionLabel: Tr.t(lang, 'retry'),
                      onAction: () => setState(
                        () =>
                            _future = OwnerOpsService.instance.fetchSnapshot(),
                      ),
                    )
                  else
                    _activityFeed(data, effectiveOpenAlerts),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _primaryMetricsGrid(
    OwnerSnapshot data,
    String role,
    int effectiveOpenAlerts,
  ) {
    final completion = data.complianceRate.trim().isEmpty
        ? '0%'
        : data.complianceRate.trim();
    final cards = <_MetricTileData>[
      _MetricTileData(
        icon: Icons.people_alt_outlined,
        value: '${data.activeMembers}',
        label: 'Active members',
      ),
      _MetricTileData(
        icon: Icons.check_circle_outline_rounded,
        value: '${data.checksCompletedToday}',
        label: 'Checks today',
      ),
      _MetricTileData(
        icon: Icons.percent_rounded,
        value: completion,
        label: 'Completion %',
      ),
      _MetricTileData(
        icon: Icons.notification_important_outlined,
        value: '$effectiveOpenAlerts',
        label: 'Open alerts',
        accent: const Color(0xFFF4BE68),
        onTap: () => _openNotificationCenter(role: role, openAlerts: true),
      ),
    ];
    return ResponsiveCardGrid(
      spacing: 10,
      runSpacing: 10,
      children: [
        for (final card in cards)
          ResponsiveCardGridItem(child: _MetricTile(data: card)),
      ],
    );
  }

  Widget _readinessDistributionCard(OwnerSnapshot data) {
    final rows = [
      _ReadinessDistributionRow(
        label: 'Stable',
        keyName: 'Stable',
        accent: const Color(0xFF72D8A0),
      ),
      _ReadinessDistributionRow(
        label: 'Low Focus',
        keyName: 'Low Focus',
        accent: const Color(0xFF6DAFEA),
      ),
      _ReadinessDistributionRow(
        label: 'Elevated Fatigue',
        keyName: 'Elevated Fatigue',
        accent: const Color(0xFFDFB35D),
      ),
      _ReadinessDistributionRow(
        label: 'High Risk',
        keyName: 'High Risk',
        accent: const Color(0xFFE38654),
      ),
    ];
    final total = rows.fold<int>(
      0,
      (sum, row) => sum + (data.readinessDistribution[row.keyName] ?? 0),
    );
    if (total == 0) {
      return OwnerSurfaceCard(
        onTap: () => Navigator.push(
          context,
          fadeSlideRoute(const CompanyReadinessResultsScreen()),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Expanded(
                  child: Text(
                    'Readiness distribution',
                    style: TextStyle(
                      color: WellarTheme.text,
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                    ),
                  ),
                ),
                Icon(
                  Icons.chevron_right_rounded,
                  color: WellarTheme.textMuted,
                  size: 22,
                ),
              ],
            ),
            const SizedBox(height: 10),
            const Text(
              'No completed assessments in this period.',
              style: TextStyle(
                color: WellarTheme.textMuted,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Tap to view every member',
              style: TextStyle(
                color: WellarTheme.textMuted,
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      );
    }
    return OwnerSurfaceCard(
      onTap: () => Navigator.push(
        context,
        fadeSlideRoute(const CompanyReadinessResultsScreen()),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Expanded(
                child: Text(
                  'Readiness distribution',
                  style: TextStyle(
                    color: WellarTheme.text,
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                  ),
                ),
              ),
              Icon(
                Icons.chevron_right_rounded,
                color: WellarTheme.textMuted,
                size: 22,
              ),
            ],
          ),
          const SizedBox(height: 10),
          ...rows.map((row) {
            final value = data.readinessDistribution[row.keyName] ?? 0;
            final progress = total == 0 ? 0.0 : value / total;
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Column(
                children: [
                  Row(
                    children: [
                      _readinessDot(row.accent),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          row.label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: WellarTheme.textMuted,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      Text(
                        '$value',
                        style: const TextStyle(
                          color: WellarTheme.text,
                          fontWeight: FontWeight.w800,
                          fontSize: 16,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(999),
                    child: LinearProgressIndicator(
                      minHeight: 7,
                      value: progress,
                      backgroundColor: row.accent.withValues(alpha: 0.10),
                      color: row.accent,
                    ),
                  ),
                ],
              ),
            );
          }),
          const SizedBox(height: 8),
          const Text(
            'Tap to view every member',
            style: TextStyle(
              color: WellarTheme.textMuted,
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _activityFeed(OwnerSnapshot? data, int effectiveOpenAlerts) {
    if (data == null) {
      return const SmartEmptyState(
        icon: Icons.timeline_outlined,
        title: 'No recent activity yet',
        subtitle: 'Updates will appear here.',
      );
    }

    final items = <_ActivityRowData>[
      if (data.pendingRequests > 0)
        _ActivityRowData(
          icon: Icons.assignment_late_outlined,
          title: 'Pending requests',
          value: '${data.pendingRequests}',
        ),
      if (effectiveOpenAlerts > 0)
        _ActivityRowData(
          icon: Icons.notification_important_outlined,
          title: 'Open alerts',
          value: '$effectiveOpenAlerts',
        ),
      if (data.attentionOutcomes > 0)
        _ActivityRowData(
          icon: Icons.warning_amber_rounded,
          title: 'High risk today',
          value: '${data.attentionOutcomes}',
        ),
      if (data.checksCompletedToday > 0)
        _ActivityRowData(
          icon: Icons.check_circle_outline_rounded,
          title: 'Checks today',
          value: '${data.checksCompletedToday}',
        ),
    ].take(3).toList();

    if (items.isEmpty) {
      return const SmartEmptyState(
        icon: Icons.timeline_outlined,
        title: 'No recent activity yet',
        subtitle: 'Updates will appear here.',
      );
    }

    return Column(
      children: items.map((item) {
        return Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: OwnerSurfaceCard(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: [
                Icon(item.icon, color: WellarTheme.primary, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    item.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: WellarTheme.text,
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                    ),
                  ),
                ),
                Text(
                  item.value,
                  style: const TextStyle(
                    color: WellarTheme.textMuted,
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }

  void _openNotificationCenter({
    required String role,
    bool openAlerts = false,
  }) {
    final canViewAlerts = _canViewAlerts(role);
    final initialTab = openAlerts && canViewAlerts
        ? NotificationCenterTab.alerts
        : NotificationCenterTab.notifications;
    Navigator.push(
      context,
      fadeSlideRoute(
        NotificationsScreen(
          showAlertsTab: canViewAlerts,
          initialTab: initialTab,
          initialAlertsFilter: openAlerts && canViewAlerts ? 'open' : 'all',
          highlightOpenAlerts: openAlerts && canViewAlerts,
        ),
      ),
    );
  }

  bool _canViewAlerts(String role) {
    final normalized = role.trim().toLowerCase();
    return normalized == 'owner' || normalized == 'hr';
  }

  Future<OwnerSnapshot> _loadSnapshotForCurrentRole({
    bool forceRefresh = false,
  }) {
    final workspace = ref.read(activeWorkspaceContextProvider);
    final activeRole = _workspaceRole(workspace);
    if (activeRole != 'owner') {
      debugPrint(
        '[STALE_ROLE_WIDGET_BLOCKED] widget=OwnerHomeScreen expected=owner actual=$activeRole',
      );
      return _idleSnapshotFuture();
    }
    return OwnerOpsService.instance.fetchSnapshot(forceRefresh: forceRefresh);
  }

  String _roleLabel(String? role) {
    switch (role?.trim().toLowerCase()) {
      case 'owner':
        return 'Owner';
      case 'hr':
        return 'HR';
      case 'manager':
      case 'manger':
        return 'Manager';
      case 'employee':
        return 'Employee';
      default:
        return 'Owner';
    }
  }

  bool _containsArabic(String value) {
    return RegExp(r'[\u0600-\u06FF]').hasMatch(value);
  }

  String _workspaceRole(ActiveWorkspaceContext? workspace) {
    if (workspace == null) return '';
    return workspace.finalEffectiveRole.trim().toLowerCase();
  }

  Future<OwnerSnapshot> _idleSnapshotFuture() {
    return Future<OwnerSnapshot>.value(
      const OwnerSnapshot(
        activeMembers: 0,
        departmentsCount: 0,
        scanRequestsToday: 0,
        checksCompletedToday: 0,
        missingChecks: 0,
        pendingScans: 0,
        attentionOutcomes: 0,
        openAlerts: 0,
        pendingRequests: 0,
        complianceRate: '0%',
        readinessDistribution: <String, int>{},
      ),
    );
  }

  Widget _readinessDot(Color color) {
    return Container(
      width: 8,
      height: 8,
      decoration: BoxDecoration(shape: BoxShape.circle, color: color),
    );
  }
}

class _ReadinessDistributionRow {
  final String label;
  final String keyName;
  final Color accent;

  const _ReadinessDistributionRow({
    required this.label,
    required this.keyName,
    required this.accent,
  });
}

class _MetricTileData {
  final IconData icon;
  final String value;
  final String label;
  final Color accent;
  final VoidCallback? onTap;

  const _MetricTileData({
    required this.icon,
    required this.value,
    required this.label,
    this.accent = WellarTheme.primary,
    this.onTap,
  });
}

class _MetricTile extends StatelessWidget {
  final _MetricTileData data;

  const _MetricTile({required this.data});

  @override
  Widget build(BuildContext context) {
    return OwnerSurfaceCard(
      onTap: data.onTap,
      padding: const EdgeInsets.all(14),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(data.icon, color: data.accent, size: 18),
          const SizedBox(height: 12),
          Text(
            data.value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: WellarTheme.text,
              fontSize: 24,
              fontWeight: FontWeight.w800,
              height: 1,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            data.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: WellarTheme.textMuted,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String text;

  const _SectionTitle(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        color: WellarTheme.text,
        fontWeight: FontWeight.w800,
        fontSize: 17,
      ),
    );
  }
}

class _ActivityRowData {
  final IconData icon;
  final String title;
  final String value;

  const _ActivityRowData({
    required this.icon,
    required this.title,
    required this.value,
  });
}

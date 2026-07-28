import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../i18n/tr.dart';
import '../models/alert_item.dart';
import '../models/request_item.dart';
import '../services/alert_service.dart';
import '../services/owner_ops_service.dart';
import '../services/request_service.dart';
import '../state/app_providers.dart';
import '../theme/app_theme.dart';
import '../utils/page_transition.dart';
import '../utils/request_status_normalizer.dart';
import '../widgets/animated_wellar_screen.dart';
import '../widgets/owner/owner_design_system.dart';
import '../widgets/page_header_actions.dart';
import '../widgets/responsive_card_grid.dart';
import 'company_readiness_results_screen.dart';
import 'report_metric_detail_screen.dart';

enum _ReportsRange { today, sevenDays, thirtyDays }

class OwnerReportsScreen extends ConsumerStatefulWidget {
  final String? roleOverride;

  const OwnerReportsScreen({super.key, this.roleOverride});

  @override
  ConsumerState<OwnerReportsScreen> createState() => _OwnerReportsScreenState();
}

class _OwnerReportsScreenState extends ConsumerState<OwnerReportsScreen> {
  late Future<_ReportsData> _future;
  ProviderSubscription? _workspaceSubscription;
  String _workspaceIdentity = '';
  _ReportsRange _range = _ReportsRange.today;

  @override
  void initState() {
    super.initState();
    _workspaceIdentity = _identityOf(ref.read(activeWorkspaceContextProvider));
    _future = _load();
    _workspaceSubscription = ref.listenManual(
      activeWorkspaceContextProvider,
      (previous, next) {
        final nextIdentity = _identityOf(next);
        if (nextIdentity == _workspaceIdentity) return;
        if (!mounted) return;
        setState(() {
          _workspaceIdentity = nextIdentity;
          _future = _load();
        });
      },
    );
  }

  @override
  void dispose() {
    _workspaceSubscription?.close();
    super.dispose();
  }

  String get _role {
    final override = widget.roleOverride?.trim().toLowerCase();
    if (override != null && override.isNotEmpty) return override;
    return ref.read(activeWorkspaceContextProvider)?.finalEffectiveRole
            .trim()
            .toLowerCase() ??
        'owner';
  }

  bool get _isHr => _role == 'hr';

  Future<_ReportsData> _load() async {
    final requestsFuture = _isHr
        ? RequestService.instance.fetchHrRequests(limit: 300)
        : RequestService.instance.fetchOwnerRequests(limit: 300);
    // Requests are the source of truth for Required/Completed/Pending/Overdue.
    // We must not let alerts or readiness failures hide them.
    final requests = await requestsFuture;

    List<AlertItem> alerts = const [];
    try {
      alerts = await AlertService.instance.fetchAlerts(limit: 200);
    } catch (_) {
      alerts = const [];
    }

    late WorkspaceReadinessSummary readinessSummary;
    try {
      readinessSummary = await OwnerOpsService.instance
          .fetchWorkspaceReadinessSummary(
            start: _rangeStart(),
            end: _rangeEnd(),
          );
    } catch (_) {
      readinessSummary = WorkspaceReadinessSummary(
        distribution: const {
          'Stable': 0,
          'Low Focus': 0,
          'Elevated Fatigue': 0,
          'High Risk': 0,
        },
        resultsByScanId: const <String, OwnerAssessmentResult>{},
        queryFailed: true,
      );
    }

    return _ReportsData(
      alerts: alerts,
      requests: requests,
      readinessSummary: readinessSummary,
      assessmentsByScanId: readinessSummary.resultsByScanId,
      readinessFailed: readinessSummary.queryFailed,
    );
  }

  @override
  Widget build(BuildContext context) {
    final lang = ref.watch(appLanguageControllerProvider).language;
    final unread = ref.watch(unreadNotificationsProvider);
    final workspace = ref.watch(activeWorkspaceContextProvider);
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: AnimatedWellarScreen(
        showBackground: false,
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
        child: FutureBuilder<_ReportsData>(
          future: _future,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const OwnerSurfaceCard(
                child: SizedBox(
                  height: 180,
                  child: Center(
                    child: CircularProgressIndicator(
                      strokeWidth: 2.2,
                      color: WellarTheme.primary,
                    ),
                  ),
                ),
              );
            }
            if (snapshot.hasError) {
              return SmartEmptyState(
                icon: Icons.error_outline_rounded,
                title: Tr.t(lang, 'reports_summary_unavailable'),
                subtitle: Tr.t(lang, 'unable_load_reports_summary'),
                actionLabel: Tr.t(lang, 'retry'),
                onAction: () => setState(() => _future = _load()),
              );
            }
            final data = snapshot.data!;
            final metrics = _buildMetrics(
              requests: data.requests,
              assessmentsByScanId: data.assessmentsByScanId,
              alerts: data.alerts,
              readinessSummary: data.readinessSummary,
            );
            final businessProfileId = workspace?.businessProfileId.trim() ?? '';
            final membershipId = workspace?.membershipId.trim() ?? '';
            final role = (workspace?.finalEffectiveRole ??
                    workspace?.memberRole ??
                    _role)
                .trim();
            final readinessTotal = metrics.readinessDistribution.values
                .fold<int>(0, (sum, value) => sum + value);
            debugPrint(
              '[HR_REPORTS_CONTEXT] business_profile=$businessProfileId membership_id=$membershipId role=$role',
            );
            debugPrint(
              '[HR_REPORTS_RENDER] raw_count=$readinessTotal stable=${metrics.readinessDistribution['Stable'] ?? 0} low_focus=${metrics.readinessDistribution['Low Focus'] ?? 0} elevated_fatigue=${metrics.readinessDistribution['Elevated Fatigue'] ?? 0} high_risk=${metrics.readinessDistribution['High Risk'] ?? 0}',
            );

            return RefreshIndicator(
              onRefresh: () async => setState(() => _future = _load()),
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: [
                  SectionHeader(
                    title: Tr.t(lang, 'reports'),
                    subtitle: Tr.t(lang, 'reports_subtitle'),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        TextButton(
                          onPressed: null,
                          child: Text(Tr.t(lang, 'export_coming_soon')),
                        ),
                        const SizedBox(width: 6),
                        PageHeaderActions(
                          unreadCount: unread,
                          showAlertsTab: true,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  _rangeSelector(lang),
                  const SizedBox(height: 16),
                  ResponsiveCardGrid(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                  ResponsiveCardGridItem(
                        child: _metricCard(
                          title: Tr.t(lang, 'required'),
                          value: '${metrics.requiredCount}',
                          subtitle: _rangeLabel(lang, _range),
                          icon: Icons.check_circle_outline_rounded,
                          onTap: () => _openDetail(
                            title: Tr.t(lang, 'required'),
                            summaryLabel: Tr.t(lang, 'required'),
                            summaryValue: '${metrics.requiredCount}',
                            entries: metrics.requiredEntries,
                          ),
                        ),
                      ),
                      ResponsiveCardGridItem(
                        child: _metricCard(
                          title: Tr.t(lang, 'completed'),
                          value: '${metrics.completedCount}',
                          subtitle: _rangeLabel(lang, _range),
                          icon: Icons.verified_rounded,
                          onTap: () => _openDetail(
                            title: Tr.t(lang, 'completed'),
                            summaryLabel: Tr.t(lang, 'completed'),
                            summaryValue: '${metrics.completedCount}',
                            entries: metrics.completedEntriesDetails,
                          ),
                        ),
                      ),
                      ResponsiveCardGridItem(
                        child: _metricCard(
                          title: Tr.t(lang, 'pending'),
                          value: '${metrics.pendingCount}',
                          subtitle: _rangeLabel(lang, _range),
                          icon: Icons.pending_actions_rounded,
                          onTap: () => _openDetail(
                            title: Tr.t(lang, 'pending'),
                            summaryLabel: Tr.t(lang, 'pending'),
                            summaryValue: '${metrics.pendingCount}',
                            entries: metrics.pendingEntriesDetails,
                          ),
                        ),
                      ),
                      ResponsiveCardGridItem(
                        child: _metricCard(
                          title: Tr.t(lang, 'overdue'),
                          value: '${metrics.overdueCount}',
                          subtitle: _rangeLabel(lang, _range),
                          icon: Icons.warning_amber_rounded,
                          onTap: () => _openDetail(
                            title: Tr.t(lang, 'overdue'),
                            summaryLabel: Tr.t(lang, 'overdue'),
                            summaryValue: '${metrics.overdueCount}',
                            entries: metrics.overdueEntriesDetails,
                          ),
                        ),
                      ),
                      ResponsiveCardGridItem.fullWidth(
                        child: _metricCard(
                          title: Tr.t(lang, 'open_alerts'),
                          value: '${metrics.openAlertsCount}',
                          subtitle: Tr.t(lang, 'alerts'),
                          icon: Icons.notification_important_outlined,
                          onTap: () => _openDetail(
                            title: Tr.t(lang, 'open_alerts'),
                            summaryLabel: Tr.t(lang, 'open_alerts'),
                            summaryValue: '${metrics.openAlertsCount}',
                            entries: metrics.alertEntries,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  _readinessCard(
                    lang: lang,
                    metrics: metrics,
                    data: data,
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  _ReportMetrics _buildMetrics({
    required List<RequestItem> requests,
    required Map<String, OwnerAssessmentResult> assessmentsByScanId,
    required List<AlertItem> alerts,
    required WorkspaceReadinessSummary readinessSummary,
  }) {
    final relevantEntries = requests
        .where(_isAssignedRequest)
        .map((item) => _toRequestEntry(item, assessmentsByScanId))
        .where(_isRelevantForRange)
        .toList()
      ..sort((a, b) => _sortRequestEntry(a, b));

    final completedEntries = relevantEntries
        .where((entry) => entry.status == NormalizedRequestStatus.completed)
        .toList();
    final pendingEntries = relevantEntries
        .where((entry) => entry.status == NormalizedRequestStatus.pending)
        .toList();
    final overdueEntries = relevantEntries
        .where((entry) => entry.status == NormalizedRequestStatus.overdue)
        .toList();
    final openAlerts = alerts.where((alert) => alert.isOpen).toList();
    final readiness = readinessSummary.distribution;
    final completionRate = relevantEntries.isEmpty
        ? 0.0
        : completedEntries.length / relevantEntries.length;

    return _ReportMetrics(
      requiredCount: relevantEntries.length,
      completedCount: completedEntries.length,
      pendingCount: pendingEntries.length,
      overdueCount: overdueEntries.length,
      openAlertsCount: openAlerts.length,
      completionRate: completionRate,
      readinessDistribution: readiness,
      requiredEntries: relevantEntries.map(_toReportDetailEntry).toList(),
      completedEntriesDetails: completedEntries.map(_toReportDetailEntry).toList(),
      pendingEntriesDetails: pendingEntries.map(_toReportDetailEntry).toList(),
      overdueEntriesDetails: overdueEntries.map(_toReportDetailEntry).toList(),
      alertEntries: openAlerts.map((alert) {
        return ReportDetailEntry(
          icon: Icons.notification_important_outlined,
          title: alert.title,
          subtitle: alert.summary,
          trailing: alert.severity ?? alert.status,
        );
      }).toList(),
      distributionEntries: readiness.entries.map((entry) {
        return ReportDetailEntry(
          icon: Icons.pie_chart_outline_rounded,
          title: entry.key,
          trailing: '${entry.value}',
        );
      }).toList(),
    );
  }

  Widget _rangeSelector(dynamic lang) {
    return SizedBox(
      height: 40,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          _rangeChip(lang, _ReportsRange.today),
          const SizedBox(width: 8),
          _rangeChip(lang, _ReportsRange.sevenDays),
          const SizedBox(width: 8),
          _rangeChip(lang, _ReportsRange.thirtyDays),
        ],
      ),
    );
  }

  Widget _rangeChip(dynamic lang, _ReportsRange range) {
    return ChoiceChip(
      label: Text(_rangeLabel(lang, range)),
      selected: _range == range,
      onSelected: (_) => setState(() {
        _range = range;
        _future = _load();
      }),
    );
  }

  Widget _metricCard({
    required String title,
    required String value,
    required String subtitle,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return OwnerSurfaceCard(
      onTap: onTap,
      glow: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(icon, color: WellarTheme.primary, size: 18),
              const Spacer(),
              const Icon(
                Icons.arrow_forward_rounded,
                color: WellarTheme.textMuted,
                size: 16,
              ),
            ],
          ),
          const SizedBox(height: 18),
          Text(
            value,
            style: const TextStyle(
              color: WellarTheme.text,
              fontSize: 26,
              fontWeight: FontWeight.w800,
              height: 1,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            title,
            style: const TextStyle(
              color: WellarTheme.text,
              fontWeight: FontWeight.w700,
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: const TextStyle(
              color: WellarTheme.textMuted,
              fontSize: 11.5,
            ),
          ),
        ],
      ),
    );
  }

  void _openDetail({
    required String title,
    required String summaryLabel,
    required String summaryValue,
    required List<ReportDetailEntry> entries,
  }) {
    Navigator.push(
      context,
      fadeSlideRoute(
        ReportMetricDetailScreen(
          title: title,
          rangeLabel: _rangeLabel(
            ref.read(appLanguageControllerProvider).language,
            _range,
          ),
          summaryLabel: summaryLabel,
          summaryValue: summaryValue,
          entries: entries,
        ),
      ),
    );
  }

  String _identityOf(Object? workspace) {
    if (workspace == null) return '';
    final dynamic value = workspace;
    return '${value.currentUserId}:${value.membershipId}:${value.businessProfileId}:${value.finalEffectiveRole}:${value.departmentId ?? ''}';
  }

  void _openCompanyReadiness({
    required WorkspaceReadinessSummary readinessSummary,
  }) {
    Navigator.push(
      context,
      fadeSlideRoute(
        CompanyReadinessResultsScreen(
          initialSummary: readinessSummary,
          start: _rangeStart(),
          end: _rangeEnd(),
          periodLabel: _rangePeriodDescription(),
        ),
      ),
    );
  }

  Widget _readinessCard({
    required dynamic lang,
    required _ReportMetrics metrics,
    required _ReportsData data,
  }) {
    final total = metrics.readinessDistribution.values
        .fold<int>(0, (sum, item) => sum + item);
    final hasResults = !data.readinessFailed && total > 0;
    return OwnerSurfaceCard(
      onTap: () => _openCompanyReadiness(readinessSummary: data.readinessSummary),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  Tr.t(lang, 'readiness_distribution'),
                  style: const TextStyle(
                    color: WellarTheme.text,
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                  ),
                ),
              ),
              const Icon(
                Icons.chevron_right_rounded,
                color: WellarTheme.textMuted,
                size: 22,
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (data.readinessFailed)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 6),
              child: Row(
                children: [
                  Icon(
                    Icons.info_outline_rounded,
                    color: Color(0xFFFFC46B),
                    size: 18,
                  ),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Readiness details unavailable for your role. Contact your admin to enable Directus read access on scan_results (relation scan_id → wellness_scans.business_profile).',
                      style: TextStyle(
                        color: WellarTheme.text,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        height: 1.35,
                      ),
                    ),
                  ),
                ],
              ),
            )
          else if (!hasResults)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 6),
              child: Text(
                'No completed assessments in this period.',
                style: TextStyle(
                  color: WellarTheme.textMuted,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            )
          else
            ...metrics.readinessDistribution.entries.map((entry) {
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 5),
                child: Row(
                  children: [
                    _distributionDot(entry.key),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        entry.key,
                        style: const TextStyle(
                          color: WellarTheme.textMuted,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    Text(
                      '${entry.value}',
                      style: const TextStyle(
                        color: WellarTheme.text,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              );
            }),
          const SizedBox(height: 8),
          Text(
            'Tap to view every member',
            style: const TextStyle(
              color: WellarTheme.textMuted,
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  String _rangeLabel(dynamic lang, _ReportsRange range) {
    switch (range) {
      case _ReportsRange.today:
        return Tr.t(lang, 'range_today');
      case _ReportsRange.sevenDays:
        return Tr.t(lang, 'range_7_days');
      case _ReportsRange.thirtyDays:
        return Tr.t(lang, 'range_30_days');
    }
  }

  String _rangePeriodDescription() {
    switch (_range) {
      case _ReportsRange.today:
        return 'today';
      case _ReportsRange.sevenDays:
        return 'last 7 days';
      case _ReportsRange.thirtyDays:
        return 'last 30 days';
    }
  }

  bool _isWithinRange(DateTime? value) {
    if (value == null) return false;
    final local = value.toLocal();
    final start = _rangeStart();
    return !local.isBefore(start);
  }

  bool _isRelevantForRange(_RequestReportEntry entry) {
    final start = _rangeStart();
    final end = _rangeEnd();
    switch (entry.status) {
      case NormalizedRequestStatus.completed:
        return _isBetween(entry.completedAt, start, end) ||
            _isBetween(entry.dueAt, start, end) ||
            _isBetween(entry.requestedAt, start, end);
      case NormalizedRequestStatus.pending:
        return _isBetween(entry.dueAt, start, end) ||
            _isBetween(entry.requestedAt, start, end);
      case NormalizedRequestStatus.overdue:
        return entry.dueAt != null &&
            _isBetween(entry.dueAt, start, end) &&
            entry.dueAt!.isBefore(DateTime.now());
      case NormalizedRequestStatus.cancelled:
        return false;
    }
  }

  bool _isBetween(DateTime? value, DateTime start, DateTime end) {
    if (value == null) return false;
    final local = value.toLocal();
    return !local.isBefore(start) && local.isBefore(end);
  }

  bool _isAssignedRequest(RequestItem item) {
    return item.requestedForId?.trim().isNotEmpty == true ||
        item.requestedForUserId?.trim().isNotEmpty == true ||
        item.departmentId?.trim().isNotEmpty == true ||
        item.target?.trim().isNotEmpty == true;
  }

  _RequestReportEntry _toRequestEntry(
    RequestItem item,
    Map<String, OwnerAssessmentResult> assessmentsByScanId,
  ) {
    final status = RequestStatusNormalizer.normalize(item, log: false);
    final scanId = item.scanId?.trim() ?? '';
    final assessment = scanId.isEmpty ? null : assessmentsByScanId[scanId];
    return _RequestReportEntry(
      item: item,
      status: status,
      requestedAt: item.timestamp,
      dueAt: item.dueAt,
      completedAt: item.completedAt ?? assessment?.completedAt,
      assessment: assessment,
    );
  }

  int _sortRequestEntry(_RequestReportEntry a, _RequestReportEntry b) {
    final priority =
        _statusPriority(b.status).compareTo(_statusPriority(a.status));
    if (priority != 0) return priority;
    final aDate = a.primaryDate ?? DateTime.fromMillisecondsSinceEpoch(0);
    final bDate = b.primaryDate ?? DateTime.fromMillisecondsSinceEpoch(0);
    return bDate.compareTo(aDate);
  }

  int _statusPriority(NormalizedRequestStatus status) {
    switch (status) {
      case NormalizedRequestStatus.overdue:
        return 3;
      case NormalizedRequestStatus.pending:
        return 2;
      case NormalizedRequestStatus.completed:
        return 1;
      case NormalizedRequestStatus.cancelled:
        return 0;
    }
  }

  ReportDetailEntry _toReportDetailEntry(_RequestReportEntry entry) {
    final item = entry.item;
    return ReportDetailEntry(
      icon: _statusIcon(entry.status),
      title: item.displayTarget,
      subtitle: _subtitleForEntry(entry),
      trailing: _summaryTrailing(entry),
      department: item.displayDepartment,
      meta: _summaryMeta(entry),
      statusLabel: entry.status.label,
      email: item.requestedForEmail,
      role: item.requestedForRole,
    );
  }

  String _summaryMeta(_RequestReportEntry entry) {
    final lines = <String>[
      if (entry.requestedAt != null)
        'Requested: ${_formatDate(entry.requestedAt)}',
      if (entry.status == NormalizedRequestStatus.pending && entry.dueAt != null)
        'Due: ${_formatDate(entry.dueAt)}',
      if (entry.status == NormalizedRequestStatus.overdue && entry.dueAt != null)
        'Overdue since: ${_formatDate(entry.dueAt)}',
      if (entry.status == NormalizedRequestStatus.completed &&
          entry.completedAt != null)
        'Completed: ${_formatDate(entry.completedAt)}',
    ];
    return lines.join('  |  ');
  }

  String? _summaryTrailing(_RequestReportEntry entry) {
    switch (entry.status) {
      case NormalizedRequestStatus.completed:
        return Tr.t(ref.read(appLanguageControllerProvider).language, 'completed');
      case NormalizedRequestStatus.pending:
        return Tr.t(ref.read(appLanguageControllerProvider).language, 'pending');
      case NormalizedRequestStatus.overdue:
        return Tr.t(ref.read(appLanguageControllerProvider).language, 'overdue');
      case NormalizedRequestStatus.cancelled:
        return null;
    }
  }

  String? _subtitleForEntry(_RequestReportEntry entry) {
    final assessment = entry.assessment;
    final segments = <String>[];
    if (assessment?.outcome != null) segments.add('Outcome: ${assessment!.outcome}');
    if (assessment?.readinessScore != null) {
      segments.add('Readiness score: ${assessment!.readinessScore}');
    }
    return segments.isEmpty ? null : segments.join('  |  ');
  }

  IconData _statusIcon(NormalizedRequestStatus status) {
    switch (status) {
      case NormalizedRequestStatus.completed:
        return Icons.check_circle_outline_rounded;
      case NormalizedRequestStatus.pending:
        return Icons.pending_actions_rounded;
      case NormalizedRequestStatus.overdue:
        return Icons.warning_amber_rounded;
      case NormalizedRequestStatus.cancelled:
        return Icons.cancel_outlined;
    }
  }

  DateTime _rangeStart() {
    final now = DateTime.now();
    switch (_range) {
      case _ReportsRange.today:
        return DateTime(now.year, now.month, now.day);
      case _ReportsRange.sevenDays:
        final start = now.subtract(const Duration(days: 6));
        return DateTime(start.year, start.month, start.day);
      case _ReportsRange.thirtyDays:
        final start = now.subtract(const Duration(days: 29));
        return DateTime(start.year, start.month, start.day);
    }
  }

  DateTime _rangeEnd() {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day).add(const Duration(days: 1));
  }

  String _formatDate(DateTime? value) {
    if (value == null) return '-';
    final local = value.toLocal();
    final day = local.day.toString().padLeft(2, '0');
    final month = local.month.toString().padLeft(2, '0');
    final year = local.year.toString();
    return '$day/$month/$year';
  }

  Widget _distributionDot(String label) {
    final normalized = label.toLowerCase();
    Color color;
    switch (normalized) {
      case 'high risk':
        color = const Color(0xFFFF7A8F);
        break;
      case 'elevated fatigue':
        color = const Color(0xFFFFC46B);
        break;
      case 'low focus':
        color = const Color(0xFF7DBBFF);
        break;
      default:
        color = const Color(0xFF6EE7A8);
        break;
    }
    return Container(
      width: 10,
      height: 10,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
  }
}

class _ReportsData {
  final List<RequestItem> requests;
  final List<AlertItem> alerts;
  final WorkspaceReadinessSummary readinessSummary;
  final Map<String, OwnerAssessmentResult> assessmentsByScanId;
  final bool readinessFailed;

  const _ReportsData({
    required this.requests,
    required this.alerts,
    required this.readinessSummary,
    required this.assessmentsByScanId,
    required this.readinessFailed,
  });
}

class _RequestReportEntry {
  final RequestItem item;
  final NormalizedRequestStatus status;
  final DateTime? requestedAt;
  final DateTime? dueAt;
  final DateTime? completedAt;
  final OwnerAssessmentResult? assessment;

  const _RequestReportEntry({
    required this.item,
    required this.status,
    required this.requestedAt,
    required this.dueAt,
    required this.completedAt,
    required this.assessment,
  });

  DateTime? get primaryDate => completedAt ?? dueAt ?? requestedAt;
}

class _ReportMetrics {
  final int requiredCount;
  final int completedCount;
  final int pendingCount;
  final int overdueCount;
  final int openAlertsCount;
  final double completionRate;
  final Map<String, int> readinessDistribution;
  final List<ReportDetailEntry> requiredEntries;
  final List<ReportDetailEntry> completedEntriesDetails;
  final List<ReportDetailEntry> pendingEntriesDetails;
  final List<ReportDetailEntry> overdueEntriesDetails;
  final List<ReportDetailEntry> alertEntries;
  final List<ReportDetailEntry> distributionEntries;

  const _ReportMetrics({
    required this.requiredCount,
    required this.completedCount,
    required this.pendingCount,
    required this.overdueCount,
    required this.openAlertsCount,
    required this.completionRate,
    required this.readinessDistribution,
    required this.requiredEntries,
    required this.completedEntriesDetails,
    required this.pendingEntriesDetails,
    required this.overdueEntriesDetails,
    required this.alertEntries,
    required this.distributionEntries,
  });
}

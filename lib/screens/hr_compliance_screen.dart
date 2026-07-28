import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../i18n/tr.dart';
import '../models/request_item.dart';
import '../models/workspace_department.dart';
import '../services/alert_service.dart';
import '../services/hr_ops_service.dart';
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
import 'admin_scan_requests_screen.dart';
import 'company_readiness_results_screen.dart';
import 'notifications_screen.dart';
import 'report_metric_detail_screen.dart';

enum _HrComplianceRange { today, sevenDays, thirtyDays }

class HrComplianceScreen extends ConsumerStatefulWidget {
  const HrComplianceScreen({super.key});

  @override
  ConsumerState<HrComplianceScreen> createState() => _HrComplianceScreenState();
}

class _HrComplianceScreenState extends ConsumerState<HrComplianceScreen> {
  late Future<_HrComplianceData> _future;
  ProviderSubscription? _workspaceSubscription;
  String _workspaceIdentity = '';
  _HrComplianceRange _range = _HrComplianceRange.today;

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

  Future<_HrComplianceData> _load() async {
    // Requests are the source of truth for Required/Completed/Pending/Overdue.
    // If this call throws, the screen shows a visible error+retry (no blank).
    final requests = await RequestService.instance.fetchHrRequests(limit: 300);

    HrSnapshot? snapshot;
    List<HrMemberView> members = const [];
    List<WorkspaceDepartment> departments = const [];
    int openAlertsCount = 0;
    late WorkspaceReadinessSummary readinessSummary;

    try {
      snapshot = await HrOpsService.instance.fetchSnapshot();
    } catch (_) {
      snapshot = null;
    }
    try {
      members = await HrOpsService.instance.fetchWorkforce();
    } catch (_) {
      members = const [];
    }
    try {
      departments = await HrOpsService.instance.fetchDepartments();
    } catch (_) {
      departments = const [];
    }
    try {
      final alerts = await AlertService.instance.fetchAlerts(limit: 200);
      openAlertsCount = alerts.where((alert) => alert.isOpen).length;
    } catch (_) {
      openAlertsCount = 0;
    }
    readinessSummary = await OwnerOpsService.instance
        .fetchWorkspaceReadinessSummary(
          start: _rangeStart(),
          end: _rangeEnd(),
        );

    return _HrComplianceData(
      requests: requests,
      snapshot: snapshot,
      members: members,
      departments: departments,
      openAlertsCount: openAlertsCount,
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
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
        child: FutureBuilder<_HrComplianceData>(
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
              final forbidden =
                  snapshot.error is DioException &&
                  (snapshot.error as DioException).response?.statusCode == 403;
              return SmartEmptyState(
                icon: Icons.error_outline_rounded,
                title: forbidden
                    ? Tr.t(lang, 'access_unavailable')
                    : Tr.t(lang, 'reports_summary_unavailable'),
                subtitle: forbidden
                    ? Tr.t(lang, 'access_unavailable')
                    : Tr.t(lang, 'unable_load_reports_summary'),
                actionLabel: Tr.t(lang, 'retry'),
                onAction: () => setState(() => _future = _load()),
              );
            }

            final data = snapshot.data!;
            final metrics = _buildMetrics(
              requests: data.requests,
              assessmentsByScanId: data.assessmentsByScanId,
              members: data.members,
              departments: data.departments,
              openAlertsCount: data.openAlertsCount,
              unassignedLabel: Tr.t(lang, 'unassigned'),
            );
            final missingScanEntries = _buildMissingScanEntries(data.members);
            final businessProfileId = workspace?.businessProfileId.trim() ?? '';
            final membershipId = workspace?.membershipId.trim() ?? '';
            final role = (workspace?.finalEffectiveRole ??
                    workspace?.memberRole ??
                    'unknown')
                .trim();
            debugPrint(
              '[HR_COMPLIANCE_CONTEXT] business_profile=$businessProfileId membership_id=$membershipId role=$role',
            );
            debugPrint(
              '[HR_COMPLIANCE_RENDER] total=${metrics.requiredCount} pending=${metrics.pendingCount} completed=${metrics.completedCount} overdue=${metrics.overdueCount}',
            );

            return RefreshIndicator(
              onRefresh: () async => setState(() => _future = _load()),
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: [
                  SectionHeader(
                    title: Tr.t(lang, 'compliance'),
                    subtitle: Tr.t(lang, 'compliance_subtitle'),
                    trailing: PageHeaderActions(
                      unreadCount: unread,
                      showAlertsTab: true,
                    ),
                  ),
                  const SizedBox(height: 14),
                  _rangeSelector(lang),
                  const SizedBox(height: 14),
                  OwnerSurfaceCard(
                    glow: true,
                    child: Row(
                      children: [
                        ComplianceRing(
                          score: metrics.completionRate,
                          label: _rangeLabel(lang, _range),
                        ),
                        const SizedBox(width: 18),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                Tr.t(lang, 'compliance_rate'),
                                style: const TextStyle(
                                  color: WellarTheme.textMuted,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                metrics.requiredCount == 0
                                    ? '-'
                                    : '${(metrics.completionRate * 100).round()}%',
                                style: const TextStyle(
                                  color: WellarTheme.text,
                                  fontSize: 28,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              const SizedBox(height: 10),
                              _summaryLine(
                                Tr.t(lang, 'required'),
                                '${metrics.requiredCount}',
                              ),
                              _summaryLine(
                                Tr.t(lang, 'completed'),
                                '${metrics.completedCount}',
                              ),
                              _summaryLine(
                                Tr.t(lang, 'pending'),
                                '${metrics.pendingCount}',
                              ),
                              _summaryLine(
                                Tr.t(lang, 'overdue'),
                                '${metrics.overdueCount}',
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 18),
                  SectionHeader(title: Tr.t(lang, 'operational_summary')),
                  const SizedBox(height: 10),
                  ResponsiveCardGrid(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      ResponsiveCardGridItem(
                        child: OwnerMetricCard(
                          label: Tr.t(lang, 'required'),
                          value: metrics.requiredCount,
                          icon: Icons.assignment_turned_in_outlined,
                        ),
                      ),
                      ResponsiveCardGridItem(
                        child: OwnerMetricCard(
                          label: Tr.t(lang, 'completed'),
                          value: metrics.completedCount,
                          icon: Icons.verified_rounded,
                        ),
                      ),
                      ResponsiveCardGridItem(
                        child: OwnerMetricCard(
                          label: Tr.t(lang, 'pending'),
                          value: metrics.pendingCount,
                          icon: Icons.pending_actions_rounded,
                          accent: const Color(0xFF7DBBFF),
                        ),
                      ),
                      ResponsiveCardGridItem(
                        child: OwnerMetricCard(
                          label: Tr.t(lang, 'overdue'),
                          value: metrics.overdueCount,
                          icon: Icons.schedule_outlined,
                          accent: const Color(0xFFFFC46B),
                        ),
                      ),
                      ResponsiveCardGridItem(
                        child: OwnerMetricCard(
                          label: Tr.t(lang, 'open_alerts'),
                          value: metrics.openAlertsCount,
                          icon: Icons.notification_important_outlined,
                          accent: const Color(0xFF7DBBFF),
                        ),
                      ),
                      ResponsiveCardGridItem(
                        child: OwnerMetricCard(
                          label: Tr.t(lang, 'high_risk_today'),
                          value: metrics.highRiskCount,
                          icon: Icons.warning_amber_rounded,
                          accent: const Color(0xFFFF7A8F),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  SectionHeader(title: Tr.t(lang, 'department_breakdown')),
                  const SizedBox(height: 10),
                  if (metrics.departmentRows.isEmpty)
                    SmartEmptyState(
                      icon: Icons.apartment_outlined,
                      title: Tr.t(lang, 'no_departments_found'),
                      subtitle: Tr.t(lang, 'reports_subtitle'),
                    )
                  else
                    ...metrics.departmentRows.map(
                      (row) => Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: _departmentCard(row),
                      ),
                    ),
                  const SizedBox(height: 18),
                  SectionHeader(
                    title: Tr.t(lang, 'readiness_distribution'),
                    subtitle: 'Completed scan results in this period.',
                  ),
                  const SizedBox(height: 10),
                  _readinessCard(
                    lang: lang,
                    readinessSummary: data.readinessSummary,
                    readinessFailed: data.readinessFailed,
                    start: _rangeStart(),
                    end: _rangeEnd(),
                    periodLabel: _rangeLabel(lang, _range),
                  ),
                  const SizedBox(height: 18),
                  SectionHeader(title: Tr.t(lang, 'quick_actions')),
                  const SizedBox(height: 10),
                  QuickActionButton(
                    title: Tr.t(lang, 'view_missing_scans'),
                    icon: Icons.pending_actions_rounded,
                    onTap: () => _openReportDetail(
                      context,
                      title: Tr.t(lang, 'missing_scans'),
                      summaryLabel: Tr.t(lang, 'missing_scans'),
                      summaryValue: '${missingScanEntries.length}',
                      entries: missingScanEntries,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: QuickActionButton(
                          title: Tr.t(lang, 'send_request'),
                          icon: Icons.assignment_add,
                          onTap: () => Navigator.push(
                            context,
                            fadeSlideRoute(const AdminScanRequestsScreen()),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: QuickActionButton(
                          title: Tr.t(lang, 'open_alerts'),
                          icon: Icons.notifications_active_outlined,
                          onTap: () => Navigator.push(
                            context,
                            fadeSlideRoute(
                              const NotificationsScreen(
                                showAlertsTab: true,
                                initialTab: NotificationCenterTab.alerts,
                                initialAlertsFilter: 'open',
                                highlightOpenAlerts: true,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  _HrComplianceMetrics _buildMetrics({
    required List<RequestItem> requests,
    required Map<String, OwnerAssessmentResult> assessmentsByScanId,
    required List<HrMemberView> members,
    required List<WorkspaceDepartment> departments,
    required int openAlertsCount,
    required String unassignedLabel,
  }) {
    final relevantEntries = requests
        .where(_isAssignedRequest)
        .map((item) => _toRequestEntry(item, assessmentsByScanId))
        .where(_isRelevantForRange)
        .toList()
      ..sort(_sortRequestEntry);

    final completedEntries = relevantEntries
        .where((entry) => entry.status == NormalizedRequestStatus.completed)
        .toList();
    final pendingEntries = relevantEntries
        .where((entry) => entry.status == NormalizedRequestStatus.pending)
        .toList();
    final overdueEntries = relevantEntries
        .where((entry) => entry.status == NormalizedRequestStatus.overdue)
        .toList();

    final readiness = <String, int>{
      'Stable': 0,
      'Low Focus': 0,
      'Elevated Fatigue': 0,
      'High Risk': 0,
    };
    for (final entry in completedEntries) {
      final scanId = entry.item.scanId?.trim() ?? '';
      if (scanId.isEmpty) continue;
      final assessment = assessmentsByScanId[scanId];
      final label = assessment?.outcome;
      if (label != null && readiness.containsKey(label)) {
        readiness[label] = (readiness[label] ?? 0) + 1;
      }
    }

    final highRiskCount = readiness['High Risk'] ?? 0;
    final completionRate = relevantEntries.isEmpty
        ? 0.0
        : completedEntries.length / relevantEntries.length;

    return _HrComplianceMetrics(
      requiredCount: relevantEntries.length,
      completedCount: completedEntries.length,
      pendingCount: pendingEntries.length,
      overdueCount: overdueEntries.length,
      openAlertsCount: openAlertsCount,
      highRiskCount: highRiskCount,
      completionRate: completionRate,
      readinessDistribution: readiness,
      pendingEntries: pendingEntries.map(_toReportDetailEntry).toList(),
      overdueEntries: overdueEntries.map(_toReportDetailEntry).toList(),
      departmentRows: _buildDepartmentRows(
        entries: relevantEntries,
        members: members,
        departments: departments,
        unassignedLabel: unassignedLabel,
      ),
    );
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

  String _identityOf(Object? workspace) {
    if (workspace == null) return '';
    final dynamic value = workspace;
    return '${value.currentUserId}:${value.membershipId}:${value.businessProfileId}:${value.finalEffectiveRole}:${value.departmentId ?? ''}';
  }

  List<_HrDepartmentComplianceRow> _buildDepartmentRows({
    required List<_RequestReportEntry> entries,
    required List<HrMemberView> members,
    required List<WorkspaceDepartment> departments,
    required String unassignedLabel,
  }) {
    final membersByMembershipId = <String, HrMemberView>{
      for (final member in members)
        if (member.memberId.trim().isNotEmpty) member.memberId: member,
    };
    final departmentNameById = <String, String>{
      for (final dep in departments)
        if (dep.id.trim().isNotEmpty) dep.id: dep.displayName,
    };

    final buckets = <String, _DeptBucket>{};
    _DeptBucket unassignedBucket = _DeptBucket(name: unassignedLabel);
    for (final entry in entries) {
      final requestedForId = entry.item.requestedForId?.trim() ?? '';
      final memberDeptId = requestedForId.isEmpty
          ? ''
          : (membersByMembershipId[requestedForId]?.departmentId?.trim() ?? '');
      final directDeptId = entry.item.departmentId?.trim() ?? '';
      final departmentId = memberDeptId.isNotEmpty ? memberDeptId : directDeptId;
      final memberDeptName = requestedForId.isEmpty
          ? null
          : membersByMembershipId[requestedForId]?.departmentName;
      final departmentName = (memberDeptName?.trim().isNotEmpty == true)
          ? memberDeptName!.trim()
          : (departmentNameById[departmentId]?.trim() ??
              (entry.item.displayDepartment.trim().isNotEmpty
                  ? entry.item.displayDepartment.trim()
                  : ''));

      if (departmentId.isNotEmpty) {
        final bucket = buckets.putIfAbsent(
          departmentId,
          () => _DeptBucket(
            name: departmentName.isEmpty
                ? departmentNameById[departmentId] ?? unassignedLabel
                : departmentName,
          ),
        );
        bucket.add(entry);
      } else if (departmentName.isNotEmpty) {
        final key = 'name:${departmentName.toLowerCase()}';
        final bucket = buckets.putIfAbsent(
          key,
          () => _DeptBucket(name: departmentName),
        );
        bucket.add(entry);
      } else {
        unassignedBucket.add(entry);
      }
    }

    final rows = <_HrDepartmentComplianceRow>[];
    for (final department in departments) {
      final bucket = buckets.remove(department.id);
      if (bucket == null) {
        rows.add(_HrDepartmentComplianceRow(
          name: department.displayName,
          requiredCount: 0,
          completedCount: 0,
          pendingCount: 0,
          overdueCount: 0,
          completionRate: 0.0,
        ));
      } else {
        rows.add(bucket.toRow(department.displayName));
      }
    }
    for (final leftover in buckets.entries) {
      rows.add(leftover.value.toRow(leftover.value.name));
    }
    if (unassignedBucket.requiredCount > 0) {
      rows.add(unassignedBucket.toRow(unassignedLabel));
    }
    return rows;
  }

  Widget _departmentCard(_HrDepartmentComplianceRow row) {
    final accent = _completionAccent(row.completionRate);
    return OwnerSurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  row.name,
                  style: const TextStyle(
                    color: WellarTheme.text,
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                  ),
                ),
              ),
              TonePill(
                label: row.requiredCount == 0
                    ? '-'
                    : '${(row.completionRate * 100).round()}%',
                color: accent,
              ),
            ],
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              minHeight: 6,
              value: row.completionRate.clamp(0.0, 1.0),
              color: accent,
              backgroundColor: const Color(0x223A4A6D),
            ),
          ),
          const SizedBox(height: 14),
          LayoutBuilder(
            builder: (context, constraints) {
              final wide = constraints.maxWidth >= 340;
              final itemWidth = wide
                  ? (constraints.maxWidth - 12) / 2
                  : constraints.maxWidth;
              return Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  _departmentMetric(
                    'Required',
                    '${row.requiredCount}',
                    itemWidth,
                  ),
                  _departmentMetric(
                    'Completed',
                    '${row.completedCount}',
                    itemWidth,
                  ),
                  _departmentMetric(
                    'Pending',
                    '${row.pendingCount}',
                    itemWidth,
                  ),
                  _departmentMetric(
                    'Overdue',
                    '${row.overdueCount}',
                    itemWidth,
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _departmentMetric(String label, String value, double width) {
    return Container(
      width: width,
      padding: const EdgeInsets.fromLTRB(12, 11, 12, 10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        color: const Color(0x1AFFFFFF),
        border: Border.all(color: const Color(0x18FFFFFF)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: WellarTheme.textMuted,
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: const TextStyle(
              color: WellarTheme.text,
              fontSize: 18,
              fontWeight: FontWeight.w800,
              height: 1,
            ),
          ),
        ],
      ),
    );
  }

  Widget _readinessCard({
    required dynamic lang,
    required WorkspaceReadinessSummary readinessSummary,
    required bool readinessFailed,
    required DateTime start,
    required DateTime end,
    required String periodLabel,
  }) {
    final readiness = readinessSummary.distribution;
    final total = readiness.values.fold<int>(0, (sum, item) => sum + item);
    final hasResults = !readinessFailed && total > 0;
    return OwnerSurfaceCard(
      onTap: () => Navigator.push(
        context,
        fadeSlideRoute(
          CompanyReadinessResultsScreen(
            initialSummary: readinessSummary,
            start: start,
            end: end,
            periodLabel: periodLabel,
          ),
        ),
      ),
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
          if (readinessFailed)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                children: [
                  const Icon(
                    Icons.info_outline_rounded,
                    color: Color(0xFFFFC46B),
                    size: 18,
                  ),
                  const SizedBox(width: 8),
                  const Expanded(
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
            ...readiness.entries.map((entry) {
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
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
                        fontSize: 15,
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

  ReportDetailEntry _toReportDetailEntry(_RequestReportEntry entry) {
    final item = entry.item;
    return ReportDetailEntry(
      icon: _statusIcon(entry.status),
      title: item.displayTarget,
      subtitle: _subtitleForEntry(entry),
      trailing: entry.status.label,
      department: item.displayDepartment,
      meta: _summaryMeta(entry),
      statusLabel: entry.status.label,
      email: item.requestedForEmail,
      role: item.requestedForRole,
    );
  }

  List<ReportDetailEntry> _buildMissingScanEntries(
    List<HrMemberView> members,
  ) {
    final missingMembers = members
        .where((member) => member.isHrReadyScopeMember && member.missingCheck)
        .toList();
    missingMembers.sort(
      (a, b) => a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase()),
    );
    return missingMembers
        .map(
          (member) => ReportDetailEntry(
            icon: Icons.pending_actions_rounded,
            title: member.displayName,
            email: member.displayEmail,
            role: member.roleLabel,
            department: member.departmentLabel,
            meta: member.lastCheckAt == null
                ? 'No scan completed today'
                : 'Last check: ${_formatDate(member.lastCheckAt)}',
            statusLabel: 'Missing',
          ),
        )
        .toList();
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

  void _openReportDetail(
    BuildContext context, {
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

  Widget _rangeSelector(dynamic lang) {
    return SizedBox(
      height: 40,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          _rangeChip(lang, _HrComplianceRange.today),
          const SizedBox(width: 8),
          _rangeChip(lang, _HrComplianceRange.sevenDays),
          const SizedBox(width: 8),
          _rangeChip(lang, _HrComplianceRange.thirtyDays),
        ],
      ),
    );
  }

  Widget _rangeChip(dynamic lang, _HrComplianceRange range) {
    final selected = _range == range;
    return ChoiceChip(
      label: Text(_rangeLabel(lang, range)),
      selected: selected,
      onSelected: (_) => setState(() {
        _range = range;
        _future = _load();
      }),
    );
  }

  Color _completionAccent(double value) {
    if (value >= 0.75) return const Color(0xFF6EE7A8);
    if (value >= 0.4) return const Color(0xFFFFC46B);
    return const Color(0xFFFF7A8F);
  }

  DateTime _rangeStart() {
    final now = DateTime.now();
    switch (_range) {
      case _HrComplianceRange.today:
        return DateTime(now.year, now.month, now.day);
      case _HrComplianceRange.sevenDays:
        final start = now.subtract(const Duration(days: 6));
        return DateTime(start.year, start.month, start.day);
      case _HrComplianceRange.thirtyDays:
        final start = now.subtract(const Duration(days: 29));
        return DateTime(start.year, start.month, start.day);
    }
  }

  DateTime _rangeEnd() {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day).add(const Duration(days: 1));
  }

  String _rangeLabel(dynamic lang, _HrComplianceRange range) {
    switch (range) {
      case _HrComplianceRange.today:
        return Tr.t(lang, 'range_today');
      case _HrComplianceRange.sevenDays:
        return Tr.t(lang, 'range_7_days');
      case _HrComplianceRange.thirtyDays:
        return Tr.t(lang, 'range_30_days');
    }
  }

  Widget _summaryLine(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                color: WellarTheme.textMuted,
                fontSize: 12,
              ),
            ),
          ),
          Text(
            value,
            style: const TextStyle(
              color: WellarTheme.text,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
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

class _HrComplianceData {
  final List<RequestItem> requests;
  final HrSnapshot? snapshot;
  final List<HrMemberView> members;
  final List<WorkspaceDepartment> departments;
  final int openAlertsCount;
  final WorkspaceReadinessSummary readinessSummary;
  final Map<String, OwnerAssessmentResult> assessmentsByScanId;
  final bool readinessFailed;

  const _HrComplianceData({
    required this.requests,
    required this.snapshot,
    required this.members,
    required this.departments,
    required this.openAlertsCount,
    required this.readinessSummary,
    required this.assessmentsByScanId,
    required this.readinessFailed,
  });
}

class _HrComplianceMetrics {
  final int requiredCount;
  final int completedCount;
  final int pendingCount;
  final int overdueCount;
  final int openAlertsCount;
  final int highRiskCount;
  final double completionRate;
  final Map<String, int> readinessDistribution;
  final List<ReportDetailEntry> pendingEntries;
  final List<ReportDetailEntry> overdueEntries;
  final List<_HrDepartmentComplianceRow> departmentRows;

  const _HrComplianceMetrics({
    required this.requiredCount,
    required this.completedCount,
    required this.pendingCount,
    required this.overdueCount,
    required this.openAlertsCount,
    required this.highRiskCount,
    required this.completionRate,
    required this.readinessDistribution,
    required this.pendingEntries,
    required this.overdueEntries,
    required this.departmentRows,
  });
}

class _HrDepartmentComplianceRow {
  final String name;
  final int requiredCount;
  final int completedCount;
  final int pendingCount;
  final int overdueCount;
  final double completionRate;

  const _HrDepartmentComplianceRow({
    required this.name,
    required this.requiredCount,
    required this.completedCount,
    required this.pendingCount,
    required this.overdueCount,
    required this.completionRate,
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

class _DeptBucket {
  String name;
  int requiredCount = 0;
  int completedCount = 0;
  int pendingCount = 0;
  int overdueCount = 0;

  _DeptBucket({required this.name});

  void add(_RequestReportEntry entry) {
    requiredCount += 1;
    switch (entry.status) {
      case NormalizedRequestStatus.completed:
        completedCount += 1;
        break;
      case NormalizedRequestStatus.pending:
        pendingCount += 1;
        break;
      case NormalizedRequestStatus.overdue:
        overdueCount += 1;
        break;
      case NormalizedRequestStatus.cancelled:
        break;
    }
  }

  _HrDepartmentComplianceRow toRow(String displayName) {
    final rate =
        requiredCount == 0 ? 0.0 : completedCount / requiredCount;
    return _HrDepartmentComplianceRow(
      name: displayName,
      requiredCount: requiredCount,
      completedCount: completedCount,
      pendingCount: pendingCount,
      overdueCount: overdueCount,
      completionRate: rate,
    );
  }
}

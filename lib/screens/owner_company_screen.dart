import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../i18n/tr.dart';
import '../models/request_item.dart';
import '../models/workspace_department.dart';
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
import 'report_metric_detail_screen.dart';

enum _OwnerComplianceRange { today, sevenDays, thirtyDays }

class OwnerCompanyScreen extends ConsumerStatefulWidget {
  const OwnerCompanyScreen({super.key});

  @override
  ConsumerState<OwnerCompanyScreen> createState() => _OwnerCompanyScreenState();
}

class _OwnerCompanyScreenState extends ConsumerState<OwnerCompanyScreen> {
  late Future<_OwnerComplianceData> _future;
  _OwnerComplianceRange _range = _OwnerComplianceRange.today;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<_OwnerComplianceData> _load() async {
    final results = await Future.wait<dynamic>([
      OwnerOpsService.instance.fetchWorkforce(),
      OwnerOpsService.instance.fetchDepartments(),
      RequestService.instance.fetchOwnerRequests(limit: 300),
      OwnerOpsService.instance.fetchWorkspaceReadinessSummary(
        start: _rangeStart(),
        end: _rangeEnd(),
      ),
    ]);
    return _OwnerComplianceData(
      members: (results[0] as List<OwnerMemberView>).toList(),
      departments: (results[1] as List<WorkspaceDepartment>).toList(),
      requests: (results[2] as List<RequestItem>).toList(),
      readinessSummary: results[3] as WorkspaceReadinessSummary,
    );
  }

  @override
  Widget build(BuildContext context) {
    final lang = ref.watch(appLanguageControllerProvider).language;
    final unread = ref.watch(unreadNotificationsProvider);
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: AnimatedWellarScreen(
        showBackground: false,
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
        child: FutureBuilder<_OwnerComplianceData>(
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
                    : Tr.t(lang, 'workspace_details_unavailable'),
                subtitle: forbidden
                    ? Tr.t(lang, 'access_unavailable')
                    : Tr.t(lang, 'unable_load_company_summary'),
                actionLabel: Tr.t(lang, 'retry'),
                onAction: () => setState(() => _future = _load()),
              );
            }

            final data = snapshot.data!;
            final metrics = _buildMetrics(
              requests: data.requests,
              members: data.members,
              departments: data.departments,
              readinessSummary: data.readinessSummary,
              unassignedLabel: Tr.t(lang, 'unassigned'),
            );

            return RefreshIndicator(
              onRefresh: () async => setState(() => _future = _load()),
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: [
                  SectionHeader(
                    title: Tr.t(lang, 'compliance'),
                    subtitle: _rangeLabel(lang, _range),
                    trailing: PageHeaderActions(
                      unreadCount: unread,
                      showAlertsTab: true,
                    ),
                  ),
                  const SizedBox(height: 14),
                  _rangeSelector(lang),
                  const SizedBox(height: 18),
                  SectionHeader(title: Tr.t(lang, 'operational_summary')),
                  const SizedBox(height: 10),
                  ResponsiveCardGrid(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      ResponsiveCardGridItem(
                        child: OwnerMetricCard(
                          label: 'Required',
                          value: metrics.requiredCount,
                          icon: Icons.assignment_outlined,
                        ),
                      ),
                      ResponsiveCardGridItem(
                        child: OwnerMetricCard(
                          label: Tr.t(lang, 'completed'),
                          value: metrics.completedCount,
                          icon: Icons.check_circle_outline_rounded,
                          accent: const Color(0xFF6EE7A8),
                        ),
                      ),
                      ResponsiveCardGridItem(
                        child: OwnerMetricCard(
                          label: Tr.t(lang, 'pending'),
                          value: metrics.pendingCount,
                          icon: Icons.hourglass_bottom_rounded,
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
                    ],
                  ),
                  const SizedBox(height: 18),
                  SectionHeader(title: _complianceOverviewTitle()),
                  const SizedBox(height: 10),
                  if (metrics.relevantEntries.isEmpty)
                    const SmartEmptyState(
                      icon: Icons.assignment_outlined,
                      title: 'No required checks in this period.',
                      subtitle: 'No scan requests are due or assigned for this period.',
                    )
                  else
                    ...metrics.relevantEntries.take(5).map(
                      (entry) => Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: _complianceCard(entry),
                      ),
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
                  if (data.readinessSummary.queryFailed)
                    const SmartEmptyState(
                      icon: Icons.insights_outlined,
                      title: 'Readiness distribution could not be loaded.',
                      subtitle:
                          'Completed assessment results for this workspace were not returned by the result query.',
                    )
                  else if (data.readinessSummary.totalCount == 0)
                    const SmartEmptyState(
                      icon: Icons.insights_outlined,
                      title: 'No completed assessments in this period.',
                      subtitle:
                          'Completed assessments will appear here after results are recorded.',
                    )
                  else
                    OwnerSurfaceCard(
                      child: Column(
                        children: _distributionEntries(
                          data.readinessSummary.distribution,
                        ).map((entry) {
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
                        }).toList(),
                      ),
                    ),
                  const SizedBox(height: 18),
                  SectionHeader(title: Tr.t(lang, 'quick_actions')),
                  const SizedBox(height: 10),
                  ResponsiveCardGrid(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      ResponsiveCardGridItem(
                        child: QuickActionButton(
                          title: 'Pending checks',
                          icon: Icons.hourglass_bottom_rounded,
                          onTap: () => _openReportDetail(
                            context,
                            title: 'Pending checks',
                            summaryLabel: Tr.t(lang, 'pending'),
                            summaryValue: '${metrics.pendingEntries.length}',
                            entries: _buildReportEntries(metrics.pendingEntries),
                            emptyTitle: 'No pending checks.',
                            emptyBody: 'No assigned scan requests are pending in this period.',
                          ),
                        ),
                      ),
                      ResponsiveCardGridItem(
                        child: QuickActionButton(
                          title: 'Overdue checks',
                          icon: Icons.schedule_outlined,
                          onTap: () => _openReportDetail(
                            context,
                            title: 'Overdue checks',
                            summaryLabel: Tr.t(lang, 'overdue'),
                            summaryValue: '${metrics.overdueEntries.length}',
                            entries: _buildReportEntries(metrics.overdueEntries),
                            emptyTitle: 'No overdue checks.',
                            emptyBody: 'No assigned scan requests are overdue in this period.',
                          ),
                        ),
                      ),
                      ResponsiveCardGridItem.fullWidth(
                        child: QuickActionButton(
                          title: _complianceOverviewTitle(),
                          subtitle: 'Review completed, pending, and overdue assigned checks',
                          icon: Icons.verified_user_outlined,
                          onTap: () => _openReportDetail(
                            context,
                            title: _complianceOverviewTitle(),
                            summaryLabel: 'Required',
                            summaryValue: '${metrics.requiredCount}',
                            entries: _buildReportEntries(metrics.relevantEntries),
                            emptyTitle: 'No required checks in this period.',
                            emptyBody: 'No scan requests are due or assigned for this period.',
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  QuickActionButton(
                    title: Tr.t(lang, 'send_request'),
                    icon: Icons.assignment_add,
                    onTap: () => Navigator.push(
                      context,
                      fadeSlideRoute(const AdminScanRequestsScreen()),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  _OwnerComplianceMetrics _buildMetrics({
    required List<RequestItem> requests,
    required List<OwnerMemberView> members,
    required List<WorkspaceDepartment> departments,
    required WorkspaceReadinessSummary readinessSummary,
    required String unassignedLabel,
  }) {
    debugPrint('[COMPLIANCE_TRACE] request_count=${requests.length}');
    final complianceEntries = requests
        .map((item) => _toComplianceEntry(
              item,
              readinessSummary.resultsByScanId,
            ))
        .toList();
    for (final entry in complianceEntries) {
      debugPrint(
        '[COMPLIANCE_TRACE] request_status=${entry.status.label} requested_at_present=${entry.requestedAt != null} due_at_present=${entry.dueAt != null} completed_at_present=${entry.completedAt != null} included_in_range=${_isRelevantForRange(entry)} exclusion_reason=${_complianceExclusionReason(entry) ?? '-'}',
      );
    }
    final relevantEntries = complianceEntries
        .where(_isRelevantForRange)
        .toList()
      ..sort((a, b) => _sortComplianceEntry(a, b));

    final pendingEntries = relevantEntries
        .where((entry) => entry.status == NormalizedRequestStatus.pending)
        .toList();
    final overdueEntries = relevantEntries
        .where((entry) => entry.status == NormalizedRequestStatus.overdue)
        .toList();
    final completedEntries = relevantEntries
        .where((entry) => entry.status == NormalizedRequestStatus.completed)
        .toList();

    final attentionEntries = completedEntries
        .where((entry) => entry.outcome == 'High Risk')
        .toList();

    return _OwnerComplianceMetrics(
      requiredCount: relevantEntries.length,
      completedCount: completedEntries.length,
      pendingCount: pendingEntries.length,
      overdueCount: overdueEntries.length,
      attentionCount: attentionEntries.length,
      pendingEntries: pendingEntries,
      overdueEntries: overdueEntries,
      relevantEntries: relevantEntries,
      departmentRows: _buildDepartmentRows(
        relevantEntries: relevantEntries,
        members: members,
        departments: departments,
        unassignedLabel: unassignedLabel,
      ),
    );
  }

  List<_DepartmentComplianceRow> _buildDepartmentRows({
    required List<_ComplianceEntry> relevantEntries,
    required List<OwnerMemberView> members,
    required List<WorkspaceDepartment> departments,
    required String unassignedLabel,
  }) {
    final activeMembersByDepartment = <String, int>{};
    for (final member in members.where((member) => member.isActive)) {
      final key = _departmentKey(member.departmentId, member.departmentName);
      if (key == null) continue;
      activeMembersByDepartment[key] =
          (activeMembersByDepartment[key] ?? 0) + 1;
    }

    final requestsByDepartment = <String, List<_ComplianceEntry>>{};
    for (final entry in relevantEntries) {
      final key = _departmentKey(entry.departmentId, entry.departmentName);
      if (key == null) continue;
      requestsByDepartment.putIfAbsent(key, () => <_ComplianceEntry>[]).add(entry);
    }

    final rows = <_DepartmentComplianceRow>[];
    final knownDepartmentKeys = <String>{};

    for (final department in departments) {
      final key = _departmentKey(department.id, department.displayName)!;
      knownDepartmentKeys.add(key);
      final departmentRequests = requestsByDepartment[key] ?? const <_ComplianceEntry>[];
      final counts = _countStatusList(departmentRequests);
      rows.add(
        _DepartmentComplianceRow(
          name: department.displayName,
          activeMembers: activeMembersByDepartment[key] ?? 0,
          requiredChecks: departmentRequests.length,
          completedChecks: counts.completed,
          pendingChecks: counts.pending,
          overdueChecks: counts.overdue,
          completionRate: departmentRequests.isEmpty
              ? 0
              : counts.completed / departmentRequests.length,
        ),
      );
    }

    return rows.where((row) => row.activeMembers > 0 || row.requiredChecks > 0).toList();
  }

  _ComplianceEntry _toComplianceEntry(
    RequestItem item,
    Map<String, OwnerAssessmentResult> resultsByScanId,
  ) {
    final status = RequestStatusNormalizer.normalize(item, log: false);
    final scanId = item.scanId?.trim() ?? '';
    final assessment = scanId.isEmpty ? null : resultsByScanId[scanId];
    return _ComplianceEntry(
      item: item,
      status: status,
      requestedAt: item.timestamp,
      dueAt: item.dueAt,
      completedAt: item.completedAt ?? assessment?.completedAt,
      departmentId: item.departmentId?.trim(),
      departmentName: item.departmentName?.trim().isNotEmpty == true
          ? item.departmentName!.trim()
          : null,
      outcome: assessment?.outcome,
      readinessScore: assessment?.readinessScore,
    );
  }

  bool _isRelevantForRange(_ComplianceEntry entry) {
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

  String? _complianceExclusionReason(_ComplianceEntry entry) {
    final start = _rangeStart();
    final end = _rangeEnd();
    switch (entry.status) {
      case NormalizedRequestStatus.completed:
        return _isBetween(entry.completedAt, start, end) ||
                _isBetween(entry.dueAt, start, end) ||
                _isBetween(entry.requestedAt, start, end)
            ? null
            : 'out_of_range_completed';
      case NormalizedRequestStatus.pending:
        return _isBetween(entry.dueAt, start, end) ||
                _isBetween(entry.requestedAt, start, end)
            ? null
            : 'out_of_range_pending';
      case NormalizedRequestStatus.overdue:
        if (entry.dueAt == null) return 'missing_due_date';
        if (!_isBetween(entry.dueAt, start, end)) return 'out_of_range_overdue';
        if (!entry.dueAt!.isBefore(DateTime.now())) return 'not_overdue';
        return null;
      case NormalizedRequestStatus.cancelled:
        return 'cancelled';
    }
  }

  int _sortComplianceEntry(_ComplianceEntry a, _ComplianceEntry b) {
    final priority = _statusPriority(b.status).compareTo(_statusPriority(a.status));
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

  _StatusCountSet _countStatusList(List<_ComplianceEntry> entries) {
    var completed = 0;
    var pending = 0;
    var overdue = 0;
    for (final entry in entries) {
      switch (entry.status) {
        case NormalizedRequestStatus.completed:
          completed += 1;
          break;
        case NormalizedRequestStatus.pending:
          pending += 1;
          break;
        case NormalizedRequestStatus.overdue:
          overdue += 1;
          break;
        case NormalizedRequestStatus.cancelled:
          break;
      }
    }
    return _StatusCountSet(
      completed: completed,
      pending: pending,
      overdue: overdue,
    );
  }

  List<ReportDetailEntry> _buildReportEntries(List<_ComplianceEntry> entries) {
    return entries.map((entry) {
      final item = entry.item;
      return ReportDetailEntry(
        icon: _statusIcon(entry.status),
        title: item.displayTarget,
        email: _secondaryEmail(item.displayTarget, item.requestedForEmail),
        role: item.requestedForRole,
        department: entry.departmentName ?? 'Unassigned',
        meta: _summaryMeta(entry),
        statusLabel: entry.status.label,
        subtitle: _subtitleForEntry(entry),
      );
    }).toList();
  }

  String _summaryMeta(_ComplianceEntry entry) {
    final lines = <String>[
      if (entry.requestedAt != null)
        'Requested: ${_formatDateTime(entry.requestedAt)}',
      if (entry.status == NormalizedRequestStatus.pending && entry.dueAt != null)
        'Due: ${_formatDateTime(entry.dueAt)}',
      if (entry.status == NormalizedRequestStatus.overdue && entry.dueAt != null)
        'Overdue since: ${_formatDateTime(entry.dueAt)}',
      if (entry.status == NormalizedRequestStatus.completed &&
          entry.completedAt != null)
        'Completed: ${_formatDateTime(entry.completedAt)}',
    ];
    return lines.join('  |  ');
  }

  String? _subtitleForEntry(_ComplianceEntry entry) {
    final segments = <String>[];
    if (entry.outcome != null) segments.add('Outcome: ${entry.outcome}');
    if (entry.readinessScore != null) {
      segments.add('Readiness score: ${entry.readinessScore}');
    }
    return segments.isEmpty ? null : segments.join('  |  ');
  }

  Widget _complianceCard(_ComplianceEntry entry) {
    final item = entry.item;
    final accent = _statusColor(entry.status);
    return OwnerSurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              InitialsAvatar(label: item.displayTarget, size: 44, accent: accent),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.displayTarget,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: WellarTheme.text,
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                      ),
                    ),
                    if ((item.requestedForEmail ?? '').trim().isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        item.requestedForEmail!.trim(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: WellarTheme.textMuted,
                          fontSize: 12,
                        ),
                      ),
                    ],
                    const SizedBox(height: 6),
                    Text(
                      entry.departmentName ?? 'Unassigned',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: WellarTheme.textMuted,
                        fontSize: 11.5,
                      ),
                    ),
                  ],
                ),
              ),
              TonePill(label: entry.status.label, color: accent),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if ((item.requestedForRole ?? '').trim().isNotEmpty)
                RoleChip(item.requestedForRole!.trim()),
            ],
          ),
          const SizedBox(height: 12),
          if (entry.requestedAt != null)
            _detailLine('Requested', _formatDateTime(entry.requestedAt)),
          if (entry.status == NormalizedRequestStatus.pending && entry.dueAt != null)
            _detailLine('Due', _formatDateTime(entry.dueAt)),
          if (entry.status == NormalizedRequestStatus.overdue && entry.dueAt != null)
            _detailLine('Overdue since', _formatDateTime(entry.dueAt)),
          if (entry.status == NormalizedRequestStatus.completed &&
              entry.completedAt != null)
            _detailLine('Completed', _formatDateTime(entry.completedAt)),
          if (entry.outcome != null) _detailLine('Outcome', entry.outcome!),
          if (entry.readinessScore != null)
            _detailLine('Readiness score', entry.readinessScore!),
        ],
      ),
    );
  }

  Widget _detailLine(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          SizedBox(
            width: 102,
            child: Text(
              label,
              style: const TextStyle(
                color: WellarTheme.textMuted,
                fontSize: 11.5,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                color: WellarTheme.text,
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _openReportDetail(
    BuildContext context, {
    required String title,
    required String summaryLabel,
    required String summaryValue,
    required List<ReportDetailEntry> entries,
    String? emptyTitle,
    String? emptyBody,
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
          emptyTitle: emptyTitle,
          emptyBody: emptyBody,
        ),
      ),
    );
  }

  Widget _departmentCard(_DepartmentComplianceRow row) {
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
                label: '${(row.completionRate * 100).round()}%',
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
          ResponsiveCardGrid(
            spacing: 12,
            runSpacing: 12,
            children: [
              ResponsiveCardGridItem(
                child: _departmentMetric('Active members', '${row.activeMembers}'),
              ),
              ResponsiveCardGridItem(
                child: _departmentMetric('Required', '${row.requiredChecks}'),
              ),
              ResponsiveCardGridItem(
                child: _departmentMetric('Completed', '${row.completedChecks}'),
              ),
              ResponsiveCardGridItem(
                child: _departmentMetric('Pending', '${row.pendingChecks}'),
              ),
              ResponsiveCardGridItem(
                child: _departmentMetric('Overdue', '${row.overdueChecks}'),
              ),
              ResponsiveCardGridItem.fullWidth(
                child: _departmentMetric(
                  'Completion rate',
                  '${(row.completionRate * 100).round()}%',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _departmentMetric(String label, String value) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 11, 12, 10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        color: const Color(0x1AFFFFFF),
        border: Border.all(color: const Color(0x18FFFFFF)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
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

  Widget _rangeSelector(dynamic lang) {
    return SizedBox(
      height: 40,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          _rangeChip(lang, _OwnerComplianceRange.today),
          const SizedBox(width: 8),
          _rangeChip(lang, _OwnerComplianceRange.sevenDays),
          const SizedBox(width: 8),
          _rangeChip(lang, _OwnerComplianceRange.thirtyDays),
        ],
      ),
    );
  }

  Widget _rangeChip(dynamic lang, _OwnerComplianceRange range) {
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

  DateTime _rangeStart() {
    final now = DateTime.now();
    switch (_range) {
      case _OwnerComplianceRange.today:
        return DateTime(now.year, now.month, now.day);
      case _OwnerComplianceRange.sevenDays:
        final start = now.subtract(const Duration(days: 6));
        return DateTime(start.year, start.month, start.day);
      case _OwnerComplianceRange.thirtyDays:
        final start = now.subtract(const Duration(days: 29));
        return DateTime(start.year, start.month, start.day);
    }
  }

  DateTime _rangeEnd() {
    final start = _rangeStart();
    switch (_range) {
      case _OwnerComplianceRange.today:
        return start.add(const Duration(days: 1));
      case _OwnerComplianceRange.sevenDays:
        return start.add(const Duration(days: 7));
      case _OwnerComplianceRange.thirtyDays:
        return start.add(const Duration(days: 30));
    }
  }

  bool _isBetween(DateTime? value, DateTime start, DateTime end) {
    if (value == null) return false;
    final local = value.toLocal();
    return !local.isBefore(start) && local.isBefore(end);
  }

  String _rangeLabel(dynamic lang, _OwnerComplianceRange range) {
    switch (range) {
      case _OwnerComplianceRange.today:
        return Tr.t(lang, 'range_today');
      case _OwnerComplianceRange.sevenDays:
        return Tr.t(lang, 'range_7_days');
      case _OwnerComplianceRange.thirtyDays:
        return Tr.t(lang, 'range_30_days');
    }
  }

  Color _completionAccent(double value) {
    if (value >= 0.75) return const Color(0xFF6EE7A8);
    if (value >= 0.4) return const Color(0xFFFFC46B);
    return const Color(0xFFFF7A8F);
  }

  Color _statusColor(NormalizedRequestStatus status) {
    switch (status) {
      case NormalizedRequestStatus.completed:
        return const Color(0xFF6EE7A8);
      case NormalizedRequestStatus.pending:
        return const Color(0xFF7DBBFF);
      case NormalizedRequestStatus.overdue:
        return const Color(0xFFFFC46B);
      case NormalizedRequestStatus.cancelled:
        return WellarTheme.textMuted;
    }
  }

  IconData _statusIcon(NormalizedRequestStatus status) {
    switch (status) {
      case NormalizedRequestStatus.completed:
        return Icons.check_circle_outline_rounded;
      case NormalizedRequestStatus.pending:
        return Icons.hourglass_bottom_rounded;
      case NormalizedRequestStatus.overdue:
        return Icons.schedule_outlined;
      case NormalizedRequestStatus.cancelled:
        return Icons.block_outlined;
    }
  }

  String? _secondaryEmail(String name, String? email) {
    final value = email?.trim() ?? '';
    if (value.isEmpty) return null;
    if (name.trim().toLowerCase() == value.toLowerCase()) return null;
    return value;
  }

  String _formatDateTime(DateTime? value) {
    if (value == null) return '-';
    final local = value.toLocal();
    final day = local.day.toString().padLeft(2, '0');
    final month = local.month.toString().padLeft(2, '0');
    final year = local.year.toString();
    final hour = local.hour.toString().padLeft(2, '0');
    final minute = local.minute.toString().padLeft(2, '0');
    return '$day/$month/$year $hour:$minute';
  }

  String? _departmentKey(String? id, String? name) {
    final departmentId = id?.trim() ?? '';
    if (departmentId.isNotEmpty) return 'id:$departmentId';
    final departmentName = name?.trim() ?? '';
    if (departmentName.isNotEmpty) return 'name:${departmentName.toLowerCase()}';
    return null;
  }

  String _complianceOverviewTitle() {
    switch (_range) {
      case _OwnerComplianceRange.today:
        return 'Today\'s compliance';
      case _OwnerComplianceRange.sevenDays:
        return '7-day compliance';
      case _OwnerComplianceRange.thirtyDays:
        return '30-day compliance';
    }
  }

  List<MapEntry<String, int>> _distributionEntries(
    Map<String, int> distribution,
  ) {
    return [
      MapEntry('Stable', distribution['Stable'] ?? 0),
      MapEntry('Low Focus', distribution['Low Focus'] ?? 0),
      MapEntry('Elevated Fatigue', distribution['Elevated Fatigue'] ?? 0),
      MapEntry('High Risk', distribution['High Risk'] ?? 0),
    ];
  }

  Widget _distributionDot(String label) {
    Color color;
    switch (label) {
      case 'High Risk':
        color = const Color(0xFFFF7A8F);
        break;
      case 'Elevated Fatigue':
        color = const Color(0xFFFFC46B);
        break;
      case 'Low Focus':
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

class _OwnerComplianceData {
  final List<OwnerMemberView> members;
  final List<WorkspaceDepartment> departments;
  final List<RequestItem> requests;
  final WorkspaceReadinessSummary readinessSummary;

  const _OwnerComplianceData({
    required this.members,
    required this.departments,
    required this.requests,
    required this.readinessSummary,
  });
}

class _OwnerComplianceMetrics {
  final int requiredCount;
  final int completedCount;
  final int pendingCount;
  final int overdueCount;
  final int attentionCount;
  final List<_ComplianceEntry> pendingEntries;
  final List<_ComplianceEntry> overdueEntries;
  final List<_ComplianceEntry> relevantEntries;
  final List<_DepartmentComplianceRow> departmentRows;

  const _OwnerComplianceMetrics({
    required this.requiredCount,
    required this.completedCount,
    required this.pendingCount,
    required this.overdueCount,
    required this.attentionCount,
    required this.pendingEntries,
    required this.overdueEntries,
    required this.relevantEntries,
    required this.departmentRows,
  });
}

class _ComplianceEntry {
  final RequestItem item;
  final NormalizedRequestStatus status;
  final DateTime? requestedAt;
  final DateTime? dueAt;
  final DateTime? completedAt;
  final String? departmentId;
  final String? departmentName;
  final String? outcome;
  final String? readinessScore;

  const _ComplianceEntry({
    required this.item,
    required this.status,
    required this.requestedAt,
    required this.dueAt,
    required this.completedAt,
    required this.departmentId,
    required this.departmentName,
    required this.outcome,
    required this.readinessScore,
  });

  DateTime? get primaryDate => completedAt ?? dueAt ?? requestedAt;
}

class _DepartmentComplianceRow {
  final String name;
  final int activeMembers;
  final int requiredChecks;
  final int completedChecks;
  final int pendingChecks;
  final int overdueChecks;
  final double completionRate;

  const _DepartmentComplianceRow({
    required this.name,
    required this.activeMembers,
    required this.requiredChecks,
    required this.completedChecks,
    required this.pendingChecks,
    required this.overdueChecks,
    required this.completionRate,
  });
}

class _StatusCountSet {
  final int completed;
  final int pending;
  final int overdue;

  const _StatusCountSet({
    required this.completed,
    required this.pending,
    required this.overdue,
  });
}

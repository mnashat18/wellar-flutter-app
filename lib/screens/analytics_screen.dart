import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/request_item.dart';
import '../models/scan_result.dart';
import '../models/report_export.dart';
import '../state/app_providers.dart';
import '../utils/app_colors.dart';
import '../utils/page_transition.dart';
import '../widgets/animated_space_background.dart';
import '../widgets/app_buttons.dart';
import '../widgets/app_cards.dart';
import '../widgets/lux_header.dart';
import '../widgets/responsive_card_grid.dart';
import '../widgets/state_views.dart';
import 'pricing_screen.dart';
import 'export_screen.dart';
import 'subscription_paywall_screen.dart';

enum _TimeRange { week, month, quarter, all }

enum _StateFilter { all, stable, low, elevated, high }

extension _TimeRangeMeta on _TimeRange {
  String get label {
    switch (this) {
      case _TimeRange.week:
        return '7D';
      case _TimeRange.month:
        return '30D';
      case _TimeRange.quarter:
        return '90D';
      case _TimeRange.all:
        return 'All';
    }
  }

  int? get days {
    switch (this) {
      case _TimeRange.week:
        return 7;
      case _TimeRange.month:
        return 30;
      case _TimeRange.quarter:
        return 90;
      case _TimeRange.all:
        return null;
    }
  }
}

extension _StateFilterMeta on _StateFilter {
  String get label {
    switch (this) {
      case _StateFilter.all:
        return 'All';
      case _StateFilter.stable:
        return 'Stable';
      case _StateFilter.low:
        return 'Attention Needed';
      case _StateFilter.elevated:
        return 'Readiness Concern';
      case _StateFilter.high:
        return 'Action Required';
    }
  }
}

/// =============================================================
/// ANALYTICS SCREEN — ENTERPRISE EDITION
///
/// Philosophy:
/// - This screen is NOT a chart screen
/// - This is a "System Intelligence Surface"
/// - It tells a story about performance, risk & behavior
///
/// Intentional verbosity:
/// - Readability > brevity
/// - Explicit layers > clever tricks
/// =============================================================

class AnalyticsScreen extends ConsumerStatefulWidget {
  const AnalyticsScreen({super.key});

  @override
  ConsumerState<AnalyticsScreen> createState() => _AnalyticsScreenState();
}

class _AnalyticsScreenState extends ConsumerState<AnalyticsScreen>
    with TickerProviderStateMixin {
  // -------------------------------------------------------------
  // Animation system (Dark magic, but controlled)
  // -------------------------------------------------------------

  late final AnimationController _revealController;
  late final Animation<double> _fadeIn;
  late final Animation<Offset> _slideUp;
  _TimeRange _timeRange = _TimeRange.month;
  _StateFilter _stateFilter = _StateFilter.all;

  @override
  void initState() {
    super.initState();

    _revealController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    );

    _fadeIn = CurvedAnimation(parent: _revealController, curve: Curves.easeOut);

    _slideUp = Tween<Offset>(begin: const Offset(0, 0.08), end: Offset.zero)
        .animate(
          CurvedAnimation(
            parent: _revealController,
            curve: Curves.easeOutCubic,
          ),
        );

    // Trigger reveal after first frame
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _revealController.forward();
    });
  }

  @override
  void dispose() {
    _revealController.dispose();
    super.dispose();
  }

  // -------------------------------------------------------------
  // UI ROOT
  // -------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final subscriptionAsync = ref.watch(activeSubscriptionProvider);
    final access = subscriptionAsync.maybeWhen(
      data: (sub) =>
          ref.read(subscriptionServiceProvider).accessForSubscription(sub),
      orElse: () =>
          ref.read(subscriptionServiceProvider).accessForSubscription(null),
    );

    if (subscriptionAsync.isLoading) {
      return const Scaffold(
        backgroundColor: AppColors.background,
        body: Center(
          child: CircularProgressIndicator(color: AppColors.primarySoft),
        ),
      );
    }

    if (access.isExpired) {
      return const SubscriptionPaywallScreen(title: 'Analytics locked');
    }

    if (!access.canViewAnalytics) {
      return Scaffold(
        backgroundColor: AppColors.background,
        body: Stack(
          children: [
            const AnimatedSpaceBackground(),
            SafeArea(
              child: Center(
                child: _UpgradeGate(
                  title: 'Analytics locked',
                  message: 'Upgrade to Business to access analytics.',
                  onUpgrade: () {
                    Navigator.push(
                      context,
                      fadeSlideRoute(const PricingScreen()),
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      );
    }

    final historyAsync = ref.watch(historyProvider);
    final sentAsync = ref.watch(sentRequestsProvider);
    final incomingAsync = ref.watch(incomingRequestsProvider);
    final exportsAsync = ref.watch(exportsProvider);

    final hasError = historyAsync.hasError || exportsAsync.hasError;

    final isLoading =
        historyAsync.isLoading ||
        sentAsync.isLoading ||
        incomingAsync.isLoading ||
        exportsAsync.isLoading;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: Stack(
        children: [
          const AnimatedSpaceBackground(),
          SafeArea(
            child: hasError
                ? _buildErrorState(
                    historyAsync,
                    exportsAsync,
                  )
                : isLoading
                ? const SkeletonList()
                : FadeTransition(
                    opacity: _fadeIn,
                    child: SlideTransition(
                      position: _slideUp,
                      child: SingleChildScrollView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
                        child: _AnalyticsContent(
                          history: historyAsync.value ?? const [],
                          sent: sentAsync.value ?? const [],
                          incoming: incomingAsync.value ?? const [],
                          exports: exportsAsync.value ?? const [],
                          timeRange: _timeRange,
                          stateFilter: _stateFilter,
                          onTimeRangeChanged: (range) {
                            setState(() => _timeRange = range);
                          },
                          onStateFilterChanged: (filter) {
                            setState(() => _stateFilter = filter);
                          },
                        ),
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorState(
    AsyncValue a,
    AsyncValue b,
  ) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
      children: [
        const SizedBox(height: 80),
        StatusCard(
          title: 'Analytics unavailable',
          message:
              a.error?.toString() ??
              b.error?.toString() ??
              'Unknown error',
          icon: Icons.warning_amber_rounded,
          iconColor: AppColors.highRisk,
          actionText: 'Retry',
          onAction: () {},
        ),
      ],
    );
  }
}

/// =============================================================
/// INTERNAL VIEW MODEL
///
/// CTO note:
/// UI should NEVER aggregate business data inline.
/// This object is the single source of analytics truth.
/// =============================================================

class _AnalyticsViewModel {
  final List<ScanResult> history;
  final List<RequestItem> sent;
  final List<RequestItem> incoming;
  final List<ScanResult> previousHistory;
  final List<RequestItem> previousSent;
  final List<RequestItem> previousIncoming;

  _AnalyticsViewModel({
    required this.history,
    required this.sent,
    required this.incoming,
    required this.previousHistory,
    required this.previousSent,
    required this.previousIncoming,
  });

  // -------------------------------------------------------------
  // Core metrics
  // -------------------------------------------------------------

  int get totalScans => history.length;
  int get previousTotalScans => previousHistory.length;

  double get averageConfidenceNormalized {
    final values = history
        .map((e) => e.confidence)
        .whereType<double>()
        .toList();
    if (values.isEmpty) return 0;
    final avg = values.reduce((a, b) => a + b) / values.length;
    return (avg <= 1 ? avg : avg / 100).clamp(0, 1);
  }

  double get previousAverageConfidenceNormalized {
    final values = previousHistory
        .map((e) => e.confidence)
        .whereType<double>()
        .toList();
    if (values.isEmpty) return 0;
    final avg = values.reduce((a, b) => a + b) / values.length;
    return (avg <= 1 ? avg : avg / 100).clamp(0, 1);
  }

  double get approvalRate {
    final all = [...sent, ...incoming];
    final approved = all
        .where((e) => e.displayStatus.toLowerCase() == 'approved')
        .length;
    if (all.isEmpty) return 0;
    return approved / all.length;
  }

  double get previousApprovalRate {
    final all = [...previousSent, ...previousIncoming];
    final approved = all
        .where((e) => e.displayStatus.toLowerCase() == 'approved')
        .length;
    if (all.isEmpty) return 0;
    return approved / all.length;
  }

  double get performanceIndex =>
      (averageConfidenceNormalized + approvalRate) / 2;

  double get previousPerformanceIndex =>
      (previousAverageConfidenceNormalized + previousApprovalRate) / 2;

  double get riskRate {
    if (history.isEmpty) return 0;
    final high = history
        .where((e) => _normalizeState(e.overallState) == 'Action Required')
        .length;
    return high / history.length;
  }

  double get previousRiskRate {
    if (previousHistory.isEmpty) return 0;
    final high = previousHistory
        .where((e) => _normalizeState(e.overallState) == 'Action Required')
        .length;
    return high / previousHistory.length;
  }

  Map<String, int> get stateDistribution {
    final map = {
      'Stable': 0,
      'Attention Needed': 0,
      'Readiness Concern': 0,
      'Action Required': 0,
    };

    for (final r in history) {
      final key = _normalizeState(r.overallState);
      map[key] = (map[key] ?? 0) + 1;
    }
    return map;
  }

  static String _normalizeState(String value) {
    final v = value.toLowerCase();
    if (v.contains('stable')) return 'Stable';
    if (v.contains('low')) return 'Attention Needed';
    if (v.contains('elevated')) return 'Readiness Concern';
    if (v.contains('high')) return 'Action Required';
    return 'Stable';
  }

  double? deltaPercent(double current, double previous) {
    if (previous == 0) return null;
    return (current - previous) / previous;
  }
}

/// =============================================================
/// CONTENT COMPOSITION
/// =============================================================

class _AnalyticsContent extends StatelessWidget {
  final List<ScanResult> history;
  final List<RequestItem> sent;
  final List<RequestItem> incoming;
  final List<ReportExport> exports;
  final _TimeRange timeRange;
  final _StateFilter stateFilter;
  final ValueChanged<_TimeRange> onTimeRangeChanged;
  final ValueChanged<_StateFilter> onStateFilterChanged;

  const _AnalyticsContent({
    required this.history,
    required this.sent,
    required this.incoming,
    required this.exports,
    required this.timeRange,
    required this.stateFilter,
    required this.onTimeRangeChanged,
    required this.onStateFilterChanged,
  });

  @override
  Widget build(BuildContext context) {
    final filtered = _filterHistory(history, timeRange, stateFilter);
    final previous = _previousHistory(history, timeRange, stateFilter);
    final filteredSent = _filterRequests(sent, timeRange);
    final filteredIncoming = _filterRequests(incoming, timeRange);
    final previousSent = _previousRequests(sent, timeRange);
    final previousIncoming = _previousRequests(incoming, timeRange);

    final vm = _AnalyticsViewModel(
      history: filtered,
      sent: filteredSent,
      incoming: filteredIncoming,
      previousHistory: previous,
      previousSent: previousSent,
      previousIncoming: previousIncoming,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _Header(),
        const SizedBox(height: 16),
        _FilterBar(
          timeRange: timeRange,
          stateFilter: stateFilter,
          onTimeRangeChanged: onTimeRangeChanged,
          onStateFilterChanged: onStateFilterChanged,
        ),
        const SizedBox(height: 18),
        _PerformanceHero(vm: vm),
        const SizedBox(height: 18),
        _StatsGrid(vm: vm),
        const SizedBox(height: 20),
        _CompareSection(vm: vm, timeRange: timeRange),
        const SizedBox(height: 20),
        _DistributionSection(vm: vm),
        const SizedBox(height: 20),
        _ReportsSection(exports: exports),
      ],
    );
  }

  List<ScanResult> _filterHistory(
    List<ScanResult> items,
    _TimeRange range,
    _StateFilter filter,
  ) {
    var results = items;
    final days = range.days;
    if (days != null) {
      final cutoff = DateTime.now().subtract(Duration(days: days));
      results = results
          .where((r) => r.dateCreated != null && r.dateCreated!.isAfter(cutoff))
          .toList();
    }
    if (filter != _StateFilter.all) {
      final stateKey = filter.label.toLowerCase();
      results = results.where((r) {
        final state = r.overallState.toLowerCase();
        return state.contains(stateKey.split(' ').first);
      }).toList();
    }
    return results;
  }

  List<ScanResult> _previousHistory(
    List<ScanResult> items,
    _TimeRange range,
    _StateFilter filter,
  ) {
    final days = range.days;
    if (days == null) return const [];
    final now = DateTime.now();
    final end = now.subtract(Duration(days: days));
    final start = end.subtract(Duration(days: days));
    var results = items.where((r) {
      final date = r.dateCreated;
      if (date == null) return false;
      return date.isAfter(start) && date.isBefore(end);
    }).toList();
    if (filter != _StateFilter.all) {
      final stateKey = filter.label.toLowerCase();
      results = results.where((r) {
        final state = r.overallState.toLowerCase();
        return state.contains(stateKey.split(' ').first);
      }).toList();
    }
    return results;
  }

  List<RequestItem> _filterRequests(List<RequestItem> items, _TimeRange range) {
    final days = range.days;
    if (days == null) return items;
    final cutoff = DateTime.now().subtract(Duration(days: days));
    return items
        .where((r) => r.timestamp != null && r.timestamp!.isAfter(cutoff))
        .toList();
  }

  List<RequestItem> _previousRequests(
    List<RequestItem> items,
    _TimeRange range,
  ) {
    final days = range.days;
    if (days == null) return const [];
    final now = DateTime.now();
    final end = now.subtract(Duration(days: days));
    final start = end.subtract(Duration(days: days));
    return items
        .where(
          (r) =>
              r.timestamp != null &&
              r.timestamp!.isAfter(start) &&
              r.timestamp!.isBefore(end),
        )
        .toList();
  }
}

/// =============================================================
/// HEADER
/// =============================================================

class _Header extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return LuxHeader(
      title: 'Analytics',
      subtitle: 'Fleet readiness and dispatch intelligence',
      icon: Icons.analytics_rounded,
    );
  }
}

class _FilterBar extends StatelessWidget {
  final _TimeRange timeRange;
  final _StateFilter stateFilter;
  final ValueChanged<_TimeRange> onTimeRangeChanged;
  final ValueChanged<_StateFilter> onStateFilterChanged;

  const _FilterBar({
    required this.timeRange,
    required this.stateFilter,
    required this.onTimeRangeChanged,
    required this.onStateFilterChanged,
  });

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Filters',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _TimeRange.values
                .map(
                  (range) => _FilterChip(
                    label: range.label,
                    selected: range == timeRange,
                    onTap: () => onTimeRangeChanged(range),
                  ),
                )
                .toList(),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _StateFilter.values
                .map(
                  (filter) => _FilterChip(
                    label: filter.label,
                    selected: filter == stateFilter,
                    onTap: () => onStateFilterChanged(filter),
                  ),
                )
                .toList(),
          ),
        ],
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: selected
              ? AppColors.primarySoft.withValues(alpha: 0.22)
              : AppColors.backgroundAlt,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: selected ? AppColors.primarySoft : Colors.white12,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? AppColors.primarySoft : Colors.white70,
            fontSize: 11,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

class _PerformanceHero extends StatelessWidget {
  final _AnalyticsViewModel vm;

  const _PerformanceHero({required this.vm});

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: const EdgeInsets.all(20),
      child: Row(
        children: [
          _RadialGauge(
            value: vm.performanceIndex,
            label: '${(vm.performanceIndex * 100).round()}%',
          ),
          const SizedBox(width: 16),
          Expanded(
              child: Text(
                'Performance Index blends departure-readiness confidence '
                'and supervisor response quality.',
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 12,
                height: 1.5,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// =============================================================
/// STATS GRID
/// =============================================================

class _StatsGrid extends StatelessWidget {
  final _AnalyticsViewModel vm;

  const _StatsGrid({required this.vm});

  @override
  Widget build(BuildContext context) {
    return ResponsiveCardGrid(
      spacing: 12,
      runSpacing: 12,
      children: [
        ResponsiveCardGridItem(
          child: _StatTile(
            label: 'Shift Checks',
            value: vm.totalScans.toString(),
            color: AppColors.primarySoft,
          ),
        ),
        ResponsiveCardGridItem(
          child: _StatTile(
            label: 'Avg Confidence',
            value: '${(vm.averageConfidenceNormalized * 100).round()}%',
            color: AppColors.stable,
          ),
        ),
        ResponsiveCardGridItem(
          child: _StatTile(
            label: 'Approval Rate',
            value: '${(vm.approvalRate * 100).round()}%',
            color: AppColors.elevated,
          ),
        ),
        ResponsiveCardGridItem.fullWidth(
          child: _StatTile(
            label: 'Operational Status',
            value: vm.performanceIndex > 0.7 ? 'On Track' : 'Watch',
            color: AppColors.lowFocus,
          ),
        ),
      ],
    );
  }
}

class _StatTile extends StatelessWidget {
  final String label;
  final String value;
  final Color color;

  const _StatTile({
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(Icons.insights, color: color),
          ),
          const Spacer(),
          Text(
            label,
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 11,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

/// =============================================================
/// DISTRIBUTION
/// =============================================================

class _DistributionSection extends StatelessWidget {
  final _AnalyticsViewModel vm;

  const _DistributionSection({required this.vm});

  @override
  Widget build(BuildContext context) {
    final data = vm.stateDistribution;
    final maxValue = data.values.isEmpty
        ? 1
        : data.values.reduce((a, b) => a > b ? a : b);

    return AppCard(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Shift Check Distribution',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 14),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: data.entries.map((e) {
              final normalized = maxValue == 0 ? 0.0 : e.value / maxValue;
              return _AnimatedBar(
                label: e.key,
                value: e.value,
                normalized: normalized,
                color: _stateColor(e.key),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Color _stateColor(String state) {
    switch (state) {
      case 'Stable':
        return AppColors.stable;
      case 'Attention Needed':
        return AppColors.lowFocus;
      case 'Readiness Concern':
        return AppColors.elevated;
      case 'Action Required':
        return AppColors.highRisk;
      default:
        return AppColors.primarySoft;
    }
  }
}

class _AnimatedBar extends StatelessWidget {
  final String label;
  final int value;
  final double normalized;
  final Color color;

  const _AnimatedBar({
    required this.label,
    required this.value,
    required this.normalized,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final height = 28 + normalized * 60;

    return Column(
      children: [
        AnimatedContainer(
          duration: const Duration(milliseconds: 600),
          curve: Curves.easeOutBack,
          width: 12,
          height: height,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(10),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          label,
          textAlign: TextAlign.center,
          style: const TextStyle(color: AppColors.textSecondary, fontSize: 10),
        ),
        const SizedBox(height: 4),
        Text(
          value.toString(),
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w600,
            fontSize: 11,
          ),
        ),
      ],
    );
  }
}

/// =============================================================
/// RADIAL GAUGE (Dark magic but safe)
/// =============================================================

class _RadialGauge extends StatelessWidget {
  final double value;
  final String label;

  const _RadialGauge({required this.value, required this.label});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 78,
      height: 78,
      child: Stack(
        alignment: Alignment.center,
        children: [
          CustomPaint(size: const Size(78, 78), painter: _GaugePainter(value)),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _GaugePainter extends CustomPainter {
  final double value;

  _GaugePainter(this.value);

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.width / 2 - 6;

    final base = Paint()
      ..color = Colors.white12
      ..style = PaintingStyle.stroke
      ..strokeWidth = 6;

    final active = Paint()
      ..color = AppColors.primarySoft
      ..style = PaintingStyle.stroke
      ..strokeWidth = 6
      ..strokeCap = StrokeCap.round;

    canvas.drawCircle(center, radius, base);

    final sweep = 2 * pi * value.clamp(0, 1);
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -pi / 2,
      sweep,
      false,
      active,
    );
  }

  @override
  bool shouldRepaint(_) => false;
}

class _UpgradeGate extends StatelessWidget {
  final String title;
  final String message;
  final VoidCallback onUpgrade;

  const _UpgradeGate({
    required this.title,
    required this.message,
    required this.onUpgrade,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: AppCard(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.lock_outline,
              color: AppColors.primarySoft,
              size: 32,
            ),
            const SizedBox(height: 10),
            Text(
              title,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 12,
              ),
            ),
            const SizedBox(height: 14),
            PrimaryButton(
              text: 'View Plans',
              icon: Icons.upgrade_rounded,
              onPressed: onUpgrade,
            ),
          ],
        ),
      ),
    );
  }
}

class _ReportsSection extends StatelessWidget {
  final List<ReportExport> exports;

  const _ReportsSection({required this.exports});

  @override
  Widget build(BuildContext context) {
    final pending = exports
        .where((e) => e.status.toLowerCase() == 'pending')
        .length;
    final ready = exports
        .where((e) => e.status.toLowerCase() == 'ready')
        .length;
    final failed = exports
        .where((e) => e.status.toLowerCase() == 'failed')
        .length;

    return AppCard(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Reports & Exports',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              _ReportStat(
                label: 'Pending',
                value: pending,
                color: AppColors.lowFocus,
              ),
              const SizedBox(width: 10),
              _ReportStat(
                label: 'Ready',
                value: ready,
                color: AppColors.stable,
              ),
              const SizedBox(width: 10),
              _ReportStat(
                label: 'Failed',
                value: failed,
                color: AppColors.highRisk,
              ),
            ],
          ),
          const SizedBox(height: 12),
          SolidButton(
            text: 'Open Export Center',
            color: AppColors.primarySoft,
            onPressed: () {
              Navigator.push(context, fadeSlideRoute(const ExportScreen()));
            },
          ),
        ],
      ),
    );
  }
}

class _ReportStat extends StatelessWidget {
  final String label;
  final int value;
  final Color color;

  const _ReportStat({
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
        decoration: BoxDecoration(
          color: AppColors.backgroundAlt,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white12),
        ),
        child: Column(
          children: [
            Text(
              value.toString(),
              style: TextStyle(
                color: color,
                fontWeight: FontWeight.w700,
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 11,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CompareSection extends StatelessWidget {
  final _AnalyticsViewModel vm;
  final _TimeRange timeRange;

  const _CompareSection({required this.vm, required this.timeRange});

  @override
  Widget build(BuildContext context) {
    final rangeLabel = timeRange.days == null
        ? 'Compare to previous period'
        : 'Compare to previous ${timeRange.label}';

    return AppCard(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            rangeLabel,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 12),
          _CompareRow(
            label: 'Shift Checks',
            current: vm.totalScans.toString(),
            delta: _formatDelta(
              vm.deltaPercent(
                vm.totalScans.toDouble(),
                vm.previousTotalScans.toDouble(),
              ),
            ),
          ),
          const SizedBox(height: 10),
          _CompareRow(
            label: 'Avg Confidence',
            current: '${(vm.averageConfidenceNormalized * 100).round()}%',
            delta: _formatDelta(
              vm.deltaPercent(
                vm.averageConfidenceNormalized,
                vm.previousAverageConfidenceNormalized,
              ),
            ),
          ),
          const SizedBox(height: 10),
          _CompareRow(
            label: 'Approval Rate',
            current: '${(vm.approvalRate * 100).round()}%',
            delta: _formatDelta(
              vm.deltaPercent(vm.approvalRate, vm.previousApprovalRate),
            ),
          ),
          const SizedBox(height: 10),
          _CompareRow(
            label: 'Risk Index',
            current: '${(vm.riskRate * 100).round()}%',
            delta: _formatDelta(
              vm.deltaPercent(vm.riskRate, vm.previousRiskRate),
            ),
          ),
        ],
      ),
    );
  }

  _DeltaValue _formatDelta(double? delta) {
    if (delta == null) {
      return const _DeltaValue(text: '—', color: Colors.white38);
    }
    final percent = (delta * 100).round();
    if (percent == 0) {
      return const _DeltaValue(text: '0%', color: Colors.white38);
    }
    final isUp = percent > 0;
    final color = isUp ? AppColors.stable : AppColors.highRisk;
    final sign = isUp ? '+' : '';
    return _DeltaValue(text: '$sign$percent%', color: color);
  }
}

class _CompareRow extends StatelessWidget {
  final String label;
  final String current;
  final _DeltaValue delta;

  const _CompareRow({
    required this.label,
    required this.current,
    required this.delta,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 12,
            ),
          ),
        ),
        Text(
          current,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(width: 12),
        Text(
          delta.text,
          style: TextStyle(color: delta.color, fontWeight: FontWeight.w600),
        ),
      ],
    );
  }
}

class _DeltaValue {
  final String text;
  final Color color;

  const _DeltaValue({required this.text, required this.color});
}

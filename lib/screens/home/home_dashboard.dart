import 'package:flutter/material.dart';

import '../../models/scan_result.dart';
import '../../services/scan_service.dart';
import '../../state/session.dart';
import '../../utils/app_colors.dart';
import '../../utils/page_transition.dart';
import '../../widgets/app_cards.dart';
import '../../widgets/fade_slide.dart';
import '../../widgets/responsive_card_grid.dart';
import '../scan/scan_premium_components.dart';

import '../activity_screen.dart';
import '../analytics_screen.dart';
import '../export_screen.dart';
import '../insights_screen.dart';
import '../company_dashboard_screen.dart';

class HomeDashboard extends StatelessWidget {
  final HomeData data;
  final ValueChanged<ScanResult> onOpenDetails;
  final VoidCallback onOpenCreate;
  final int pendingRequests;

  const HomeDashboard({
    super.key,
    required this.data,
    required this.onOpenDetails,
    required this.onOpenCreate,
    this.pendingRequests = 0,
  });

  @override
  Widget build(BuildContext context) {
    final List<ScanResult> allResults = data.results;

    final ScanResult? latest =
        data.latest ?? (allResults.isNotEmpty ? allResults.first : null);

    final List<ScanResult> recent = data.recent.isNotEmpty
        ? data.recent
        : allResults.take(5).toList();

    final name = Session.instance.userName?.trim();
    final role = Session.instance.roleName?.trim();

    final displayName = (name != null && name.isNotEmpty)
        ? 'Welcome, $name'
        : 'Welcome back';

    final displayRole = (role != null && role.isNotEmpty)
        ? role
        : (Session.instance.isAdmin ? 'Admin' : 'User');

    final counts = data.countsByState;
    final total = data.total;
    final stable = counts['Stable'] ?? 0;
    final lowFocus = counts['Attention Needed'] ?? 0;
    final elevated = counts['Readiness Concern'] ?? 0;
    final highRisk = counts['Action Required'] ?? 0;
    final readiness = _readinessScore(latest, stable, total);

    return SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          FadeSlide(
            child: _buildHero(
              displayName,
              displayRole,
              readiness,
              total,
              pendingRequests,
            ),
          ),
          const SizedBox(height: 18),
          FadeSlide(
            delay: const Duration(milliseconds: 80),
            child: _StartScanPriorityCard(onTap: onOpenCreate),
          ),
          if (pendingRequests > 0) ...[
            const SizedBox(height: 12),
            FadeSlide(
              delay: const Duration(milliseconds: 120),
              child: _buildPendingCard(pendingRequests),
            ),
          ],
          const SizedBox(height: 22),
          FadeSlide(
            delay: const Duration(milliseconds: 220),
            child: _sectionHeader(
              'Fleet Readiness Pulse',
              trailing: total > 0 ? '$total checks' : 'No checks yet',
            ),
          ),
          const SizedBox(height: 10),
          FadeSlide(
            delay: const Duration(milliseconds: 250),
            child: _buildInsightBars(
              total: total,
              stable: stable,
              lowFocus: lowFocus,
              elevated: elevated,
              highRisk: highRisk,
            ),
          ),
          const SizedBox(height: 22),
          FadeSlide(
            delay: const Duration(milliseconds: 300),
            child: _sectionHeader(
              'Departure Readiness',
              trailing: latest != null ? 'Ready for dispatch review' : 'Awaiting pre-shift check',
            ),
          ),
          const SizedBox(height: 10),
          FadeSlide(
            delay: const Duration(milliseconds: 320),
            child: _buildLatestReport(latest),
          ),
          const SizedBox(height: 22),
          FadeSlide(
            delay: const Duration(milliseconds: 360),
            child: _sectionHeader('Recent Shift Checks'),
          ),
          const SizedBox(height: 10),
          FadeSlide(
            delay: const Duration(milliseconds: 380),
            child: _buildRecentScans(recent),
          ),
        ],
      ),
    );
  }

  double _readinessScore(ScanResult? latest, int stable, int total) {
    double score = 0;
    if (latest?.confidence != null) {
      score = latest!.confidence!;
    } else if (total > 0) {
      score = stable / total;
    }
    if (score > 1) {
      score = score / 100;
    }
    if (score.isNaN || score.isInfinite) {
      return 0;
    }
    return score.clamp(0, 1);
  }

  double _ratio(int part, int total) {
    if (total <= 0) return 0;
    return (part / total).clamp(0, 1);
  }

  double _averageConfidence(List<ScanResult> results) {
    if (results.isEmpty) return 0;
    final values = results
        .map((r) => r.confidence)
        .whereType<double>()
        .where((v) => v.isFinite && v >= 0);
    if (values.isEmpty) return 0;
    final sum = values.reduce((a, b) => a + b);
    return (sum / values.length).clamp(0, 1);
  }

  int _recentCount(List<ScanResult> results, {int days = 7}) {
    if (results.isEmpty) return 0;
    final cutoff = DateTime.now().subtract(Duration(days: days));
    return results
        .where((r) => r.dateCreated != null && r.dateCreated!.isAfter(cutoff))
        .length;
  }

  Widget _buildHero(
    String name,
    String role,
    double readiness,
    int total,
    int pendingRequests,
  ) {
    return AppCard(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        height: 1.2,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Role: $role',
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _MetricPill(
                          label: 'Readiness',
                          value: '${(readiness * 100).round()}%',
                          color: AppColors.primarySoft,
                        ),
                        _MetricPill(
                          label: 'Shift Checks',
                          value: total.toString(),
                          color: AppColors.accentGold,
                        ),
                        if (pendingRequests > 0)
                          _MetricPill(
                            label: 'Pending Clearance',
                            value: pendingRequests.toString(),
                            color: AppColors.lowFocus,
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              _ReadinessRing(value: readiness),
            ],
          ),
          const SizedBox(height: 16),
          const Divider(color: Colors.white12, height: 1),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _StatTile(
                  label: 'Stable',
                  value: data.countsByState['Stable'] ?? 0,
                  color: AppColors.stable,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _StatTile(
                  label: 'Action Required',
                  value: data.countsByState['Action Required'] ?? 0,
                  color: AppColors.highRisk,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPendingCard(int count) {
    return AppCard(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          Container(
            width: 46,
            height: 46,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AppColors.lowFocus.withOpacity(0.16),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.lowFocus.withOpacity(0.35)),
            ),
            child: const Icon(
              Icons.assignment_rounded,
              color: AppColors.lowFocus,
              size: 22,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Pending clearance requests',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '$count assignment request(s) waiting for your pre-shift check.',
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          const Icon(Icons.chevron_right, color: Colors.white30),
        ],
      ),
    );
  }

  Widget _buildQuickActions(BuildContext context) {
    final actions = [
      _QuickAction(
        label: 'Insights',
        subtitle: 'Focus map',
        icon: Icons.insights_rounded,
        color: AppColors.primarySoft,
        onTap: () {
          Navigator.push(context, fadeSlideRoute(const InsightsScreen()));
        },
      ),
      _QuickAction(
        label: 'Analytics',
        subtitle: 'Performance',
        icon: Icons.analytics_rounded,
        color: AppColors.elevated,
        onTap: () {
          Navigator.push(context, fadeSlideRoute(const AnalyticsScreen()));
        },
      ),
      _QuickAction(
        label: 'Activity',
        subtitle: 'Alerts',
        icon: Icons.notifications_none_rounded,
        color: AppColors.lowFocus,
        onTap: () {
          Navigator.push(context, fadeSlideRoute(const ActivityScreen()));
        },
      ),
      _QuickAction(
        label: 'Export',
        subtitle: 'Reports',
        icon: Icons.file_download_rounded,
        color: AppColors.accentGold,
        onTap: () {
          Navigator.push(context, fadeSlideRoute(const ExportScreen()));
        },
      ),
    ];

    if (Session.instance.isAdmin) {
      actions.add(
        _QuickAction(
          label: 'Company',
          subtitle: 'Control room',
          icon: Icons.apartment_rounded,
          color: AppColors.primarySoft,
          onTap: () {
            Navigator.push(
              context,
              fadeSlideRoute(const CompanyDashboardScreen()),
            );
          },
        ),
      );
    }

    return SizedBox(
      height: 140,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: actions.length,
        separatorBuilder: (_, __) => const SizedBox(width: 12),
        itemBuilder: (context, index) {
          return _QuickActionCard(action: actions[index]);
        },
      ),
    );
  }

  Widget _buildKpiGrid(List<_KpiMetric> metrics) {
    return ResponsiveCardGrid(
      spacing: 12,
      runSpacing: 12,
      children: [
        for (final metric in metrics)
          ResponsiveCardGridItem(
            child: _KpiCard(metric: metric),
          ),
      ],
    );
  }

  Widget _buildInsightBars({
    required int total,
    required int stable,
    required int lowFocus,
    required int elevated,
    required int highRisk,
  }) {
    return AppCard(
      padding: const EdgeInsets.all(18),
      child: Column(
        children: [
          _InsightBar(
            label: 'Stable',
            value: stable,
            total: total,
            color: AppColors.stable,
          ),
          const SizedBox(height: 12),
          _InsightBar(
            label: 'Attention Needed',
            value: lowFocus,
            total: total,
            color: AppColors.lowFocus,
          ),
          const SizedBox(height: 12),
          _InsightBar(
            label: 'Readiness Concern',
            value: elevated,
            total: total,
            color: AppColors.elevated,
          ),
          const SizedBox(height: 12),
          _InsightBar(
            label: 'Action Required',
            value: highRisk,
            total: total,
            color: AppColors.highRisk,
          ),
        ],
      ),
    );
  }

  Widget _buildLatestReport(ScanResult? latest) {
    if (latest == null) {
      return const AppCard(
        padding: EdgeInsets.all(18),
        child: Text(
          'No checks recorded yet. Complete a pre-shift check to view readiness insights.',
          style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
        ),
      );
    }

    final state = _displayState(latest.overallState);
    final color = _stateColor(state);

    return InkWell(
      onTap: () => onOpenDetails(latest),
      child: AppCard(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                StatusChip(text: state, color: color),
                const Spacer(),
                const Icon(Icons.chevron_right, color: Colors.white30),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              latest.explanation?.trim().isNotEmpty == true
                  ? latest.explanation!
                  : 'Readiness assessment completed. Tap to open dispatch details.',
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 12,
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 10,
              runSpacing: 8,
              children: [
                _MetaTag(
                  icon: Icons.schedule,
                  text: _formatDate(latest.dateCreated),
                ),
                _MetaTag(
                  icon: Icons.bolt,
                  text: latest.confidence != null
                      ? '${(latest.confidence! * 100).round()}% confidence'
                      : 'Confidence n/a',
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRecentScans(List<ScanResult> items) {
    if (items.isEmpty) {
      return const AppCard(
        padding: EdgeInsets.all(16),
        child: Text(
          'No checks recorded yet.',
          style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
        ),
      );
    }

    return AppCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: items.map((r) {
          final state = _displayState(r.overallState);
          final color = _stateColor(state);
          return InkWell(
            onTap: () => onOpenDetails(r),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(
                children: [
                  Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      color: color,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          state,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _formatDate(r.dateCreated),
                          style: const TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Icon(Icons.chevron_right, color: Colors.white24),
                ],
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _sectionHeader(String text, {String? trailing}) {
    return Row(
      children: [
        Text(
          text.toUpperCase(),
          style: const TextStyle(
            color: Colors.white,
            fontSize: 12,
            letterSpacing: 1.2,
            fontWeight: FontWeight.w700,
          ),
        ),
        const Spacer(),
        if (trailing != null)
          Text(
            trailing,
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 12,
            ),
          ),
      ],
    );
  }

  String _formatDate(DateTime? date) {
    if (date == null) return '-';
    final d = date.toLocal();
    return '${d.day}/${d.month}/${d.year} - ${d.hour}:${d.minute.toString().padLeft(2, '0')}';
  }

  String _displayState(String state) {
    final v = state.toLowerCase();
    if (v.contains('stable')) return 'Stable';
    if (v.contains('low')) return 'Attention Needed';
    if (v.contains('elevated')) return 'Readiness Concern';
    if (v.contains('high')) return 'Action Required';
    return state;
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

class _StartScanPriorityCard extends StatelessWidget {
  final VoidCallback onTap;

  const _StartScanPriorityCard({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GlassPanel(
      padding: const EdgeInsets.all(0),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(24),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Row(
              children: [
                Container(
                  width: 58,
                  height: 58,
                  decoration: BoxDecoration(
                    color: ScanTheme.primaryBlue.withOpacity(0.16),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(
                      color: ScanTheme.cyan.withOpacity(0.25),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: ScanTheme.primaryBlue.withOpacity(0.18),
                        blurRadius: 18,
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.radar_rounded,
                    color: ScanTheme.cyan,
                    size: 28,
                  ),
                ),
                const SizedBox(width: 14),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Start Scan',
                        style: TextStyle(
                          color: ScanTheme.textPrimary,
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      SizedBox(height: 4),
                      Text(
                        'Start pre-shift readiness check',
                        style: TextStyle(
                          color: ScanTheme.textPrimary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      SizedBox(height: 4),
                      Text(
                        'Video, voice, and focus in under 2 minutes',
                        style: TextStyle(
                          color: ScanTheme.textSecondary,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.arrow_forward_rounded, color: ScanTheme.cyan),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _MetricPill extends StatelessWidget {
  final String label;
  final String value;
  final Color color;

  const _MetricPill({
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.18),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.5)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            value,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w700,
              fontSize: 12,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(color: Colors.white70, fontSize: 11),
          ),
        ],
      ),
    );
  }
}

class _ReadinessRing extends StatelessWidget {
  final double value;

  const _ReadinessRing({required this.value});

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: value),
      duration: const Duration(milliseconds: 900),
      curve: Curves.easeOutCubic,
      builder: (context, v, _) {
        return SizedBox(
          width: 72,
          height: 72,
          child: Stack(
            alignment: Alignment.center,
            children: [
              CircularProgressIndicator(
                value: v,
                strokeWidth: 6,
                backgroundColor: Colors.white12,
                valueColor: const AlwaysStoppedAnimation(AppColors.primarySoft),
              ),
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '${(v * 100).round()}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 16,
                    ),
                  ),
                  const Text(
                    'Ready',
                    style: TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 10,
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}

class _StatTile extends StatelessWidget {
  final String label;
  final int value;
  final Color color;

  const _StatTile({
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.backgroundAlt,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white12),
      ),
      child: Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 11,
              ),
            ),
          ),
          _AnimatedCount(
            value: value,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w700,
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }
}

class _QuickAction {
  final String label;
  final String subtitle;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  const _QuickAction({
    required this.label,
    required this.subtitle,
    required this.icon,
    required this.color,
    required this.onTap,
  });
}

class _KpiMetric {
  final String label;
  final String value;
  final String subtitle;
  final IconData icon;
  final Color color;

  const _KpiMetric({
    required this.label,
    required this.value,
    required this.subtitle,
    required this.icon,
    required this.color,
  });
}

class _KpiCard extends StatelessWidget {
  final _KpiMetric metric;

  const _KpiCard({required this.metric});

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: metric.color.withOpacity(0.18),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: metric.color.withOpacity(0.45)),
            ),
            child: Icon(metric.icon, color: metric.color, size: 20),
          ),
          const SizedBox(height: 12),
          Text(
            metric.value,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w800,
              fontSize: 18,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            metric.label,
            style: const TextStyle(
              color: Colors.white70,
              fontWeight: FontWeight.w600,
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            metric.subtitle,
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }
}

class _QuickActionCard extends StatelessWidget {
  final _QuickAction action;

  const _QuickActionCard({required this.action});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: action.onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        width: 160,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.cardAlt,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.white12),
          boxShadow: [
            BoxShadow(
              color: action.color.withOpacity(0.2),
              blurRadius: 18,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: action.color.withOpacity(0.15),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: action.color.withOpacity(0.5)),
              ),
              child: Icon(action.icon, color: action.color, size: 20),
            ),
            const Spacer(),
            Text(
              action.label,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              action.subtitle,
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

class _InsightBar extends StatelessWidget {
  final String label;
  final int value;
  final int total;
  final Color color;

  const _InsightBar({
    required this.label,
    required this.value,
    required this.total,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final ratio = total == 0 ? 0.0 : value / total;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w600,
              ),
            ),
            const Spacer(),
            _AnimatedCount(
              value: value,
              style: TextStyle(color: color, fontWeight: FontWeight.w700),
            ),
          ],
        ),
        const SizedBox(height: 6),
        LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth * ratio;
            return Stack(
              children: [
                Container(
                  height: 8,
                  decoration: BoxDecoration(
                    color: Colors.white10,
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                AnimatedContainer(
                  duration: const Duration(milliseconds: 700),
                  curve: Curves.easeOutCubic,
                  height: 8,
                  width: width,
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ],
            );
          },
        ),
      ],
    );
  }
}

class _MetaTag extends StatelessWidget {
  final IconData icon;
  final String text;

  const _MetaTag({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.backgroundAlt,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: AppColors.textSecondary, size: 14),
          const SizedBox(width: 6),
          Text(
            text,
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }
}

class _AnimatedCount extends StatelessWidget {
  final int value;
  final TextStyle style;

  const _AnimatedCount({required this.value, required this.style});

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: value.toDouble()),
      duration: const Duration(milliseconds: 700),
      curve: Curves.easeOutCubic,
      builder: (context, v, _) {
        return Text(v.round().toString(), style: style);
      },
    );
  }
}

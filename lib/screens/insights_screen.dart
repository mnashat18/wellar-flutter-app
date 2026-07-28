import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/scan_result.dart';
import '../state/app_providers.dart';
import '../utils/app_colors.dart';
import '../widgets/animated_space_background.dart';
import '../widgets/app_cards.dart';
import '../widgets/lux_header.dart';
import '../widgets/state_views.dart';

class InsightsScreen extends ConsumerWidget {
  const InsightsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dataAsync = ref.watch(homeDataProvider);
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Stack(
        children: [
          const AnimatedSpaceBackground(),
          SafeArea(
            child: dataAsync.when(
              loading: () => const SkeletonList(),
              error: (error, _) => ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
                children: [
                  const SizedBox(height: 80),
                  StatusCard(
                    title: 'Failed to load insights',
                    message: error.toString(),
                    icon: Icons.warning_amber_rounded,
                    iconColor: AppColors.highRisk,
                    actionText: 'Retry',
                    onAction: () {},
                  ),
                ],
              ),
              data: (data) {
                final latest = data.latest;
                return RefreshIndicator(
                  color: AppColors.primarySoft,
                  onRefresh: () async {
                  },
                  child: SingleChildScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
                    child: FadeSlideIn(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildHeader(context),
                          const SizedBox(height: 16),
                          if (latest == null)
                            const EmptyStateCard(
                              title: 'No insights yet',
                              message: 'Run a scan to unlock insights.',
                            )
                          else ...[
                            _buildHeroCard(latest),
                            const SizedBox(height: 16),
                            _buildSignalCard(latest),
                            const SizedBox(height: 16),
                            _buildTrendCard(data.results),
                            const SizedBox(height: 16),
                            if (latest.medicalReport != null &&
                                latest.medicalReport!.isNotEmpty)
                              _buildReadinessNotesCard(latest.medicalReport!),
                          ],
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return LuxHeader(
      title: 'Insights',
      subtitle: 'Latest readiness signals and operational summary',
      icon: Icons.insights_rounded,
      onBack: () => Navigator.pop(context),
    );
  }

  Widget _buildHeroCard(ScanResult latest) {
    final state = _displayState(latest.overallState);
    final color = _stateColor(state);
    final confidence = _normalize(latest.confidence);
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AppColors.cardAlt,
            AppColors.cardAlt.withOpacity(0.7),
            AppColors.card,
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.3),
            blurRadius: 18,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(18),
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
                        state,
                        style: TextStyle(
                          color: color,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1.1,
                        ),
                      ),
                      const SizedBox(height: 6),
                      const Text(
                        'Latest Insight',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: 18,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        latest.explanation ??
                            'No detailed explanation yet. Complete another scan for richer insight.',
                        style: const TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 12,
                          height: 1.5,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        'Last scan: ${_formatDate(latest.dateCreated)}',
                        style: const TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                _ConfidenceRing(
                  value: confidence,
                  color: color,
                  label: _formatPercent(latest.confidence),
                ),
              ],
            ),
            const SizedBox(height: 16),
            const _PulseChart(),
          ],
        ),
      ),
    );
  }

  Widget _buildSignalCard(ScanResult latest) {
    return AppCard(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Signal Breakdown',
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              _InsightMetric(
                label: 'Overall',
                value: latest.confidence,
                color: AppColors.primarySoft,
              ),
              _InsightMetric(
                label: 'Camera',
                value: latest.cameraConfidence,
                color: AppColors.stable,
              ),
              _InsightMetric(
                label: 'Voice',
                value: latest.voiceConfidence,
                color: AppColors.elevated,
              ),
              _InsightMetric(
                label: 'Task',
                value: latest.taskPerformanceScore,
                color: AppColors.lowFocus,
              ),
              _InsightMetric(
                label: 'Drift',
                value: latest.confidenceDrift,
                color: AppColors.highRisk,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTrendCard(List<ScanResult> results) {
    final points = results.take(7).map(_scoreForResult).toList();
    if (points.isEmpty) {
      return const AppCard(
        padding: EdgeInsets.all(18),
        child: Text(
          'No trend data yet.',
          style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
        ),
      );
    }
    return AppCard(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Recent Trend',
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 12),
          _MiniBars(values: points),
          const SizedBox(height: 8),
          const Text(
            'Last 7 scans',
            style: TextStyle(
              color: AppColors.textSecondary,
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildReadinessNotesCard(String report) {
    return AppCard(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Readiness Notes',
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            report,
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 12,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }

  double _normalize(double? value) {
    if (value == null) return 0.0;
    if (value <= 1) return value.clamp(0.0, 1.0);
    return (value / 100).clamp(0.0, 1.0);
  }

  double _scoreForResult(ScanResult result) {
    final confidence = _normalize(result.confidence);
    if (confidence > 0) return confidence;
    switch (result.overallState.toLowerCase()) {
      case 'stable':
        return 0.85;
      case 'low focus':
      case 'low_focus':
        return 0.55;
      case 'elevated fatigue':
      case 'elevated_fatigue':
        return 0.45;
      case 'high risk':
      case 'high_risk':
        return 0.3;
      default:
        return 0.5;
    }
  }

  String _formatPercent(double? value) {
    if (value == null) return '--';
    final normalized = value <= 1 ? value * 100 : value;
    return '${normalized.toStringAsFixed(0)}%';
  }

  String _formatDate(DateTime? date) {
    if (date == null) return '-';
    final d = date.toLocal();
    final dd = d.day.toString().padLeft(2, '0');
    final mm = d.month.toString().padLeft(2, '0');
    final yyyy = d.year.toString();
    return '$dd/$mm/$yyyy';
  }

  Color _stateColor(String state) {
    switch (state.toLowerCase()) {
      case 'stable':
        return AppColors.stable;
      case 'low focus':
      case 'low_focus':
        return AppColors.lowFocus;
      case 'elevated fatigue':
      case 'elevated_fatigue':
        return AppColors.elevated;
      case 'high risk':
      case 'high_risk':
        return AppColors.highRisk;
      default:
        return AppColors.textSecondary;
    }
  }

  String _displayState(String state) {
    final v = state.trim().toLowerCase();
    if (v == 'stable') return 'Stable';
    if (v == 'low focus' || v == 'low_focus') return 'Attention Needed';
    if (v == 'elevated fatigue' || v == 'elevated_fatigue') {
      return 'Readiness Concern';
    }
    if (v == 'high risk' || v == 'high_risk') return 'Action Required';
    return state.isEmpty ? 'No Data' : state;
  }
}

class _InsightMetric extends StatelessWidget {
  final String label;
  final double? value;
  final Color color;

  const _InsightMetric({
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final normalized = _normalize(value);
    return Container(
      width: 150,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.cardAlt,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 11,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _formatPercent(value),
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w700,
              fontSize: 18,
            ),
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: normalized,
              minHeight: 6,
              backgroundColor: Colors.white12,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  double _normalize(double? value) {
    if (value == null) return 0.0;
    if (value <= 1) return value.clamp(0.0, 1.0);
    return (value / 100).clamp(0.0, 1.0);
  }

  String _formatPercent(double? value) {
    if (value == null) return '--';
    final normalized = value <= 1 ? value * 100 : value;
    return '${normalized.toStringAsFixed(0)}%';
  }
}

class _ConfidenceRing extends StatelessWidget {
  final double value;
  final Color color;
  final String label;

  const _ConfidenceRing({
    required this.value,
    required this.color,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 76,
      height: 76,
      child: Stack(
        alignment: Alignment.center,
        children: [
          CustomPaint(
            size: const Size(76, 76),
            painter: _RingPainter(value: value, color: color),
          ),
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

class _RingPainter extends CustomPainter {
  final double value;
  final Color color;

  const _RingPainter({required this.value, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 4;
    final basePaint = Paint()
      ..color = Colors.white12
      ..style = PaintingStyle.stroke
      ..strokeWidth = 6;
    final valuePaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 6
      ..strokeCap = StrokeCap.round;

    canvas.drawCircle(center, radius, basePaint);
    final sweep = 2 * 3.1415926 * value.clamp(0.0, 1.0);
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -1.5708,
      sweep,
      false,
      valuePaint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _PulseChart extends StatelessWidget {
  const _PulseChart();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 46,
      width: double.infinity,
      child: CustomPaint(
        painter: _PulsePainter(),
      ),
    );
  }
}

class _PulsePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = AppColors.primarySoft.withOpacity(0.8)
      ..strokeWidth = 2.2
      ..style = PaintingStyle.stroke;

    final path = Path();
    final midY = size.height / 2;
    final amplitude = size.height / 3.2;
    for (var i = 0.0; i <= size.width; i += 6) {
      final x = i;
      final y = midY + amplitude * (i % 24 == 0 ? -0.6 : 0.6);
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    canvas.drawPath(path, paint);

    final glowPaint = Paint()
      ..color = AppColors.primary.withOpacity(0.2)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 10;
    canvas.drawPath(path, glowPaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _MiniBars extends StatelessWidget {
  final List<double> values;

  const _MiniBars({required this.values});

  @override
  Widget build(BuildContext context) {
    final maxValue = values.fold<double>(0.0, (max, v) => v > max ? v : max);
    final safeMax = maxValue == 0 ? 1.0 : maxValue;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: values.map((value) {
        final height = 14 + (value / safeMax) * 50;
        return Expanded(
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 3),
            height: height,
            decoration: BoxDecoration(
              color: AppColors.primarySoft,
              borderRadius: BorderRadius.circular(8),
            ),
          ),
        );
      }).toList(),
    );
  }
}


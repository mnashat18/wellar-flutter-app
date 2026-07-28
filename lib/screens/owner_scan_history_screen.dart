/*
/*
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/history_entry.dart';
import '../models/scan_result.dart';
import '../state/app_providers.dart';
import '../theme/app_theme.dart';
import '../utils/page_transition.dart';
import '../widgets/animated_wellar_card.dart';
import '../widgets/animated_wellar_screen.dart';
import '../widgets/owner/owner_design_system.dart';
import '../widgets/wellar_empty_state.dart';
import '../widgets/wellar_error_state.dart';
import 'scan_details_screen.dart';

class OwnerScanHistoryScreen extends ConsumerWidget {
  const OwnerScanHistoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(historyTimelineProvider);
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: AnimatedWellarScreen(
        showBackground: false,
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
        child: RefreshIndicator(
          onRefresh: () async {
            ref.invalidate(historyTimelineProvider);
            await ref.read(historyTimelineProvider.future);
          },
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: EdgeInsets.zero,
            children: [
              const _Header(),
              const SizedBox(height: 18),
              async.when(
                loading: () => const OwnerSurfaceCard(
                  child: SizedBox(
                    height: 160,
                    child: Center(child: CircularProgressIndicator()),
                  ),
                ),
                error: (error, _) => WellarErrorState(
                  title: 'Failed to load scan history',
                  body: error.toString(),
                  onRetry: () => ref.invalidate(historyTimelineProvider),
                ),
                data: (entries) {
                  if (entries.isEmpty) {
                    return const WellarEmptyState(
                      icon: Icons.history_rounded,
                      title: 'No scans yet',
                      body: 'Your previous readiness checks will appear here.',
                    );
                  }
                  return Column(
                    children: entries
                        .asMap()
                        .entries
                        .map(
                          (entry) => AnimatedWellarCard(
                            delay: Duration(milliseconds: 45 * entry.key),
                            child: Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: _HistoryCard(entry: entry.value),
                            ),
                          ),
                        )
                        .toList(),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header();

  @override
  Widget build(BuildContext context) {
    return const OwnerSurfaceCard(
      glow: true,
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFF0F1830), Color(0xFF1A2644)],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Scan history',
            style: TextStyle(
              color: WellarTheme.text,
              fontSize: 26,
              fontWeight: FontWeight.w800,
            ),
          ),
          SizedBox(height: 6),
          Text(
            'Review your previous readiness checks',
            style: TextStyle(color: WellarTheme.textMuted, fontSize: 12),
          ),
        ],
      ),
    );
  }
}

class _HistoryCard extends StatelessWidget {
  final HistoryEntry entry;

  const _HistoryCard({required this.entry});

  @override
  Widget build(BuildContext context) {
    final result = entry.result;
    final state = _displayState(entry.readinessLabel, entry.status);
    final score = _scoreLabel(result, entry.status);
    final scanTime = _formatDate(entry.displayTime);
    final status = _displayStatus(entry.status);
    final preview = _previewText(result, entry.status);
    final color = _stateColor(state);

    return OwnerSurfaceCard(
      onTap: () => Navigator.push(
        context,
        fadeSlideRoute(ScanDetailsScreen(result: result, scanId: entry.scanId)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _MiniChip(label: score, color: WellarTheme.primary),
              const SizedBox(width: 8),
              _MiniChip(label: state, color: color),
              const Spacer(),
              _MiniChip(label: status, color: WellarTheme.textMuted),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            scanTime,
            style: const TextStyle(
              color: WellarTheme.textMuted,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          if (preview.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              preview,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: WellarTheme.text,
                fontSize: 13,
                height: 1.45,
              ),
            ),
          ],
        ],
      ),
    );
  }

  String _scoreLabel(ScanResult? result, String status) {
    final readiness = _toPercent(result?.readinessScore);
    if (readiness != null) return 'Score $readiness%';
    final confidence = _toPercent(result?.confidence);
    if (confidence != null) return 'Score $confidence%';
    if (status.trim().toLowerCase() == 'failed') {
      return 'Assessment could not be completed';
    }
    return 'Assessment could not be completed';
  }

  String _displayState(String value, String status) {
    final normalizedStatus = status.trim().toLowerCase();
    if (normalizedStatus == 'failed') return 'Retake needed';
    if (normalizedStatus == 'pending' ||
        normalizedStatus == 'processing' ||
        normalizedStatus == 'in_progress' ||
        normalizedStatus == 'media_ready') {
      return 'Processing assessment';
    }
    final v = value.trim().toLowerCase();
    if (v == 'stable') return 'Stable';
    if (v == 'low focus' || v == 'low_focus') return 'Low focus';
    if (v == 'elevated fatigue' || v == 'elevated_fatigue') {
      return 'Elevated fatigue';
    }
    if (v == 'high risk' || v == 'high_risk' || v == 'high') return 'High risk';
    return value.trim().isEmpty ? 'Processing assessment' : value;
  }

  String _displayStatus(String value) {
    final normalized = value.trim().toLowerCase();
    if (normalized.isEmpty) return 'Processing assessment';
    if (normalized == 'completed') return 'Completed';
    if (normalized == 'pending' ||
        normalized == 'processing' ||
        normalized == 'in_progress' ||
        normalized == 'media_ready') {
      return 'Processing assessment';
    }
    if (normalized == 'failed') return 'Assessment could not be completed';
    return normalized
        .split(RegExp(r'[_\s]+'))
        .where((part) => part.isNotEmpty)
        .map((part) => '${part[0].toUpperCase()}${part.substring(1)}')
        .join(' ');
  }

  String _previewText(ScanResult? result, String status) {
    final explanation = result?.explanation?.trim() ?? '';
    if (explanation.isNotEmpty) return explanation;
    if (status.trim().toLowerCase() == 'failed') {
      return 'Assessment could not be completed. Retake needed.';
    }
    return '';
  }

  int? _toPercent(double? value) {
    if (value == null) return null;
    if (value <= 1) return (value * 100).round();
    return value.round();
  }

  String _formatDate(DateTime? date) {
    if (date == null) return 'Scan time unavailable';
    final local = date.toLocal();
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${local.day.toString().padLeft(2, '0')} ${months[local.month - 1]} ${local.year} • ${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
  }

  Color _stateColor(String state) {
    switch (state) {
      case 'Stable':
        return const Color(0xFF72D8A0);
      case 'Low focus':
        return const Color(0xFF6DAFEA);
      case 'Elevated fatigue':
        return const Color(0xFFDFB35D);
      case 'High risk':
        return const Color(0xFFE38654);
      default:
        return WellarTheme.textMuted;
    }
  }
}

class _MiniChip extends StatelessWidget {
  final String label;
  final Color color;

  const _MiniChip({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
*/

import 'package:flutter/material.dart';

import 'history_screen.dart';

class OwnerScanHistoryScreen extends StatelessWidget {
  const OwnerScanHistoryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const HistoryScreen();
  }
}

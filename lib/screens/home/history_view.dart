/*
/*
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/scan_result.dart';
import '../../state/app_providers.dart';
import '../../utils/app_colors.dart';
import '../../utils/page_transition.dart';
import '../../widgets/app_cards.dart';
import '../../widgets/state_views.dart';
import '../scan_details_screen.dart';

class HistoryTab extends StatelessWidget {
  const HistoryTab({super.key});

  @override
  Widget build(BuildContext context) {
    return const _HistoryTab();
  }
}

class _HistoryTab extends ConsumerWidget {
  const _HistoryTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final historyAsync = ref.watch(historyProvider);
    return RefreshIndicator(
      color: AppColors.primarySoft,
      onRefresh: () async {
      },
      child: historyAsync.when(
        loading: () => const SkeletonList(),
        error: (error, _) => ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
          children: [
            const SizedBox(height: 80),
            StatusCard(
              title: 'Failed to load history',
              message: error.toString(),
              icon: Icons.warning_amber_rounded,
              iconColor: AppColors.highRisk,
              actionText: 'Retry',
              onAction: () {},
            ),
          ],
        ),
        data: (results) => HistoryView(
          results: results,
          onOpenDetails: (result) {
            Navigator.push(
            context,
            fadeSlideRoute(
              ScanDetailsScreen(
                scanId: result.scanId,
              ),
            ),
        );
      },

      ),
    ),
  );
}
}

class HistoryView extends StatelessWidget {
  final List<ScanResult> results;
  final ValueChanged<ScanResult> onOpenDetails;
  final String? highlightId;
  final GlobalKey? highlightKey;

  const HistoryView({
    required this.results,
    required this.onOpenDetails,
    this.highlightId,
    this.highlightKey,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Scan History',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    SizedBox(height: 6),
                    Text(
                      'Track pre-shift readiness and compliance over time.',
                      style: TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (results.isEmpty)
            const EmptyStateCard(
              title: 'No checks yet',
              message: 'Run a scan to see your history here.',
            )
          else
            ..._buildCards(results),
        ],
      ),
    );
  }

  List<Widget> _buildCards(List<ScanResult> results) {
    final items = <Widget>[];
    final target = highlightId?.trim();
    var used = false;
    for (final r in results) {
      final shouldHighlight =
          !used && target != null && _matchesHighlight(r, target);
      if (shouldHighlight) {
        used = true;
      }
      Widget card = _HistoryCard(
        result: r,
        onTap: () => onOpenDetails(r),
      );
      if (shouldHighlight) {
        final wrapped = _HighlightFrame(child: card);
        card = highlightKey != null
            ? KeyedSubtree(key: highlightKey, child: wrapped)
            : wrapped;
      }
      items.add(
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: card,
        ),
      );
    }
    return items;
  }

  bool _matchesHighlight(ScanResult result, String target) {
    return result.id == target || result.scanId == target;
  }
}

class _HistoryCard extends StatelessWidget {
  final ScanResult result;
  final VoidCallback onTap;

  const _HistoryCard({
    required this.result,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final date = _formatDate(result.dateCreated);
    final state = _displayState(result.overallState);
    final color = _stateColor(state);
    return AppCard(
      padding: const EdgeInsets.all(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    date,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                StatusChip(text: state, color: color),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              result.explanation ??
                  'No major readiness flags detected. Continue standard operations and re-scan as needed.',
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 12,
                height: 1.4,
              ),
            ),
          ],
        ),
      ),
    );
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

class _HighlightFrame extends StatefulWidget {
  final Widget child;

  const _HighlightFrame({required this.child});

  @override
  State<_HighlightFrame> createState() => _HighlightFrameState();
}

class _HighlightFrameState extends State<_HighlightFrame>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final t = Curves.easeInOut.transform(_controller.value);
        final border = 1.6 + 2.0 * t;
        final glow = 0.18 + 0.35 * t;
        return Container(
          padding: const EdgeInsets.all(2),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: AppColors.accentGold.withOpacity(0.75 + 0.2 * t),
              width: border,
            ),
            boxShadow: [
              BoxShadow(
                color: AppColors.accentGold.withOpacity(glow),
                blurRadius: 18 + 14 * t,
                spreadRadius: 1 + 2 * t,
              ),
            ],
          ),
          child: widget.child,
        );
      },
    );
  }
}
*/

import 'package:flutter/material.dart';

import '../../models/scan_result.dart';
import '../history_screen.dart';

class HistoryTab extends StatelessWidget {
  const HistoryTab({super.key});

  @override
  Widget build(BuildContext context) {
    return const HistoryScreen();
  }
}

class HistoryView extends StatelessWidget {
  final List<ScanResult> results;
  final ValueChanged<ScanResult> onOpenDetails;
  final String? highlightId;
  final GlobalKey? highlightKey;

  const HistoryView({
    required this.results,
    required this.onOpenDetails,
    this.highlightId,
    this.highlightKey,
  });

  @override
  Widget build(BuildContext context) {
    return const HistoryScreen();
  }
}


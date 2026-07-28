import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../i18n/tr.dart';
import '../models/history_entry.dart';
import '../state/app_language_state.dart';
import '../state/app_providers.dart';
import '../theme/app_theme.dart';
import '../utils/page_transition.dart';
import '../widgets/animated_wellar_card.dart';
import '../widgets/animated_wellar_screen.dart';
import '../widgets/wellar_card.dart';
import '../widgets/wellar_empty_state.dart';
import '../widgets/wellar_error_state.dart';
import 'scan_details_screen.dart';

class HistoryScreen extends ConsumerStatefulWidget {
  final String? highlightId;

  const HistoryScreen({super.key, this.highlightId});

  @override
  ConsumerState<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends ConsumerState<HistoryScreen> {
  @override
  Widget build(BuildContext context) {
    final lang = ref.watch(appLanguageControllerProvider).language;
    final async = ref.watch(ownerHistoryTimelineProvider);
    final canPop = Navigator.of(context).canPop();

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: AnimatedWellarScreen(
        showBackground: false,
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
        child: RefreshIndicator(
          onRefresh: () async {
            ref.read(refreshTickProvider.notifier).state++;
            ref.invalidate(ownerHistoryTimelineProvider);
          },
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: EdgeInsets.zero,
            children: [
              _Header(
                canPop: canPop,
                onBack: canPop ? () => Navigator.maybePop(context) : null,
              ),
              const SizedBox(height: 18),
              async.when(
                loading: () => const _HistoryLoadingState(),
                error: (error, _) => WellarErrorState(
                  title: Tr.t(lang, 'failed_load_history'),
                  body: _errorText(error, lang),
                  onRetry: () {
                    ref.read(refreshTickProvider.notifier).state++;
                    ref.invalidate(ownerHistoryTimelineProvider);
                  },
                ),
                data: (entries) => _HistoryContent(
                  entries: entries,
                  highlightId: widget.highlightId,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _errorText(Object error, AppLanguage lang) {
    final raw = error.toString().toLowerCase();
    if (raw.contains('permission') || raw.contains('403')) {
      return Tr.t(lang, 'history_unavailable_role');
    }
    if (raw.contains('session') || raw.contains('unauth')) {
      return Tr.t(lang, 'session_needs_refresh');
    }
    return Tr.t(lang, 'unable_load_history');
  }
}

class _Header extends StatelessWidget {
  final bool canPop;
  final VoidCallback? onBack;

  const _Header({required this.canPop, required this.onBack});

  @override
  Widget build(BuildContext context) {
    return WellarCard(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (canPop) ...[
            IconButton(
              onPressed: onBack,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints.tightFor(width: 40, height: 40),
              icon: const Icon(
                Icons.arrow_back_rounded,
                color: WellarTheme.text,
              ),
            ),
            const SizedBox(width: 8),
          ],
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Scan History',
                  style: TextStyle(
                    color: WellarTheme.text,
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                SizedBox(height: 6),
                Text(
                  'Review past scan reports',
                  style: TextStyle(
                    color: WellarTheme.textMuted,
                    fontSize: 12.5,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: WellarTheme.primary.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: WellarTheme.primary.withValues(alpha: 0.25),
              ),
            ),
            alignment: Alignment.center,
            child: const Icon(
              Icons.history_rounded,
              color: WellarTheme.primary,
              size: 20,
            ),
          ),
        ],
      ),
    );
  }
}

class _HistoryLoadingState extends StatelessWidget {
  const _HistoryLoadingState();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: List.generate(
        3,
        (index) => Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: AnimatedWellarCard(
            delay: Duration(milliseconds: 55 * index),
            child: const WellarCard(child: SizedBox(height: 88)),
          ),
        ),
      ),
    );
  }
}

class _HistoryContent extends StatelessWidget {
  final List<HistoryEntry> entries;
  final String? highlightId;

  const _HistoryContent({required this.entries, required this.highlightId});

  @override
  Widget build(BuildContext context) {
    final visibleEntries = _visibleEntries(entries);
    if (visibleEntries.isEmpty) {
      return const WellarEmptyState(
        icon: Icons.history_rounded,
        title: 'No scans yet',
        body: 'Run a scan to see your history here.',
      );
    }

    final groups = _groupEntries(visibleEntries);
    final widgets = <Widget>[];
    var index = 0;

    for (final group in groups) {
      if (group.entries.isEmpty) continue;
      if (widgets.isNotEmpty) {
        widgets.add(const SizedBox(height: 18));
      }
      widgets.add(
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Text(
            group.title,
            style: const TextStyle(
              color: WellarTheme.textMuted,
              fontSize: 12,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.3,
            ),
          ),
        ),
      );
      for (final entry in group.entries) {
        widgets.add(
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: AnimatedWellarCard(
              delay: Duration(milliseconds: 45 * index),
              child: _HistoryCard(
                entry: entry,
                highlighted: _isHighlighted(entry),
              ),
            ),
          ),
        );
        index++;
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: widgets,
    );
  }

  List<HistoryEntry> _visibleEntries(List<HistoryEntry> input) {
    final visible = <HistoryEntry>[];
    for (final entry in input) {
      if (_isRenderable(entry)) {
        visible.add(entry);
        continue;
      }
      debugPrint(
        '[HISTORY_FILTERED_ORPHAN] scan_id=${entry.scanId.trim().isNotEmpty ? entry.scanId : 'missing'} result_id=${entry.result?.id.trim().isNotEmpty == true ? entry.result!.id : 'missing'} status=${entry.status.trim().isNotEmpty ? entry.status.trim() : 'missing'}',
      );
    }
    return visible;
  }

  bool _isRenderable(HistoryEntry entry) {
    if (entry.hasResult) return true;
    final status = entry.status.trim().toLowerCase();
    if (status.isEmpty) return false;
    if (entry.scanId.trim().isEmpty) return false;
    return status == 'processing' ||
        status == 'in_progress' ||
        status == 'pending' ||
        status == 'media_ready' ||
        status == 'completed' ||
        status == 'failed' ||
        status == 'error' ||
        status == 'rejected' ||
        status == 'cancelled';
  }

  List<_HistoryGroup> _groupEntries(List<HistoryEntry> input) {
    final ordered = [...input]
      ..sort((a, b) {
        final aTime = a.displayTime ?? DateTime.fromMillisecondsSinceEpoch(0);
        final bTime = b.displayTime ?? DateTime.fromMillisecondsSinceEpoch(0);
        return bTime.compareTo(aTime);
      });

    final today = DateUtils.dateOnly(DateTime.now());
    final yesterday = today.subtract(const Duration(days: 1));
    final todayEntries = <HistoryEntry>[];
    final yesterdayEntries = <HistoryEntry>[];
    final earlierEntries = <HistoryEntry>[];

    for (final entry in ordered) {
      final time = entry.displayTime;
      if (time == null) {
        earlierEntries.add(entry);
        continue;
      }
      final local = DateUtils.dateOnly(time.toLocal());
      if (DateUtils.isSameDay(local, today)) {
        todayEntries.add(entry);
      } else if (DateUtils.isSameDay(local, yesterday)) {
        yesterdayEntries.add(entry);
      } else {
        earlierEntries.add(entry);
      }
    }

    return [
      _HistoryGroup(title: 'Today', entries: todayEntries),
      _HistoryGroup(title: 'Yesterday', entries: yesterdayEntries),
      _HistoryGroup(title: 'Earlier', entries: earlierEntries),
    ];
  }

  bool _isHighlighted(HistoryEntry entry) {
    final target = highlightId?.trim();
    if (target == null || target.isEmpty) return false;
    return entry.id == target || entry.scanId == target;
  }
}

class _HistoryCard extends StatelessWidget {
  final HistoryEntry entry;
  final bool highlighted;

  const _HistoryCard({required this.entry, required this.highlighted});

  @override
  Widget build(BuildContext context) {
    final state = _readinessLabel(entry);
    final dateTime = _formatDateTime(entry.displayTime);
    final tone = _stateTone(state);

    return WellarCard(
      highlighted: highlighted,
      padding: EdgeInsets.zero,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => Navigator.push(
            context,
            fadeSlideRoute(
              ScanDetailsScreen(result: entry.result, scanId: entry.scanId),
            ),
          ),
          borderRadius: BorderRadius.circular(WellarTheme.cardRadius),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        tone.color.withValues(alpha: 0.24),
                        tone.color.withValues(alpha: 0.10),
                      ],
                    ),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: tone.color.withValues(alpha: 0.24),
                    ),
                  ),
                  child: Icon(tone.icon, color: tone.color, size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        state,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: tone.color,
                          fontSize: 16.5,
                          fontWeight: FontWeight.w700,
                          height: 1.15,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        dateTime,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: WellarTheme.textMuted,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          height: 1.2,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                const Icon(
                  Icons.chevron_right_rounded,
                  color: WellarTheme.textMuted,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _readinessLabel(HistoryEntry entry) {
    final result = entry.result;
    if (result != null) {
      final raw = result.overallState.trim();
      final normalized = _normalizeState(raw);
      if (normalized == 'Stable' ||
          normalized == 'Low Focus' ||
          normalized == 'Elevated Fatigue' ||
          normalized == 'High Risk') {
        return normalized;
      }
    }
    final status = entry.status.trim().toLowerCase();
    if (!entry.hasResult &&
        (status == 'failed' ||
            status == 'error' ||
            status == 'rejected' ||
            status == 'cancelled')) {
      return 'Assessment could not be completed';
    }
    if (status == 'processing' ||
        status == 'in_progress' ||
        status == 'pending' ||
        status == 'media_ready' ||
        status == 'completed') {
      return 'Processing assessment';
    }
    return entry.hasResult
        ? 'Processing assessment'
        : 'Assessment could not be completed';
  }

  _HistoryTone _stateTone(String state) {
    switch (_normalizeState(state)) {
      case 'Stable':
        return const _HistoryTone(
          icon: Icons.check_circle_outline_rounded,
          color: Color(0xFF72D8A0),
        );
      case 'Low Focus':
        return const _HistoryTone(
          icon: Icons.center_focus_strong_rounded,
          color: Color(0xFFDAA94F),
        );
      case 'Elevated Fatigue':
        return const _HistoryTone(
          icon: Icons.battery_alert_rounded,
          color: Color(0xFFE08A52),
        );
      case 'High Risk':
        return const _HistoryTone(
          icon: Icons.warning_amber_rounded,
          color: Color(0xFFE05D63),
        );
      case 'Processing assessment':
        return const _HistoryTone(
          icon: Icons.hourglass_bottom_rounded,
          color: WellarTheme.textMuted,
        );
      case 'Assessment could not be completed':
        return const _HistoryTone(
          icon: Icons.restart_alt_rounded,
          color: Color(0xFF97A0B3),
        );
      default:
        return const _HistoryTone(
          icon: Icons.insights_rounded,
          color: WellarTheme.primary,
        );
    }
  }

  String _normalizeState(String value) {
    final v = value.trim().toLowerCase();
    if (v == 'stable') return 'Stable';
    if (v == 'low focus' || v == 'low_focus') return 'Low Focus';
    if (v == 'elevated fatigue' || v == 'elevated_fatigue') {
      return 'Elevated Fatigue';
    }
    if (v == 'high risk' || v == 'high_risk') return 'High Risk';
    if (v == 'processing assessment') return 'Processing assessment';
    if (v == 'assessment could not be completed') {
      return 'Assessment could not be completed';
    }
    if (v == 'no completed readiness result yet.') {
      return 'No completed readiness result yet.';
    }
    return value.trim().isEmpty ? 'Processing assessment' : value;
  }

  String _formatDateTime(DateTime? date) {
    if (date == null) return 'Scan time unavailable';
    final local = date.toLocal();
    const months = <String>[
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
    final day = local.day.toString().padLeft(2, '0');
    final month = months[local.month - 1];
    final year = local.year.toString();
    final hour = local.hour.toString().padLeft(2, '0');
    final minute = local.minute.toString().padLeft(2, '0');
    return '$day $month $year - $hour:$minute';
  }
}

class _HistoryGroup {
  final String title;
  final List<HistoryEntry> entries;

  const _HistoryGroup({required this.title, required this.entries});
}

class _HistoryTone {
  final IconData icon;
  final Color color;

  const _HistoryTone({required this.icon, required this.color});
}

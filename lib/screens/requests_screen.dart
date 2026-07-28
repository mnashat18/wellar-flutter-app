import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../i18n/tr.dart';
import '../models/request_item.dart';
import '../state/app_providers.dart';
import '../theme/app_theme.dart';
import '../utils/page_transition.dart';
import '../widgets/wellar_button.dart';
import '../widgets/wellar_card.dart';
import '../widgets/wellar_empty_state.dart';
import '../widgets/wellar_error_state.dart';
import '../widgets/wellar_header.dart';
import '../widgets/status_chip.dart';
import '../widgets/animated_wellar_screen.dart';
import '../widgets/animated_wellar_card.dart';
import '../widgets/wellar_skeleton_shimmer.dart';
import 'scan_flow_impl_normalized.dart';

class RequestsScreen extends ConsumerStatefulWidget {
  final String? highlightId;
  const RequestsScreen({super.key, this.highlightId});

  @override
  ConsumerState<RequestsScreen> createState() => _RequestsScreenState();
}

class _RequestsScreenState extends ConsumerState<RequestsScreen> {
  String _filter = 'All';

  @override
  Widget build(BuildContext context) {
    debugPrint('[SCAN_REQUESTS] load start');
    final lang = ref.watch(appLanguageControllerProvider).language;
    final async = ref.watch(incomingRequestsProvider);
    return Scaffold(
      backgroundColor: WellarTheme.bg,
      body: AnimatedWellarScreen(
        child: RefreshIndicator(
          onRefresh: () async => ref.invalidate(incomingRequestsProvider),
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            children: [
              WellarHeader(
                title: Tr.t(lang, 'assigned_requests_title'),
                subtitle: 'Current readiness requests for your account',
              ),
              const SizedBox(height: WellarTheme.sectionGap),
              _buildFilters(),
              const SizedBox(height: WellarTheme.sectionGap),
              async.when(
                loading: _loadingState,
                error: (e, _) => _errorState(e),
                data: (items) => _contentState(_applyFilter(items), lang),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFilters() {
    final lang = ref.watch(appLanguageControllerProvider).language;
    final values = [
      Tr.t(lang, 'all'),
      Tr.t(lang, 'pending'),
      Tr.t(lang, 'completed'),
      Tr.t(lang, 'overdue'),
    ];
    return SizedBox(
      height: 40,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemBuilder: (_, i) {
          final v = values[i];
          final selected = _filter == v;
          return ChoiceChip(
            label: Text(v),
            selected: selected,
            onSelected: (_) => setState(() => _filter = v),
          );
        },
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemCount: values.length,
      ),
    );
  }

  List<RequestItem> _applyFilter(List<RequestItem> input) {
    final lang = ref.watch(appLanguageControllerProvider).language;
    final all = Tr.t(lang, 'all');
    final pending = Tr.t(lang, 'pending');
    final completed = Tr.t(lang, 'completed');
    final overdue = Tr.t(lang, 'overdue');
    if (_filter == all) return input;
    if (_filter == pending) {
      return input.where((r) {
        final s = r.displayStatus.toLowerCase();
        return s == 'pending' || s == 'requested' || s == 'assigned';
      }).toList();
    }
    if (_filter == completed) {
      return input.where((r) => (r.scanId ?? '').trim().isNotEmpty || r.displayStatus.toLowerCase() == 'completed').toList();
    }
    if (_filter == overdue) {
      final now = DateTime.now();
      return input.where((r) {
        if (r.dueAt == null) return false;
        final completed = (r.scanId ?? '').trim().isNotEmpty || r.displayStatus.toLowerCase() == 'completed';
        return !completed && r.dueAt!.toLocal().isBefore(now);
      }).toList();
    }
    return input;
  }

  Widget _loadingState() {
    return Column(
      children: List.generate(
        3,
        (i) => Padding(
          padding: EdgeInsets.only(bottom: 12),
          child: AnimatedWellarCard(
            delay: Duration(milliseconds: 80 * i),
            child: const WellarCard(
              child: WellarSkeletonShimmer(height: 92),
            ),
          ),
        ),
      ),
    );
  }

  Widget _errorState(Object e) {
    final lang = ref.watch(appLanguageControllerProvider).language;
    final raw = e.toString().toLowerCase();
    if (raw.contains('403') || raw.contains('permission')) {
      return WellarEmptyState(
        icon: Icons.lock_outline_rounded,
        title: Tr.t(lang, 'access_unavailable'),
        body: Tr.t(lang, 'no_permission_assigned_requests'),
      );
    }
    return WellarErrorState(
      title: Tr.t(lang, 'unable_load_requests'),
      body: Tr.t(lang, 'unable_load_scan_requests'),
      onRetry: () => ref.invalidate(incomingRequestsProvider),
    );
  }

  Widget _contentState(List<RequestItem> items, dynamic lang) {
    debugPrint('[SCAN_REQUESTS] success count=${items.length}');
    if (items.isEmpty) {
      return WellarEmptyState(
        icon: Icons.assignment_turned_in_outlined,
        title: Tr.t(lang, 'no_assigned_requests_yet'),
        body: Tr.t(lang, 'requests_from_owner_hr'),
      );
    }
    return Column(
      children: items
          .asMap()
          .entries
          .map((e) => AnimatedWellarCard(
                delay: Duration(milliseconds: 65 * e.key),
                child: _card(e.value),
              ))
          .toList(),
    );
  }

  Widget _card(RequestItem item) {
    final lang = ref.watch(appLanguageControllerProvider).language;
    final status = item.displayStatus.toLowerCase();
    final isCompleted = (item.scanId ?? '').trim().isNotEmpty || status == 'completed';
    final canStart = !isCompleted && (status == 'pending' || status == 'requested' || status == 'assigned' || status.isEmpty);
    final due = item.dueAt?.toLocal();
    final requestedAt = item.timestamp?.toLocal();
    final requestedBy = item.requestedByUserName?.trim().isNotEmpty == true
        ? item.requestedByUserName!
        : Tr.t(lang, 'workspace_admin');

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: WellarCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    Tr.t(lang, 'preshift_readiness_check'),
                    style: const TextStyle(color: WellarTheme.text, fontWeight: FontWeight.w700),
                  ),
                ),
                StatusChip(isCompleted ? Tr.t(lang, 'completed') : (status.isEmpty ? Tr.t(lang, 'pending') : _cap(status))),
              ],
            ),
            const SizedBox(height: 8),
            Text('${Tr.t(lang, 'requested_by')}: $requestedBy', style: const TextStyle(color: WellarTheme.textMuted, fontSize: 12)),
            if (requestedAt != null)
              Text('${Tr.t(lang, 'requested_at')}: ${_fmt(requestedAt)}', style: const TextStyle(color: WellarTheme.textMuted, fontSize: 12)),
            if (due != null)
              Text('${Tr.t(lang, 'due')}: ${_fmt(due)}', style: const TextStyle(color: WellarTheme.textMuted, fontSize: 12)),
            const SizedBox(height: 12),
            if (canStart)
              WellarButton.primary(
                text: Tr.t(lang, 'start_scan'),
                onPressed: () {
                  Navigator.push(
                    context,
                    fadeSlideRoute(ScanFlowScreen(requestId: item.id, forceCompletion: true)),
                  ).then((_) => ref.invalidate(incomingRequestsProvider));
                },
              )
            else
              Text(
                Tr.t(lang, 'completed'),
                style: const TextStyle(color: WellarTheme.success, fontWeight: FontWeight.w700),
              ),
          ],
        ),
      ),
    );
  }

  String _cap(String value) {
    if (value.isEmpty) return value;
    return value[0].toUpperCase() + value.substring(1);
  }

  String _fmt(DateTime value) {
    return '${value.day}/${value.month}/${value.year} ${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')}';
  }
}

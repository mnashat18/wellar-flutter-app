import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../i18n/tr.dart';
import '../models/request_item.dart';
import '../services/employee_request_service.dart';
import '../state/app_providers.dart';
import '../theme/app_theme.dart';
import '../utils/page_transition.dart';
import '../widgets/animated_wellar_card.dart';
import '../widgets/animated_wellar_screen.dart';
import '../widgets/readiness_chip.dart';
import '../widgets/wellar_card.dart';
import '../widgets/wellar_empty_state.dart';
import '../widgets/wellar_error_state.dart';
import '../widgets/wellar_header.dart';
import '../widgets/wellar_skeleton_shimmer.dart';
import '../widgets/scan_request_action_card.dart';
import 'scan_flow_impl_normalized.dart';
import 'scan_request_details_screen.dart';

class EmployeeRequestsScreen extends ConsumerStatefulWidget {
  const EmployeeRequestsScreen({super.key});

  @override
  ConsumerState<EmployeeRequestsScreen> createState() =>
      _EmployeeRequestsScreenState();
}

class _EmployeeRequestsScreenState
    extends ConsumerState<EmployeeRequestsScreen> {
  late Future<List<RequestItem>> _future;
  String _filter = 'all';
  ProviderSubscription<int>? _refreshSubscription;

  @override
  void initState() {
    super.initState();
    _future = EmployeeRequestService.instance.fetchAssignedRequests();
    _refreshSubscription = ref.listenManual<int>(refreshTickProvider, (_, __) {
      if (!mounted) return;
      setState(() {
        _future = EmployeeRequestService.instance.fetchAssignedRequests();
      });
    });
  }

  @override
  void dispose() {
    _refreshSubscription?.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final lang = ref.watch(appLanguageControllerProvider).language;
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: AnimatedWellarScreen(
        showBackground: false,
        child: FutureBuilder<List<RequestItem>>(
          future: _future,
          builder: (context, snap) {
            if (snap.connectionState != ConnectionState.done) {
              return const WellarCard(
                child: WellarSkeletonShimmer(height: 180),
              );
            }
            if (snap.hasError) {
              return WellarErrorState(
                title: Tr.t(lang, 'access_unavailable'),
                body: Tr.t(lang, 'assigned_requests_unavailable'),
                onRetry: () => setState(
                  () => _future = EmployeeRequestService.instance
                      .fetchAssignedRequests(),
                ),
              );
            }
            final items = _applyFilter(snap.data ?? const []);
            return RefreshIndicator(
              onRefresh: () async => setState(
                () => _future = EmployeeRequestService.instance
                    .fetchAssignedRequests(),
              ),
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: [
                  WellarHeader(
                    title: Tr.t(lang, 'assigned_requests_title'),
                    subtitle: 'Current readiness requests for your account',
                  ),
                  const SizedBox(height: 10),
                  _filters(lang),
                  const SizedBox(height: 10),
                  if (items.isEmpty)
                    WellarEmptyState(
                      icon: Icons.assignment_outlined,
                      title: Tr.t(lang, 'no_assigned_requests_yet'),
                      body: Tr.t(lang, 'requests_from_owner_hr'),
                    )
                  else
                    ...items.asMap().entries.map((entry) {
                      final item = entry.value;
                      return AnimatedWellarCard(
                        delay: Duration(milliseconds: 40 + (entry.key * 25)),
                        child: Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: _requestCard(lang, item),
                        ),
                      );
                    }),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _filters(dynamic lang) {
    return Wrap(
      spacing: 8,
      children: [
        _chip(lang, 'all', Tr.t(lang, 'all')),
        _chip(lang, 'pending', Tr.t(lang, 'pending')),
        _chip(lang, 'completed', Tr.t(lang, 'completed')),
        _chip(lang, 'overdue', Tr.t(lang, 'overdue')),
      ],
    );
  }

  Widget _chip(dynamic lang, String id, String label) {
    final selected = _filter == id;
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => setState(() => _filter = id),
    );
  }

  List<RequestItem> _applyFilter(List<RequestItem> items) {
    if (_filter == 'all') return items;
    return items.where((i) {
      final status = i.displayStatus.toLowerCase();
      final completed = status == 'completed' || i.scanId != null;
      final overdue =
          !completed && i.dueAt != null && i.dueAt!.isBefore(DateTime.now());
      if (_filter == 'completed') return completed;
      if (_filter == 'overdue') return overdue;
      return !completed && !overdue;
    }).toList();
  }

  Widget _requestCard(dynamic lang, RequestItem item) {
    final canStart = item.isActionableCanonical && !item.hasCompletedScan;
    return ScanRequestActionCard(
      key: ValueKey(item.id),
      item: item,
      scope: ScanRequestCardScope.personal,
      canStartScan: canStart,
      onStartScan: canStart
          ? () => Navigator.push(
              context,
              fadeSlideRoute(
                ScanFlowScreen(requestId: item.id, forceCompletion: true),
              ),
            )
          : null,
      onViewDetails: () => Navigator.push(
        context,
        fadeSlideRoute(
          ScanRequestDetailsScreen(item: item, canStartScan: canStart),
        ),
      ),
    );
  }
}

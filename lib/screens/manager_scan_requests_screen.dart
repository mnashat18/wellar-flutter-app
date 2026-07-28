import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../i18n/tr.dart';
import '../models/request_item.dart';
import '../services/manager_request_service.dart';
import '../state/app_providers.dart';
import '../state/session.dart';
import '../theme/app_theme.dart';
import '../utils/page_transition.dart';
import '../widgets/animated_wellar_card.dart';
import '../widgets/animated_wellar_screen.dart';
import '../widgets/wellar_button.dart';
import '../widgets/wellar_card.dart';
import '../widgets/wellar_empty_state.dart';
import '../widgets/wellar_error_state.dart';
import '../widgets/wellar_header.dart';
import '../widgets/wellar_skeleton_shimmer.dart';
import '../widgets/scan_request_action_card.dart';
import 'scan_flow_impl_normalized.dart';
import 'scan_request_details_screen.dart';
import 'wellness_check_screen.dart';

class ManagerScanRequestsScreen extends ConsumerStatefulWidget {
  final String initialFilter;

  const ManagerScanRequestsScreen({
    super.key,
    this.initialFilter = 'all',
  });

  @override
  ConsumerState<ManagerScanRequestsScreen> createState() =>
      _ManagerScanRequestsScreenState();
}

class _ManagerScanRequestsScreenState
    extends ConsumerState<ManagerScanRequestsScreen> {
  late Future<List<RequestItem>> _future;
  String _filter = 'all';
  bool _loadAllRequests = true;
  ProviderSubscription<int>? _refreshSubscription;

  @override
  void initState() {
    super.initState();
    _filter = _normalizeFilter(widget.initialFilter);
    _loadAllRequests = _filter != 'pending';
    _future = _loadRequests();
    _refreshSubscription = ref.listenManual<int>(refreshTickProvider, (_, __) {
      _reload();
    });
  }

  Future<List<RequestItem>> _loadRequests() {
    return ManagerRequestService.instance.fetchTeamRequests(
      statusFilter: _loadAllRequests ? null : 'pending',
    );
  }

  void _reload() {
    if (!mounted) return;
    setState(() {
      _future = _loadRequests();
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
    final workspace = ref.watch(activeWorkspaceContextProvider);
    final membershipId = workspace?.membershipId.trim() ?? '';
    final currentUserId = Session.instance.userId?.trim() ?? '';
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
              final err = snap.error;
              final forbidden =
                  err is DioException && err.response?.statusCode == 403;
              return WellarErrorState(
                title: forbidden
                    ? Tr.t(lang, 'access_unavailable')
                    : Tr.t(lang, 'unable_load_requests'),
                body: forbidden
                    ? Tr.t(lang, 'role_unavailable_info')
                    : Tr.t(lang, 'requests_temporarily_unavailable'),
                onRetry: _reload,
              );
            }
            final items = _applyFilter(snap.data ?? const []);
            return RefreshIndicator(
              onRefresh: () async => _reload(),
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: [
                  WellarHeader(
                    title: Tr.t(lang, 'team_requests_title'),
                    subtitle: Tr.t(lang, 'team_requests_subtitle'),
                  ),
                  const SizedBox(height: 10),
                  WellarCard(
                    child: WellarButton.secondary(
                      text: Tr.t(lang, 'start_self_readiness_scan'),
                      onPressed: () => Navigator.push(
                        context,
                        fadeSlideRoute(const WellnessCheckScreen()),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    children: [
                      _chip(lang, 'all', Tr.t(lang, 'all')),
                      _chip(lang, 'pending', Tr.t(lang, 'pending')),
                      _chip(lang, 'completed', Tr.t(lang, 'completed')),
                      _chip(lang, 'overdue', Tr.t(lang, 'overdue')),
                    ],
                  ),
                  const SizedBox(height: 10),
                  if (items.isEmpty)
                    WellarEmptyState(
                      icon: Icons.assignment_outlined,
                      title: Tr.t(lang, 'no_scan_requests_yet'),
                      body: Tr.t(lang, 'team_requests_appear_here'),
                    )
                  else
                    ...items.asMap().entries.map((e) {
                      final item = e.value;
                      final assignedToYou = item.isAssignedToCurrentUser(
                        currentUserId: currentUserId,
                        currentMembershipId: membershipId,
                      );
                      final canStart =
                          assignedToYou && item.isActionableCanonical;
                      return AnimatedWellarCard(
                        delay: Duration(milliseconds: 40 + (e.key * 20)),
                        child: Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: ScanRequestActionCard(
                            key: ValueKey(item.id),
                            item: item,
                            scope: assignedToYou
                                ? ScanRequestCardScope.personal
                                : ScanRequestCardScope.team,
                            canStartScan: canStart,
                            onStartScan: canStart
                                ? () => Navigator.push(
                                    context,
                                    fadeSlideRoute(
                                      ScanFlowScreen(
                                        requestId: item.id,
                                        forceCompletion: true,
                                      ),
                                    ),
                                  )
                                : null,
                            onViewDetails: () => Navigator.push(
                              context,
                              fadeSlideRoute(
                                ScanRequestDetailsScreen(
                                  item: item,
                                  canStartScan: canStart,
                                ),
                              ),
                            ),
                          ),
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

  Widget _chip(dynamic lang, String id, String label) {
    return ChoiceChip(
      label: Text(label),
      selected: _filter == id,
      onSelected: (_) => setState(() {
        _filter = id;
        if (id != 'pending') {
          _loadAllRequests = true;
        }
        _future = _loadRequests();
      }),
    );
  }

  String _normalizeFilter(String value) {
    final normalized = value.trim().toLowerCase();
    switch (normalized) {
      case 'all':
      case 'pending':
      case 'completed':
      case 'overdue':
        return normalized;
      default:
        return 'all';
    }
  }

  List<RequestItem> _applyFilter(List<RequestItem> items) {
    if (_filter == 'all') return items;
    return items.where((i) {
      final done =
          i.displayStatus.toLowerCase() == 'completed' || i.scanId != null;
      final overdue =
          !done && i.dueAt != null && i.dueAt!.isBefore(DateTime.now());
      if (_filter == 'completed') return done;
      if (_filter == 'overdue') return overdue;
      return !done && !overdue;
    }).toList();
  }
}

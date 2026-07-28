import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/scan_result.dart';
import '../../models/request_item.dart';
import '../../state/app_providers.dart';
import '../../state/session.dart';
import '../../utils/app_colors.dart';
import '../../utils/page_transition.dart';
import '../../widgets/animated_space_background.dart';
import '../../widgets/app_buttons.dart';
import '../../widgets/app_cards.dart';
import '../../widgets/state_views.dart';
import '../../services/push_notification_service.dart';

import '../history_screen.dart';
import '../notifications_screen.dart';
import '../profile_screen.dart';
import '../requests_screen.dart';
import '../scan_details_screen.dart';
import '../wellness_check_screen.dart';
import '../../services/request_service.dart';
import '../scan_flow_impl_normalized.dart';
import 'home_dashboard.dart';

/* ============================================================
   HOME SCREEN â€” HISTORY DRIVEN (FINAL)
============================================================ */

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  int _index = 0;
  String? _lastAutoRequestId;
  DateTime? _lastAutoAt;
  bool _autoLaunching = false;
  bool _homeEffectsQueued = false;
  bool _isPushing = false;
  bool _promptVisible = false;
  String? _lastPromptRequestId;
  DateTime? _lastPromptAt;
  final Set<String> _notifiedPendingIds = {};
  final Set<String> _notifiedRiskScanIds = {};
  DateTime? _lastDailyPromptAt;
  DateTime? _lastDailyNotifyAt;
  late final _LifecycleObserver _lifecycleObserver;

  @override
  void initState() {
    super.initState();
    _lifecycleObserver = _LifecycleObserver(
      onResume: () {
        _checkPendingRequests();
      },
    );
    WidgetsBinding.instance.addObserver(_lifecycleObserver);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkPendingRequests();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(_lifecycleObserver);
    super.dispose();
  }

  void _setIndex(int index) {
    if (!mounted || index == _index) return;
    setState(() => _index = index);
  }

  @override
  Widget build(BuildContext context) {
    debugPrint('[HOME] loading shell');
    final unread = ref.watch(unreadNotificationsProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      body: Stack(
        children: [
          const AnimatedSpaceBackground(),
          SafeArea(
            bottom: false,
            child: Padding(
      padding: (_index == 3 || _index == 4)
              ? EdgeInsets.zero
              : const EdgeInsets.fromLTRB(20, 20, 20, 24),
              child: _buildPage(context),
            ),
          ),
          if (_index == 0) _buildTopActions(unread),
        ],
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        minimum: const EdgeInsets.fromLTRB(12, 0, 12, 8),
        child: _BottomNavBar(currentIndex: _index, onTap: _setIndex),
      ),
    );
  }

  // ===============================
  // TOP ACTIONS
  // ===============================

  Widget _buildTopActions(int unread) {
    return SafeArea(
      bottom: false,
      child: Align(
        alignment: Alignment.topRight,
        child: Padding(
          padding: const EdgeInsets.only(top: 12, right: 12),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _NotificationBell(
                count: unread,
                onTap: () {
                  _pushWhenReady(const NotificationsScreen());
                },
              ),
              const SizedBox(width: 10),
              _ProfileBadge(
                onTap: () {
                  _pushWhenReady(const ProfileScreen());
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ===============================
  // PAGE SWITCH
  // ===============================

  Widget _buildPage(BuildContext context) {
    switch (_index) {
      case 0:
        return _buildHome();
      case 1:
        return const RequestsScreen();
      case 2:
        return const HistoryScreen();
      case 3:
        return const NotificationsScreen();
      case 4:
        return const ProfileScreen();
      default:
        return const SizedBox.shrink();
    }
  }

  // ===============================
  // HOME CONTENT
  // ===============================

  Widget _buildHome() {
    final async = ref.watch(homeDataProvider);
    debugPrint('[HOME] data load start');
    final pendingCount = ref
        .watch(incomingRequestsProvider)
        .maybeWhen(
          data: (items) => items
              .where((item) => item.displayStatus.toLowerCase() == 'pending')
              .length,
          orElse: () => 0,
        );

    return async.when(
      loading: () => const SkeletonList(),
      error: (e, _) {
        debugPrint('[HOME] data load fail $e');
        return StatusCard(
          title: 'Failed to load',
          message: e.toString(),
          icon: Icons.warning_amber_rounded,
          iconColor: AppColors.highRisk,
          actionText: 'Retry',
          onAction: () => ref.invalidate(homeDataProvider),
        );
      },
      data: (data) {
        debugPrint('[HOME] data load success count=${data.results.length}');
        _scheduleHomeEffects(latest: data.latest, hasPending: pendingCount > 0);
        return HomeDashboard(
          data: data,
          pendingRequests: pendingCount,
          onOpenDetails: (latest) {
            _pushWhenReady(
              ScanDetailsScreen(result: latest, scanId: latest.scanId),
            );
          },
          onOpenCreate: _openWellnessCheck,
        );
      },
    );
  }

  void _scheduleHomeEffects({
    required ScanResult? latest,
    required bool hasPending,
  }) {
    if (_homeEffectsQueued) return;
    _homeEffectsQueued = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      _homeEffectsQueued = false;
      if (!mounted || _index != 0) return;
      if (latest != null) {
        _maybeNotifyRisk(latest);
      }
      await _maybePromptDailyScan(latest: latest, hasPending: hasPending);
    });
  }

  void _pushWhenReady(Widget page) {
    if (!mounted || _isPushing) return;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted || _isPushing) return;
      final route = ModalRoute.of(context);
      if (route == null || !route.isCurrent) return;
      _isPushing = true;
      try {
        await Navigator.push(context, fadeSlideRoute(page));
      } finally {
        if (mounted) {
          _isPushing = false;
        }
      }
    });
  }

  void _openWellnessCheck() {
    _pushWhenReady(const WellnessCheckScreen());
  }

  Future<void> _checkPendingRequests() async {
    if (_autoLaunching) return;
    final route = ModalRoute.of(context);
    if (route == null || !route.isCurrent) return;
    final userId = Session.instance.userId;
    if (userId == null || userId.isEmpty) return;
    try {
      _autoLaunching = true;
      final pending = await RequestService.instance.fetchIncomingRequests(
        userId: userId,
        limit: 1,
        statusFilter: 'pending',
      );
      if (!mounted || pending.isEmpty) return;
      final item = pending.first;
      final requestId = item.id;
      if (requestId.isEmpty) return;
      _maybeNotifyPending(item);

      if (_promptVisible) return;
      final now = DateTime.now();
      if (_lastPromptRequestId == requestId &&
          _lastPromptAt != null &&
          now.difference(_lastPromptAt!).inMinutes < 30) {
        return;
      }
      _lastPromptRequestId = requestId;
      _lastPromptAt = now;

      final shouldStart = await _showPendingPrompt(item);
      if (!mounted) return;
      if (!shouldStart) return;

      if (_lastAutoRequestId == requestId &&
          _lastAutoAt != null &&
          DateTime.now().difference(_lastAutoAt!).inMinutes < 2) {
        return;
      }
      _lastAutoRequestId = requestId;
      _lastAutoAt = DateTime.now();
      _pushWhenReady(
        ScanFlowScreen(requestId: requestId, forceCompletion: true),
      );
    } catch (_) {
      // best-effort
    } finally {
      _autoLaunching = false;
    }
  }

  void _maybeNotifyPending(RequestItem item) {
    final id = item.id.trim();
    if (id.isEmpty || _notifiedPendingIds.contains(id)) return;
    _notifiedPendingIds.add(id);
  }

  void _maybeNotifyRisk(ScanResult latest) {
    final scanId = latest.scanId.trim();
    if (scanId.isEmpty || _notifiedRiskScanIds.contains(scanId)) return;
    _notifiedRiskScanIds.add(scanId);
  }

  Future<bool> _showPendingPrompt(RequestItem item) async {
    _promptVisible = true;
    final source = (item.target ?? 'Admin').trim();
    final requiredState = (item.requiredState ?? '').trim();
    final result = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
          child: AppCard(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: AppColors.lowFocus.withOpacity(0.18),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: AppColors.lowFocus.withOpacity(0.5),
                        ),
                      ),
                      child: const Icon(
                        Icons.assignment_rounded,
                        color: AppColors.lowFocus,
                      ),
                    ),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Text(
                        'Scan required',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: 16,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  'Request from $source'
                  '${requiredState.isNotEmpty ? ' â€¢ Required: $requiredState' : ''}',
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 16),
                SolidButton(
                  text: 'Start pre-shift scan',
                  color: AppColors.primary,
                  onPressed: () => Navigator.pop(context, true),
                ),
                const SizedBox(height: 10),
                SolidButton(
                  text: 'Later',
                  color: AppColors.cardAlt,
                  onPressed: () => Navigator.pop(context, false),
                ),
              ],
            ),
          ),
        );
      },
    );
    _promptVisible = false;
    return result ?? false;
  }

  Future<void> _maybePromptDailyScan({
    required ScanResult? latest,
    required bool hasPending,
  }) async {
    if (!mounted) return;
    final route = ModalRoute.of(context);
    if (route == null || !route.isCurrent) return;
    if (hasPending) return;
    final last = latest?.dateCreated;
    final now = DateTime.now();
    if (last != null && now.difference(last).inHours < 24) return;

    if (_lastDailyPromptAt != null &&
        now.difference(_lastDailyPromptAt!).inHours < 6) {
      return;
    }

    _lastDailyPromptAt = now;
    final shouldStart = await _showDailyPrompt();
    if (shouldStart) {
      _openWellnessCheck();
    }

    if (_lastDailyNotifyAt == null ||
        now.difference(_lastDailyNotifyAt!).inHours >= 12) {
      _lastDailyNotifyAt = now;
      _pushDailyNotification();
    }
  }

  Future<bool> _showDailyPrompt() async {
    if (_promptVisible) return false;
    _promptVisible = true;
    final route = ModalRoute.of(context);
    if (route == null || !route.isCurrent) {
      _promptVisible = false;
      return false;
    }

    try {
      final result = await showModalBottomSheet<bool>(
        context: context,
        backgroundColor: Colors.transparent,
        isScrollControlled: true,
        builder: (context) {
          return Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
            child: AppCard(
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: AppColors.primarySoft.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: AppColors.primarySoft.withOpacity(0.5),
                          ),
                        ),
                        child: const Icon(
                          Icons.auto_awesome,
                          color: AppColors.primarySoft,
                        ),
                      ),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Text(
                          'Pre-shift scan reminder',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                            fontSize: 16,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Complete a quick pre-shift scan before departure to stay compliant.',
                    style: TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 16),
                  SolidButton(
                    text: 'Start pre-shift scan',
                    color: AppColors.primary,
                    onPressed: () => Navigator.pop(context, true),
                  ),
                  const SizedBox(height: 10),
                  SolidButton(
                    text: 'Later',
                    color: AppColors.cardAlt,
                    onPressed: () => Navigator.pop(context, false),
                  ),
                ],
              ),
            ),
          );
        },
      );
      return result ?? false;
    } finally {
      _promptVisible = false;
    }
  }

  void _pushDailyNotification() {
    try {
      PushNotificationService.instance.showLocalNotification(
        title: 'Pre-shift scan reminder',
        body: 'Complete your pre-shift scan before departure.',
        payload: {'type': 'daily_scan'},
      );
    } catch (_) {}
  }
}

class _LifecycleObserver extends WidgetsBindingObserver {
  final VoidCallback onResume;

  _LifecycleObserver({required this.onResume});

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      onResume();
    }
  }
}

/* ============================================================
   LATEST SCAN CARD
============================================================ */

class _LatestScanCard extends StatelessWidget {
  final ScanResult result;
  final VoidCallback onTap;

  const _LatestScanCard({required this.result, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final state = _displayState(result.overallState);
    final color = _stateColor(state);

    return AppCard(
      padding: const EdgeInsets.all(18),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Row(
          children: [
            Container(
              width: 12,
              height: 12,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    state,
                    style: TextStyle(
                      color: color,
                      fontWeight: FontWeight.w700,
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    _formatDate(result.dateCreated),
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
      ),
    );
  }

  String _formatDate(DateTime? date) {
    if (date == null) return '-';
    final d = date.toLocal();
    return '${d.day}/${d.month}/${d.year} â€¢ ${d.hour}:${d.minute.toString().padLeft(2, '0')}';
  }

  String _displayState(String state) {
    final v = state.toLowerCase();
    if (v.contains('stable')) return 'Stable';
    if (v.contains('low')) return 'Low focus';
    if (v.contains('elevated')) return 'Elevated fatigue';
    if (v.contains('high')) return 'High risk';
    return state;
  }

  Color _stateColor(String state) {
    switch (state) {
      case 'Stable':
        return AppColors.stable;
      case 'Low focus':
        return AppColors.lowFocus;
      case 'Elevated fatigue':
        return AppColors.elevated;
      case 'High risk':
        return AppColors.highRisk;
      default:
        return AppColors.primarySoft;
    }
  }
}

/* ============================================================
   SUPPORT WIDGETS
============================================================ */

class _BottomNavBar extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onTap;

  const _BottomNavBar({required this.currentIndex, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final items = const [
      _NavItem(Icons.home_rounded, 'Home'),
      _NavItem(Icons.assignment_outlined, 'Requests'),
      _NavItem(Icons.history_rounded, 'History'),
      _NavItem(Icons.notifications_none, 'Alerts'),
      _NavItem(Icons.person_outline, 'Profile'),
    ];

    return AppCard(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
      child: Row(
        children: List.generate(items.length, (i) {
          final selected = i == currentIndex;
          return Expanded(
            child: InkWell(
              onTap: () => onTap(i),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    items[i].icon,
                    color: selected ? AppColors.accentGold : Colors.white70,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    items[i].label,
                    style: TextStyle(
                      color: selected
                          ? AppColors.accentGold
                          : AppColors.textSecondary,
                      fontSize: 10,
                    ),
                  ),
                ],
              ),
            ),
          );
        }),
      ),
    );
  }
}

class _NavItem {
  final IconData icon;
  final String label;
  const _NavItem(this.icon, this.label);
}

class _NotificationBell extends StatelessWidget {
  final int count;
  final VoidCallback onTap;

  const _NotificationBell({required this.count, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Stack(
        children: [
          const Icon(Icons.notifications_none, color: Colors.white70),
          if (count > 0)
            Positioned(
              right: -2,
              top: -2,
              child: CircleAvatar(
                radius: 8,
                backgroundColor: AppColors.highRisk,
                child: Text(
                  count.toString(),
                  style: const TextStyle(fontSize: 10, color: Colors.white),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _ProfileBadge extends StatelessWidget {
  final VoidCallback onTap;

  const _ProfileBadge({required this.onTap});

  @override
  Widget build(BuildContext context) {
    final rawName = Session.instance.userName?.trim() ?? '';
    final initial = rawName.isNotEmpty ? rawName[0].toUpperCase() : '?';
    return InkWell(
      onTap: onTap,
      child: CircleAvatar(
        backgroundColor: AppColors.card,
        child: Text(initial),
      ),
    );
  }
}



import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/business_profile.dart';
import '../models/business_profile_member.dart';
import '../models/request_item.dart';
import '../models/scan_result.dart';
import '../state/app_providers.dart';
import '../state/session.dart';
import '../services/organization_service.dart';
import '../utils/app_colors.dart';
import '../utils/page_transition.dart';
import '../widgets/animated_space_background.dart';
import '../widgets/app_buttons.dart';
import '../widgets/app_cards.dart';
import '../widgets/lux_header.dart';
import '../widgets/responsive_card_grid.dart';
import '../widgets/state_views.dart';
import 'analytics_screen.dart';
import 'business_members_manage_screen.dart';
import 'business_profile_summary_screen.dart';
import 'export_screen.dart';
import 'requests_screen.dart';
import 'pricing_screen.dart';
import 'subscription_paywall_screen.dart';

enum _TimeRange { week, month, quarter, all }

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

class CompanyDashboardScreen extends ConsumerStatefulWidget {
  const CompanyDashboardScreen({super.key});

  @override
  ConsumerState<CompanyDashboardScreen> createState() =>
      _CompanyDashboardScreenState();
}

class _CompanyDashboardScreenState extends ConsumerState<CompanyDashboardScreen>
    with TickerProviderStateMixin {
  late final AnimationController _revealController;
  late final Animation<double> _fadeIn;
  late final Animation<Offset> _slideUp;
  _TimeRange _timeRange = _TimeRange.month;
  bool _resolvingBusinessAccess = true;
  bool _hasBusinessAccess = false;
  bool _subscriptionExpired = false;
  bool _canManageTeam = false;

  @override
  void initState() {
    super.initState();
    _resolveBusinessAccess();
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
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _revealController.forward();
    });
  }

  @override
  void dispose() {
    _revealController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_resolvingBusinessAccess) {
      return const Scaffold(
        backgroundColor: AppColors.background,
        body: Center(
          child: CircularProgressIndicator(color: AppColors.primarySoft),
        ),
      );
    }

    if (!_hasBusinessAccess) {
      if (_subscriptionExpired) {
        return const SubscriptionPaywallScreen(
          title: 'Company dashboard locked',
        );
      }
      return Scaffold(
        backgroundColor: AppColors.background,
        body: Stack(
          children: [
            const AnimatedSpaceBackground(),
            SafeArea(
              child: Center(
                child: _UpgradeGate(
                  title: 'Company dashboard locked',
                  message:
                      'Business access required. Activate a valid Business subscription to continue.',
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

    final hasError =
        historyAsync.hasError ||
        sentAsync.hasError ||
        incomingAsync.hasError ||
        exportsAsync.hasError;

    final isLoading =
        historyAsync.isLoading &&
        sentAsync.isLoading &&
        incomingAsync.isLoading &&
        exportsAsync.isLoading &&
        !historyAsync.hasValue &&
        !sentAsync.hasValue &&
        !incomingAsync.hasValue &&
        !exportsAsync.hasValue;

    final warningMessage = hasError
        ? _firstDataError(historyAsync, sentAsync, incomingAsync, exportsAsync)
        : null;
    final history = historyAsync.valueOrNull ?? const <ScanResult>[];
    final sent = sentAsync.valueOrNull ?? const <RequestItem>[];
    final incoming = incomingAsync.valueOrNull ?? const <RequestItem>[];
    final exportsCount = exportsAsync.valueOrNull?.length ?? 0;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: Stack(
        children: [
          const AnimatedSpaceBackground(),
          SafeArea(
            child: isLoading
                ? const SkeletonList()
                : FadeTransition(
                    opacity: _fadeIn,
                    child: SlideTransition(
                      position: _slideUp,
                      child: SingleChildScrollView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
                        child: _CompanyDashboardContent(
                          history: history,
                          sent: sent,
                          incoming: incoming,
                          timeRange: _timeRange,
                          exportsCount: exportsCount,
                          warningMessage: warningMessage,
                          canManageTeam: _canManageTeam,
                          onTimeRangeChanged: (range) {
                            setState(() => _timeRange = range);
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

  Future<void> _resolveBusinessAccess() async {
    final subscription = await ref
        .read(subscriptionServiceProvider)
        .fetchActiveSubscription();
    final access = ref
        .read(subscriptionServiceProvider)
        .accessForSubscription(subscription);
    var hasAccess = access.canUseBusiness;
    var canManage = false;
    final expired = access.isExpired;

    final userId = Session.instance.userId?.trim();
    if (userId == null || userId.isEmpty) {
      if (mounted) {
        setState(() {
          _hasBusinessAccess = hasAccess;
          _subscriptionExpired = expired;
          _canManageTeam = canManage;
          _resolvingBusinessAccess = false;
        });
      }
      return;
    }

    BusinessProfile? profile;
    try {
      profile = await OrganizationService.instance.fetchPrimaryBusinessProfile(
        forceRefresh: true,
      );
    } catch (_) {
      profile = null;
    }

    final ownerUserId = profile?.ownerUserId?.trim();
    if (ownerUserId != null &&
        ownerUserId.isNotEmpty &&
        ownerUserId == userId &&
        hasAccess) {
      canManage = true;
    }
    if (hasAccess && profile != null && profile.id.trim().isNotEmpty) {
      try {
        final members = await OrganizationService.instance.fetchBusinessMembers(
          businessProfileId: profile.id,
          limit: 200,
        );
        for (final member in members) {
          if (member.userId.trim() != userId) continue;
          if (_isMemberActive(member.status)) {
            hasAccess = true;
          }
          if (_isMemberOwnerAndActive(member.memberRole, member.status)) {
            canManage = true;
            break;
          }
        }
      } catch (_) {
        // Keep going: fallback to my memberships.
      }
    }

    if (hasAccess && !canManage) {
      try {
        final myMemberships = await OrganizationService.instance
            .fetchMyBusinessMemberships(limit: 200);
        for (final membership in myMemberships) {
          final membershipUserId = membership.userId.trim();
          if (membershipUserId.isNotEmpty && membershipUserId != userId) {
            continue;
          }
          if (_isMemberActive(membership.status)) {
            hasAccess = true;
          }
          if (_isMemberOwnerAndActive(
            membership.memberRole,
            membership.status,
          )) {
            canManage = true;
            break;
          }
        }
      } catch (_) {
        // Best effort only.
      }
    }

    if (mounted) {
      setState(() {
        _hasBusinessAccess = hasAccess;
        _subscriptionExpired = expired;
        _canManageTeam = canManage;
        _resolvingBusinessAccess = false;
      });
    }
  }

  bool _isMemberOwnerAndActive(String role, String status) {
    return _isOwnerRole(role) && _isMemberActive(status);
  }

  bool _isOwnerRole(String role) {
    final normalized = _normalizeToken(role);
    return normalized == 'owner' ||
        normalized == 'business_owner' ||
        normalized == 'team_owner' ||
        normalized.endsWith('_owner') ||
        normalized.contains('owner');
  }

  bool _isMemberActive(String status) {
    final normalizedStatus = _normalizeToken(status);
    return normalizedStatus == 'active';
  }

  String _normalizeToken(String value) {
    return value.trim().toLowerCase().replaceAll('-', '_').replaceAll(' ', '_');
  }

  String? _firstDataError(
    AsyncValue history,
    AsyncValue sent,
    AsyncValue incoming,
    AsyncValue exports,
  ) {
    final err = history.error ?? sent.error ?? incoming.error ?? exports.error;
    if (err == null) return null;
    return err.toString();
  }
}

class _CompanyDashboardContent extends StatelessWidget {
  final List<ScanResult> history;
  final List<RequestItem> sent;
  final List<RequestItem> incoming;
  final _TimeRange timeRange;
  final int exportsCount;
  final String? warningMessage;
  final bool canManageTeam;
  final ValueChanged<_TimeRange> onTimeRangeChanged;

  const _CompanyDashboardContent({
    required this.history,
    required this.sent,
    required this.incoming,
    required this.timeRange,
    required this.exportsCount,
    required this.warningMessage,
    required this.canManageTeam,
    required this.onTimeRangeChanged,
  });

  @override
  Widget build(BuildContext context) {
    final filteredHistory = _filterHistory(history, timeRange);
    final previousHistory = _previousHistory(history, timeRange);
    final filteredIncoming = _filterRequests(incoming, timeRange);
    final filteredSent = _filterRequests(sent, timeRange);
    final previousIncoming = _previousRequests(incoming, timeRange);
    final previousSent = _previousRequests(sent, timeRange);

    final vm = _CompanyViewModel(
      history: filteredHistory,
      sent: filteredSent,
      incoming: filteredIncoming,
      previousHistory: previousHistory,
      previousIncoming: previousIncoming,
      previousSent: previousSent,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (warningMessage != null && warningMessage!.trim().isNotEmpty) ...[
          AppCard(
            padding: const EdgeInsets.all(14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(
                  Icons.warning_amber_rounded,
                  color: AppColors.highRisk,
                  size: 18,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    warningMessage!,
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 12,
                    ),
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
        ],
        _CompanyHeader(),
        const SizedBox(height: 12),
        _CompanyHero(vm: vm, exportsCount: exportsCount),
        const SizedBox(height: 16),
        _BusinessWorkspaceSnapshot(canManageTeam: canManageTeam),
        const SizedBox(height: 16),
        _FilterBar(
          timeRange: timeRange,
          onTimeRangeChanged: onTimeRangeChanged,
        ),
        const SizedBox(height: 18),
        _CompanyStats(vm: vm),
        const SizedBox(height: 18),
        _ComparePanel(vm: vm, timeRange: timeRange),
        const SizedBox(height: 18),
        _TeamPulse(vm: vm),
        const SizedBox(height: 18),
        _RiskQueue(vm: vm),
        const SizedBox(height: 18),
        _ActionCenter(canManageTeam: canManageTeam),
      ],
    );
  }

  List<ScanResult> _filterHistory(List<ScanResult> items, _TimeRange range) {
    final days = range.days;
    if (days == null) return items;
    final cutoff = DateTime.now().subtract(Duration(days: days));
    return items
        .where((r) => r.dateCreated != null && r.dateCreated!.isAfter(cutoff))
        .toList();
  }

  List<ScanResult> _previousHistory(List<ScanResult> items, _TimeRange range) {
    final days = range.days;
    if (days == null) return const [];
    final now = DateTime.now();
    final end = now.subtract(Duration(days: days));
    final start = end.subtract(Duration(days: days));
    return items
        .where(
          (r) =>
              r.dateCreated != null &&
              r.dateCreated!.isAfter(start) &&
              r.dateCreated!.isBefore(end),
        )
        .toList();
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

class _CompanyHeader extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return FutureBuilder(
      future: OrganizationService.instance.fetchPrimaryOrganization(),
      builder: (context, snapshot) {
        final org = snapshot.data;
        final name = org?.name.trim();
        return LuxHeader(
          title: name != null && name.isNotEmpty ? name : 'Company Dashboard',
          subtitle: 'Depot-level readiness and compliance controls',
          icon: Icons.apartment_rounded,
        );
      },
    );
  }
}

class _CompanyViewModel {
  final List<ScanResult> history;
  final List<RequestItem> sent;
  final List<RequestItem> incoming;
  final List<ScanResult> previousHistory;
  final List<RequestItem> previousSent;
  final List<RequestItem> previousIncoming;

  _CompanyViewModel({
    required this.history,
    required this.sent,
    required this.incoming,
    required this.previousHistory,
    required this.previousSent,
    required this.previousIncoming,
  });

  int get totalScans => history.length;
  int get pendingRequests =>
      incoming.where((e) => e.displayStatus.toLowerCase() == 'pending').length;

  double get complianceRate {
    if (history.isEmpty) return 0;
    final stable = history
        .where((e) => _normalizeState(e.overallState) == 'Stable')
        .length;
    return stable / history.length;
  }

  double get riskRate {
    if (history.isEmpty) return 0;
    final high = history
        .where((e) => _normalizeState(e.overallState) == 'Action Required')
        .length;
    return high / history.length;
  }

  double get avgConfidence {
    final values = history
        .map((e) => e.confidence)
        .whereType<double>()
        .toList();
    if (values.isEmpty) return 0;
    final avg = values.reduce((a, b) => a + b) / values.length;
    return (avg <= 1 ? avg : avg / 100).clamp(0, 1);
  }

  double get approvalRate {
    final all = [...sent, ...incoming];
    if (all.isEmpty) return 0;
    final approved = all
        .where((e) => e.displayStatus.toLowerCase() == 'approved')
        .length;
    return approved / all.length;
  }

  double get previousComplianceRate {
    if (previousHistory.isEmpty) return 0;
    final stable = previousHistory
        .where((e) => _normalizeState(e.overallState) == 'Stable')
        .length;
    return stable / previousHistory.length;
  }

  double get previousRiskRate {
    if (previousHistory.isEmpty) return 0;
    final high = previousHistory
        .where((e) => _normalizeState(e.overallState) == 'Action Required')
        .length;
    return high / previousHistory.length;
  }

  double get previousApprovalRate {
    final all = [...previousSent, ...previousIncoming];
    if (all.isEmpty) return 0;
    final approved = all
        .where((e) => e.displayStatus.toLowerCase() == 'approved')
        .length;
    return approved / all.length;
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

  List<_TeamMetric> get topRequesters {
    final Map<String, int> counts = {};
    for (final item in sent) {
      final key = (item.target ?? 'Admin').trim();
      counts[key] = (counts[key] ?? 0) + 1;
    }
    final entries = counts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return entries.take(5).map((e) {
      return _TeamMetric(name: e.key, count: e.value);
    }).toList();
  }

  List<ScanResult> get highRiskScans {
    final results = history.where((r) {
      final state = r.overallState.toLowerCase();
      return state.contains('high') || state.contains('elevated');
    }).toList();
    results.sort((a, b) {
      final aDate = a.dateCreated ?? DateTime.fromMillisecondsSinceEpoch(0);
      final bDate = b.dateCreated ?? DateTime.fromMillisecondsSinceEpoch(0);
      return bDate.compareTo(aDate);
    });
    return results.take(6).toList();
  }

  double? deltaPercent(double current, double previous) {
    if (previous == 0) return null;
    return (current - previous) / previous;
  }

  String _normalizeState(String value) {
    final v = value.toLowerCase();
    if (v.contains('stable')) return 'Stable';
    if (v.contains('low')) return 'Attention Needed';
    if (v.contains('elevated')) return 'Readiness Concern';
    if (v.contains('high')) return 'Action Required';
    return 'Stable';
  }
}

class _CompanyHero extends StatelessWidget {
  final _CompanyViewModel vm;
  final int exportsCount;

  const _CompanyHero({required this.vm, required this.exportsCount});

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Fleet Operations Control Room',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Depot Compliance ${_toPercent(vm.complianceRate)} • Assignment Risk ${_toPercent(vm.riskRate)}',
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              _GaugeRing(value: vm.avgConfidence),
            ],
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _HeroChip(
                label: 'Pending Requests',
                value: vm.pendingRequests.toString(),
                color: AppColors.lowFocus,
              ),
              _HeroChip(
                label: 'Shift Checks',
                value: vm.totalScans.toString(),
                color: AppColors.primarySoft,
              ),
              _HeroChip(
                label: 'Exports',
                value: exportsCount.toString(),
                color: AppColors.accentGold,
              ),
            ],
          ),
        ],
      ),
    );
  }

  static String _toPercent(double value) {
    return '${(value * 100).round()}%';
  }
}

class _HeroChip extends StatelessWidget {
  final String label;
  final String value;
  final Color color;

  const _HeroChip({
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color.withOpacity(0.18),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withOpacity(0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w700,
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: const TextStyle(color: Colors.white70, fontSize: 10),
          ),
        ],
      ),
    );
  }
}

class _GaugeRing extends StatelessWidget {
  final double value;

  const _GaugeRing({required this.value});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 64,
      height: 64,
      child: Stack(
        alignment: Alignment.center,
        children: [
          CircularProgressIndicator(
            value: value.clamp(0, 1),
            strokeWidth: 6,
            backgroundColor: Colors.white12,
            valueColor: const AlwaysStoppedAnimation(AppColors.primarySoft),
          ),
          Text(
            '${(value * 100).round()}%',
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w700,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}

class _BusinessWorkspaceSnapshot extends StatefulWidget {
  final bool canManageTeam;

  const _BusinessWorkspaceSnapshot({required this.canManageTeam});

  @override
  State<_BusinessWorkspaceSnapshot> createState() =>
      _BusinessWorkspaceSnapshotState();
}

class _BusinessWorkspaceSnapshotState
    extends State<_BusinessWorkspaceSnapshot> {
  late Future<_BusinessSnapshotData> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_BusinessSnapshotData>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const InlineLoadingCard(
            message: 'Loading business workspace...',
          );
        }
        if (snapshot.hasError) {
          return AppCard(
            padding: const EdgeInsets.all(14),
            child: Text(
              snapshot.error.toString(),
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 12,
              ),
            ),
          );
        }
        final data = snapshot.data;
        if (data == null || data.profile == null) {
          return const EmptyStateCard(
            title: 'Business profile missing',
            message:
                'Complete onboarding to unlock business workspace details.',
          );
        }

        final profile = data.profile!;
        final members = data.members;
        final canManageTeam = widget.canManageTeam;
        return Column(
          children: [
            AppCard(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Expanded(
                        child: Text(
                          'Business Profile Snapshot',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      _softTag(
                        profile.billingStatus?.trim().isEmpty == false
                            ? profile.billingStatus!.trim()
                            : (profile.isActive ? 'active' : 'inactive'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  _kv('Business Name', profile.displayName),
                  _kv('Plan Code', profile.planCode ?? '-'),
                  _kv('Owner User', profile.ownerUserId ?? '-'),
                  _kv('Work Email', profile.workEmail ?? '-'),
                  _kv('Industry', profile.industry ?? '-'),
                  _kv('Location', _location(profile.country, profile.city)),
                  const SizedBox(height: 10),
                  SolidButton(
                    text: 'Open Full Profile Summary',
                    color: AppColors.primarySoft,
                    onPressed: () {
                      Navigator.push(
                        context,
                        fadeSlideRoute(const BusinessProfileSummaryScreen()),
                      );
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            AppCard(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Expanded(
                        child: Text(
                          'Team Members',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      _softTag('${members.length} members'),
                    ],
                  ),
                  const SizedBox(height: 10),
                  if (members.isEmpty)
                    const Text(
                      'No team members linked yet.',
                      style: TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 12,
                      ),
                    )
                  else
                    ...members
                        .take(4)
                        .map(
                          (member) => Padding(
                            padding: const EdgeInsets.only(bottom: 7),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    member.userEmail?.trim().isEmpty == false
                                        ? member.userEmail!
                                        : member.displayName,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  member.memberRole,
                                  style: const TextStyle(
                                    color: AppColors.textSecondary,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                  const SizedBox(height: 10),
                  SolidButton(
                    text: canManageTeam
                        ? 'Open Members Manager'
                        : 'Open Members (View Only)',
                    color: canManageTeam
                        ? AppColors.stable
                        : AppColors.lowFocus,
                    onPressed: () {
                      Navigator.push(
                        context,
                        fadeSlideRoute(const BusinessMembersManageScreen()),
                      );
                    },
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  Future<_BusinessSnapshotData> _load() async {
    final profile = await OrganizationService.instance
        .fetchPrimaryBusinessProfile(forceRefresh: true);
    if (profile == null || profile.id.trim().isEmpty) {
      return const _BusinessSnapshotData(
        profile: null,
        members: <BusinessProfileMember>[],
      );
    }
    try {
      final members = await OrganizationService.instance.fetchBusinessMembers(
        businessProfileId: profile.id,
        limit: 100,
      );
      return _BusinessSnapshotData(profile: profile, members: members);
    } catch (_) {
      return _BusinessSnapshotData(
        profile: profile,
        members: const <BusinessProfileMember>[],
      );
    }
  }

  Widget _softTag(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.primarySoft.withOpacity(0.18),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.primarySoft.withOpacity(0.45)),
      ),
      child: Text(
        text,
        style: const TextStyle(
          color: AppColors.primarySoft,
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  Widget _kv(String key, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          SizedBox(
            width: 108,
            child: Text(
              key,
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value.trim().isEmpty ? '-' : value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _location(String? country, String? city) {
    final c1 = country?.trim() ?? '';
    final c2 = city?.trim() ?? '';
    if (c1.isEmpty && c2.isEmpty) return '-';
    if (c1.isEmpty) return c2;
    if (c2.isEmpty) return c1;
    return '$c1, $c2';
  }
}

class _BusinessSnapshotData {
  final BusinessProfile? profile;
  final List<BusinessProfileMember> members;

  const _BusinessSnapshotData({required this.profile, required this.members});
}

class _FilterBar extends StatelessWidget {
  final _TimeRange timeRange;
  final ValueChanged<_TimeRange> onTimeRangeChanged;

  const _FilterBar({required this.timeRange, required this.onTimeRangeChanged});

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Time range',
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
              ? AppColors.primarySoft.withOpacity(0.22)
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

class _CompanyStats extends StatelessWidget {
  final _CompanyViewModel vm;

  const _CompanyStats({required this.vm});

  @override
  Widget build(BuildContext context) {
    return ResponsiveCardGrid(
      spacing: 12,
      runSpacing: 12,
      children: [
        ResponsiveCardGridItem(
          child: _StatTile(
            label: 'Compliance',
            value: '${(vm.complianceRate * 100).round()}%',
            color: AppColors.stable,
          ),
        ),
        ResponsiveCardGridItem(
          child: _StatTile(
            label: 'Risk Index',
            value: '${(vm.riskRate * 100).round()}%',
            color: AppColors.highRisk,
          ),
        ),
        ResponsiveCardGridItem(
          child: _StatTile(
            label: 'Avg Confidence',
            value: '${(vm.avgConfidence * 100).round()}%',
            color: AppColors.primarySoft,
          ),
        ),
        ResponsiveCardGridItem.fullWidth(
          child: _StatTile(
            label: 'Approval Rate',
            value: '${(vm.approvalRate * 100).round()}%',
            color: AppColors.elevated,
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
              color: color.withOpacity(0.2),
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

class _ComparePanel extends StatelessWidget {
  final _CompanyViewModel vm;
  final _TimeRange timeRange;

  const _ComparePanel({required this.vm, required this.timeRange});

  @override
  Widget build(BuildContext context) {
    final label = timeRange.days == null
        ? 'Compare to previous period'
        : 'Compare to previous ${timeRange.label}';
    return AppCard(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 12),
          _CompareRow(
            label: 'Compliance',
            current: '${(vm.complianceRate * 100).round()}%',
            delta: _delta(
              vm.deltaPercent(vm.complianceRate, vm.previousComplianceRate),
            ),
          ),
          const SizedBox(height: 10),
          _CompareRow(
            label: 'Risk Index',
            current: '${(vm.riskRate * 100).round()}%',
            delta: _delta(vm.deltaPercent(vm.riskRate, vm.previousRiskRate)),
          ),
          const SizedBox(height: 10),
          _CompareRow(
            label: 'Approval Rate',
            current: '${(vm.approvalRate * 100).round()}%',
            delta: _delta(
              vm.deltaPercent(vm.approvalRate, vm.previousApprovalRate),
            ),
          ),
        ],
      ),
    );
  }

  _DeltaValue _delta(double? delta) {
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

class _TeamPulse extends StatelessWidget {
  final _CompanyViewModel vm;

  const _TeamPulse({required this.vm});

  @override
  Widget build(BuildContext context) {
    final top = vm.topRequesters;
    return AppCard(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Team Pulse',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 10),
          if (top.isEmpty)
            const Text(
              'No activity captured yet.',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
            )
          else
            Column(
              children: top
                  .map(
                    (item) => Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              item.name,
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          Text(
                            '${item.count} requests',
                            style: const TextStyle(
                              color: AppColors.textSecondary,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                  .toList(),
            ),
        ],
      ),
    );
  }
}

class _TeamMetric {
  final String name;
  final int count;

  const _TeamMetric({required this.name, required this.count});
}

class _RiskQueue extends StatelessWidget {
  final _CompanyViewModel vm;

  const _RiskQueue({required this.vm});

  @override
  Widget build(BuildContext context) {
    final risks = vm.highRiskScans;
    return AppCard(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Supervisor Alert Queue',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 10),
          if (risks.isEmpty)
            const Text(
              'No readiness or assignment-hold alerts found.',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
            )
          else
            Column(
              children: risks.map((scan) {
                final state = scan.overallState;
                final color = _stateColor(state);
                return Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.backgroundAlt,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: Colors.white12),
                  ),
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
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          state,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      Text(
                        _formatDate(scan.dateCreated),
                        style: const TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
        ],
      ),
    );
  }

  String _formatDate(DateTime? date) {
    if (date == null) return '-';
    final d = date.toLocal();
    return '${d.day}/${d.month}/${d.year}';
  }

  Color _stateColor(String state) {
    final v = state.toLowerCase();
    if (v.contains('high')) return AppColors.highRisk;
    if (v.contains('elevated')) return AppColors.elevated;
    if (v.contains('low')) return AppColors.lowFocus;
    return AppColors.stable;
  }
}

class _ActionCenter extends StatelessWidget {
  final bool canManageTeam;

  const _ActionCenter({required this.canManageTeam});

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Operations Workspace',
            style: TextStyle(
              color: Colors.white,
              fontSize: 15,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            canManageTeam
                ? 'Owner tools enabled. You can manage members and open full business profile.'
                : 'View tools enabled. Team management requires Owner member role.',
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 12),
          _ActionTile(
            title: 'Business Profile Summary',
            subtitle: 'Open complete company profile details.',
            icon: Icons.badge_outlined,
            color: AppColors.primarySoft,
            onTap: () {
              Navigator.push(
                context,
                fadeSlideRoute(const BusinessProfileSummaryScreen()),
              );
            },
          ),
          const SizedBox(height: 10),
          _ActionTile(
            title: 'Team Members',
            subtitle: canManageTeam
                ? 'Add/update members and choose member_role.'
                : 'Open members list (edit disabled for non-owner).',
            icon: Icons.groups_2_outlined,
            color: canManageTeam ? AppColors.stable : AppColors.lowFocus,
            onTap: () {
              Navigator.push(
                context,
                fadeSlideRoute(const BusinessMembersManageScreen()),
              );
            },
          ),
          const SizedBox(height: 14),
          SolidButton(
            text: 'Open Fleet Analytics',
            color: AppColors.primarySoft,
            onPressed: () {
              Navigator.push(context, fadeSlideRoute(const AnalyticsScreen()));
            },
          ),
          const SizedBox(height: 10),
          SolidButton(
            text: 'Open Export Center',
            color: AppColors.accentGold,
            onPressed: () {
              Navigator.push(context, fadeSlideRoute(const ExportScreen()));
            },
          ),
          const SizedBox(height: 10),
          SolidButton(
            text: 'Review Requests',
            color: AppColors.lowFocus,
            onPressed: () {
              Navigator.push(context, fadeSlideRoute(const RequestsScreen()));
            },
          ),
        ],
      ),
    );
  }
}

class _ActionTile extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  const _ActionTile({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        decoration: BoxDecoration(
          color: AppColors.backgroundAlt.withOpacity(0.75),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.white12),
        ),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: color.withOpacity(0.2),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: color.withOpacity(0.5)),
              ),
              child: Icon(icon, color: color, size: 19),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(
              Icons.arrow_forward_ios_rounded,
              size: 14,
              color: AppColors.textSecondary,
            ),
          ],
        ),
      ),
    );
  }
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

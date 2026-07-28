import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/activity_event.dart';
import '../state/app_providers.dart';
import '../utils/app_colors.dart';
import '../utils/page_transition.dart';
import '../widgets/animated_space_background.dart';
import '../widgets/app_buttons.dart';
import '../widgets/app_cards.dart';
import '../widgets/lux_header.dart';
import '../widgets/state_views.dart';
import 'pricing_screen.dart';
import 'subscription_paywall_screen.dart';

class ActivityScreen extends ConsumerStatefulWidget {
  const ActivityScreen({super.key});

  @override
  ConsumerState<ActivityScreen> createState() => _ActivityScreenState();
}

class _ActivityScreenState extends ConsumerState<ActivityScreen> {
  _ActivityFilter _filter = _ActivityFilter.all;

  @override
  Widget build(BuildContext context) {
    final subscriptionAsync = ref.watch(activeSubscriptionProvider);
    final access = subscriptionAsync.maybeWhen(
      data: (sub) =>
          ref.read(subscriptionServiceProvider).accessForSubscription(sub),
      orElse: () =>
          ref.read(subscriptionServiceProvider).accessForSubscription(null),
    );

    if (subscriptionAsync.isLoading) {
      return const Scaffold(
        backgroundColor: AppColors.background,
        body: Center(
          child: CircularProgressIndicator(color: AppColors.primarySoft),
        ),
      );
    }

    if (access.isExpired) {
      return const SubscriptionPaywallScreen(title: 'Activity locked');
    }

    if (!access.canViewActivity) {
      return Scaffold(
        backgroundColor: AppColors.background,
        body: Stack(
          children: [
            const AnimatedSpaceBackground(),
            SafeArea(
              child: Center(
                child: _UpgradeGate(
                  title: 'Activity locked',
                  message: 'Upgrade to Business to access activity logs.',
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

    final eventsAsync = ref.watch(activityEventsProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      body: Stack(
        children: [
          const AnimatedSpaceBackground(),
          SafeArea(
            child: eventsAsync.when(
              loading: () => const SkeletonList(),
              error: (error, _) => ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
                children: [
                  const SizedBox(height: 80),
                  StatusCard(
                    title: 'Failed to load activity',
                    message: error.toString(),
                    icon: Icons.warning_amber_rounded,
                    iconColor: AppColors.highRisk,
                    actionText: 'Retry',
                    onAction: () {},
                  ),
                ],
              ),
              data: (events) => RefreshIndicator(
                color: AppColors.primarySoft,
                onRefresh: () async {},
                child: SingleChildScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
                  child: FadeSlideIn(child: _buildContent(context, events)),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContent(BuildContext context, List<ActivityEvent> events) {
    final items = events.map(_ActivityItem.fromEvent).toList();
    final filtered = _applyFilter(items);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildHeader(context, filtered.length),
        const SizedBox(height: 12),
        _buildFilters(),
        const SizedBox(height: 16),
        if (filtered.isEmpty)
          const EmptyStateCard(
            title: 'No activity yet',
            message: 'System events will show here.',
          )
        else
          ...List.generate(
            filtered.length,
            (index) => _ActivityCard(
              item: filtered[index],
              isLast: index == filtered.length - 1,
            ),
          ),
      ],
    );
  }

  Widget _buildHeader(BuildContext context, int count) {
    return LuxHeader(
      title: 'Activity',
      subtitle: '$count events logged',
      icon: Icons.bolt,
      onBack: () => Navigator.pop(context),
    );
  }

  Widget _buildFilters() {
    return AppCard(
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          _FilterChip(
            label: 'All',
            selected: _filter == _ActivityFilter.all,
            onTap: () => setState(() => _filter = _ActivityFilter.all),
          ),
          const SizedBox(width: 8),
          _FilterChip(
            label: 'Scans',
            selected: _filter == _ActivityFilter.scans,
            onTap: () => setState(() => _filter = _ActivityFilter.scans),
          ),
          const SizedBox(width: 8),
          _FilterChip(
            label: 'Requests',
            selected: _filter == _ActivityFilter.requests,
            onTap: () => setState(() => _filter = _ActivityFilter.requests),
          ),
        ],
      ),
    );
  }

  List<_ActivityItem> _applyFilter(List<_ActivityItem> items) {
    switch (_filter) {
      case _ActivityFilter.scans:
        return items.where((item) => item.type == _ActivityType.scan).toList();
      case _ActivityFilter.requests:
        return items
            .where((item) => item.type == _ActivityType.request)
            .toList();
      case _ActivityFilter.all:
        return items;
    }
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

enum _ActivityType { scan, request, system }

enum _ActivityFilter { all, scans, requests }

class _ActivityItem {
  final DateTime? time;
  final String title;
  final List<String> details;
  final IconData icon;
  final Color color;
  final _ActivityType type;

  const _ActivityItem({
    required this.time,
    required this.title,
    required this.details,
    required this.icon,
    required this.color,
    required this.type,
  });

  factory _ActivityItem.fromEvent(ActivityEvent event) {
    final action = event.action.toLowerCase();
    final actor = _actorLabel(event);
    final target = _targetLabel(event);
    final entity = event.entityType.isNotEmpty
        ? 'Entity: ${event.entityType}'
        : null;
    final entityId = event.entityId != null && event.entityId!.isNotEmpty
        ? 'ID: ${event.entityId}'
        : null;
    final metaLines = <String>[];
    if (actor != null) metaLines.add('Actor: $actor');
    if (target != null) metaLines.add('Target: $target');
    if (entity != null) metaLines.add(entity);
    if (entityId != null) metaLines.add(entityId);

    if (action.contains('request')) {
      final status = event.payload['status']?.toString();
      final details = <String>[];
      details.add(
        status != null && status.isNotEmpty
            ? 'Status: $status'
            : 'Request activity recorded',
      );
      details.addAll(metaLines);
      return _ActivityItem(
        time: event.createdAt,
        title: action.contains('updated') ? 'Request updated' : 'Request sent',
        details: details,
        icon: Icons.mark_email_unread_outlined,
        color: AppColors.primarySoft,
        type: _ActivityType.request,
      );
    }
    if (action.contains('scan')) {
      final details = <String>[];
      details.add(
        action.contains('completed') ? 'Scan completed' : 'Wellness scan event',
      );
      details.addAll(metaLines);
      return _ActivityItem(
        time: event.createdAt,
        title: action.contains('completed') ? 'Scan completed' : 'Scan started',
        details: details,
        icon: Icons.auto_awesome,
        color: AppColors.stable,
        type: _ActivityType.scan,
      );
    }
    final details = <String>['Activity recorded', ...metaLines];
    return _ActivityItem(
      time: event.createdAt,
      title: 'System update',
      details: details,
      icon: Icons.bolt,
      color: AppColors.elevated,
      type: _ActivityType.system,
    );
  }

  static String? _actorLabel(ActivityEvent event) {
    final name = event.actorName?.trim();
    if (name != null && name.isNotEmpty) return name;
    final email = event.actorEmail?.trim();
    if (email != null && email.isNotEmpty) return email;
    final action = event.action.toLowerCase();
    if (action.contains('request')) return 'Administration';
    return 'System';
  }

  static String? _targetLabel(ActivityEvent event) {
    final name = event.targetUserName?.trim();
    if (name != null && name.isNotEmpty) return name;
    final email = event.targetUserEmail?.trim();
    if (email != null && email.isNotEmpty) return email;
    final id = event.targetUserId?.trim();
    if (id != null && id.isNotEmpty) return id;
    return null;
  }
}

class _ActivityCard extends StatelessWidget {
  final _ActivityItem item;
  final bool isLast;

  const _ActivityCard({required this.item, required this.isLast});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Column(
            children: [
              Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  color: item.color,
                  shape: BoxShape.circle,
                ),
              ),
              if (!isLast)
                Container(width: 2, height: 72, color: Colors.white12),
            ],
          ),
          const SizedBox(width: 12),
          Expanded(
            child: AppCard(
              padding: const EdgeInsets.all(16),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: item.color.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: item.color.withOpacity(0.5)),
                    ),
                    child: Icon(item.icon, color: item.color, size: 18),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.title,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 4),
                        ...item.details.map(
                          (line) => Padding(
                            padding: const EdgeInsets.only(bottom: 4),
                            child: Text(
                              line,
                              style: const TextStyle(
                                color: AppColors.textSecondary,
                                fontSize: 12,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          _formatDate(item.time),
                          style: const TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _formatDate(DateTime? date) {
    if (date == null) return '-';
    final d = date.toLocal();
    final dd = d.day.toString().padLeft(2, '0');
    final mm = d.month.toString().padLeft(2, '0');
    final yyyy = d.year.toString();
    final hh = d.hour.toString().padLeft(2, '0');
    final min = d.minute.toString().padLeft(2, '0');
    return '$dd/$mm/$yyyy $hh:$min';
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
    final color = selected ? AppColors.primarySoft : Colors.white24;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? AppColors.primarySoft.withOpacity(0.2) : null,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? Colors.white : Colors.white70,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

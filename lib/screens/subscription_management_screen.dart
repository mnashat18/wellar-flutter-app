import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/plan.dart';
import '../models/user_subscription.dart';
import '../services/organization_service.dart';
import '../state/app_providers.dart';
import '../utils/app_colors.dart';
import '../utils/page_transition.dart';
import '../widgets/animated_space_background.dart';
import '../widgets/app_buttons.dart';
import '../widgets/app_cards.dart';
import '../widgets/state_views.dart';
import 'pricing_screen.dart';
import 'subscription_paywall_screen.dart';

class SubscriptionManagementScreen extends ConsumerStatefulWidget {
  const SubscriptionManagementScreen({super.key});

  @override
  ConsumerState<SubscriptionManagementScreen> createState() =>
      _SubscriptionManagementScreenState();
}

class _SubscriptionManagementScreenState
    extends ConsumerState<SubscriptionManagementScreen> {
  Timer? _refreshTicker;
  bool _actionLoading = false;

  @override
  void initState() {
    super.initState();
    _refreshTicker = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _refreshTicker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final subscriptionAsync = ref.watch(activeSubscriptionProvider);
    final accessAsync = ref.watch(subscriptionAccessProvider);
    final membersCountAsync = ref.watch(businessMembersCountProvider);
    final plansAsync = ref.watch(plansProvider);
    final service = ref.read(subscriptionServiceProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      body: Stack(
        children: [
          const AnimatedSpaceBackground(),
          SafeArea(
            child: subscriptionAsync.when(
              loading: () => const SkeletonList(),
              error: (error, _) => ListView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                children: [
                  _header(context),
                  const SizedBox(height: 12),
                  StatusCard(
                    title: 'Unable to load subscription',
                    message: error.toString(),
                    icon: Icons.warning_amber_rounded,
                    iconColor: AppColors.highRisk,
                    actionText: 'Retry',
                    onAction: () => ref.invalidate(activeSubscriptionProvider),
                  ),
                ],
              ),
              data: (subscription) {
                final access = accessAsync.maybeWhen(
                  data: (value) => value,
                  orElse: () => service.accessForSubscription(subscription),
                );

                if (access.isExpired) {
                  return const SubscriptionPaywallScreen(
                    title: 'Subscription expired',
                  );
                }

                if (subscription == null) {
                  return ListView(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                    children: [
                      _header(context),
                      const SizedBox(height: 12),
                      const EmptyStateCard(
                        title: 'No subscription yet',
                        message: 'Choose a Business plan to activate features.',
                        icon: Icons.subscriptions_outlined,
                      ),
                      const SizedBox(height: 12),
                      PrimaryButton(
                        text: 'View Plans',
                        icon: Icons.upgrade_rounded,
                        onPressed: () {
                          Navigator.push(
                            context,
                            fadeSlideRoute(const PricingScreen()),
                          );
                        },
                      ),
                    ],
                  );
                }

                final days = service.daysRemaining(subscription);
                final remaining = service.remainingDuration(subscription);
                final trialColor = (days != null && days <= 3)
                    ? AppColors.highRisk
                    : AppColors.lowFocus;
                final plans = plansAsync.maybeWhen(
                  data: (items) => items
                      .where(
                        (plan) =>
                            plan.isBusiness ||
                            plan.code.trim().toLowerCase() == 'business',
                      )
                      .toList(),
                  orElse: () => const <Plan>[],
                );
                final membersCount = membersCountAsync.maybeWhen(
                  data: (count) => count,
                  orElse: () => subscription.currentMembersCount ?? 0,
                );
                final maxMembers = subscription.plan?.maxMembers;

                return ListView(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                  children: [
                    _header(context),
                    const SizedBox(height: 12),
                    if (access.showExpiredBanner) _expiredBanner(),
                    if (access.showExpiredBanner) const SizedBox(height: 12),
                    AppCard(
                      radius: 16,
                      padding: const EdgeInsets.all(18),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  subscription.plan?.name ?? 'Business',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 20,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ),
                              _statusBadge(
                                subscription.status,
                                access.isTrial,
                                trialColor,
                              ),
                            ],
                          ),
                          const SizedBox(height: 14),
                          _row('Current Plan', subscription.plan?.name ?? '-'),
                          _row('Status', _statusLabel(subscription.status)),
                          _row(
                            'Expires At',
                            _formatDate(subscription.expiresAt),
                          ),
                          _row('Days Remaining', days?.toString() ?? '-'),
                          _row(
                            'Billing Cycle',
                            _titleCase(subscription.billingCycle),
                          ),
                          _row(
                            'Max Members',
                            maxMembers?.toString() ?? 'Unlimited',
                          ),
                          _row('Current Members', membersCount.toString()),
                          if (access.isTrial) ...[
                            const SizedBox(height: 10),
                            Text(
                              remaining == null
                                  ? 'Trial countdown unavailable'
                                  : '${_countdownText(remaining)} left',
                              style: TextStyle(
                                color: trialColor,
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),
                    PrimaryButton(
                      text: 'Upgrade Plan',
                      icon: Icons.upgrade_rounded,
                      onPressed: _actionLoading
                          ? null
                          : () => _handleUpgrade(subscription, plans),
                    ),
                    const SizedBox(height: 10),
                    SecondaryButton(
                      text: 'Renew Subscription',
                      onPressed: _actionLoading
                          ? null
                          : () => _handleRenew(subscription),
                    ),
                    const SizedBox(height: 10),
                    SecondaryButton(
                      text: 'Cancel Subscription',
                      onPressed: _actionLoading
                          ? null
                          : () => _handleCancel(subscription),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _header(BuildContext context) {
    return Row(
      children: [
        IconButton(
          onPressed: () => Navigator.maybePop(context),
          icon: const Icon(Icons.arrow_back_ios_new, color: Colors.white),
        ),
        const SizedBox(width: 6),
        const Expanded(
          child: Text(
            'Subscription Management',
            style: TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    );
  }

  Widget _expiredBanner() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.highRisk.withOpacity(0.2),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.highRisk.withOpacity(0.6)),
      ),
      child: const Text(
        'Your subscription has expired. Upgrade now.',
        style: TextStyle(
          color: AppColors.highRisk,
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  Widget _row(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          SizedBox(
            width: 140,
            child: Text(
              label,
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 12,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _statusBadge(String status, bool isTrial, Color trialColor) {
    final label = _statusLabel(status);
    final color = isTrial ? trialColor : AppColors.stable;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withOpacity(0.2),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.6)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w700,
          fontSize: 11,
        ),
      ),
    );
  }

  String _statusLabel(String raw) {
    final status = raw.trim().toLowerCase();
    if (status == 'trial') return 'Trial';
    if (status == 'active') return 'Active';
    if (status == 'expired') return 'Expired';
    if (status == 'canceled' || status == 'cancelled') return 'Canceled';
    if (status.isEmpty) return 'Unknown';
    return '${status[0].toUpperCase()}${status.substring(1)}';
  }

  String _titleCase(String raw) {
    final value = raw.trim().toLowerCase();
    if (value.isEmpty) return '-';
    return '${value[0].toUpperCase()}${value.substring(1)}';
  }

  String _formatDate(DateTime? value) {
    if (value == null) return '-';
    final d = value.toLocal();
    final month = d.month.toString().padLeft(2, '0');
    final day = d.day.toString().padLeft(2, '0');
    return '${d.year}-$month-$day';
  }

  String _countdownText(Duration duration) {
    final totalDays = (duration.inMinutes / Duration.minutesPerDay).ceil();
    if (totalDays <= 1) return '1 day';
    return '$totalDays days';
  }

  Future<void> _handleRenew(UserSubscription subscription) async {
    setState(() => _actionLoading = true);
    try {
      await ref
          .read(subscriptionServiceProvider)
          .renewSubscription(subscription);
      ref.invalidate(activeSubscriptionProvider);
      ref.invalidate(subscriptionAccessProvider);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Subscription renewed.'),
          backgroundColor: AppColors.stable,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Renew failed: $e'),
          backgroundColor: AppColors.highRisk,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) setState(() => _actionLoading = false);
    }
  }

  Future<void> _handleCancel(UserSubscription subscription) async {
    setState(() => _actionLoading = true);
    try {
      await ref
          .read(subscriptionServiceProvider)
          .cancelSubscription(subscription);
      ref.invalidate(activeSubscriptionProvider);
      ref.invalidate(subscriptionAccessProvider);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Subscription canceled.'),
          backgroundColor: AppColors.lowFocus,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Cancel failed: $e'),
          backgroundColor: AppColors.highRisk,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) setState(() => _actionLoading = false);
    }
  }

  Future<void> _handleUpgrade(
    UserSubscription subscription,
    List<Plan> businessPlans,
  ) async {
    if (businessPlans.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No business plans available right now.'),
          backgroundColor: AppColors.lowFocus,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    final selected = await showModalBottomSheet<Plan>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return Container(
          margin: const EdgeInsets.all(12),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.card,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: Colors.white12),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: businessPlans.map((plan) {
              final isCurrent =
                  subscription.plan?.id == plan.id ||
                  subscription.plan?.code.toLowerCase() ==
                      plan.code.toLowerCase();
              return ListTile(
                enabled: !isCurrent,
                title: Text(
                  plan.name,
                  style: const TextStyle(color: Colors.white),
                ),
                subtitle: Text(
                  plan.monthlyPrice != null
                      ? '\$${plan.monthlyPrice!.toStringAsFixed(0)} / month'
                      : 'Custom pricing',
                  style: const TextStyle(color: AppColors.textSecondary),
                ),
                trailing: isCurrent
                    ? const Text(
                        'Current',
                        style: TextStyle(color: AppColors.stable),
                      )
                    : const Icon(
                        Icons.arrow_forward_ios_rounded,
                        color: Colors.white54,
                        size: 14,
                      ),
                onTap: isCurrent ? null : () => Navigator.pop(context, plan),
              );
            }).toList(),
          ),
        );
      },
    );

    if (selected == null) return;

    setState(() => _actionLoading = true);
    try {
      final profileId =
          subscription.businessProfileId?.trim().isNotEmpty == true
          ? subscription.businessProfileId!.trim()
          : await OrganizationService.instance.fetchPrimaryBusinessProfileId();
      if (profileId == null || profileId.isEmpty) {
        throw Exception('Business profile not found.');
      }

      await ref
          .read(subscriptionServiceProvider)
          .upsertSubscriptionForProfile(
            plan: selected,
            billingCycle: subscription.billingCycle,
            businessProfileId: profileId,
            status: 'active',
          );
      ref.invalidate(activeSubscriptionProvider);
      ref.invalidate(subscriptionAccessProvider);
      ref.invalidate(businessMembersCountProvider);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Plan upgraded successfully.'),
          backgroundColor: AppColors.stable,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Upgrade failed: $e'),
          backgroundColor: AppColors.highRisk,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) setState(() => _actionLoading = false);
    }
  }
}

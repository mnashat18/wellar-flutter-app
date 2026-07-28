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
import '../widgets/fade_slide.dart';
import '../widgets/state_views.dart';
import 'business_profile_wizard_screen.dart';
import 'subscription_management_screen.dart';
import 'subscription_success_screen.dart';

class PricingScreen extends ConsumerStatefulWidget {
  const PricingScreen({super.key});

  @override
  ConsumerState<PricingScreen> createState() => _PricingScreenState();
}

class _PricingScreenState extends ConsumerState<PricingScreen> {
  String _billingCycle = 'monthly';
  bool _processing = false;

  @override
  Widget build(BuildContext context) {
    final plansAsync = ref.watch(plansProvider);
    final subscriptionAsync = ref.watch(activeSubscriptionProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      body: Stack(
        children: [
          const AnimatedSpaceBackground(),
          SafeArea(
            child: plansAsync.when(
              loading: () => const SkeletonList(),
              error: (error, _) => ListView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                children: [
                  _header(context, false),
                  const SizedBox(height: 12),
                  StatusCard(
                    title: 'Unable to load plans',
                    message: error.toString(),
                    icon: Icons.warning_amber_rounded,
                    iconColor: AppColors.highRisk,
                    actionText: 'Retry',
                    onAction: () => ref.invalidate(plansProvider),
                  ),
                ],
              ),
              data: (plans) {
                final source = plans.isNotEmpty ? plans : _fallbackPlans();
                final normalized = [...source]
                  ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
                final hasSubscription = subscriptionAsync.maybeWhen(
                  data: (sub) => sub != null,
                  orElse: () => false,
                );

                return ListView(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                  children: [
                    FadeSlide(child: _header(context, hasSubscription)),
                    const SizedBox(height: 12),
                    FadeSlide(
                      delay: const Duration(milliseconds: 70),
                      child: _billingToggle(),
                    ),
                    const SizedBox(height: 12),
                    ...normalized.asMap().entries.map((entry) {
                      final index = entry.key;
                      final plan = entry.value;
                      return FadeSlide(
                        delay: Duration(milliseconds: 120 + (index * 80)),
                        child: Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: _PlanCard(
                            plan: plan,
                            billingCycle: _billingCycle,
                            isCurrent: _isCurrentPlan(
                              subscriptionAsync.maybeWhen(
                                data: (sub) => sub?.plan?.code,
                                orElse: () => null,
                              ),
                              plan.code,
                            ),
                            onAction: _processing
                                ? null
                                : () => _onSelectPlan(
                                    plan,
                                    currentSubscription:
                                        subscriptionAsync.valueOrNull,
                                  ),
                          ),
                        ),
                      );
                    }),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _header(BuildContext context, bool hasSubscription) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: const [
              Text(
                'Business Pricing',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                ),
              ),
              SizedBox(height: 6),
              Text(
                'Choose your plan and unlock business features.',
                style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
              ),
            ],
          ),
        ),
        if (hasSubscription)
          TextButton.icon(
            onPressed: () {
              Navigator.push(
                context,
                fadeSlideRoute(const SubscriptionManagementScreen()),
              );
            },
            icon: const Icon(
              Icons.settings_suggest_rounded,
              color: AppColors.primarySoft,
              size: 17,
            ),
            label: const Text(
              'Manage',
              style: TextStyle(
                color: AppColors.primarySoft,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
      ],
    );
  }

  Widget _billingToggle() {
    return AppCard(
      radius: 16,
      padding: const EdgeInsets.all(8),
      child: Row(
        children: [
          Expanded(
            child: _cycleButton(
              label: 'Monthly',
              selected: _billingCycle == 'monthly',
              onTap: () => setState(() => _billingCycle = 'monthly'),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _cycleButton(
              label: 'Yearly',
              helper: 'Save more',
              selected: _billingCycle == 'yearly',
              onTap: () => setState(() => _billingCycle = 'yearly'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _cycleButton({
    required String label,
    String? helper,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: selected ? AppColors.primarySoft : AppColors.backgroundAlt,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? AppColors.primarySoft : Colors.white12,
          ),
        ),
        child: Column(
          children: [
            Text(
              label,
              style: TextStyle(
                color: selected ? Colors.black : Colors.white,
                fontWeight: FontWeight.w700,
              ),
            ),
            if (helper != null) ...[
              const SizedBox(height: 3),
              Text(
                helper,
                style: TextStyle(
                  color: selected ? Colors.black87 : AppColors.textSecondary,
                  fontSize: 10,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _onSelectPlan(
    Plan plan, {
    required UserSubscription? currentSubscription,
  }) async {
    final code = plan.code.trim().toLowerCase();
    if (code == 'free') {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Free plan is already available.'),
          behavior: SnackBarBehavior.floating,
          backgroundColor: AppColors.cardAlt,
        ),
      );
      return;
    }

    if (!plan.isBusiness && code != 'business') {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('This plan is not marked as a Business plan.'),
          behavior: SnackBarBehavior.floating,
          backgroundColor: AppColors.lowFocus,
        ),
      );
      return;
    }

    setState(() => _processing = true);
    try {
      final profileId = await OrganizationService.instance
          .fetchPrimaryBusinessProfileId();
      if (profileId != null && profileId.trim().isNotEmpty) {
        final statusToApply = currentSubscription == null ? 'trial' : 'active';
        final updated = await ref
            .read(subscriptionServiceProvider)
            .upsertSubscriptionForProfile(
              plan: plan,
              billingCycle: _billingCycle,
              businessProfileId: profileId.trim(),
              status: statusToApply,
            );

        ref.invalidate(activeSubscriptionProvider);
        ref.invalidate(subscriptionAccessProvider);
        ref.invalidate(businessMembersCountProvider);

        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              statusToApply == 'trial'
                  ? 'Trial started using your existing business profile.'
                  : 'Subscription upgraded successfully.',
            ),
            behavior: SnackBarBehavior.floating,
            backgroundColor: AppColors.stable,
          ),
        );

        if (statusToApply == 'trial' && updated != null) {
          await Navigator.push(
            context,
            fadeSlideRoute(SubscriptionSuccessScreen(subscription: updated)),
          );
        } else {
          await Navigator.push(
            context,
            fadeSlideRoute(const SubscriptionManagementScreen()),
          );
        }
        return;
      }

      if (!mounted) return;
      await Navigator.push(
        context,
        fadeSlideRoute(
          BusinessProfileWizardScreen(plan: plan, billingCycle: _billingCycle),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Unable to continue: $e'),
          behavior: SnackBarBehavior.floating,
          backgroundColor: AppColors.highRisk,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _processing = false);
      }
    }
  }

  bool _isCurrentPlan(String? currentCode, String planCode) {
    if (currentCode == null || currentCode.trim().isEmpty) return false;
    return currentCode.trim().toLowerCase() == planCode.trim().toLowerCase();
  }
}

class _PlanCard extends StatelessWidget {
  final Plan plan;
  final String billingCycle;
  final bool isCurrent;
  final VoidCallback? onAction;

  const _PlanCard({
    required this.plan,
    required this.billingCycle,
    required this.isCurrent,
    required this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    final price = _priceText(plan, billingCycle);
    final cycleText = billingCycle == 'yearly' ? '/year' : '/month';
    final actionText = isCurrent
        ? 'Current Plan'
        : (plan.trialDays > 0 ? 'Start Free Trial' : 'Subscribe Now');
    final highlight = plan.isPopular;
    final code = plan.code.trim().toLowerCase();
    final features = plan.features.isNotEmpty
        ? plan.features
        : ((plan.isBusiness || code == 'business')
              ? const [
                  'Team members and collaboration',
                  'Reports and analytics',
                  'Priority business support',
                ]
              : const ['Personal use']);

    return AppCard(
      radius: 16,
      padding: const EdgeInsets.all(16),
      color: highlight ? AppColors.cardAlt.withOpacity(0.92) : null,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: highlight
                ? AppColors.accentGold.withOpacity(0.7)
                : Colors.transparent,
            width: 1.2,
          ),
        ),
        padding: const EdgeInsets.all(4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    plan.name.trim().isEmpty ? 'Plan' : plan.name,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                if (highlight)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.accentGold.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: AppColors.accentGold.withOpacity(0.7),
                      ),
                    ),
                    child: const Text(
                      'Popular',
                      style: TextStyle(
                        color: AppColors.accentGold,
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
              ],
            ),
            if (plan.description.trim().isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                plan.description,
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 12,
                ),
              ),
            ],
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  price,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 28,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  cycleText,
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            PrimaryButton(
              text: actionText,
              icon: isCurrent
                  ? Icons.verified_rounded
                  : Icons.rocket_launch_rounded,
              onPressed: isCurrent ? null : onAction,
            ),
            const SizedBox(height: 12),
            ...features.map(
              (feature) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Padding(
                      padding: EdgeInsets.only(top: 2),
                      child: Icon(
                        Icons.check_circle_rounded,
                        size: 15,
                        color: AppColors.primarySoft,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        feature,
                        style: const TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _priceText(Plan plan, String cycle) {
    final code = plan.code.trim().toLowerCase();
    if (code == 'free') return 'Free';
    final monthly = plan.monthlyPrice ?? 0;
    if (cycle == 'yearly') {
      final yearly = plan.yearlyPrice ?? (monthly * 12);
      if (yearly <= 0) return 'Custom';
      return _formatCurrency(yearly);
    }
    if (monthly <= 0) return 'Custom';
    return _formatCurrency(monthly);
  }

  String _formatCurrency(double value) {
    if (value == value.roundToDouble()) {
      return '\$${value.toInt()}';
    }
    return '\$${value.toStringAsFixed(2)}';
  }
}

List<Plan> _fallbackPlans() {
  return const [
    Plan(
      id: 'free',
      name: 'Free',
      code: 'free',
      description: 'Basic access for individual users.',
      monthlyPrice: 0,
      yearlyPrice: 0,
      trialDays: 0,
      maxMembers: 1,
      isBusiness: false,
      features: ['Personal dashboard', 'Scan history'],
      isPopular: false,
      isActive: true,
      sortOrder: 1,
    ),
    Plan(
      id: 'business',
      name: 'Business',
      code: 'business',
      description: 'Team collaboration and premium reporting.',
      monthlyPrice: 29,
      yearlyPrice: 299,
      trialDays: 14,
      maxMembers: 25,
      isBusiness: true,
      features: [
        'Add and manage members',
        'Business reports and exports',
        'Priority support',
      ],
      isPopular: true,
      isActive: true,
      sortOrder: 2,
    ),
  ];
}

import 'dart:async';

import 'package:flutter/material.dart';

import '../models/user_subscription.dart';
import '../utils/app_colors.dart';
import '../utils/page_transition.dart';
import '../widgets/animated_space_background.dart';
import '../widgets/app_buttons.dart';
import '../widgets/app_cards.dart';
import 'business_members_manage_screen.dart';
import 'subscription_management_screen.dart';

class SubscriptionSuccessScreen extends StatefulWidget {
  final UserSubscription subscription;

  const SubscriptionSuccessScreen({super.key, required this.subscription});

  @override
  State<SubscriptionSuccessScreen> createState() =>
      _SubscriptionSuccessScreenState();
}

class _SubscriptionSuccessScreenState extends State<SubscriptionSuccessScreen> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final remaining = _remaining(widget.subscription.expiresAt);
    final daysLeft = remaining == null
        ? null
        : (remaining.inMinutes / Duration.minutesPerDay).ceil();
    final trialColor = (daysLeft != null && daysLeft < 3)
        ? AppColors.highRisk
        : AppColors.lowFocus;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: Stack(
        children: [
          const AnimatedSpaceBackground(),
          SafeArea(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 24),
              children: [
                Container(
                  padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(20),
                    gradient: LinearGradient(
                      colors: [
                        AppColors.primary.withOpacity(0.85),
                        AppColors.accentGold.withOpacity(0.8),
                      ],
                    ),
                  ),
                  child: Column(
                    children: [
                      TweenAnimationBuilder<double>(
                        duration: const Duration(milliseconds: 700),
                        tween: Tween(begin: 0.7, end: 1),
                        curve: Curves.easeOutBack,
                        builder: (context, value, child) {
                          return Transform.scale(scale: value, child: child);
                        },
                        child: const CircleAvatar(
                          radius: 28,
                          backgroundColor: Colors.white,
                          child: Icon(
                            Icons.check_rounded,
                            color: AppColors.stable,
                            size: 32,
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        'Welcome to Business Plan',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 520),
                    child: AppCard(
                      radius: 16,
                      padding: const EdgeInsets.all(18),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _row(
                            'Plan Name',
                            widget.subscription.plan?.name ?? 'Business',
                          ),
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              const SizedBox(
                                width: 120,
                                child: Text(
                                  'Status',
                                  style: TextStyle(
                                    color: AppColors.textSecondary,
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: trialColor.withOpacity(0.2),
                                  borderRadius: BorderRadius.circular(20),
                                  border: Border.all(
                                    color: trialColor.withOpacity(0.7),
                                  ),
                                ),
                                child: Text(
                                  'Trial',
                                  style: TextStyle(
                                    color: trialColor,
                                    fontWeight: FontWeight.w700,
                                    fontSize: 11,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          _row(
                            'Trial Ends In',
                            remaining == null ? '-' : _countdownText(remaining),
                            valueColor: trialColor,
                          ),
                          const SizedBox(height: 10),
                          _row(
                            'Expiration Date',
                            _formatDate(widget.subscription.expiresAt),
                          ),
                          const SizedBox(height: 16),
                          PrimaryButton(
                            text: 'Manage Subscription',
                            icon: Icons.settings_suggest_rounded,
                            onPressed: () {
                              Navigator.push(
                                context,
                                fadeSlideRoute(
                                  const SubscriptionManagementScreen(),
                                ),
                              );
                            },
                          ),
                          const SizedBox(height: 10),
                          SecondaryButton(
                            text: 'Invite Members',
                            onPressed: () {
                              Navigator.push(
                                context,
                                fadeSlideRoute(
                                  const BusinessMembersManageScreen(),
                                ),
                              );
                            },
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _row(String label, String value, {Color valueColor = Colors.white}) {
    return Row(
      children: [
        SizedBox(
          width: 120,
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
            style: TextStyle(
              color: valueColor,
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    );
  }

  Duration? _remaining(DateTime? expiresAt) {
    if (expiresAt == null) return null;
    final diff = expiresAt.toUtc().difference(DateTime.now().toUtc());
    if (diff.isNegative) return Duration.zero;
    return diff;
  }

  String _countdownText(Duration remaining) {
    final days = (remaining.inMinutes / Duration.minutesPerDay).ceil();
    return days <= 1 ? '1 day left' : '$days days left';
  }

  String _formatDate(DateTime? value) {
    if (value == null) return '-';
    final d = value.toLocal();
    final month = d.month.toString().padLeft(2, '0');
    final day = d.day.toString().padLeft(2, '0');
    return '${d.year}-$month-$day';
  }
}

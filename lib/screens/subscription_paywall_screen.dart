import 'package:flutter/material.dart';

import '../utils/app_colors.dart';
import '../utils/page_transition.dart';
import '../widgets/animated_space_background.dart';
import '../widgets/app_buttons.dart';
import '../widgets/app_cards.dart';
import 'pricing_screen.dart';

class SubscriptionPaywallScreen extends StatelessWidget {
  final String? title;
  final String? message;

  const SubscriptionPaywallScreen({super.key, this.title, this.message});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Stack(
        children: [
          const AnimatedSpaceBackground(),
          SafeArea(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: AppCard(
                  radius: 16,
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 72,
                        height: 72,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: LinearGradient(
                            colors: [
                              AppColors.highRisk.withOpacity(0.9),
                              AppColors.accentGold.withOpacity(0.9),
                            ],
                          ),
                        ),
                        child: const Icon(
                          Icons.workspace_premium_rounded,
                          color: Colors.white,
                          size: 34,
                        ),
                      ),
                      const SizedBox(height: 14),
                      Text(
                        title ?? 'Business subscription required',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        message ??
                            'Your subscription has expired. Upgrade now to keep team management and reports active.',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 13,
                        ),
                      ),
                      const SizedBox(height: 14),
                      _feature('Invite and manage team members'),
                      _feature('Advanced reports and exports'),
                      _feature('Analytics and activity insights'),
                      const SizedBox(height: 18),
                      PrimaryButton(
                        text: 'Upgrade Now',
                        icon: Icons.upgrade_rounded,
                        onPressed: () {
                          Navigator.push(
                            context,
                            fadeSlideRoute(const PricingScreen()),
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _feature(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          const Icon(
            Icons.check_circle_rounded,
            color: AppColors.primarySoft,
            size: 16,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 12,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

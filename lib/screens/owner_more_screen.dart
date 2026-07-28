import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../i18n/tr.dart';
import '../state/app_providers.dart';
import '../theme/app_theme.dart';
import '../utils/page_transition.dart';
import '../widgets/animated_wellar_screen.dart';
import '../widgets/owner/owner_design_system.dart';
import 'notifications_screen.dart';
import 'owner_company_screen.dart';
import 'owner_reports_screen.dart';
import 'profile_screen.dart';

class OwnerMoreScreen extends ConsumerWidget {
  const OwnerMoreScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lang = ref.watch(appLanguageControllerProvider).language;
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: AnimatedWellarScreen(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
        child: ListView(
          children: [
            SectionHeader(
              title: Tr.t(lang, 'owner_more_title'),
              subtitle: Tr.t(lang, 'owner_more_subtitle'),
            ),
            const SizedBox(height: 14),
            _menuCard(
              icon: Icons.insights_outlined,
              title: Tr.t(lang, 'reports'),
              subtitle: Tr.t(lang, 'owner_action_reports_sub'),
              onTap: () => Navigator.push(
                context,
                fadeSlideRoute(const OwnerReportsScreen()),
              ),
            ),
            const SizedBox(height: 10),
            _menuCard(
              icon: Icons.verified_user_outlined,
              title: Tr.t(lang, 'compliance'),
              subtitle: Tr.t(lang, 'owner_action_compliance_sub'),
              onTap: () => Navigator.push(
                context,
                fadeSlideRoute(const OwnerCompanyScreen()),
              ),
            ),
            const SizedBox(height: 10),
            _menuCard(
              icon: Icons.notifications_outlined,
              title: Tr.t(lang, 'alerts'),
              subtitle: Tr.t(lang, 'owner_action_alerts_sub'),
              onTap: () => Navigator.push(
                context,
                fadeSlideRoute(const NotificationsScreen()),
              ),
            ),
            const SizedBox(height: 10),
            _menuCard(
              icon: Icons.person_outline_rounded,
              title: Tr.t(lang, 'profile'),
              subtitle: Tr.t(lang, 'account_workspace_settings'),
              onTap: () => Navigator.push(
                context,
                fadeSlideRoute(const ProfileScreen()),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _menuCard({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return OwnerSurfaceCard(
      onTap: onTap,
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              gradient: const LinearGradient(
                colors: [Color(0x3349D3C2), Color(0x33458BFF)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              border: Border.all(color: const Color(0x4049D3C2)),
            ),
            child: Icon(icon, color: WellarTheme.primary),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: WellarTheme.text,
                    fontWeight: FontWeight.w700,
                    fontSize: 14.5,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  subtitle,
                  style: const TextStyle(
                    color: WellarTheme.textMuted,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          const Icon(
            Icons.arrow_forward_ios_rounded,
            color: WellarTheme.textMuted,
            size: 15,
          ),
        ],
      ),
    );
  }
}

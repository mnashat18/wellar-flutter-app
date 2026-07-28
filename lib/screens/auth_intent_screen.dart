import 'package:flutter/material.dart';

import '../state/session.dart';
import '../utils/app_colors.dart';
import '../utils/page_transition.dart';
import 'invite_screen.dart';
import 'login_screen.dart';
import 'register_screen.dart';
import 'workspace_access_screen.dart';

class AuthIntentScreen extends StatelessWidget {
  const AuthIntentScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final pendingInviteToken =
        Session.instance.pendingInviteToken?.trim() ?? '';

    return Scaffold(
      backgroundColor: const Color(0xFF050A12),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            return SingleChildScrollView(
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: constraints.maxHeight),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const _BrandBlock(),
                    const SizedBox(height: 24),
                    const Text(
                      'How would you like to get started?',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 30,
                        fontWeight: FontWeight.w800,
                        height: 1.08,
                        letterSpacing: -0.45,
                      ),
                    ),
                    const SizedBox(height: 10),
                    const Text(
                      'Create a new organization, or join an existing one with an invitation from your team.',
                      style: TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 13.8,
                        height: 1.5,
                      ),
                    ),
                    const SizedBox(height: 18),
                    _IntentRow(
                      icon: Icons.apartment_outlined,
                      title: 'Create an organisation',
                      body:
                          'Start a new company workspace, then finish setup after sign-up.',
                      onTap: () {
                        Navigator.push(
                          context,
                          fadeSlideRoute(const RegisterScreen()),
                        );
                      },
                    ),
                    const SizedBox(height: 12),
                    _IntentRow(
                      icon: Icons.group_add_outlined,
                      title: 'Join an organisation',
                      body: pendingInviteToken.isNotEmpty
                          ? 'Continue with your invitation link or code.'
                          : 'Use an invitation link or invite code from your team.',
                      onTap: () {
                        if (pendingInviteToken.isNotEmpty) {
                          Navigator.push(
                            context,
                            fadeSlideRoute(
                              InviteScreen(token: pendingInviteToken),
                            ),
                          );
                          return;
                        }
                        Navigator.push(
                          context,
                          fadeSlideRoute(
                            const WorkspaceAccessScreen(
                              state: WorkspaceAccessViewState.pendingInvite,
                            ),
                          ),
                        );
                      },
                    ),
                    const SizedBox(height: 14),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton(
                        onPressed: () {
                          Navigator.push(
                            context,
                            fadeSlideRoute(const LoginScreen()),
                          );
                        },
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 0,
                            vertical: 6,
                          ),
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          foregroundColor: AppColors.primarySoft,
                        ),
                        child: const Text(
                          'Sign in',
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 13.5,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    const Text(
                      'Managed activation, invite claims, and role-based access are handled after authentication.',
                      style: TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 12.2,
                        height: 1.45,
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _BrandBlock extends StatelessWidget {
  const _BrandBlock();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 46,
          height: 46,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: const Color(0xFF101A2A),
            borderRadius: BorderRadius.circular(15),
            border: Border.all(color: const Color(0xFF273247)),
          ),
          child: const Text(
            'W',
            style: TextStyle(
              color: Colors.white,
              fontSize: 19,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        const SizedBox(width: 12),
        const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Wellar AI',
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.2,
              ),
            ),
            SizedBox(height: 4),
            Text(
              'Workforce operations',
              style: TextStyle(
                color: AppColors.textSecondary,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _IntentRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String body;
  final VoidCallback onTap;

  const _IntentRow({
    required this.icon,
    required this.title,
    required this.body,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFF0B1320),
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFF0B1320),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: const Color(0xFF243247)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 42,
                height: 42,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: const Color(0xFF102032),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: const Color(0xFF2C415A)),
                ),
                child: Icon(icon, color: AppColors.primarySoft, size: 22),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 15.5,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      body,
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 13,
                        height: 1.45,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              const Icon(
                Icons.arrow_forward_ios_rounded,
                color: AppColors.textSecondary,
                size: 16,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

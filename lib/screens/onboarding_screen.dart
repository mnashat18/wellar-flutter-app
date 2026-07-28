import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../i18n/tr.dart';
import '../services/auth_service.dart';
import '../utils/app_colors.dart';
import '../utils/page_transition.dart';
import '../widgets/animated_space_background.dart';
import '../widgets/app_buttons.dart';
import '../widgets/app_cards.dart';
import '../widgets/fade_slide.dart';
import '../widgets/google_auth_button.dart';
import 'login_screen.dart';
import 'pricing_screen.dart';
import 'register_screen.dart';
import 'role_based_shells.dart';
import 'workspace_access_screen.dart';

import '../state/app_providers.dart';

class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  bool _googleLoading = false;
  String? _error;

  Future<void> _continueWithGoogle() async {
    if (_googleLoading) return;
    setState(() => _googleLoading = true);
    try {
      await AuthService.instance.loginWithGoogle();
      if (!mounted) return;
      setState(() => _error = null);
      final result = await resolveVerifiedRouteResult(validateSession: false);
      if (!mounted) return;
      switch (result.kind) {
        case VerifiedRouteKind.roleShell:
          Navigator.pushReplacement(
            context,
            fadeSlideRoute(RoleShellRouter(initialContext: result.context)),
          );
          return;
        case VerifiedRouteKind.workspaceAccessError:
        case VerifiedRouteKind.restrictedWorkspace:
          Navigator.pushReplacement(
            context,
            fadeSlideRoute(
              WorkspaceAccessScreen(
                state: WorkspaceAccessViewState.accessResolutionError,
                message: result.message,
              ),
            ),
          );
          return;
        case VerifiedRouteKind.workspaceAccess:
          Navigator.pushReplacement(
            context,
            fadeSlideRoute(
              const WorkspaceAccessScreen(
                state: WorkspaceAccessViewState.noWorkspace,
              ),
            ),
          );
          return;
        case VerifiedRouteKind.workspaceNotActivated:
          Navigator.pushReplacement(
            context,
            fadeSlideRoute(
              const WorkspaceAccessScreen(
                state: WorkspaceAccessViewState.workspaceNotActivated,
              ),
            ),
          );
          return;
        case VerifiedRouteKind.login:
          Navigator.pushReplacement(
            context,
            fadeSlideRoute(const LoginScreen()),
          );
          return;
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e is AuthFlowException
            ? _friendlyGoogleError(e)
            : Tr.t(ref.read(appLanguageControllerProvider).language, 'signin_generic_failed');
      });
    } finally {
      if (mounted) {
        setState(() => _googleLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final lang = ref.watch(appLanguageControllerProvider).language;
    void openLogin() {
      Navigator.push(context, fadeSlideRoute(const LoginScreen()));
    }

    void openRegister() {
      Navigator.push(context, fadeSlideRoute(const RegisterScreen()));
    }

    return Scaffold(
      backgroundColor: AppColors.background,
      body: Stack(
        children: [
          const AnimatedSpaceBackground(),
          Positioned.fill(
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.white.withValues(alpha: 0.04),
                      Colors.transparent,
                      Colors.black.withValues(alpha: 0.24),
                    ],
                    stops: const [0.0, 0.35, 1.0],
                  ),
                ),
              ),
            ),
          ),
          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 24, 20, 26),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 780),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      FadeSlide(child: _buildBrand()),
                      const SizedBox(height: 22),
                      FadeSlide(
                        delay: const Duration(milliseconds: 80),
                        child: const Text(
                          'Daily readiness checks\nin under 2 minutes.',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 44,
                            fontWeight: FontWeight.w800,
                            height: 1.02,
                            letterSpacing: -1.1,
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      FadeSlide(
                        delay: const Duration(milliseconds: 130),
                        child: const Text(
                          'Shorter onboarding. Faster access. One secure sign-in with Google.',
                          style: TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 14,
                            height: 1.55,
                          ),
                        ),
                      ),
                      const SizedBox(height: 18),
                      FadeSlide(
                        delay: const Duration(milliseconds: 190),
                        child: Wrap(
                          spacing: 12,
                          runSpacing: 12,
                          children: const [
                            _QuickPoint(
                              icon: Icons.timer_outlined,
                              title: '2 min pre-trip scan',
                              subtitle: 'Driver-friendly mobile flow',
                            ),
                            _QuickPoint(
                              icon: Icons.shield_outlined,
                              title: 'Role aware',
                              subtitle: 'Secure access controls',
                            ),
                            _QuickPoint(
                              icon: Icons.insights_outlined,
                              title: 'Live dispatch signal',
                              subtitle: 'Readiness posted instantly',
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),
                      FadeSlide(
                        delay: const Duration(milliseconds: 250),
                        child: AppCard(
                          padding: const EdgeInsets.all(18),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Continue',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 16,
                                ),
                              ),
                              const SizedBox(height: 6),
                              const Text(
                                'Google sign-in only',
                                style: TextStyle(
                                  color: AppColors.textSecondary,
                                  fontSize: 12,
                                ),
                              ),
                              const SizedBox(height: 12),
                              GoogleAuthButton(
                                text: _googleLoading
                                    ? 'Connecting...'
                                    : Tr.t(lang, 'continue_with_google'),
                                isLoading: _googleLoading,
                                onPressed: _googleLoading
                                    ? null
                                    : _continueWithGoogle,
                              ),
                              const SizedBox(height: 12),
                              Row(
                                children: [
                                  Expanded(
                                    child: SecondaryButton(
                                      text: 'Login',
                                      onPressed: openLogin,
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: PrimaryButton(
                                      text: 'Create Account',
                                      onPressed: openRegister,
                                      height: 50,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Align(
                                alignment: Alignment.centerRight,
                                child: TextButton(
                                  onPressed: () {
                                    Navigator.push(
                                      context,
                                      fadeSlideRoute(const PricingScreen()),
                                    );
                                  },
                                  child: const Text(
                                    'View plans',
                                    style: TextStyle(
                                      color: AppColors.primarySoft,
                                      fontWeight: FontWeight.w600,
                                    ),
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
              ),
            ),
          ),
          if (_error != null)
            Positioned.fill(
              child: GestureDetector(
                onTap: () => setState(() => _error = null),
                child: Container(
                  color: Colors.black.withValues(alpha: 0.35),
                  alignment: Alignment.center,
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: AppColors.cardAlt,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: AppColors.highRisk),
                    ),
                    child: Text(
                      _error!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildBrand() {
    return Row(
      children: [
        Container(
          width: 44,
          height: 44,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            gradient: const LinearGradient(
              colors: [AppColors.primarySoft, AppColors.primary],
            ),
          ),
          child: const Text(
            'W',
            style: TextStyle(
              color: Colors.black,
              fontWeight: FontWeight.w800,
              fontSize: 19,
            ),
          ),
        ),
        const SizedBox(width: 10),
        const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Wellar AI',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
                fontSize: 18,
              ),
            ),
            SizedBox(height: 2),
            Text(
              'Fleet pre-shift safety and compliance',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 11),
            ),
          ],
        ),
      ],
    );
  }

  String _friendlyGoogleError(AuthFlowException e) {
    final lang = ref.read(appLanguageControllerProvider).language;
    switch (e.code) {
      case AuthFlowError.googleCancelled:
        return Tr.t(lang, 'google_signin_cancelled');
      case AuthFlowError.googleNoIdToken:
        return Tr.t(lang, 'google_signin_try_again');
      case AuthFlowError.networkIssue:
        return Tr.t(lang, 'connection_issue_try_again');
      case AuthFlowError.googleExchangeMissing:
        return Tr.t(lang, 'google_signin_exchange_missing');
      case AuthFlowError.googleConfigMissing:
        return Tr.t(lang, 'google_signin_config_error');
      case AuthFlowError.noWorkspaceSession:
        return Tr.t(lang, 'google_signin_no_session');
      case AuthFlowError.noMembership:
        return Tr.t(lang, 'google_signin_no_membership');
      case AuthFlowError.invalidSession:
        return Tr.t(lang, 'session_expired_signin');
    }
  }
}

class _QuickPoint extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;

  const _QuickPoint({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 228,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.cardAlt.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white12),
      ),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: AppColors.primarySoft.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: AppColors.primarySoft, size: 18),
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
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 2),
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
        ],
      ),
    );
  }
}

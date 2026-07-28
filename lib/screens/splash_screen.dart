import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:google_fonts/google_fonts.dart';

import '../services/auth_service.dart';
import '../services/organization_service.dart';
import '../state/session.dart';
import '../utils/app_colors.dart';
import '../utils/page_transition.dart';
import 'login_screen.dart';
import 'public_entry_screen.dart';
import 'workspace_access_screen.dart';
import 'role_based_shells.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with TickerProviderStateMixin {
  static const List<String> _slowLoadingStates = [
    'Authenticating',
    'Restoring workspace',
    'Loading dashboard',
    'Preparing experience',
  ];

  // If startup exceeds this window, morph the bottom into the premium
  // "Preparing your workspace" panel so the user is never left staring at
  // only a logo. No artificial floor is enforced; fast startup routes
  // immediately when resolveVerifiedRouteResult completes.
  static const Duration _slowStateThreshold = Duration(milliseconds: 1400);

  late final AnimationController _intro;
  late final AnimationController _ambient;
  late final Animation<double> _wordmarkOpacity;
  late final Animation<double> _wordmarkOffset;
  late final Animation<double> _subtitleOpacity;
  late final Animation<double> _footerOpacity;

  Timer? _slowTimer;
  Timer? _statusRotator;
  int _statusIndex = 0;
  bool _slowMode = false;
  bool _startupFailed = false;
  bool _reduceMotion = false;
  bool _navigationCommitted = false;
  bool _navigationScheduled = false;

  @override
  void initState() {
    super.initState();

    _intro = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _ambient = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 8),
    )..repeat(reverse: true);

    _wordmarkOpacity = CurvedAnimation(
      parent: _intro,
      curve: const Interval(0.28, 0.70, curve: Curves.easeOut),
    );
    _wordmarkOffset = Tween<double>(begin: 12, end: 0).animate(
      CurvedAnimation(
        parent: _intro,
        curve: const Interval(0.28, 0.70, curve: Curves.easeOutCubic),
      ),
    );
    _subtitleOpacity = CurvedAnimation(
      parent: _intro,
      curve: const Interval(0.46, 0.88, curve: Curves.easeOut),
    );
    _footerOpacity = CurvedAnimation(
      parent: _intro,
      curve: const Interval(0.66, 1.0, curve: Curves.easeOut),
    );

    _intro.forward();

    _slowTimer = Timer(_slowStateThreshold, _enterSlowMode);
    _bootstrap();
  }

  void _enterSlowMode() {
    if (!mounted || _startupFailed) return;
    setState(() => _slowMode = true);
    _statusRotator ??= Timer.periodic(const Duration(milliseconds: 1500), (_) {
      if (!mounted) return;
      setState(() {
        _statusIndex = (_statusIndex + 1) % _slowLoadingStates.length;
      });
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduce = MediaQuery.of(context).disableAnimations;
    if (reduce != _reduceMotion) {
      _reduceMotion = reduce;
      if (_reduceMotion) {
        _ambient.stop();
        _ambient.value = 0.5;
      } else if (!_ambient.isAnimating) {
        _ambient.repeat(reverse: true);
      }
    }
  }

  @override
  void dispose() {
    _slowTimer?.cancel();
    _statusRotator?.cancel();
    _intro.dispose();
    _ambient.dispose();
    super.dispose();
  }

  static const Duration _startupHardTimeout = Duration(seconds: 8);

  Future<void> _bootstrap() async {
    setState(() {
      _startupFailed = false;
      _slowMode = false;
      _statusIndex = 0;
    });
    _slowTimer?.cancel();
    _statusRotator?.cancel();
    _statusRotator = null;
    _slowTimer = Timer(_slowStateThreshold, _enterSlowMode);

    if (_intro.status == AnimationStatus.completed) {
      _intro.forward(from: 0);
    }
    debugPrint('[STARTUP_ROUTE] start');
    final sessionPresent = Session.instance.isLoggedIn;
    debugPrint('[STARTUP_ROUTE] session_present=$sessionPresent');
    if (!sessionPresent) {
      debugPrint('[STARTUP_ROUTE] resolved=public_entry');
      _slowTimer?.cancel();
      _statusRotator?.cancel();
      OrganizationService.instance.clearActiveWorkspaceContext();
      _scheduleStartupNavigation(const PublicEntryScreen());
      return;
    }
    try {
      final sessionState = await AuthService.instance
          .validateSession()
          .timeout(_startupHardTimeout);
      if (!mounted) return;
      switch (sessionState) {
        case SessionValidationState.unauthenticated:
          debugPrint('[STARTUP_ROUTE] user_verified=false');
          debugPrint('[STARTUP_ROUTE] resolved=public_entry');
          OrganizationService.instance.clearActiveWorkspaceContext();
          _slowTimer?.cancel();
          _statusRotator?.cancel();
          _scheduleStartupNavigation(const PublicEntryScreen());
          return;
        case SessionValidationState.validationUnavailable:
          debugPrint('[STARTUP_ROUTE] validation_unavailable=true');
          break;
        case SessionValidationState.authenticated:
          break;
      }

      final result = await resolveVerifiedRouteResult(validateSession: false)
          .timeout(_startupHardTimeout);
      if (!mounted) return;
      late final Widget target;
      switch (result.kind) {
        case VerifiedRouteKind.login:
          debugPrint('[STARTUP_ROUTE] user_verified=false');
          debugPrint('[STARTUP_ROUTE] resolved=public_entry');
          OrganizationService.instance.clearActiveWorkspaceContext();
          target = const PublicEntryScreen();
          break;
        case VerifiedRouteKind.workspaceAccessError:
          debugPrint('[STARTUP_ROUTE] resolved=workspace_access_error');
          target = WorkspaceAccessScreen(
            state: WorkspaceAccessViewState.accessResolutionError,
            message: result.message,
          );
          break;
        case VerifiedRouteKind.roleShell:
          debugPrint('[STARTUP_ROUTE] user_verified=true');
          debugPrint('[STARTUP_ROUTE] resolved=role_shell');
          target = RoleShellRouter(initialContext: result.context);
          break;
        case VerifiedRouteKind.workspaceAccess:
          debugPrint('[STARTUP_ROUTE] user_verified=true');
          debugPrint('[STARTUP_ROUTE] resolved=workspace_access_new_company');
          target = const WorkspaceAccessScreen(
            state: WorkspaceAccessViewState.noWorkspace,
          );
          break;
        case VerifiedRouteKind.restrictedWorkspace:
          debugPrint('[STARTUP_ROUTE] resolved=workspace_access_error');
          target = WorkspaceAccessScreen(
            state: WorkspaceAccessViewState.accessResolutionError,
            message: result.message,
          );
          break;
        case VerifiedRouteKind.workspaceNotActivated:
          debugPrint('[STARTUP_ROUTE] user_verified=true');
          debugPrint('[STARTUP_ROUTE] resolved=workspace_not_activated');
          target = const WorkspaceAccessScreen(
            state: WorkspaceAccessViewState.workspaceNotActivated,
          );
          break;
      }
      _slowTimer?.cancel();
      _statusRotator?.cancel();
      _scheduleStartupNavigation(target);
    } on TimeoutException {
      debugPrint('[STARTUP_ROUTE] timeout=true');
      debugPrint('[STARTUP_ROUTE] resolved=splash_fallback');
      if (!mounted) return;
      _slowTimer?.cancel();
      _statusRotator?.cancel();
      setState(() {
        _startupFailed = true;
        _slowMode = false;
      });
    } on FirebaseException catch (e) {
      debugPrint('[STARTUP_ROUTE] firebase_exception_non_fatal=true');
      debugPrint('[STARTUP_ROUTE] startup_error_type=${e.runtimeType}');
      if (!mounted) return;
      _slowTimer?.cancel();
      _statusRotator?.cancel();
      try {
        final result = await resolveVerifiedRouteResult(validateSession: false)
            .timeout(_startupHardTimeout);
        if (!mounted) return;
        late final Widget target;
        switch (result.kind) {
          case VerifiedRouteKind.login:
            debugPrint('[STARTUP_ROUTE] user_verified=false');
            debugPrint('[STARTUP_ROUTE] resolved=public_entry');
            OrganizationService.instance.clearActiveWorkspaceContext();
            target = const PublicEntryScreen();
            break;
          case VerifiedRouteKind.workspaceAccessError:
            debugPrint('[STARTUP_ROUTE] resolved=workspace_access_error');
            target = WorkspaceAccessScreen(
              state: WorkspaceAccessViewState.accessResolutionError,
              message: result.message,
            );
            break;
          case VerifiedRouteKind.roleShell:
            debugPrint('[STARTUP_ROUTE] user_verified=true');
            debugPrint('[STARTUP_ROUTE] resolved=role_shell');
            target = RoleShellRouter(initialContext: result.context);
            break;
          case VerifiedRouteKind.workspaceAccess:
            debugPrint('[STARTUP_ROUTE] user_verified=true');
            debugPrint('[STARTUP_ROUTE] resolved=workspace_access_new_company');
            target = const WorkspaceAccessScreen(
              state: WorkspaceAccessViewState.noWorkspace,
            );
            break;
          case VerifiedRouteKind.restrictedWorkspace:
            debugPrint('[STARTUP_ROUTE] resolved=workspace_access_error');
            target = WorkspaceAccessScreen(
              state: WorkspaceAccessViewState.accessResolutionError,
              message: result.message,
            );
            break;
          case VerifiedRouteKind.workspaceNotActivated:
            debugPrint('[STARTUP_ROUTE] user_verified=true');
            debugPrint('[STARTUP_ROUTE] resolved=workspace_not_activated');
            target = const WorkspaceAccessScreen(
              state: WorkspaceAccessViewState.workspaceNotActivated,
            );
            break;
        }
        _scheduleStartupNavigation(target);
      } on TimeoutException {
        debugPrint('[STARTUP_ROUTE] timeout=true');
        debugPrint('[STARTUP_ROUTE] resolved=splash_fallback');
        if (!mounted) return;
        _slowTimer?.cancel();
        _statusRotator?.cancel();
        setState(() {
          _startupFailed = true;
          _slowMode = false;
        });
      } catch (inner) {
        debugPrint('[STARTUP_ROUTE] startup_error_type=${inner.runtimeType}');
      }
    } catch (e) {
      debugPrint('[STARTUP_ROUTE] startup_error_type=${e.runtimeType}');
    }
  }

  void _scheduleStartupNavigation(Widget target) {
    if (_navigationCommitted || _navigationScheduled) return;
    if (!mounted) return;
    _navigationScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _navigationCommitted) return;
      _navigationCommitted = true;
      Navigator.of(context, rootNavigator: true).pushReplacement(
        impactRoute(target),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Stack(
        fit: StackFit.expand,
        children: [
          const _SplashBackdrop(),
          _AmbientNebula(
            animation: _ambient,
            reduceMotion: _reduceMotion,
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 28),
              child: Column(
                children: [
                  Expanded(child: _buildBrandBlock()),
                  _buildBottomBlock(),
                  const SizedBox(height: 22),
                  _buildFooter(),
                  const SizedBox(height: 20),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBrandBlock() {
    return Center(
      child: AnimatedBuilder(
        animation: _intro,
        builder: (context, _) {
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Transform.translate(
                offset: Offset(0, _wordmarkOffset.value),
                child: Opacity(
                  opacity: _wordmarkOpacity.value,
                  child: Text(
                    'WELLAR',
                    style: GoogleFonts.spaceGrotesk(
                      fontSize: 32,
                      letterSpacing: 6,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                      height: 1,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Opacity(
                opacity: _subtitleOpacity.value,
                child: _buildSubtitle(context),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildSubtitle(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final availableWidth = (screenWidth - 56).clamp(220.0, 360.0);
    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: availableWidth),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Preparing your workspace',
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            softWrap: true,
            style: GoogleFonts.inter(
              color: Colors.white,
              fontSize: 13.5,
              letterSpacing: 0.15,
              fontWeight: FontWeight.w600,
              height: 1.25,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Securing your session and loading your organization data',
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            softWrap: true,
            style: GoogleFonts.inter(
              color: AppColors.textSecondary,
              fontSize: 11.5,
              letterSpacing: 0.25,
              fontWeight: FontWeight.w500,
              height: 1.35,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomBlock() {
    return AnimatedSize(
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOutCubic,
      alignment: Alignment.bottomCenter,
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 380),
        switchInCurve: Curves.easeOut,
        switchOutCurve: Curves.easeIn,
        child: _startupFailed
            ? _startupErrorState()
            : (_slowMode ? _preparingPanel() : _idleIndicator()),
      ),
    );
  }

  Widget _idleIndicator() {
    return SizedBox(
      key: const ValueKey('idle-indicator'),
      height: 48,
      child: Center(
        child: AnimatedBuilder(
          animation: _intro,
          builder: (context, _) {
            return Opacity(
              opacity: _footerOpacity.value,
              child: _ShimmerLine(
                controller: _ambient,
                reduceMotion: _reduceMotion,
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _preparingPanel() {
    return Container(
      key: const ValueKey('preparing-panel'),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Preparing your workspace',
            style: GoogleFonts.spaceGrotesk(
              color: Colors.white,
              fontSize: 15.5,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.2,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Securing your session and loading your organization data.',
            style: GoogleFonts.inter(
              color: AppColors.textSecondary,
              fontSize: 12,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              _PulsingDots(controller: _ambient, reduceMotion: _reduceMotion),
              const SizedBox(width: 14),
              Expanded(
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 280),
                  transitionBuilder: (child, anim) => FadeTransition(
                    opacity: anim,
                    child: SlideTransition(
                      position: Tween<Offset>(
                        begin: const Offset(0, 0.18),
                        end: Offset.zero,
                      ).animate(anim),
                      child: child,
                    ),
                  ),
                  child: Text(
                    _slowLoadingStates[_statusIndex],
                    key: ValueKey<int>(_statusIndex),
                    style: GoogleFonts.inter(
                      color: Colors.white.withValues(alpha: 0.82),
                      fontSize: 12,
                      letterSpacing: 0.4,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildFooter() {
    return AnimatedBuilder(
      animation: _intro,
      builder: (context, _) {
        return Opacity(
          opacity: 0.55 * _footerOpacity.value,
          child: Text(
            'WORKFORCE WELLNESS INTELLIGENCE',
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.inter(
              color: AppColors.textSecondary,
              fontSize: 10,
              letterSpacing: 3.2,
              fontWeight: FontWeight.w600,
              height: 1.4,
            ),
          ),
        );
      },
    );
  }

  Widget _startupErrorState() {
    return Container(
      key: const ValueKey('startup-error'),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.cardAlt.withValues(alpha: 0.86),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppColors.primarySoft.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.wifi_rounded,
                  color: AppColors.primarySoft,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Connection is taking longer than expected',
                      style: GoogleFonts.spaceGrotesk(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                        height: 1.25,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Check your connection, then try again.',
                      style: GoogleFonts.inter(
                        color: AppColors.textSecondary,
                        fontSize: 12,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 44,
            child: ElevatedButton(
              onPressed: _bootstrap,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              child: Text(
                'Try again',
                style: GoogleFonts.inter(
                  fontWeight: FontWeight.w700,
                  fontSize: 13.5,
                  letterSpacing: 0.4,
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 44,
            child: OutlinedButton(
              onPressed: () {
                OrganizationService.instance.clearActiveWorkspaceContext();
                _scheduleStartupNavigation(
                  Session.instance.isLoggedIn
                      ? const LoginScreen()
                      : const PublicEntryScreen(),
                );
              },
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.white,
                side: const BorderSide(color: Color(0xFF314056)),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              child: Text(
                Session.instance.isLoggedIn
                    ? 'Use another account'
                    : 'Go to login',
                style: GoogleFonts.inter(
                  fontWeight: FontWeight.w700,
                  fontSize: 13.5,
                  letterSpacing: 0.4,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SplashBackdrop extends StatelessWidget {
  const _SplashBackdrop();

  @override
  Widget build(BuildContext context) {
    return const DecoratedBox(
      decoration: BoxDecoration(
        gradient: RadialGradient(
          center: Alignment(0, -0.15),
          radius: 1.25,
          colors: [
            Color(0xFF0F1A38),
            Color(0xFF080D22),
            Color(0xFF04060F),
          ],
          stops: [0.0, 0.55, 1.0],
        ),
      ),
      child: SizedBox.expand(),
    );
  }
}

class _AmbientNebula extends StatelessWidget {
  final Animation<double> animation;
  final bool reduceMotion;

  const _AmbientNebula({
    required this.animation,
    required this.reduceMotion,
  });

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: animation,
        builder: (context, _) {
          final t = reduceMotion ? 0.5 : animation.value;
          return Stack(
            children: [
              Positioned(
                top: 60 + 12 * t,
                left: -70,
                child: _GlowOrb(
                  size: 260,
                  colors: [
                    AppColors.primary.withValues(
                      alpha: 0.22 * (0.7 + 0.3 * t),
                    ),
                    Colors.transparent,
                  ],
                ),
              ),
              Positioned(
                bottom: 90 - 14 * t,
                right: -80,
                child: _GlowOrb(
                  size: 220,
                  colors: [
                    AppColors.primarySoft.withValues(
                      alpha: 0.14 * (0.6 + 0.4 * (1 - t)),
                    ),
                    Colors.transparent,
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _GlowOrb extends StatelessWidget {
  final double size;
  final List<Color> colors;

  const _GlowOrb({required this.size, required this.colors});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(colors: colors),
      ),
    );
  }
}

class _ShimmerLine extends StatelessWidget {
  final AnimationController controller;
  final bool reduceMotion;

  const _ShimmerLine({
    required this.controller,
    required this.reduceMotion,
  });

  @override
  Widget build(BuildContext context) {
    if (reduceMotion) {
      return Container(
        width: 120,
        height: 2,
        decoration: BoxDecoration(
          color: AppColors.primarySoft.withValues(alpha: 0.4),
          borderRadius: BorderRadius.circular(1),
        ),
      );
    }
    return SizedBox(
      width: 128,
      height: 2,
      child: AnimatedBuilder(
        animation: controller,
        builder: (context, _) {
          final t = controller.value;
          return ClipRRect(
            borderRadius: BorderRadius.circular(1),
            child: Stack(
              children: [
                Container(color: Colors.white.withValues(alpha: 0.06)),
                FractionallySizedBox(
                  widthFactor: 0.45,
                  heightFactor: 1,
                  alignment: Alignment(-1 + 2 * t, 0),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          Colors.transparent,
                          AppColors.primarySoft.withValues(alpha: 0.75),
                          Colors.transparent,
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _PulsingDots extends StatelessWidget {
  final AnimationController controller;
  final bool reduceMotion;

  const _PulsingDots({
    required this.controller,
    required this.reduceMotion,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: List.generate(3, (i) {
            final phase = ((controller.value * 2) + i * 0.18) % 1.0;
            final wave = 0.5 - (phase - 0.5).abs();
            final scale = reduceMotion ? 1.0 : 0.75 + 0.6 * wave;
            final alpha = reduceMotion ? 0.55 : (0.35 + wave * 1.3).clamp(0.0, 1.0);
            return Padding(
              padding: EdgeInsets.only(right: i == 2 ? 0 : 6),
              child: Container(
                width: 6 * scale,
                height: 6 * scale,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.primarySoft.withValues(alpha: alpha),
                ),
              ),
            );
          }),
        );
      },
    );
  }
}

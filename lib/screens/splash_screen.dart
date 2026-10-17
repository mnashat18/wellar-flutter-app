import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:google_fonts/google_fonts.dart';

import '../services/auth_service.dart';
import '../services/organization_service.dart';
import '../state/app_language_state.dart';
import '../state/session.dart';
import '../i18n/tr.dart';
import '../utils/app_colors.dart';
import '../utils/page_transition.dart';
import '../widgets/welcome_galaxy_background.dart';
import 'login_screen.dart';
import 'public_entry_screen.dart';
import 'workspace_access_screen.dart';
import 'role_based_shells.dart';
import 'workspace_picker_screen.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with TickerProviderStateMixin {
  static const List<String> _slowLoadingStates = [
    'authenticating',
    'restoring_workspace',
    'loading_dashboard',
    'preparing_experience',
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
  Widget? _resolvedTarget;

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
        _intro.stop();
        _intro.value = 1;
        _ambient.stop();
        _ambient.value = 0.5;
      } else {
        if (_intro.status != AnimationStatus.completed) _intro.forward();
        if (!_ambient.isAnimating) _ambient.repeat(reverse: true);
      }
    }
  }

  String _tr(BuildContext context, String key) => Tr.t(
    AppLanguage.fromCode(Localizations.localeOf(context).languageCode),
    key,
  );

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

    if (_reduceMotion) {
      _intro.value = 1;
    } else if (_intro.status == AnimationStatus.completed) {
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
      final sessionState = await AuthService.instance.validateSession().timeout(
        _startupHardTimeout,
      );
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

      final result = await resolveVerifiedRouteResult(
        validateSession: false,
      ).timeout(_startupHardTimeout);
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
        case VerifiedRouteKind.workspaceSelection:
          target = WorkspacePickerScreen(
            memberships: result.memberships,
            mandatory: true,
          );
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
      _showStartupFailure();
    } on FirebaseException catch (e) {
      debugPrint('[STARTUP_ROUTE] firebase_exception_non_fatal=true');
      debugPrint('[STARTUP_ROUTE] startup_error_type=${e.runtimeType}');
      if (!mounted) return;
      _slowTimer?.cancel();
      _statusRotator?.cancel();
      try {
        final result = await resolveVerifiedRouteResult(
          validateSession: false,
        ).timeout(_startupHardTimeout);
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
          case VerifiedRouteKind.workspaceSelection:
            target = WorkspacePickerScreen(
              memberships: result.memberships,
              mandatory: true,
            );
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
        _showStartupFailure();
      } catch (inner) {
        debugPrint('[STARTUP_ROUTE] startup_error_type=${inner.runtimeType}');
        _showStartupFailure();
      }
    } catch (e) {
      debugPrint('[STARTUP_ROUTE] startup_error_type=${e.runtimeType}');
      _showStartupFailure();
    }
  }

  void _showStartupFailure() {
    if (!mounted) return;
    _slowTimer?.cancel();
    _statusRotator?.cancel();
    setState(() {
      _startupFailed = true;
      _slowMode = false;
    });
  }

  void _scheduleStartupNavigation(Widget target) {
    if (_navigationCommitted || _navigationScheduled) return;
    if (!mounted) return;
    _resolvedTarget = target;
    _navigationScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _navigateToResolvedTarget();
    });
  }

  void _skipToResolvedTarget() => _navigateToResolvedTarget();

  void _navigateToResolvedTarget() {
    final target = _resolvedTarget;
    if (!mounted || _navigationCommitted || target == null) return;
    _navigationCommitted = true;
    Navigator.of(
      context,
      rootNavigator: true,
    ).pushReplacement(impactRoute(target));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF03070D),
      body: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _skipToResolvedTarget,
        child: Stack(
          fit: StackFit.expand,
          children: [
            WelcomeGalaxyBackground(reduceMotion: _reduceMotion),
            SafeArea(
              child: LayoutBuilder(
                builder: (context, constraints) => SingleChildScrollView(
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      minHeight: constraints.maxHeight,
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 28),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SizedBox(height: constraints.maxHeight * 0.12),
                          _buildBrandBlock(),
                          const SizedBox(height: 24),
                          _buildBottomBlock(),
                          const SizedBox(height: 22),
                          _buildFooter(),
                          const SizedBox(height: 20),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
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
                child: Text(
                  _greetingText(),
                  textAlign: TextAlign.center,
                  style: GoogleFonts.spaceGrotesk(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 25,
                    height: 1.16,
                    letterSpacing: -0.2,
                  ),
                ),
              ),
              const SizedBox(height: 10),
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

  String _greetingText() {
    final savedName = Session.instance.userName?.trim() ?? '';
    final firstName = savedName.isEmpty
        ? ''
        : savedName.split(RegExp(r'\s+')).first.trim();
    return firstName.isEmpty ? 'Welcome back' : 'Welcome back, $firstName';
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
            _tr(context, 'preparing_workspace'),
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
            _tr(context, 'securing_workspace'),
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
    if (_startupFailed) return _startupErrorState();
    return SizedBox(
      height: 48,
      child: Center(
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 260),
          child: _slowMode
              ? Text(
                  _tr(context, _slowLoadingStates[_statusIndex]),
                  key: ValueKey<int>(_statusIndex),
                  textAlign: TextAlign.center,
                  style: GoogleFonts.inter(
                    color: Colors.white.withValues(alpha: .68),
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    letterSpacing: .25,
                  ),
                )
              : _idleIndicator(),
        ),
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

  Widget _buildFooter() {
    return AnimatedBuilder(
      animation: _intro,
      builder: (context, _) {
        return Opacity(
          opacity: 0.55 * _footerOpacity.value,
          child: Text(
            _tr(context, 'workforce_wellness_intelligence'),
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
                      _tr(context, 'connection_slow'),
                      style: GoogleFonts.spaceGrotesk(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                        height: 1.25,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _tr(context, 'check_connection_retry'),
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
                _tr(context, 'try_again'),
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
                    ? _tr(context, 'use_another_account')
                    : _tr(context, 'go_to_login'),
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

class _ShimmerLine extends StatelessWidget {
  final AnimationController controller;
  final bool reduceMotion;

  const _ShimmerLine({required this.controller, required this.reduceMotion});

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

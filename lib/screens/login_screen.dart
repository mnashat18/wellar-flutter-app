import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/auth_service.dart';
import '../state/app_providers.dart';
import '../state/session.dart';
import '../utils/app_colors.dart';
import '../utils/app_feedback.dart';
import '../utils/page_transition.dart';
import '../widgets/google_mark.dart';
import 'forgot_password_screen.dart';
import 'register_screen.dart';
import 'splash_screen.dart';

const _authTeal = Color(0xFF12B892);
const _authTealDeep = Color(0xFF0B7A63);

class LoginScreen extends ConsumerStatefulWidget {
  final String? emailFromRegister;
  final String? inviteToken;
  final String? noticeMessage;

  const LoginScreen({
    super.key,
    this.emailFromRegister,
    this.inviteToken,
    this.noticeMessage,
  });

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen>
    with SingleTickerProviderStateMixin {
  late final TextEditingController emailController;
  late final TextEditingController passwordController;
  final _emailFocus = FocusNode();
  final _passwordFocus = FocusNode();
  bool _loading = false;
  bool _obscurePassword = true;
  bool _touchedEmail = false;
  bool _touchedPassword = false;
  bool _submitAttempted = false;
  String? _error;
  late final AnimationController _entranceController;
  late final Animation<double> _headerFade;
  late final Animation<Offset> _headerSlide;
  late final Animation<double> _fieldsFade;
  late final Animation<Offset> _fieldsSlide;
  late final Animation<double> _actionsFade;
  late final Animation<Offset> _actionsSlide;
  late final Animation<double> _reducedFade;
  bool _reduceMotion = false;
  bool _motionPreferenceRead = false;

  @override
  void initState() {
    super.initState();
    _entranceController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _headerFade = _fadeInterval(const Interval(0, 0.46, curve: Curves.easeOut));
    _headerSlide = _slideInterval(
      const Interval(0, 0.46, curve: Curves.easeOutCubic),
    );
    _fieldsFade = _fadeInterval(
      const Interval(0.17, 0.70, curve: Curves.easeOut),
    );
    _fieldsSlide = _slideInterval(
      const Interval(0.17, 0.70, curve: Curves.easeOutCubic),
    );
    _actionsFade = _fadeInterval(
      const Interval(0.34, 0.84, curve: Curves.easeOut),
    );
    _actionsSlide = _slideInterval(
      const Interval(0.34, 0.84, curve: Curves.easeOutCubic),
    );
    _reducedFade = Tween<double>(begin: 0.01, end: 1).animate(
      CurvedAnimation(parent: _entranceController, curve: Curves.easeOut),
    );
    emailController = TextEditingController(
      text: widget.emailFromRegister ?? '',
    );
    passwordController = TextEditingController();
    final token = widget.inviteToken?.trim();
    if (token != null && token.isNotEmpty) {
      Session.instance.setPendingInviteToken(token);
    }
    _emailFocus.addListener(
      () => setState(
        () => _touchedEmail = _touchedEmail || !_emailFocus.hasFocus,
      ),
    );
    _passwordFocus.addListener(
      () => setState(
        () => _touchedPassword = _touchedPassword || !_passwordFocus.hasFocus,
      ),
    );
  }

  Animation<double> _fadeInterval(Interval interval) => Tween<double>(
    begin: 0.01,
    end: 1,
  ).animate(CurvedAnimation(parent: _entranceController, curve: interval));

  Animation<Offset> _slideInterval(Interval interval) => Tween<Offset>(
    begin: const Offset(0, 0.035),
    end: Offset.zero,
  ).animate(CurvedAnimation(parent: _entranceController, curve: interval));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final shouldReduceMotion = MediaQuery.of(context).disableAnimations;
    if (_motionPreferenceRead && shouldReduceMotion == _reduceMotion) return;
    _motionPreferenceRead = true;
    _reduceMotion = shouldReduceMotion;
    _entranceController.stop();
    _entranceController.duration = shouldReduceMotion
        ? const Duration(milliseconds: 170)
        : const Duration(milliseconds: 900);
    _entranceController.forward(from: 0);
  }

  @override
  void dispose() {
    emailController.dispose();
    passwordController.dispose();
    _emailFocus.dispose();
    _passwordFocus.dispose();
    _entranceController.dispose();
    super.dispose();
  }

  Widget _reveal(
    Widget child, {
    required Animation<double> opacity,
    required Animation<Offset> slide,
  }) {
    return FadeTransition(
      opacity: _reduceMotion ? _reducedFade : opacity,
      child: SlideTransition(
        position: _reduceMotion
            ? const AlwaysStoppedAnimation<Offset>(Offset.zero)
            : slide,
        child: child,
      ),
    );
  }

  bool get _isEmailValid {
    final email = emailController.text.trim();
    if (email.isEmpty) return false;
    return RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email);
  }

  bool get _isPasswordValid => passwordController.text.isNotEmpty;

  Future<void> _login() async {
    setState(() {
      _submitAttempted = true;
      _touchedEmail = true;
      _touchedPassword = true;
    });
    if (!_isEmailValid) {
      setState(() => _error = 'Enter a valid work email address.');
      return;
    }
    if (!_isPasswordValid) {
      setState(() => _error = 'Enter your password to continue.');
      return;
    }
    if (ref.read(connectivityStatusProvider).asData?.value == false) {
      AppFeedback.showOffline(context);
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await AuthService.instance.login(
        email: emailController.text.trim(),
        password: passwordController.text,
      );
      if (!mounted) return;
      await _advanceAfterAuthentication();
    } catch (e) {
      if (!mounted) return;
      if (ref.read(connectivityStatusProvider).asData?.value == false) {
        AppFeedback.showOffline(context);
        return;
      }
      setState(() => _error = _friendlyLoginError(e.toString()));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _advanceAfterAuthentication() async {
    if (!mounted) return;
    debugPrint('[AUTH_DEBUG] post_auth_route_start=true');
    Navigator.pushReplacement(context, fadeSlideRoute(const SplashScreen()));
  }

  Future<void> _onGoogleTap(dynamic lang) async {
    if (ref.read(connectivityStatusProvider).asData?.value == false) {
      AppFeedback.showOffline(context);
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await AuthService.instance.loginWithGoogle();
      if (!mounted) return;
      await _advanceAfterAuthentication();
    } on AuthFlowException catch (e) {
      if (!mounted) return;
      if (ref.read(connectivityStatusProvider).asData?.value == false) {
        AppFeedback.showOffline(context);
        return;
      }
      setState(() => _error = _friendlyGoogleError(e));
    } catch (e) {
      if (!mounted) return;
      if (ref.read(connectivityStatusProvider).asData?.value == false) {
        AppFeedback.showOffline(context);
        return;
      }
      setState(() => _error = _friendlyLoginError(e.toString()));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final lang = ref.watch(appLanguageControllerProvider).language;
    final hasInvite =
        widget.inviteToken != null && widget.inviteToken!.trim().isNotEmpty;
    final showEmailError =
        (_touchedEmail || _submitAttempted) && !_isEmailValid;
    final showPassError =
        (_touchedPassword || _submitAttempted) && !_isPasswordValid;

    return Scaffold(
      backgroundColor: const Color(0xFF04060F),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF0A2424), Color(0xFF081521), Color(0xFF04060F)],
            stops: [0, 0.48, 1],
          ),
        ),
        child: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              return AutofillGroup(
                child: SingleChildScrollView(
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
                  padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      minHeight: (constraints.maxHeight - 34)
                          .clamp(0.0, double.infinity)
                          .toDouble(),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _reveal(
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  IconButton(
                                    tooltip: 'Back',
                                    icon: const Icon(
                                      Icons.arrow_back_rounded,
                                      color: Colors.white,
                                    ),
                                    onPressed: () =>
                                        Navigator.maybePop(context),
                                  ),
                                  const SizedBox(width: 8),
                                  const Text(
                                    'Wisebase',
                                    style: TextStyle(
                                      color: _authTeal,
                                      fontWeight: FontWeight.w800,
                                      fontSize: 14,
                                      letterSpacing: 0.35,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 10),
                              const Text(
                                'Welcome back',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w800,
                                  fontSize: 31,
                                  height: 1.08,
                                  letterSpacing: -0.45,
                                ),
                              ),
                              const SizedBox(height: 8),
                              const Text(
                                'Sign in to continue to your organization\'s workforce operations.',
                                style: TextStyle(
                                  color: AppColors.textSecondary,
                                  fontSize: 13.8,
                                  height: 1.5,
                                ),
                              ),
                              if (widget.noticeMessage != null) ...[
                                const SizedBox(height: 14),
                                _NoticeBanner(
                                  text: widget.noticeMessage!,
                                  tone: _NoticeTone.info,
                                ),
                              ],
                              if (hasInvite) ...[
                                const SizedBox(height: 14),
                                const _NoticeBanner(
                                  text:
                                      'Invite detected. Use your work account to continue.',
                                  tone: _NoticeTone.info,
                                ),
                              ],
                            ],
                          ),
                          opacity: _headerFade,
                          slide: _headerSlide,
                        ),
                        const SizedBox(height: 16),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
                          decoration: BoxDecoration(
                            color: const Color(0xFF0B1320),
                            borderRadius: BorderRadius.circular(24),
                            border: Border.all(color: const Color(0xFF243247)),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (_error != null) ...[
                                _NoticeBanner(
                                  text: _error!,
                                  tone: _isCancellationFeedback(_error!)
                                      ? _NoticeTone.info
                                      : _NoticeTone.error,
                                ),
                                const SizedBox(height: 14),
                              ],
                              _reveal(
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const _FieldLabel(text: 'Work email'),
                                    const SizedBox(height: 8),
                                    _authField(
                                      controller: emailController,
                                      focusNode: _emailFocus,
                                      keyboardType: TextInputType.emailAddress,
                                      textInputAction: TextInputAction.next,
                                      hint: 'name@company.com',
                                      autofillHints: const [
                                        AutofillHints.email,
                                      ],
                                      icon: Icons.alternate_email_rounded,
                                      errorText: showEmailError
                                          ? 'Enter a valid work email address.'
                                          : null,
                                    ),
                                    const SizedBox(height: 12),
                                    const _FieldLabel(text: 'Password'),
                                    const SizedBox(height: 8),
                                    _authField(
                                      controller: passwordController,
                                      focusNode: _passwordFocus,
                                      textInputAction: TextInputAction.done,
                                      hint: 'Enter your password',
                                      autofillHints: const [
                                        AutofillHints.password,
                                      ],
                                      icon: Icons.lock_outline_rounded,
                                      obscureText: _obscurePassword,
                                      errorText: showPassError
                                          ? 'Enter your password to continue.'
                                          : null,
                                      suffix: IconButton(
                                        style: IconButton.styleFrom(
                                          foregroundColor: _authTeal,
                                          overlayColor: _authTeal.withValues(
                                            alpha: .14,
                                          ),
                                        ),
                                        tooltip: _obscurePassword
                                            ? 'Show password'
                                            : 'Hide password',
                                        onPressed: () => setState(
                                          () => _obscurePassword =
                                              !_obscurePassword,
                                        ),
                                        icon: Icon(
                                          _obscurePassword
                                              ? Icons.visibility_outlined
                                              : Icons.visibility_off_outlined,
                                          color: AppColors.textSecondary,
                                        ),
                                      ),
                                      onSubmitted: (_) {
                                        if (!_loading) _login();
                                      },
                                    ),
                                    const SizedBox(height: 8),
                                    Align(
                                      alignment: Alignment.centerLeft,
                                      child: TextButton(
                                        onPressed: () async {
                                          final email =
                                              await Navigator.push<String>(
                                                context,
                                                fadeSlideRoute(
                                                  ForgotPasswordScreen(
                                                    initialEmail:
                                                        emailController.text
                                                            .trim(),
                                                  ),
                                                ),
                                              );
                                          if (email != null && mounted) {
                                            emailController.text = email;
                                          }
                                        },
                                        style: TextButton.styleFrom(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 0,
                                            vertical: 2,
                                          ),
                                          tapTargetSize:
                                              MaterialTapTargetSize.shrinkWrap,
                                          foregroundColor:
                                              AppColors.textSecondary,
                                        ),
                                        child: const Text(
                                          'Forgot password?',
                                          style: TextStyle(
                                            fontWeight: FontWeight.w700,
                                            fontSize: 12.5,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                opacity: _fieldsFade,
                                slide: _fieldsSlide,
                              ),
                              const SizedBox(height: 16),
                              _reveal(
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    _ActionButton.primary(
                                      text: _loading
                                          ? 'Signing in...'
                                          : 'Sign in',
                                      onPressed: _loading ? null : _login,
                                      isLoading: _loading,
                                    ),
                                    const SizedBox(height: 10),
                                    _GoogleActionButton(
                                      text: 'Continue with Google',
                                      isLoading: _loading,
                                      onPressed: _loading
                                          ? null
                                          : () => _onGoogleTap(lang),
                                    ),
                                    const SizedBox(height: 10),
                                    Align(
                                      alignment: Alignment.centerLeft,
                                      child: TextButton(
                                        onPressed: () => Navigator.push(
                                          context,
                                          fadeSlideRoute(
                                            RegisterScreen(
                                              inviteToken: widget.inviteToken,
                                            ),
                                          ),
                                        ),
                                        style: TextButton.styleFrom(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 0,
                                            vertical: 6,
                                          ),
                                          tapTargetSize:
                                              MaterialTapTargetSize.shrinkWrap,
                                          foregroundColor: _authTeal,
                                          overlayColor: _authTeal.withValues(
                                            alpha: 0.12,
                                          ),
                                        ),
                                        child: const Text(
                                          'Create account',
                                          style: TextStyle(
                                            fontWeight: FontWeight.w700,
                                            fontSize: 13.5,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                opacity: _actionsFade,
                                slide: _actionsSlide,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _authField({
    required TextEditingController controller,
    required FocusNode focusNode,
    required String hint,
    required IconData icon,
    TextInputType keyboardType = TextInputType.text,
    TextInputAction textInputAction = TextInputAction.next,
    bool obscureText = false,
    Iterable<String>? autofillHints,
    Widget? suffix,
    String? errorText,
    void Function(String)? onSubmitted,
  }) {
    return AnimatedBuilder(
      animation: focusNode,
      builder: (context, _) => AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          boxShadow: focusNode.hasFocus && errorText == null
              ? [
                  BoxShadow(
                    color: _authTeal.withValues(alpha: 0.20),
                    blurRadius: 16,
                    spreadRadius: 1,
                  ),
                ]
              : const [],
        ),
        child: TextField(
          controller: controller,
          focusNode: focusNode,
          keyboardType: keyboardType,
          textInputAction: textInputAction,
          obscureText: obscureText,
          autofillHints: autofillHints,
          autocorrect: false,
          enableSuggestions: !obscureText,
          onChanged: (_) => setState(() => _error = null),
          onSubmitted: onSubmitted,
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: const TextStyle(color: AppColors.textSecondary),
            errorText: errorText,
            errorMaxLines: 2,
            filled: true,
            fillColor: const Color(0xFF0A111D),
            prefixIcon: Icon(icon, color: AppColors.textSecondary),
            suffixIcon: suffix,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 14,
              vertical: 15,
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: Color(0xFF2A384E)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: _authTeal, width: 1.4),
            ),
            errorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: AppColors.highRisk),
            ),
            focusedErrorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: AppColors.highRisk),
            ),
          ),
        ),
      ),
    );
  }

  bool _isCancellationFeedback(String message) {
    final lower = message.toLowerCase();
    return lower.contains('cancelled') || lower.contains('canceled');
  }

  String _friendlyLoginError(String raw) {
    final v = raw.toLowerCase();
    if (v.contains('invalid') ||
        v.contains('password') ||
        v.contains('credentials') ||
        v.contains('unauthorized')) {
      return 'Invalid email or password.';
    }
    if (v.contains('expired') || v.contains('session')) {
      return 'Your session expired. Sign in again to continue.';
    }
    if (v.contains('network') ||
        v.contains('connection') ||
        v.contains('socket') ||
        v.contains('host lookup')) {
      return 'Could not connect to Wisebase right now. Check your connection.';
    }
    if (v.contains('timeout') || v.contains('too long')) {
      return 'Server took too long. Try again.';
    }
    return 'Sign in could not be completed. Try again.';
  }

  String _friendlyGoogleError(AuthFlowException e) {
    switch (e.code) {
      case AuthFlowError.googleCancelled:
        return 'Google sign-in was cancelled.';
      case AuthFlowError.googleNoIdToken:
        return 'Google sign-in could not be completed. Try again.';
      case AuthFlowError.networkIssue:
        return 'We could not reach the server. Try again.';
      case AuthFlowError.googleExchangeMissing:
        return 'Google sign-in is unavailable right now. Try again later.';
      case AuthFlowError.googleConfigMissing:
        return 'Google sign-in is unavailable right now. Try again later.';
      case AuthFlowError.noWorkspaceSession:
        return 'Sign in could not be completed. Try again.';
      case AuthFlowError.noMembership:
        return 'No active workspace was found for this account.';
      case AuthFlowError.invalidSession:
        return 'Your session expired. Sign in again to continue.';
    }
  }
}

class _FieldLabel extends StatelessWidget {
  final String text;

  const _FieldLabel({required this.text});

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        color: Colors.white,
        fontSize: 12,
        fontWeight: FontWeight.w800,
        letterSpacing: 0.2,
      ),
    );
  }
}

class _ActionButton extends StatefulWidget {
  final String text;
  final VoidCallback? onPressed;
  final bool isLoading;

  const _ActionButton.primary({
    required this.text,
    required this.onPressed,
    this.isLoading = false,
  });

  @override
  State<_ActionButton> createState() => _ActionButtonState();
}

class _ActionButtonState extends State<_ActionButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: AnimatedScale(
        scale: _pressed && widget.onPressed != null ? .97 : 1,
        duration: Duration(milliseconds: _pressed ? 90 : 220),
        curve: _pressed ? Curves.easeOut : Curves.easeOutBack,
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: widget.onPressed == null
                ? null
                : const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [_authTeal, _authTealDeep],
                  ),
            color: widget.onPressed == null ? const Color(0xFF33404A) : null,
            borderRadius: BorderRadius.circular(16),
            boxShadow: widget.onPressed == null
                ? const []
                : [
                    BoxShadow(
                      color: _authTeal.withValues(alpha: .22),
                      blurRadius: 18,
                      offset: const Offset(0, 8),
                    ),
                  ],
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(16),
              splashColor: Colors.white.withValues(alpha: .14),
              highlightColor: Colors.white.withValues(alpha: .06),
              onTap: widget.onPressed,
              onTapDown: widget.onPressed == null
                  ? null
                  : (_) => setState(() => _pressed = true),
              onTapCancel: () => setState(() => _pressed = false),
              onTapUp: (_) => setState(() => _pressed = false),
              child: Center(
                child: widget.isLoading
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.2,
                          color: Colors.white,
                        ),
                      )
                    : Text(
                        widget.text,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                        ),
                      ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _GoogleActionButton extends StatelessWidget {
  final String text;
  final VoidCallback? onPressed;
  final bool isLoading;

  const _GoogleActionButton({
    required this.text,
    required this.onPressed,
    required this.isLoading,
  });

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null && !isLoading;
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: OutlinedButton(
        onPressed: enabled ? onPressed : null,
        style: OutlinedButton.styleFrom(
          foregroundColor: Colors.white,
          side: const BorderSide(color: Color(0xFF314056)),
          backgroundColor: const Color(0xFF0A111D),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 14),
        ),
        child: Stack(
          alignment: Alignment.center,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(9),
                      ),
                      child: const Center(child: GoogleMark(size: 16)),
                    ),
                    const SizedBox(width: 10),
                    const SizedBox(width: 16),
                  ],
                ),
                SizedBox(
                  width: 16,
                  height: 16,
                  child: isLoading
                      ? const CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        )
                      : const SizedBox.shrink(),
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 44),
              child: Text(
                text,
                style: const TextStyle(
                  fontSize: 14.5,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.1,
                ),
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NoticeBanner extends StatelessWidget {
  final String text;
  final _NoticeTone tone;

  const _NoticeBanner({required this.text, required this.tone});

  @override
  Widget build(BuildContext context) {
    final isError = tone == _NoticeTone.error;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: isError ? const Color(0xFF2A1420) : const Color(0xFF102033),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isError ? const Color(0xFF8F3A53) : const Color(0xFF2C4A68),
        ),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: isError ? const Color(0xFFFFD0D8) : const Color(0xFFD9EEF8),
          fontSize: 12.5,
          fontWeight: FontWeight.w600,
          height: 1.35,
        ),
      ),
    );
  }
}

enum _NoticeTone { info, error }

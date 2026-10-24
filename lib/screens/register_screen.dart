import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../config/app_config.dart';
import '../i18n/tr.dart';
import '../services/auth_service.dart';
import '../state/app_providers.dart';
import '../state/session.dart';
import '../utils/app_colors.dart';
import '../utils/app_feedback.dart';
import '../utils/page_transition.dart';
import 'login_screen.dart';
import 'splash_screen.dart';

const _authTeal = Color(0xFF12B892);
const _authTealDeep = Color(0xFF0B7A63);

class RegisterScreen extends ConsumerStatefulWidget {
  final String? inviteToken;

  const RegisterScreen({super.key, this.inviteToken});

  @override
  ConsumerState<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends ConsumerState<RegisterScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _entranceController;
  late final Animation<double> _headerFade;
  late final Animation<Offset> _headerSlide;
  late final Animation<double> _fieldsFade;
  late final Animation<Offset> _fieldsSlide;
  late final Animation<double> _actionsFade;
  late final Animation<Offset> _actionsSlide;
  late final Animation<double> _reducedFade;
  bool _reducedMotion = false;
  bool _motionInitialized = false;
  final firstNameController = TextEditingController();
  final lastNameController = TextEditingController();
  final emailController = TextEditingController();
  final passwordController = TextEditingController();
  final confirmPasswordController = TextEditingController();

  final _firstNameFocus = FocusNode();
  final _lastNameFocus = FocusNode();
  final _emailFocus = FocusNode();
  final _passwordFocus = FocusNode();
  final _confirmPasswordFocus = FocusNode();

  bool _loading = false;
  bool _obscurePass = true;
  bool _obscureConfirmPass = true;
  bool _submitAttempted = false;
  bool _touchedFirstName = false;
  bool _touchedLastName = false;
  bool _touchedEmail = false;
  bool _touchedPassword = false;
  bool _touchedConfirmPassword = false;
  bool _acceptedLegal = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _entranceController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _headerFade = _entranceController
        .drive(CurveTween(curve: const Interval(0, .48, curve: Curves.easeOut)))
        .drive(Tween(begin: .01, end: 1));
    _headerSlide = _entranceController
        .drive(
          CurveTween(curve: const Interval(0, .48, curve: Curves.easeOutCubic)),
        )
        .drive(Tween(begin: const Offset(0, .035), end: Offset.zero));
    _fieldsFade = _entranceController
        .drive(
          CurveTween(curve: const Interval(.18, .72, curve: Curves.easeOut)),
        )
        .drive(Tween(begin: .01, end: 1));
    _fieldsSlide = _entranceController
        .drive(
          CurveTween(
            curve: const Interval(.18, .72, curve: Curves.easeOutCubic),
          ),
        )
        .drive(Tween(begin: const Offset(0, .035), end: Offset.zero));
    _actionsFade = _entranceController
        .drive(CurveTween(curve: const Interval(.42, 1, curve: Curves.easeOut)))
        .drive(Tween(begin: .01, end: 1));
    _actionsSlide = _entranceController
        .drive(
          CurveTween(curve: const Interval(.42, 1, curve: Curves.easeOutCubic)),
        )
        .drive(Tween(begin: const Offset(0, .035), end: Offset.zero));
    _reducedFade = _entranceController
        .drive(CurveTween(curve: Curves.easeOut))
        .drive(Tween(begin: .01, end: 1));
    final token = widget.inviteToken?.trim();
    if (token != null && token.isNotEmpty) {
      Session.instance.setPendingInviteToken(token);
    }
    _firstNameFocus.addListener(() {
      if (!_firstNameFocus.hasFocus) setState(() => _touchedFirstName = true);
    });
    _lastNameFocus.addListener(() {
      if (!_lastNameFocus.hasFocus) setState(() => _touchedLastName = true);
    });
    _emailFocus.addListener(() {
      if (!_emailFocus.hasFocus) setState(() => _touchedEmail = true);
    });
    _passwordFocus.addListener(() {
      if (!_passwordFocus.hasFocus) setState(() => _touchedPassword = true);
    });
    _confirmPasswordFocus.addListener(() {
      if (!_confirmPasswordFocus.hasFocus) {
        setState(() => _touchedConfirmPassword = true);
      }
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduce = MediaQuery.disableAnimationsOf(context);
    if (!_motionInitialized || reduce != _reducedMotion) {
      _motionInitialized = true;
      _reducedMotion = reduce;
      _entranceController
        ..stop()
        ..duration = Duration(milliseconds: reduce ? 170 : 900)
        ..forward(from: 0);
    }
  }

  Widget _reveal(
    Widget child, {
    required Animation<double> opacity,
    required Animation<Offset> slide,
  }) => FadeTransition(
    opacity: _reducedMotion ? _reducedFade : opacity,
    child: SlideTransition(
      position: _reducedMotion
          ? const AlwaysStoppedAnimation(Offset.zero)
          : slide,
      child: child,
    ),
  );

  @override
  void dispose() {
    _entranceController.dispose();
    firstNameController.dispose();
    lastNameController.dispose();
    emailController.dispose();
    passwordController.dispose();
    confirmPasswordController.dispose();
    _firstNameFocus.dispose();
    _lastNameFocus.dispose();
    _emailFocus.dispose();
    _passwordFocus.dispose();
    _confirmPasswordFocus.dispose();
    super.dispose();
  }

  bool get _isEmailValid {
    final email = emailController.text.trim();
    if (email.isEmpty) return false;
    return RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email);
  }

  bool get _isPasswordValid {
    final value = passwordController.text;
    if (value.length < 10 || value.length > 128) return false;
    if (!RegExp(r'[A-Za-z]').hasMatch(value)) return false;
    if (!RegExp(r'\d').hasMatch(value)) return false;
    return true;
  }

  bool get _isConfirmPasswordValid =>
      confirmPasswordController.text.isNotEmpty &&
      confirmPasswordController.text == passwordController.text;

  Uri _legalUri(String path) {
    final base = AppConfig.publicWebBaseUrl.replaceFirst(RegExp(r'/+$'), '');
    return Uri.parse('$base$path');
  }

  Future<void> _openLegalPage(String path) async {
    try {
      if (await launchUrl(_legalUri(path))) return;
    } catch (_) {
      // Show the same feedback as a false launch result.
    }
    if (!mounted) return;
    final lang = ref.read(appLanguageControllerProvider).language;
    AppFeedback.showError(
      context,
      lang.isRtl
          ? 'تعذّر فتح هذه الصفحة. حاول مرة أخرى.'
          : 'Could not open this page. Please try again.',
    );
  }

  Future<void> _register() async {
    setState(() {
      _submitAttempted = true;
      _touchedFirstName = true;
      _touchedLastName = true;
      _touchedEmail = true;
      _touchedPassword = true;
      _touchedConfirmPassword = true;
    });

    if (firstNameController.text.trim().isEmpty ||
        lastNameController.text.trim().isEmpty) {
      setState(() => _error = 'Enter your first and last name.');
      return;
    }
    if (!_isEmailValid) {
      setState(() => _error = 'Enter a valid email address.');
      return;
    }
    if (!_isPasswordValid) {
      setState(
        () => _error =
            'Use 10 to 128 characters with at least one letter and one number.',
      );
      return;
    }
    if (!_isConfirmPasswordValid) {
      setState(() => _error = 'Confirm password must exactly match password.');
      return;
    }
    if (!_acceptedLegal) {
      setState(
        () => _error = 'Accept the Terms and Privacy Policy to continue.',
      );
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
      final sessionCreated = await AuthService.instance.register(
        email: emailController.text.trim(),
        password: passwordController.text,
        firstName: firstNameController.text.trim(),
        lastName: lastNameController.text.trim(),
      );
      if (!mounted) return;
      if (sessionCreated) {
        await _advanceAfterAuthentication();
        return;
      }
      Navigator.pushReplacement(
        context,
        fadeSlideRoute(
          LoginScreen(
            emailFromRegister: emailController.text.trim(),
            inviteToken: widget.inviteToken,
            noticeMessage: 'Account created. Sign in to continue.',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      if (ref.read(connectivityStatusProvider).asData?.value == false) {
        AppFeedback.showOffline(context);
        return;
      }
      final message = e.toString();
      if (_isDuplicateEmailError(message)) {
        setState(() => _error = 'Account already exists.');
        return;
      }
      setState(() => _error = _friendlySignupError(message));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _advanceAfterAuthentication() async {
    if (!mounted) return;
    debugPrint('[AUTH_DEBUG] post_auth_route_start=true');
    Navigator.pushReplacement(context, fadeSlideRoute(const SplashScreen()));
  }

  bool _isDuplicateEmailError(String raw) {
    final lower = raw.toLowerCase();
    return lower.contains('already') ||
        lower.contains('duplicate') ||
        lower.contains('409') ||
        lower.contains('exists');
  }

  String _friendlySignupError(String raw) {
    final lower = raw.toLowerCase();
    if (_isDuplicateEmailError(raw)) {
      return 'Account already exists.';
    }
    if (lower.contains('timeout') || lower.contains('too long')) {
      return 'Server took too long. Try again.';
    }
    if (lower.contains('network') ||
        lower.contains('connection') ||
        lower.contains('socket') ||
        lower.contains('host lookup')) {
      return 'Could not connect to Wisebase right now. Check your connection.';
    }
    return 'Account creation could not be completed. Try again.';
  }

  @override
  Widget build(BuildContext context) {
    final lang = ref.watch(appLanguageControllerProvider).language;
    final hasInvite =
        widget.inviteToken != null && widget.inviteToken!.trim().isNotEmpty;

    final hasRequiredNames =
        firstNameController.text.trim().isNotEmpty &&
        lastNameController.text.trim().isNotEmpty;
    final canSubmit =
        hasRequiredNames &&
        _isEmailValid &&
        _isPasswordValid &&
        _isConfirmPasswordValid &&
        _acceptedLegal;
    final showFirstNameError =
        (_submitAttempted || _touchedFirstName) &&
        firstNameController.text.trim().isEmpty;
    final showLastNameError =
        (_submitAttempted || _touchedLastName) &&
        lastNameController.text.trim().isEmpty;
    final showEmailError =
        (_submitAttempted || _touchedEmail) && !_isEmailValid;
    final showPasswordError =
        (_submitAttempted || _touchedPassword) && !_isPasswordValid;
    final showConfirmPasswordError =
        (_submitAttempted || _touchedConfirmPassword) &&
        !_isConfirmPasswordValid;

    return Scaffold(
      backgroundColor: const Color(0xFF04060F),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF0A2424), Color(0xFF081521), Color(0xFF04060F)],
            stops: [0, .48, 1],
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
                                    tooltip: Tr.t(lang, 'home'),
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
                              Text(
                                hasInvite
                                    ? 'Create your account to join your organization'
                                    : 'Start your organization',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w800,
                                  fontSize: 31,
                                  height: 1.08,
                                  letterSpacing: -0.45,
                                ),
                              ),
                              const SizedBox(height: 8),
                              const Text(
                                'Create your account to begin managed activation for your organization.',
                                style: TextStyle(
                                  color: AppColors.textSecondary,
                                  fontSize: 13.8,
                                  height: 1.5,
                                ),
                              ),
                              if (hasInvite) ...[
                                const SizedBox(height: 14),
                                const _InviteBanner(),
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
                                  tone: _NoticeTone.error,
                                ),
                                const SizedBox(height: 14),
                              ],
                              _reveal(
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    LayoutBuilder(
                                      builder: (context, fieldConstraints) {
                                        final isWide =
                                            fieldConstraints.maxWidth >= 520;
                                        if (isWide) {
                                          final fieldWidth =
                                              (fieldConstraints.maxWidth - 10) /
                                              2;
                                          return Row(
                                            children: [
                                              SizedBox(
                                                width: fieldWidth,
                                                child: _FieldColumn(
                                                  label: Tr.t(
                                                    lang,
                                                    'first_name',
                                                  ),
                                                  hint: Tr.t(
                                                    lang,
                                                    'first_name_hint',
                                                  ),
                                                  icon: Icons
                                                      .person_outline_rounded,
                                                  controller:
                                                      firstNameController,
                                                  focusNode: _firstNameFocus,
                                                  onChanged: (_) =>
                                                      setState(() {}),
                                                  textInputAction:
                                                      TextInputAction.next,
                                                  errorText: showFirstNameError
                                                      ? 'First name is required.'
                                                      : null,
                                                ),
                                              ),
                                              const SizedBox(width: 10),
                                              SizedBox(
                                                width: fieldWidth,
                                                child: _FieldColumn(
                                                  label: Tr.t(
                                                    lang,
                                                    'last_name',
                                                  ),
                                                  hint: Tr.t(
                                                    lang,
                                                    'last_name_hint',
                                                  ),
                                                  icon: Icons
                                                      .person_outline_rounded,
                                                  controller:
                                                      lastNameController,
                                                  focusNode: _lastNameFocus,
                                                  onChanged: (_) =>
                                                      setState(() {}),
                                                  textInputAction:
                                                      TextInputAction.next,
                                                  errorText: showLastNameError
                                                      ? 'Last name is required.'
                                                      : null,
                                                ),
                                              ),
                                            ],
                                          );
                                        }

                                        return Column(
                                          children: [
                                            _FieldColumn(
                                              label: Tr.t(lang, 'first_name'),
                                              hint: Tr.t(
                                                lang,
                                                'first_name_hint',
                                              ),
                                              icon:
                                                  Icons.person_outline_rounded,
                                              controller: firstNameController,
                                              focusNode: _firstNameFocus,
                                              onChanged: (_) => setState(() {}),
                                              textInputAction:
                                                  TextInputAction.next,
                                              errorText: showFirstNameError
                                                  ? 'First name is required.'
                                                  : null,
                                            ),
                                            const SizedBox(height: 12),
                                            _FieldColumn(
                                              label: Tr.t(lang, 'last_name'),
                                              hint: Tr.t(
                                                lang,
                                                'last_name_hint',
                                              ),
                                              icon:
                                                  Icons.person_outline_rounded,
                                              controller: lastNameController,
                                              focusNode: _lastNameFocus,
                                              onChanged: (_) => setState(() {}),
                                              textInputAction:
                                                  TextInputAction.next,
                                              errorText: showLastNameError
                                                  ? 'Last name is required.'
                                                  : null,
                                            ),
                                          ],
                                        );
                                      },
                                    ),
                                    const SizedBox(height: 12),
                                    _FieldColumn(
                                      label: Tr.t(lang, 'email'),
                                      hint: Tr.t(lang, 'email_hint'),
                                      icon: Icons.alternate_email_rounded,
                                      controller: emailController,
                                      focusNode: _emailFocus,
                                      onChanged: (_) => setState(() {}),
                                      keyboardType: TextInputType.emailAddress,
                                      autofillHints: const [
                                        AutofillHints.email,
                                      ],
                                      textInputAction: TextInputAction.next,
                                      errorText: showEmailError
                                          ? 'Enter a valid email address.'
                                          : null,
                                    ),
                                    const SizedBox(height: 12),
                                    _FieldColumn(
                                      label: Tr.t(lang, 'password'),
                                      hint: Tr.t(lang, 'password_hint'),
                                      icon: Icons.lock_outline_rounded,
                                      controller: passwordController,
                                      focusNode: _passwordFocus,
                                      onChanged: (_) => setState(() {}),
                                      obscureText: _obscurePass,
                                      keyboardType:
                                          TextInputType.visiblePassword,
                                      autofillHints: const [
                                        AutofillHints.newPassword,
                                      ],
                                      textInputAction: TextInputAction.done,
                                      onSubmitted: (_) {
                                        if (!_loading) _register();
                                      },
                                      suffix: IconButton(
                                        style: IconButton.styleFrom(
                                          foregroundColor: _authTeal,
                                          overlayColor: _authTeal.withValues(
                                            alpha: .14,
                                          ),
                                        ),
                                        tooltip: _obscurePass
                                            ? 'Show password'
                                            : 'Hide password',
                                        onPressed: () => setState(
                                          () => _obscurePass = !_obscurePass,
                                        ),
                                        icon: Icon(
                                          _obscurePass
                                              ? Icons.visibility_outlined
                                              : Icons.visibility_off_outlined,
                                          color: AppColors.textSecondary,
                                        ),
                                      ),
                                      errorText: showPasswordError
                                          ? 'Use 10 to 128 characters with at least one letter and one number.'
                                          : null,
                                    ),
                                    const SizedBox(height: 12),
                                    _FieldColumn(
                                      label: 'Confirm password',
                                      hint: 'Re-enter your password',
                                      icon: Icons.lock_outline_rounded,
                                      controller: confirmPasswordController,
                                      focusNode: _confirmPasswordFocus,
                                      onChanged: (_) => setState(() {}),
                                      obscureText: _obscureConfirmPass,
                                      keyboardType:
                                          TextInputType.visiblePassword,
                                      autofillHints: const [
                                        AutofillHints.newPassword,
                                      ],
                                      textInputAction: TextInputAction.done,
                                      onSubmitted: (_) {
                                        if (!_loading) _register();
                                      },
                                      suffix: IconButton(
                                        style: IconButton.styleFrom(
                                          foregroundColor: _authTeal,
                                          overlayColor: _authTeal.withValues(
                                            alpha: .14,
                                          ),
                                        ),
                                        tooltip: _obscureConfirmPass
                                            ? 'Show password'
                                            : 'Hide password',
                                        onPressed: () => setState(
                                          () => _obscureConfirmPass =
                                              !_obscureConfirmPass,
                                        ),
                                        icon: Icon(
                                          _obscureConfirmPass
                                              ? Icons.visibility_outlined
                                              : Icons.visibility_off_outlined,
                                          color: AppColors.textSecondary,
                                        ),
                                      ),
                                      errorText: showConfirmPasswordError
                                          ? 'Confirm password must exactly match password.'
                                          : null,
                                    ),
                                    const SizedBox(height: 14),
                                  ],
                                ),
                                opacity: _fieldsFade,
                                slide: _fieldsSlide,
                              ),
                              _reveal(
                                Column(
                                  children: [
                                    CheckboxListTile(
                                      value: _acceptedLegal,
                                      contentPadding: EdgeInsets.zero,
                                      controlAffinity:
                                          ListTileControlAffinity.leading,
                                      onChanged: (value) => setState(
                                        () => _acceptedLegal = value ?? false,
                                      ),
                                      title: Wrap(
                                        crossAxisAlignment:
                                            WrapCrossAlignment.center,
                                        children: [
                                          const Text(
                                            'I agree to the ',
                                            style: TextStyle(
                                              color: Colors.white,
                                              fontSize: 12.5,
                                            ),
                                          ),
                                          GestureDetector(
                                            onTap: () =>
                                                _openLegalPage('/terms'),
                                            child: const Text(
                                              'Terms',
                                              style: TextStyle(
                                                color: _authTeal,
                                                fontSize: 12.5,
                                                fontWeight: FontWeight.w700,
                                              ),
                                            ),
                                          ),
                                          const Text(
                                            ' and ',
                                            style: TextStyle(
                                              color: Colors.white,
                                              fontSize: 12.5,
                                            ),
                                          ),
                                          GestureDetector(
                                            onTap: () =>
                                                _openLegalPage('/privacy'),
                                            child: const Text(
                                              'Privacy Policy',
                                              style: TextStyle(
                                                color: _authTeal,
                                                fontSize: 12.5,
                                                fontWeight: FontWeight.w700,
                                              ),
                                            ),
                                          ),
                                          const Text(
                                            '.',
                                            style: TextStyle(
                                              color: Colors.white,
                                              fontSize: 12.5,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(height: 10),
                                    _ActionButton.primary(
                                      text: _loading
                                          ? (hasInvite
                                                ? 'Creating account and joining...'
                                                : 'Creating account...')
                                          : (hasInvite
                                                ? 'Create account and join organization'
                                                : 'Create account'),
                                      onPressed: (!_loading && canSubmit)
                                          ? _register
                                          : null,
                                      isLoading: _loading,
                                    ),
                                  ],
                                ),
                                opacity: _actionsFade,
                                slide: _actionsSlide,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 12),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: TextButton(
                            onPressed: () => Navigator.pushReplacement(
                              context,
                              fadeSlideRoute(
                                LoginScreen(
                                  emailFromRegister: emailController.text
                                      .trim(),
                                  inviteToken: widget.inviteToken,
                                ),
                              ),
                            ),
                            style: TextButton.styleFrom(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 0,
                                vertical: 6,
                              ),
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              foregroundColor: AppColors.primarySoft,
                            ),
                            child: const Text(
                              'Log in',
                              style: TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 13.5,
                              ),
                            ),
                          ),
                        ),
                        if (_isDuplicateEmailError(_error ?? ''))
                          Align(
                            alignment: Alignment.centerLeft,
                            child: TextButton(
                              onPressed: () => Navigator.pushReplacement(
                                context,
                                fadeSlideRoute(
                                  LoginScreen(
                                    emailFromRegister: emailController.text
                                        .trim(),
                                    inviteToken: widget.inviteToken,
                                  ),
                                ),
                              ),
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
}

class _FieldColumn extends StatelessWidget {
  final String label;
  final String hint;
  final IconData icon;
  final TextEditingController controller;
  final FocusNode focusNode;
  final TextInputType keyboardType;
  final TextInputAction textInputAction;
  final Iterable<String>? autofillHints;
  final bool obscureText;
  final Widget? suffix;
  final String? errorText;
  final void Function(String)? onSubmitted;
  final ValueChanged<String>? onChanged;

  const _FieldColumn({
    required this.label,
    required this.hint,
    required this.icon,
    required this.controller,
    required this.focusNode,
    this.keyboardType = TextInputType.text,
    this.textInputAction = TextInputAction.next,
    this.autofillHints,
    this.obscureText = false,
    this.suffix,
    this.errorText,
    this.onSubmitted,
    this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 12,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.2,
          ),
        ),
        const SizedBox(height: 8),
        AnimatedBuilder(
          animation: focusNode,
          builder: (context, _) => AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              boxShadow: focusNode.hasFocus
                  ? [
                      BoxShadow(
                        color: _authTeal.withValues(alpha: .16),
                        blurRadius: 14,
                        spreadRadius: 1,
                      ),
                    ]
                  : const [],
            ),
            child: TextField(
              controller: controller,
              focusNode: focusNode,
              keyboardType: keyboardType,
              autofillHints: autofillHints,
              textInputAction: textInputAction,
              obscureText: obscureText,
              autocorrect: false,
              enableSuggestions: !obscureText,
              onChanged: onChanged,
              onSubmitted: onSubmitted,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: hint,
                hintStyle: const TextStyle(color: AppColors.textSecondary),
                errorText: errorText,
                errorMaxLines: 2,
                prefixIcon: Icon(icon, color: AppColors.textSecondary),
                suffixIcon: suffix,
                filled: true,
                fillColor: const Color(0xFF0A111D),
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
        ),
      ],
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

class _InviteBanner extends StatelessWidget {
  const _InviteBanner();

  @override
  Widget build(BuildContext context) {
    return const _NoticeBanner(
      text: 'Invite detected. Use your work account to continue.',
      tone: _NoticeTone.info,
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

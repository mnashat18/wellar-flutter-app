import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/auth_service.dart';
import '../utils/app_colors.dart';
import '../utils/page_transition.dart';
import 'login_screen.dart';

class ForgotPasswordScreen extends ConsumerStatefulWidget {
  final String? initialEmail;

  const ForgotPasswordScreen({super.key, this.initialEmail});

  @override
  ConsumerState<ForgotPasswordScreen> createState() =>
      _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends ConsumerState<ForgotPasswordScreen> {
  late final TextEditingController _emailController;
  final FocusNode _emailFocus = FocusNode();
  bool _loading = false;
  bool _submitAttempted = false;
  bool _touchedEmail = false;
  bool _submitted = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _emailController = TextEditingController(text: widget.initialEmail ?? '');
    _emailFocus.addListener(() {
      if (!_emailFocus.hasFocus) {
        setState(() => _touchedEmail = true);
      }
    });
  }

  @override
  void dispose() {
    _emailController.dispose();
    _emailFocus.dispose();
    super.dispose();
  }

  bool get _isEmailValid {
    final email = _emailController.text.trim();
    if (email.isEmpty) return false;
    return RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email);
  }

  Future<void> _submit() async {
    setState(() {
      _submitAttempted = true;
      _touchedEmail = true;
      _error = null;
    });
    if (!_isEmailValid) {
      setState(() => _error = 'Enter a valid email address.');
      return;
    }

    setState(() => _loading = true);
    try {
      final result = await AuthService.instance.requestPasswordReset(
        email: _emailController.text.trim(),
      );
      if (!mounted) return;
      setState(() {
        if (result == PasswordResetRequestResult.success) {
          _submitted = true;
        } else {
          _error = 'We could not send a reset link right now. Try again.';
        }
      });
    } catch (_) {
      if (!mounted) return;
      setState(
        () => _error = 'We could not send a reset link right now. Try again.',
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final showEmailError = (_submitAttempted || _touchedEmail) && !_isEmailValid;
    return Scaffold(
      backgroundColor: const Color(0xFF050A12),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              IconButton(
                tooltip: 'Back',
                icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
                onPressed: () => Navigator.pushReplacement(
                  context,
                  fadeSlideRoute(
                    LoginScreen(emailFromRegister: _emailController.text.trim()),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              const Text(
                'Forgot password',
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
                'Enter your email address and we will send a password reset link if the account exists.',
                style: TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 13.8,
                  height: 1.5,
                ),
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
                    if (_submitted) ...[
                      const _NoticeBanner(
                        text:
                            'If an account exists for this email, you will receive a reset link shortly.',
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        'Open the reset link in your email, set a new password in the trusted reset page, then return here to sign in.',
                        style: TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 12.8,
                          height: 1.45,
                        ),
                      ),
                      const SizedBox(height: 16),
                      _PrimaryButton(
                        text: 'Back to sign in',
                        onPressed: () => Navigator.pushReplacement(
                          context,
                          fadeSlideRoute(
                            LoginScreen(
                              emailFromRegister: _emailController.text.trim(),
                            ),
                          ),
                        ),
                      ),
                    ] else ...[
                      if (_error != null) ...[
                        _ErrorBanner(text: _error!),
                        const SizedBox(height: 14),
                      ],
                      const _FieldLabel(text: 'Email'),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _emailController,
                        focusNode: _emailFocus,
                        keyboardType: TextInputType.emailAddress,
                        textInputAction: TextInputAction.done,
                        onChanged: (_) => setState(() => _error = null),
                        onSubmitted: (_) {
                          if (!_loading) _submit();
                        },
                        style: const TextStyle(color: Colors.white),
                        decoration: InputDecoration(
                          hintText: 'name@company.com',
                          hintStyle:
                              const TextStyle(color: AppColors.textSecondary),
                          errorText:
                              showEmailError ? 'Enter a valid email address.' : null,
                          filled: true,
                          fillColor: const Color(0xFF0A111D),
                          prefixIcon: const Icon(
                            Icons.alternate_email_rounded,
                            color: AppColors.textSecondary,
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 15,
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide:
                                const BorderSide(color: Color(0xFF2A384E)),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: const BorderSide(
                              color: AppColors.primarySoft,
                            ),
                          ),
                          errorBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide:
                                const BorderSide(color: AppColors.highRisk),
                          ),
                          focusedErrorBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide:
                                const BorderSide(color: AppColors.highRisk),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      _PrimaryButton(
                        text: _loading ? 'Sending...' : 'Send reset link',
                        onPressed: _loading ? null : _submit,
                        isLoading: _loading,
                      ),
                      const SizedBox(height: 10),
                      TextButton(
                        onPressed: () => Navigator.pushReplacement(
                          context,
                          fadeSlideRoute(
                            LoginScreen(
                              emailFromRegister: _emailController.text.trim(),
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
                          'Back to sign in',
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 13.5,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
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

class _PrimaryButton extends StatelessWidget {
  final String text;
  final VoidCallback? onPressed;
  final bool isLoading;

  const _PrimaryButton({
    required this.text,
    required this.onPressed,
    this.isLoading = false,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFFF0BD5F),
          foregroundColor: const Color(0xFF08111F),
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
        child: isLoading
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2.2,
                  color: Color(0xFF08111F),
                ),
              )
            : Text(
                text,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                ),
              ),
      ),
    );
  }
}

class _NoticeBanner extends StatelessWidget {
  final String text;

  const _NoticeBanner({required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF102033),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF2C4A68)),
      ),
      child: Text(
        text,
        style: const TextStyle(
          color: Color(0xFFD9EEF8),
          fontSize: 12.5,
          fontWeight: FontWeight.w600,
          height: 1.35,
        ),
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  final String text;

  const _ErrorBanner({required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF2A1420),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF8F3A53)),
      ),
      child: Text(
        text,
        style: const TextStyle(
          color: Color(0xFFFFD0D8),
          fontSize: 12.5,
          fontWeight: FontWeight.w600,
          height: 1.35,
        ),
      ),
    );
  }
}


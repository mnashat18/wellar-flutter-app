import 'dart:async';

import 'package:flutter/material.dart';

import '../utils/app_colors.dart';
import '../widgets/animated_space_background.dart';
import '../widgets/app_buttons.dart';
import '../widgets/app_cards.dart';
import '../widgets/fade_slide.dart';
import '../widgets/otp_input.dart';
import '../utils/page_transition.dart';
import 'login_screen.dart';
import 'role_based_shells.dart';

enum VerificationChannel { whatsapp, email }
enum VerificationNext { home, login }

class VerificationScreen extends StatefulWidget {
  final VerificationChannel channel;
  final String destination;
  final VerificationNext next;
  final String? emailPrefill;

  const VerificationScreen({
    super.key,
    required this.channel,
    required this.destination,
    required this.next,
    this.emailPrefill,
  });

  @override
  State<VerificationScreen> createState() => _VerificationScreenState();
}

class _VerificationScreenState extends State<VerificationScreen> {
  static const int _cooldownSeconds = 90;
  late int _secondsLeft;
  Timer? _timer;
  String _code = '';

  @override
  void initState() {
    super.initState();
    _secondsLeft = _cooldownSeconds;
    _startTimer();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _startTimer() {
    _timer?.cancel();
    _secondsLeft = _cooldownSeconds;
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return;
      if (_secondsLeft <= 1) {
        timer.cancel();
        setState(() => _secondsLeft = 0);
        return;
      }
      setState(() => _secondsLeft--);
    });
  }

  void _resendCode() {
    _startTimer();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(_sentMessage()),
        backgroundColor: AppColors.cardAlt,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _continue() {
    if (_code.length != 6) return;
    switch (widget.next) {
      case VerificationNext.home:
        Navigator.pushAndRemoveUntil(
          context,
          fadeSlideRoute(const RoleShellRouter()),
          (_) => false,
        );
        break;
      case VerificationNext.login:
        Navigator.pushAndRemoveUntil(
          context,
          fadeSlideRoute(
            LoginScreen(emailFromRegister: widget.emailPrefill),
          ),
          (_) => false,
        );
        break;
    }
  }

  String _formatTime(int seconds) {
    final m = seconds ~/ 60;
    final s = seconds % 60;
    final mm = m.toString().padLeft(2, '0');
    final ss = s.toString().padLeft(2, '0');
    return '$mm:$ss';
  }

  String _sentMessage() {
    if (widget.channel == VerificationChannel.whatsapp) {
      return 'Code sent to WhatsApp.';
    }
    return 'Code sent to email.';
  }

  String _channelLabel() {
    return widget.channel == VerificationChannel.whatsapp ? 'WhatsApp' : 'Email';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Stack(
        children: [
          const AnimatedSpaceBackground(),
          SafeArea(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
              children: [
                Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.arrow_back, color: Colors.white70),
                      onPressed: () => Navigator.pop(context),
                    ),
                    const SizedBox(width: 6),
                    const Text(
                      'Verification',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                FadeSlide(
                  delay: const Duration(milliseconds: 80),
                  child: AppCard(
                    padding: const EdgeInsets.all(18),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Verify with ${_channelLabel()}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'We sent a 6-digit code to ${widget.destination}.',
                          style: const TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 12,
                          ),
                        ),
                        const SizedBox(height: 16),
                        OtpInput(
                          length: 6,
                          onChanged: (value) => setState(() => _code = value),
                        ),
                        const SizedBox(height: 16),
                        PrimaryButton(
                          text: 'Continue',
                          icon: Icons.verified_rounded,
                          onPressed: _code.length == 6 ? _continue : null,
                        ),
                        const SizedBox(height: 14),
                        Center(
                          child: _secondsLeft == 0
                              ? TextButton(
                                  onPressed: _resendCode,
                                  child: const Text(
                                    'Resend code',
                                    style: TextStyle(
                                      color: AppColors.primarySoft,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                )
                              : Text(
                                  'Resend in ${_formatTime(_secondsLeft)}',
                                  style: const TextStyle(
                                    color: AppColors.textSecondary,
                                    fontSize: 12,
                                  ),
                                ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                FadeSlide(
                  delay: const Duration(milliseconds: 140),
                  child: AppCard(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: const [
                        Icon(Icons.shield_outlined,
                            color: AppColors.primarySoft),
                        SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Verification keeps your account secure and ensures every request is trusted.',
                            style: TextStyle(
                              color: AppColors.textSecondary,
                              fontSize: 12,
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
        ],
      ),
    );
  }
}

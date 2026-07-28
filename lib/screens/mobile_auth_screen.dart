import 'package:flutter/material.dart';

import '../utils/app_colors.dart';
import '../widgets/animated_space_background.dart';
import '../widgets/app_buttons.dart';
import '../widgets/app_cards.dart';
import '../widgets/fade_slide.dart';
import '../utils/page_transition.dart';
import 'verification_screen.dart';

class MobileAuthScreen extends StatefulWidget {
  const MobileAuthScreen({super.key});

  @override
  State<MobileAuthScreen> createState() => _MobileAuthScreenState();
}

class _MobileAuthScreenState extends State<MobileAuthScreen> {
  final _phoneController = TextEditingController();
  final _emailController = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _phoneController.dispose();
    _emailController.dispose();
    super.dispose();
  }

  void _sendViaWhatsApp() {
    final phone = _phoneController.text.trim();
    if (phone.isEmpty) {
      setState(() => _error = 'Please enter a phone number.');
      return;
    }
    setState(() => _error = null);
    Navigator.push(
      context,
      fadeSlideRoute(
        VerificationScreen(
          channel: VerificationChannel.whatsapp,
          destination: phone,
          next: VerificationNext.home,
        ),
      ),
    );
  }

  void _sendViaEmail() {
    final email = _emailController.text.trim();
    if (email.isEmpty || !email.contains('@')) {
      setState(() => _error = 'Please enter a valid email address.');
      return;
    }
    setState(() => _error = null);
    Navigator.push(
      context,
      fadeSlideRoute(
        VerificationScreen(
          channel: VerificationChannel.email,
          destination: email,
          next: VerificationNext.home,
        ),
      ),
    );
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
                      'Continue with Mobile',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                FadeSlide(
                  delay: const Duration(milliseconds: 80),
                  child: AppCard(
                    padding: const EdgeInsets.all(18),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Secure access',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 6),
                        const Text(
                          'We will send a 6-digit verification code. Choose WhatsApp or email.',
                          style: TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 12,
                          ),
                        ),
                        const SizedBox(height: 16),
                        _label('Phone number'),
                        const SizedBox(height: 8),
                        _inputField(
                          controller: _phoneController,
                          hint: '+1 555 000 1234',
                          icon: Icons.phone_android,
                        ),
                        const SizedBox(height: 14),
                        _label('Backup email (optional)'),
                        const SizedBox(height: 8),
                        _inputField(
                          controller: _emailController,
                          hint: 'name@company.com',
                          icon: Icons.email_outlined,
                        ),
                        if (_error != null) ...[
                          const SizedBox(height: 10),
                          Text(
                            _error!,
                            style: const TextStyle(
                              color: AppColors.highRisk,
                              fontSize: 12,
                            ),
                          ),
                        ],
                        const SizedBox(height: 16),
                        PrimaryButton(
                          text: 'Send via WhatsApp',
                          icon: Icons.chat_bubble_outline,
                          onPressed: _sendViaWhatsApp,
                        ),
                        const SizedBox(height: 12),
                        SecondaryButton(
                          text: 'Send via Email',
                          onPressed: _sendViaEmail,
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                FadeSlide(
                  delay: const Duration(milliseconds: 140),
                  child: AppCard(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: const [
                        Icon(Icons.lock_outline, color: AppColors.primarySoft),
                        SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Verification codes expire quickly for security. If you do not receive a message, resend the code.',
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

  Widget _label(String text) {
    return Text(
      text,
      style: const TextStyle(
        color: Colors.white,
        fontSize: 12,
        fontWeight: FontWeight.w600,
      ),
    );
  }

  Widget _inputField({
    required TextEditingController controller,
    required String hint,
    required IconData icon,
  }) {
    return TextField(
      controller: controller,
      style: const TextStyle(color: Colors.white),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: AppColors.textSecondary),
        prefixIcon: Icon(icon, color: AppColors.textSecondary),
        filled: true,
        fillColor: AppColors.backgroundAlt,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Colors.white12),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AppColors.primarySoft),
        ),
      ),
    );
  }
}

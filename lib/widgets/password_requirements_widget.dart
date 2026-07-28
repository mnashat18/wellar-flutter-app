import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../utils/password_validator.dart';

class PasswordRequirementsWidget extends StatelessWidget {
  final PasswordValidationState state;
  final String minLengthLabel;
  final String upperLabel;
  final String lowerLabel;
  final String numberLabel;
  final String specialLabel;
  final String matchLabel;

  const PasswordRequirementsWidget({
    super.key,
    required this.state,
    required this.minLengthLabel,
    required this.upperLabel,
    required this.lowerLabel,
    required this.numberLabel,
    required this.specialLabel,
    required this.matchLabel,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _item(minLengthLabel, state.minLength),
        _item(upperLabel, state.upper),
        _item(lowerLabel, state.lower),
        _item(numberLabel, state.number),
        _item(specialLabel, state.special),
        _item(matchLabel, state.match),
      ],
    );
  }

  Widget _item(String label, bool ok) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: ok
            ? WellarTheme.success.withValues(alpha: 0.12)
            : WellarTheme.surfaceSoft.withValues(alpha: 0.36),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: ok
              ? WellarTheme.success.withValues(alpha: 0.6)
              : Colors.white10,
        ),
      ),
      child: Row(
        children: [
          Icon(
            ok ? Icons.check_circle : Icons.radio_button_unchecked,
            size: 15,
            color: ok ? WellarTheme.success : WellarTheme.textMuted,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                color: ok ? Colors.white : WellarTheme.textMuted,
                fontSize: 12,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

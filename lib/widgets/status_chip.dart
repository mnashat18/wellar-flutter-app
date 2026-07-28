import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

class StatusChip extends StatelessWidget {
  final String value;
  const StatusChip(this.value, {super.key});

  @override
  Widget build(BuildContext context) {
    final normalized = value.trim().toLowerCase();
    final color = switch (normalized) {
      'pending' => WellarTheme.warning,
      'completed' => WellarTheme.success,
      'overdue' => WellarTheme.danger,
      'active' => WellarTheme.primary,
      'unread' => const Color(0xFF79A7FF),
      _ => WellarTheme.textMuted,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.45)),
      ),
      child: Text(
        value.isEmpty ? '-' : value,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}


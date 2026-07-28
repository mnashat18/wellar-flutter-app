import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

class ReadinessChip extends StatelessWidget {
  final String label;
  const ReadinessChip(this.label, {super.key});

  @override
  Widget build(BuildContext context) {
    final normalized = _normalize(label);
    final color = switch (normalized) {
      'Stable' => WellarTheme.success,
      'Low Focus' => WellarTheme.warning,
      'Elevated Fatigue' => const Color(0xFFFFA07A),
      'High Risk' => WellarTheme.danger,
      _ => WellarTheme.textMuted,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Text(
        normalized,
        style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w700),
      ),
    );
  }

  String _normalize(String value) {
    final v = value.trim().toLowerCase();
    if (v == 'stable') return 'Stable';
    if (v == 'low focus' || v == 'low_focus') return 'Low Focus';
    if (v == 'elevated fatigue' || v == 'elevated_fatigue') return 'Elevated Fatigue';
    if (v == 'high risk' || v == 'high_risk') return 'High Risk';
    if (v.isEmpty) return 'Pending';
    return value;
  }
}


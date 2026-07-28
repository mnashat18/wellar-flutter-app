import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'wellar_card.dart';

class WellarMetricCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;

  const WellarMetricCard({
    super.key,
    required this.label,
    required this.value,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return WellarCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: WellarTheme.primary, size: 18),
          const SizedBox(height: 8),
          Text(value,
              style: const TextStyle(
                color: WellarTheme.text,
                fontWeight: FontWeight.w700,
              )),
          const SizedBox(height: 4),
          Text(label, style: const TextStyle(color: WellarTheme.textMuted, fontSize: 12)),
        ],
      ),
    );
  }
}


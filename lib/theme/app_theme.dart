import 'package:flutter/material.dart';

class WellarTheme {
  static const Color bg = Color(0xFF050A12);
  static const Color surface = Color(0xCC0F1A2E);
  static const Color surfaceSoft = Color(0xBF16263F);
  static const Color border = Color(0x4D5A7EA8);
  static const Color text = Color(0xFFF1F5FF);
  static const Color textMuted = Color(0xFFA8B8D3);
  static const Color primary = Color(0xFF49D3C2);
  static const Color danger = Color(0xFFFF6A7A);
  static const Color warning = Color(0xFFFFC46B);
  static const Color success = Color(0xFF6EE7A8);

  static const double pagePadding = 20;
  static const double cardRadius = 24;
  static const double cardPadding = 18;
  static const double sectionGap = 16;
  static const Duration fast = Duration(milliseconds: 180);

  static const LinearGradient backgroundGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF040810), Color(0xFF081020), Color(0xFF0D1628)],
  );
}

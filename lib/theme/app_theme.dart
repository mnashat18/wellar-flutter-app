import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class WellarTheme {
  static const Color bg = Color(0xFF050A12);
  static const Color surface = Color(0xCC0F1A2E);
  static const Color surfaceSoft = Color(0xBF16263F);
  static const Color border = Color(0x4D5A7EA8);
  static const Color text = Color(0xFFF1F5FF);
  static const Color textMuted = Color(0xFFA8B8D3);
  static const Color primary = Color(0xFF12B892);
  static const Color primaryDark = Color(0xFF0B7A63);
  static const Color disabled = Color(0xFF617486);
  static const Color primaryOverlay = Color(0x2412B892);
  static const Color danger = Color(0xFFFF6A7A);
  static const Color warning = Color(0xFFFFC46B);
  static const Color success = Color(0xFF6EE7A8);
  static const Color info = Color(0xFF7DBBFF);
  static const Color neutral = Color(0xFF8B98B4);

  static const double pagePadding = 20;
  static const double cardRadius = 24;
  static const double cardPadding = 18;
  static const double sectionGap = 16;
  static const Duration fast = Duration(milliseconds: 180);

  static TextStyle get heading => GoogleFonts.spaceGrotesk(
    fontSize: 24,
    fontWeight: FontWeight.w700,
    color: text,
  );

  static TextStyle get body => GoogleFonts.inter(fontSize: 14, color: text);

  static TextStyle get caption =>
      GoogleFonts.inter(fontSize: 12, color: textMuted);

  static TextTheme get textTheme => GoogleFonts.manropeTextTheme().copyWith(
    headlineSmall: heading,
    bodyMedium: body,
    bodySmall: caption,
  );

  static const LinearGradient backgroundGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF040810), Color(0xFF081020), Color(0xFF0D1628)],
  );
}

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

class WellarButton extends StatelessWidget {
  final String text;
  final VoidCallback? onPressed;
  final Color bg;
  final Color fg;

  const WellarButton._({
    required this.text,
    required this.onPressed,
    required this.bg,
    required this.fg,
  });

  factory WellarButton.primary({required String text, required VoidCallback? onPressed}) =>
      WellarButton._(text: text, onPressed: onPressed, bg: WellarTheme.primary, fg: Colors.black);

  factory WellarButton.secondary({required String text, required VoidCallback? onPressed}) =>
      WellarButton._(text: text, onPressed: onPressed, bg: WellarTheme.surfaceSoft, fg: WellarTheme.text);

  @override
  Widget build(BuildContext context) {
    return ElevatedButton(
      style: ElevatedButton.styleFrom(
        elevation: 0,
        backgroundColor: bg,
        foregroundColor: fg,
        minimumSize: const Size.fromHeight(46),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      onPressed: onPressed,
      child: Text(text, style: const TextStyle(fontWeight: FontWeight.w700)),
    );
  }
}


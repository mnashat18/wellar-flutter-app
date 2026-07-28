import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

class WellarCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final bool highlighted;

  const WellarCard({
    super.key,
    required this.child,
    this.padding,
    this.highlighted = false,
  });

  @override
  Widget build(BuildContext context) {
    final borderColor = highlighted
        ? WellarTheme.primary.withValues(alpha: 0.72)
        : WellarTheme.border;

    return Container(
      padding: padding ?? const EdgeInsets.all(WellarTheme.cardPadding),
      decoration: BoxDecoration(
        color: highlighted ? const Color(0xFF111C2E) : WellarTheme.surface,
        borderRadius: BorderRadius.circular(WellarTheme.cardRadius),
        border: Border.all(color: borderColor),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.14),
            blurRadius: 10,
            offset: const Offset(0, 5),
          ),
          if (highlighted)
            BoxShadow(
              color: WellarTheme.primary.withValues(alpha: 0.06),
              blurRadius: 12,
            ),
        ],
      ),
      child: child,
    );
  }
}

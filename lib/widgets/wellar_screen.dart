import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'app_animated_background.dart';

class WellarScreen extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final bool showBackground;

  const WellarScreen({
    super.key,
    required this.child,
    this.padding,
    this.showBackground = true,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        if (showBackground) const AppAnimatedBackground(),
        SafeArea(
          child: Padding(
            padding:
                padding ??
                EdgeInsets.fromLTRB(
                  WellarTheme.pagePadding,
                  20,
                  WellarTheme.pagePadding,
                  8,
                ),
            child: child,
          ),
        ),
      ],
    );
  }
}

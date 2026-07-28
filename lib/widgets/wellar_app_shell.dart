import 'package:flutter/material.dart';

import 'app_animated_background.dart';

class WellarAppShell extends StatelessWidget {
  final Widget child;
  final Widget? bottomNavigationBar;
  final bool animateBackground;

  const WellarAppShell({
    super.key,
    required this.child,
    this.bottomNavigationBar,
    this.animateBackground = true,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      extendBody: true,
      body: Stack(
        fit: StackFit.expand,
        children: [
          AppAnimatedBackground(enableAnimation: animateBackground),
          Positioned.fill(child: child),
        ],
      ),
      bottomNavigationBar: bottomNavigationBar,
    );
  }
}

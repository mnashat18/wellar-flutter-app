import 'package:flutter/material.dart';

class AnimatedSpaceBackground extends StatelessWidget {
  const AnimatedSpaceBackground({super.key});

  @override
  Widget build(BuildContext context) {
    return const DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF050A12), Color(0xFF08111D), Color(0xFF0B1322)],
        ),
      ),
    );
  }
}

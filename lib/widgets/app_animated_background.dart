import 'package:flutter/material.dart';

class AppAnimatedBackground extends StatelessWidget {
  final bool enableAnimation;

  const AppAnimatedBackground({super.key, this.enableAnimation = true});

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: const DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color(0xFF04080F),
              Color(0xFF070E1A),
              Color(0xFF0B1422),
            ],
          ),
        ),
        child: Stack(
          fit: StackFit.expand,
          children: [
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: Alignment(-0.22, -0.86),
                  radius: 1.12,
                  colors: [Color(0x1439B8FF), Colors.transparent],
                ),
              ),
            ),
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: Alignment(0.9, -0.12),
                  radius: 0.78,
                  colors: [Color(0x1249D3C2), Colors.transparent],
                ),
              ),
            ),
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.transparent, Color(0x22000000)],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

class WellarBackground extends StatelessWidget {
  const WellarBackground({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(gradient: WellarTheme.backgroundGradient),
      child: Stack(
        children: [
          Positioned(
            top: -80,
            right: -60,
            child: _glow(const Color(0x3349D3C2), 220),
          ),
          Positioned(
            bottom: -120,
            left: -80,
            child: _glow(const Color(0x223C67FF), 260),
          ),
        ],
      ),
    );
  }

  Widget _glow(Color color, double size) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color,
      ),
    );
  }
}


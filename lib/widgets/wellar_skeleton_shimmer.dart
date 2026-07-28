import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

class WellarSkeletonShimmer extends StatefulWidget {
  final double height;
  final BorderRadiusGeometry? borderRadius;

  const WellarSkeletonShimmer({
    super.key,
    required this.height,
    this.borderRadius,
  });

  @override
  State<WellarSkeletonShimmer> createState() => _WellarSkeletonShimmerState();
}

class _WellarSkeletonShimmerState extends State<WellarSkeletonShimmer>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1300),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (_, __) {
        final t = _controller.value;
        return Container(
          height: widget.height,
          decoration: BoxDecoration(
            borderRadius: widget.borderRadius ?? BorderRadius.circular(20),
            gradient: LinearGradient(
              begin: Alignment(-1.2 + 2.4 * t, -0.2),
              end: Alignment(1.2 + 2.4 * t, 0.2),
              colors: const [
                Color(0xFF18243A),
                Color(0xFF263753),
                Color(0xFF18243A),
              ],
            ),
            border: Border.all(color: WellarTheme.border),
          ),
        );
      },
    );
  }
}


import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'app_animated_background.dart';

class AnimatedWellarScreen extends StatefulWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final Duration duration;
  final bool showBackground;

  const AnimatedWellarScreen({
    super.key,
    required this.child,
    this.padding,
    this.duration = const Duration(milliseconds: 380),
    this.showBackground = true,
  });

  @override
  State<AnimatedWellarScreen> createState() => _AnimatedWellarScreenState();
}

class _AnimatedWellarScreenState extends State<AnimatedWellarScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _fade;
  late final Animation<Offset> _slide;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: widget.duration);
    _fade = CurvedAnimation(parent: _controller, curve: Curves.easeOut);
    _slide = Tween<Offset>(
      begin: const Offset(0, 0.018),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic));
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        if (widget.showBackground) const AppAnimatedBackground(),
        SafeArea(
          child: FadeTransition(
            opacity: _fade,
            child: SlideTransition(
              position: _slide,
              child: Padding(
                padding:
                    widget.padding ??
                    EdgeInsets.fromLTRB(
                      WellarTheme.pagePadding,
                      20,
                      WellarTheme.pagePadding,
                      8,
                    ),
                child: widget.child,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'wellar_button.dart';

class WellarErrorState extends StatefulWidget {
  final String title;
  final String body;
  final VoidCallback onRetry;

  const WellarErrorState({
    super.key,
    required this.title,
    required this.body,
    required this.onRetry,
  });

  @override
  State<WellarErrorState> createState() => _WellarErrorStateState();
}

class _WellarErrorStateState extends State<WellarErrorState>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _fade;
  late final Animation<Offset> _slide;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 260),
    );
    _fade = CurvedAnimation(parent: _controller, curve: Curves.easeOut);
    _slide = Tween<Offset>(begin: const Offset(0, 0.04), end: Offset.zero)
        .animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic));
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 30),
      child: FadeTransition(
        opacity: _fade,
        child: SlideTransition(
          position: _slide,
          child: Column(
            children: [
              const Icon(Icons.error_outline_rounded, color: WellarTheme.danger, size: 30),
              const SizedBox(height: 10),
              Text(widget.title, style: const TextStyle(color: WellarTheme.text, fontWeight: FontWeight.w700)),
              const SizedBox(height: 6),
              Text(widget.body, textAlign: TextAlign.center, style: const TextStyle(color: WellarTheme.textMuted)),
              const SizedBox(height: 14),
              WellarButton.secondary(text: 'Retry', onPressed: widget.onRetry),
            ],
          ),
        ),
      ),
    );
  }
}

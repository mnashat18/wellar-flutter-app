import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

class WellarEmptyState extends StatefulWidget {
  final IconData icon;
  final String title;
  final String body;

  const WellarEmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.body,
  });

  @override
  State<WellarEmptyState> createState() => _WellarEmptyStateState();
}

class _WellarEmptyStateState extends State<WellarEmptyState>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 8),
      child: Column(
        children: [
          ScaleTransition(
            scale: Tween<double>(begin: 0.96, end: 1.04).animate(
              CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
            ),
            child: Icon(widget.icon, color: WellarTheme.textMuted, size: 30),
          ),
          const SizedBox(height: 10),
          Text(widget.title, style: const TextStyle(color: WellarTheme.text, fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          Text(widget.body, textAlign: TextAlign.center, style: const TextStyle(color: WellarTheme.textMuted)),
        ],
      ),
    );
  }
}

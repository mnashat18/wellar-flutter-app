import 'dart:async';

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'wellar_card.dart';

class WellarProcessingState extends StatefulWidget {
  final List<String> stages;
  final String title;

  const WellarProcessingState({
    super.key,
    required this.stages,
    this.title = 'Processing',
  });

  @override
  State<WellarProcessingState> createState() => _WellarProcessingStateState();
}

class _WellarProcessingStateState extends State<WellarProcessingState>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  Timer? _timer;
  int _index = 0;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
    _timer = Timer.periodic(const Duration(seconds: 2), (_) {
      if (!mounted || widget.stages.isEmpty) return;
      setState(() => _index = (_index + 1) % widget.stages.length);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final stage = widget.stages.isEmpty ? '' : widget.stages[_index];
    return WellarCard(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ScaleTransition(
            scale: Tween<double>(begin: 0.95, end: 1.06).animate(
              CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
            ),
            child: const Icon(
              Icons.sync_rounded,
              color: WellarTheme.primary,
              size: 28,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            widget.title,
            style: const TextStyle(
              color: WellarTheme.text,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 260),
            child: Text(
              stage,
              key: ValueKey(stage),
              textAlign: TextAlign.center,
              style: const TextStyle(color: WellarTheme.textMuted),
            ),
          ),
        ],
      ),
    );
  }
}


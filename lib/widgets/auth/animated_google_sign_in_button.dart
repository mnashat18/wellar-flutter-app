import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../utils/app_colors.dart';
import '../google_mark.dart';

class AnimatedGoogleSignInButton extends StatefulWidget {
  final String text;
  final VoidCallback? onPressed;
  final bool isLoading;
  final double height;

  const AnimatedGoogleSignInButton({
    super.key,
    required this.text,
    required this.onPressed,
    this.isLoading = false,
    this.height = 58,
  });

  @override
  State<AnimatedGoogleSignInButton> createState() =>
      _AnimatedGoogleSignInButtonState();
}

class _AnimatedGoogleSignInButtonState extends State<AnimatedGoogleSignInButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _borderController;
  bool _pressed = false;
  bool _hovered = false;

  @override
  void initState() {
    super.initState();
    _borderController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2800),
    )..repeat();
  }

  @override
  void dispose() {
    _borderController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onPressed != null && !widget.isLoading;
    final scale = _pressed
        ? 0.986
        : _hovered
            ? 1.01
            : 1.0;

    return AnimatedScale(
      scale: scale,
      duration: const Duration(milliseconds: 150),
      curve: Curves.easeOutCubic,
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          onTapDown: enabled ? (_) => setState(() => _pressed = true) : null,
          onTapCancel: enabled ? () => setState(() => _pressed = false) : null,
          onTapUp: enabled ? (_) => setState(() => _pressed = false) : null,
          child: AnimatedBuilder(
            animation: _borderController,
            builder: (context, _) {
              final angle = _borderController.value * 2 * math.pi;
              return Container(
                height: widget.height,
                width: double.infinity,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(22),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF3BA8FF).withValues(alpha: 0.2),
                      blurRadius: 26,
                      spreadRadius: -6,
                      offset: const Offset(0, 10),
                    ),
                  ],
                  gradient: SweepGradient(
                    transform: GradientRotation(angle),
                    colors: const [
                      Color(0xFF2F80FF),
                      Color(0xFF18D3F4),
                      Color(0xFF8B5CF6),
                      Color(0xFFF2C94C),
                      Color(0xFF4285F4),
                      Color(0xFF34A853),
                      Color(0xFFFBBC05),
                      Color(0xFFEA4335),
                      Color(0xFF2F80FF),
                    ],
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(1.5),
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(20.5),
                      onTap: enabled ? widget.onPressed : null,
                      child: Ink(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(20.5),
                          color: const Color(0xFF0D1731).withValues(alpha: 0.88),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.11),
                          ),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 14),
                          child: Row(
                            children: [
                              Container(
                                width: 34,
                                height: 34,
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(11),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withValues(alpha: 0.2),
                                      blurRadius: 12,
                                      offset: const Offset(0, 4),
                                    ),
                                  ],
                                ),
                                child: const Center(child: GoogleMark(size: 19)),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  widget.text,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 15,
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: 0.1,
                                  ),
                                ),
                              ),
                              if (widget.isLoading)
                                const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2.1,
                                    color: Colors.white,
                                  ),
                                )
                              else
                                Icon(
                                  Icons.arrow_forward_rounded,
                                  size: 20,
                                  color: AppColors.primarySoft.withValues(
                                    alpha: 0.95,
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

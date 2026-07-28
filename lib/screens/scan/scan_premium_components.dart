import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

class ScanTheme {
  static const Color background = Color(0xFF050B16);
  static const Color backgroundMid = Color(0xFF07111F);
  static const Color backgroundSoft = Color(0xFF0B1628);
  static const Color surface = Color.fromRGBO(255, 255, 255, 0.06);
  static const Color surfaceStrong = Color.fromRGBO(255, 255, 255, 0.08);
  static const Color border = Color.fromRGBO(255, 255, 255, 0.10);
  static const Color textPrimary = Color(0xFFF8FAFC);
  static const Color textSecondary = Color(0xFF94A3B8);
  static const Color primaryBlue = Color(0xFF3B82F6);
  static const Color cyan = Color(0xFF22D3EE);
  static const Color teal = Color(0xFF2DD4BF);
  static const Color warning = Color(0xFFF59E0B);
  static const Color danger = Color(0xFFEF4444);
}

class ScanBackground extends StatelessWidget {
  final Widget child;

  const ScanBackground({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            ScanTheme.background,
            ScanTheme.backgroundMid,
            ScanTheme.backgroundSoft,
          ],
        ),
      ),
      child: Stack(
        children: [
          Positioned(
            top: -120,
            right: -80,
            child: _GlowOrb(
              size: 280,
              color: ScanTheme.primaryBlue.withOpacity(0.18),
            ),
          ),
          Positioned(
            top: 180,
            left: -90,
            child: _GlowOrb(
              size: 220,
              color: ScanTheme.cyan.withOpacity(0.12),
            ),
          ),
          Positioned(
            bottom: -120,
            right: -20,
            child: _GlowOrb(
              size: 260,
              color: ScanTheme.teal.withOpacity(0.10),
            ),
          ),
          child,
        ],
      ),
    );
  }
}

class PremiumScanScaffold extends StatelessWidget {
  final String stepLabel;
  final int? step;
  final int? totalSteps;
  final VoidCallback? onBack;
  final Widget body;
  final Widget? footer;
  final bool showSecureBadge;
  final EdgeInsets padding;

  const PremiumScanScaffold({
    super.key,
    required this.stepLabel,
    required this.body,
    this.step,
    this.totalSteps,
    this.onBack,
    this.footer,
    this.showSecureBadge = true,
    this.padding = const EdgeInsets.fromLTRB(20, 18, 20, 20),
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: ScanBackground(
        child: SafeArea(
          child: Padding(
            padding: padding,
            child: Column(
              children: [
                ScanStepHeader(
                  stepLabel: stepLabel,
                  step: step,
                  totalSteps: totalSteps,
                  onBack: onBack,
                  showSecureBadge: showSecureBadge,
                ),
                const SizedBox(height: 18),
                Expanded(child: body),
                if (footer != null) ...[
                  const SizedBox(height: 16),
                  footer!,
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class ScanStepHeader extends StatelessWidget {
  final String stepLabel;
  final int? step;
  final int? totalSteps;
  final VoidCallback? onBack;
  final bool showSecureBadge;

  const ScanStepHeader({
    super.key,
    required this.stepLabel,
    this.step,
    this.totalSteps,
    this.onBack,
    this.showSecureBadge = true,
  });

  @override
  Widget build(BuildContext context) {
    final hasProgress = step != null && totalSteps != null && totalSteps! > 0;
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 360;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _HeaderIconButton(
                  icon: onBack == null
                      ? Icons.close_rounded
                      : Icons.arrow_back_ios_new_rounded,
                  onTap: onBack,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        hasProgress
                            ? 'Step $step of $totalSteps'
                            : 'Readiness Check',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.inter(
                          color: ScanTheme.textSecondary,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        stepLabel,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.spaceGrotesk(
                          color: ScanTheme.textPrimary,
                          fontSize: compact ? 22 : 24,
                          fontWeight: FontWeight.w700,
                          height: 1.0,
                        ),
                      ),
                    ],
                  ),
                ),
                if (showSecureBadge && !compact) ...[
                  const SizedBox(width: 12),
                  const StatusPill(
                    label: 'Secure check',
                    color: ScanTheme.cyan,
                    icon: Icons.verified_user_outlined,
                  ),
                ],
              ],
            ),
            if (showSecureBadge && compact) ...[
              const SizedBox(height: 12),
              const StatusPill(
                label: 'Secure check',
                color: ScanTheme.cyan,
                icon: Icons.verified_user_outlined,
              ),
            ],
            if (hasProgress) ...[
              const SizedBox(height: 14),
              _StepSegmentedIndicator(
                currentStep: step!,
                totalSteps: totalSteps!,
              ),
            ],
          ],
        );
      },
    );
  }
}

class _StepSegmentedIndicator extends StatelessWidget {
  final int currentStep;
  final int totalSteps;

  const _StepSegmentedIndicator({
    required this.currentStep,
    required this.totalSteps,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: List.generate(totalSteps, (index) {
        final isComplete = index < currentStep;
        return Expanded(
          child: Padding(
            padding: EdgeInsets.only(right: index == totalSteps - 1 ? 0 : 8),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              height: 8,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(999),
                color: isComplete
                    ? ScanTheme.cyan
                    : Colors.white.withOpacity(0.08),
                border: Border.all(
                  color: isComplete
                      ? ScanTheme.cyan.withOpacity(0.35)
                      : ScanTheme.border,
                ),
                boxShadow: isComplete
                    ? [
                        BoxShadow(
                          color: ScanTheme.primaryBlue.withOpacity(0.22),
                          blurRadius: 14,
                        ),
                      ]
                    : null,
              ),
            ),
          ),
        );
      }),
    );
  }
}

class ScanProgressBar extends StatelessWidget {
  final double value;

  const ScanProgressBar({super.key, required this.value});

  @override
  Widget build(BuildContext context) {
    final clamped = value.clamp(0.0, 1.0);
    return Container(
      height: 8,
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.06),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: ScanTheme.border),
      ),
      child: Align(
        alignment: Alignment.centerLeft,
        child: FractionallySizedBox(
          widthFactor: clamped,
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(999),
              gradient: const LinearGradient(
                colors: [ScanTheme.primaryBlue, ScanTheme.cyan],
              ),
              boxShadow: [
                BoxShadow(
                  color: ScanTheme.primaryBlue.withOpacity(0.35),
                  blurRadius: 14,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class GlassPanel extends StatelessWidget {
  final Widget child;
  final EdgeInsets padding;
  final double radius;

  const GlassPanel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(18),
    this.radius = 24,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: ScanTheme.surface,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: ScanTheme.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.28),
            blurRadius: 24,
            offset: const Offset(0, 16),
          ),
        ],
      ),
      child: child,
    );
  }
}

class ScanPrimaryButton extends StatefulWidget {
  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;

  const ScanPrimaryButton({
    super.key,
    required this.label,
    this.onPressed,
    this.icon,
  });

  @override
  State<ScanPrimaryButton> createState() => _ScanPrimaryButtonState();
}

class _ScanPrimaryButtonState extends State<ScanPrimaryButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onPressed != null;
    return GestureDetector(
      onTapDown: enabled ? (_) => setState(() => _pressed = true) : null,
      onTapCancel: enabled ? () => setState(() => _pressed = false) : null,
      onTapUp: enabled
          ? (_) {
              setState(() => _pressed = false);
              HapticFeedback.selectionClick();
            }
          : null,
      child: AnimatedScale(
        duration: const Duration(milliseconds: 120),
        scale: _pressed ? 0.985 : 1,
        child: SizedBox(
          width: double.infinity,
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              gradient: enabled
                  ? const LinearGradient(
                      colors: [ScanTheme.primaryBlue, ScanTheme.cyan],
                    )
                  : LinearGradient(
                      colors: [
                        Colors.white.withOpacity(0.10),
                        Colors.white.withOpacity(0.08),
                      ],
                    ),
              boxShadow: enabled
                  ? [
                      BoxShadow(
                        color: ScanTheme.primaryBlue.withOpacity(0.30),
                        blurRadius: 20,
                        offset: const Offset(0, 10),
                      ),
                    ]
                  : null,
            ),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(18),
                onTap: widget.onPressed,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (widget.icon != null) ...[
                        Icon(widget.icon, color: ScanTheme.textPrimary, size: 18),
                        const SizedBox(width: 10),
                      ],
                      Text(
                        widget.label,
                        style: GoogleFonts.inter(
                          color: ScanTheme.textPrimary,
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class ScanSecondaryButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;

  const ScanSecondaryButton({
    super.key,
    required this.label,
    this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          foregroundColor: ScanTheme.textSecondary,
          side: BorderSide(color: Colors.white.withOpacity(0.12)),
          backgroundColor: Colors.white.withOpacity(0.03),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 15),
        ),
        child: Text(
          label,
          style: GoogleFonts.inter(fontWeight: FontWeight.w600),
        ),
      ),
    );
  }
}

class StatusPill extends StatelessWidget {
  final String label;
  final Color color;
  final IconData? icon;

  const StatusPill({
    super.key,
    required this.label,
    required this.color,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color.withOpacity(0.14),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withOpacity(0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, color: color, size: 14),
            const SizedBox(width: 6),
          ],
          Text(
            label,
            style: GoogleFonts.inter(
              color: color,
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class ProcessingPipelineView extends StatelessWidget {
  final String title;
  final String subtitle;
  final int activeIndex;
  final List<PipelineStep> steps;

  const ProcessingPipelineView({
    super.key,
    required this.title,
    required this.subtitle,
    required this.activeIndex,
    required this.steps,
  });

  @override
  Widget build(BuildContext context) {
    return GlassPanel(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: GoogleFonts.spaceGrotesk(
              color: ScanTheme.textPrimary,
              fontSize: 24,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            subtitle,
            style: GoogleFonts.inter(
              color: ScanTheme.textSecondary,
              fontSize: 13,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 18),
          ...List.generate(steps.length, (index) {
            final step = steps[index];
            final state = index < activeIndex
                ? PipelineState.done
                : index == activeIndex
                ? PipelineState.active
                : step.state;
            return Padding(
              padding: EdgeInsets.only(bottom: index == steps.length - 1 ? 0 : 12),
              child: _PipelineRow(
                title: step.title,
                subtitle: step.subtitle,
                state: state,
              ),
            );
          }),
        ],
      ),
    );
  }
}

enum PipelineState { pending, active, done, failed }

class PipelineStep {
  final String title;
  final String subtitle;
  final PipelineState state;

  const PipelineStep({
    required this.title,
    required this.subtitle,
    this.state = PipelineState.pending,
  });
}

class FailureStateView extends StatelessWidget {
  final String title;
  final String message;
  final String primaryLabel;
  final VoidCallback primaryAction;
  final String secondaryLabel;
  final VoidCallback secondaryAction;

  const FailureStateView({
    super.key,
    required this.title,
    required this.message,
    required this.primaryLabel,
    required this.primaryAction,
    required this.secondaryLabel,
    required this.secondaryAction,
  });

  @override
  Widget build(BuildContext context) {
    return GlassPanel(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 88,
            height: 88,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: ScanTheme.danger.withOpacity(0.45)),
              boxShadow: [
                BoxShadow(
                  color: ScanTheme.danger.withOpacity(0.18),
                  blurRadius: 22,
                ),
              ],
            ),
            child: const Center(
              child: Icon(
                Icons.warning_amber_rounded,
                color: ScanTheme.danger,
                size: 38,
              ),
            ),
          ),
          const SizedBox(height: 20),
          Text(
            title,
            textAlign: TextAlign.center,
            style: GoogleFonts.spaceGrotesk(
              color: ScanTheme.textPrimary,
              fontSize: 26,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            message,
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(
              color: ScanTheme.textSecondary,
              fontSize: 13,
              height: 1.6,
            ),
          ),
          const SizedBox(height: 20),
          ScanPrimaryButton(label: primaryLabel, onPressed: primaryAction),
          const SizedBox(height: 10),
          ScanSecondaryButton(label: secondaryLabel, onPressed: secondaryAction),
        ],
      ),
    );
  }
}

class ReadinessGauge extends StatelessWidget {
  final double value;
  final Color color;
  final String label;
  final String sublabel;

  const ReadinessGauge({
    super.key,
    required this.value,
    required this.color,
    required this.label,
    required this.sublabel,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 176,
      height: 176,
      child: Stack(
        alignment: Alignment.center,
        children: [
          CustomPaint(
            size: const Size.square(176),
            painter: _GaugePainter(
              value: value.clamp(0, 1),
              color: color,
            ),
          ),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: GoogleFonts.spaceGrotesk(
                  color: ScanTheme.textPrimary,
                  fontSize: 34,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                sublabel,
                style: GoogleFonts.inter(
                  color: color,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class FocusTileGrid extends StatelessWidget {
  final int activeIndex;
  final ValueChanged<int> onTap;

  const FocusTileGrid({
    super.key,
    required this.activeIndex,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      physics: const NeverScrollableScrollPhysics(),
      shrinkWrap: true,
      itemCount: 9,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        mainAxisSpacing: 10,
        crossAxisSpacing: 10,
        childAspectRatio: 1,
      ),
      itemBuilder: (context, index) {
        final active = index == activeIndex;
        return GestureDetector(
          onTap: () => onTap(index),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              color: active
                  ? ScanTheme.cyan.withOpacity(0.22)
                  : Colors.white.withOpacity(0.05),
              border: Border.all(
                color: active ? ScanTheme.cyan : Colors.white.withOpacity(0.10),
              ),
              boxShadow: active
                  ? [
                      BoxShadow(
                        color: ScanTheme.cyan.withOpacity(0.25),
                        blurRadius: 18,
                      ),
                    ]
                  : null,
            ),
            child: Center(
              child: AnimatedScale(
                duration: const Duration(milliseconds: 180),
                scale: active ? 1 : 0.85,
                child: Container(
                  width: 18,
                  height: 18,
                  decoration: BoxDecoration(
                    color: active ? ScanTheme.cyan : Colors.white24,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _HeaderIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;

  const _HeaderIconButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.05),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: ScanTheme.border),
        ),
        child: Icon(icon, color: ScanTheme.textPrimary, size: 18),
      ),
    );
  }
}

class _GlowOrb extends StatelessWidget {
  final double size;
  final Color color;

  const _GlowOrb({required this.size, required this.color});

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            colors: [color, color.withOpacity(0)],
          ),
        ),
      ),
    );
  }
}

class _PipelineRow extends StatelessWidget {
  final String title;
  final String subtitle;
  final PipelineState state;

  const _PipelineRow({
    required this.title,
    required this.subtitle,
    required this.state,
  });

  @override
  Widget build(BuildContext context) {
    final color = switch (state) {
      PipelineState.pending => ScanTheme.textSecondary,
      PipelineState.active => ScanTheme.cyan,
      PipelineState.done => ScanTheme.teal,
      PipelineState.failed => ScanTheme.danger,
    };
    final icon = switch (state) {
      PipelineState.pending => Icons.schedule_rounded,
      PipelineState.active => Icons.radar_rounded,
      PipelineState.done => Icons.check_circle_rounded,
      PipelineState.failed => Icons.error_rounded,
    };
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.03),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withOpacity(0.08)),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: color.withOpacity(0.14),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: color.withOpacity(0.35)),
            ),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: GoogleFonts.inter(
                    color: ScanTheme.textPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: GoogleFonts.inter(
                    color: ScanTheme.textSecondary,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          StatusPill(
            label: switch (state) {
              PipelineState.pending => 'Pending',
              PipelineState.active => 'Active',
              PipelineState.done => 'Done',
              PipelineState.failed => 'Failed',
            },
            color: color,
          ),
        ],
      ),
    );
  }
}

class _GaugePainter extends CustomPainter {
  final double value;
  final Color color;

  _GaugePainter({required this.value, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    const start = -math.pi * 0.75;
    const sweep = math.pi * 1.5;
    final strokeWidth = 14.0;
    final rect = Offset.zero & size;
    final center = rect.center;
    final radius = (size.width / 2) - strokeWidth;
    final background = Paint()
      ..color = Colors.white.withOpacity(0.08)
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;
    final progress = Paint()
      ..shader = SweepGradient(
        startAngle: start,
        endAngle: start + sweep,
        colors: [color.withOpacity(0.5), color, ScanTheme.cyan],
      ).createShader(rect)
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      start,
      sweep,
      false,
      background,
    );
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      start,
      sweep * value,
      false,
      progress,
    );
  }

  @override
  bool shouldRepaint(covariant _GaugePainter oldDelegate) {
    return oldDelegate.value != value || oldDelegate.color != color;
  }
}

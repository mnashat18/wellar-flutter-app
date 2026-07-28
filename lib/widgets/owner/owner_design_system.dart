import 'dart:math' as math;
import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';

class SectionHeader extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Widget? trailing;

  const SectionHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  color: WellarTheme.text,
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                ),
              ),
              if (subtitle != null) ...[
                const SizedBox(height: 4),
                Text(
                  subtitle!,
                  style: const TextStyle(
                    color: WellarTheme.textMuted,
                    fontSize: 12.5,
                    height: 1.35,
                  ),
                ),
              ],
            ],
          ),
        ),
        if (trailing != null) trailing!,
      ],
    );
  }
}

class OwnerSurfaceCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final bool glow;
  final Gradient? gradient;
  final VoidCallback? onTap;
  final double radius;

  const OwnerSurfaceCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.glow = false,
    this.gradient,
    this.onTap,
    this.radius = 24,
  });

  @override
  Widget build(BuildContext context) {
    final borderRadius = BorderRadius.circular(radius);
    final body = Container(
      decoration: BoxDecoration(
        color: gradient == null ? const Color(0xFF121B2B) : null,
        gradient: gradient,
        border: Border.all(color: const Color(0x2238485F)),
        borderRadius: borderRadius,
        boxShadow: [
          const BoxShadow(
            color: Color(0x24000000),
            blurRadius: 16,
            offset: Offset(0, 8),
          ),
          if (glow)
            BoxShadow(
              color: WellarTheme.primary.withValues(alpha: 0.05),
              blurRadius: 12,
            ),
        ],
      ),
      child: Padding(padding: padding, child: child),
    );
    if (onTap == null) return body;
    return Material(
      color: Colors.transparent,
      child: InkWell(onTap: onTap, borderRadius: borderRadius, child: body),
    );
  }
}

class OwnerMetricCard extends StatelessWidget {
  final String label;
  final int value;
  final IconData icon;
  final String? helper;
  final Color accent;

  const OwnerMetricCard({
    super.key,
    required this.label,
    required this.value,
    required this.icon,
    this.helper,
    this.accent = WellarTheme.primary,
  });

  @override
  Widget build(BuildContext context) {
    return OwnerSurfaceCard(
      padding: const EdgeInsets.all(14),
      glow: true,
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          const Color(0xFF0E172B),
          Color.alphaBlend(
            accent.withValues(alpha: 0.14),
            const Color(0xFF121E34),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: accent, size: 18),
              const Spacer(),
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: accent.withValues(alpha: 0.9),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          TweenAnimationBuilder<double>(
            tween: Tween<double>(begin: 0, end: value.toDouble()),
            duration: const Duration(milliseconds: 700),
            curve: Curves.easeOutCubic,
            builder: (context, animated, _) => Text(
              '${animated.round()}',
              style: const TextStyle(
                color: WellarTheme.text,
                fontSize: 30,
                fontWeight: FontWeight.w800,
                height: 1,
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            label,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: WellarTheme.textMuted,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          if (helper != null) ...[
            const SizedBox(height: 5),
            Text(
              helper!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: accent.withValues(alpha: 0.9),
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class OwnerInsightCard extends StatelessWidget {
  final String title;
  final String value;
  final String? subtitle;
  final Widget? chip;
  final IconData icon;
  final Color accent;

  const OwnerInsightCard({
    super.key,
    required this.title,
    required this.value,
    this.subtitle,
    this.chip,
    required this.icon,
    this.accent = WellarTheme.primary,
  });

  @override
  Widget build(BuildContext context) {
    return OwnerSurfaceCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: accent),
              const Spacer(),
              if (chip != null) chip!,
            ],
          ),
          const SizedBox(height: 10),
          Text(
            title,
            style: const TextStyle(
              color: WellarTheme.textMuted,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            value,
            style: const TextStyle(
              color: WellarTheme.text,
              fontSize: 22,
              fontWeight: FontWeight.w800,
              height: 1,
            ),
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 6),
            Text(
              subtitle!,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: WellarTheme.textMuted,
                fontSize: 11,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class ReadinessStatusChip extends StatelessWidget {
  final String label;

  const ReadinessStatusChip(this.label, {super.key});

  @override
  Widget build(BuildContext context) {
    final lower = label.toLowerCase();
    Color color;
    if (lower.contains('high')) {
      color = const Color(0xFFFF7A8F);
    } else if (lower.contains('elevated')) {
      color = const Color(0xFFFFC46B);
    } else if (lower.contains('low focus')) {
      color = const Color(0xFF7DBBFF);
    } else {
      color = const Color(0xFF6EE7A8);
    }
    return _pill(label, color);
  }
}

class MemberStatusChip extends StatelessWidget {
  final String status;

  const MemberStatusChip(this.status, {super.key});

  @override
  Widget build(BuildContext context) {
    final value = status.trim();
    final lower = value.toLowerCase();
    Color color;
    if (lower == 'active') {
      color = const Color(0xFF6EE7A8);
    } else if (lower.contains('pending') || lower.contains('invite')) {
      color = const Color(0xFFFFC46B);
    } else {
      color = const Color(0xFFA7B4CC);
    }
    return _pill(value.isEmpty ? 'Unknown' : value, color);
  }
}

class RoleChip extends StatelessWidget {
  final String role;

  const RoleChip(this.role, {super.key});

  @override
  Widget build(BuildContext context) {
    final normalized = role.trim().toLowerCase();
    String label;
    switch (normalized) {
      case 'owner':
        label = 'Owner';
        break;
      case 'admin':
      case 'hr':
        label = 'HR';
        break;
      case 'manager':
      case 'manger':
        label = 'Manager';
        break;
      case 'member':
      case 'employee':
      case 'user':
        label = 'Employee';
        break;
      default:
        label = normalized.isEmpty ? 'Unknown' : _title(normalized);
        break;
    }
    return _pill(label, const Color(0xFF74E6D7));
  }
}

class TonePill extends StatelessWidget {
  final String label;
  final Color color;
  final double fontSize;
  final EdgeInsetsGeometry padding;

  const TonePill({
    super.key,
    required this.label,
    required this.color,
    this.fontSize = 11,
    this.padding = const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
  });

  @override
  Widget build(BuildContext context) {
    return _pill(label, color, fontSize: fontSize, padding: padding);
  }
}

class InitialsAvatar extends StatelessWidget {
  final String label;
  final double size;
  final Color accent;

  const InitialsAvatar({
    super.key,
    required this.label,
    this.size = 44,
    this.accent = WellarTheme.primary,
  });

  @override
  Widget build(BuildContext context) {
    final initials = _initials(label);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(size * 0.34),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [accent.withValues(alpha: 0.26), const Color(0x3358A6FF)],
        ),
        border: Border.all(color: accent.withValues(alpha: 0.26)),
      ),
      alignment: Alignment.center,
      child: Text(
        initials,
        style: TextStyle(
          color: accent.withValues(alpha: 0.96),
          fontWeight: FontWeight.w800,
          fontSize: size * 0.28,
          letterSpacing: 0.2,
        ),
      ),
    );
  }
}

class RiskLevelChip extends StatelessWidget {
  final int count;

  const RiskLevelChip({super.key, required this.count});

  @override
  Widget build(BuildContext context) {
    if (count <= 0) return _pill('Low', const Color(0xFF6EE7A8));
    if (count < 3) return _pill('Moderate', const Color(0xFFFFC46B));
    return _pill('High', const Color(0xFFFF7A8F));
  }
}

class QuickActionButton extends StatelessWidget {
  final String title;
  final String? subtitle;
  final IconData icon;
  final VoidCallback onTap;

  const QuickActionButton({
    super.key,
    required this.title,
    this.subtitle,
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return OwnerSurfaceCard(
      padding: const EdgeInsets.all(14),
      onTap: onTap,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              gradient: const LinearGradient(
                colors: [Color(0x2949D3C2), Color(0x224A89FF)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              border: Border.all(color: const Color(0x2249D3C2)),
            ),
            child: Icon(icon, color: WellarTheme.primary),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 2,
                  overflow: TextOverflow.fade,
                  style: const TextStyle(
                    color: WellarTheme.text,
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                    height: 1.2,
                  ),
                ),
                if (subtitle != null && subtitle!.trim().isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(
                    subtitle!,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: WellarTheme.textMuted,
                      fontSize: 11,
                      height: 1.25,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 4),
          const Icon(
            Icons.arrow_forward_rounded,
            color: WellarTheme.textMuted,
            size: 16,
          ),
        ],
      ),
    );
  }
}

class MiniTrendCard extends StatelessWidget {
  final String title;
  final String current;
  final String details;
  final double score;

  const MiniTrendCard({
    super.key,
    required this.title,
    required this.current,
    required this.details,
    required this.score,
  });

  @override
  Widget build(BuildContext context) {
    final normalized = score.clamp(0.0, 1.0);
    return OwnerSurfaceCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: WellarTheme.textMuted,
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            current,
            style: const TextStyle(
              color: WellarTheme.text,
              fontWeight: FontWeight.w800,
              fontSize: 20,
            ),
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(99),
            child: LinearProgressIndicator(
              minHeight: 6,
              value: normalized,
              color: const Color(0xFF49D3C2),
              backgroundColor: const Color(0x223A4A6D),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            details,
            style: const TextStyle(color: WellarTheme.textMuted, fontSize: 11),
          ),
        ],
      ),
    );
  }
}

class AlertSummaryCard extends StatelessWidget {
  final String title;
  final int count;
  final IconData icon;
  final VoidCallback? onTap;

  const AlertSummaryCard({
    super.key,
    required this.title,
    required this.count,
    required this.icon,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isZero = count == 0;
    return OwnerSurfaceCard(
      onTap: onTap,
      padding: const EdgeInsets.all(14),
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          const Color(0xFF131F37),
          isZero ? const Color(0xFF102231) : const Color(0xFF24182A),
        ],
      ),
      child: Row(
        children: [
          Icon(
            icon,
            color: isZero ? const Color(0xFF6EE7A8) : const Color(0xFFFF7A8F),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              title,
              style: const TextStyle(
                color: WellarTheme.textMuted,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Text(
            '$count',
            style: const TextStyle(
              color: WellarTheme.text,
              fontSize: 22,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class ComplianceRing extends StatelessWidget {
  final double score;
  final String label;

  const ComplianceRing({super.key, required this.score, required this.label});

  @override
  Widget build(BuildContext context) {
    final clamped = score.clamp(0.0, 1.0);
    return SizedBox(
      width: 110,
      height: 110,
      child: Stack(
        alignment: Alignment.center,
        children: [
          CustomPaint(
            size: const Size(110, 110),
            painter: _RingPainter(progress: clamped),
          ),
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                '${(clamped * 100).round()}%',
                style: const TextStyle(
                  color: WellarTheme.text,
                  fontWeight: FontWeight.w800,
                  fontSize: 24,
                ),
              ),
              Text(
                label,
                style: const TextStyle(
                  color: WellarTheme.textMuted,
                  fontSize: 11,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class SmartEmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final String? actionLabel;
  final VoidCallback? onAction;

  const SmartEmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    this.actionLabel,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    return OwnerSurfaceCard(
      padding: const EdgeInsets.all(18),
      child: Column(
        children: [
          Icon(icon, color: WellarTheme.textMuted, size: 28),
          const SizedBox(height: 10),
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: WellarTheme.text,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: WellarTheme.textMuted,
              fontSize: 12,
              height: 1.3,
            ),
          ),
          if (actionLabel != null && onAction != null) ...[
            const SizedBox(height: 12),
            TextButton(onPressed: onAction, child: Text(actionLabel!)),
          ],
        ],
      ),
    );
  }
}

Future<T?> showPremiumBottomSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool isScrollControlled = true,
}) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: isScrollControlled,
    backgroundColor: Colors.transparent,
    builder: (ctx) {
      return Container(
        decoration: const BoxDecoration(
          color: Color(0xFF0F172A),
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          border: Border(top: BorderSide(color: Color(0xFF273555))),
        ),
        child: SafeArea(top: false, child: builder(ctx)),
      );
    },
  );
}

Widget _pill(
  String text,
  Color color, {
  double fontSize = 10.5,
  EdgeInsetsGeometry padding = const EdgeInsets.symmetric(
    horizontal: 10,
    vertical: 4,
  ),
}) {
  return Container(
    padding: padding,
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.14),
      borderRadius: BorderRadius.circular(999),
      border: Border.all(color: color.withValues(alpha: 0.45)),
    ),
    child: Text(
      text,
      style: TextStyle(
        color: color,
        fontSize: fontSize,
        fontWeight: FontWeight.w700,
      ),
    ),
  );
}

String _title(String raw) {
  if (raw.isEmpty) return raw;
  return raw[0].toUpperCase() + raw.substring(1).toLowerCase();
}

String _initials(String raw) {
  final words = raw
      .trim()
      .split(RegExp(r'\s+'))
      .where((part) => part.isNotEmpty)
      .toList();
  if (words.isEmpty) return '?';
  if (words.length == 1) {
    final word = words.first;
    return word.length >= 2
        ? word.substring(0, 2).toUpperCase()
        : word.toUpperCase();
  }
  return (words.first[0] + words.last[0]).toUpperCase();
}

class _RingPainter extends CustomPainter {
  final double progress;

  _RingPainter({required this.progress});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = math.min(size.width, size.height) / 2 - 8;

    final track = Paint()
      ..color = const Color(0x223A4A6D)
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 10;
    canvas.drawCircle(center, radius, track);

    final ring = Paint()
      ..shader = const SweepGradient(
        colors: [Color(0xFF49D3C2), Color(0xFF58A6FF), Color(0xFF49D3C2)],
        startAngle: -math.pi / 2,
        endAngle: 3 * math.pi / 2,
      ).createShader(Rect.fromCircle(center: center, radius: radius))
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 10;
    final start = -math.pi / 2;
    final sweep = 2 * math.pi * progress;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      start,
      sweep,
      false,
      ring,
    );
  }

  @override
  bool shouldRepaint(covariant _RingPainter oldDelegate) {
    return oldDelegate.progress != progress;
  }
}

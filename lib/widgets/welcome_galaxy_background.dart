import 'dart:math' as math;

import 'package:flutter/material.dart';

const _galaxyTeal = Color(0xFF12B892);
const _galaxyDeepTeal = Color(0xFF0B7A63);

class WelcomeGalaxyBackground extends StatefulWidget {
  final bool reduceMotion;

  const WelcomeGalaxyBackground({super.key, required this.reduceMotion});

  @override
  State<WelcomeGalaxyBackground> createState() =>
      _WelcomeGalaxyBackgroundState();
}

class _WelcomeGalaxyBackgroundState extends State<WelcomeGalaxyBackground>
    with SingleTickerProviderStateMixin {
  late final AnimationController _motion;
  bool _systemReduceMotion = false;

  bool get _isStatic => widget.reduceMotion || _systemReduceMotion;

  @override
  void initState() {
    super.initState();
    _motion = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 16),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduce = MediaQuery.disableAnimationsOf(context);
    if (_systemReduceMotion == reduce && (_motion.isAnimating || reduce)) {
      return;
    }
    _systemReduceMotion = reduce;
    if (_isStatic) {
      _motion.stop();
      _motion.value = 0;
    } else {
      _motion.repeat();
    }
  }

  @override
  void didUpdateWidget(covariant WelcomeGalaxyBackground oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.reduceMotion != widget.reduceMotion) {
      if (_isStatic) {
        _motion.stop();
        _motion.value = 0;
      } else {
        _motion.repeat();
      }
    }
  }

  @override
  void dispose() {
    _motion.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_isStatic) {
      return const DecoratedBox(
        decoration: BoxDecoration(
          gradient: RadialGradient(
            center: Alignment(0, -0.2),
            radius: 1.25,
            colors: [Color(0xFF092523), Color(0xFF07131C), Color(0xFF03070D)],
            stops: [0, .48, 1],
          ),
        ),
        child: SizedBox.expand(),
      );
    }
    return Positioned.fill(
      child: RepaintBoundary(
        child: CustomPaint(painter: _GalaxyPainter(_motion)),
      ),
    );
  }
}

class _GalaxyStar {
  final double x;
  final double y;
  final double radius;
  final double opacity;
  final double drift;
  final double phase;

  const _GalaxyStar(
    this.x,
    this.y,
    this.radius,
    this.opacity,
    this.drift,
    this.phase,
  );
}

class _GalaxyPainter extends CustomPainter {
  final Animation<double> animation;
  static final List<_GalaxyStar> _stars = _createStars();

  _GalaxyPainter(this.animation) : super(repaint: animation);

  static List<_GalaxyStar> _createStars() {
    final random = math.Random(40621);
    return List.generate(
      52,
      (_) => _GalaxyStar(
        random.nextDouble(),
        random.nextDouble(),
        .55 + random.nextDouble() * 1.25,
        .22 + random.nextDouble() * .58,
        .008 + random.nextDouble() * .026,
        random.nextDouble() * math.pi * 2,
      ),
    );
  }

  @override
  void paint(Canvas canvas, Size size) {
    final bounds = Offset.zero & size;
    canvas.drawRect(
      bounds,
      Paint()
        ..shader = const RadialGradient(
          center: Alignment(0, -.18),
          radius: 1.25,
          colors: [Color(0xFF092523), Color(0xFF07131C), Color(0xFF03070D)],
          stops: [0, .48, 1],
        ).createShader(bounds),
    );

    final t = animation.value * math.pi * 2;
    _paintGlow(
      canvas,
      Offset(
        size.width * (.18 + .06 * math.sin(t)),
        size.height * (.25 + .04 * math.cos(t * .7)),
      ),
      size.shortestSide * .62,
      _galaxyTeal,
      .19 + .025 * math.sin(t + .8),
    );
    _paintGlow(
      canvas,
      Offset(
        size.width * (.83 + .055 * math.cos(t * .64)),
        size.height * (.68 + .035 * math.sin(t * .9)),
      ),
      size.shortestSide * .66,
      _galaxyDeepTeal,
      .17 + .025 * math.cos(t + .5),
    );
    _paintGlow(
      canvas,
      Offset(
        size.width * (.79 + .045 * math.sin(t * .48 + 1)),
        size.height * (.20 + .04 * math.cos(t * .52)),
      ),
      size.shortestSide * .52,
      const Color(0xFF7163C9),
      .11 + .018 * math.sin(t * .75),
    );

    for (final star in _stars) {
      final x = (star.x + animation.value * star.drift) % 1;
      final y = (star.y + animation.value * star.drift * .32) % 1;
      final twinkle = .72 + .28 * math.sin(t * 1.4 + star.phase);
      final paint = Paint()
        ..color = Colors.white.withValues(alpha: star.opacity * twinkle)
        ..isAntiAlias = true;
      canvas.drawCircle(
        Offset(x * size.width, y * size.height),
        star.radius,
        paint,
      );
    }
    _paintShootingStar(canvas, size, animation.value);
  }

  void _paintGlow(
    Canvas canvas,
    Offset center,
    double radius,
    Color color,
    double opacity,
  ) {
    final rect = Rect.fromCircle(center: center, radius: radius);
    final shader = RadialGradient(
      colors: [
        color.withValues(alpha: opacity),
        color.withValues(alpha: 0),
      ],
      stops: const [0, 1],
    ).createShader(rect);
    canvas.drawCircle(center, radius, Paint()..shader = shader);
  }

  void _paintShootingStar(Canvas canvas, Size size, double progress) {
    final cycle = (progress * 16 / 5.4) % 1;
    if (cycle > .075) return;
    final phase = cycle / .075;
    final x = size.width * (.12 + phase * .86);
    final y = size.height * (.16 + phase * .31);
    final fade = math.sin(phase * math.pi).clamp(0.0, 1.0);
    final length = size.shortestSide * .10;
    final paint = Paint()
      ..strokeWidth = 1.25
      ..strokeCap = StrokeCap.round
      ..shader = LinearGradient(
        colors: [
          Colors.white.withValues(alpha: .68 * fade),
          Colors.transparent,
        ],
      ).createShader(Rect.fromLTWH(x - length, y - length * .24, length, 2));
    canvas.drawLine(Offset(x, y), Offset(x - length, y - length * .24), paint);
  }

  @override
  bool shouldRepaint(covariant _GalaxyPainter oldDelegate) =>
      oldDelegate.animation != animation;
}

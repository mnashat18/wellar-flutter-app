import 'dart:math';
import 'package:flutter/material.dart';
import '../utils/app_colors.dart';

class GoogleMark extends StatelessWidget {
  final double size;

  const GoogleMark({super.key, this.size = 20});

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size.square(size),
      painter: _GoogleMarkPainter(),
    );
  }
}

class _GoogleMarkPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final stroke = size.width * 0.16;
    final rect = Rect.fromLTWH(
      stroke / 2,
      stroke / 2,
      size.width - stroke,
      size.height - stroke,
    );

    const colors = [
      AppColors.googleBlue,
      AppColors.googleRed,
      AppColors.googleYellow,
      AppColors.googleGreen,
    ];

    final gap = 0.18;
    final sweep = (2 * pi - (gap * colors.length)) / colors.length;
    var start = -pi / 2 - sweep * 0.15;

    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round;

    for (final color in colors) {
      paint.color = color;
      canvas.drawArc(rect, start, sweep, false, paint);
      start += sweep + gap;
    }

    final barPaint = Paint()
      ..color = AppColors.googleBlue
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round;

    final center = size.center(Offset.zero);
    canvas.drawLine(
      Offset(center.dx, center.dy),
      Offset(size.width - stroke, center.dy),
      barPaint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

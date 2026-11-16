import 'dart:ui' show PathMetric;

import 'package:flutter/material.dart';

/// Paints a dashed rounded outline around [child]. Used for the reminder block,
/// the hidden-task notice and the Add subtask button.
class DashedBorder extends StatelessWidget {
  const DashedBorder({
    super.key,
    required this.color,
    required this.child,
    this.radius = 12,
    this.fill,
    this.padding = EdgeInsets.zero,
    this.strokeWidth = 1,
  });

  final Color color;
  final Widget child;
  final double radius;
  final Color? fill;
  final EdgeInsetsGeometry padding;
  final double strokeWidth;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _DashedPainter(
        color: color,
        radius: radius,
        fill: fill,
        strokeWidth: strokeWidth,
      ),
      child: Padding(padding: padding, child: child),
    );
  }
}

class _DashedPainter extends CustomPainter {
  _DashedPainter({
    required this.color,
    required this.radius,
    required this.fill,
    required this.strokeWidth,
  });

  final Color color;
  final double radius;
  final Color? fill;
  final double strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = RRect.fromRectAndRadius(
      Offset.zero & size,
      Radius.circular(radius),
    ).deflate(strokeWidth / 2);
    if (fill != null) {
      canvas.drawRRect(rect, Paint()..color = fill!);
    }
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth;
    final path = Path()..addRRect(rect);
    for (final PathMetric metric in path.computeMetrics()) {
      var distance = 0.0;
      while (distance < metric.length) {
        final end = (distance + 5).clamp(0.0, metric.length);
        canvas.drawPath(metric.extractPath(distance, end), paint);
        distance += 9;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DashedPainter old) =>
      old.color != color ||
      old.radius != radius ||
      old.fill != fill ||
      old.strokeWidth != strokeWidth;
}

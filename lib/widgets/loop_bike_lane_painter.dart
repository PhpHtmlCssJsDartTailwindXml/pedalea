import 'package:flutter/material.dart';

/// Ciclovía en forma de lazo/óvalo con curvas que se dibuja progresivamente
/// (0.0 a 1.0) alrededor de un contenido central, como si se estuviera
/// trazando en tiempo real.
class LoopBikeLanePainter extends CustomPainter {
  final Color color;
  final double strokeWidth;
  final double progress;

  const LoopBikeLanePainter({
    required this.color,
    required this.progress,
    this.strokeWidth = 3,
  });

  Path _buildLoopPath(Size size) {
    final w = size.width;
    final h = size.height;
    return Path()
      ..moveTo(w * 0.5, h * 0.02)
      ..quadraticBezierTo(w * 0.92, h * 0.02, w * 0.98, h * 0.5)
      ..quadraticBezierTo(w * 1.02, h * 0.85, w * 0.62, h * 0.98)
      ..quadraticBezierTo(w * 0.5, h * 1.02, w * 0.38, h * 0.98)
      ..quadraticBezierTo(w * -0.02, h * 0.85, w * 0.02, h * 0.5)
      ..quadraticBezierTo(w * 0.08, h * 0.02, w * 0.5, h * 0.02);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final fullPath = _buildLoopPath(size);
    final paint = Paint()
      ..color = color
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    final dashLength = strokeWidth * 5.3;
    final gap = strokeWidth * 4;

    for (final metric in fullPath.computeMetrics()) {
      final drawLength = metric.length * progress;
      double distance = 0;
      while (distance < drawLength) {
        final next = (distance + dashLength).clamp(0, drawLength);
        canvas.drawPath(
          metric.extractPath(distance, next.toDouble()),
          paint,
        );
        distance += dashLength + gap;
      }
    }
  }

  @override
  bool shouldRepaint(covariant LoopBikeLanePainter oldDelegate) =>
      oldDelegate.progress != progress ||
      oldDelegate.color != color ||
      oldDelegate.strokeWidth != strokeWidth;
}

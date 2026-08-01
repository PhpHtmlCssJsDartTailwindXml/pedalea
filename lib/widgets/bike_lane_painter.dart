import 'package:flutter/material.dart';

/// Ruta segmentada decorativa que serpentea por todo el lienzo de fondo
/// (demarcación de ciclovía), de esquina a esquina. Se usa como motivo de
/// marca en el login y en las tarjetas de compartir.
class BikeLanePainter extends CustomPainter {
  final Color color;
  final double strokeWidth;
  const BikeLanePainter({required this.color, this.strokeWidth = 3});

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final path = Path()
      ..moveTo(-30, h * 0.06)
      ..quadraticBezierTo(w * 0.55, h * 0.01, w * 0.92, h * 0.16)
      ..quadraticBezierTo(w * 1.15, h * 0.28, w * 0.62, h * 0.40)
      ..quadraticBezierTo(w * 0.10, h * 0.52, w * 0.58, h * 0.66)
      ..quadraticBezierTo(w * 0.95, h * 0.79, w * 0.42, h * 0.93)
      ..quadraticBezierTo(w * 0.12, h * 1.01, w * 0.30, h * 1.10);

    final paint = Paint()
      ..color = color
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    final dashLength = strokeWidth * 5.3;
    final gap = strokeWidth * 4;

    for (final metric in path.computeMetrics()) {
      double distance = 0;
      while (distance < metric.length) {
        final next = (distance + dashLength).clamp(0, metric.length);
        canvas.drawPath(
          metric.extractPath(distance, next.toDouble()),
          paint,
        );
        distance += dashLength + gap;
      }
    }
  }

  @override
  bool shouldRepaint(covariant BikeLanePainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.strokeWidth != strokeWidth;
}

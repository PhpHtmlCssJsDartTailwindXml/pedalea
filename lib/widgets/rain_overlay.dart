import 'dart:math';
import 'package:flutter/material.dart';

/// Overlay de gotas de lluvia cayendo, para mostrar sobre el mapa cuando
/// el clima detectado (WeatherData.isRaining) indica lluvia.
class RainOverlay extends StatefulWidget {
  final bool heavy;
  const RainOverlay({super.key, this.heavy = false});

  @override
  State<RainOverlay> createState() => _RainOverlayState();
}

class _Drop {
  double x; // 0..1 relativo al ancho
  double y; // 0..1 relativo al alto
  double length;
  double speed;
  double opacity;

  _Drop({
    required this.x,
    required this.y,
    required this.length,
    required this.speed,
    required this.opacity,
  });
}

class _RainOverlayState extends State<RainOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  final _random = Random();
  final List<_Drop> _drops = [];

  int get _dropCount => widget.heavy ? 140 : 70;

  @override
  void initState() {
    super.initState();
    _drops.addAll(List.generate(_dropCount, (_) => _newDrop(randomY: true)));
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(days: 1), // se maneja con addListener, no repeat por ciclo fijo
    )..addListener(_tick);
    _controller.repeat();
  }

  _Drop _newDrop({bool randomY = false}) {
    return _Drop(
      x: _random.nextDouble(),
      y: randomY ? _random.nextDouble() : -0.05,
      length: 10 + _random.nextDouble() * (widget.heavy ? 18 : 12),
      speed: 0.006 + _random.nextDouble() * (widget.heavy ? 0.012 : 0.008),
      opacity: 0.25 + _random.nextDouble() * 0.35,
    );
  }

  void _tick() {
    if (!mounted) return;
    setState(() {
      for (final drop in _drops) {
        drop.y += drop.speed;
        if (drop.y > 1.05) {
          drop.y = -0.05;
          drop.x = _random.nextDouble();
        }
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: CustomPaint(
        painter: _RainPainter(_drops),
        size: Size.infinite,
      ),
    );
  }
}

class _RainPainter extends CustomPainter {
  final List<_Drop> drops;
  _RainPainter(this.drops);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white
      ..strokeWidth = 1.6
      ..strokeCap = StrokeCap.round;

    for (final drop in drops) {
      final startX = drop.x * size.width;
      final startY = drop.y * size.height;
      paint.color = Colors.lightBlueAccent.withOpacity(drop.opacity);
      canvas.drawLine(
        Offset(startX, startY),
        Offset(startX - drop.length * 0.18, startY + drop.length),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _RainPainter oldDelegate) => true;
}

import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_compass/flutter_compass.dart';

/// Calibración real del magnetómetro: muestra el heading en vivo y la
/// precisión reportada por el sensor (FlutterCompass.events.accuracy),
/// y guía al usuario a mover el celular en forma de "8" —el patrón
/// estándar que usan Android/iOS para recalibrar el magnetómetro, ya
/// que el sistema operativo no expone una API para forzarlo por código.
class CompassCalibrationPage extends StatefulWidget {
  const CompassCalibrationPage({super.key});

  @override
  State<CompassCalibrationPage> createState() =>
      _CompassCalibrationPageState();
}

enum _CalibQuality { unknown, poor, medium, good }

class _CompassCalibrationPageState extends State<CompassCalibrationPage>
    with SingleTickerProviderStateMixin {
  StreamSubscription<CompassEvent>? _sub;
  double? _heading;
  late final AnimationController _figureEightController;

  // Guarda el mejor (menor) accuracy visto en esta sesión de calibración,
  // para poder mostrar progreso aunque el sensor oscile.
  double? _bestAccuracy;

  @override
  void initState() {
    super.initState();
    _figureEightController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )..repeat();
    _sub = FlutterCompass.events?.listen((event) {
      if (!mounted) return;
      setState(() {
        _heading = event.heading;
        final accuracy = event.accuracy;
        if (accuracy != null) {
          _bestAccuracy = _bestAccuracy == null
              ? accuracy
              : min(_bestAccuracy!, accuracy);
        }
      });
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    _figureEightController.dispose();
    super.dispose();
  }

  _CalibQuality get _quality {
    final acc = _bestAccuracy;
    if (acc == null) return _CalibQuality.unknown;
    if (acc <= 10) return _CalibQuality.good;
    if (acc <= 25) return _CalibQuality.medium;
    return _CalibQuality.poor;
  }

  Color get _qualityColor {
    switch (_quality) {
      case _CalibQuality.good:
        return const Color(0xFF7CF0BC);
      case _CalibQuality.medium:
        return Colors.orangeAccent;
      case _CalibQuality.poor:
        return Colors.redAccent;
      case _CalibQuality.unknown:
        return Colors.white38;
    }
  }

  String get _qualityLabel {
    switch (_quality) {
      case _CalibQuality.good:
        return 'Precisión buena';
      case _CalibQuality.medium:
        return 'Precisión media — sigue moviendo el celular';
      case _CalibQuality.poor:
        return 'Precisión baja — necesita calibración';
      case _CalibQuality.unknown:
        return 'Leyendo sensor…';
    }
  }

  // Trazo de Lissajous (a=1, b=2) que dibuja un "8" acostado, usado tanto
  // por el painter del trazo como para ubicar el ícono del celular sobre
  // la línea.
  Offset _figureEightPoint(double progress, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;
    final rx = size.width / 2.4;
    final ry = size.height / 3.2;
    final t = 2 * pi * progress;
    return Offset(cx + rx * sin(t), cy + ry * sin(2 * t));
  }

  @override
  Widget build(BuildContext context) {
    final heading = _heading ?? 0;
    return Scaffold(
      backgroundColor: const Color(0xFF08080F),
      appBar: AppBar(
        backgroundColor: const Color(0xFF08080F),
        elevation: 0,
        title: const Text(
          'Calibrar brújula',
          style: TextStyle(fontFamily: 'Poppins', color: Colors.white),
        ),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          child: Column(
            children: [
              // ── Brújula en vivo ────────────────────────────────────────
              Expanded(
                flex: 4,
                child: Center(
                  child: SizedBox(
                    width: 220,
                    height: 220,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        Container(
                          width: 220,
                          height: 220,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: _qualityColor.withOpacity(0.5),
                              width: 2,
                            ),
                            color: Colors.white.withOpacity(0.03),
                          ),
                        ),
                        AnimatedRotation(
                          turns: -heading / 360,
                          duration: const Duration(milliseconds: 150),
                          child: Icon(
                            Icons.navigation_rounded,
                            size: 90,
                            color: _qualityColor,
                          ),
                        ),
                        Positioned(
                          bottom: 12,
                          child: Text(
                            _heading == null
                                ? '--°'
                                : '${_heading!.toStringAsFixed(0)}°',
                            style: const TextStyle(
                              fontFamily: 'Poppins',
                              color: Colors.white70,
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              // ── Estado de precisión ────────────────────────────────────
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.gps_fixed_rounded, color: _qualityColor, size: 16),
                  const SizedBox(width: 8),
                  Text(
                    _qualityLabel,
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      color: _qualityColor,
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
              if (_bestAccuracy != null) ...[
                const SizedBox(height: 4),
                Text(
                  'Error estimado: ±${_bestAccuracy!.toStringAsFixed(0)}°',
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    color: Colors.grey[500],
                    fontSize: 12,
                  ),
                ),
              ],
              const SizedBox(height: 24),
              // ── Animación guía en forma de 8, con un ícono de celular
              // recorriendo el trazo para mostrar cómo moverlo ──────────
              SizedBox(
                height: 70,
                width: 70,
                child: AnimatedBuilder(
                  animation: _figureEightController,
                  builder: (_, _) {
                    const size = Size(70, 70);
                    final t = _figureEightController.value;
                    final pos = _figureEightPoint(t, size);
                    final tangent = _figureEightPoint((t + 0.01) % 1.0, size);
                    final angle = atan2(
                      tangent.dy - pos.dy,
                      tangent.dx - pos.dx,
                    );
                    return Stack(
                      alignment: Alignment.center,
                      children: [
                        CustomPaint(
                          painter: _FigureEightPainter(color: _qualityColor),
                          size: size,
                        ),
                        Positioned(
                          left: pos.dx - 9,
                          top: pos.dy - 9,
                          child: Transform.rotate(
                            angle: angle,
                            child: Icon(
                              Icons.smartphone_rounded,
                              size: 18,
                              color: _qualityColor,
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'Mueve tu celular dibujando un "8" en el aire, '
                'como se ve arriba, durante unos segundos.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: 'Poppins',
                  color: Colors.white70,
                  fontSize: 13,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Aléjate de imanes, parlantes o soportes metálicos: '
                'suelen ser la causa de una brújula imprecisa.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: 'Poppins',
                  color: Colors.grey[500],
                  fontSize: 11,
                ),
              ),
              const Spacer(),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _quality == _CalibQuality.good
                        ? const Color(0xFF7CF0BC)
                        : Colors.white12,
                    foregroundColor: _quality == _CalibQuality.good
                        ? const Color(0xFF08080F)
                        : Colors.white70,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  onPressed: () => Navigator.pop(context),
                  child: Text(
                    _quality == _CalibQuality.good
                        ? 'Listo, calibración buena'
                        : 'Salir',
                    style: const TextStyle(
                      fontFamily: 'Poppins',
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FigureEightPainter extends CustomPainter {
  final Color color;
  _FigureEightPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path();
    final cx = size.width / 2;
    final cy = size.height / 2;
    final rx = size.width / 2.4;
    final ry = size.height / 3.2;

    // Curva de Lissajous (a=1, b=2) dibuja un "8" acostado.
    const steps = 120;
    for (int i = 0; i <= steps; i++) {
      final t = 2 * pi * i / steps;
      final x = cx + rx * sin(t);
      final y = cy + ry * sin(2 * t);
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }

    canvas.drawPath(
      path,
      Paint()
        ..color = color.withOpacity(0.25)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
  }

  @override
  bool shouldRepaint(covariant _FigureEightPainter oldDelegate) =>
      oldDelegate.color != color;
}

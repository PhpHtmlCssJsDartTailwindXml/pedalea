import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:pedalea/services/fall_detection_service.dart';

/// Simula sensores: acelerómetro cada 50 ms y GPS cada 1 s.
class _Sim {
  final a = FallAnalyzer();
  DateTime t = DateTime(2026, 1, 1, 12);

  static const upright = [0.0, 9.8, 0.0]; // teléfono vertical (bolsillo/soporte)
  static const lying = [9.8, 0.0, 0.0]; // teléfono de lado (en el suelo)

  /// Avanza [ms] con la orientación [acc], un temblor [jitter] y la
  /// velocidad [kmh] (null = sin GPS). Si [evaluate], devuelve la primera
  /// decisión del analizador.
  FallEvidence? feed(
    int ms, {
    List<double> acc = upright,
    double jitter = 0.6,
    double? kmh = 18,
    bool evaluate = false,
    double? gyro,
  }) {
    for (var i = 0; i < ms; i += 50) {
      final j = jitter * math.sin(i / 37.0);
      a.addAccel(acc[0] + j, acc[1] + j, acc[2], t);
      if (gyro != null) a.addGyro(0, 0, gyro, t);
      if (kmh != null && i % 1000 == 0) a.addSpeed(kmh, t);
      t = t.add(const Duration(milliseconds: 50));
      if (evaluate) {
        final ev = a.evaluate(t);
        if (ev != null) return ev;
      }
    }
    return null;
  }

  FallEvidence? hit(FallTrigger trigger, {double peak = 40}) =>
      a.startCandidate(trigger, t, peak: peak);
}

void main() {
  group('FallAnalyzer: se confirma', () {
    test('caída real: pedaleando, golpe, quedas de lado y quieto', () {
      final s = _Sim()..feed(8000);
      expect(s.hit(FallTrigger.impact), isNull); // queda en observación
      final ev = s.feed(9000, acc: _Sim.lying, jitter: 0.05, kmh: 0, evaluate: true);
      expect(ev, isNotNull);
      expect(ev!.confirmed, isTrue);
      expect(ev.reason, 'caida_confirmada');
      expect(ev.orientationChangeDeg, greaterThan(80));
      expect(ev.speedBeforeKmh, 18);
    });

    test('frenada imposible y la bici cae (teléfono en el manubrio gira)', () {
      final s = _Sim()..feed(8000, kmh: 22);
      s.hit(FallTrigger.suddenStop);
      final ev = s.feed(9000, acc: _Sim.lying, jitter: 0.4, kmh: 0, evaluate: true);
      expect(ev!.confirmed, isTrue);
    });

    test('impacto con giro brusco y quietud, aunque no cambie la orientación', () {
      final s = _Sim()..feed(8000);
      s.feed(500, gyro: 7); // giro fuerte justo antes del golpe
      s.hit(FallTrigger.impact);
      final ev = s.feed(9000, jitter: 0.05, kmh: 0, evaluate: true);
      expect(ev!.confirmed, isTrue);
    });

    test('sin GPS: golpe seco, de lado y quieto (modo estricto)', () {
      final s = _Sim()..feed(8000, kmh: null);
      s.hit(FallTrigger.hardImpact, peak: 60);
      final ev = s.feed(9000, acc: _Sim.lying, jitter: 0.05, kmh: null, evaluate: true);
      expect(ev!.confirmed, isTrue);
      expect(ev.strict, isTrue);
    });
  });

  group('FallAnalyzer: falsas alarmas descartadas', () {
    test('teléfono soltado o golpeado sin ir pedaleando', () {
      final s = _Sim()..feed(8000, kmh: 0, jitter: 0.05);
      final ev = s.hit(FallTrigger.hardImpact, peak: 60);
      expect(ev, isNotNull);
      expect(ev!.confirmed, isFalse);
      expect(ev.reason, 'no_pedaleando');
      expect(s.a.hasPending, isFalse);
    });

    test('caminando con el teléfono (3-5 km/h) no cuenta como pedaleo', () {
      final s = _Sim()..feed(8000, kmh: 4);
      expect(s.hit(FallTrigger.impact)!.reason, 'no_pedaleando');
    });

    test('bache: golpe fuerte pero sigues pedaleando', () {
      final s = _Sim()..feed(8000);
      s.hit(FallTrigger.hardImpact, peak: 55);
      final ev = s.feed(9000, kmh: 18, evaluate: true);
      expect(ev!.confirmed, isFalse);
      expect(ev.reason, 'siguio_pedaleando');
    });

    test('frenada fuerte en un semáforo: te detienes de pie', () {
      final s = _Sim()..feed(8000, kmh: 22);
      s.hit(FallTrigger.suddenStop);
      final ev = s.feed(9000, kmh: 0, jitter: 0.6, evaluate: true);
      expect(ev!.confirmed, isFalse);
      expect(ev.reason, 'frenada_sin_caida');
    });

    test('golpe seco y luego te detienes de pie (sin girar ni caer)', () {
      final s = _Sim()..feed(8000);
      s.hit(FallTrigger.hardImpact, peak: 55);
      final ev = s.feed(9000, kmh: 0, jitter: 1.2, evaluate: true);
      expect(ev!.confirmed, isFalse);
      expect(ev.reason, 'sin_senales_fisicas');
    });

    test('impacto, te detienes quieto pero sin giro ni cambio de posición', () {
      final s = _Sim()..feed(8000);
      s.hit(FallTrigger.impact);
      final ev = s.feed(9000, kmh: 0, jitter: 0.05, evaluate: true);
      expect(ev!.confirmed, isFalse);
    });

    test('sin GPS y el teléfono sigue vertical: no se alerta', () {
      final s = _Sim()..feed(8000, kmh: null);
      s.hit(FallTrigger.hardImpact, peak: 60);
      final ev = s.feed(9000, jitter: 0.05, kmh: null, evaluate: true);
      expect(ev!.confirmed, isFalse);
      expect(ev.reason, 'sin_gps_pocas_senales');
    });

    test('frenada del GPS sin datos de GPS previos se ignora', () {
      final s = _Sim()..feed(8000, kmh: null);
      expect(s.hit(FallTrigger.suddenStop), isNull);
      expect(s.a.hasPending, isFalse);
    });
  });

  group('FallAnalyzer: tiempos', () {
    test('no decide antes de terminar la ventana de observación', () {
      final s = _Sim()..feed(8000);
      s.hit(FallTrigger.impact);
      expect(s.feed(5000, acc: _Sim.lying, jitter: 0.05, kmh: 0, evaluate: true), isNull);
      expect(s.a.hasPending, isTrue);
    });

    test('un segundo golpe durante la observación no reinicia la ventana', () {
      final s = _Sim()..feed(8000);
      s.hit(FallTrigger.impact);
      s.feed(3000, acc: _Sim.lying, jitter: 0.05, kmh: 0);
      expect(s.hit(FallTrigger.hardImpact), isNull);
      final ev = s.feed(5000, acc: _Sim.lying, jitter: 0.05, kmh: 0, evaluate: true);
      expect(ev!.trigger, FallTrigger.impact);
    });

    test('la evidencia se puede serializar para el registro', () {
      final s = _Sim()..feed(8000);
      s.hit(FallTrigger.impact);
      final ev = s.feed(9000, acc: _Sim.lying, jitter: 0.05, kmh: 0, evaluate: true)!;
      final json = ev.toJson();
      expect(json['trigger'], 'impact');
      expect(json['confirmed'], isTrue);
      expect(json.keys, containsAll(['peak_accel', 'speed_before', 'orientation_change']));
    });
  });
}

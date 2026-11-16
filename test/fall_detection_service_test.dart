import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:pedalea/services/fall_detection_service.dart';
import 'package:sensors_plus/sensors_plus.dart';

void main() {
  group('FallDetectionService', () {
    late StreamController<AccelerometerEvent> sensor;
    late StreamController<GyroscopeEvent> gyro;
    late DateTime now;
    late FallDetectionService service;
    late int falls;
    late List<FallEvidence> evidence;

    setUp(() {
      sensor = StreamController<AccelerometerEvent>();
      gyro = StreamController<GyroscopeEvent>();
      now = DateTime(2026, 1, 1, 12);
      falls = 0;
      evidence = [];
      service = FallDetectionService(
        events: sensor.stream,
        gyroEvents: gyro.stream,
        clock: () => now,
        useTimer: false,
      );
    });

    tearDown(() async {
      service.stop();
      await sensor.close();
      await gyro.close();
    });

    void startService() =>
        service.start(() => falls++, onEvidence: evidence.add);

    /// Avanza [ms] enviando muestras cada 50 ms y la velocidad cada 1 s.
    Future<void> feed(
      int ms, {
      double x = 0,
      double y = 9.8,
      double z = 0,
      double? kmh = 18,
      double jitter = 0.6,
    }) async {
      for (var i = 0; i < ms; i += 50) {
        final j = jitter * ((i ~/ 50).isEven ? 1 : -1);
        if (kmh != null && i % 1000 == 0) service.reportSpeed(kmh);
        sensor.add(AccelerometerEvent(x + j, y + j, z, now));
        await Future<void>.delayed(Duration.zero);
        now = now.add(const Duration(milliseconds: 50));
      }
    }

    Future<void> hit(double mag) async {
      sensor.add(AccelerometerEvent(0, mag, 0, now));
      await Future<void>.delayed(Duration.zero);
      now = now.add(const Duration(milliseconds: 50));
    }

    Future<void> realFall() async {
      await feed(8000); // pedaleando
      await hit(60); // golpe seco
      await feed(9000, x: 9.8, y: 0, kmh: 0, jitter: 0.05); // de lado, quieto
    }

    test('no está activo hasta llamar a start', () {
      expect(service.isRunning, isFalse);
      startService();
      expect(service.isRunning, isTrue);
    });

    test('caída real: avisa una vez y guarda la evidencia', () async {
      startService();
      await realFall();
      expect(falls, 1);
      expect(service.lastEvidence?.confirmed, isTrue);
      expect(evidence.where((e) => e.confirmed), hasLength(1));
    });

    test('el aviso espera la confirmación (no salta en el golpe)', () async {
      startService();
      await feed(8000);
      await hit(60);
      expect(falls, 0);
    });

    test('pedaleo normal no avisa', () async {
      startService();
      await feed(20000);
      expect(falls, 0);
    });

    test('bache: golpe y sigues pedaleando → no avisa', () async {
      startService();
      await feed(8000);
      await hit(60);
      await feed(9000);
      expect(falls, 0);
      expect(evidence.single.reason, 'siguio_pedaleando');
    });

    test('teléfono golpeado estando detenido → no avisa', () async {
      startService();
      await feed(8000, kmh: 0, jitter: 0.05);
      await hit(60);
      await feed(9000, x: 9.8, y: 0, kmh: 0, jitter: 0.05);
      expect(falls, 0);
      expect(evidence.first.reason, 'no_pedaleando');
    });

    test('frenada en semáforo informada por el GPS → no avisa', () async {
      startService();
      await feed(8000, kmh: 22);
      service.reportSuddenStop();
      await feed(9000, kmh: 0);
      expect(falls, 0);
      expect(evidence.single.reason, 'frenada_sin_caida');
    });

    test('frenada del GPS y la bici cae → avisa', () async {
      startService();
      await feed(8000, kmh: 22);
      service.reportSuddenStop();
      await feed(9000, x: 9.8, y: 0, kmh: 0, jitter: 0.05);
      expect(falls, 1);
    });

    test('una segunda caída dentro del enfriamiento (20 s) se ignora', () async {
      startService();
      await realFall();
      await feed(1000, kmh: 18);
      await hit(60);
      await feed(9000, x: 0, y: -9.8, kmh: 0, jitter: 0.05);
      expect(falls, 1);
    });

    test('llamar a start dos veces no duplica la escucha', () async {
      startService();
      startService();
      await realFall();
      expect(falls, 1);
    });

    test('stop detiene la escucha y olvida lo medido', () async {
      startService();
      await feed(8000);
      service.stop();
      expect(service.isRunning, isFalse);
      await hit(60);
      await feed(9000, x: 9.8, y: 0, kmh: 0, jitter: 0.05);
      expect(falls, 0);
    });

    test('un error del sensor no detiene el servicio', () async {
      startService();
      sensor.addError(Exception('sensor no disponible'));
      gyro.addError(Exception('sin giroscopio'));
      await Future<void>.delayed(Duration.zero);
      expect(service.isRunning, isTrue);
      await realFall();
      expect(falls, 1);
    });
  });
}

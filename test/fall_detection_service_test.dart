import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:pedalea/services/fall_detection_service.dart';
import 'package:sensors_plus/sensors_plus.dart';

AccelerometerEvent _ev(double mag) =>
    AccelerometerEvent(0, mag, 0, DateTime(2026));

void main() {
  group('FallDetectionService', () {
    late StreamController<AccelerometerEvent> sensor;
    late DateTime now;
    late FallDetectionService service;
    late int falls;

    setUp(() {
      sensor = StreamController<AccelerometerEvent>();
      now = DateTime(2026, 1, 1, 12);
      falls = 0;
      service = FallDetectionService(events: sensor.stream, clock: () => now);
    });

    tearDown(() async {
      service.stop();
      await sensor.close();
    });

    Future<void> feed(double mag, {int afterMs = 0}) async {
      now = now.add(Duration(milliseconds: afterMs));
      sensor.add(_ev(mag));
      await Future<void>.delayed(Duration.zero);
    }

    test('no está activo hasta llamar a start', () {
      expect(service.isRunning, isFalse);
      service.start(() => falls++);
      expect(service.isRunning, isTrue);
    });

    test('caída libre seguida de impacto avisa una vez', () async {
      service.start(() => falls++);
      await feed(1.0);
      await feed(38.0, afterMs: 400);
      expect(falls, 1);
    });

    test('pedaleo normal no avisa', () async {
      service.start(() => falls++);
      for (var i = 0; i < 20; i++) {
        await feed(9.8 + (i % 3), afterMs: 50);
      }
      expect(falls, 0);
    });

    test('un segundo golpe dentro del enfriamiento (20 s) se ignora', () async {
      service.start(() => falls++);
      await feed(55.0);
      await feed(55.0, afterMs: 5000);
      expect(falls, 1);
    });

    test('pasado el enfriamiento vuelve a avisar', () async {
      service.start(() => falls++);
      await feed(55.0);
      await feed(55.0, afterMs: 21000);
      expect(falls, 2);
    });

    test('llamar a start dos veces no duplica la escucha', () async {
      service.start(() => falls++);
      service.start(() => falls++);
      await feed(55.0);
      expect(falls, 1);
    });

    test('stop detiene la escucha', () async {
      service.start(() => falls++);
      service.stop();
      expect(service.isRunning, isFalse);
      await feed(55.0);
      expect(falls, 0);
    });

    test('un error del sensor no detiene el servicio', () async {
      service.start(() => falls++);
      sensor.addError(Exception('sensor no disponible'));
      await Future<void>.delayed(Duration.zero);
      expect(service.isRunning, isTrue);
      await feed(55.0);
      expect(falls, 1);
    });
  });
}

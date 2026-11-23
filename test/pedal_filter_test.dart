import 'package:flutter_test/flutter_test.dart';
import 'package:pedalea/services/pedal_filter.dart';

/// Simula [seconds] segundos a [kmh] km/h, un tramo por segundo.
PedalChunk? ride(PedalFilter f, DateTime start, int seconds, double Function(int s) kmh) {
  PedalChunk? last;
  for (var s = 0; s < seconds; s++) {
    final v = kmh(s);
    final c = f.add(
      at: start.add(Duration(seconds: s)),
      km: v / 3600,
      speedKmh: v,
      seconds: 1,
    );
    if (c != null) last = c;
  }
  return last;
}

void main() {
  final t0 = DateTime(2026, 11, 23, 8);

  test('un trayecto en bici a 18 km/h cuenta km y velocidad', () {
    final f = PedalFilter();
    final c = ride(f, t0, 120, (_) => 18)!;
    expect(c.accepted, isTrue);
    expect(c.km, closeTo(0.6, 0.001));
    expect(c.maxKmh, closeTo(18, 0.001));
  });

  test('una bajada corta a 42 km/h sigue contando como bici', () {
    final f = PedalFilter();
    // 100 s a 18 km/h y 20 s de bajada a 42 km/h (17% del tiempo)
    final c = ride(f, t0, 120, (s) => s < 100 ? 18 : 42)!;
    expect(c.accepted, isTrue);
    expect(c.maxKmh, closeTo(42, 0.001));
  });

  test('un auto en la ciudad (semáforos, 45 km/h) no cuenta', () {
    final f = PedalFilter();
    // alterna 40 s a 45 km/h y 20 s a 15 km/h (frenando en semáforos)
    final c = ride(f, t0, 120, (s) => s % 60 < 40 ? 45 : 15)!;
    expect(c.accepted, isFalse);
    expect(c.km, 0);
    expect(c.maxKmh, 0);
  });

  test('un solo tramo sobre 60 km/h descarta el bloque', () {
    final f = PedalFilter();
    final c = ride(f, t0, 120, (s) => s == 50 ? 75 : 18)!;
    expect(c.accepted, isFalse);
  });

  test('un salto suelto del GPS no infla la velocidad máxima', () {
    final f = PedalFilter();
    // un pico de 55 km/h de un segundo en un trayecto a 18 km/h
    final c = ride(f, t0, 120, (s) => s == 30 ? 55 : 18)!;
    expect(c.accepted, isTrue);
    expect(c.maxKmh, closeTo(18, 0.001));
  });

  test('confirmar modo pasajero descarta el bloque en curso', () {
    final f = PedalFilter();
    ride(f, t0, 60, (_) => 18);
    expect(f.pendingKm, greaterThan(0));
    f.discard();
    expect(f.pendingKm, 0);
    expect(f.flush(), isNull);
  });

  test('flush evalúa el bloque incompleto al apagar el modo activo', () {
    final f = PedalFilter();
    expect(ride(f, t0, 30, (_) => 15), isNull);
    final c = f.flush()!;
    expect(c.accepted, isTrue);
    expect(c.km, closeTo(0.125, 0.001));
  });
}

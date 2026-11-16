import 'package:flutter_test/flutter_test.dart';
import 'package:pedalea/widgets/rider_activity.dart';

RiderActivity _withDays(Map<String, double> days) => RiderActivity(
  totalKm: 0,
  weekKm: 0,
  monthKm: 0,
  maxSpeed: 0,
  activeDays30: 0,
  streak: 0,
  lastRide: null,
  last14: List.filled(14, 0),
  dailyKm: days,
  karma: 0,
  alerts: 0,
  events: 0,
  memberSince: null,
);

void main() {
  // 2026-11-16 es lunes; la semana va del 16 al 22.
  final a = _withDays({
    '2026-11-15': 7, // domingo de la semana anterior
    '2026-11-16': 5,
    '2026-11-18': 3.5,
    '2026-11-22': 10, // domingo
    '2026-11-23': 4, // lunes siguiente
  });

  test('km de un día', () {
    expect(a.kmOn(DateTime(2026, 11, 18)), 3.5);
    expect(a.kmOn(DateTime(2026, 11, 17)), 0);
  });

  test('semana de lunes a domingo del día elegido', () {
    expect(a.weekKmOf(DateTime(2026, 11, 18)), 18.5);
    expect(a.weekKmOf(DateTime(2026, 11, 22)), 18.5); // domingo, misma semana
    expect(a.weekKmOf(DateTime(2026, 11, 15)), 7); // semana anterior
    expect(a.weekKmOf(DateTime(2026, 11, 23)), 4); // semana siguiente
  });
}

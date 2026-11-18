import 'package:flutter_test/flutter_test.dart';
import 'package:pedalea/services/stats_summary.dart';

void main() {
  // Miércoles 18-11-2026.
  final now = DateTime(2026, 11, 18, 15);
  final data = <String, double>{
    '2026-11-16': 5, // lunes
    '2026-11-17': 3,
    '2026-11-18': 2,
    '2026-11-10': 4, // semana anterior
    '2026-11-11': 4,
    '2026-10-05': 10,
    '2025-12-31': 7,
  };

  test('semana: lunes a domingo y comparación con la anterior', () {
    final s = summarize(data, StatsPeriod.week, now: now);
    expect(s.km, 10);
    expect(s.prevKm, 8);
    expect(s.changePct, closeTo(25, 0.001));
    expect(s.activeDays, 3);
    expect(s.bars.length, 7);
    expect(s.bars.first.km, 5);
    expect(s.bars.last.km, 0);
    expect(s.bestDayKm, 5);
  });

  test('mes: barras por día y mes anterior', () {
    final s = summarize(data, StatsPeriod.month, now: now);
    expect(s.km, 18);
    expect(s.prevKm, 10);
    expect(s.bars.length, 30);
  });

  test('año: barras por mes', () {
    final s = summarize(data, StatsPeriod.year, now: now);
    expect(s.km, 28);
    expect(s.prevKm, 7);
    expect(s.bars.length, 12);
    expect(s.bars[10].km, 18);
    expect(s.bars[9].km, 10);
  });

  test('total: sin comparación, últimos 12 meses', () {
    final s = summarize(data, StatsPeriod.all, now: now);
    expect(s.km, 35);
    expect(s.prevKm, isNull);
    expect(s.changePct, isNull);
    expect(s.bars.length, 12);
    expect(s.bars.last.km, 18);
    expect(s.bars.first.km, 7); // diciembre 2025
  });

  test('récords: mejor día, racha más larga y mejor semana', () {
    final r = records(data);
    expect(r.bestDayKm, 10);
    expect(r.bestDayDate, DateTime(2026, 10, 5));
    expect(r.longestStreak, 3);
    expect(r.longestStreakEnd, DateTime(2026, 11, 18));
    expect(r.bestWeekKm, 10);
  });

  test('sin datos no falla', () {
    final s = summarize({}, StatsPeriod.week, now: now);
    expect(s.km, 0);
    expect(s.changePct, isNull);
    final r = records({});
    expect(r.longestStreak, 0);
    expect(r.bestDayDate, isNull);
  });
}

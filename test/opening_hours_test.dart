import 'dart:io';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:pedalea/services/opening_hours.dart';

// 2026-11-16 es lunes.
DateTime at(int weekday, int h, [int m = 0]) =>
    DateTime(2026, 11, 15 + weekday, h, m);

void main() {
  test('rango de días con dos tramos', () {
    final o = OpeningHours.parse('Mo-Fr 10:00-13:00,15:00-19:00; Sa 10:00-14:00')!;
    expect(o.isOpenAt(at(1, 11)), isTrue);
    expect(o.isOpenAt(at(1, 14)), isFalse); // colación
    expect(o.isOpenAt(at(6, 13, 59)), isTrue);
    expect(o.isOpenAt(at(7, 11)), isFalse); // domingo
    expect(o.dayText(0), '10:00–13:00, 15:00–19:00');
    expect(o.dayText(6), 'Cerrado');
  });

  test('frases de estado', () {
    final o = OpeningHours.parse('Mo-Fr 10:00-13:00,15:00-19:00; Sa 10:00-14:00')!;
    expect(o.status(at(1, 11)).text, 'Abierto · cierra a las 13:00');
    expect(o.status(at(1, 14)).text, 'Cerrado · abre hoy a las 15:00');
    expect(o.status(at(1, 20)).text, 'Cerrado · abre mañana a las 10:00');
    expect(o.status(at(6, 15)).text, 'Cerrado · abre el lunes a las 10:00');
    expect(o.status(at(6, 15)).open, isFalse);
  });

  test('24/7 y «desde las HH:MM»', () {
    expect(OpeningHours.parse('24/7')!.status(at(3, 3)).text, 'Abierto las 24 horas');
    final o = OpeningHours.parse('Mo-Su,PH 08:00+')!;
    expect(o.isOpenAt(at(2, 23, 30)), isTrue);
    expect(o.isOpenAt(at(2, 7)), isFalse);
  });

  test('cruza la medianoche', () {
    final o = OpeningHours.parse('Fr 20:00-02:00')!;
    expect(o.isOpenAt(at(5, 23)), isTrue);
    expect(o.isOpenAt(at(6, 1)), isTrue);
    expect(o.isOpenAt(at(6, 3)), isFalse);
    expect(o.status(at(5, 23)).text, 'Abierto · cierra el sábado a las 02:00');
  });

  test('rango que da la vuelta a la semana y espacios raros', () {
    final o = OpeningHours.parse('Su-Fr 09:30-19:30; Sa 15:30- 19:00')!;
    expect(o.isOpenAt(at(7, 10)), isTrue);
    expect(o.isOpenAt(at(6, 16)), isTrue);
    expect(o.isOpenAt(at(6, 10)), isFalse);
  });

  test('coma antes de un día inicia otra regla', () {
    final o = OpeningHours.parse('Mo-Fr 11:00-15:00,16:00-20:00, Sa 10:00-16:00')!;
    expect(o.isOpenAt(at(6, 12)), isTrue);
    expect(o.isOpenAt(at(1, 15, 30)), isFalse);
  });

  test('closed y feriados', () {
    final o = OpeningHours.parse('Mo-Fr 10:00-20:00; Sa 10:00-16:00; PH closed')!;
    expect(o.isOpenAt(at(1, 12)), isTrue);
    expect(o.dayText(6), 'Cerrado');
  });

  test('texto que no se entiende devuelve null', () {
    expect(OpeningHours.parse('consultar por teléfono'), isNull);
    expect(OpeningHours.parse(''), isNull);
  });

  test('todos los horarios del dataset de la app se pueden leer', () {
    final data = jsonDecode(
      File('assets/data/bike_services_chile.json').readAsStringSync(),
    ) as List;
    final hours = data
        .map((e) => (e as Map)['opening_hours'] as String?)
        .whereType<String>()
        .toSet();
    expect(hours, isNotEmpty);
    final failed = hours.where((h) => OpeningHours.parse(h) == null).toList();
    expect(failed, isEmpty, reason: 'Horarios sin leer: $failed');
  });
}

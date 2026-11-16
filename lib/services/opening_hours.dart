/// Lee el horario de atención en formato OpenStreetMap (`opening_hours`),
/// p. ej. `Mo-Fr 10:00-13:00,15:00-19:00; Sa 10:00-14:00`, y responde si el
/// lugar está abierto ahora y cuándo abre o cierra.
///
/// Cubre la sintaxis que usan los talleres y bencineras de Chile en OSM:
/// rangos y listas de días, varios tramos por día, `24/7`, `HH:MM+`,
/// `closed`/`off` y horarios que cruzan la medianoche. Los feriados (`PH`)
/// se ignoran. Si el texto no se entiende, [parse] devuelve `null` y la app
/// muestra el texto tal cual.
class OpeningHours {
  OpeningHours._(this.week, this.raw);

  /// Minutos abiertos por día (0 = lunes … 6 = domingo), como pares
  /// [inicio, fin) en minutos desde las 00:00. El fin puede ser 1440.
  final List<List<(int, int)>> week;
  final String raw;

  static const _days = ['Mo', 'Tu', 'We', 'Th', 'Fr', 'Sa', 'Su'];
  static const dayNames = [
    'Lunes',
    'Martes',
    'Miércoles',
    'Jueves',
    'Viernes',
    'Sábado',
    'Domingo',
  ];

  bool get isAlwaysOpen =>
      week.every((d) => d.length == 1 && d.first.$1 == 0 && d.first.$2 == 1440);

  static OpeningHours? parse(String? text) {
    if (text == null) return null;
    final raw = text.trim();
    if (raw.isEmpty) return null;
    final week = List.generate(7, (_) => <(int, int)>[]);

    if (raw == '24/7') {
      for (final d in week) {
        d.add((0, 1440));
      }
      return OpeningHours._(week, raw);
    }

    // Reglas separadas por «;». Algunos escriben «…20:00, Sa 10:00-16:00»:
    // una coma seguida de un día también inicia una regla nueva.
    final rules = raw
        .split(';')
        .expand((r) => r.split(RegExp(r',\s*(?=(Mo|Tu|We|Th|Fr|Sa|Su)\b)')))
        .map((r) => r.trim())
        .where((r) => r.isNotEmpty);

    for (final rule in rules) {
      final m = RegExp(
        r'^((?:(?:Mo|Tu|We|Th|Fr|Sa|Su|PH)(?:-(?:Mo|Tu|We|Th|Fr|Sa|Su))?\s*,?\s*)+)?\s*(.*)$',
      ).firstMatch(rule);
      if (m == null) return null;
      final daySel = (m.group(1) ?? '').trim();
      final timeSel = (m.group(2) ?? '').trim();

      // Días que cubre la regla (sin selector = todos).
      final days = <int>{};
      if (daySel.isEmpty) {
        days.addAll(List.generate(7, (i) => i));
      } else {
        for (final part in daySel.split(',')) {
          final p = part.trim();
          if (p.isEmpty || p == 'PH') continue;
          final ends = p.split('-');
          final a = _days.indexOf(ends.first.trim());
          if (a < 0) return null;
          if (ends.length == 1) {
            days.add(a);
          } else {
            final b = _days.indexOf(ends[1].trim());
            if (b < 0) return null;
            for (var i = a; ; i = (i + 1) % 7) {
              days.add(i);
              if (i == b) break;
            }
          }
        }
        // Regla solo de feriados: no aplica a días normales.
        if (days.isEmpty) continue;
      }

      final t = timeSel.toLowerCase();
      if (t == 'closed' || t == 'off') {
        for (final d in days) {
          week[d].clear();
        }
        continue;
      }
      if (t.isEmpty) return null;

      for (final range in timeSel.split(',')) {
        final r = range.replaceAll(' ', '');
        if (r.isEmpty) continue;
        final open = RegExp(r'^(\d{1,2}):(\d{2})\+$').firstMatch(r);
        final span = RegExp(r'^(\d{1,2}):(\d{2})-(\d{1,2}):(\d{2})$').firstMatch(r);
        int start, end;
        if (open != null) {
          start = _min(open.group(1)!, open.group(2)!);
          end = 1440; // «desde las HH:MM» sin hora de cierre
        } else if (span != null) {
          start = _min(span.group(1)!, span.group(2)!);
          end = _min(span.group(3)!, span.group(4)!);
        } else {
          return null;
        }
        if (start > 1440 || end > 1440) return null;
        for (final d in days) {
          if (end > start) {
            week[d].add((start, end));
          } else {
            // Cruza la medianoche (ej. 20:00-02:00) o 00:00-00:00.
            week[d].add((start, 1440));
            if (end > 0) week[(d + 1) % 7].add((0, end));
          }
        }
      }
    }
    for (final d in week) {
      d.sort((a, b) => a.$1.compareTo(b.$1));
    }
    return OpeningHours._(week, raw);
  }

  static int _min(String h, String m) => int.parse(h) * 60 + int.parse(m);

  static String _fmt(int minutes) {
    final m = minutes % 1440;
    return '${(m ~/ 60).toString().padLeft(2, '0')}:${(m % 60).toString().padLeft(2, '0')}';
  }

  bool isOpenAt(DateTime t) {
    final day = t.weekday - 1;
    final now = t.hour * 60 + t.minute;
    return week[day].any((r) => now >= r.$1 && now < r.$2);
  }

  /// Hora de cierre del tramo actual (siguiendo al día siguiente si sigue
  /// abierto pasada la medianoche). `null` si está cerrado.
  (int day, int minute)? _closesAt(DateTime t) {
    var day = t.weekday - 1;
    final now = t.hour * 60 + t.minute;
    final cur = week[day].where((r) => now >= r.$1 && now < r.$2);
    if (cur.isEmpty) return null;
    var end = cur.first.$2;
    // Une tramos contiguos (ej. 18:00-24:00 y 00:00-02:00 del día siguiente).
    for (var guard = 0; guard < 7 && end == 1440; guard++) {
      final next = (day + 1) % 7;
      final cont = week[next].where((r) => r.$1 == 0);
      if (cont.isEmpty) break;
      day = next;
      end = cont.first.$2;
    }
    return (day, end);
  }

  (int dayOffset, int minute)? _nextOpening(DateTime t) {
    final today = t.weekday - 1;
    final now = t.hour * 60 + t.minute;
    for (var off = 0; off < 8; off++) {
      final d = (today + off) % 7;
      for (final r in week[d]) {
        if (off == 0 && r.$1 <= now) continue;
        return (off, r.$1);
      }
    }
    return null;
  }

  /// Frase corta para la tarjeta, p. ej. «Abierto · cierra a las 19:00» o
  /// «Cerrado · abre mañana a las 10:00».
  ({bool open, String text}) status(DateTime t) {
    if (isAlwaysOpen) return (open: true, text: 'Abierto las 24 horas');
    if (isOpenAt(t)) {
      final c = _closesAt(t);
      if (c == null) return (open: true, text: 'Abierto ahora');
      final sameDay = c.$1 == t.weekday - 1;
      if (c.$2 == 1440 && sameDay) {
        return (open: true, text: 'Abierto · cierra a medianoche');
      }
      return (
        open: true,
        text: sameDay
            ? 'Abierto · cierra a las ${_fmt(c.$2)}'
            : 'Abierto · cierra el ${dayNames[c.$1].toLowerCase()} a las ${_fmt(c.$2)}',
      );
    }
    final n = _nextOpening(t);
    if (n == null) return (open: false, text: 'Cerrado');
    final when = switch (n.$1) {
      0 => 'hoy',
      1 => 'mañana',
      _ => 'el ${dayNames[(t.weekday - 1 + n.$1) % 7].toLowerCase()}',
    };
    return (open: false, text: 'Cerrado · abre $when a las ${_fmt(n.$2)}');
  }

  /// Horario de un día como texto: «10:00–13:00, 15:00–19:00» o «Cerrado».
  String dayText(int day) {
    final r = week[day];
    if (r.isEmpty) return 'Cerrado';
    if (r.length == 1 && r.first.$1 == 0 && r.first.$2 == 1440) {
      return '24 horas';
    }
    return r.map((e) => '${_fmt(e.$1)}–${_fmt(e.$2)}').join(', ');
  }
}

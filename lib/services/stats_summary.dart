/// Resúmenes por periodo para «Mis estadísticas» (semana, mes, año, total).
///
/// Funciones puras sobre el mapa { "YYYY-MM-DD": km } que guarda
/// RideStatsService, para poder probarlas sin SharedPreferences.
library;

enum StatsPeriod { week, month, year, all }

/// Una barra del gráfico: un día (semana/mes) o un mes (año/total).
class StatsBar {
  final DateTime start;
  final double km;
  final String label;
  const StatsBar(this.start, this.km, this.label);
}

class PeriodSummary {
  final StatsPeriod period;
  final double km;
  /// Km del periodo anterior equivalente (null en «total»).
  final double? prevKm;
  final int activeDays;
  final double bestDayKm;
  final DateTime? bestDayDate;
  final List<StatsBar> bars;

  const PeriodSummary({
    required this.period,
    required this.km,
    required this.prevKm,
    required this.activeDays,
    required this.bestDayKm,
    required this.bestDayDate,
    required this.bars,
  });

  double get avgPerActiveDay => activeDays == 0 ? 0 : km / activeDays;

  /// Variación porcentual frente al periodo anterior (null si no aplica).
  double? get changePct {
    final p = prevKm;
    if (p == null || p < 0.1) return null;
    return (km - p) / p * 100;
  }
}

class PersonalRecords {
  final double bestDayKm;
  final DateTime? bestDayDate;
  final int longestStreak;
  final DateTime? longestStreakEnd;
  final double bestWeekKm;
  final DateTime? bestWeekStart;
  const PersonalRecords({
    required this.bestDayKm,
    required this.bestDayDate,
    required this.longestStreak,
    required this.longestStreakEnd,
    required this.bestWeekKm,
    required this.bestWeekStart,
  });
}

const _diasCortos = ['L', 'M', 'M', 'J', 'V', 'S', 'D'];
const _mesesIniciales = ['E', 'F', 'M', 'A', 'M', 'J', 'J', 'A', 'S', 'O', 'N', 'D'];
const kActiveDayKm = 0.1;

DateTime? _parse(String k) {
  final p = k.split('-');
  if (p.length != 3) return null;
  final y = int.tryParse(p[0]), m = int.tryParse(p[1]), d = int.tryParse(p[2]);
  if (y == null || m == null || d == null) return null;
  return DateTime(y, m, d);
}

DateTime _day(DateTime d) => DateTime(d.year, d.month, d.day);

/// Lunes de la semana de [d].
DateTime weekStart(DateTime d) => _day(d).subtract(Duration(days: d.weekday - 1));

Map<DateTime, double> _byDate(Map<String, double> raw) {
  final out = <DateTime, double>{};
  raw.forEach((k, v) {
    final d = _parse(k);
    if (d != null) out[d] = (out[d] ?? 0) + v;
  });
  return out;
}

(DateTime, DateTime) _range(StatsPeriod p, DateTime now, {int back = 0}) {
  final t = _day(now);
  switch (p) {
    case StatsPeriod.week:
      final s = weekStart(t).subtract(Duration(days: 7 * back));
      return (s, s.add(const Duration(days: 7)));
    case StatsPeriod.month:
      final s = DateTime(t.year, t.month - back, 1);
      return (s, DateTime(s.year, s.month + 1, 1));
    case StatsPeriod.year:
      final s = DateTime(t.year - back, 1, 1);
      return (s, DateTime(s.year + 1, 1, 1));
    case StatsPeriod.all:
      return (DateTime(1970), t.add(const Duration(days: 1)));
  }
}

double _sum(Map<DateTime, double> m, DateTime a, DateTime b) =>
    m.entries.where((e) => !e.key.isBefore(a) && e.key.isBefore(b)).fold(0.0, (s, e) => s + e.value);

PeriodSummary summarize(Map<String, double> raw, StatsPeriod period, {DateTime? now}) {
  final ref = now ?? DateTime.now();
  final m = _byDate(raw);
  final (a, b) = _range(period, ref);
  final inRange = m.entries.where((e) => !e.key.isBefore(a) && e.key.isBefore(b)).toList();

  final km = inRange.fold(0.0, (s, e) => s + e.value);
  final active = inRange.where((e) => e.value > kActiveDayKm).length;
  MapEntry<DateTime, double>? best;
  for (final e in inRange) {
    if (best == null || e.value > best.value) best = e;
  }

  double? prev;
  if (period != StatsPeriod.all) {
    final (pa, pb) = _range(period, ref, back: 1);
    prev = _sum(m, pa, pb);
  }

  final bars = <StatsBar>[];
  switch (period) {
    case StatsPeriod.week:
      for (var i = 0; i < 7; i++) {
        final d = a.add(Duration(days: i));
        bars.add(StatsBar(d, m[d] ?? 0, _diasCortos[i]));
      }
    case StatsPeriod.month:
      for (var d = a; d.isBefore(b); d = DateTime(d.year, d.month, d.day + 1)) {
        bars.add(StatsBar(d, m[d] ?? 0, '${d.day}'));
      }
    case StatsPeriod.year:
      for (var i = 0; i < 12; i++) {
        final s = DateTime(a.year, i + 1, 1);
        bars.add(StatsBar(s, _sum(m, s, DateTime(a.year, i + 2, 1)), _mesesIniciales[i]));
      }
    case StatsPeriod.all:
      // Últimos 12 meses.
      final t = _day(ref);
      for (var i = 11; i >= 0; i--) {
        final s = DateTime(t.year, t.month - i, 1);
        bars.add(StatsBar(s, _sum(m, s, DateTime(s.year, s.month + 1, 1)), _mesesIniciales[s.month - 1]));
      }
  }

  return PeriodSummary(
    period: period,
    km: km,
    prevKm: prev,
    activeDays: active,
    bestDayKm: best?.value ?? 0,
    bestDayDate: best?.key,
    bars: bars,
  );
}

PersonalRecords records(Map<String, double> raw) {
  final m = _byDate(raw);
  MapEntry<DateTime, double>? best;
  for (final e in m.entries) {
    if (best == null || e.value > best.value) best = e;
  }

  // Racha más larga.
  final days = m.entries.where((e) => e.value > kActiveDayKm).map((e) => e.key).toList()..sort();
  var longest = 0, cur = 0;
  DateTime? longestEnd, prevDay;
  for (final d in days) {
    cur = (prevDay != null && d.difference(prevDay).inHours.abs() >= 20 && d.difference(prevDay).inHours <= 28) ? cur + 1 : 1;
    if (cur > longest) {
      longest = cur;
      longestEnd = d;
    }
    prevDay = d;
  }

  // Mejor semana (lunes a domingo).
  final weeks = <DateTime, double>{};
  m.forEach((d, v) {
    final w = weekStart(d);
    weeks[w] = (weeks[w] ?? 0) + v;
  });
  MapEntry<DateTime, double>? bestWeek;
  for (final e in weeks.entries) {
    if (bestWeek == null || e.value > bestWeek.value) bestWeek = e;
  }

  return PersonalRecords(
    bestDayKm: best?.value ?? 0,
    bestDayDate: best?.key,
    longestStreak: longest,
    longestStreakEnd: longestEnd,
    bestWeekKm: bestWeek?.value ?? 0,
    bestWeekStart: bestWeek?.key,
  );
}

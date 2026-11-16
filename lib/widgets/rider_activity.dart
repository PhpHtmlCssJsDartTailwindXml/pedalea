import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../core/time_format.dart';
import '../services/co2_service.dart';
import '../services/karma_service.dart';

/// Actividad pública de un ciclista, calculada desde `ride_stats` (legible
/// para todos) y otras tablas públicas. Sirve tanto para "Mi perfil" como
/// para el perfil de otra persona.
class RiderActivity {
  final double totalKm;
  final double weekKm;
  final double monthKm;
  final double maxSpeed;
  final int activeDays30;
  final int streak;
  final DateTime? lastRide;
  final List<double> last14; // del más antiguo a hoy

  /// Km por día de los últimos 30 días (clave yyyy-mm-dd), para sumar la
  /// semana completa (lunes a domingo) del día que se toque en el gráfico.
  final Map<String, double> dailyKm;
  final int karma;
  final int alerts;
  final int events;
  final DateTime? memberSince;

  const RiderActivity({
    required this.totalKm,
    required this.weekKm,
    required this.monthKm,
    required this.maxSpeed,
    required this.activeDays30,
    required this.streak,
    required this.lastRide,
    required this.last14,
    this.dailyKm = const {},
    required this.karma,
    required this.alerts,
    required this.events,
    required this.memberSince,
  });

  /// Km de un día (0 si no pedaleó o está fuera de los últimos 30 días).
  double kmOn(DateTime d) => dailyKm[_key(d)] ?? 0;

  /// Km de la semana (lunes a domingo) que contiene a [d].
  double weekKmOf(DateTime d) {
    final monday = DateTime(d.year, d.month, d.day - (d.weekday - 1));
    double s = 0;
    for (var i = 0; i < 7; i++) {
      s += kmOn(DateTime(monday.year, monday.month, monday.day + i));
    }
    return s;
  }

  static String _key(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  /// Carga todo en paralelo. Si algo falla, esa parte queda en 0.
  static Future<RiderActivity> load(String userId, {double? totalKm}) async {
    final sb = Supabase.instance.client;
    final today = DateTime.now();
    final since = today.subtract(const Duration(days: 29));

    Future<List> rides() async {
      try {
        return await sb
            .from('ride_stats')
            .select('day, km, max_speed_kmh')
            .eq('user_id', userId)
            .gte('day', _key(since));
      } catch (_) {
        return [];
      }
    }

    Future<Map<String, dynamic>?> profile() async {
      try {
        return await sb
            .from('profiles')
            .select('total_km, created_at')
            .eq('id', userId)
            .maybeSingle();
      } catch (_) {
        return null;
      }
    }

    Future<DateTime?> lastRideEver() async {
      try {
        final r = await sb
            .from('ride_stats')
            .select('day')
            .eq('user_id', userId)
            .gt('km', 0.1)
            .order('day', ascending: false)
            .limit(1)
            .maybeSingle();
        return r == null ? null : DateTime.tryParse(r['day'] as String);
      } catch (_) {
        return null;
      }
    }

    Future<int> count(String table, String column) async {
      try {
        final rows = await sb.from(table).select('id').eq(column, userId);
        return (rows as List).length;
      } catch (_) {
        return 0;
      }
    }

    final res = await Future.wait([
      rides(),
      profile(),
      lastRideEver(),
      KarmaService().getUserKarma(userId).catchError((_) => 0),
      count('bike_alerts', 'user_id'),
      count('events', 'user_id'),
    ]);

    final rows = res[0] as List;
    final prof = res[1] as Map<String, dynamic>?;
    final byDay = <String, double>{};
    double maxSpeed = 0;
    for (final r in rows) {
      final km = (r['km'] as num?)?.toDouble() ?? 0;
      byDay[r['day'] as String] = km;
      final ms = (r['max_speed_kmh'] as num?)?.toDouble() ?? 0;
      if (ms > maxSpeed) maxSpeed = ms;
    }
    double kmOn(DateTime d) => byDay[_key(d)] ?? 0;

    final last14 = [
      for (int i = 13; i >= 0; i--) kmOn(today.subtract(Duration(days: i)))
    ];
    double sumDays(int n) {
      double s = 0;
      for (int i = 0; i < n; i++) {
        s += kmOn(today.subtract(Duration(days: i)));
      }
      return s;
    }

    // Racha: días seguidos con pedaleo, terminando hoy (o ayer si hoy aún no).
    int streak = 0;
    var cursor = kmOn(today) > 0.1 ? today : today.subtract(const Duration(days: 1));
    while (kmOn(cursor) > 0.1 && streak < 30) {
      streak++;
      cursor = cursor.subtract(const Duration(days: 1));
    }

    return RiderActivity(
      totalKm: totalKm ?? (prof?['total_km'] as num?)?.toDouble() ?? 0,
      weekKm: sumDays(7),
      monthKm: sumDays(30),
      maxSpeed: maxSpeed,
      activeDays30: byDay.values.where((v) => v > 0.1).length,
      streak: streak,
      lastRide: res[2] as DateTime?,
      last14: last14,
      dailyKm: byDay,
      karma: res[3] as int,
      alerts: res[4] as int,
      events: res[5] as int,
      memberSince:
          DateTime.tryParse(prof?['created_at'] as String? ?? '')?.toLocal(),
    );
  }
}

const _meses = [
  'ene', 'feb', 'mar', 'abr', 'may', 'jun',
  'jul', 'ago', 'sep', 'oct', 'nov', 'dic',
];

String memberSinceLabel(DateTime d) => '${_meses[d.month - 1]} ${d.year}';

String lastRideLabel(DateTime? d) {
  if (d == null) return 'Aún no registra salidas';
  final days = DateTime(DateTime.now().year, DateTime.now().month,
          DateTime.now().day)
      .difference(DateTime(d.year, d.month, d.day))
      .inDays;
  if (days <= 0) return 'Pedaleó hoy';
  if (days == 1) return 'Pedaleó ayer';
  if (days < 7) return 'Pedaleó hace $days días';
  return 'Última salida ${timeAgoShort(d)}';
}

Widget activitySectionLabel(String text, Color accent, {String? trailing}) {
  return Row(
    children: [
      Container(
        width: 3,
        height: 12,
        decoration: BoxDecoration(
          color: accent,
          borderRadius: BorderRadius.circular(2),
        ),
      ),
      const SizedBox(width: 8),
      Text(
        text,
        style: TextStyle(
          fontFamily: 'Poppins',
          color: Colors.white.withOpacity(0.6),
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.1,
        ),
      ),
      const Spacer(),
      if (trailing != null)
        Text(
          trailing,
          style: TextStyle(
            fontFamily: 'Poppins',
            color: Colors.white.withOpacity(0.35),
            fontSize: 11,
          ),
        ),
    ],
  );
}

/// Tarjeta de actividad: métricas, mini gráfico de 14 días y última salida.
class RiderActivityCard extends StatelessWidget {
  final RiderActivity? data;
  final Color accent;
  const RiderActivityCard({super.key, required this.data, required this.accent});

  Widget _metric(String value, String unit, String label, IconData icon) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.fromLTRB(10, 10, 8, 10),
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.18),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: accent, size: 16),
            const SizedBox(height: 6),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text.rich(
                TextSpan(children: [
                  TextSpan(
                    text: value,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  TextSpan(
                    text: ' $unit',
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.45),
                      fontSize: 11,
                    ),
                  ),
                ]),
                style: const TextStyle(fontFamily: 'Poppins'),
              ),
            ),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontFamily: 'Poppins',
                color: Colors.white.withOpacity(0.5),
                fontSize: 10.5,
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final d = data;
    final days = d?.last14 ?? List.filled(14, 0.0);

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [accent.withOpacity(0.1), Colors.white.withOpacity(0.03)],
        ),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: Colors.white.withOpacity(0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.directions_bike_rounded, color: accent, size: 18),
              const SizedBox(width: 8),
              const Text(
                'Actividad',
                style: TextStyle(
                  fontFamily: 'Poppins',
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              if (d != null && d.streak > 0)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: Colors.orange.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '🔥 ${d.streak} ${d.streak == 1 ? 'día' : 'días'}',
                    style: const TextStyle(
                      fontFamily: 'Poppins',
                      color: Colors.orangeAccent,
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _metric(d == null ? '—' : d.totalKm.toStringAsFixed(1), 'km',
                  'Total', Icons.route_rounded),
              const SizedBox(width: 8),
              _metric(d == null ? '—' : d.weekKm.toStringAsFixed(1), 'km',
                  'Esta semana', Icons.date_range_rounded),
              const SizedBox(width: 8),
              _metric(
                  d == null || d.maxSpeed <= 0
                      ? '—'
                      : d.maxSpeed.toStringAsFixed(0),
                  'km/h',
                  'Vel. máx (30d)',
                  Icons.bolt_rounded),
            ],
          ),
          const SizedBox(height: 14),
          // Gráfico de 14 días: al tocar una barra se ven los km de ese día
          // y de su semana.
          ActivityBars(data: d, days: days, accent: accent),
          const SizedBox(height: 12),
          Row(
            children: [
              Icon(Icons.schedule_rounded,
                  size: 14, color: Colors.white.withOpacity(0.45)),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  d == null ? 'Cargando actividad…' : lastRideLabel(d.lastRide),
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    color: Colors.white.withOpacity(0.55),
                    fontSize: 12,
                  ),
                ),
              ),
              if (d != null)
                Text(
                  '${d.activeDays30} días activos · ${d.monthKm.toStringAsFixed(0)} km/mes',
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    color: Colors.white.withOpacity(0.4),
                    fontSize: 11,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Barras de los últimos 14 días. Tocar una barra muestra los km de ese día
/// y el total de su semana (lunes a domingo); tocarla otra vez vuelve al
/// resumen.
class ActivityBars extends StatefulWidget {
  const ActivityBars({
    super.key,
    required this.data,
    required this.days,
    required this.accent,
  });

  final RiderActivity? data;
  final List<double> days; // del más antiguo a hoy
  final Color accent;

  @override
  State<ActivityBars> createState() => _ActivityBarsState();
}

class _ActivityBarsState extends State<ActivityBars> {
  int? _selected;

  static const _wd = ['L', 'M', 'M', 'J', 'V', 'S', 'D'];
  static const _wdLong = ['Lun', 'Mar', 'Mié', 'Jue', 'Vie', 'Sáb', 'Dom'];

  DateTime _dateOf(int i) {
    final t = DateTime.now();
    return DateTime(t.year, t.month, t.day - (widget.days.length - 1 - i));
  }

  static String _km(double v) =>
      v >= 100 ? v.toStringAsFixed(0) : v.toStringAsFixed(1);

  @override
  Widget build(BuildContext context) {
    final days = widget.days;
    final accent = widget.accent;
    final maxKm = days.fold<double>(0.1, (m, v) => v > m ? v : m);
    final sel = _selected;
    final d = widget.data;
    final last = days.length - 1;

    // Semana (lunes a domingo) del día elegido, para resaltarla.
    DateTime? weekStart;
    if (sel != null) {
      final date = _dateOf(sel);
      weekStart = DateTime(date.year, date.month, date.day - (date.weekday - 1));
    }
    bool inSelectedWeek(int i) {
      if (weekStart == null) return false;
      final diff = _dateOf(i).difference(weekStart).inDays;
      return diff >= 0 && diff < 7;
    }

    final total14 = days.fold<double>(0, (a, b) => a + b);
    final Widget info;
    if (sel == null) {
      info = Text.rich(
        TextSpan(children: [
          TextSpan(
            text: '${_km(total14)} km',
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
          ),
          const TextSpan(text: ' en 14 días · toca una barra'),
        ]),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontFamily: 'Poppins',
          color: Colors.white.withOpacity(0.45),
          fontSize: 11.5,
        ),
      );
    } else {
      final date = _dateOf(sel);
      final dayLabel = sel == last
          ? 'Hoy'
          : '${_wdLong[date.weekday - 1]} ${date.day}/${date.month}';
      final week = d?.weekKmOf(date) ?? 0;
      final thisWeek = inSelectedWeek(last);
      info = Row(
        children: [
          Expanded(
            child: Text.rich(
              TextSpan(children: [
                TextSpan(text: '$dayLabel  '),
                TextSpan(
                  text: '${_km(days[sel])} km',
                  style: TextStyle(
                    color: accent,
                    fontWeight: FontWeight.w800,
                    fontSize: 14,
                  ),
                ),
              ]),
              style: const TextStyle(
                fontFamily: 'Poppins',
                color: Colors.white,
                fontSize: 12.5,
              ),
            ),
          ),
          Text.rich(
            TextSpan(children: [
              TextSpan(text: thisWeek ? 'Esta semana  ' : 'Esa semana  '),
              TextSpan(
                text: '${_km(week)} km',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ]),
            style: TextStyle(
              fontFamily: 'Poppins',
              color: Colors.white.withOpacity(0.55),
              fontSize: 12,
            ),
          ),
        ],
      );
    }

    Color barColor(int i) {
      final highlighted = i == sel || (sel == null && i == last);
      if (days[i] <= 0.1) {
        return Colors.white.withOpacity(i == sel ? 0.3 : 0.1);
      }
      if (highlighted) return accent;
      return accent.withOpacity(sel == null ? 0.55 : 0.35);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: 22,
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 180),
            child: Align(
              key: ValueKey(sel),
              alignment: Alignment.centerLeft,
              child: info,
            ),
          ),
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 72,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              for (int i = 0; i < days.length; i++)
                Expanded(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () =>
                        setState(() => _selected = _selected == i ? null : i),
                    child: Container(
                      // Fondo suave para la semana del día elegido.
                      decoration: BoxDecoration(
                        color: inSelectedWeek(i)
                            ? accent.withOpacity(0.08)
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 2),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          Flexible(
                            child: FractionallySizedBox(
                              heightFactor:
                                  (days[i] / maxKm).clamp(0.06, 1.0).toDouble(),
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 180),
                                decoration: BoxDecoration(
                                  color: barColor(i),
                                  borderRadius: BorderRadius.circular(4),
                                  border: i == sel
                                      ? Border.all(color: Colors.white, width: 1.2)
                                      : null,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            _wd[_dateOf(i).weekday - 1],
                            style: TextStyle(
                              fontFamily: 'Poppins',
                              color: i == sel || (sel == null && i == last)
                                  ? accent
                                  : Colors.white.withOpacity(0.3),
                              fontSize: 9,
                              fontWeight: i == sel || i == last
                                  ? FontWeight.w700
                                  : FontWeight.w400,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Fila de 3 mini tarjetas: nivel de karma, CO₂ e impacto en la comunidad.
class RiderBadgesRow extends StatelessWidget {
  final RiderActivity? data;
  const RiderBadgesRow({super.key, required this.data});

  Widget _tile({
    required Widget top,
    required String value,
    required String label,
    required Color color,
  }) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.fromLTRB(10, 12, 10, 12),
        decoration: BoxDecoration(
          color: color.withOpacity(0.08),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: color.withOpacity(0.2)),
        ),
        child: Column(
          children: [
            SizedBox(height: 24, child: Center(child: top)),
            const SizedBox(height: 6),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                value,
                maxLines: 1,
                style: TextStyle(
                  fontFamily: 'Poppins',
                  color: color,
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontFamily: 'Poppins',
                color: Colors.white.withOpacity(0.5),
                fontSize: 10.5,
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final d = data;
    final level = KarmaService.getLevel(d?.karma ?? 0);
    final co2 = Co2Service.savedKg(d?.totalKm ?? 0);
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _tile(
            top: Text(level.emoji, style: const TextStyle(fontSize: 20)),
            value: level.title,
            label: '${d?.karma ?? 0} karma',
            color: Color(level.colorValue),
          ),
          const SizedBox(width: 8),
          _tile(
            top: const Text('🌱', style: TextStyle(fontSize: 20)),
            value: Co2Service.format(co2),
            label: 'CO₂ ahorrado',
            color: Colors.lightGreenAccent,
          ),
          const SizedBox(width: 8),
          _tile(
            top: const Icon(Icons.campaign_rounded,
                color: Colors.orangeAccent, size: 22),
            value: '${d?.alerts ?? 0} · ${d?.events ?? 0}',
            label: 'alertas · eventos',
            color: Colors.orangeAccent,
          ),
        ],
      ),
    );
  }
}

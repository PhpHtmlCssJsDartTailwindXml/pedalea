import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Km recorridos en un día concreto.
class DayStat {
  final DateTime date; // medianoche local
  final double km;
  const DayStat(this.date, this.km);
}

/// Registro local (offline) de los km recorridos por día.
///
/// Guarda un mapa { "YYYY-MM-DD": km } en SharedPreferences, lo que permite
/// mostrar el progreso diario, semanal, la racha y los totales sin depender
/// de internet ni de la base de datos.
class RideStatsService {
  static const _key = 'ride_stats_v1';
  // v2: la v1 guardaba velocidades de auto/micro (hasta 80 km/h). Al cambiar
  // la clave se parte de 0 y se rellena con el servidor ya corregido.
  static const _maxSpeedKey = 'ride_max_speed_v2';

  /// Velocidad máxima creíble en bici urbana (km/h).
  static const maxBikeSpeedKmh = 60.0;
  static SharedPreferences? _prefs;

  static Future<void> init() async {
    _prefs ??= await SharedPreferences.getInstance();
  }

  static String dayKey(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  static Map<String, double> _readAll() {
    final raw = _prefs?.getString(_key);
    if (raw == null) return {};
    try {
      final m = jsonDecode(raw) as Map<String, dynamic>;
      return m.map((k, v) => MapEntry(k, (v as num).toDouble()));
    } catch (e) {
      debugPrint('RideStatsService: error leyendo: $e');
      return {};
    }
  }

  static Future<void> _writeAll(Map<String, double> m) async {
    await _prefs?.setString(_key, jsonEncode(m));
  }

  /// Suma [km] al total del día de hoy.
  static Future<void> addKm(double km, {DateTime? now}) async {
    if (km <= 0) return;
    await init();
    final m = _readAll();
    final k = dayKey(now ?? DateTime.now());
    m[k] = (m[k] ?? 0) + km;
    await _writeAll(m);
  }

  /// Copia de todos los días registrados { "YYYY-MM-DD": km }.
  static Map<String, double> allDays() => Map.of(_readAll());

  static double kmForDay(DateTime d) => _readAll()[dayKey(d)] ?? 0;
  static double todayKm() => kmForDay(DateTime.now());

  /// Fusiona los km por día que llegan del servidor. El servidor manda, pero
  /// nunca se baja un valor local mayor (km de un viaje que aún no se subió).
  static Future<void> mergeServerDays(Map<String, double> serverKm) async {
    if (serverKm.isEmpty) return;
    await init();
    final m = _readAll();
    serverKm.forEach((day, km) {
      final local = m[day] ?? 0;
      if (km > local) m[day] = km;
    });
    await _writeAll(m);
  }

  /// Velocidad máxima detectada por GPS (histórica, km/h).
  static double maxSpeedKmh() => _prefs?.getDouble(_maxSpeedKey) ?? 0;

  /// Registra una nueva velocidad si supera la máxima guardada. Descarta
  /// valores que no son de bici (> [maxBikeSpeedKmh]: auto, micro o un salto
  /// del GPS).
  static Future<void> recordMaxSpeed(double kmh) async {
    if (kmh <= 0 || kmh > maxBikeSpeedKmh) return;
    await init();
    if (kmh > maxSpeedKmh()) await _prefs?.setDouble(_maxSpeedKey, kmh);
  }

  /// Últimos [n] días (hoy incluido), del más antiguo al más reciente.
  static List<DayStat> lastNDays(int n, {DateTime? now}) {
    final all = _readAll();
    final ref = now ?? DateTime.now();
    final today = DateTime(ref.year, ref.month, ref.day);
    return List.generate(n, (i) {
      final d = today.subtract(Duration(days: n - 1 - i));
      return DayStat(d, all[dayKey(d)] ?? 0);
    });
  }

  /// Últimos 7 días (hoy incluido), del más antiguo al más reciente.
  static List<DayStat> last7Days({DateTime? now}) => lastNDays(7, now: now);

  static double weekKm({DateTime? now}) =>
      last7Days(now: now).fold(0.0, (s, e) => s + e.km);

  static double totalKm() => _readAll().values.fold(0.0, (s, v) => s + v);

  static int activeDays() => _readAll().values.where((v) => v > 0.1).length;

  static double bestDayKm() {
    final v = _readAll().values;
    return v.isEmpty ? 0 : v.reduce((a, b) => a > b ? a : b);
  }

  /// Días consecutivos con actividad (>0,1 km) contando hacia atrás desde hoy
  /// (o desde ayer si hoy aún no hay registro).
  static int currentStreak({DateTime? now}) {
    final all = _readAll();
    final ref = now ?? DateTime.now();
    var day = DateTime(ref.year, ref.month, ref.day);
    if ((all[dayKey(day)] ?? 0) <= 0.1) {
      day = day.subtract(const Duration(days: 1));
    }
    var streak = 0;
    while ((all[dayKey(day)] ?? 0) > 0.1) {
      streak++;
      day = day.subtract(const Duration(days: 1));
    }
    return streak;
  }

  /// Solo para pruebas: inyecta datos crudos.
  @visibleForTesting
  static Future<void> debugSeed(Map<String, double> data) async {
    await init();
    await _writeAll(data);
  }

  /// Solo para pruebas: fuerza re-leer SharedPreferences en el próximo init().
  @visibleForTesting
  static void resetForTest() => _prefs = null;
}

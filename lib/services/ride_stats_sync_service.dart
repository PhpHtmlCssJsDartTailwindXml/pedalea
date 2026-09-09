import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'ride_stats_service.dart';

/// Una fila del ranking de ciclistas.
class RankingEntry {
  final String userId;
  final String username;
  final String? avatarUrl;
  final double value; // km o km/h según la métrica
  final bool isMe;
  const RankingEntry({
    required this.userId,
    required this.username,
    required this.avatarUrl,
    required this.value,
    required this.isMe,
  });
}

/// Sincroniza las estadísticas diarias con Supabase (tabla `ride_stats`).
///
/// El registro local de [RideStatsService] sigue siendo la caché rápida y el
/// respaldo offline; este servicio lo mantiene alineado con el servidor para
/// que "Mis estadísticas" no se pierda al reinstalar la app y para alimentar
/// el ranking de ciclistas (km del día/semana y velocidad máxima).
class RideStatsSyncService {
  RideStatsSyncService._();
  static final RideStatsSyncService instance = RideStatsSyncService._();

  SupabaseClient get _db => Supabase.instance.client;

  /// Suma [km] al día de hoy en el servidor y reporta la [maxSpeedKmh] de la
  /// sesión. Best-effort: si no hay red, los km ya quedaron en el registro
  /// local y se reintenta en el próximo push.
  Future<void> pushDelta({required double km, double maxSpeedKmh = 0}) async {
    if (_db.auth.currentUser == null) return;
    if (km <= 0 && maxSpeedKmh <= 0) return;
    try {
      await _db.rpc('bump_ride_stats', params: {
        'p_day': RideStatsService.dayKey(DateTime.now()),
        'p_km': km <= 0 ? 0 : km,
        'p_max_speed': maxSpeedKmh <= 0 ? 0 : maxSpeedKmh,
      });
    } catch (e) {
      debugPrint('RideStatsSyncService.pushDelta error: $e');
    }
  }

  /// Trae los últimos [days] días del usuario y los fusiona en la caché local
  /// (el servidor manda, salvo km locales aún sin subir). Devuelve el total
  /// histórico real (`profiles.total_km`) o null si no se pudo consultar.
  Future<double?> pull({int days = 35}) async {
    final uid = _db.auth.currentUser?.id;
    if (uid == null) return null;
    try {
      final since = DateTime.now().subtract(Duration(days: days - 1));
      final rows = await _db
          .from('ride_stats')
          .select('day, km, max_speed_kmh')
          .eq('user_id', uid)
          .gte('day', RideStatsService.dayKey(since));

      final serverKm = <String, double>{};
      double maxSpeed = 0;
      for (final r in rows as List) {
        serverKm[r['day'] as String] = (r['km'] as num?)?.toDouble() ?? 0;
        final ms = (r['max_speed_kmh'] as num?)?.toDouble() ?? 0;
        if (ms > maxSpeed) maxSpeed = ms;
      }
      await RideStatsService.mergeServerDays(serverKm);
      if (maxSpeed > 0) await RideStatsService.recordMaxSpeed(maxSpeed);

      final profile = await _db
          .from('profiles')
          .select('total_km')
          .eq('id', uid)
          .maybeSingle();
      return (profile?['total_km'] as num?)?.toDouble();
    } catch (e) {
      debugPrint('RideStatsSyncService.pull error: $e');
      return null;
    }
  }

  /// Ranking de ciclistas. [metric] = 'km' (suma) o 'max_speed' (máxima).
  /// [sinceDays] acota la ventana: 1 = hoy, 7 = última semana, 30 = mes.
  Future<List<RankingEntry>> fetchRanking({
    required String metric,
    required int sinceDays,
    int limit = 50,
  }) async {
    try {
      final since = DateTime.now().subtract(Duration(days: sinceDays - 1));
      final rows = await _db.rpc('ride_ranking', params: {
        'p_metric': metric,
        'p_since': RideStatsService.dayKey(since),
        'p_limit': limit,
      });
      final me = _db.auth.currentUser?.id;
      return [
        for (final r in rows as List)
          RankingEntry(
            userId: r['user_id'] as String,
            username: (r['username'] as String?)?.trim().isNotEmpty == true
                ? (r['username'] as String).trim()
                : 'Ciclista',
            avatarUrl: r['avatar_url'] as String?,
            value: (r['value'] as num?)?.toDouble() ?? 0,
            isMe: r['user_id'] == me,
          ),
      ];
    } catch (e) {
      debugPrint('RideStatsSyncService.fetchRanking error: $e');
      return [];
    }
  }
}

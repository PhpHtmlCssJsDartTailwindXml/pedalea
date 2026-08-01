import 'dart:convert';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter/foundation.dart';
import 'ride_stats_service.dart';
import 'karma_service.dart';
import 'co2_service.dart';

class AchievementsService {
  final SupabaseClient _supabase = Supabase.instance.client;

  String? get _userId => _supabase.auth.currentUser?.id;

  /// Devuelve todos los logros del catálogo junto con si el usuario los desbloqueó.
  Future<List<Map<String, dynamic>>> getAllWithStatus() async {
    final uid = _userId;
    if (uid == null) return [];

    try {
      final catalog = await _supabase
          .from('achievements')
          .select()
          .order('category')
          .order('requirement_value');

      final unlocked = await _supabase
          .from('user_achievements')
          .select('achievement_id, unlocked_at')
          .eq('user_id', uid);

      final unlockedMap = {
        for (final u in unlocked)
          u['achievement_id'] as String: u['unlocked_at'] as String,
      };

      return catalog.map<Map<String, dynamic>>((a) {
        final aid = a['id'] as String;
        return {
          ...a,
          'unlocked': unlockedMap.containsKey(aid),
          'unlocked_at': unlockedMap[aid],
        };
      }).toList();
    } catch (e) {
      debugPrint('Error obteniendo logros: $e');
      return [];
    }
  }

  /// Chequea todos los logros del usuario y desbloquea los que correspondan.
  /// Retorna los IDs de los logros recién desbloqueados.
  Future<List<String>> checkAndUnlock() async {
    final uid = _userId;
    if (uid == null) return [];

    try {
      // Obtener logros ya desbloqueados para no re-chequear
      final alreadyUnlocked = await _supabase
          .from('user_achievements')
          .select('achievement_id')
          .eq('user_id', uid);

      final done = {
        for (final u in alreadyUnlocked) u['achievement_id'] as String,
      };

      final toUnlock = <String>[];

      // --- Perfil completo ---
      if (!done.contains('profile_complete')) {
        final profile = await _supabase
            .from('profiles')
            .select('username, full_name, avatar_url')
            .eq('id', uid)
            .maybeSingle();
        if (profile != null &&
            (profile['username'] as String? ?? '').isNotEmpty &&
            (profile['full_name'] as String? ?? '').isNotEmpty &&
            (profile['avatar_url'] as String? ?? '').isNotEmpty) {
          toUnlock.add('profile_complete');
        }
      }

      // --- Alertas reportadas ---
      final alertsNeedCheck = {'first_alert', 'guardian_5', 'centinel_10', 'reporter_25', 'early_bird', 'night_owl'}
          .where((id) => !done.contains(id))
          .toSet();

      if (alertsNeedCheck.isNotEmpty) {
        final alerts = await _supabase
            .from('bike_alerts')
            .select('created_at')
            .eq('user_id', uid);

        final count = alerts.length;

        if (alertsNeedCheck.contains('first_alert') && count >= 1) {
          toUnlock.add('first_alert');
        }
        if (alertsNeedCheck.contains('guardian_5') && count >= 5) {
          toUnlock.add('guardian_5');
        }
        if (alertsNeedCheck.contains('centinel_10') && count >= 10) {
          toUnlock.add('centinel_10');
        }
        if (alertsNeedCheck.contains('reporter_25') && count >= 25) {
          toUnlock.add('reporter_25');
        }

        // Madrugador: alguna alerta creada antes de las 7am
        if (alertsNeedCheck.contains('early_bird')) {
          final hasEarly = alerts.any((a) {
            final dt = DateTime.tryParse(a['created_at'] as String? ?? '');
            if (dt == null) return false;
            final local = dt.toLocal();
            return local.hour < 7;
          });
          if (hasEarly) toUnlock.add('early_bird');
        }

        // Búho nocturno: alguna alerta creada después de las 22h
        if (alertsNeedCheck.contains('night_owl')) {
          final hasNight = alerts.any((a) {
            final dt = DateTime.tryParse(a['created_at'] as String? ?? '');
            if (dt == null) return false;
            final local = dt.toLocal();
            return local.hour >= 22;
          });
          if (hasNight) toUnlock.add('night_owl');
        }
      }

      // --- Eventos creados ---
      final eventsCreatedCheck = {'first_event_create', 'event_host_3'}
          .where((id) => !done.contains(id))
          .toSet();

      if (eventsCreatedCheck.isNotEmpty) {
        final created = await _supabase
            .from('events')
            .select('id')
            .eq('user_id', uid);

        final createdCount = created.length;
        if (eventsCreatedCheck.contains('first_event_create') && createdCount >= 1) {
          toUnlock.add('first_event_create');
        }
        if (eventsCreatedCheck.contains('event_host_3') && createdCount >= 3) {
          toUnlock.add('event_host_3');
        }
      }

      // --- Eventos en que participó ---
      final eventsJoinedCheck = {'first_event_join', 'event_social_5'}
          .where((id) => !done.contains(id))
          .toSet();

      if (eventsJoinedCheck.isNotEmpty) {
        // participants_ids es jsonb (no un array nativo de Postgres), así que
        // el filtro de contención debe mandarse como literal JSON codificado
        // en vez de usar .contains(), que genera sintaxis de array Postgres.
        final joined = await _supabase
            .from('events')
            .select('id')
            .filter('participants_ids', 'cs', jsonEncode([uid]));

        final joinedCount = joined.length;
        if (eventsJoinedCheck.contains('first_event_join') && joinedCount >= 1) {
          toUnlock.add('first_event_join');
        }
        if (eventsJoinedCheck.contains('event_social_5') && joinedCount >= 5) {
          toUnlock.add('event_social_5');
        }
      }

      // --- Kilómetros totales (profiles.total_km) ---
      final kmChecks = {
        'km_10': 10, 'km_25': 25, 'km_50': 50, 'km_100': 100,
        'km_250': 250, 'km_500': 500, 'km_1000': 1000,
        'km_2500': 2500, 'km_5000': 5000, 'km_10000': 10000,
      }..removeWhere((id, _) => done.contains(id));

      double totalKm = 0;
      if (kmChecks.isNotEmpty || !done.contains('plus_member')) {
        final profile = await _supabase
            .from('profiles')
            .select('total_km, is_plus')
            .eq('id', uid)
            .maybeSingle();
        totalKm = (profile?['total_km'] as num?)?.toDouble() ?? 0;

        for (final entry in kmChecks.entries) {
          if (totalKm >= entry.value) toUnlock.add(entry.key);
        }

        if (!done.contains('plus_member') && profile?['is_plus'] == true) {
          toUnlock.add('plus_member');
        }
      }

      // --- CO2 ahorrado (derivado del total de km) ---
      final co2Checks = {'co2_1': 1, 'co2_5': 5, 'co2_10': 10, 'co2_50': 50, 'co2_100': 100}
        ..removeWhere((id, _) => done.contains(id));
      if (co2Checks.isNotEmpty) {
        final co2 = Co2Service.savedKg(totalKm);
        for (final entry in co2Checks.entries) {
          if (co2 >= entry.value) toUnlock.add(entry.key);
        }
      }

      // --- Racha y mejor día (locales, RideStatsService — no dependen de internet) ---
      final streakChecks = {
        'streak_3': 3, 'streak_7': 7, 'streak_14': 14, 'streak_30': 30,
        'streak_60': 60, 'streak_100': 100, 'streak_180': 180, 'streak_365': 365,
      }..removeWhere((id, _) => done.contains(id));
      if (streakChecks.isNotEmpty) {
        final streak = RideStatsService.currentStreak();
        for (final entry in streakChecks.entries) {
          if (streak >= entry.value) toUnlock.add(entry.key);
        }
      }

      final bestDayChecks = {'bestday_20': 20, 'bestday_50': 50, 'bestday_100': 100}
        ..removeWhere((id, _) => done.contains(id));
      if (bestDayChecks.isNotEmpty) {
        final bestDay = RideStatsService.bestDayKm();
        for (final entry in bestDayChecks.entries) {
          if (bestDay >= entry.value) toUnlock.add(entry.key);
        }
      }

      // --- Karma (niveles de KarmaService) ---
      final karmaChecks = {
        'karma_explorador': 10, 'karma_guardian': 30, 'karma_heroe': 60, 'karma_leyenda': 100,
      }..removeWhere((id, _) => done.contains(id));
      if (karmaChecks.isNotEmpty) {
        final karma = await KarmaService().getUserKarma(uid);
        for (final entry in karmaChecks.entries) {
          if (karma >= entry.value) toUnlock.add(entry.key);
        }
      }

      // --- Más niveles de alertas ---
      final moreAlertsCheck = {'reporter_50', 'reporter_100'}.where((id) => !done.contains(id)).toSet();
      if (moreAlertsCheck.isNotEmpty) {
        final alerts = await _supabase.from('bike_alerts').select('id').eq('user_id', uid);
        final count = alerts.length;
        if (moreAlertsCheck.contains('reporter_50') && count >= 50) toUnlock.add('reporter_50');
        if (moreAlertsCheck.contains('reporter_100') && count >= 100) toUnlock.add('reporter_100');
      }

      // --- Más niveles de eventos creados/unidos + evento privado ---
      final moreEventsHostCheck =
          {'event_host_5', 'event_host_10', 'event_private_1'}.where((id) => !done.contains(id)).toSet();
      if (moreEventsHostCheck.isNotEmpty) {
        final created = await _supabase.from('events').select('id, is_private').eq('user_id', uid);
        final count = created.length;
        if (moreEventsHostCheck.contains('event_host_5') && count >= 5) toUnlock.add('event_host_5');
        if (moreEventsHostCheck.contains('event_host_10') && count >= 10) toUnlock.add('event_host_10');
        if (moreEventsHostCheck.contains('event_private_1') &&
            created.any((e) => e['is_private'] == true)) {
          toUnlock.add('event_private_1');
        }
      }

      final moreEventsJoinCheck =
          {'event_social_10', 'event_social_20'}.where((id) => !done.contains(id)).toSet();
      if (moreEventsJoinCheck.isNotEmpty) {
        final joined = await _supabase
            .from('events')
            .select('id')
            .filter('participants_ids', 'cs', jsonEncode([uid]));
        final count = joined.length;
        if (moreEventsJoinCheck.contains('event_social_10') && count >= 10) toUnlock.add('event_social_10');
        if (moreEventsJoinCheck.contains('event_social_20') && count >= 20) toUnlock.add('event_social_20');
      }

      // --- Mensajes en chats de eventos ---
      final eventChatCheck = {'event_chat_1', 'event_chat_10'}.where((id) => !done.contains(id)).toSet();
      if (eventChatCheck.isNotEmpty) {
        final messages = await _supabase.from('event_messages').select('id').eq('user_id', uid);
        final count = messages.length;
        if (eventChatCheck.contains('event_chat_1') && count >= 1) toUnlock.add('event_chat_1');
        if (eventChatCheck.contains('event_chat_10') && count >= 10) toUnlock.add('event_chat_10');
      }

      // --- Rutas favoritas guardadas ---
      final favRouteCheck =
          {'fav_route_1', 'fav_route_5', 'fav_route_10'}.where((id) => !done.contains(id)).toSet();
      if (favRouteCheck.isNotEmpty) {
        final favs = await _supabase.from('favorite_routes').select('id').eq('user_id', uid);
        final count = favs.length;
        if (favRouteCheck.contains('fav_route_1') && count >= 1) toUnlock.add('fav_route_1');
        if (favRouteCheck.contains('fav_route_5') && count >= 5) toUnlock.add('fav_route_5');
        if (favRouteCheck.contains('fav_route_10') && count >= 10) toUnlock.add('fav_route_10');
      }

      // --- Fotos de referencia (POIs y eventos) ---
      final poiPhotoCheck =
          {'poi_photo_1', 'poi_photo_5', 'poi_photo_20'}.where((id) => !done.contains(id)).toSet();
      if (poiPhotoCheck.isNotEmpty) {
        final photos = await _supabase.from('poi_photos').select('id').eq('uploaded_by', uid);
        final count = photos.length;
        if (poiPhotoCheck.contains('poi_photo_1') && count >= 1) toUnlock.add('poi_photo_1');
        if (poiPhotoCheck.contains('poi_photo_5') && count >= 5) toUnlock.add('poi_photo_5');
        if (poiPhotoCheck.contains('poi_photo_20') && count >= 20) toUnlock.add('poi_photo_20');
      }

      final eventPhotoCheck = {'event_photo_1', 'event_photo_5'}.where((id) => !done.contains(id)).toSet();
      if (eventPhotoCheck.isNotEmpty) {
        final photos = await _supabase.from('event_photos').select('id').eq('uploaded_by', uid);
        final count = photos.length;
        if (eventPhotoCheck.contains('event_photo_1') && count >= 1) toUnlock.add('event_photo_1');
        if (eventPhotoCheck.contains('event_photo_5') && count >= 5) toUnlock.add('event_photo_5');
      }

      // Insertar los nuevos logros desbloqueados (sin duplicados)
      final uniqueToUnlock = toUnlock.toSet().toList();
      if (uniqueToUnlock.isNotEmpty) {
        await _supabase.from('user_achievements').insert(
          uniqueToUnlock
              .map((id) => {'user_id': uid, 'achievement_id': id})
              .toList(),
        );
      }

      return uniqueToUnlock;
    } catch (e) {
      debugPrint('Error chequeando logros: $e');
      return [];
    }
  }

  /// Cantidad de logros desbloqueados por el usuario.
  Future<int> unlockedCount() async {
    final uid = _userId;
    if (uid == null) return 0;
    try {
      final result = await _supabase
          .from('user_achievements')
          .select('id')
          .eq('user_id', uid);
      return result.length;
    } catch (_) {
      return 0;
    }
  }
}

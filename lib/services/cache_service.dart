import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Caché persistente en disco para alertas, eventos y ciclovías.
/// Las alertas y eventos expiran a los 30 min; las ciclovías no expiran.
class CacheService {
  static const _keyAlerts     = 'cache_alerts_v1';
  static const _keyEvents     = 'cache_events_v1';
  // v2: antes solo cubría Santiago; se sube de versión para que los
  // usuarios que ya tenían la caché vieja guardada reciban el dataset
  // nuevo de todo Chile en vez de quedar pegados con el de Santiago.
  static const _keyCiclovias  = 'cache_ciclovias_v2';
  static const _keyProfile   = 'cache_profile_v1';
  static const _keyAchievements = 'cache_achievements_v1';
  static const _keyAlertTs    = 'cache_alerts_ts_v1';
  static const _keyEventTs    = 'cache_events_ts_v1';
  static const _keyAchievementsTs = 'cache_achievements_ts_v1';
  static const _maxAge        = Duration(minutes: 30);
  static const _achievementsMaxAge = Duration(minutes: 15);

  // Dueño de la caché de perfil y logros: al cambiar de cuenta en el mismo
  // teléfono no se deben mostrar los datos ni los logros de la otra cuenta.
  static const _keyProfileOwner = 'cache_profile_owner_v1';
  static const _keyAchievementsOwner = 'cache_achievements_owner_v1';

  static SharedPreferences? _prefs;

  static String? get _uid {
    try {
      return Supabase.instance.client.auth.currentUser?.id;
    } catch (_) {
      return null;
    }
  }

  static bool _ownedByCurrentUser(String ownerKey) {
    final uid = _uid;
    return uid != null && _prefs?.getString(ownerKey) == uid;
  }

  static Future<void> _setOwner(String ownerKey) async {
    final uid = _uid;
    if (uid == null) {
      await _prefs?.remove(ownerKey);
    } else {
      await _prefs?.setString(ownerKey, uid);
    }
  }

  static Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
    // Las ciclovías (3,6 MB) ya vienen incluidas en la app. Guardarlas además
    // en las preferencias obligaba a leerlas enteras en CADA arranque, aunque
    // no se usaran. Se borra la copia antigua (una sola vez).
    for (final k in const ['cache_ciclovias_v1', _keyCiclovias]) {
      if (_prefs!.containsKey(k)) await _prefs!.remove(k);
    }
  }

  // ── Helpers ──────────────────────────────────────────────────────────────

  static bool _isExpired(String? tsStr, [Duration maxAge = _maxAge]) {
    if (tsStr == null) return true;
    final ts = DateTime.tryParse(tsStr);
    if (ts == null) return true;
    return DateTime.now().difference(ts) > maxAge;
  }

  static List<Map<String, dynamic>>? _readList(String key) {
    try {
      final raw = _prefs?.getString(key);
      if (raw == null) return null;
      return (jsonDecode(raw) as List).cast<Map<String, dynamic>>();
    } catch (e) {
      debugPrint('CacheService: error leyendo $key: $e');
      return null;
    }
  }

  static Future<void> _writeList(
      String key, List<Map<String, dynamic>> data) async {
    try {
      await _prefs?.setString(key, jsonEncode(data));
    } catch (e) {
      debugPrint('CacheService: error escribiendo $key: $e');
    }
  }

  // ── Alertas ───────────────────────────────────────────────────────────────

  static Future<void> saveAlerts(List<Map<String, dynamic>> alerts) async {
    await _writeList(_keyAlerts, alerts);
    await _prefs?.setString(_keyAlertTs, DateTime.now().toIso8601String());
  }

  /// Devuelve las alertas en caché. Si [ignoreExpiry] es false y el caché
  /// venció, devuelve null para que el caller sepa que debe refrescar.
  static List<Map<String, dynamic>>? loadAlerts({bool ignoreExpiry = false}) {
    if (!ignoreExpiry && _isExpired(_prefs?.getString(_keyAlertTs))) return null;
    return _readList(_keyAlerts);
  }

  // ── Eventos ───────────────────────────────────────────────────────────────

  static Future<void> saveEvents(List<Map<String, dynamic>> events) async {
    await _writeList(_keyEvents, events);
    await _prefs?.setString(_keyEventTs, DateTime.now().toIso8601String());
  }

  static List<Map<String, dynamic>>? loadEvents({bool ignoreExpiry = false}) {
    if (!ignoreExpiry && _isExpired(_prefs?.getString(_keyEventTs))) return null;
    return _readList(_keyEvents);
  }

  // ── Ciclovías (sin expiración) ─────────────────────────────────────────────

  /// Ya no se guardan: se leen del archivo incluido en la app (ver init).
  static Future<void> saveCiclovias(String geoJson) async {}

  static String? loadCiclovias() => null;

  // ── Perfil del usuario (sin expiración — mejor mostrar datos viejos que
  // nada cuando no hay internet) ──────────────────────────────────────────

  static Future<void> saveProfile(Map<String, dynamic> profile) async {
    try {
      await _prefs?.setString(_keyProfile, jsonEncode(profile));
      await _setOwner(_keyProfileOwner);
    } catch (e) {
      debugPrint('CacheService: error guardando perfil: $e');
    }
  }

  static Map<String, dynamic>? loadProfile() {
    if (!_ownedByCurrentUser(_keyProfileOwner)) return null;
    try {
      final raw = _prefs?.getString(_keyProfile);
      if (raw == null) return null;
      return jsonDecode(raw) as Map<String, dynamic>;
    } catch (e) {
      debugPrint('CacheService: error leyendo perfil: $e');
      return null;
    }
  }

  // ── Logros del usuario (expira a los 15 min: checkAndUnlock() hace hasta
  // ~14 consultas en serie, así que no vale la pena repetirlo cada vez que
  // se entra al perfil) ────────────────────────────────────────────────────

  static Future<void> saveAchievements(List<Map<String, dynamic>> achievements) async {
    await _writeList(_keyAchievements, achievements);
    await _setOwner(_keyAchievementsOwner);
    await _prefs?.setString(_keyAchievementsTs, DateTime.now().toIso8601String());
  }

  static List<Map<String, dynamic>>? loadAchievements({bool ignoreExpiry = false}) {
    if (!_ownedByCurrentUser(_keyAchievementsOwner)) return null;
    if (!ignoreExpiry && _isExpired(_prefs?.getString(_keyAchievementsTs), _achievementsMaxAge)) {
      return null;
    }
    return _readList(_keyAchievements);
  }

  // ── Limpieza ──────────────────────────────────────────────────────────────

  static Future<void> clearAll() async {
    await _prefs?.remove(_keyAlerts);
    await _prefs?.remove(_keyEvents);
    await _prefs?.remove(_keyAlertTs);
    await _prefs?.remove(_keyEventTs);
  }
}

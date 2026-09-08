import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

  static SharedPreferences? _prefs;

  static Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
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

  static Future<void> saveCiclovias(String geoJson) async {
    try {
      await _prefs?.setString(_keyCiclovias, geoJson);
    } catch (e) {
      debugPrint('CacheService: error guardando ciclovías: $e');
    }
  }

  static String? loadCiclovias() => _prefs?.getString(_keyCiclovias);

  // ── Perfil del usuario (sin expiración — mejor mostrar datos viejos que
  // nada cuando no hay internet) ──────────────────────────────────────────

  static Future<void> saveProfile(Map<String, dynamic> profile) async {
    try {
      await _prefs?.setString(_keyProfile, jsonEncode(profile));
    } catch (e) {
      debugPrint('CacheService: error guardando perfil: $e');
    }
  }

  static Map<String, dynamic>? loadProfile() {
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
    await _prefs?.setString(_keyAchievementsTs, DateTime.now().toIso8601String());
  }

  static List<Map<String, dynamic>>? loadAchievements({bool ignoreExpiry = false}) {
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

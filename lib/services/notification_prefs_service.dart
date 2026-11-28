import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Qué tipos de aviso quiere recibir el ciclista. Se guarda en la tabla
/// `notification_prefs` (el servidor no envía el push de un tipo apagado; el
/// aviso igual queda en la campana) y en el teléfono, para filtrar también
/// los avisos locales que llegan por Realtime.
class NotificationPrefs {
  NotificationPrefs._();

  /// Tipos configurables, en el orden en que se muestran.
  static const keys = ['messages', 'social', 'impact', 'weekly', 'streak', 'news'];

  static final ValueNotifier<Map<String, bool>> prefs =
      ValueNotifier({for (final k in keys) k: true});

  static const _cacheKey = 'notification_prefs_v1';
  static SupabaseClient get _sb => Supabase.instance.client;

  static bool allows(String key) => prefs.value[key] ?? true;

  /// Tipo de preferencia que corresponde a un aviso, según su payload
  /// (dm|…, chat|…, follow_req|…, post_activity|…). null = siempre se muestra.
  static String? keyForPayload(String payload) {
    final head = payload.split('|').first;
    switch (head) {
      case 'dm':
      case 'chat':
        return 'messages';
      case 'follow_req':
      case 'follow_accept':
      case 'post_activity':
        return 'social';
      case 'my_impact':
        return 'impact';
      case 'app_update':
      case 'plus_promo':
        return 'news';
    }
    return null;
  }

  static bool allowsPayload(String payload) {
    final key = keyForPayload(payload);
    return key == null || allows(key);
  }

  /// Lee la copia del teléfono y después la del servidor.
  static Future<void> load() async {
    try {
      final sp = await SharedPreferences.getInstance();
      final raw = sp.getString(_cacheKey);
      if (raw != null) _apply(Map<String, dynamic>.from(jsonDecode(raw) as Map));
    } catch (_) {}
    final uid = _sb.auth.currentUser?.id;
    if (uid == null) return;
    try {
      final row = await _sb
          .from('notification_prefs')
          .select(keys.join(','))
          .eq('user_id', uid)
          .maybeSingle();
      if (row != null) {
        _apply(row);
        await _saveLocal();
      }
    } catch (e) {
      debugPrint('NotificationPrefs.load: $e');
    }
  }

  /// Cambia un tipo y lo guarda en el teléfono y en el servidor.
  static Future<bool> set(String key, bool value) async {
    prefs.value = {...prefs.value, key: value};
    await _saveLocal();
    final uid = _sb.auth.currentUser?.id;
    if (uid == null) return false;
    try {
      await _sb.from('notification_prefs').upsert({
        'user_id': uid,
        ...prefs.value,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      });
      return true;
    } catch (e) {
      debugPrint('NotificationPrefs.set: $e');
      return false;
    }
  }

  static void _apply(Map<String, dynamic> m) {
    prefs.value = {
      for (final k in keys) k: m[k] is bool ? m[k] as bool : (prefs.value[k] ?? true),
    };
  }

  static Future<void> _saveLocal() async {
    try {
      final sp = await SharedPreferences.getInstance();
      await sp.setString(_cacheKey, jsonEncode(prefs.value));
    } catch (_) {}
  }
}

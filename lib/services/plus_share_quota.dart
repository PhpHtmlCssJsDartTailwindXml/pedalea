import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Imágenes «Plus» gratis al compartir estadísticas: quien no es Plus puede
/// exportar 2 por semana con foto de fondo, sin fondo o colores Plus.
///
/// El conteo vive en el servidor (`plus_share_remaining` / `use_plus_share`)
/// para que no se reinicie al reinstalar. Si esas funciones aún no existen
/// (migración sin aplicar) o no hay conexión, se cuenta en el teléfono.
class PlusShareQuota {
  static const weeklyLimit = 2;
  static const _kLocal = 'plus_share_uses_local_v1';

  static SupabaseClient get _sb => Supabase.instance.client;

  /// Lunes 00:00 (hora local) de la semana de [now].
  @visibleForTesting
  static DateTime weekStart(DateTime now) {
    final d = DateTime(now.year, now.month, now.day);
    return d.subtract(Duration(days: d.weekday - 1));
  }

  static Future<List<DateTime>> _localUses() async {
    final p = await SharedPreferences.getInstance();
    final from = weekStart(DateTime.now());
    return (p.getStringList(_kLocal) ?? const [])
        .map(DateTime.tryParse)
        .whereType<DateTime>()
        .where((d) => !d.isBefore(from))
        .toList();
  }

  static Future<int> _localRemaining() async =>
      (weeklyLimit - (await _localUses()).length).clamp(0, weeklyLimit);

  static Future<int?> _localUse() async {
    final uses = await _localUses();
    if (uses.length >= weeklyLimit) return null;
    uses.add(DateTime.now());
    final p = await SharedPreferences.getInstance();
    await p.setStringList(_kLocal, uses.map((d) => d.toIso8601String()).toList());
    return weeklyLimit - uses.length;
  }

  /// Cuántas quedan esta semana (-1 = es Plus, sin límite).
  static Future<int> remaining() async {
    try {
      final r = await _sb.rpc('plus_share_remaining');
      if (r is int) return r;
    } catch (e) {
      debugPrint('plus_share_remaining sin servidor, se cuenta local: $e');
    }
    return _localRemaining();
  }

  /// Usa una. Devuelve las que quedan después, -1 si es Plus, o null si ya
  /// no quedaban (en ese caso no se usa nada).
  static Future<int?> use() async {
    try {
      final r = await _sb.rpc('use_plus_share');
      if (r == null || r is int) return r as int?;
    } catch (e) {
      debugPrint('use_plus_share sin servidor, se cuenta local: $e');
    }
    return _localUse();
  }
}

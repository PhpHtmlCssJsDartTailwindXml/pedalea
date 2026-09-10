import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../core/constants.dart';

/// Personalización de Pedalea Plus. **Todo se guarda en `profiles`** (no en el
/// dispositivo) para que sincronice entre teléfonos y para que la medalla la
/// vea el resto de ciclistas.
///
/// Expone tres [ValueNotifier] con la configuración del usuario actual; la UI
/// escucha esos notifiers y se actualiza en vivo. Los escritores son
/// optimistas: cambian el notifier al instante y luego persisten en la BD.
class PlusPrefsService {
  static SupabaseClient get _sb => Supabase.instance.client;

  /// Variante de la medalla Plus del usuario actual.
  static final ValueNotifier<int> medalVariant = ValueNotifier(0);

  /// Estilo de mapa premium del usuario actual ('' = automático día/noche).
  static final ValueNotifier<String> mapStyle = ValueNotifier('');

  /// Índice unificado del color de acento de estadísticas del usuario actual.
  static final ValueNotifier<int> accentIndex = ValueNotifier(0);

  static bool _authHooked = false;

  // ── Catálogos ───────────────────────────────────────────────────────
  /// Estilos de mapa reservados para Plus (etiqueta visible + URI de Mapbox).
  static const premiumMapStyles = <(String, String)>[
    ('Satélite', kMapStyleSatellite),
    ('Exterior', kMapStyleOutdoors),
    ('Minimalista', kMapStyleMinimal),
  ];

  /// Variantes de la medalla: (nombre, color base del brillo).
  static const medalVariants = <(String, Color)>[
    ('Oro', Color(0xFFFFC107)),
    ('Neón', Color(0xFF69FF47)),
    ('Hielo', Color(0xFF4FC3F7)),
    ('Fuego', Color(0xFFFF5722)),
    ('Holográfico', Color(0xFFBA68C8)),
  ];

  static int clampVariant(int i) =>
      (i >= 0 && i < medalVariants.length) ? i : 0;

  static String _validStyle(String uri) =>
      premiumMapStyles.any((s) => s.$2 == uri) ? uri : '';

  // ── Ciclo de vida ───────────────────────────────────────────────────
  static Future<void> init() async {
    if (!_authHooked) {
      _authHooked = true;
      _sb.auth.onAuthStateChange.listen((_) => refresh());
    }
    await refresh();
  }

  /// Relee la configuración del perfil del usuario actual.
  static Future<void> refresh() async {
    final uid = _sb.auth.currentUser?.id;
    if (uid == null) {
      medalVariant.value = 0;
      mapStyle.value = '';
      accentIndex.value = 0;
      return;
    }
    try {
      final row = await _sb
          .from('profiles')
          .select('plus_badge_variant, stats_accent_index, map_style')
          .eq('id', uid)
          .maybeSingle();
      if (row == null) return;
      medalVariant.value =
          clampVariant((row['plus_badge_variant'] as num?)?.toInt() ?? 0);
      accentIndex.value = (row['stats_accent_index'] as num?)?.toInt() ?? 0;
      mapStyle.value = _validStyle(row['map_style'] as String? ?? '');
    } catch (e) {
      debugPrint('PlusPrefsService.refresh: $e');
    }
  }

  // ── Escritores (optimistas) ─────────────────────────────────────────
  static Future<void> setMedalVariant(int i) async {
    i = clampVariant(i);
    medalVariant.value = i;
    await _update({'plus_badge_variant': i});
  }

  static Future<void> setMapStyle(String uri) async {
    uri = _validStyle(uri);
    mapStyle.value = uri;
    await _update({'map_style': uri});
  }

  static Future<void> setAccentIndex(int i) async {
    accentIndex.value = i;
    await _update({'stats_accent_index': i});
  }

  static Future<void> _update(Map<String, dynamic> patch) async {
    final uid = _sb.auth.currentUser?.id;
    if (uid == null) return;
    try {
      await _sb.from('profiles').update(patch).eq('id', uid);
    } catch (e) {
      debugPrint('PlusPrefsService._update: $e');
    }
  }
}

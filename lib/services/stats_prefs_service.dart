import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Preferencias de personalización de la pantalla «Mis estadísticas» y de la
/// tarjeta para compartir: color de acento, orden y visibilidad de las
/// tarjetas y rango del gráfico. Se guarda en el dispositivo (SharedPreferences)
/// para que la elección del ciclista persista entre sesiones.
class StatsPrefsService {
  static const _kAccent = 'stats_accent_v1';
  static const _kOrder = 'stats_tile_order_v1';
  static const _kHidden = 'stats_tile_hidden_v1';
  static const _kRange = 'stats_chart_range_v1';

  static SharedPreferences? _prefs;

  /// Paleta de acentos disponible (compartida con la tarjeta de compartir).
  static const accentPalette = <Color>[
    Color(0xFF69FF47), // verde neón (por defecto)
    Color(0xFF4FC3F7), // celeste
    Color(0xFFFF7043), // naranjo
    Color(0xFFBA68C8), // púrpura
    Color(0xFFFFCA28), // ámbar
    Color(0xFFEC407A), // rosado
  ];

  /// Todas las tarjetas del grid en su orden por defecto.
  static const allTiles = <String>[
    'streak',
    'bestDay',
    'total',
    'activeDays',
    'co2',
    'week',
  ];

  static Future<void> init() async {
    _prefs ??= await SharedPreferences.getInstance();
  }

  // ── Color de acento ──────────────────────────────────────────────────
  static int get accentIndex {
    final i = _prefs?.getInt(_kAccent) ?? 0;
    return (i >= 0 && i < accentPalette.length) ? i : 0;
  }

  static Color get accent => accentPalette[accentIndex];

  static Future<void> setAccentIndex(int i) async {
    await init();
    await _prefs?.setInt(_kAccent, i);
  }

  // ── Orden de las tarjetas ────────────────────────────────────────────
  static List<String> get tileOrder {
    final raw = _prefs?.getStringList(_kOrder);
    if (raw == null || raw.isEmpty) return List.of(allTiles);
    // Conserva solo claves conocidas y añade al final las que falten
    // (por si en una futura versión se agregan tarjetas nuevas).
    final order = raw.where(allTiles.contains).toList();
    for (final t in allTiles) {
      if (!order.contains(t)) order.add(t);
    }
    return order;
  }

  static Future<void> setTileOrder(List<String> order) async {
    await init();
    await _prefs?.setStringList(_kOrder, order);
  }

  // ── Tarjetas ocultas ─────────────────────────────────────────────────
  static Set<String> get hiddenTiles {
    final raw = _prefs?.getStringList(_kHidden) ?? const [];
    return raw.where(allTiles.contains).toSet();
  }

  static Future<void> setHiddenTiles(Set<String> hidden) async {
    await init();
    await _prefs?.setStringList(_kHidden, hidden.toList());
  }

  // ── Rango del gráfico (7 o 30 días) ──────────────────────────────────
  static int get chartRange {
    final r = _prefs?.getInt(_kRange) ?? 7;
    return r == 30 ? 30 : 7;
  }

  static Future<void> setChartRange(int range) async {
    await init();
    await _prefs?.setInt(_kRange, range == 30 ? 30 : 7);
  }
}

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Personalización de la pantalla «Mis estadísticas» y de la tarjeta para
/// compartir.
///
/// El **color de acento** ya no vive aquí: se guarda en `profiles` vía
/// [PlusPrefsService] (sincroniza entre dispositivos). Esta clase conserva
/// solo los catálogos/paletas y las preferencias locales de disposición
/// (orden, tarjetas ocultas, rango del gráfico), que son propias del equipo.
class StatsPrefsService {
  // Disposición local de la pantalla (no es Plus ni la ve nadie más).
  static const _kOrder = 'stats_tile_order_v1';
  static const _kHidden = 'stats_tile_hidden_v1';
  static const _kRange = 'stats_chart_range_v1';

  static SharedPreferences? _prefs;

  /// Paleta de acentos gratis (compartida con la tarjeta de compartir).
  static const accentPalette = <Color>[
    Color(0xFF69FF47), // verde neón (por defecto)
    Color(0xFF4FC3F7), // celeste
    Color(0xFFFF7043), // naranjo
    Color(0xFFBA68C8), // púrpura
    Color(0xFFFFCA28), // ámbar
    Color(0xFFEC407A), // rosado
  ];

  /// Colores sólidos exclusivos de Pedalea Plus.
  static const accentPalettePlus = <Color>[
    Color(0xFF00E5C3), // turquesa
    Color(0xFF7C4DFF), // violeta profundo
    Color(0xFFFF4D6D), // carmín
    Color(0xFFD4AF37), // oro viejo
    Color(0xFF18C2F7), // cian eléctrico
    Color(0xFFB2FF59), // lima
  ];

  /// Degradados de dos tonos, exclusivos de Pedalea Plus.
  static const accentGradientsPlus = <List<Color>>[
    [Color(0xFF69FF47), Color(0xFF00B8D4)], // verde → cian
    [Color(0xFF7C4DFF), Color(0xFFEC407A)], // violeta → rosa
    [Color(0xFFFF8A00), Color(0xFFFF3D77)], // naranja → magenta
    [Color(0xFF00E5C3), Color(0xFF3D5AFE)], // turquesa → azul
    [Color(0xFFFFD200), Color(0xFFFF7A00)], // dorado ardiente
  ];

  /// Índice de acento a partir del cual la opción es de Plus.
  static int get freeAccentCount => accentPalette.length;

  /// Todas las opciones de acento en un solo espacio de índices:
  /// `[0..5]` sólidos gratis, luego sólidos Plus, luego degradados Plus.
  /// El valor es el color primario (primer tono en los degradados).
  static List<Color> get allAccentColors => <Color>[
        ...accentPalette,
        ...accentPalettePlus,
        for (final g in accentGradientsPlus) g.first,
      ];

  static bool isPlusAccentIndex(int i) => i >= freeAccentCount;

  /// Par de colores del acento en [i]: un degradado real si [i] apunta a uno,
  /// o `[color, color]` para los sólidos.
  static List<Color> accentGradientFor(int i) {
    final gStart = freeAccentCount + accentPalettePlus.length;
    if (i >= gStart && i < gStart + accentGradientsPlus.length) {
      return accentGradientsPlus[i - gStart];
    }
    final c = (i >= 0 && i < allAccentColors.length)
        ? allAccentColors[i]
        : allAccentColors[0];
    return [c, c];
  }

  /// Índice efectivo: acota [i] al rango válido y, si el ciclista no es Plus
  /// pero tenía un acento Plus, vuelve al verde por defecto.
  static int effectiveAccentIndex(int i, bool isPlus) {
    if (i < 0 || i >= allAccentColors.length) return 0;
    return (!isPlus && isPlusAccentIndex(i)) ? 0 : i;
  }

  static Color effectiveAccent(int i, bool isPlus) =>
      allAccentColors[effectiveAccentIndex(i, isPlus)];

  static List<Color> effectiveAccentGradient(int i, bool isPlus) =>
      accentGradientFor(effectiveAccentIndex(i, isPlus));

  /// Todas las tarjetas del grid en su orden por defecto.
  static const allTiles = <String>[
    'streak',
    'bestDay',
    'total',
    'activeDays',
    'co2',
    'week',
    'maxSpeed',
  ];

  static Future<void> init() async {
    _prefs ??= await SharedPreferences.getInstance();
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

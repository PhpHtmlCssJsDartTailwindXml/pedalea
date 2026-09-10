import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Una celda del mapa de calor: centro aproximado + cuántas veces se ha
/// pedaleado por ahí (peso).
class HeatCell {
  final double lat;
  final double lng;
  final int weight;
  const HeatCell(this.lat, this.lng, this.weight);
}

/// Registro local (offline, privado) de por dónde ha pedaleado el ciclista,
/// para dibujar un mapa de calor personal.
///
/// No guarda el trazado exacto: agrupa cada posición GPS en una celda de
/// ~110 m y solo cuenta cuántas veces se ha pasado por cada celda. Así el
/// archivo es pequeño y no queda un historial de rutas reconstruible.
/// Todo vive en el dispositivo (SharedPreferences); nunca se sube.
class RideHeatService {
  static const _key = 'ride_heat_cells_v1'; // SharedPreferences

  /// Tamaño de celda en grados (~0.001° ≈ 111 m de latitud).
  static const _cellDeg = 0.001;

  /// Tope de celdas guardadas; al superarlo se descartan las de menor peso.
  static const _maxCells = 6000;

  static SharedPreferences? _prefs;
  static final Map<String, int> _cells = {};
  static bool _loaded = false;
  static Timer? _saveTimer;

  static Future<void> init() async {
    _prefs ??= await SharedPreferences.getInstance();
    if (_loaded) return;
    final raw = _prefs?.getString(_key);
    if (raw != null) {
      try {
        final m = jsonDecode(raw) as Map<String, dynamic>;
        _cells
          ..clear()
          ..addAll(m.map((k, v) => MapEntry(k, (v as num).toInt())));
      } catch (e) {
        debugPrint('RideHeatService: error leyendo: $e');
      }
    }
    _loaded = true;
  }

  static String _cellKey(double lat, double lng) {
    final la = (lat / _cellDeg).floor();
    final lo = (lng / _cellDeg).floor();
    return '$la,$lo';
  }

  /// Suma una pasada por la celda que contiene [lat],[lng].
  static Future<void> addPoint(double lat, double lng) async {
    if (lat.abs() < 0.0001 && lng.abs() < 0.0001) return; // (0,0) = GPS inválido
    await init();
    final k = _cellKey(lat, lng);
    _cells[k] = (_cells[k] ?? 0) + 1;
    _scheduleSave();
  }

  static void _scheduleSave() {
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(seconds: 4), _flush);
  }

  static Future<void> _flush() async {
    await init();
    if (_cells.length > _maxCells) {
      final entries = _cells.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));
      _cells
        ..clear()
        ..addEntries(entries.take(_maxCells));
    }
    await _prefs?.setString(_key, jsonEncode(_cells));
  }

  /// Fuerza el guardado inmediato (p. ej. al terminar una sesión de pedaleo).
  static Future<void> flushNow() async {
    _saveTimer?.cancel();
    await _flush();
  }

  /// Todas las celdas con su peso, para alimentar la capa de calor.
  static List<HeatCell> cells() {
    final out = <HeatCell>[];
    _cells.forEach((k, w) {
      final parts = k.split(',');
      if (parts.length != 2) return;
      final la = int.tryParse(parts[0]);
      final lo = int.tryParse(parts[1]);
      if (la == null || lo == null) return;
      out.add(HeatCell(
        (la + 0.5) * _cellDeg,
        (lo + 0.5) * _cellDeg,
        w,
      ));
    });
    return out;
  }

  static int get cellCount => _cells.length;

  /// Peso máximo de una celda (para normalizar el degradado del mapa).
  static int get maxWeight =>
      _cells.values.fold(0, (m, w) => w > m ? w : m);

  static Future<void> clear() async {
    await init();
    _cells.clear();
    _saveTimer?.cancel();
    await _prefs?.remove(_key);
  }

  @visibleForTesting
  static void resetForTest() {
    _prefs = null;
    _loaded = false;
    _cells.clear();
  }
}

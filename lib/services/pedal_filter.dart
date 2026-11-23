/// Resultado de un bloque de recorrido ya evaluado.
class PedalChunk {
  /// Km del bloque (0 si se descartó).
  final double km;

  /// Velocidad máxima sostenida del bloque en km/h (0 si se descartó).
  final double maxKmh;

  /// true si el bloque parece pedaleo y se cuenta.
  final bool accepted;

  const PedalChunk(this.km, this.maxKmh, this.accepted);
}

/// Decide qué km y qué velocidad máxima cuentan como pedaleo.
///
/// Los tramos de GPS no se suman al instante: se juntan en bloques de unos
/// 2 minutos en movimiento y cada bloque se evalúa completo. Un bloque se
/// descarta (no suma km ni velocidad) si parece un vehículo:
///
/// - algún tramo supera [bikeMaxKmh] (ninguna bici urbana va tan rápido);
/// - la velocidad media en movimiento supera [maxAvgKmh];
/// - más de [maxFastShare] del tiempo en movimiento va sobre [fastKmh].
///
/// Así un auto en la ciudad (semáforos, tramos de 40-50 km/h) queda fuera,
/// aunque nunca alcance a activar el aviso de modo pasajero, mientras que un
/// ciclista que baja una cuesta unos segundos a 40 km/h sigue contando.
///
/// La velocidad máxima no es un dato suelto del GPS: es la velocidad
/// *sostenida* durante [sustainWindow] (la mínima de esa ventana), para que
/// un salto del sensor no la infle.
class PedalFilter {
  static const bikeMaxKmh = 60.0;
  static const fastKmh = 32.0;
  static const maxAvgKmh = 28.0;
  static const maxFastShare = 0.25;
  static const sustainWindow = Duration(seconds: 5);
  static const minSustainSpan = Duration(seconds: 3);

  PedalFilter({this.chunkSeconds = 120});

  /// Segundos en movimiento que forman un bloque.
  final double chunkSeconds;

  double _km = 0;
  double _movingSec = 0;
  double _fastSec = 0;
  double _maxSustained = 0;
  bool _overLimit = false;
  final List<(DateTime, double)> _recent = [];

  /// Km retenidos en el bloque en curso (aún no evaluados).
  double get pendingKm => _km;

  /// Agrega un tramo aceptado por el GPS. Devuelve el bloque evaluado cuando
  /// se completa; si no, null.
  PedalChunk? add({
    required DateTime at,
    required double km,
    required double speedKmh,
    required double seconds,
  }) {
    if (km <= 0 || seconds <= 0) return null;
    _km += km;
    _movingSec += seconds;
    if (speedKmh >= fastKmh) _fastSec += seconds;
    if (speedKmh > bikeMaxKmh) _overLimit = true;

    _recent.add((at, speedKmh));
    _recent.removeWhere((s) => at.difference(s.$1) > sustainWindow);
    if (_recent.length >= 3 && at.difference(_recent.first.$1) >= minSustainSpan) {
      final sustained =
          _recent.map((s) => s.$2).reduce((a, b) => a < b ? a : b);
      if (sustained > _maxSustained) _maxSustained = sustained;
    }

    return _movingSec >= chunkSeconds ? flush() : null;
  }

  /// Evalúa y cierra el bloque en curso (al apagar el modo activo o salir de
  /// la app). Devuelve null si no había nada.
  PedalChunk? flush() {
    if (_km <= 0) {
      _reset();
      return null;
    }
    final avgKmh = _movingSec > 0 ? _km / (_movingSec / 3600) : 0.0;
    final fastShare = _movingSec > 0 ? _fastSec / _movingSec : 0.0;
    final ok = !_overLimit && avgKmh <= maxAvgKmh && fastShare <= maxFastShare;
    final maxKmh = _maxSustained > bikeMaxKmh ? bikeMaxKmh : _maxSustained;
    final chunk = ok ? PedalChunk(_km, maxKmh, true) : const PedalChunk(0, 0, false);
    _reset();
    return chunk;
  }

  /// Descarta el bloque en curso (el usuario confirmó que va como pasajero).
  void discard() => _reset();

  void _reset() {
    _km = 0;
    _movingSec = 0;
    _fastSec = 0;
    _maxSustained = 0;
    _overLimit = false;
    _recent.clear();
  }
}

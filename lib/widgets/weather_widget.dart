import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart' as geo;
import 'package:shared_preferences/shared_preferences.dart';
import '../services/weather_service.dart';
import '../core/glass.dart';

class WeatherPill extends StatefulWidget {
  final bool isDayMode;
  const WeatherPill({super.key, this.isDayMode = false});

  /// Si se muestra el recordatorio «Toca para ver el clima» bajo el botón.
  /// Se oculta solo después de que la persona abrió el detalle varias veces.
  static final ValueNotifier<bool> showHint = ValueNotifier(false);
  static const _kHintOpens = 'weather_detail_opens';
  static const _hintUntilOpens = 3;

  static Future<void> initHint() async {
    try {
      final p = await SharedPreferences.getInstance();
      showHint.value = (p.getInt(_kHintOpens) ?? 0) < _hintUntilOpens;
    } catch (_) {}
  }

  static Future<void> _countOpen() async {
    try {
      final p = await SharedPreferences.getInstance();
      final n = (p.getInt(_kHintOpens) ?? 0) + 1;
      await p.setInt(_kHintOpens, n);
      if (n >= _hintUntilOpens) showHint.value = false;
    } catch (_) {}
  }

  @override
  State<WeatherPill> createState() => _WeatherPillState();
}

class _WeatherPillState extends State<WeatherPill> {
  final _service = WeatherService();

  /// Datos actuales (se mantienen mientras se actualiza, para no dejar la
  /// ficha en blanco) y si hay una carga en curso.
  final _data = ValueNotifier<WeatherData?>(null);
  final _busy = ValueNotifier<bool>(true);

  @override
  void initState() {
    super.initState();
    WeatherPill.initHint();
    _data.addListener(_rebuild);
    _busy.addListener(_rebuild);
    _load();
  }

  void _rebuild() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _data.removeListener(_rebuild);
    _busy.removeListener(_rebuild);
    super.dispose();
  }

  Future<void> _load({bool force = false}) async {
    if (_busy.value && _data.value != null && !force) return;
    _busy.value = true;
    try {
      // Reintenta: al arrancar la app el permiso/fix de GPS puede no estar
      // listo todavía. Se usa primero la última posición conocida (instantánea).
      for (var attempt = 0; attempt < 3; attempt++) {
        try {
          geo.Position? pos = await geo.Geolocator.getLastKnownPosition();
          pos ??= await geo.Geolocator.getCurrentPosition(
            desiredAccuracy: geo.LocationAccuracy.medium,
          ).timeout(const Duration(seconds: 8));

          final data = await _service.fetch(
            pos.latitude,
            pos.longitude,
            force: force,
          );
          if (data != null) {
            if (mounted) _data.value = data;
            return;
          }
        } catch (e) {
          debugPrint('WeatherPill intento $attempt falló: $e');
        }
        await Future.delayed(const Duration(seconds: 2));
      }
    } finally {
      if (mounted) _busy.value = false;
    }
  }

  void _openSheet() {
    WeatherPill._countOpen();
    // Sin datos (falló o aún no carga): se abre igual y se reintenta; la
    // ficha muestra el clima apenas llegue.
    if (_data.value == null && !_busy.value) _load();
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => ValueListenableBuilder<WeatherData?>(
        valueListenable: _data,
        builder: (_, data, _) => ValueListenableBuilder<bool>(
          valueListenable: _busy,
          builder: (_, busy, _) {
            if (data == null) {
              return _WeatherPlaceholder(
                busy: busy,
                onRetry: () => _load(force: true),
              );
            }
            return _WeatherSheet(
              data: data,
              refreshing: busy,
              onRefresh: () => _load(force: true),
            );
          },
        ),
      ),
    );
  }

  bool get _isDayMode => widget.isDayMode;
  Color get _textColor => _isDayMode ? const Color(0xFF1A1A2E) : Colors.white;
  Color get _subtextColor => _isDayMode ? const Color(0xFF555577) : Colors.white60;

  @override
  Widget build(BuildContext context) {
    final d = _data.value;

    if (d == null) {
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _openSheet,
        child: _busy.value
            ? SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(
                  color: _isDayMode ? const Color(0xFF00A86B) : Colors.white54,
                  strokeWidth: 1.5,
                ),
              )
            : const Text('🌡️', style: TextStyle(fontSize: 14)),
      );
    }

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _openSheet,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(d.emoji, style: const TextStyle(fontSize: 14)),
          const SizedBox(width: 4),
          Text(
            '${d.temperature.round()}°',
            style: TextStyle(
              fontFamily: 'Poppins',
              color: _textColor,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
          if (d.windSpeed >= 20) ...[
            const SizedBox(width: 5),
            const Text('💨', style: TextStyle(fontSize: 11)),
            Text(
              '${d.windSpeed.round()}',
              style: TextStyle(
                fontFamily: 'Poppins',
                color: _subtextColor,
                fontSize: 11,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Fondo de la ficha del clima: sólido, para que se lea igual sobre el mapa
/// claro (antes era casi transparente con letras blancas).
BoxDecoration _sheetBox() => BoxDecoration(
  color: const Color(0xFF141A2C),
  borderRadius: BorderRadius.circular(28),
  border: Border.all(color: Colors.white.withOpacity(0.12)),
  boxShadow: [
    BoxShadow(
      color: Colors.black.withOpacity(0.4),
      blurRadius: 24,
      offset: const Offset(0, 8),
    ),
  ],
);

/// Ficha mientras todavía no hay datos: cargando, o error con reintento.
class _WeatherPlaceholder extends StatelessWidget {
  final bool busy;
  final VoidCallback onRetry;
  const _WeatherPlaceholder({required this.busy, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      padding: const EdgeInsets.fromLTRB(20, 28, 20, 28),
      decoration: _sheetBox(),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (busy) ...[
            const SizedBox(
              width: 28,
              height: 28,
              child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white70),
            ),
            const SizedBox(height: 14),
            const Text(
              'Consultando el clima de tu zona…',
              style: TextStyle(fontFamily: 'Poppins', color: Colors.white70, fontSize: 14),
            ),
          ] else ...[
            const Text('🌡️', style: TextStyle(fontSize: 36)),
            const SizedBox(height: 10),
            const Text(
              'No pudimos obtener el clima',
              style: TextStyle(
                fontFamily: 'Poppins',
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              'Revisa tu conexión y que la ubicación esté activada.',
              textAlign: TextAlign.center,
              style: TextStyle(fontFamily: 'Poppins', color: Colors.white54, fontSize: 13),
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh, size: 18),
              label: const Text('Reintentar'),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.white,
                side: const BorderSide(color: Colors.white24),
                textStyle: const TextStyle(fontFamily: 'Poppins'),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _WeatherSheet extends StatelessWidget {
  final WeatherData data;
  final VoidCallback onRefresh;
  final bool refreshing;

  const _WeatherSheet({
    required this.data,
    required this.onRefresh,
    this.refreshing = false,
  });

  @override
  Widget build(BuildContext context) {
    final recs = data.recommendations;

    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      decoration: _sheetBox(),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Handle
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Header: ciudad + hora
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (data.cityName.isNotEmpty)
                        Text(
                          data.cityName,
                          style: const TextStyle(
                            fontFamily: 'Poppins',
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      Text(
                        _formatTime(data.fetchedAt),
                        style: const TextStyle(
                          fontFamily: 'Poppins',
                          color: Colors.white38,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                GestureDetector(
                  onTap: refreshing ? null : onRefresh,
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: glassDecoration(radius: 12, opacity: 0.08),
                    // Se actualiza sin cerrar la ficha.
                    child: refreshing
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white54,
                            ),
                          )
                        : const Icon(Icons.refresh, color: Colors.white54, size: 18),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Temperatura principal
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(data.emoji, style: const TextStyle(fontSize: 48)),
                const SizedBox(width: 16),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${data.temperature.round()}°C',
                      style: const TextStyle(
                        fontFamily: 'Poppins',
                        color: Colors.white,
                        fontSize: 40,
                        fontWeight: FontWeight.w300,
                      ),
                    ),
                    Text(
                      data.weatherDescription,
                      style: const TextStyle(
                        fontFamily: 'Poppins',
                        color: Colors.white60,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Stats grid
            Container(
              decoration: glassDecoration(radius: 16, opacity: 0.07, borderOpacity: 0.1),
              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
              child: Column(
                children: [
                  _statRow('🌡️', 'Sensación térmica', '${data.apparentTemperature.round()}°C'),
                  _divider(),
                  _statRow('💨', 'Viento', '${data.windSpeed.round()} km/h ${data.windCardinal}'),
                  _divider(),
                  _statRow('💧', 'Humedad', '${data.humidity.round()}%'),
                  _divider(),
                  _statRow('🌧️', 'Precipitación', '${data.precipitation} mm'),
                  _divider(),
                  _statRow(
                    '☀️',
                    'Índice UV',
                    '${data.uvIndex.toStringAsFixed(1)} · ${data.uvLabel}',
                    valueColor: _uvColor(data.uvIndex),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // Recomendaciones
            const Text(
              'RECOMENDACIONES',
              style: TextStyle(
                fontFamily: 'Poppins',
                color: Colors.white38,
                fontSize: 11,
                fontWeight: FontWeight.w600,
                letterSpacing: 1.2,
              ),
            ),
            const SizedBox(height: 10),
            ...recs.map((r) => _recTile(r)),
          ],
        ),
      ),
    );
  }

  Widget _statRow(String icon, String label, String value, {Color? valueColor}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Text(icon, style: const TextStyle(fontSize: 15)),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                fontFamily: 'Poppins',
                color: Colors.white54,
                fontSize: 13,
              ),
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontFamily: 'Poppins',
              color: valueColor ?? Colors.white,
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _divider() => Divider(height: 1, color: Colors.white.withOpacity(0.06));

  Widget _recTile(WeatherRecommendation rec) {
    final colors = {
      RecommendationLevel.good: Colors.greenAccent,
      RecommendationLevel.info: Colors.lightBlueAccent,
      RecommendationLevel.warning: Colors.orangeAccent,
      RecommendationLevel.danger: Colors.redAccent,
    };
    final bgColors = {
      RecommendationLevel.good: Colors.greenAccent,
      RecommendationLevel.info: Colors.lightBlueAccent,
      RecommendationLevel.warning: Colors.orangeAccent,
      RecommendationLevel.danger: Colors.redAccent,
    };
    final color = colors[rec.level]!;
    final bg = bgColors[rec.level]!;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      decoration: BoxDecoration(
        color: bg.withOpacity(0.07),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: bg.withOpacity(0.18)),
      ),
      child: Row(
        children: [
          Text(rec.icon, style: const TextStyle(fontSize: 18)),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              rec.text,
              style: TextStyle(
                fontFamily: 'Poppins',
                color: color,
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Color _uvColor(double uv) {
    if (uv < 3) return Colors.greenAccent;
    if (uv < 6) return Colors.yellowAccent;
    if (uv < 8) return Colors.orangeAccent;
    return Colors.redAccent;
  }

  String _formatTime(DateTime dt) {
    final local = dt.toLocal();
    final h = local.hour.toString().padLeft(2, '0');
    final m = local.minute.toString().padLeft(2, '0');
    return 'Actualizado a las $h:$m';
  }
}

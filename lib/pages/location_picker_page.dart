import 'package:flutter/material.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart' hide ImageSource;
import '../core/glass.dart';

/// Resultado devuelto al confirmar una ubicación.
class PickedLocation {
  final double latitude;
  final double longitude;
  const PickedLocation({required this.latitude, required this.longitude});
}

/// Pantalla simple para elegir un punto exacto en el mapa (estilo Uber/Google
/// Maps): un pin queda fijo en el centro de la pantalla y el mapa se mueve
/// debajo. Al confirmar, se devuelve la coordenada que quedó bajo el pin.
class LocationPickerPage extends StatefulWidget {
  final double initialLat;
  final double initialLng;

  const LocationPickerPage({
    super.key,
    required this.initialLat,
    required this.initialLng,
  });

  @override
  State<LocationPickerPage> createState() => _LocationPickerPageState();
}

class _LocationPickerPageState extends State<LocationPickerPage> {
  MapboxMap? _mapboxMap;
  bool _confirming = false;

  Future<void> _confirm() async {
    if (_mapboxMap == null || _confirming) return;
    setState(() => _confirming = true);
    try {
      final camState = await _mapboxMap!.getCameraState();
      final center = camState.center.coordinates;
      if (mounted) {
        Navigator.pop(
          context,
          PickedLocation(latitude: center.lat.toDouble(), longitude: center.lng.toDouble()),
        );
      }
    } finally {
      if (mounted) setState(() => _confirming = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          MapWidget(
            key: const ValueKey('locationPickerMap'),
            cameraOptions: CameraOptions(
              center: Point(
                coordinates: Position(widget.initialLng, widget.initialLat),
              ),
              zoom: 16.0,
            ),
            onMapCreated: (map) => _mapboxMap = map,
            // Tocar cualquier punto del mapa mueve la cámara para que el pin
            // fijo del centro quede exactamente ahí — así se puede "poner el
            // pin" tocando directamente, además de arrastrar el mapa.
            onTapListener: (info) {
              _mapboxMap?.flyTo(
                CameraOptions(center: info.point),
                MapAnimationOptions(duration: 300),
              );
            },
          ),
          // Pin fijo en el centro de la pantalla — no se mueve, se mueve el mapa.
          const IgnorePointer(
            child: Center(
              child: Padding(
                padding: EdgeInsets.only(bottom: 36), // ancla la punta del pin al centro
                child: Icon(Icons.location_on, size: 46, color: Color(0xFFE53935)),
              ),
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: Container(
                      width: 40,
                      height: 40,
                      decoration: glassDecoration(radius: 12),
                      child: const Icon(Icons.arrow_back_ios_new, color: Colors.white, size: 18),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      decoration: glassDecoration(radius: 14),
                      child: const Text(
                        'Mueve el mapa para elegir el lugar exacto',
                        style: TextStyle(fontFamily: 'Poppins', color: Colors.white, fontSize: 13),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          Positioned(
            left: 20,
            right: 20,
            bottom: 32,
            child: SafeArea(
              top: false,
              child: SizedBox(
                height: 52,
                child: ElevatedButton.icon(
                  onPressed: _confirming ? null : _confirm,
                  icon: _confirming
                      ? const SizedBox(
                          width: 18, height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black),
                        )
                      : const Icon(Icons.check_circle_outline, size: 20),
                  label: const Text('Usar esta ubicación'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFC9FF5C),
                    foregroundColor: Colors.black,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    textStyle: const TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w700, fontSize: 15),
                    elevation: 0,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

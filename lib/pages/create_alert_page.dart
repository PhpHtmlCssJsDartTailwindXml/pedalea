import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart' as geo;
import 'package:permission_handler/permission_handler.dart';
import '../services/alerts_service.dart';
import '../core/glass.dart';

enum LocationMethod { current, pin }

class CreateAlertPage extends StatefulWidget {
  final Function(Map<String, dynamic>)? onAlertCreated;
  final double? initialLatitude;
  final double? initialLongitude;

  const CreateAlertPage({
    super.key,
    this.onAlertCreated,
    this.initialLatitude,
    this.initialLongitude,
  });

  @override
  State<CreateAlertPage> createState() => _CreateAlertPageState();
}

class _CreateAlertPageState extends State<CreateAlertPage> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _locationController = TextEditingController();

  String _selectedType = 'danger';
  bool _loading = false;
  bool _isGettingLocation = false;

  double? _latitude;
  double? _longitude;
  LocationMethod _locationMethod = LocationMethod.current;

  final AlertsService _alertsService = AlertsService();

  final Map<String, AlertTypeInfo> _alertTypes = {
    'danger': AlertTypeInfo(
      icon: Icons.warning,
      color: Colors.red,
      label: 'Peligro',
      description: 'Zona peligrosa',
    ),
    'theft': AlertTypeInfo(
      icon: Icons.no_accounts,
      color: Colors.purple,
      label: 'Robo',
      description: 'Robos recientes',
    ),
    'construction': AlertTypeInfo(
      icon: Icons.construction,
      color: Colors.orange,
      label: 'Obras',
      description: 'Obras en la vía',
    ),
    'accident': AlertTypeInfo(
      icon: Icons.car_crash,
      color: Colors.deepOrange,
      label: 'Accidente',
      description: 'Accidente reciente',
    ),
    'other': AlertTypeInfo(
      icon: Icons.info,
      color: Colors.blue,
      label: 'Otro',
      description: 'Otro tipo',
    ),
  };

  @override
  void initState() {
    super.initState();
    // Rebuild para la vista previa en vivo (no cambia la funcionalidad).
    _titleController.addListener(_rebuild);
    _descriptionController.addListener(_rebuild);
    if (widget.initialLatitude != null && widget.initialLongitude != null) {
      _latitude = widget.initialLatitude;
      _longitude = widget.initialLongitude;
      _locationController.text = 'Ubicación seleccionada';
      _locationMethod = LocationMethod.current;
    } else if (widget.onAlertCreated != null) {
      _locationMethod = LocationMethod.pin;
    } else {
      _locationMethod = LocationMethod.current;
      _getCurrentLocation();
    }
  }

  void _rebuild() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    _locationController.dispose();
    super.dispose();
  }

  Future<void> _getCurrentLocation() async {
    setState(() => _isGettingLocation = true);
    final status = await Permission.location.status;
    if (status.isDenied) {
      final result = await Permission.location.request();
      if (!result.isGranted) {
        setState(() => _isGettingLocation = false);
        if (mounted) _showSnack('Se necesita permiso de ubicación', color: Colors.orange);
        return;
      }
    }
    try {
      final position = await geo.Geolocator.getCurrentPosition(
        timeLimit: const Duration(seconds: 10),
      );
      if (mounted) {
        setState(() {
          _latitude = position.latitude;
          _longitude = position.longitude;
          _isGettingLocation = false;
        });
        _locationController.text = 'Ubicación actual';
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isGettingLocation = false);
        _showSnack('Error obteniendo ubicación: $e', color: Colors.redAccent);
      }
    }
  }

  void _showSnack(String msg, {Color color = Colors.green}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg, style: const TextStyle(fontFamily: 'Poppins')),
        backgroundColor: color,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        margin: const EdgeInsets.all(16),
      ),
    );
  }

  Future<void> _createAlert() async {
    if (!_formKey.currentState!.validate()) return;
    if (_locationMethod == LocationMethod.pin && widget.onAlertCreated != null) {
      widget.onAlertCreated!({
        'type': _selectedType,
        'title': _titleController.text,
        'description': _descriptionController.text,
        'locationName': _locationController.text.isNotEmpty
            ? _locationController.text
            : 'Ubicación pendiente',
      });
      Navigator.pop(context);
      return;
    }
    if (_latitude == null || _longitude == null) {
      _showSnack('No se pudo obtener tu ubicación. Activa el GPS y presiona 📍',
          color: Colors.orange);
      return;
    }
    setState(() => _loading = true);
    try {
      final alert = await _alertsService.createAlert(
        type: _selectedType,
        title: _titleController.text,
        description: _descriptionController.text,
        latitude: _latitude!,
        longitude: _longitude!,
        locationName: _locationController.text.isNotEmpty
            ? _locationController.text
            : null,
      );
      if (alert != null && mounted) {
        Navigator.pop(context);
        if (widget.onAlertCreated != null) widget.onAlertCreated!(alert);
        _showSnack('Alerta creada con éxito');
      } else if (mounted) {
        throw Exception('No se pudo crear la alerta');
      }
    } catch (e) {
      if (mounted) _showSnack('Error: $e', color: Colors.redAccent);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final type = _alertTypes[_selectedType]!;
    final accentColor = type.color;

    return Scaffold(
      backgroundColor: kBgDark,
      extendBodyBehindAppBar: true,
      body: Container(
        decoration: kPageGradient,
        child: Stack(
          children: [
            // Resplandor del color del tipo, arriba
            Positioned(
              top: -140,
              left: -60,
              right: -60,
              child: IgnorePointer(
                child: Container(
                  height: 320,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: [
                        accentColor.withOpacity(0.28),
                        accentColor.withOpacity(0.0),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            Column(
              children: [
                SafeArea(
                  bottom: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                    child: Row(
                      children: [
                        GestureDetector(
                          onTap: () => Navigator.pop(context),
                          child: Container(
                            width: 42,
                            height: 42,
                            decoration: glassDecoration(radius: 14),
                            child: const Icon(Icons.arrow_back_ios_new_rounded,
                                color: Colors.white, size: 18),
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Nueva alerta',
                                style: TextStyle(
                                  fontFamily: 'Poppins',
                                  color: Colors.white,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 20,
                                ),
                              ),
                              Text(
                                'Avisa a la comunidad de un problema en la vía',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontFamily: 'Poppins',
                                  color: Colors.white.withOpacity(0.45),
                                  fontSize: 11.5,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                Expanded(
                  child: Form(
                    key: _formKey,
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 40),
                      children: [
                        _previewCard(type),
                        const SizedBox(height: 22),

                        // Tipo
                        _sectionLabel('TIPO DE ALERTA'),
                        const SizedBox(height: 12),
                        _typeSelector(),
                        const SizedBox(height: 8),
                        Padding(
                          padding: const EdgeInsets.only(left: 4),
                          child: Text(
                            type.description,
                            style: TextStyle(
                              fontFamily: 'Poppins',
                              color: accentColor.withOpacity(0.85),
                              fontSize: 12,
                            ),
                          ),
                        ),
                        const SizedBox(height: 22),

                        // Detalles
                        _sectionLabel('DETALLES'),
                        const SizedBox(height: 12),
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: glassDecoration(radius: 18),
                          child: Column(
                            children: [
                              TextFormField(
                                controller: _titleController,
                                textCapitalization:
                                    TextCapitalization.sentences,
                                style: const TextStyle(
                                  fontFamily: 'Poppins',
                                  color: Colors.white,
                                  fontSize: 15,
                                ),
                                decoration: glassInput(
                                  'Título de la alerta',
                                  type.icon,
                                  accentColor: accentColor,
                                ),
                                validator: (v) => v == null || v.isEmpty
                                    ? 'Ingresa un título'
                                    : null,
                              ),
                              const SizedBox(height: 12),
                              TextFormField(
                                controller: _descriptionController,
                                maxLines: 3,
                                textCapitalization:
                                    TextCapitalization.sentences,
                                style: const TextStyle(
                                  fontFamily: 'Poppins',
                                  color: Colors.white,
                                  fontSize: 15,
                                ),
                                decoration: glassInput(
                                    'Descripción', Icons.notes_rounded,
                                    accentColor: accentColor),
                                validator: (v) => v == null || v.isEmpty
                                    ? 'Describe la situación'
                                    : null,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 22),

                        // Ubicación
                        _sectionLabel('UBICACIÓN'),
                        const SizedBox(height: 12),
                        Container(
                          decoration: glassDecoration(radius: 18),
                          child: Column(
                        children: [
                          // Selector de método
                          Padding(
                            padding: const EdgeInsets.fromLTRB(14, 14, 14, 0),
                            child: Row(
                              children: [
                                _methodChip(
                                  label: '📍 Ubicación actual',
                                  selected: _locationMethod ==
                                      LocationMethod.current,
                                  onTap: () {
                                    setState(() =>
                                        _locationMethod = LocationMethod.current);
                                    if (_latitude == null) _getCurrentLocation();
                                  },
                                ),
                                const SizedBox(width: 10),
                                _methodChip(
                                  label: '🗺️ Elegir en mapa',
                                  selected:
                                      _locationMethod == LocationMethod.pin,
                                  onTap: () => setState(
                                      () => _locationMethod = LocationMethod.pin),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 12),
                          if (_locationMethod == LocationMethod.current) ...[
                            Padding(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 14),
                              child: TextFormField(
                                controller: _locationController,
                                style: const TextStyle(
                                  fontFamily: 'Poppins',
                                  color: Colors.white,
                                  fontSize: 15,
                                ),
                                decoration: glassInput(
                                  'Nombre del lugar (opcional)',
                                  Icons.location_on,
                                  suffix: _isGettingLocation
                                      ? const Padding(
                                          padding: EdgeInsets.all(12),
                                          child: SizedBox(
                                            width: 20,
                                            height: 20,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                              color: Colors.greenAccent,
                                            ),
                                          ),
                                        )
                                      : IconButton(
                                          icon: const Icon(
                                              Icons.my_location,
                                              color: Colors.greenAccent,
                                              size: 20),
                                          onPressed: _getCurrentLocation,
                                        ),
                                ),
                              ),
                            ),
                            Padding(
                              padding: const EdgeInsets.fromLTRB(14, 8, 14, 14),
                              child: _locationStatus(),
                            ),
                          ] else
                            Padding(
                              padding: const EdgeInsets.fromLTRB(14, 4, 14, 14),
                              child: Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: Colors.greenAccent.withOpacity(0.08),
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(
                                      color:
                                          Colors.greenAccent.withOpacity(0.2)),
                                ),
                                child: const Row(
                                  children: [
                                    Icon(Icons.touch_app,
                                        color: Colors.greenAccent, size: 18),
                                    SizedBox(width: 10),
                                    Expanded(
                                      child: Text(
                                        'Después de crear la alerta, toca el mapa para colocar el pin',
                                        style: TextStyle(
                                          fontFamily: 'Poppins',
                                          color: Colors.white60,
                                          fontSize: 12,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                        const SizedBox(height: 28),

                        Container(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(16),
                            boxShadow: [
                              BoxShadow(
                                color: accentColor.withOpacity(0.35),
                                blurRadius: 22,
                                offset: const Offset(0, 8),
                              ),
                            ],
                          ),
                          child: SizedBox(
                            height: 56,
                            width: double.infinity,
                            child: ElevatedButton.icon(
                              onPressed: _loading ? null : _createAlert,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: accentColor,
                                foregroundColor: Colors.white,
                                disabledBackgroundColor:
                                    accentColor.withOpacity(0.5),
                                elevation: 0,
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(16)),
                                textStyle: const TextStyle(
                                  fontFamily: 'Poppins',
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              icon: _loading
                                  ? const SizedBox(
                                      height: 20,
                                      width: 20,
                                      child: CircularProgressIndicator(
                                          color: Colors.white,
                                          strokeWidth: 2),
                                    )
                                  : Icon(type.icon, size: 20),
                              label: Text(
                                  _loading ? 'Publicando…' : 'Publicar alerta'),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _sectionLabel(String text) => Padding(
        padding: const EdgeInsets.only(left: 4),
        child: Text(
          text,
          style: const TextStyle(
            fontFamily: 'Poppins',
            color: Colors.white30,
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.4,
          ),
        ),
      );

  /// Vista previa en vivo de la alerta.
  Widget _previewCard(AlertTypeInfo type) {
    final title = _titleController.text.trim();
    final desc = _descriptionController.text.trim();
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: type.color.withOpacity(0.35)),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            type.color.withOpacity(0.20),
            type.color.withOpacity(0.04),
          ],
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: type.color.withOpacity(0.9),
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                    color: type.color.withOpacity(0.5), blurRadius: 14),
              ],
            ),
            child: Icon(type.icon, color: Colors.white, size: 26),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: type.color.withOpacity(0.25),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        type.label.toUpperCase(),
                        style: TextStyle(
                          fontFamily: 'Poppins',
                          color: Colors.white.withOpacity(0.9),
                          fontSize: 9,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  title.isEmpty ? 'Título de tu alerta' : title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    color: title.isEmpty
                        ? Colors.white.withOpacity(0.4)
                        : Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  desc.isEmpty
                      ? 'Aquí aparecerá tu descripción…'
                      : desc,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    color: Colors.white.withOpacity(desc.isEmpty ? 0.3 : 0.6),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _typeSelector() {
    return SizedBox(
      height: 96,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 2),
        itemCount: _alertTypes.length,
        separatorBuilder: (_, _) => const SizedBox(width: 10),
        itemBuilder: (_, i) {
          final entry = _alertTypes.entries.elementAt(i);
          final t = entry.value;
          final sel = _selectedType == entry.key;
          return GestureDetector(
            onTap: () => setState(() => _selectedType = entry.key),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              width: 82,
              decoration: BoxDecoration(
                color: sel
                    ? t.color.withOpacity(0.18)
                    : Colors.white.withOpacity(0.04),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color:
                      sel ? t.color : Colors.white.withOpacity(0.08),
                  width: sel ? 1.6 : 1,
                ),
                boxShadow: sel
                    ? [
                        BoxShadow(
                            color: t.color.withOpacity(0.35),
                            blurRadius: 16)
                      ]
                    : null,
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: sel
                          ? t.color
                          : Colors.white.withOpacity(0.06),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(t.icon,
                        color: sel ? Colors.white : Colors.white38,
                        size: 20),
                  ),
                  const SizedBox(height: 7),
                  Text(
                    t.label,
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      color: sel ? Colors.white : Colors.white38,
                      fontSize: 11,
                      fontWeight: sel ? FontWeight.w700 : FontWeight.w400,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _methodChip({
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: selected
                ? Colors.greenAccent.withOpacity(0.15)
                : Colors.white.withOpacity(0.05),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: selected
                  ? Colors.greenAccent.withOpacity(0.4)
                  : Colors.white.withOpacity(0.08),
            ),
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: 'Poppins',
              color: selected ? Colors.greenAccent : Colors.white38,
              fontSize: 12,
              fontWeight:
                  selected ? FontWeight.w600 : FontWeight.normal,
            ),
          ),
        ),
      ),
    );
  }

  Widget _locationStatus() {
    if (_latitude != null && _longitude != null) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.greenAccent.withOpacity(0.08),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.greenAccent.withOpacity(0.2)),
        ),
        child: const Row(
          children: [
            Icon(Icons.check_circle, color: Colors.greenAccent, size: 15),
            SizedBox(width: 8),
            Text(
              'Ubicación obtenida correctamente',
              style: TextStyle(
                fontFamily: 'Poppins',
                color: Colors.greenAccent,
                fontSize: 12,
              ),
            ),
          ],
        ),
      );
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.orange.withOpacity(0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.orange.withOpacity(0.2)),
      ),
      child: const Row(
        children: [
          Icon(Icons.warning_amber_rounded, color: Colors.orange, size: 15),
          SizedBox(width: 8),
          Text(
            'Presiona 📍 para obtener tu ubicación',
            style: TextStyle(
              fontFamily: 'Poppins',
              color: Colors.orange,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}

class AlertTypeInfo {
  final IconData icon;
  final Color color;
  final String label;
  final String description;

  AlertTypeInfo({
    required this.icon,
    required this.color,
    required this.label,
    required this.description,
  });
}

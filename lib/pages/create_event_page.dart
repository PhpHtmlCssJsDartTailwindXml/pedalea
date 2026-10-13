import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart' as geo;
import 'package:permission_handler/permission_handler.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/events_service.dart';
import '../services/subscription_service.dart';
import '../core/glass.dart';
import 'paywall_page.dart';
import 'location_picker_page.dart';

const _kFreeActiveEventsLimit = 2;

class CreateEventPage extends StatefulWidget {
  const CreateEventPage({super.key});

  @override
  State<CreateEventPage> createState() => _CreateEventPageState();
}

class _CreateEventPageState extends State<CreateEventPage> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _locationController = TextEditingController();
  final _maxParticipantsController = TextEditingController();

  DateTime _selectedDate = DateTime.now().add(const Duration(days: 1));
  TimeOfDay _selectedTime = TimeOfDay.now();
  bool _loading = false;
  bool _isGettingLocation = false;

  double? _latitude;
  double? _longitude;

  bool _isPrivate = false;
  final _passwordController = TextEditingController();
  bool _obscurePassword = true;

  final EventsService _eventsService = EventsService();

  @override
  void initState() {
    super.initState();
    _getCurrentLocation();
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    _locationController.dispose();
    _maxParticipantsController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _getCurrentLocation() async {
    setState(() => _isGettingLocation = true);
    final status = await Permission.location.status;
    if (status.isDenied) {
      final result = await Permission.location.request();
      if (!result.isGranted) {
        setState(() => _isGettingLocation = false);
        _showSnack('Se necesita permiso de ubicación', color: Colors.orange);
        return;
      }
    }
    try {
      final position = await geo.Geolocator.getCurrentPosition(
        timeLimit: const Duration(seconds: 10),
      );
      setState(() {
        _latitude = position.latitude;
        _longitude = position.longitude;
        _isGettingLocation = false;
      });
      if (_locationController.text.isEmpty) {
        _locationController.text = 'Mi ubicación actual';
      }
    } catch (e) {
      setState(() => _isGettingLocation = false);
      _showSnack('Error obteniendo ubicación: $e', color: Colors.redAccent);
    }
  }

  Future<void> _pickOnMap() async {
    final result = await Navigator.push<PickedLocation>(
      context,
      MaterialPageRoute(
        builder: (_) => LocationPickerPage(
          initialLat: _latitude ?? -33.4569,
          initialLng: _longitude ?? -70.6483,
        ),
      ),
    );
    if (result != null) {
      setState(() {
        _latitude = result.latitude;
        _longitude = result.longitude;
        _locationController.text = 'Ubicación elegida en el mapa';
      });
    }
  }

  Future<void> _selectDate() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      builder: (context, child) => Theme(
        data: ThemeData.dark().copyWith(
          colorScheme: const ColorScheme.dark(
            primary: Colors.greenAccent,
            onPrimary: Colors.black,
            surface: Color(0xFF1A1A2E),
            onSurface: Colors.white,
          ),
        ),
        child: child!,
      ),
    );
    if (date != null) setState(() => _selectedDate = date);
  }

  Future<void> _selectTime() async {
    final time = await showTimePicker(
      context: context,
      initialTime: _selectedTime,
      builder: (context, child) => Theme(
        data: ThemeData.dark().copyWith(
          colorScheme: const ColorScheme.dark(
            primary: Colors.greenAccent,
            onPrimary: Colors.black,
            surface: Color(0xFF1A1A2E),
            onSurface: Colors.white,
          ),
        ),
        child: child!,
      ),
    );
    if (time != null) setState(() => _selectedTime = time);
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

  /// Valida Plus apenas se activa el switch, sin esperar a que presione
  /// "Crear evento".
  void _onTogglePrivate(bool val) {
    if (val && !SubscriptionService.instance.isPlus.value) {
      _showSnack('Los eventos privados son una función de Pedalea Plus', color: Colors.orange);
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => const PaywallPage(
            reason: 'Los eventos privados con contraseña son una función de Pedalea Plus.',
          ),
        ),
      );
      return;
    }
    setState(() => _isPrivate = val);
  }

  Future<void> _createEvent() async {
    if (!_formKey.currentState!.validate()) return;
    if (_latitude == null || _longitude == null) {
      _showSnack('No se pudo obtener tu ubicación. Activa el GPS y toca "Mi ubicación"',
          color: Colors.orange);
      return;
    }
    final isPlus = SubscriptionService.instance.isPlus.value;

    if (!isPlus) {
      final activeCount = await _eventsService.countMyActiveEvents();
      if (activeCount >= _kFreeActiveEventsLimit) {
        if (!mounted) return;
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => const PaywallPage(
              reason:
                  'El plan gratis permite hasta 2 eventos activos a la vez. Hazte Plus para crear ilimitados.',
            ),
          ),
        );
        return;
      }
    }

    if (_isPrivate && !isPlus) {
      if (!mounted) return;
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => const PaywallPage(
            reason: 'Los eventos privados con contraseña son una función de Pedalea Plus.',
          ),
        ),
      );
      return;
    }

    if (_isPrivate && _passwordController.text.trim().isEmpty) {
      _showSnack('Ponle una contraseña a tu evento privado', color: Colors.orange);
      return;
    }

    setState(() => _loading = true);
    final eventDate = DateTime(
      _selectedDate.year,
      _selectedDate.month,
      _selectedDate.day,
      _selectedTime.hour,
      _selectedTime.minute,
    );
    final maxParticipants = _maxParticipantsController.text.isNotEmpty
        ? int.tryParse(_maxParticipantsController.text)
        : null;
    try {
      final event = await _eventsService.createEvent(
        title: _titleController.text,
        description: _descriptionController.text,
        eventDate: eventDate,
        locationName: _locationController.text,
        latitude: _latitude!,
        longitude: _longitude!,
        maxParticipants: maxParticipants,
        isPrivate: _isPrivate,
        password: _isPrivate ? _passwordController.text.trim() : null,
      );
      if (event != null && mounted) {
        Navigator.pop(context, event);
        _showSnack('¡Evento creado con éxito!');
      } else if (mounted) {
        throw Exception('No se pudo crear el evento');
      }
    } catch (e) {
      if (mounted) _showSnack('Error: $e', color: Colors.redAccent);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  static const _accent = Colors.greenAccent;
  static const _dias = ['lun', 'mar', 'mié', 'jue', 'vie', 'sáb', 'dom'];
  static const _meses = [
    'ene', 'feb', 'mar', 'abr', 'may', 'jun',
    'jul', 'ago', 'sep', 'oct', 'nov', 'dic',
  ];

  String get _dateLabel =>
      '${_dias[_selectedDate.weekday - 1]} ${_selectedDate.day} ${_meses[_selectedDate.month - 1]}';

  String get _timeLabel =>
      '${_selectedTime.hour.toString().padLeft(2, '0')}:${_selectedTime.minute.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final bottomPadding = MediaQuery.of(context).padding.bottom;
    return Scaffold(
      backgroundColor: Colors.transparent,
      extendBodyBehindAppBar: true,
      body: Container(
        decoration: kPageGradient,
        child: Column(
          children: [
            // ── Barra superior ────────────────────────────────────────
            SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                child: Row(
                  children: [
                    GestureDetector(
                      onTap: () => Navigator.pop(context),
                      child: Container(
                        width: 40,
                        height: 40,
                        decoration: glassDecoration(radius: 12),
                        child: const Icon(Icons.close,
                            color: Colors.white, size: 20),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Crear Evento',
                            style: TextStyle(
                              fontFamily: 'Poppins',
                              color: Colors.white,
                              fontWeight: FontWeight.w600,
                              fontSize: 18,
                              height: 1.2,
                            ),
                          ),
                          Text(
                            'Organiza una salida con otros ciclistas',
                            style: TextStyle(
                              fontFamily: 'Poppins',
                              color: Colors.white.withOpacity(0.4),
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // ── Formulario ────────────────────────────────────────────
            Expanded(
              child: Form(
                key: _formKey,
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
                  children: [
                    _section(
                      step: 1,
                      icon: Icons.edit_note_rounded,
                      title: 'Información',
                      subtitle: 'Cómo se llama y de qué se trata',
                      children: [
                        _field(
                          controller: _titleController,
                          label: 'Título del evento',
                          hint: 'Ej: Vuelta al cerro San Cristóbal',
                          icon: Icons.title_rounded,
                          textCapitalization: TextCapitalization.sentences,
                          validator: (v) => v == null || v.isEmpty
                              ? 'Ingresa un título'
                              : null,
                        ),
                        const SizedBox(height: 12),
                        _field(
                          controller: _descriptionController,
                          label: 'Descripción',
                          hint: 'Ritmo, distancia, qué llevar…',
                          icon: Icons.notes_rounded,
                          maxLines: 4,
                          textCapitalization: TextCapitalization.sentences,
                        ),
                      ],
                    ),

                    _section(
                      step: 2,
                      icon: Icons.event_rounded,
                      title: 'Fecha y hora',
                      subtitle: 'Cuándo parte la salida',
                      children: [
                        Row(
                          children: [
                            Expanded(
                              flex: 3,
                              child: _pickerTile(
                                label: 'Fecha',
                                value: _dateLabel,
                                caption: '${_selectedDate.year}',
                                icon: Icons.calendar_month_rounded,
                                onTap: _selectDate,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              flex: 2,
                              child: _pickerTile(
                                label: 'Hora',
                                value: _timeLabel,
                                caption: 'hrs',
                                icon: Icons.schedule_rounded,
                                onTap: _selectTime,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),

                    _section(
                      step: 3,
                      icon: Icons.place_rounded,
                      title: 'Punto de encuentro',
                      subtitle: 'Dónde se juntan para partir',
                      children: [
                        _field(
                          controller: _locationController,
                          label: 'Lugar de encuentro',
                          hint: 'Ej: Plaza de Armas, Parque Forestal…',
                          icon: Icons.location_on_rounded,
                          validator: (v) => v == null || v.isEmpty
                              ? 'Ingresa el lugar de encuentro'
                              : null,
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: _actionChip(
                                icon: Icons.my_location_rounded,
                                label: 'Mi ubicación',
                                loading: _isGettingLocation,
                                onTap: _isGettingLocation
                                    ? null
                                    : _getCurrentLocation,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: _actionChip(
                                icon: Icons.map_outlined,
                                label: 'Elegir en mapa',
                                onTap: _pickOnMap,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        _locationStatus(),
                        const SizedBox(height: 10),
                        _note(
                          Icons.visibility_outlined,
                          'El pin de este evento en el mapa solo lo verán quienes se unan (o tú, como creador).',
                        ),
                      ],
                    ),

                    _section(
                      step: 4,
                      icon: Icons.groups_rounded,
                      title: 'Participantes',
                      subtitle: 'Opcional · déjalo vacío para sin límite',
                      children: [
                        _field(
                          controller: _maxParticipantsController,
                          label: 'Máximo de participantes',
                          hint: 'Sin límite',
                          icon: Icons.people_alt_rounded,
                          keyboardType: TextInputType.number,
                        ),
                      ],
                    ),

                    _section(
                      step: 5,
                      icon: Icons.shield_outlined,
                      title: 'Privacidad',
                      subtitle: 'Quién puede unirse',
                      children: [
                        _privacyToggle(),
                        AnimatedSize(
                          duration: const Duration(milliseconds: 220),
                          curve: Curves.easeOut,
                          alignment: Alignment.topCenter,
                          child: _isPrivate
                              ? Padding(
                                  padding: const EdgeInsets.only(top: 12),
                                  child: _field(
                                    controller: _passwordController,
                                    label: 'Contraseña del evento',
                                    hint: 'Compártela solo con quienes quieres que se unan',
                                    icon: Icons.lock_outline_rounded,
                                    accent: Colors.amber,
                                    obscureText: _obscurePassword,
                                    suffix: IconButton(
                                      icon: Icon(
                                        _obscurePassword
                                            ? Icons.visibility_outlined
                                            : Icons.visibility_off_outlined,
                                        color: Colors.white38,
                                        size: 20,
                                      ),
                                      onPressed: () => setState(() =>
                                          _obscurePassword = !_obscurePassword),
                                    ),
                                  ),
                                )
                              : const SizedBox(width: double.infinity),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),

            // ── Botón fijo inferior ───────────────────────────────────
            Container(
              padding: EdgeInsets.fromLTRB(16, 12, 16, 12 + bottomPadding),
              decoration: BoxDecoration(
                color: const Color(0xFF0A0A14).withOpacity(0.96),
                border: Border(
                  top: BorderSide(color: Colors.white.withOpacity(0.06)),
                ),
              ),
              child: SizedBox(
                height: 54,
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _loading ? null : _createEvent,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.greenAccent,
                    foregroundColor: Colors.black,
                    disabledBackgroundColor:
                        Colors.greenAccent.withOpacity(0.5),
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16)),
                    textStyle: const TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  child: _loading
                      ? const SizedBox(
                          height: 22,
                          width: 22,
                          child: CircularProgressIndicator(
                              color: Colors.black, strokeWidth: 2),
                        )
                      : const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.check_circle_outline_rounded, size: 20),
                            SizedBox(width: 8),
                            Text('Crear Evento'),
                          ],
                        ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Tarjeta de sección con número de paso, ícono, título y subtítulo.
  Widget _section({
    required int step,
    required IconData icon,
    required String title,
    required String subtitle,
    required List<Widget> children,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 18),
      decoration: glassDecoration(radius: 22, opacity: 0.045, borderOpacity: 0.09),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: _accent.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: _accent.withOpacity(0.2)),
                ),
                child: Icon(icon, color: _accent, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontFamily: 'Poppins',
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        height: 1.2,
                      ),
                    ),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontFamily: 'Poppins',
                        color: Colors.white.withOpacity(0.4),
                        fontSize: 11.5,
                      ),
                    ),
                  ],
                ),
              ),
              Text(
                '$step/5',
                style: TextStyle(
                  fontFamily: 'Poppins',
                  color: Colors.white.withOpacity(0.25),
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          ...children,
        ],
      ),
    );
  }

  OutlineInputBorder _border(Color color, [double width = 1]) =>
      OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: color, width: width),
      );

  Widget _field({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    String? hint,
    int maxLines = 1,
    TextInputType? keyboardType,
    TextCapitalization textCapitalization = TextCapitalization.none,
    String? Function(String?)? validator,
    bool obscureText = false,
    Widget? suffix,
    Color accent = _accent,
  }) {
    return TextFormField(
      controller: controller,
      maxLines: maxLines,
      keyboardType: keyboardType,
      textCapitalization: textCapitalization,
      validator: validator,
      obscureText: obscureText,
      cursorColor: accent,
      style: const TextStyle(
        fontFamily: 'Poppins',
        color: Colors.white,
        fontSize: 15,
      ),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        alignLabelWithHint: maxLines > 1,
        floatingLabelStyle: TextStyle(
          fontFamily: 'Poppins',
          color: accent,
          fontSize: 13,
          fontWeight: FontWeight.w500,
        ),
        labelStyle: const TextStyle(
          fontFamily: 'Poppins',
          color: Colors.white54,
          fontSize: 14,
        ),
        hintStyle: TextStyle(
          fontFamily: 'Poppins',
          color: Colors.white.withOpacity(0.22),
          fontSize: 13.5,
        ),
        errorStyle: const TextStyle(fontFamily: 'Poppins', fontSize: 11.5),
        prefixIcon: Padding(
          padding: EdgeInsets.only(bottom: maxLines > 1 ? 60 : 0),
          child: Icon(icon, color: accent.withOpacity(0.75), size: 20),
        ),
        suffixIcon: suffix,
        filled: true,
        fillColor: Colors.white.withOpacity(0.05),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
        border: _border(Colors.white.withOpacity(0.08)),
        enabledBorder: _border(Colors.white.withOpacity(0.08)),
        focusedBorder: _border(accent.withOpacity(0.8), 1.4),
        errorBorder: _border(Colors.redAccent.withOpacity(0.7)),
        focusedErrorBorder: _border(Colors.redAccent, 1.4),
      ),
    );
  }

  Widget _pickerTile({
    required String label,
    required String value,
    required String caption,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.white.withOpacity(0.05),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.fromLTRB(14, 12, 12, 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white.withOpacity(0.08)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(icon, color: _accent.withOpacity(0.8), size: 16),
                  const SizedBox(width: 6),
                  Text(
                    label,
                    style: const TextStyle(
                      fontFamily: 'Poppins',
                      color: Colors.white54,
                      fontSize: 11.5,
                    ),
                  ),
                  const Spacer(),
                  Icon(Icons.expand_more_rounded,
                      color: Colors.white.withOpacity(0.3), size: 18),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontFamily: 'Poppins',
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  height: 1.1,
                ),
              ),
              Text(
                caption,
                style: TextStyle(
                  fontFamily: 'Poppins',
                  color: Colors.white.withOpacity(0.35),
                  fontSize: 11,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _actionChip({
    required IconData icon,
    required String label,
    required VoidCallback? onTap,
    bool loading = false,
  }) {
    return Material(
      color: _accent.withOpacity(0.07),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          height: 46,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: _accent.withOpacity(0.25)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (loading)
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.greenAccent,
                  ),
                )
              else
                Icon(icon, color: _accent, size: 18),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  label,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontFamily: 'Poppins',
                    color: Colors.greenAccent,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _note(IconData icon, String text) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 1),
          child: Icon(icon, size: 15, color: Colors.white.withOpacity(0.35)),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: TextStyle(
              fontFamily: 'Poppins',
              color: Colors.white.withOpacity(0.4),
              fontSize: 11.5,
              height: 1.4,
            ),
          ),
        ),
      ],
    );
  }

  Widget _privacyToggle() {
    return Material(
      color: _isPrivate
          ? Colors.amber.withOpacity(0.07)
          : Colors.white.withOpacity(0.04),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => _onTogglePrivate(!_isPrivate),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.fromLTRB(12, 12, 6, 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: _isPrivate
                  ? Colors.amber.withOpacity(0.35)
                  : Colors.white.withOpacity(0.08),
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: Colors.amber.withOpacity(0.13),
                  borderRadius: BorderRadius.circular(11),
                ),
                child: Icon(
                  _isPrivate ? Icons.lock_rounded : Icons.lock_open_rounded,
                  color: Colors.amber,
                  size: 18,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Text(
                          'Evento privado',
                          style: TextStyle(
                            fontFamily: 'Poppins',
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.amber.withOpacity(0.15),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: const Text(
                            'PLUS',
                            style: TextStyle(
                              fontFamily: 'Poppins',
                              color: Colors.amber,
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      'Solo pueden unirse usuarios Plus que tengan la contraseña — el resto de funciones son iguales',
                      style: TextStyle(
                        fontFamily: 'Poppins',
                        color: Colors.white.withOpacity(0.45),
                        fontSize: 11.5,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
              Switch(
                value: _isPrivate,
                onChanged: _onTogglePrivate,
                activeThumbColor: Colors.amber,
                activeTrackColor: Colors.amber.withOpacity(0.35),
                inactiveThumbColor: Colors.white54,
                inactiveTrackColor: Colors.white.withOpacity(0.08),
                trackOutlineColor:
                    const WidgetStatePropertyAll(Colors.transparent),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _locationStatus() {
    final ok = _latitude != null && _longitude != null;
    final color = ok ? Colors.greenAccent : Colors.orange;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      child: Row(
        children: [
          Icon(
            ok ? Icons.check_circle_rounded : Icons.warning_amber_rounded,
            color: color,
            size: 16,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              ok
                  ? 'Ubicación lista · ${_latitude!.toStringAsFixed(4)}, ${_longitude!.toStringAsFixed(4)}'
                  : 'Toca "Mi ubicación" o elige el punto en el mapa',
              style: TextStyle(
                fontFamily: 'Poppins',
                color: color,
                fontSize: 12,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

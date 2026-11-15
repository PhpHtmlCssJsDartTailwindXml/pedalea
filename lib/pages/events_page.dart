import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/events_service.dart';
import '../core/glass.dart';
import '../core/confirm_word_dialog.dart';
import '../services/subscription_service.dart';
import 'create_event_page.dart';
import 'event_chat_page.dart';
import 'paywall_page.dart';

class EventsPage extends StatefulWidget {
  const EventsPage({super.key});

  @override
  State<EventsPage> createState() => _EventsPageState();
}

class _EventsPageState extends State<EventsPage> {
  final EventsService _eventsService = EventsService();
  List<Map<String, dynamic>> _events = [];
  bool _loading = true;
  String? _userId;
  String? _userEmail;

  @override
  void initState() {
    super.initState();
    _userId = Supabase.instance.client.auth.currentUser?.id;
    _userEmail = Supabase.instance.client.auth.currentUser?.email;
    _loadEvents();
    _eventsService.streamUpcomingEvents().listen((events) {
      if (mounted) setState(() => _events = events);
    });
  }

  Future<void> _loadEvents() async {
    setState(() => _loading = true);
    final events = await _eventsService.getUpcomingEvents();
    if (mounted) setState(() { _events = events; _loading = false; });
  }

  Future<void> _joinEvent(Map<String, dynamic> event) async {
    final eventId = event['id'] as String;
    String? password;

    if (event['is_private'] == true) {
      if (!SubscriptionService.instance.isPlus.value) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => const PaywallPage(
              reason: 'Unirte a eventos privados es una función de Pedalea Plus.',
            ),
          ),
        );
        return;
      }
      password = await _askEventPassword();
      if (password == null) return; // canceló el diálogo
    }

    final result = await _eventsService.joinEvent(eventId, password: password);
    if (!mounted) return;
    switch (result) {
      case 'ok':
        await _loadEvents();
        _showSnack('Te has unido al evento');
        break;
      case 'wrong_password':
        _showSnack('Contraseña incorrecta', isError: true);
        break;
      case 'full':
        _showSnack('El evento ya no tiene cupo', isError: true);
        break;
      case 'plus_required':
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => const PaywallPage(
              reason: 'Unirte a eventos privados es una función de Pedalea Plus.',
            ),
          ),
        );
        break;
      default:
        _showSnack('No se pudo unir al evento', isError: true);
    }
  }

  /// Pide la contraseña de un evento privado. Devuelve null si el usuario
  /// cancela el diálogo.
  Future<String?> _askEventPassword() async {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        child: GlassBox(
          blur: 20,
          opacity: 0.13,
          radius: 22,
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Evento privado',
                  style: TextStyle(fontFamily: 'Poppins', color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 6),
                const Text(
                  'Pide la contraseña a quien lo creó para unirte.',
                  style: TextStyle(fontFamily: 'Poppins', color: Colors.white60, fontSize: 13),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: controller,
                  obscureText: true,
                  autofocus: true,
                  style: const TextStyle(fontFamily: 'Poppins', color: Colors.white),
                  decoration: InputDecoration(
                    hintText: 'Contraseña',
                    hintStyle: const TextStyle(fontFamily: 'Poppins', color: Colors.white38),
                    filled: true,
                    fillColor: Colors.white.withOpacity(0.06),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                  ),
                ),
                const SizedBox(height: 20),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.pop(ctx),
                      child: const Text('Cancelar', style: TextStyle(fontFamily: 'Poppins', color: Colors.white38)),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton(
                      onPressed: () => Navigator.pop(ctx, controller.text),
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.greenAccent, foregroundColor: Colors.black),
                      child: const Text('Unirme'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _leaveEvent(String eventId) async {
    final confirmed = await confirmWithWord(
      context,
      title: 'Salir del evento',
      message: 'Vas a salir de este evento y perderás tu cupo.',
      requiredWord: 'SALIR',
      confirmLabel: 'Salir',
      confirmColor: Colors.orange,
    );
    if (!confirmed) return;

    final success = await _eventsService.leaveEvent(eventId);
    if (success && mounted) {
      await _loadEvents();
      _showSnack('Has salido del evento', color: Colors.orange);
    }
  }

  Future<void> _cancelEvent(String eventId) async {
    final confirmed = await confirmWithWord(
      context,
      title: 'Cancelar evento',
      message: 'Esto cancela el evento para todos los que se unieron. No se puede deshacer.',
      requiredWord: 'CANCELAR',
      confirmLabel: 'Cancelar evento',
    );
    if (confirmed) {
      final success = await _eventsService.cancelEvent(eventId);
      if (success && mounted) {
        await _loadEvents();
        _showSnack('Evento cancelado', color: Colors.orange);
      }
    }
  }

  void _showSnack(String msg,
      {bool isError = false, Color color = Colors.green}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg, style: const TextStyle(fontFamily: 'Poppins')),
        backgroundColor: isError ? Colors.redAccent : color,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        margin: const EdgeInsets.all(16),
      ),
    );
  }

  int _getAvailableSpots(Map<String, dynamic> event) {
    if (event['max_participants'] == null) return -1;
    return event['max_participants'] - (event['participants_count'] ?? 0);
  }

  // ── Filtros (solo de vista, no cambian los datos) ─────────────────────────
  String _filter = 'all';

  static const _dias = ['LUN', 'MAR', 'MIÉ', 'JUE', 'VIE', 'SÁB', 'DOM'];
  static const _meses = [
    'ENE', 'FEB', 'MAR', 'ABR', 'MAY', 'JUN',
    'JUL', 'AGO', 'SEP', 'OCT', 'NOV', 'DIC',
  ];

  bool _isJoined(Map<String, dynamic> e) =>
      List<String>.from(e['participants_ids'] ?? []).contains(_userId);
  bool _isMine(Map<String, dynamic> e) => e['created_by'] == _userEmail;
  bool _isFull(Map<String, dynamic> e) =>
      e['max_participants'] != null &&
      e['participants_count'] >= e['max_participants'];

  List<Map<String, dynamic>> get _visibleEvents {
    switch (_filter) {
      case 'joined':
        return _events.where((e) => _isJoined(e) && !_isMine(e)).toList();
      case 'mine':
        return _events.where(_isMine).toList();
      case 'open':
        return _events.where((e) => !_isFull(e)).toList();
      default:
        return _events;
    }
  }

  @override
  Widget build(BuildContext context) {
    final visible = _visibleEvents;
    return Scaffold(
      backgroundColor: Colors.transparent,
      extendBodyBehindAppBar: true,
      body: Container(
        decoration: kPageGradient,
        child: Column(
          children: [
            // ── Barra superior ───────────────────────────────────────
            SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                child: Row(
                  children: [
                    _circleButton(
                      icon: Icons.arrow_back_ios_new_rounded,
                      color: Colors.white,
                      size: 18,
                      tooltip: 'Volver',
                      onTap: () => Navigator.pop(context),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Container(
                        height: 48,
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        decoration: _pillBox(),
                        child: Row(
                          children: [
                            const Icon(Icons.event_rounded,
                                color: Colors.greenAccent, size: 20),
                            const SizedBox(width: 10),
                            const Expanded(
                              child: Text(
                                'Próximos eventos',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontFamily: 'Poppins',
                                  color: Colors.white,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 15,
                                ),
                              ),
                            ),
                            if (!_loading)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 2),
                                decoration: BoxDecoration(
                                  color: Colors.greenAccent.withOpacity(0.14),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Text(
                                  '${_events.length}',
                                  style: const TextStyle(
                                    fontFamily: 'Poppins',
                                    color: Colors.greenAccent,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    _circleButton(
                      icon: Icons.refresh_rounded,
                      color: Colors.greenAccent,
                      tooltip: 'Actualizar',
                      onTap: _loadEvents,
                    ),
                  ],
                ),
              ),
            ),

            // ── Chips de filtro ──────────────────────────────────────
            SizedBox(
              height: 54,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                children: [
                  _filterChip('all', 'Todos', Icons.apps_rounded),
                  _filterChip('joined', 'Me uní', Icons.how_to_reg_rounded),
                  _filterChip('mine', 'Organizo', Icons.star_rounded),
                  _filterChip('open', 'Con cupo', Icons.event_available_rounded),
                ],
              ),
            ),

            // ── Aviso compacto ───────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 6, 16, 4),
              child: Row(
                children: [
                  Icon(Icons.visibility_outlined,
                      size: 14, color: Colors.white.withOpacity(0.35)),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'El pin de un evento en el mapa solo lo ven quienes ya se unieron a él.',
                      style: TextStyle(
                        fontFamily: 'Poppins',
                        color: Colors.white.withOpacity(0.38),
                        fontSize: 11,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            Expanded(
              child: _loading
                  ? const Center(
                      child: CircularProgressIndicator(
                        color: Colors.greenAccent,
                        strokeWidth: 2,
                      ),
                    )
                  : visible.isEmpty
                      ? _buildEmpty()
                      : RefreshIndicator(
                          color: Colors.greenAccent,
                          backgroundColor: const Color(0xFF12121C),
                          onRefresh: _loadEvents,
                          child: ListView.builder(
                            padding:
                                const EdgeInsets.fromLTRB(16, 10, 16, 110),
                            itemCount: visible.length,
                            itemBuilder: (context, index) =>
                                _buildEventCard(visible[index]),
                          ),
                        ),
            ),
          ],
        ),
      ),
      floatingActionButton: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(28),
          boxShadow: [
            BoxShadow(
              color: Colors.greenAccent.withOpacity(0.25),
              blurRadius: 18,
              offset: const Offset(0, 5),
            ),
          ],
        ),
        child: FloatingActionButton.extended(
          onPressed: _openCreate,
          icon: const Icon(Icons.add_rounded),
          label: const Text(
            'Crear evento',
            style: TextStyle(
              fontFamily: 'Poppins',
              fontWeight: FontWeight.w600,
            ),
          ),
          backgroundColor: Colors.greenAccent,
          foregroundColor: Colors.black,
          elevation: 0,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
        ),
      ),
    );
  }

  void _openCreate() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const CreateEventPage()),
    ).then((_) => _loadEvents());
  }

  // ── Piezas de estilo (mismo lenguaje que los controles del mapa) ─────────

  BoxDecoration _pillBox({double radius = 24}) => BoxDecoration(
        color: Colors.white.withOpacity(0.08),
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: Colors.white.withOpacity(0.14)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.3),
            blurRadius: 16,
            offset: const Offset(0, 3),
          ),
        ],
      );

  Widget _circleButton({
    required IconData icon,
    required Color color,
    required String tooltip,
    required VoidCallback onTap,
    double size = 21,
  }) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.transparent,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: Ink(
            width: 48,
            height: 48,
            decoration: _pillBox(),
            child: Icon(icon, color: color, size: size),
          ),
        ),
      ),
    );
  }

  Widget _filterChip(String value, String label, IconData icon) {
    final selected = _filter == value;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: GestureDetector(
        onTap: () => setState(() => _filter = value),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            color: selected
                ? Colors.greenAccent.withOpacity(0.16)
                : Colors.white.withOpacity(0.06),
            borderRadius: BorderRadius.circular(19),
            border: Border.all(
              color: selected
                  ? Colors.greenAccent.withOpacity(0.55)
                  : Colors.white.withOpacity(0.12),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon,
                  size: 15,
                  color: selected ? Colors.greenAccent : Colors.white54),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  fontFamily: 'Poppins',
                  color: selected ? Colors.greenAccent : Colors.white70,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _infoChip(IconData icon, String text, {Color? color, bool flexible = false}) {
    final c = color ?? Colors.white60;
    final label = Text(
      text,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        fontFamily: 'Poppins',
        color: c,
        fontSize: 11.5,
        fontWeight: FontWeight.w500,
      ),
    );
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.06),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: c),
          const SizedBox(width: 5),
          flexible ? Flexible(child: label) : label,
        ],
      ),
    );
  }

  Widget _buildEmpty() {
    final filtered = _filter != 'all' && _events.isNotEmpty;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 84,
              height: 84,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.greenAccent.withOpacity(0.08),
                border: Border.all(color: Colors.greenAccent.withOpacity(0.2)),
              ),
              child: Icon(
                filtered ? Icons.filter_alt_off_rounded : Icons.event_busy_rounded,
                size: 36,
                color: Colors.greenAccent.withOpacity(0.7),
              ),
            ),
            const SizedBox(height: 18),
            Text(
              filtered ? 'Nada en este filtro' : 'No hay eventos próximos',
              style: const TextStyle(
                fontFamily: 'Poppins',
                color: Colors.white,
                fontSize: 17,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              filtered
                  ? 'Prueba con otro filtro o mira todos los eventos.'
                  : '¡Sé el primero en crear uno!',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: 'Poppins',
                color: Colors.white.withOpacity(0.45),
                fontSize: 13.5,
              ),
            ),
            const SizedBox(height: 20),
            OutlinedButton.icon(
              onPressed: filtered
                  ? () => setState(() => _filter = 'all')
                  : _openCreate,
              icon: Icon(
                filtered ? Icons.apps_rounded : Icons.add_rounded,
                size: 18,
              ),
              label: Text(filtered ? 'Ver todos' : 'Crear evento'),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.greenAccent,
                side: BorderSide(color: Colors.greenAccent.withOpacity(0.5)),
                backgroundColor: Colors.greenAccent.withOpacity(0.08),
                padding:
                    const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(24)),
                textStyle: const TextStyle(
                  fontFamily: 'Poppins',
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEventCard(Map<String, dynamic> event) {
    final isCreator = _isMine(event);
    final isJoined = _isJoined(event);
    final isFull = _isFull(event);
    final eventDate = DateTime.parse(event['event_date']).toLocal();
    final isPast = eventDate.isBefore(DateTime.now());
    final availableSpots = _getAvailableSpots(event);
    final maxP = (event['max_participants'] as num?)?.toInt();
    final count = ((event['participants_count'] ?? 0) as num).toInt();
    final description = (event['description'] as String?) ?? '';

    final accentColor = isCreator
        ? Colors.orange
        : isPast
            ? Colors.white38
            : isFull
                ? Colors.redAccent
                : Colors.greenAccent;

    final time =
        '${eventDate.hour.toString().padLeft(2, '0')}:${eventDate.minute.toString().padLeft(2, '0')}';

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withOpacity(0.09)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.3),
            blurRadius: 18,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Bloque de fecha ──────────────────────────────
                Container(
                  width: 58,
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  decoration: BoxDecoration(
                    color: accentColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: accentColor.withOpacity(0.3)),
                  ),
                  child: Column(
                    children: [
                      Text(
                        _dias[eventDate.weekday - 1],
                        style: TextStyle(
                          fontFamily: 'Poppins',
                          color: accentColor,
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.6,
                        ),
                      ),
                      Text(
                        '${eventDate.day}',
                        style: const TextStyle(
                          fontFamily: 'Poppins',
                          color: Colors.white,
                          fontSize: 22,
                          fontWeight: FontWeight.w700,
                          height: 1.15,
                        ),
                      ),
                      Text(
                        _meses[eventDate.month - 1],
                        style: TextStyle(
                          fontFamily: 'Poppins',
                          color: Colors.white.withOpacity(0.5),
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.6,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 14),

                // ── Contenido ────────────────────────────────────
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              event['title'],
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontFamily: 'Poppins',
                                color: Colors.white,
                                fontWeight: FontWeight.w600,
                                fontSize: 15.5,
                                height: 1.25,
                              ),
                            ),
                          ),
                          if (event['is_private'] == true) ...[
                            const SizedBox(width: 6),
                            const Icon(Icons.lock_rounded,
                                size: 14, color: Colors.amber),
                          ],
                        ],
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          _infoChip(Icons.schedule_rounded, '$time hrs'),
                          if (isCreator)
                            _infoChip(Icons.star_rounded, 'Organizas',
                                color: Colors.orange)
                          else if (isJoined)
                            _infoChip(Icons.check_circle_rounded, 'Te uniste',
                                color: Colors.greenAccent),
                          if (isPast)
                            _infoChip(Icons.history_rounded, 'Finalizado'),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Icon(Icons.location_on_rounded,
                              size: 14, color: Colors.white.withOpacity(0.45)),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              event['location_name'],
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontFamily: 'Poppins',
                                color: Colors.white.withOpacity(0.55),
                                fontSize: 12,
                              ),
                            ),
                          ),
                        ],
                      ),
                      if (description.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Text(
                          description,
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontFamily: 'Poppins',
                            color: Colors.white.withOpacity(0.65),
                            fontSize: 12.5,
                            height: 1.4,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),

          // ── Pie: cupos + acciones ────────────────────────────
          Container(
            padding: const EdgeInsets.fromLTRB(14, 10, 12, 12),
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.15),
              borderRadius:
                  const BorderRadius.vertical(bottom: Radius.circular(24)),
              border: Border(
                top: BorderSide(color: Colors.white.withOpacity(0.06)),
              ),
            ),
            child: Row(
              children: [
                // Participantes (se achica para que la acción siempre se vea)
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.people_alt_rounded,
                              size: 15, color: Colors.white.withOpacity(0.5)),
                          const SizedBox(width: 5),
                          Flexible(
                            child: Text(
                              maxP != null
                                  ? (isFull || isPast
                                      ? '$count/$maxP'
                                      : '$count/$maxP · $availableSpots libres')
                                  : '$count ${count == 1 ? 'ciclista' : 'ciclistas'}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontFamily: 'Poppins',
                                color: Colors.white.withOpacity(0.7),
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ],
                      ),
                      if (maxP != null && maxP > 0) ...[
                        const SizedBox(height: 6),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(3),
                          child: LinearProgressIndicator(
                            value: (count / maxP).clamp(0.0, 1.0),
                            minHeight: 4,
                            backgroundColor: Colors.white.withOpacity(0.08),
                            valueColor: AlwaysStoppedAnimation(
                                accentColor.withOpacity(0.85)),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 10),

                // Chat
                if (!isPast && (isJoined || isCreator)) ...[
                  Tooltip(
                    message: 'Chat del evento',
                    child: Material(
                      color: Colors.blueAccent.withOpacity(0.12),
                      shape: const CircleBorder(),
                      child: InkWell(
                        customBorder: const CircleBorder(),
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => EventChatPage(
                              eventId: event['id'],
                              eventTitle: event['title'],
                            ),
                          ),
                        ),
                        child: Container(
                          width: 38,
                          height: 38,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(
                                color: Colors.blueAccent.withOpacity(0.3)),
                          ),
                          child: const Icon(Icons.forum_rounded,
                              color: Colors.blueAccent, size: 18),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                ],

                // Acción principal
                if (!isPast)
                  isCreator
                      ? _actionButton(
                          label: 'Cancelar',
                          color: Colors.redAccent,
                          onTap: () => _cancelEvent(event['id']),
                        )
                      : isJoined
                          ? _actionButton(
                              label: 'Salir',
                              color: Colors.redAccent,
                              onTap: () => _leaveEvent(event['id']),
                            )
                          : isFull
                              ? _actionButton(
                                  label: 'Completo',
                                  color: Colors.white24,
                                  onTap: null,
                                )
                              : _actionButton(
                                  label: 'Unirse',
                                  icon: Icons.add_rounded,
                                  color: Colors.greenAccent,
                                  onTap: () => _joinEvent(event),
                                  filled: true,
                                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _actionButton({
    required String label,
    required Color color,
    required VoidCallback? onTap,
    bool filled = false,
    IconData? icon,
  }) {
    return Material(
      color: filled ? color : color.withOpacity(0.1),
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          height: 38,
          padding: EdgeInsets.only(left: icon != null ? 12 : 16, right: 16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: color.withOpacity(filled ? 0 : 0.4)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 17, color: filled ? Colors.black : color),
                const SizedBox(width: 4),
              ],
              Text(
                label,
                style: TextStyle(
                  fontFamily: 'Poppins',
                  color: filled ? Colors.black : color,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

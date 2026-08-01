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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      extendBodyBehindAppBar: true,
      body: Container(
        decoration: kPageGradient,
        child: Column(
          children: [
            // AppBar glass
            SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                child: Row(
                  children: [
                    GestureDetector(
                      onTap: () => Navigator.pop(context),
                      child: Container(
                        width: 40,
                        height: 40,
                        decoration: glassDecoration(radius: 12),
                        child: const Icon(
                          Icons.arrow_back_ios_new,
                          color: Colors.white,
                          size: 18,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    const Text(
                      'Próximos Eventos',
                      style: TextStyle(
                        fontFamily: 'Poppins',
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                        fontSize: 18,
                      ),
                    ),
                    const Spacer(),
                    GestureDetector(
                      onTap: _loadEvents,
                      child: Container(
                        width: 40,
                        height: 40,
                        decoration: glassDecoration(radius: 12),
                        child: const Icon(
                          Icons.refresh,
                          color: Colors.greenAccent,
                          size: 20,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
              child: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.05),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    Icon(Icons.info_outline, size: 15, color: Colors.grey[400]),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'El pin de un evento en el mapa solo lo ven quienes ya se unieron a él.',
                        style: TextStyle(fontFamily: 'Poppins', color: Colors.grey[400], fontSize: 11.5, height: 1.3),
                      ),
                    ),
                  ],
                ),
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
                  : _events.isEmpty
                      ? _buildEmpty()
                      : ListView.builder(
                          padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
                          itemCount: _events.length,
                          itemBuilder: (context, index) =>
                              _buildEventCard(_events[index]),
                        ),
            ),
          ],
        ),
      ),
      floatingActionButton: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.greenAccent.withOpacity(0.2),
              blurRadius: 16,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: FloatingActionButton.extended(
          onPressed: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const CreateEventPage()),
          ).then((_) => _loadEvents()),
          icon: const Icon(Icons.add),
          label: const Text(
            'Crear Evento',
            style: TextStyle(
              fontFamily: 'Poppins',
              fontWeight: FontWeight.w600,
            ),
          ),
          backgroundColor: Colors.greenAccent,
          foregroundColor: Colors.black,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        ),
      ),
    );
  }

  Widget _buildEmpty() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 80,
            height: 80,
            decoration: glassDecoration(radius: 40),
            child: const Icon(Icons.event_busy,
                size: 36, color: Colors.white24),
          ),
          const SizedBox(height: 20),
          const Text(
            'No hay eventos próximos',
            style: TextStyle(
              fontFamily: 'Poppins',
              color: Colors.white60,
              fontSize: 17,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            '¡Sé el primero en crear uno!',
            style: TextStyle(
              fontFamily: 'Poppins',
              color: Colors.white24,
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEventCard(Map<String, dynamic> event) {
    final isCreator = event['created_by'] == _userEmail;
    final participantsIds =
        List<String>.from(event['participants_ids'] ?? []);
    final isJoined = participantsIds.contains(_userId);
    final isFull = event['max_participants'] != null &&
        event['participants_count'] >= event['max_participants'];
    final eventDate = DateTime.parse(event['event_date']).toLocal();
    final isPast = eventDate.isBefore(DateTime.now());
    final availableSpots = _getAvailableSpots(event);

    final accentColor = isCreator
        ? Colors.orange
        : isPast
            ? Colors.white38
            : isFull
                ? Colors.redAccent
                : Colors.greenAccent;

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: glassDecoration(radius: 20),
      child: Column(
        children: [
          // Header de la tarjeta
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: accentColor.withOpacity(0.12),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: accentColor.withOpacity(0.3),
                      width: 1,
                    ),
                  ),
                  child: Icon(
                    isCreator
                        ? Icons.star
                        : isPast
                            ? Icons.event_busy
                            : isFull
                                ? Icons.event_busy
                                : Icons.event,
                    color: accentColor,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              event['title'],
                              style: const TextStyle(
                                fontFamily: 'Poppins',
                                color: Colors.white,
                                fontWeight: FontWeight.w600,
                                fontSize: 16,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (event['is_private'] == true) ...[
                            const SizedBox(width: 6),
                            const Icon(Icons.lock, size: 14, color: Colors.amber),
                          ],
                        ],
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Icon(Icons.calendar_today,
                              size: 12, color: Colors.white38),
                          const SizedBox(width: 4),
                          Text(
                            '${eventDate.day}/${eventDate.month}/${eventDate.year} ${eventDate.hour}:${eventDate.minute.toString().padLeft(2, '0')}',
                            style: const TextStyle(
                              fontFamily: 'Poppins',
                              color: Colors.white38,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          const Icon(Icons.location_on,
                              size: 12, color: Colors.white38),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              event['location_name'],
                              style: const TextStyle(
                                fontFamily: 'Poppins',
                                color: Colors.white38,
                                fontSize: 12,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                      if (event['description'] != null &&
                          event['description'].isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Text(
                          event['description'],
                          style: const TextStyle(
                            fontFamily: 'Poppins',
                            color: Colors.white60,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Footer
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              border: Border(
                top: BorderSide(color: Colors.white.withOpacity(0.06)),
              ),
            ),
            child: Row(
              children: [
                // Participantes (grupo achicable para no forzar overflow
                // en pantallas angostas; el botón de acción siempre debe verse)
                Expanded(
                  child: Row(
                    children: [
                      const Icon(Icons.people, size: 15, color: Colors.white38),
                      const SizedBox(width: 5),
                      Flexible(
                        child: Text(
                          '${event['participants_count']}${event['max_participants'] != null ? '/${event['max_participants']}' : ''}',
                          overflow: TextOverflow.ellipsis,
                          maxLines: 1,
                          style: const TextStyle(
                            fontFamily: 'Poppins',
                            color: Colors.white38,
                            fontSize: 13,
                          ),
                        ),
                      ),
                      if (event['max_participants'] != null &&
                          !isFull &&
                          !isPast) ...[
                        const SizedBox(width: 4),
                        Flexible(
                          child: Text(
                            '($availableSpots libres)',
                            overflow: TextOverflow.ellipsis,
                            maxLines: 1,
                            style: TextStyle(
                              fontFamily: 'Poppins',
                              color: Colors.greenAccent.withOpacity(0.7),
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ],
                      if (isCreator) ...[
                        const SizedBox(width: 10),
                        Flexible(
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.orange.withOpacity(0.12),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                  color: Colors.orange.withOpacity(0.3), width: 1),
                            ),
                            child: const Text(
                              'Organizador',
                              overflow: TextOverflow.ellipsis,
                              maxLines: 1,
                              style: TextStyle(
                                fontFamily: 'Poppins',
                                color: Colors.orange,
                                fontSize: 11,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),

                // Chat
                if (!isPast && (isJoined || isCreator)) ...[
                  GestureDetector(
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
                      width: 36,
                      height: 36,
                      margin: const EdgeInsets.only(right: 8),
                      decoration: BoxDecoration(
                        color: Colors.blueAccent.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                            color: Colors.blueAccent.withOpacity(0.25)),
                      ),
                      child: const Icon(Icons.chat,
                          color: Colors.blueAccent, size: 17),
                    ),
                  ),
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
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: filled ? color : color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withOpacity(filled ? 0 : 0.4)),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontFamily: 'Poppins',
            color: filled ? Colors.black : color,
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

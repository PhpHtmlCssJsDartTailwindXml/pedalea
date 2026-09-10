import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'notification_service.dart';

/// Escucha en tiempo real los mensajes nuevos de **todos los grupos (eventos)
/// en los que participa el usuario** y muestra una notificación local cuando
/// alguien escribe y el usuario no está mirando ese chat.
///
/// Funciona con la app abierta o en segundo plano (mientras el sistema
/// mantenga viva la conexión). No cubre la app completamente cerrada: para
/// eso haría falta push (FCM).
///
/// No hace falta filtrar por participante en el cliente: la política RLS de
/// `event_messages` (SELECT solo para participantes) hace que Realtime solo
/// entregue los mensajes de los grupos del usuario.
class ChatNotificationsService {
  ChatNotificationsService._();
  static final ChatNotificationsService instance = ChatNotificationsService._();

  SupabaseClient get _sb => Supabase.instance.client;

  RealtimeChannel? _channel;
  StreamSubscription<AuthState>? _authSub;

  /// `event_id` del chat que el usuario tiene abierto ahora mismo. Lo fija
  /// [EventChatPage] al entrar y lo limpia al salir, para no notificar los
  /// mensajes del chat que ya está viendo.
  static String? activeEventId;

  final Map<String, String> _eventTitles = {};
  final Map<String, String> _senderNames = {};

  /// Se llama una vez al arrancar la app.
  void start() {
    _authSub ??= _sb.auth.onAuthStateChange.listen((state) {
      switch (state.event) {
        case AuthChangeEvent.signedIn:
        case AuthChangeEvent.initialSession:
        case AuthChangeEvent.tokenRefreshed:
          _subscribe();
          break;
        case AuthChangeEvent.signedOut:
          _unsubscribe();
          break;
        default:
          break;
      }
    });
    if (_sb.auth.currentUser != null) _subscribe();
  }

  void _subscribe() {
    final uid = _sb.auth.currentUser?.id;
    if (uid == null || _channel != null) return;
    _channel = _sb.channel('chat-notifs-$uid');
    _channel!
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'event_messages',
          callback: _onInsert,
        )
        .subscribe();
  }

  void _unsubscribe() {
    final ch = _channel;
    if (ch != null) {
      _sb.removeChannel(ch);
      _channel = null;
    }
    _eventTitles.clear();
    _senderNames.clear();
  }

  Future<void> _onInsert(PostgresChangePayload payload) async {
    try {
      final row = payload.newRecord;
      final uid = _sb.auth.currentUser?.id;
      if (uid == null) return;

      final senderId = row['user_id'] as String?;
      final eventId = row['event_id'] as String?;
      if (senderId == null || eventId == null) return;
      if (senderId == uid) return; // mensaje propio
      if (activeEventId == eventId) return; // ya está viendo ese chat

      final text = (row['message'] as String?)?.trim() ?? '';
      final title = await _eventTitle(eventId);
      final sender = await _senderName(senderId);

      await NotificationService.instance.showChatMessage(
        eventId: eventId,
        groupTitle: title,
        sender: sender,
        body: text.isEmpty ? 'Envió un mensaje' : text,
      );
    } catch (e) {
      debugPrint('ChatNotificationsService._onInsert: $e');
    }
  }

  Future<String> _eventTitle(String eventId) async {
    final cached = _eventTitles[eventId];
    if (cached != null) return cached;
    try {
      final r = await _sb
          .from('events')
          .select('title')
          .eq('id', eventId)
          .maybeSingle();
      final t = (r?['title'] as String?)?.trim();
      final value = (t == null || t.isEmpty) ? 'Grupo' : t;
      _eventTitles[eventId] = value;
      return value;
    } catch (_) {
      return 'Grupo';
    }
  }

  Future<String> _senderName(String userId) async {
    final cached = _senderNames[userId];
    if (cached != null) return cached;
    try {
      final r = await _sb
          .from('profiles')
          .select('username, full_name')
          .eq('id', userId)
          .maybeSingle();
      final u = (r?['username'] as String?)?.trim();
      final f = (r?['full_name'] as String?)?.trim();
      final value = (u != null && u.isNotEmpty)
          ? u
          : (f != null && f.isNotEmpty ? f : 'Alguien');
      _senderNames[userId] = value;
      return value;
    } catch (_) {
      return 'Alguien';
    }
  }
}

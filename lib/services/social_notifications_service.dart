import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'notification_service.dart';

/// Escucha en tiempo real la actividad social del usuario y lanza
/// notificaciones locales:
///  - alguien te envía una solicitud de seguimiento
///  - alguien acepta tu solicitud
///  - alguien reacciona o comenta uno de tus momentos
///
/// Funciona con la app abierta o en segundo plano (no con la app cerrada del
/// todo).
class SocialNotificationsService {
  SocialNotificationsService._();
  static final SocialNotificationsService instance =
      SocialNotificationsService._();

  SupabaseClient get _sb => Supabase.instance.client;

  RealtimeChannel? _channel;
  StreamSubscription<AuthState>? _authSub;
  final Map<String, String> _names = {};

  void start() {
    _authSub ??= _sb.auth.onAuthStateChange.listen((state) {
      switch (state.event) {
        case AuthChangeEvent.signedIn:
        case AuthChangeEvent.initialSession:
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
    final me = _sb.auth.currentUser?.id;
    if (me == null || _channel != null) return;
    _channel = _sb.channel('social-notifs-$me');
    _channel!
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'follows',
          filter: PostgresChangeFilter(
              column: 'following_id',
              value: me,
              type: PostgresChangeFilterType.eq),
          callback: _onFollowInsert,
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'follows',
          filter: PostgresChangeFilter(
              column: 'follower_id',
              value: me,
              type: PostgresChangeFilterType.eq),
          callback: _onFollowUpdate,
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'post_likes',
          filter: PostgresChangeFilter(
              column: 'post_author_id',
              value: me,
              type: PostgresChangeFilterType.eq),
          callback: _onLike,
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'post_comments',
          filter: PostgresChangeFilter(
              column: 'post_author_id',
              value: me,
              type: PostgresChangeFilterType.eq),
          callback: _onComment,
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'post_comments',
          filter: PostgresChangeFilter(
              column: 'reply_to_user_id',
              value: me,
              type: PostgresChangeFilterType.eq),
          callback: _onReply,
        )
        .subscribe();
  }

  void _unsubscribe() {
    final ch = _channel;
    if (ch != null) {
      _sb.removeChannel(ch);
      _channel = null;
    }
    _names.clear();
  }

  Future<void> _onFollowInsert(PostgresChangePayload p) async {
    final row = p.newRecord;
    if (row['status'] != 'pending') return;
    final from = row['follower_id'] as String?;
    if (from == null) return;
    final name = await _name(from);
    await NotificationService.instance.showSocial(
      id: 300001,
      title: 'Nueva solicitud de seguimiento',
      body: '$name quiere seguirte',
      payload: 'follow_req',
    );
  }

  Future<void> _onFollowUpdate(PostgresChangePayload p) async {
    final row = p.newRecord;
    if (row['status'] != 'accepted') return;
    final who = row['following_id'] as String?; // quien aceptó
    if (who == null) return;
    final name = await _name(who);
    await NotificationService.instance.showSocial(
      id: 300002,
      title: 'Te aceptaron',
      body: '$name aceptó tu solicitud de seguimiento',
      payload: 'follow_accept|$who',
    );
  }

  Future<void> _onLike(PostgresChangePayload p) async {
    final row = p.newRecord;
    final who = row['user_id'] as String?;
    final me = _sb.auth.currentUser?.id;
    if (who == null || who == me) return;
    final name = await _name(who);
    await NotificationService.instance.showSocial(
      id: 300100,
      title: 'A $name le gustó tu momento',
      body: 'Toca para ver tu perfil',
      payload: 'post_activity|$me',
    );
  }

  Future<void> _onComment(PostgresChangePayload p) async {
    final row = p.newRecord;
    // Las respuestas las maneja _onReply (para no duplicar la notificación).
    if (row['parent_id'] != null) return;
    final who = row['user_id'] as String?;
    final me = _sb.auth.currentUser?.id;
    if (who == null || who == me) return;
    final name = await _name(who);
    final body = (row['body'] as String?)?.trim() ?? '';
    await NotificationService.instance.showSocial(
      id: 300101,
      title: 'Nuevo comentario en tu momento',
      body: body.isEmpty ? '$name comentó tu momento' : '$name: $body',
      payload: 'post_activity|$me',
    );
  }

  Future<void> _onReply(PostgresChangePayload p) async {
    final row = p.newRecord;
    final who = row['user_id'] as String?;
    final me = _sb.auth.currentUser?.id;
    if (who == null || who == me) return;
    final name = await _name(who);
    final body = (row['body'] as String?)?.trim() ?? '';
    await NotificationService.instance.showSocial(
      id: 300102,
      title: '$name respondió tu comentario',
      body: body.isEmpty ? 'Toca para ver' : body,
      payload: 'post_activity|$me',
    );
  }

  Future<String> _name(String userId) async {
    final cached = _names[userId];
    if (cached != null) return cached;
    try {
      final r = await _sb
          .from('profiles')
          .select('username, full_name')
          .eq('id', userId)
          .maybeSingle();
      final u = (r?['username'] as String?)?.trim();
      final f = (r?['full_name'] as String?)?.trim();
      final v = (u != null && u.isNotEmpty)
          ? u
          : (f != null && f.isNotEmpty ? f : 'Alguien');
      _names[userId] = v;
      return v;
    } catch (_) {
      return 'Alguien';
    }
  }
}

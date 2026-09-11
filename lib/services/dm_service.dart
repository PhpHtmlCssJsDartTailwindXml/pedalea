import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Mensajes directos 1 a 1. Solo entre usuarios con follow mutuo y sin
/// bloqueo (lo obliga la BD). El envío va por el RPC `dm_send`; el cliente
/// solo lee y marca como leído.
class DmService {
  DmService._();
  static final DmService instance = DmService._();

  SupabaseClient get _sb => Supabase.instance.client;
  String? get _uid => _sb.auth.currentUser?.id;

  Future<Map<String, Map<String, dynamic>>> _profilesByIds(
      List<String> ids) async {
    if (ids.isEmpty) return {};
    final rows = await _sb
        .from('profiles')
        .select('id, username, full_name, avatar_url, is_plus, plus_badge_variant')
        .inFilter('id', ids);
    return {
      for (final r in rows) r['id'] as String: Map<String, dynamic>.from(r)
    };
  }

  /// Lista de conversaciones con la otra persona, último mensaje y no leídos.
  Future<List<Map<String, dynamic>>> threads() async {
    final me = _uid;
    if (me == null) return [];
    try {
      final rows = await _sb
          .from('dm_threads')
          .select('id, user_a, user_b, last_body, last_at, last_sender')
          .or('user_a.eq.$me,user_b.eq.$me')
          .order('last_at', ascending: false, nullsFirst: false);
      final list = rows.map((r) => Map<String, dynamic>.from(r)).toList();
      if (list.isEmpty) return [];

      final others = <String>{
        for (final t in list)
          (t['user_a'] == me ? t['user_b'] : t['user_a']) as String
      }.toList();
      final profs = await _profilesByIds(others);

      // No leídos por hilo.
      final unreadRows = await _sb
          .from('dm_messages')
          .select('thread_id')
          .eq('recipient_id', me)
          .isFilter('read_at', null);
      final unread = <String, int>{};
      for (final u in unreadRows) {
        final tid = u['thread_id'] as String;
        unread[tid] = (unread[tid] ?? 0) + 1;
      }

      for (final t in list) {
        final otherId =
            (t['user_a'] == me ? t['user_b'] : t['user_a']) as String;
        t['other'] = profs[otherId] ?? {'id': otherId};
        t['unread'] = unread[t['id']] ?? 0;
        t['mine_last'] = t['last_sender'] == me;
      }
      return list;
    } catch (e) {
      debugPrint('DmService.threads: $e');
      return [];
    }
  }

  Future<int> totalUnread() async {
    final me = _uid;
    if (me == null) return 0;
    try {
      final rows = await _sb
          .from('dm_messages')
          .select('id')
          .eq('recipient_id', me)
          .isFilter('read_at', null);
      return rows.length;
    } catch (_) {
      return 0;
    }
  }

  /// id del hilo con [otherUserId], o null si aún no existe.
  Future<String?> threadIdWith(String otherUserId) async {
    final me = _uid;
    if (me == null) return null;
    final a = me.compareTo(otherUserId) < 0 ? me : otherUserId;
    final b = me.compareTo(otherUserId) < 0 ? otherUserId : me;
    try {
      final r = await _sb
          .from('dm_threads')
          .select('id')
          .eq('user_a', a)
          .eq('user_b', b)
          .maybeSingle();
      return r?['id'] as String?;
    } catch (e) {
      debugPrint('DmService.threadIdWith: $e');
      return null;
    }
  }

  Future<List<Map<String, dynamic>>> messages(String threadId) async {
    try {
      final rows = await _sb
          .from('dm_messages')
          .select('id, sender_id, recipient_id, body, created_at, read_at')
          .eq('thread_id', threadId)
          .order('created_at', ascending: true);
      return rows.map((r) => Map<String, dynamic>.from(r)).toList();
    } catch (e) {
      debugPrint('DmService.messages: $e');
      return [];
    }
  }

  /// Envía un mensaje. Devuelve el id del hilo. Lanza si no está permitido.
  Future<String?> send(String recipientId, String body) async {
    try {
      final res = await _sb.rpc('dm_send', params: {
        'p_recipient': recipientId,
        'p_body': body.trim(),
      });
      return res as String?;
    } catch (e) {
      debugPrint('DmService.send: $e');
      rethrow;
    }
  }

  Future<void> markRead(String threadId) async {
    final me = _uid;
    if (me == null) return;
    try {
      await _sb
          .from('dm_messages')
          .update({'read_at': DateTime.now().toUtc().toIso8601String()})
          .eq('thread_id', threadId)
          .eq('recipient_id', me)
          .isFilter('read_at', null);
    } catch (e) {
      debugPrint('DmService.markRead: $e');
    }
  }
}

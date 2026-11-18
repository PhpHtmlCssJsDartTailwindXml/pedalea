import 'dart:io';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Mensajes directos 1 a 1. Solo entre usuarios con follow mutuo y sin
/// bloqueo (lo obliga la BD). El envío va por el RPC `dm_send`; el cliente
/// solo lee y marca como leído.
///
/// Fotos, audios, responder y "eliminar para todos" requieren la migración
/// `supabase/migrations/20261012232603_dm_rich_messages.sql`. Mientras no esté
/// aplicada, el servicio funciona en modo texto (como antes) y
/// [richSupported] queda en false.
class DmService {
  DmService._();
  static final DmService instance = DmService._();

  static const _bucket = 'dm-media';
  static const _baseCols = 'id, sender_id, recipient_id, body, created_at, read_at';
  static const _richCols =
      '$_baseCols, kind, media_path, media_duration_ms, reply_to, deleted_at';

  SupabaseClient get _sb => Supabase.instance.client;
  String? get _uid => _sb.auth.currentUser?.id;

  /// null = aún no se sabe; se detecta en la primera lectura de mensajes.
  bool? richSupported;

  final Map<String, (String, DateTime)> _signedUrls = {};

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
          .not('last_at', 'is', null)
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

      // Estado de lectura de mi último mensaje en cada hilo (para ✓✓).
      final mineLastIds = [
        for (final t in list)
          if (t['last_sender'] == me) t['id'] as String
      ];
      final lastRead = <String, bool>{};
      if (mineLastIds.isNotEmpty) {
        final reads = await _sb
            .from('dm_messages')
            .select('thread_id, read_at, created_at')
            .inFilter('thread_id', mineLastIds)
            .eq('sender_id', me)
            .order('created_at', ascending: false);
        for (final r in reads) {
          final tid = r['thread_id'] as String;
          lastRead.putIfAbsent(tid, () => r['read_at'] != null);
        }
      }

      for (final t in list) {
        final otherId =
            (t['user_a'] == me ? t['user_b'] : t['user_a']) as String;
        t['other'] = profs[otherId] ?? {'id': otherId};
        t['unread'] = unread[t['id']] ?? 0;
        t['mine_last'] = t['last_sender'] == me;
        t['last_read'] = lastRead[t['id']] ?? false;
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

  /// Crea el hilo si no existe (necesario para subir una foto o audio antes
  /// del primer mensaje). Requiere la migración.
  Future<String> ensureThread(String otherUserId) async {
    try {
      final res = await _sb
          .rpc('dm_ensure_thread', params: {'p_recipient': otherUserId});
      return res as String;
    } on PostgrestException catch (e) {
      // PGRST202 = la función no existe → migración no aplicada.
      if (e.code == 'PGRST202') richSupported = false;
      rethrow;
    }
  }

  Future<List<Map<String, dynamic>>> messages(String threadId) async {
    Future<List<Map<String, dynamic>>> load(String cols) async {
      final rows = await _sb
          .from('dm_messages')
          .select(cols)
          .eq('thread_id', threadId)
          .order('created_at', ascending: true);
      return rows.map((r) => Map<String, dynamic>.from(r)).toList();
    }

    if (richSupported != false) {
      try {
        final r = await load(_richCols);
        richSupported = true;
        return r;
      } on PostgrestException catch (e) {
        // 42703 = columna inexistente → la migración aún no está aplicada.
        if (e.code == '42703' || e.message.contains('does not exist')) {
          richSupported = false;
        } else {
          debugPrint('DmService.messages: $e');
          return [];
        }
      } catch (e) {
        debugPrint('DmService.messages: $e');
        return [];
      }
    }
    try {
      return await load(_baseCols);
    } catch (e) {
      debugPrint('DmService.messages: $e');
      return [];
    }
  }

  /// Envía un mensaje. Devuelve el id del hilo. Lanza si no está permitido.
  Future<String?> send(
    String recipientId,
    String body, {
    String kind = 'text',
    String? mediaPath,
    int? durationMs,
    String? replyTo,
  }) async {
    final simple = kind == 'text' && replyTo == null;
    try {
      final res = await _sb.rpc('dm_send', params: {
        'p_recipient': recipientId,
        'p_body': body.trim(),
        if (!simple) ...{
          'p_kind': kind,
          'p_media_path': mediaPath,
          'p_media_duration_ms': durationMs,
          'p_reply_to': replyTo,
        },
      });
      return res as String?;
    } catch (e) {
      debugPrint('DmService.send: $e');
      rethrow;
    }
  }

  String _rand() {
    final r = Random.secure();
    return List.generate(12, (_) => r.nextInt(36).toRadixString(36)).join();
  }

  /// Sube una foto o audio al bucket privado y devuelve su ruta.
  Future<String> uploadMedia(
    String threadId,
    File file, {
    required String ext,
    required String contentType,
  }) async {
    final me = _uid!;
    final path =
        '$threadId/$me/${DateTime.now().millisecondsSinceEpoch}_${_rand()}.$ext';
    await _sb.storage.from(_bucket).upload(
          path,
          file,
          fileOptions: FileOptions(contentType: contentType, upsert: false),
        );
    return path;
  }

  /// Borra un archivo propio (p. ej. si falló el envío después de subirlo).
  Future<void> removeMedia(String path) async {
    try {
      await _sb.storage.from(_bucket).remove([path]);
    } catch (e) {
      debugPrint('DmService.removeMedia: $e');
    }
  }

  /// URL firmada (1 h) para ver/escuchar un archivo del chat. Se cachea.
  Future<String?> mediaUrl(String path) async {
    final cached = _signedUrls[path];
    if (cached != null && cached.$2.isAfter(DateTime.now())) return cached.$1;
    try {
      final url = await _sb.storage.from(_bucket).createSignedUrl(path, 3600);
      _signedUrls[path] =
          (url, DateTime.now().add(const Duration(minutes: 55)));
      return url;
    } catch (e) {
      debugPrint('DmService.mediaUrl: $e');
      return null;
    }
  }

  /// Elimina un mensaje propio para ambos (y su archivo, si tenía).
  Future<void> deleteForAll(String messageId) async {
    final path = await _sb.rpc('dm_delete', params: {'p_message': messageId});
    if (path is String && path.isNotEmpty) {
      try {
        await _sb.storage.from(_bucket).remove([path]);
      } catch (e) {
        debugPrint('DmService.deleteForAll storage: $e');
      }
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

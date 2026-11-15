import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Un aviso guardado en el centro de notificaciones.
class InboxItem {
  final String id;
  final String type;
  final String title;
  final String body;
  final String payload;
  final DateTime createdAt;
  final bool read;

  const InboxItem({
    required this.id,
    required this.type,
    required this.title,
    required this.body,
    required this.payload,
    required this.createdAt,
    required this.read,
  });

  factory InboxItem.fromRow(Map<String, dynamic> r) => InboxItem(
        id: r['id'] as String,
        type: r['type'] as String? ?? '',
        title: r['title'] as String? ?? '',
        body: r['body'] as String? ?? '',
        payload: r['payload'] as String? ?? '',
        createdAt:
            DateTime.tryParse(r['created_at'] as String? ?? '')?.toLocal() ??
                DateTime.now(),
        read: r['read_at'] != null,
      );
}

/// Centro de notificaciones: los avisos que también llegan como push
/// (seguidores, me gusta, comentarios, impacto de reportes, nuevas versiones)
/// quedan guardados para revisarlos desde el menú aunque el push se haya
/// descartado. Los inserta la Edge Function send-push.
class InboxService {
  InboxService._();
  static final InboxService instance = InboxService._();

  SupabaseClient get _db => Supabase.instance.client;
  String? get _uid => _db.auth.currentUser?.id;

  /// Cantidad de avisos sin leer (para el globo del menú).
  final ValueNotifier<int> unread = ValueNotifier(0);

  Future<int> refreshUnread() async {
    final uid = _uid;
    if (uid == null) {
      unread.value = 0;
      return 0;
    }
    try {
      final rows = await _db
          .from('notifications')
          .select('id')
          .eq('user_id', uid)
          .isFilter('read_at', null)
          .limit(100);
      unread.value = rows.length;
    } catch (e) {
      debugPrint('InboxService.refreshUnread: $e');
    }
    return unread.value;
  }

  Future<List<InboxItem>> list({int limit = 60}) async {
    final uid = _uid;
    if (uid == null) return [];
    try {
      final rows = await _db
          .from('notifications')
          .select('id, type, title, body, payload, read_at, created_at')
          .eq('user_id', uid)
          .order('created_at', ascending: false)
          .limit(limit);
      return rows.map((r) => InboxItem.fromRow(r)).toList();
    } catch (e) {
      debugPrint('InboxService.list: $e');
      return [];
    }
  }

  /// Marca como leídas [ids], o todas si es null.
  Future<void> markRead([List<String>? ids]) async {
    try {
      await _db.rpc('mark_notifications_read', params: {'p_ids': ids});
    } catch (e) {
      debugPrint('InboxService.markRead: $e');
    }
    await refreshUnread();
  }

  Future<void> delete(String id) async {
    try {
      await _db.from('notifications').delete().eq('id', id);
    } catch (e) {
      debugPrint('InboxService.delete: $e');
    }
    await refreshUnread();
  }
}

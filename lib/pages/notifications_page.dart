import 'package:flutter/material.dart';
import '../core/time_format.dart';
import '../services/inbox_service.dart';
import '../services/notification_service.dart';

const _bg = Color(0xFF0F1117);
const _accent = Color(0xFF7CF0BC);

/// Centro de notificaciones: lista de avisos recibidos, con los no leídos
/// destacados. Al tocar uno se marca como leído y se abre la pantalla que
/// corresponde (el mismo destino que el push).
class NotificationsPage extends StatefulWidget {
  const NotificationsPage({super.key});

  @override
  State<NotificationsPage> createState() => _NotificationsPageState();
}

class _NotificationsPageState extends State<NotificationsPage> {
  final _inbox = InboxService.instance;
  List<InboxItem> _items = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final items = await _inbox.list();
    if (!mounted) return;
    setState(() {
      _items = items;
      _loading = false;
    });
    _inbox.refreshUnread();
  }

  Future<void> _open(InboxItem n) async {
    if (!n.read) {
      await _inbox.markRead([n.id]);
      _load();
    }
    if (n.payload.isNotEmpty) NotificationService.openPayload(n.payload);
  }

  Future<void> _markAll() async {
    await _inbox.markRead();
    _load();
  }

  (IconData, Color) _iconFor(String type) {
    switch (type) {
      case 'follow_req':
        return (Icons.person_add_alt_1_rounded, const Color(0xFF64B5F6));
      case 'follow_accept':
        return (Icons.how_to_reg_rounded, const Color(0xFF64B5F6));
      case 'like':
        return (Icons.favorite_rounded, const Color(0xFFFF6B81));
      case 'comment':
      case 'reply':
        return (Icons.mode_comment_rounded, _accent);
      case 'alert_impact':
        return (Icons.volunteer_activism_rounded, const Color(0xFFF2C94C));
      case 'app_update':
        return (Icons.system_update_rounded, const Color(0xFFB39DDB));
      case 'plus_promo':
        return (Icons.workspace_premium_rounded, const Color(0xFFF2C94C));
      case 'weekly_summary':
        return (Icons.insights_rounded, _accent);
      case 'streak_reminder':
        return (Icons.local_fire_department_rounded, const Color(0xFFFF8A50));
      default:
        return (Icons.notifications_rounded, Colors.white70);
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasUnread = _items.any((n) => !n.read);
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _bg,
        elevation: 0,
        foregroundColor: Colors.white,
        title: const Text('Notificaciones',
            style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w700, fontSize: 18)),
        actions: [
          if (hasUnread)
            TextButton(
              onPressed: _markAll,
              child: const Text('Marcar todas',
                  style: TextStyle(fontFamily: 'Poppins', color: _accent, fontSize: 13)),
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: _accent))
          : RefreshIndicator(
              color: _accent,
              backgroundColor: const Color(0xFF1A1D26),
              onRefresh: _load,
              child: _items.isEmpty ? _empty() : _list(),
            ),
    );
  }

  Widget _empty() {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        const SizedBox(height: 140),
        Icon(Icons.notifications_none_rounded, size: 56, color: Colors.white.withOpacity(0.25)),
        const SizedBox(height: 14),
        Text('No tienes notificaciones',
            textAlign: TextAlign.center,
            style: TextStyle(fontFamily: 'Poppins', color: Colors.white.withOpacity(0.7), fontSize: 15)),
        const SizedBox(height: 6),
        Text('Aquí verás seguidores, me gusta, comentarios\ny el impacto de tus reportes.',
            textAlign: TextAlign.center,
            style: TextStyle(fontFamily: 'Poppins', color: Colors.white.withOpacity(0.4), fontSize: 12.5)),
      ],
    );
  }

  Widget _list() {
    return ListView.separated(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: _items.length,
      separatorBuilder: (_, _) =>
          Divider(height: 1, indent: 72, color: Colors.white.withOpacity(0.06)),
      itemBuilder: (_, i) {
        final n = _items[i];
        final (icon, color) = _iconFor(n.type);
        return Dismissible(
          key: ValueKey(n.id),
          direction: DismissDirection.endToStart,
          background: Container(
            color: Colors.redAccent.withOpacity(0.15),
            alignment: Alignment.centerRight,
            padding: const EdgeInsets.only(right: 24),
            child: const Icon(Icons.delete_outline_rounded, color: Colors.redAccent),
          ),
          onDismissed: (_) {
            setState(() => _items.removeAt(i));
            _inbox.delete(n.id);
          },
          child: InkWell(
            onTap: () => _open(n),
            child: Container(
              color: n.read ? Colors.transparent : _accent.withOpacity(0.05),
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: color.withOpacity(0.14),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(icon, color: color, size: 21),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(n.title,
                            style: TextStyle(
                                fontFamily: 'Poppins',
                                color: Colors.white,
                                fontSize: 13.5,
                                fontWeight: n.read ? FontWeight.w500 : FontWeight.w700)),
                        if (n.body.isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Text(n.body,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  fontFamily: 'Poppins',
                                  color: Colors.white.withOpacity(0.6),
                                  fontSize: 12.5)),
                        ],
                        const SizedBox(height: 4),
                        Text(timeAgoLong(n.createdAt),
                            style: TextStyle(
                                fontFamily: 'Poppins',
                                color: Colors.white.withOpacity(0.35),
                                fontSize: 11)),
                      ],
                    ),
                  ),
                  if (!n.read)
                    Container(
                      margin: const EdgeInsets.only(left: 8, top: 6),
                      width: 9,
                      height: 9,
                      decoration: const BoxDecoration(color: _accent, shape: BoxShape.circle),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

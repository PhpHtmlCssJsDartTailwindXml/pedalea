import 'dart:async';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../core/glass.dart';
import '../services/dm_service.dart';
import '../widgets/plus_medal.dart';
import 'dm_thread_page.dart';

/// Lista de conversaciones directas.
class MessagesPage extends StatefulWidget {
  const MessagesPage({super.key});

  @override
  State<MessagesPage> createState() => _MessagesPageState();
}

class _MessagesPageState extends State<MessagesPage> {
  final _dm = DmService.instance;
  final _sb = Supabase.instance.client;
  List<Map<String, dynamic>> _threads = [];
  bool _loading = true;
  RealtimeChannel? _channel;

  String get _me => _sb.auth.currentUser?.id ?? '';

  @override
  void initState() {
    super.initState();
    _load();
    _channel = _sb
        .channel('dm-list-$_me')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'dm_messages',
          callback: (_) => _load(),
        )
        .subscribe();
  }

  @override
  void dispose() {
    _channel?.unsubscribe();
    super.dispose();
  }

  Future<void> _load() async {
    final t = await _dm.threads();
    if (!mounted) return;
    setState(() {
      _threads = t;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBgDark,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        title: const Text('Mensajes',
            style: TextStyle(
                fontFamily: 'Poppins',
                color: Colors.white,
                fontWeight: FontWeight.w700)),
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: Colors.greenAccent))
          : _threads.isEmpty
              ? RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    children: [
                      const SizedBox(height: 120),
                      Icon(Icons.forum_outlined,
                          size: 44, color: Colors.white.withOpacity(0.25)),
                      const SizedBox(height: 12),
                      Center(
                        child: Text('No tienes conversaciones',
                            style: TextStyle(
                                fontFamily: 'Poppins',
                                color: Colors.white.withOpacity(0.5))),
                      ),
                      const SizedBox(height: 4),
                      Center(
                        child: Text(
                          'Escríbele a alguien desde su perfil\n(solo si se siguen mutuamente)',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                              fontFamily: 'Poppins',
                              color: Colors.white.withOpacity(0.3),
                              fontSize: 12),
                        ),
                      ),
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView.separated(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    itemCount: _threads.length,
                    separatorBuilder: (_, _) => Divider(
                        color: Colors.white.withOpacity(0.05),
                        height: 1,
                        indent: 76),
                    itemBuilder: (_, i) => _tile(_threads[i]),
                  ),
                ),
    );
  }

  Widget _tile(Map<String, dynamic> t) {
    final other = (t['other'] as Map?)?.cast<String, dynamic>() ?? const {};
    final u = (other['username'] as String?)?.trim();
    final f = (other['full_name'] as String?)?.trim();
    final name = (f != null && f.isNotEmpty)
        ? f
        : (u != null && u.isNotEmpty ? u : 'Ciclista');
    final avatar = (other['avatar_url'] as String?) ?? '';
    final isPlus = other['is_plus'] == true;
    final unread = (t['unread'] as num?)?.toInt() ?? 0;
    final mineLast = t['mine_last'] == true;
    final last = (t['last_body'] as String?) ?? '';
    final at = DateTime.tryParse(t['last_at'] as String? ?? '')?.toLocal();
    final when = at == null
        ? ''
        : (DateTime.now().difference(at).inDays == 0
            ? '${at.hour.toString().padLeft(2, '0')}:${at.minute.toString().padLeft(2, '0')}'
            : '${at.day}/${at.month}');

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => DmThreadPage(
            otherUserId: other['id'] as String,
            otherName: name,
            otherAvatar: avatar,
            otherIsPlus: isPlus,
            otherBadgeVariant:
                (other['plus_badge_variant'] as num?)?.toInt() ?? 0,
          ),
        ),
      ).then((_) => _load()),
      leading: Stack(
        clipBehavior: Clip.none,
        children: [
          CircleAvatar(
            radius: 24,
            backgroundColor: Colors.white12,
            backgroundImage:
                avatar.isNotEmpty ? CachedNetworkImageProvider(avatar) : null,
            child: avatar.isEmpty
                ? Text(name.substring(0, 1).toUpperCase(),
                    style: const TextStyle(
                        fontFamily: 'Poppins', color: Colors.white))
                : null,
          ),
          if (isPlus)
            Positioned(
              bottom: -3,
              right: -3,
              child: PlusMedal(
                  size: 15,
                  variant: (other['plus_badge_variant'] as num?)?.toInt() ?? 0,
                  ringColor: kBgDark),
            ),
        ],
      ),
      title: Text(name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
              fontFamily: 'Poppins',
              color: Colors.white,
              fontWeight: unread > 0 ? FontWeight.w700 : FontWeight.w600,
              fontSize: 14.5)),
      subtitle: Text(
        '${mineLast ? 'Tú: ' : ''}$last',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontFamily: 'Poppins',
          color: unread > 0
              ? Colors.white.withOpacity(0.85)
              : Colors.white.withOpacity(0.45),
          fontSize: 12.5,
        ),
      ),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(when,
              style: TextStyle(
                  fontFamily: 'Poppins',
                  color: Colors.white.withOpacity(0.35),
                  fontSize: 10)),
          const SizedBox(height: 4),
          if (unread > 0)
            Container(
              padding: const EdgeInsets.all(5),
              decoration: const BoxDecoration(
                  color: Color(0xFF69FF47), shape: BoxShape.circle),
              constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
              child: Text('$unread',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      fontFamily: 'Poppins',
                      color: Colors.black,
                      fontSize: 9,
                      fontWeight: FontWeight.w800)),
            ),
        ],
      ),
    );
  }
}

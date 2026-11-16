import 'dart:async';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../core/glass.dart';
import '../core/time_format.dart';
import '../services/dm_service.dart';
import '../widgets/plus_medal.dart';
import 'dm_thread_page.dart';
import 'public_profile_page.dart';

const _kAccent = Color(0xFF69FF47);

/// Lista de conversaciones directas.
class MessagesPage extends StatefulWidget {
  const MessagesPage({super.key});

  @override
  State<MessagesPage> createState() => _MessagesPageState();
}

class _MessagesPageState extends State<MessagesPage> {
  final _dm = DmService.instance;
  final _sb = Supabase.instance.client;
  final _search = TextEditingController();
  List<Map<String, dynamic>> _threads = [];
  bool _loading = true;
  RealtimeChannel? _channel;
  Timer? _ticker;
  Timer? _debounce;

  String get _me => _sb.auth.currentUser?.id ?? '';

  @override
  void initState() {
    super.initState();
    _load();
    _search.addListener(() => setState(() {}));
    // Mensajes nuevos, leídos o eliminados → refresca la lista.
    _channel = _sb
        .channel('dm-list-$_me')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'dm_messages',
          callback: (_) => _scheduleLoad(),
        )
        .subscribe();
    _ticker = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {}); // refresca "hace X"
    });
  }

  @override
  void dispose() {
    _channel?.unsubscribe();
    _ticker?.cancel();
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  void _scheduleLoad() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), _load);
  }

  Future<void> _load() async {
    final t = await _dm.threads();
    if (!mounted) return;
    setState(() {
      _threads = t;
      _loading = false;
    });
  }

  String _nameOf(Map<String, dynamic> other) {
    final u = (other['username'] as String?)?.trim();
    final f = (other['full_name'] as String?)?.trim();
    return (f != null && f.isNotEmpty)
        ? f
        : (u != null && u.isNotEmpty ? u : 'Ciclista');
  }

  List<Map<String, dynamic>> get _visible {
    final q = _search.text.trim().toLowerCase();
    if (q.isEmpty) return _threads;
    return _threads.where((t) {
      final o = (t['other'] as Map?)?.cast<String, dynamic>() ?? const {};
      return _nameOf(o).toLowerCase().contains(q) ||
          ((o['username'] as String?) ?? '').toLowerCase().contains(q);
    }).toList();
  }

  BoxDecoration _pillBox() => BoxDecoration(
        color: Colors.white.withOpacity(0.08),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withOpacity(0.14)),
      );

  @override
  Widget build(BuildContext context) {
    final totalUnread = _threads.fold<int>(
        0, (s, t) => s + ((t['unread'] as num?)?.toInt() ?? 0));
    final visible = _visible;
    return Scaffold(
      backgroundColor: kBgDark,
      body: Container(
        decoration: kPageGradient,
        child: SafeArea(
          bottom: false,
          child: Column(
            children: [
              // ── Barra superior ─────────────────────────────────────
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                child: Row(
                  children: [
                    Material(
                      color: Colors.transparent,
                      shape: const CircleBorder(),
                      child: InkWell(
                        customBorder: const CircleBorder(),
                        onTap: () => Navigator.pop(context),
                        child: Ink(
                          width: 48,
                          height: 48,
                          decoration: _pillBox(),
                          child: const Icon(Icons.arrow_back_ios_new_rounded,
                              color: Colors.white, size: 18),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Container(
                        height: 48,
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        decoration: _pillBox(),
                        child: Row(
                          children: [
                            const Icon(Icons.forum_rounded,
                                color: _kAccent, size: 20),
                            const SizedBox(width: 10),
                            const Expanded(
                              child: Text(
                                'Mensajes',
                                style: TextStyle(
                                  fontFamily: 'Poppins',
                                  color: Colors.white,
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            if (totalUnread > 0)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 2),
                                decoration: BoxDecoration(
                                  color: _kAccent,
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Text(
                                  '$totalUnread',
                                  style: const TextStyle(
                                    fontFamily: 'Poppins',
                                    color: Colors.black,
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              // ── Buscador ───────────────────────────────────────────
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
                child: TextField(
                  controller: _search,
                  style: const TextStyle(
                      fontFamily: 'Poppins', color: Colors.white, fontSize: 14),
                  cursorColor: _kAccent,
                  decoration: InputDecoration(
                    hintText: 'Buscar conversación',
                    hintStyle: TextStyle(
                        fontFamily: 'Poppins',
                        color: Colors.white.withOpacity(0.35)),
                    prefixIcon: Icon(Icons.search_rounded,
                        color: Colors.white.withOpacity(0.45)),
                    suffixIcon: _search.text.isEmpty
                        ? null
                        : IconButton(
                            onPressed: () => _search.clear(),
                            icon: Icon(Icons.close_rounded,
                                color: Colors.white.withOpacity(0.5), size: 18),
                          ),
                    filled: true,
                    fillColor: Colors.white.withOpacity(0.05),
                    contentPadding: const EdgeInsets.symmetric(vertical: 12),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(22),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
              ),

              Expanded(
                child: _loading
                    ? const Center(
                        child: CircularProgressIndicator(
                            color: _kAccent, strokeWidth: 2))
                    : RefreshIndicator(
                        onRefresh: _load,
                        color: _kAccent,
                        backgroundColor: const Color(0xFF12121C),
                        child: visible.isEmpty
                            ? _empty(searching: _search.text.isNotEmpty)
                            : ListView.builder(
                                physics: const AlwaysScrollableScrollPhysics(),
                                padding:
                                    const EdgeInsets.fromLTRB(8, 4, 8, 24),
                                itemCount: visible.length,
                                itemBuilder: (_, i) => _tile(visible[i]),
                              ),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _empty({required bool searching}) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 40),
      children: [
        const SizedBox(height: 100),
        Center(
          child: Container(
            width: 84,
            height: 84,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: _kAccent.withOpacity(0.08),
              border: Border.all(color: _kAccent.withOpacity(0.25)),
            ),
            child: Icon(
              searching ? Icons.search_off_rounded : Icons.forum_outlined,
              size: 36,
              color: _kAccent.withOpacity(0.8),
            ),
          ),
        ),
        const SizedBox(height: 16),
        Text(
          searching ? 'Sin resultados' : 'No tienes conversaciones',
          textAlign: TextAlign.center,
          style: const TextStyle(
              fontFamily: 'Poppins',
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 6),
        Text(
          searching
              ? 'Prueba con otro nombre.'
              : 'Escríbele a alguien desde su perfil (solo si se siguen mutuamente).',
          textAlign: TextAlign.center,
          style: TextStyle(
              fontFamily: 'Poppins',
              color: Colors.white.withOpacity(0.45),
              fontSize: 13),
        ),
      ],
    );
  }

  Widget _tile(Map<String, dynamic> t) {
    final other = (t['other'] as Map?)?.cast<String, dynamic>() ?? const {};
    final name = _nameOf(other);
    final avatar = (other['avatar_url'] as String?) ?? '';
    final isPlus = other['is_plus'] == true;
    final unread = (t['unread'] as num?)?.toInt() ?? 0;
    final mineLast = t['mine_last'] == true;
    final lastRead = t['last_read'] == true;
    final last = (t['last_body'] as String?) ?? '';
    final at = DateTime.tryParse(t['last_at'] as String? ?? '')?.toLocal();
    final hasUnread = unread > 0;

    return Material(
      color: hasUnread ? _kAccent.withOpacity(0.05) : Colors.transparent,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
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
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
          child: Row(
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  Container(
                    padding: const EdgeInsets.all(2),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: hasUnread ? _kAccent : Colors.transparent,
                        width: 2,
                      ),
                    ),
                    child: GestureDetector(
                     onTap: () => Navigator.push(
                       context,
                       MaterialPageRoute(
                           builder: (_) => PublicProfilePage(
                               userId: other['id'] as String)),
                     ),
                     child: CircleAvatar(
                      radius: 25,
                      backgroundColor: Colors.white12,
                      backgroundImage: avatar.isNotEmpty
                          ? ResizeImage(CachedNetworkImageProvider(avatar), width: 256)
                          : null,
                      child: avatar.isEmpty
                          ? Text(name.substring(0, 1).toUpperCase(),
                              style: const TextStyle(
                                  fontFamily: 'Poppins',
                                  color: Colors.white,
                                  fontSize: 17))
                          : null,
                     ),
                    ),
                  ),
                  if (isPlus)
                    Positioned(
                      bottom: -2,
                      right: -2,
                      child: PlusMedal(
                          size: 16,
                          variant:
                              (other['plus_badge_variant'] as num?)?.toInt() ??
                                  0,
                          ringColor: kBgDark),
                    ),
                ],
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontFamily: 'Poppins',
                              color: Colors.white,
                              fontWeight:
                                  hasUnread ? FontWeight.w700 : FontWeight.w600,
                              fontSize: 15,
                            ),
                          ),
                        ),
                        if (at != null)
                          Text(
                            timeAgoShort(at),
                            style: TextStyle(
                              fontFamily: 'Poppins',
                              color: hasUnread
                                  ? _kAccent
                                  : Colors.white.withOpacity(0.4),
                              fontSize: 11,
                              fontWeight:
                                  hasUnread ? FontWeight.w700 : FontWeight.w400,
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        if (mineLast) ...[
                          Icon(
                            lastRead
                                ? Icons.done_all_rounded
                                : Icons.done_rounded,
                            size: 16,
                            color: lastRead
                                ? const Color(0xFF4FC3F7)
                                : Colors.white.withOpacity(0.45),
                          ),
                          const SizedBox(width: 4),
                        ],
                        Expanded(
                          child: Text(
                            last,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontFamily: 'Poppins',
                              color: hasUnread
                                  ? Colors.white.withOpacity(0.9)
                                  : Colors.white.withOpacity(0.5),
                              fontSize: 13,
                              fontWeight:
                                  hasUnread ? FontWeight.w500 : FontWeight.w400,
                              fontStyle: last.startsWith('🚫')
                                  ? FontStyle.italic
                                  : FontStyle.normal,
                            ),
                          ),
                        ),
                        if (hasUnread) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 7, vertical: 2),
                            constraints: const BoxConstraints(minWidth: 20),
                            decoration: BoxDecoration(
                              color: _kAccent,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(
                              unread > 99 ? '99+' : '$unread',
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                fontFamily: 'Poppins',
                                color: Colors.black,
                                fontSize: 10.5,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

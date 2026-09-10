import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../core/glass.dart';
import '../services/social_service.dart';
import '../services/subscription_service.dart';
import '../widgets/post_card.dart';
import '../widgets/comments_sheet.dart';
import 'create_moment_page.dart';
import 'public_profile_page.dart';
import 'follow_requests_page.dart';
import 'paywall_page.dart';

/// Feed de "Momentos": el diario en fotos de la comunidad. Todos lo ven;
/// reaccionar y comentar solo entre quienes se siguen mutuamente. Plan gratis:
/// 2 momentos al día; Plus: ilimitado.
class MomentsPage extends StatefulWidget {
  const MomentsPage({super.key});

  @override
  State<MomentsPage> createState() => _MomentsPageState();
}

class _MomentsPageState extends State<MomentsPage> {
  final _social = SocialService.instance;
  final _scroll = ScrollController();
  final _myId = Supabase.instance.client.auth.currentUser?.id;

  final List<Map<String, dynamic>> _posts = [];
  Set<String> _mutual = {};
  int _pendingReqs = 0;
  int _postsToday = 0;
  String _myAvatar = '';
  bool _loading = true;
  bool _loadingMore = false;
  bool _reachedEnd = false;

  bool get _isPlus => SubscriptionService.instance.isPlus.value;
  bool get _canPostToday =>
      _isPlus || _postsToday < SocialService.freeDailyPostLimit;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(() {
      if (_scroll.position.pixels > _scroll.position.maxScrollExtent - 600) {
        _loadMore();
      }
    });
    _refresh();
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    final results = await Future.wait([
      _social.feed(limit: 12),
      _social.mutualFollowIds(),
      _social.pendingRequestCount(),
      _social.myPostsToday(),
      if (_myId case final id?) _social.profile(id) else Future.value(null),
    ]);
    if (!mounted) return;
    setState(() {
      _posts
        ..clear()
        ..addAll((results[0] as List).cast<Map<String, dynamic>>());
      _mutual = results[1] as Set<String>;
      _pendingReqs = results[2] as int;
      _postsToday = results[3] as int;
      _myAvatar =
          ((results[4] as Map<String, dynamic>?)?['avatar_url'] as String?) ??
              '';
      _loading = false;
      _reachedEnd = _posts.length < 12;
    });
  }

  Future<void> _loadMore() async {
    if (_loadingMore || _reachedEnd || _posts.isEmpty) return;
    setState(() => _loadingMore = true);
    final last = DateTime.tryParse(_posts.last['created_at'] as String? ?? '');
    final more = await _social.feed(limit: 12, before: last);
    if (!mounted) return;
    setState(() {
      _posts.addAll(more.cast<Map<String, dynamic>>());
      _reachedEnd = more.length < 12;
      _loadingMore = false;
    });
  }

  bool _canInteract(Map<String, dynamic> post) {
    final authorId =
        (post['author'] as Map?)?['id'] as String? ?? post['user_id'] as String;
    return _mutual.contains(authorId);
  }

  void _openAuthor(String authorId) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => PublicProfilePage(userId: authorId)),
    ).then((_) => _refresh());
  }

  void _blocked(Map<String, dynamic> post) {
    final authorId =
        (post['author'] as Map?)?['id'] as String? ?? post['user_id'] as String;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: const Text(
        'Reaccionar y comentar solo entre quienes se siguen mutuamente.',
        style: TextStyle(fontFamily: 'Poppins'),
      ),
      action: SnackBarAction(
        label: 'Ver perfil',
        onPressed: () => _openAuthor(authorId),
      ),
    ));
  }

  Future<void> _compose() async {
    if (!_canPostToday) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => const PaywallPage(
            reason:
                'El plan gratis permite 2 momentos al día. Hazte Plus para publicar sin límite.',
          ),
        ),
      );
      return;
    }
    final created = await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const CreateMomentPage()),
    );
    if (created == true) _refresh();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBgDark,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        title: const Text('Momentos',
            style: TextStyle(
                fontFamily: 'Poppins',
                color: Colors.white,
                fontWeight: FontWeight.w700)),
        actions: [
          Stack(
            alignment: Alignment.center,
            children: [
              IconButton(
                icon: const Icon(Icons.group_add_outlined, color: Colors.white),
                tooltip: 'Solicitudes de seguimiento',
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const FollowRequestsPage()),
                ).then((_) => _refresh()),
              ),
              if (_pendingReqs > 0)
                Positioned(
                  right: 8,
                  top: 8,
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: const BoxDecoration(
                        color: Color(0xFFFF4D6D), shape: BoxShape.circle),
                    constraints:
                        const BoxConstraints(minWidth: 16, minHeight: 16),
                    child: Text('$_pendingReqs',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                            fontFamily: 'Poppins',
                            color: Colors.white,
                            fontSize: 9,
                            fontWeight: FontWeight.w700)),
                  ),
                ),
            ],
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: const Color(0xFF69FF47),
        foregroundColor: Colors.black,
        icon: const Icon(Icons.add_a_photo_rounded),
        label: const Text('Compartir',
            style:
                TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w700)),
        onPressed: _compose,
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: Colors.greenAccent))
          : RefreshIndicator(
              onRefresh: _refresh,
              child: ListView.builder(
                controller: _scroll,
                padding: const EdgeInsets.fromLTRB(14, 6, 14, 100),
                itemCount: 1 + // cabecera
                    (_posts.isEmpty ? 1 : _posts.length) +
                    (_reachedEnd || _posts.isEmpty ? 0 : 1),
                itemBuilder: (context, i) {
                  if (i == 0) return _feedHeader();
                  final idx = i - 1;
                  if (_posts.isEmpty) return _emptyState();
                  if (idx >= _posts.length) {
                    return const Padding(
                      padding: EdgeInsets.all(20),
                      child: Center(
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white24),
                      ),
                    );
                  }
                  final post = _posts[idx];
                  final authorId =
                      (post['author'] as Map?)?['id'] as String? ??
                          post['user_id'] as String;
                  return PostCard(
                    key: ValueKey(post['id']),
                    post: post,
                    canInteract: _canInteract(post),
                    isMine: authorId == _myId,
                    onAuthorTap: () => _openAuthor(authorId),
                    onOpenComments: () => showCommentsSheet(
                      context,
                      post: post,
                      canInteract: _canInteract(post),
                      onChanged: _refresh,
                    ),
                    onBlockedInteract: () => _blocked(post),
                    onDeleted: () {
                      setState(() =>
                          _posts.removeWhere((p) => p['id'] == post['id']));
                      _social.myPostsToday().then((n) {
                        if (mounted) setState(() => _postsToday = n);
                      });
                    },
                  );
                },
              ),
            ),
    );
  }

  Widget _feedHeader() {
    final remaining =
        (SocialService.freeDailyPostLimit - _postsToday).clamp(0, 99);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 6),
        Text('El diario de la comunidad',
            style: TextStyle(
                fontFamily: 'Poppins',
                color: Colors.white.withOpacity(0.55),
                fontSize: 12.5,
                letterSpacing: 0.2)),
        const SizedBox(height: 12),
        // Caja "compartir un momento"
        InkWell(
          onTap: _compose,
          borderRadius: BorderRadius.circular(16),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.04),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.white.withOpacity(0.08)),
            ),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 18,
                  backgroundColor: Colors.white12,
                  backgroundImage: _myAvatar.isNotEmpty
                      ? CachedNetworkImageProvider(_myAvatar)
                      : null,
                  child: _myAvatar.isEmpty
                      ? const Icon(Icons.person, color: Colors.white38, size: 18)
                      : null,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    _canPostToday
                        ? 'Comparte un momento lindo…'
                        : 'Llegaste al límite de hoy',
                    style: TextStyle(
                        fontFamily: 'Poppins',
                        color: Colors.white.withOpacity(0.5),
                        fontSize: 13.5),
                  ),
                ),
                Icon(
                  _canPostToday
                      ? Icons.add_a_photo_outlined
                      : Icons.lock_outline_rounded,
                  color: _canPostToday
                      ? const Color(0xFF69FF47)
                      : Colors.white38,
                  size: 20,
                ),
              ],
            ),
          ),
        ),
        if (!_isPlus) ...[
          const SizedBox(height: 6),
          Text(
            remaining > 0
                ? 'Te queda${remaining == 1 ? '' : 'n'} $remaining momento${remaining == 1 ? '' : 's'} hoy · Plus es ilimitado'
                : 'Vuelve mañana o hazte Plus para publicar sin límite',
            style: TextStyle(
                fontFamily: 'Poppins',
                color: Colors.white.withOpacity(0.35),
                fontSize: 11),
          ),
          const SizedBox(height: 14),
          _whyPlusCard(),
        ],
        const SizedBox(height: 16),
        if (_posts.isNotEmpty)
          Divider(color: Colors.white.withOpacity(0.06), height: 1),
        const SizedBox(height: 12),
      ],
    );
  }

  /// Explica dentro de Momentos qué gana el ciclista con Pedalea Plus.
  Widget _whyPlusCard() {
    const perks = <(String, String)>[
      ('♾️', 'Momentos ilimitados cada día'),
      ('🎨', 'Filtros, dibujo y stickers al publicar'),
      ('🔥', 'Mapa de calor de dónde has pedaleado'),
      ('📊', 'Estadísticas avanzadas e histórico completo'),
      ('🏅', 'Medalla con brillo y estilos de mapa exclusivos'),
    ];
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            const Color(0xFF69FF47).withOpacity(0.14),
            const Color(0xFF69FF47).withOpacity(0.03),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF69FF47).withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.workspace_premium_rounded,
                  color: Color(0xFF69FF47), size: 20),
              const SizedBox(width: 8),
              const Text('¿Por qué Pedalea Plus?',
                  style: TextStyle(
                      fontFamily: 'Poppins',
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w700)),
            ],
          ),
          const SizedBox(height: 10),
          for (final p in perks)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(p.$1, style: const TextStyle(fontSize: 13)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(p.$2,
                        style: TextStyle(
                            fontFamily: 'Poppins',
                            color: Colors.white.withOpacity(0.8),
                            fontSize: 12.5)),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 6),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const PaywallPage(
                    reason:
                        'Publica momentos sin límite y desbloquea todo Pedalea Plus.',
                  ),
                ),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF69FF47),
                foregroundColor: Colors.black,
                elevation: 0,
                padding: const EdgeInsets.symmetric(vertical: 11),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
              child: const Text('Ver Pedalea Plus',
                  style: TextStyle(
                      fontFamily: 'Poppins', fontWeight: FontWeight.w700)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _emptyState() {
    return Padding(
      padding: const EdgeInsets.only(top: 60),
      child: Column(
        children: [
          Icon(Icons.auto_awesome_outlined,
              size: 44, color: Colors.white.withOpacity(0.25)),
          const SizedBox(height: 12),
          Text('Aún no hay momentos',
              style: TextStyle(
                  fontFamily: 'Poppins',
                  color: Colors.white.withOpacity(0.5))),
          const SizedBox(height: 4),
          Text('Sé quien abra el diario de la comunidad',
              style: TextStyle(
                  fontFamily: 'Poppins',
                  color: Colors.white.withOpacity(0.3),
                  fontSize: 12)),
        ],
      ),
    );
  }
}

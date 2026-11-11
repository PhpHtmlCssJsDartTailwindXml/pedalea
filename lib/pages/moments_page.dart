import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
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
  static const _green = Colors.greenAccent;
  static const _mint = Color(0xFF7CF0BC);
  static const _pink = Color(0xFFFF4D6D);

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
  bool _fabExtended = true;
  bool _plusExpanded = false;

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
      // El botón "Compartir" se encoge al bajar y vuelve al subir.
      final dir = _scroll.position.userScrollDirection;
      if (dir == ScrollDirection.reverse && _fabExtended) {
        setState(() => _fabExtended = false);
      } else if (dir == ScrollDirection.forward && !_fabExtended) {
        setState(() => _fabExtended = true);
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

  /// Reaccionar/comentar: en tus propios momentos, o con follow mutuo.
  bool _canInteract(Map<String, dynamic> post) {
    final authorId =
        (post['author'] as Map?)?['id'] as String? ?? post['user_id'] as String;
    return authorId == _myId || _mutual.contains(authorId);
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
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text(
          'Reaccionar y comentar solo entre quienes se siguen mutuamente.',
          style: TextStyle(fontFamily: 'Poppins'),
        ),
        action: SnackBarAction(
          label: 'Ver perfil',
          onPressed: () => _openAuthor(authorId),
        ),
      ),
    );
  }

  void _openPaywall(String reason) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => PaywallPage(reason: reason)),
    );
  }

  Future<void> _compose() async {
    if (!_canPostToday) {
      _openPaywall(
        'El plan gratis permite 2 momentos al día. Hazte Plus para publicar sin límite.',
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
      floatingActionButton: _composeFab(),
      body: Stack(
        children: [
          // Brillos de fondo con los colores de acento.
          SafeArea(
            bottom: false,
            child: Column(
              children: [
                _topBar(),
                Expanded(
                  child: _loading
                      ? const Center(
                          child: CircularProgressIndicator(
                            strokeWidth: 2.5,
                            color: _green,
                          ),
                        )
                      : RefreshIndicator(
                          onRefresh: _refresh,
                          color: _green,
                          backgroundColor: const Color(0xFF161622),
                          child: _feed(),
                        ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _roundButton({
    required IconData icon,
    required String tooltip,
    required VoidCallback onTap,
    int badge = 0,
  }) {
    return Tooltip(
      message: tooltip,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Material(
            color: Colors.white.withOpacity(0.07),
            shape: CircleBorder(
              side: BorderSide(color: Colors.white.withOpacity(0.10)),
            ),
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: onTap,
              child: SizedBox(
                width: 44,
                height: 44,
                child: Icon(icon, color: Colors.white, size: 21),
              ),
            ),
          ),
          if (badge > 0)
            Positioned(
              right: -3,
              top: -3,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                constraints: const BoxConstraints(minWidth: 19, minHeight: 19),
                decoration: BoxDecoration(
                  color: _pink,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: kBgDark, width: 2),
                ),
                child: Text(
                  '$badge',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontFamily: 'Poppins',
                    color: Colors.white,
                    fontSize: 9.5,
                    height: 1.1,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _topBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 10),
      child: Row(
        children: [
          _roundButton(
            icon: Icons.arrow_back_rounded,
            tooltip: 'Volver',
            onTap: () => Navigator.maybePop(context),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ShaderMask(
                  blendMode: BlendMode.srcIn,
                  shaderCallback: (r) => const LinearGradient(
                    colors: [Colors.white, _mint, _green],
                    stops: [0.0, 0.6, 1.0],
                  ).createShader(r),
                  child: const Text(
                    'Momentos',
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      color: Colors.white,
                      fontSize: 25,
                      height: 1.15,
                      letterSpacing: -0.4,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                Text(
                  'El diario de la comunidad',
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    color: Colors.white.withOpacity(0.5),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          _roundButton(
            icon: Icons.group_add_outlined,
            tooltip: 'Solicitudes de seguimiento',
            badge: _pendingReqs,
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const FollowRequestsPage()),
            ).then((_) => _refresh()),
          ),
        ],
      ),
    );
  }

  Widget _composeFab() {
    return Semantics(
      button: true,
      label: 'Compartir un momento',
      child: GestureDetector(
        onTap: _compose,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          height: 56,
          padding: EdgeInsets.symmetric(horizontal: _fabExtended ? 20 : 16),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [_green, _mint],
            ),
            borderRadius: BorderRadius.circular(28),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                _canPostToday
                    ? Icons.add_a_photo_rounded
                    : Icons.lock_outline_rounded,
                color: Colors.black,
                size: 23,
              ),
              AnimatedSize(
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeOutCubic,
                child: _fabExtended
                    ? const Padding(
                        padding: EdgeInsets.only(left: 10),
                        child: Text(
                          'Compartir',
                          style: TextStyle(
                            fontFamily: 'Poppins',
                            color: Colors.black,
                            fontSize: 14.5,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      )
                    : const SizedBox.shrink(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _feed() {
    return ListView.builder(
      controller: _scroll,
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(14, 4, 14, 110),
      itemCount:
          1 + // cabecera
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
                strokeWidth: 2,
                color: Colors.white24,
              ),
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
            setState(() => _posts.removeWhere((p) => p['id'] == post['id']));
            _social.myPostsToday().then((n) {
              if (mounted) setState(() => _postsToday = n);
            });
          },
        );
      },
    );
  }

  Widget _feedHeader() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 4),
        _composerCard(),
        if (!_isPlus) ...[
          const SizedBox(height: 12),
          _quotaRow(),
          const SizedBox(height: 12),
          _whyPlusCard(),
        ],
        const SizedBox(height: 22),
        if (_posts.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 12),
            child: Row(
              children: [
                Container(
                  width: 7,
                  height: 7,
                  decoration: BoxDecoration(
                    color: _green,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  'RECIENTES',
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    color: Colors.white.withOpacity(0.55),
                    fontSize: 11,
                    letterSpacing: 1.6,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Container(
                    height: 1,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          Colors.white.withOpacity(0.12),
                          Colors.white.withOpacity(0),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  /// Caja "compartir un momento".
  Widget _composerCard() {
    final can = _canPostToday;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: _compose,
        borderRadius: BorderRadius.circular(24),
        child: Ink(
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                _green.withOpacity(can ? 0.13 : 0.04),
                Colors.white.withOpacity(0.04),
              ],
            ),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: can
                  ? _green.withOpacity(0.22)
                  : Colors.white.withOpacity(0.08),
            ),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(2.2),
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(colors: [_green, _mint]),
                ),
                child: CircleAvatar(
                  radius: 21,
                  backgroundColor: const Color(0xFF161622),
                  backgroundImage: _myAvatar.isNotEmpty
                      ? CachedNetworkImageProvider(_myAvatar)
                      : null,
                  child: _myAvatar.isEmpty
                      ? const Icon(
                          Icons.person,
                          color: Colors.white38,
                          size: 20,
                        )
                      : null,
                ),
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      can
                          ? 'Comparte un momento lindo'
                          : 'Llegaste al límite de hoy',
                      style: const TextStyle(
                        fontFamily: 'Poppins',
                        color: Colors.white,
                        fontSize: 14.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 1),
                    Text(
                      can
                          ? 'Una foto de tu ruta de hoy'
                          : 'Publica sin límite con Plus',
                      style: TextStyle(
                        fontFamily: 'Poppins',
                        color: Colors.white.withOpacity(0.5),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: can ? _green : Colors.white.withOpacity(0.08),
                ),
                child: Icon(
                  can ? Icons.add_a_photo_rounded : Icons.lock_outline_rounded,
                  color: can ? Colors.black : Colors.white54,
                  size: 20,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Cupo diario del plan gratis: un segmento por momento disponible.
  Widget _quotaRow() {
    final limit = SocialService.freeDailyPostLimit;
    final used = _postsToday.clamp(0, limit);
    final remaining = limit - used;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Row(
        children: [
          for (int i = 0; i < limit; i++)
            AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              margin: const EdgeInsets.only(right: 5),
              width: 26,
              height: 6,
              decoration: BoxDecoration(
                color: i < used ? _green : Colors.white.withOpacity(0.12),
                borderRadius: BorderRadius.circular(3),
              ),
            ),
          const SizedBox(width: 5),
          Expanded(
            child: Text(
              remaining > 0
                  ? 'Te queda${remaining == 1 ? '' : 'n'} $remaining momento${remaining == 1 ? '' : 's'} hoy'
                  : 'Vuelve mañana o hazte Plus',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontFamily: 'Poppins',
                color: Colors.white.withOpacity(0.5),
                fontSize: 11.5,
              ),
            ),
          ),
          Text(
            'Plus es ilimitado',
            style: TextStyle(
              fontFamily: 'Poppins',
              color: _green.withOpacity(0.85),
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  /// Explica dentro de Momentos qué gana el ciclista con Pedalea Plus.
  /// Compacta por defecto; se despliega al tocarla.
  Widget _whyPlusCard() {
    const perks = <(String, String)>[
      ('♾️', 'Momentos ilimitados cada día'),
      ('🎨', 'Filtros, dibujo y stickers al publicar'),
      ('🔥', 'Mapa de calor de dónde has pedaleado'),
      ('📊', 'Estadísticas avanzadas e histórico completo'),
      ('🏅', 'Medalla con brillo y estilos de mapa exclusivos'),
    ];
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [_green.withOpacity(0.14), _green.withOpacity(0.03)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: _green.withOpacity(0.3)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () => setState(() => _plusExpanded = !_plusExpanded),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
                child: Row(
                  children: [
                    Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        color: _green.withOpacity(0.16),
                        borderRadius: BorderRadius.circular(13),
                      ),
                      child: const Icon(
                        Icons.workspace_premium_rounded,
                        color: _green,
                        size: 21,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            '¿Por qué Pedalea Plus?',
                            style: TextStyle(
                              fontFamily: 'Poppins',
                              color: Colors.white,
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          Text(
                            'Momentos sin límite y mucho más',
                            style: TextStyle(
                              fontFamily: 'Poppins',
                              color: Colors.white.withOpacity(0.55),
                              fontSize: 11.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                    AnimatedRotation(
                      turns: _plusExpanded ? 0.5 : 0,
                      duration: const Duration(milliseconds: 220),
                      child: const Icon(
                        Icons.keyboard_arrow_down_rounded,
                        color: _green,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 260),
            curve: Curves.easeOutCubic,
            alignment: Alignment.topCenter,
            child: !_plusExpanded
                ? const SizedBox(width: double.infinity)
                : Padding(
                    padding: const EdgeInsets.fromLTRB(14, 2, 14, 14),
                    child: Column(
                      children: [
                        for (final p in perks)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: Row(
                              children: [
                                Container(
                                  width: 30,
                                  height: 30,
                                  alignment: Alignment.center,
                                  decoration: BoxDecoration(
                                    color: Colors.white.withOpacity(0.06),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Text(
                                    p.$1,
                                    style: const TextStyle(fontSize: 14),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    p.$2,
                                    style: TextStyle(
                                      fontFamily: 'Poppins',
                                      color: Colors.white.withOpacity(0.85),
                                      fontSize: 12.5,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        const SizedBox(height: 4),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            onPressed: () => _openPaywall(
                              'Publica momentos sin límite y desbloquea todo Pedalea Plus.',
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: _green,
                              foregroundColor: Colors.black,
                              elevation: 0,
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                            ),
                            child: const Text(
                              'Ver Pedalea Plus',
                              style: TextStyle(
                                fontFamily: 'Poppins',
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _emptyState() {
    return Padding(
      padding: const EdgeInsets.only(top: 36),
      child: Column(
        children: [
          Container(
            width: 96,
            height: 96,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [_green.withOpacity(0.22), _mint.withOpacity(0.06)],
              ),
              border: Border.all(color: _green.withOpacity(0.3)),
            ),
            child: const Icon(
              Icons.auto_awesome_rounded,
              size: 40,
              color: _green,
            ),
          ),
          const SizedBox(height: 18),
          const Text(
            'Aún no hay momentos',
            style: TextStyle(
              fontFamily: 'Poppins',
              color: Colors.white,
              fontSize: 17,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Sé quien abra el diario de la comunidad',
            style: TextStyle(
              fontFamily: 'Poppins',
              color: Colors.white.withOpacity(0.45),
              fontSize: 12.5,
            ),
          ),
          const SizedBox(height: 18),
          OutlinedButton.icon(
            onPressed: _compose,
            icon: const Icon(Icons.add_a_photo_rounded, size: 18),
            label: const Text(
              'Compartir el primero',
              style: TextStyle(
                fontFamily: 'Poppins',
                fontWeight: FontWeight.w600,
              ),
            ),
            style: OutlinedButton.styleFrom(
              foregroundColor: _green,
              side: BorderSide(color: _green.withOpacity(0.5)),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

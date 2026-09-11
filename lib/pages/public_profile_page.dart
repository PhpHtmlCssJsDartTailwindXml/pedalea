import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../core/glass.dart';
import '../services/social_service.dart';
import '../services/co2_service.dart';
import '../widgets/plus_medal.dart';
import '../widgets/post_card.dart';
import '../widgets/comments_sheet.dart';
import 'profile_page.dart';
import 'dm_thread_page.dart';

/// Perfil público de otro ciclista: datos, seguir (con aprobación), contadores
/// y cuadrícula de momentos. Se abre al tocar el autor de un momento.
class PublicProfilePage extends StatefulWidget {
  final String userId;
  const PublicProfilePage({super.key, required this.userId});

  @override
  State<PublicProfilePage> createState() => _PublicProfilePageState();
}

class _PublicProfilePageState extends State<PublicProfilePage> {
  final _social = SocialService.instance;

  Map<String, dynamic>? _profile;
  ({String outgoing, String incoming}) _rel = (outgoing: 'none', incoming: 'none');
  ({int followers, int following}) _counts = (followers: 0, following: 0);
  List<Map<String, dynamic>> _posts = [];
  bool _loading = true;
  bool _busy = false;

  String get _me => Supabase.instance.client.auth.currentUser?.id ?? '';
  bool get _isMe => _me == widget.userId;
  bool get _mutual => _rel.outgoing == 'accepted' && _rel.incoming == 'accepted';

  /// Puede reaccionar y comentar: en sus propios momentos, o con follow mutuo.
  bool get _canInteract => _isMe || _mutual;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final results = await Future.wait([
      _social.profile(widget.userId),
      _social.relationWith(widget.userId),
      _social.counts(widget.userId),
      _social.userPosts(widget.userId),
    ]);
    if (!mounted) return;
    setState(() {
      _profile = results[0] as Map<String, dynamic>?;
      _rel = results[1] as ({String outgoing, String incoming});
      _counts = results[2] as ({int followers, int following});
      _posts = (results[3] as List).cast<Map<String, dynamic>>();
      _loading = false;
    });
  }

  Future<void> _onFollowButton() async {
    if (_isMe) {
      Navigator.push(context,
          MaterialPageRoute(builder: (_) => const ProfilePage()));
      return;
    }
    if (_busy) return;
    setState(() => _busy = true);
    try {
      if (_rel.outgoing == 'none') {
        await _social.requestFollow(widget.userId);
      } else {
        // 'pending' -> cancelar solicitud ; 'accepted' -> dejar de seguir
        await _social.unfollow(widget.userId);
      }
      _rel = await _social.relationWith(widget.userId);
      _counts = await _social.counts(widget.userId);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  ({String label, Color color, bool filled}) get _followBtn {
    if (_isMe) {
      return (label: 'Editar perfil', color: Colors.white24, filled: false);
    }
    switch (_rel.outgoing) {
      case 'accepted':
        return (label: 'Siguiendo', color: Colors.white24, filled: false);
      case 'pending':
        return (label: 'Solicitud enviada', color: Colors.white24, filled: false);
      default:
        return (
          label: _rel.incoming == 'accepted' ? 'Seguir de vuelta' : 'Seguir',
          color: const Color(0xFF69FF47),
          filled: true,
        );
    }
  }

  void _openPost(Map<String, dynamic> post) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF0E0E16),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.9,
        builder: (_, sc) => SingleChildScrollView(
          controller: sc,
          padding: const EdgeInsets.fromLTRB(14, 16, 14, 24),
          child: PostCard(
            post: post,
            canInteract: _canInteract,
            isMine: _isMe,
            onAuthorTap: () {},
            onOpenComments: () => showCommentsSheet(context,
                post: post, canInteract: _canInteract, onChanged: _load),
            onBlockedInteract: _blockedMsg,
            onDeleted: () {
              Navigator.pop(context);
              _load();
            },
          ),
        ),
      ),
    );
  }

  void _openDm() {
    final p = _profile;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => DmThreadPage(
          otherUserId: widget.userId,
          otherName: _displayName(),
          otherAvatar: p?['avatar_url'] as String?,
          otherIsPlus: p?['is_plus'] == true,
          otherBadgeVariant: (p?['plus_badge_variant'] as num?)?.toInt() ?? 0,
        ),
      ),
    );
  }

  void _blockedMsg() {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(
        _rel.outgoing == 'accepted'
            ? 'Esta persona aún no te sigue de vuelta.'
            : 'Síguela y que te acepte para reaccionar y comentar.',
        style: const TextStyle(fontFamily: 'Poppins'),
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final name = _displayName();
    return Scaffold(
      backgroundColor: kBgDark,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text(name,
            style: const TextStyle(
                fontFamily: 'Poppins',
                color: Colors.white,
                fontWeight: FontWeight.w700)),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: Colors.greenAccent))
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                children: [
                  _header(name),
                  const SizedBox(height: 18),
                  if (_posts.isEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 40),
                      child: Center(
                        child: Text('Todavía no publica momentos',
                            style: TextStyle(
                                fontFamily: 'Poppins',
                                color: Colors.white.withOpacity(0.4))),
                      ),
                    )
                  else
                    GridView.count(
                      crossAxisCount: 3,
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      mainAxisSpacing: 3,
                      crossAxisSpacing: 3,
                      children: [
                        for (final p in _posts)
                          GestureDetector(
                            onTap: () => _openPost(p),
                            child: CachedNetworkImage(
                              imageUrl: p['image_url'] as String,
                              fit: BoxFit.cover,
                              placeholder: (_, _) =>
                                  Container(color: Colors.white10),
                              errorWidget: (_, _, _) =>
                                  Container(color: Colors.white10),
                            ),
                          ),
                      ],
                    ),
                ],
              ),
            ),
    );
  }

  String _displayName() {
    final u = (_profile?['username'] as String?)?.trim();
    final f = (_profile?['full_name'] as String?)?.trim();
    if (f != null && f.isNotEmpty) return f;
    if (u != null && u.isNotEmpty) return u;
    return 'Ciclista';
  }

  Widget _header(String name) {
    final avatar = (_profile?['avatar_url'] as String?) ?? '';
    final username = (_profile?['username'] as String?)?.trim() ?? '';
    final commune = (_profile?['commune'] as String?)?.trim() ?? '';
    final km = (_profile?['total_km'] as num?)?.toDouble() ?? 0;
    final isPlus = _profile?['is_plus'] == true;
    final btn = _followBtn;

    return Column(
      children: [
        Stack(
          clipBehavior: Clip.none,
          children: [
            CircleAvatar(
              radius: 44,
              backgroundColor: Colors.white12,
              backgroundImage:
                  avatar.isNotEmpty ? CachedNetworkImageProvider(avatar) : null,
              child: avatar.isEmpty
                  ? Text(name.substring(0, 1).toUpperCase(),
                      style: const TextStyle(
                          fontFamily: 'Poppins',
                          color: Colors.white,
                          fontSize: 30))
                  : null,
            ),
            if (isPlus)
              Positioned(
                bottom: -2,
                right: -2,
                child: PlusMedal(
                  size: 26,
                  variant:
                      (_profile?['plus_badge_variant'] as num?)?.toInt() ?? 0,
                  ringColor: kBgDark,
                ),
              ),
          ],
        ),
        const SizedBox(height: 10),
        Text(name,
            style: const TextStyle(
                fontFamily: 'Poppins',
                color: Colors.white,
                fontSize: 19,
                fontWeight: FontWeight.w700)),
        if (username.isNotEmpty)
          Text('@$username',
              style: const TextStyle(
                  fontFamily: 'Poppins', color: Colors.white38, fontSize: 13)),
        const SizedBox(height: 6),
        Text(
          [
            if (commune.isNotEmpty) commune,
            '${km.toStringAsFixed(0)} km',
            '${Co2Service.format(Co2Service.savedKg(km))} CO₂',
          ].join('  ·  '),
          style: TextStyle(
              fontFamily: 'Poppins',
              color: Colors.white.withOpacity(0.55),
              fontSize: 12),
        ),
        const SizedBox(height: 14),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _stat('${_posts.length}', 'momentos'),
            _stat('${_counts.followers}', 'seguidores'),
            _stat('${_counts.following}', 'siguiendo'),
          ],
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: _busy ? null : _onFollowButton,
                style: OutlinedButton.styleFrom(
                  backgroundColor:
                      btn.filled ? btn.color : Colors.transparent,
                  side: BorderSide(
                      color: btn.filled ? btn.color : Colors.white24),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
                child: Text(
                  btn.label,
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontWeight: FontWeight.w700,
                    color: btn.filled ? Colors.black : Colors.white,
                  ),
                ),
              ),
            ),
            if (!_isMe && _mutual) ...[
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _openDm,
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Color(0xFF69FF47)),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                  icon: const Icon(Icons.chat_bubble_outline_rounded,
                      size: 16, color: Color(0xFF69FF47)),
                  label: const Text('Mensaje',
                      style: TextStyle(
                          fontFamily: 'Poppins',
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF69FF47))),
                ),
              ),
            ],
          ],
        ),
        if (!_isMe && _rel.incoming == 'pending') ...[
          const SizedBox(height: 8),
          Text('Te envió una solicitud de seguimiento',
              style: TextStyle(
                  fontFamily: 'Poppins',
                  color: Colors.amber.withOpacity(0.9),
                  fontSize: 12)),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: _busy
                      ? null
                      : () async {
                          setState(() => _busy = true);
                          await _social.acceptRequest(widget.userId);
                          _rel = await _social.relationWith(widget.userId);
                          _counts = await _social.counts(widget.userId);
                          if (mounted) setState(() => _busy = false);
                        },
                  style: OutlinedButton.styleFrom(
                    backgroundColor: Colors.amber,
                    side: const BorderSide(color: Colors.amber),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                  ),
                  child: const Text('Aceptar',
                      style: TextStyle(
                          fontFamily: 'Poppins',
                          color: Colors.black,
                          fontWeight: FontWeight.w700)),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton(
                  onPressed: _busy
                      ? null
                      : () async {
                          setState(() => _busy = true);
                          await _social.removeFollower(widget.userId);
                          _rel = await _social.relationWith(widget.userId);
                          if (mounted) setState(() => _busy = false);
                        },
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Colors.white24),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                  ),
                  child: const Text('Rechazar',
                      style: TextStyle(
                          fontFamily: 'Poppins', color: Colors.white70)),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }

  Widget _stat(String value, String label) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        children: [
          Text(value,
              style: const TextStyle(
                  fontFamily: 'Poppins',
                  color: Colors.white,
                  fontSize: 17,
                  fontWeight: FontWeight.w700)),
          Text(label,
              style: TextStyle(
                  fontFamily: 'Poppins',
                  color: Colors.white.withOpacity(0.5),
                  fontSize: 11)),
        ],
      ),
    );
  }
}

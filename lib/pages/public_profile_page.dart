import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../core/glass.dart';
import '../services/social_service.dart';
import '../widgets/rider_activity.dart';
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
  RiderActivity? _activity;

  String get _me => Supabase.instance.client.auth.currentUser?.id ?? '';
  bool get _isMe => _me == widget.userId;
  bool get _mutual => _rel.outgoing == 'accepted' && _rel.incoming == 'accepted';

  /// Cualquier ciclista con sesión puede reaccionar y comentar.
  bool get _canInteract => _me.isNotEmpty;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    RiderActivity.load(widget.userId).then((a) {
      if (mounted) setState(() => _activity = a);
    });
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


  static const _accent = Color(0xFF69FF47);
  static const _heroMid = Color(0xFF1E5C41);

  @override
  Widget build(BuildContext context) {
    final name = _displayName();
    return Scaffold(
      backgroundColor: kBgDark,
      body: Container(
        decoration: kPageGradient,
        child: SafeArea(
          bottom: false,
          child: Column(
            children: [
              _topBar(name),
              Expanded(
                child: _loading
                    ? const Center(
                        child: CircularProgressIndicator(
                            color: _accent, strokeWidth: 2))
                    : RefreshIndicator(
                        onRefresh: _load,
                        color: _accent,
                        backgroundColor: const Color(0xFF12121C),
                        child: ListView(
                          physics: const AlwaysScrollableScrollPhysics(),
                          padding: const EdgeInsets.fromLTRB(16, 14, 16, 32),
                          children: [
                            _hero(name),
                            const SizedBox(height: 12),
                            _actions(),
                            if (!_isMe && _rel.incoming == 'pending') ...[
                              const SizedBox(height: 12),
                              _requestCard(name),
                            ],
                            const SizedBox(height: 22),
                            activitySectionLabel('ACTIVIDAD', _accent),
                            const SizedBox(height: 10),
                            RiderActivityCard(data: _activity, accent: _accent),
                            const SizedBox(height: 12),
                            RiderBadgesRow(data: _activity),
                            const SizedBox(height: 26),
                            activitySectionLabel(
                              'MOMENTOS',
                              _accent,
                              trailing: '${_posts.length}',
                            ),
                            const SizedBox(height: 10),
                            _momentsGrid(name),
                          ],
                        ),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  BoxDecoration _pillBox() => BoxDecoration(
        color: Colors.white.withOpacity(0.08),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withOpacity(0.14)),
      );

  Widget _topBar(String name) {
    final username = (_profile?['username'] as String?)?.trim() ?? '';
    return Padding(
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
                  const Icon(Icons.person_rounded, color: _accent, size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      username.isNotEmpty ? '@$username' : name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontFamily: 'Poppins',
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
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

  Widget _heroChip(IconData icon, String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.2),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: Colors.white70, size: 12),
          const SizedBox(width: 4),
          Text(
            text,
            style: const TextStyle(
              fontFamily: 'Poppins',
              color: Colors.white,
              fontSize: 11,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _hero(String name) {
    final avatar = (_profile?['avatar_url'] as String?) ?? '';
    final username = (_profile?['username'] as String?)?.trim() ?? '';
    final commune = (_profile?['commune'] as String?)?.trim() ?? '';
    final isPlus = _profile?['is_plus'] == true;
    final variant = (_profile?['plus_badge_variant'] as num?)?.toInt() ?? 0;
    final since = _activity?.memberSince;
    final ringColor = isPlus ? Colors.amber : _accent;

    Widget stat(String value, String label) => Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Column(
              children: [
                Text(value,
                    style: const TextStyle(
                        fontFamily: 'Poppins',
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        height: 1.1)),
                const SizedBox(height: 2),
                Text(label,
                    style: TextStyle(
                        fontFamily: 'Poppins',
                        color: Colors.white.withOpacity(0.6),
                        fontSize: 11)),
              ],
            ),
          ),
        );
    Widget divider() => Container(
        width: 1, height: 28, color: Colors.white.withOpacity(0.12));

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(26),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF2F8F63), _heroMid, Color(0xFF153F2E)],
          stops: [0.0, 0.55, 1.0],
        ),
        border: Border.all(color: const Color(0xFF7CF0BC).withOpacity(0.22)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF2F8F63).withOpacity(0.28),
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(26),
        child: Stack(
          children: [
            Positioned(
              right: -40,
              top: -40,
              child: Container(
                width: 150,
                height: 150,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                      color: Colors.white.withOpacity(0.07), width: 16),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 20, 18, 14),
              child: Column(
                children: [
                  Row(
                    children: [
                      Stack(
                        clipBehavior: Clip.none,
                        children: [
                          Container(
                            width: 84,
                            height: 84,
                            padding: const EdgeInsets.all(3),
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: ringColor,
                              boxShadow: [
                                BoxShadow(
                                    color: ringColor.withOpacity(0.4),
                                    blurRadius: 16),
                              ],
                            ),
                            child: CircleAvatar(
                              backgroundColor: const Color(0xFF153F2E),
                              backgroundImage: avatar.isNotEmpty
                                  ? CachedNetworkImageProvider(avatar)
                                  : null,
                              child: avatar.isEmpty
                                  ? Text(name.substring(0, 1).toUpperCase(),
                                      style: const TextStyle(
                                          fontFamily: 'Poppins',
                                          color: Color(0xFF7CF0BC),
                                          fontSize: 28,
                                          fontWeight: FontWeight.bold))
                                  : null,
                            ),
                          ),
                          if (isPlus)
                            Positioned(
                              top: -4,
                              left: -4,
                              child: PlusMedal(
                                  size: 26,
                                  variant: variant,
                                  ringColor: _heroMid),
                            ),
                        ],
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              name,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontFamily: 'Poppins',
                                color: Colors.white,
                                fontSize: 20,
                                fontWeight: FontWeight.w700,
                                height: 1.2,
                              ),
                            ),
                            if (username.isNotEmpty)
                              Text(
                                '@$username',
                                style: TextStyle(
                                  fontFamily: 'Poppins',
                                  color: Colors.white.withOpacity(0.7),
                                  fontSize: 13,
                                ),
                              ),
                            const SizedBox(height: 8),
                            Wrap(
                              spacing: 6,
                              runSpacing: 6,
                              children: [
                                if (isPlus)
                                  _heroChip(Icons.workspace_premium_rounded,
                                      'Plus'),
                                if (commune.isNotEmpty)
                                  _heroChip(
                                      Icons.location_on_rounded, commune),
                                if (since != null)
                                  _heroChip(Icons.calendar_month_rounded,
                                      'Desde ${memberSinceLabel(since)}'),
                                if (!_isMe && _mutual)
                                  _heroChip(Icons.sync_alt_rounded,
                                      'Se siguen'),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.18),
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: Row(
                      children: [
                        stat('${_posts.length}', 'Momentos'),
                        divider(),
                        stat('${_counts.followers}', 'Seguidores'),
                        divider(),
                        stat('${_counts.following}', 'Siguiendo'),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _pillButton({
    required String label,
    required IconData icon,
    required VoidCallback? onTap,
    required bool filled,
    Color color = _accent,
  }) {
    return SizedBox(
      height: 46,
      child: Material(
        color: filled ? color : Colors.white.withOpacity(0.06),
        borderRadius: BorderRadius.circular(23),
        child: InkWell(
          borderRadius: BorderRadius.circular(23),
          onTap: onTap,
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(23),
              border: Border.all(
                color: filled ? color : Colors.white.withOpacity(0.14),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (_busy && onTap == null)
                  SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: filled ? Colors.black : Colors.white),
                  )
                else
                  Icon(icon,
                      size: 18, color: filled ? Colors.black : Colors.white),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                      color: filled ? Colors.black : Colors.white,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _actions() {
    final btn = _followBtn;
    final icon = _isMe
        ? Icons.edit_rounded
        : switch (_rel.outgoing) {
            'accepted' => Icons.check_rounded,
            'pending' => Icons.hourglass_top_rounded,
            _ => Icons.person_add_alt_1_rounded,
          };
    return Row(
      children: [
        Expanded(
          child: _pillButton(
            label: btn.label,
            icon: icon,
            filled: btn.filled,
            onTap: _busy ? null : _onFollowButton,
          ),
        ),
        if (!_isMe && _mutual) ...[
          const SizedBox(width: 10),
          Expanded(
            child: _pillButton(
              label: 'Mensaje',
              icon: Icons.forum_rounded,
              filled: false,
              onTap: _openDm,
            ),
          ),
        ],
      ],
    );
  }

  Widget _requestCard(String name) {
    Future<void> act(Future<void> Function() f, {bool counts = false}) async {
      setState(() => _busy = true);
      await f();
      _rel = await _social.relationWith(widget.userId);
      if (counts) _counts = await _social.counts(widget.userId);
      if (mounted) setState(() => _busy = false);
    }

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: Colors.amber.withOpacity(0.08),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.amber.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(Icons.group_add_rounded,
                  color: Colors.amber, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '$name quiere seguirte',
                  style: const TextStyle(
                    fontFamily: 'Poppins',
                    color: Colors.white,
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _pillButton(
                  label: 'Aceptar',
                  icon: Icons.check_rounded,
                  filled: true,
                  color: Colors.amber,
                  onTap: _busy
                      ? null
                      : () => act(() => _social.acceptRequest(widget.userId),
                          counts: true),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _pillButton(
                  label: 'Rechazar',
                  icon: Icons.close_rounded,
                  filled: false,
                  onTap: _busy
                      ? null
                      : () => act(() => _social.removeFollower(widget.userId)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _momentsGrid(String name) {
    if (_posts.isEmpty) {
      return Container(
        padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 20),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.03),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.white.withOpacity(0.07)),
        ),
        child: Column(
          children: [
            Icon(Icons.photo_camera_back_rounded,
                color: Colors.white.withOpacity(0.3), size: 32),
            const SizedBox(height: 8),
            Text(
              _isMe
                  ? 'Aún no publicas momentos'
                  : '$name aún no publica momentos',
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontFamily: 'Poppins',
                  color: Colors.white.withOpacity(0.45),
                  fontSize: 13),
            ),
          ],
        ),
      );
    }
    return GridView.count(
      crossAxisCount: 3,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 4,
      crossAxisSpacing: 4,
      children: [
        for (final p in _posts)
          GestureDetector(
            onTap: () => _openPost(p),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: CachedNetworkImage(
                imageUrl: p['image_url'] as String,
                fit: BoxFit.cover,
                placeholder: (_, _) => Container(color: Colors.white10),
                errorWidget: (_, _, _) => Container(color: Colors.white10),
              ),
            ),
          ),
      ],
    );
  }

  String _displayName() {
    final u = (_profile?['username'] as String?)?.trim();
    final f = (_profile?['full_name'] as String?)?.trim();
    if (f != null && f.isNotEmpty) return f;
    if (u != null && u.isNotEmpty) return u;
    return 'Ciclista';
  }
}

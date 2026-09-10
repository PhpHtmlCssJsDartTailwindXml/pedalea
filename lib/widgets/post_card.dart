import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import '../services/social_service.dart';
import 'plus_medal.dart';

String _timeAgo(String? iso) {
  final t = DateTime.tryParse(iso ?? '');
  if (t == null) return '';
  final d = DateTime.now().difference(t.toLocal());
  if (d.inMinutes < 1) return 'ahora';
  if (d.inMinutes < 60) return 'hace ${d.inMinutes} min';
  if (d.inHours < 24) return 'hace ${d.inHours} h';
  if (d.inDays < 7) return 'hace ${d.inDays} d';
  final local = t.toLocal();
  const meses = [
    'ene', 'feb', 'mar', 'abr', 'may', 'jun',
    'jul', 'ago', 'sep', 'oct', 'nov', 'dic'
  ];
  return '${local.day} ${meses[local.month - 1]}';
}

/// Tarjeta de un "momento" (foto + texto) en el feed y en el perfil.
class PostCard extends StatefulWidget {
  final Map<String, dynamic> post;

  /// true si el usuario actual y el autor se siguen mutuamente (puede
  /// reaccionar y comentar).
  final bool canInteract;

  /// true si el momento es del propio usuario (permite borrarlo).
  final bool isMine;

  final VoidCallback onAuthorTap;
  final VoidCallback onOpenComments;

  /// Se llama cuando intenta reaccionar/comentar sin follow mutuo.
  final VoidCallback onBlockedInteract;
  final VoidCallback? onDeleted;

  const PostCard({
    super.key,
    required this.post,
    required this.canInteract,
    required this.isMine,
    required this.onAuthorTap,
    required this.onOpenComments,
    required this.onBlockedInteract,
    this.onDeleted,
  });

  @override
  State<PostCard> createState() => _PostCardState();
}

class _PostCardState extends State<PostCard>
    with SingleTickerProviderStateMixin {
  late bool _liked;
  late int _likeCount;
  bool _busy = false;

  late final AnimationController _burst = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 700),
  );

  @override
  void initState() {
    super.initState();
    _liked = widget.post['liked_by_me'] == true;
    _likeCount = (widget.post['like_count'] as num?)?.toInt() ?? 0;
  }

  @override
  void dispose() {
    _burst.dispose();
    super.dispose();
  }

  Map<String, dynamic> get _author =>
      (widget.post['author'] as Map?)?.cast<String, dynamic>() ?? const {};

  String get _authorName {
    final u = (_author['username'] as String?)?.trim();
    final f = (_author['full_name'] as String?)?.trim();
    if (f != null && f.isNotEmpty) return f;
    if (u != null && u.isNotEmpty) return u;
    return 'Ciclista';
  }

  Future<void> _toggleLike({bool fromDoubleTap = false}) async {
    if (!widget.canInteract) {
      if (!fromDoubleTap) widget.onBlockedInteract();
      return;
    }
    if (fromDoubleTap && _liked) {
      _burst.forward(from: 0);
      return;
    }
    if (_busy) return;
    final was = _liked;
    setState(() {
      _busy = true;
      _liked = !was;
      _likeCount += was ? -1 : 1;
    });
    if (!was) _burst.forward(from: 0);
    try {
      await SocialService.instance.toggleLike(
        postId: widget.post['id'] as String,
        authorId: _author['id'] as String? ?? widget.post['user_id'] as String,
        currentlyLiked: was,
      );
    } catch (_) {
      if (mounted) {
        setState(() {
          _liked = was;
          _likeCount += was ? 1 : -1;
        });
        widget.onBlockedInteract();
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _confirmDelete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF161622),
        title: const Text('Borrar momento',
            style: TextStyle(fontFamily: 'Poppins', color: Colors.white)),
        content: const Text('Se eliminará para siempre.',
            style: TextStyle(fontFamily: 'Poppins', color: Colors.white70)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar',
                style: TextStyle(fontFamily: 'Poppins', color: Colors.white54)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Borrar',
                style:
                    TextStyle(fontFamily: 'Poppins', color: Colors.redAccent)),
          ),
        ],
      ),
    );
    if (ok == true) {
      await SocialService.instance.deletePost(widget.post['id'] as String);
      widget.onDeleted?.call();
    }
  }

  @override
  Widget build(BuildContext context) {
    final caption = (widget.post['caption'] as String?)?.trim() ?? '';
    final comments = (widget.post['comment_count'] as num?)?.toInt() ?? 0;
    final isPlus = _author['is_plus'] == true;
    final avatarUrl = (_author['avatar_url'] as String?) ?? '';
    final commune = (_author['commune'] as String?)?.trim() ?? '';
    final when = _timeAgo(widget.post['created_at'] as String?);
    final subtitle = [
      if (commune.isNotEmpty) commune,
      if (when.isNotEmpty) when,
    ].join('  ·  ');

    return Container(
      margin: const EdgeInsets.only(bottom: 22),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.035),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withOpacity(0.07)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Cabecera
          InkWell(
            onTap: widget.onAuthorTap,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 13, 6, 13),
              child: Row(
                children: [
                  Stack(
                    clipBehavior: Clip.none,
                    children: [
                      CircleAvatar(
                        radius: 19,
                        backgroundColor: Colors.white12,
                        backgroundImage: avatarUrl.isNotEmpty
                            ? CachedNetworkImageProvider(avatarUrl)
                            : null,
                        child: avatarUrl.isEmpty
                            ? Text(
                                _authorName.substring(0, 1).toUpperCase(),
                                style: const TextStyle(
                                    fontFamily: 'Poppins', color: Colors.white),
                              )
                            : null,
                      ),
                      if (isPlus)
                        Positioned(
                          bottom: -3,
                          right: -3,
                          child: PlusMedal(
                            size: 14,
                            variant: (_author['plus_badge_variant'] as num?)
                                    ?.toInt() ??
                                0,
                            ringColor: const Color(0xFF12121C),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(width: 11),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _authorName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontFamily: 'Poppins',
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                          ),
                        ),
                        if (subtitle.isNotEmpty)
                          Text(
                            subtitle,
                            style: TextStyle(
                              fontFamily: 'Poppins',
                              color: Colors.white.withOpacity(0.4),
                              fontSize: 11,
                            ),
                          ),
                      ],
                    ),
                  ),
                  if (widget.isMine)
                    IconButton(
                      icon: const Icon(Icons.more_horiz, color: Colors.white54),
                      onPressed: _confirmDelete,
                    ),
                ],
              ),
            ),
          ),
          // Imagen con burst de corazón al doble tap
          GestureDetector(
            onDoubleTap: () => _toggleLike(fromDoubleTap: true),
            child: Stack(
              alignment: Alignment.center,
              children: [
                CachedNetworkImage(
                  imageUrl: widget.post['image_url'] as String,
                  width: double.infinity,
                  fit: BoxFit.cover,
                  placeholder: (_, _) => Container(
                    height: 280,
                    color: Colors.white10,
                    child: const Center(
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white24),
                    ),
                  ),
                  errorWidget: (_, _, _) => Container(
                    height: 200,
                    color: Colors.white10,
                    child: const Icon(Icons.broken_image_outlined,
                        color: Colors.white24),
                  ),
                ),
                AnimatedBuilder(
                  animation: _burst,
                  builder: (_, _) {
                    final v = _burst.value;
                    if (v == 0) return const SizedBox.shrink();
                    final scale = v < 0.4 ? v / 0.4 * 1.15 : 1.15 - (v - 0.4) * 0.2;
                    final opacity = v < 0.7 ? 1.0 : (1 - (v - 0.7) / 0.3);
                    return Opacity(
                      opacity: opacity.clamp(0.0, 1.0),
                      child: Transform.scale(
                        scale: scale,
                        child: const Icon(Icons.favorite,
                            color: Colors.white, size: 88),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
          // Acciones
          Padding(
            padding: const EdgeInsets.fromLTRB(6, 4, 12, 2),
            child: Row(
              children: [
                IconButton(
                  icon: Icon(
                    _liked ? Icons.favorite : Icons.favorite_border,
                    color: _liked ? const Color(0xFFFF4D6D) : Colors.white70,
                  ),
                  onPressed: () => _toggleLike(),
                ),
                if (_likeCount > 0)
                  Text('$_likeCount',
                      style: const TextStyle(
                          fontFamily: 'Poppins',
                          color: Colors.white70,
                          fontWeight: FontWeight.w600)),
                const SizedBox(width: 6),
                IconButton(
                  icon: const Icon(Icons.mode_comment_outlined,
                      color: Colors.white70),
                  onPressed: widget.canInteract
                      ? widget.onOpenComments
                      : widget.onBlockedInteract,
                ),
                if (comments > 0)
                  Text('$comments',
                      style: const TextStyle(
                          fontFamily: 'Poppins',
                          color: Colors.white70,
                          fontWeight: FontWeight.w600)),
                const Spacer(),
                if (!widget.canInteract && !widget.isMine)
                  Row(
                    children: [
                      const Icon(Icons.lock_outline,
                          size: 13, color: Colors.white30),
                      const SizedBox(width: 4),
                      Text('síguela para reaccionar',
                          style: TextStyle(
                              fontFamily: 'Poppins',
                              color: Colors.white.withOpacity(0.3),
                              fontSize: 10.5)),
                    ],
                  ),
              ],
            ),
          ),
          if (caption.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 2, 16, 12),
              child: Text(
                caption,
                style: const TextStyle(
                  fontFamily: 'Poppins',
                  color: Colors.white,
                  fontSize: 14,
                  height: 1.4,
                ),
              ),
            ),
          if (comments > 0)
            Padding(
              padding: EdgeInsets.fromLTRB(16, caption.isEmpty ? 2 : 0, 16, 14),
              child: GestureDetector(
                onTap: widget.canInteract
                    ? widget.onOpenComments
                    : widget.onBlockedInteract,
                child: Text(
                  comments == 1
                      ? 'Ver el comentario'
                      : 'Ver los $comments comentarios',
                  style: TextStyle(
                      fontFamily: 'Poppins',
                      color: Colors.white.withOpacity(0.45),
                      fontSize: 12),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

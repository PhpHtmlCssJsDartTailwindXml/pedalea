import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/social_service.dart';

/// Hoja inferior con los comentarios de un momento y sus respuestas.
/// Comentar/responder solo si hay follow mutuo (o es tu propio momento).
Future<void> showCommentsSheet(
  BuildContext context, {
  required Map<String, dynamic> post,
  required bool canInteract,
  VoidCallback? onChanged,
}) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: const Color(0xFF12121C),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => _CommentsSheet(
      post: post,
      canInteract: canInteract,
      onChanged: onChanged,
    ),
  );
}

String _nameOf(Map? profile) {
  final p = profile?.cast<String, dynamic>() ?? const {};
  final u = (p['username'] as String?)?.trim();
  final f = (p['full_name'] as String?)?.trim();
  if (u != null && u.isNotEmpty) return u;
  if (f != null && f.isNotEmpty) return f;
  return 'Ciclista';
}

class _CommentsSheet extends StatefulWidget {
  final Map<String, dynamic> post;
  final bool canInteract;
  final VoidCallback? onChanged;

  const _CommentsSheet({
    required this.post,
    required this.canInteract,
    this.onChanged,
  });

  @override
  State<_CommentsSheet> createState() => _CommentsSheetState();
}

class _CommentsSheetState extends State<_CommentsSheet> {
  final _ctrl = TextEditingController();
  final _scroll = ScrollController();
  final _focus = FocusNode();

  List<Map<String, dynamic>> _top = [];
  final Map<String, List<Map<String, dynamic>>> _replies = {};
  bool _loading = true;
  bool _sending = false;

  ({String id, String name})? _replyTo;

  String get _postId => widget.post['id'] as String;
  String get _authorId =>
      (widget.post['author'] as Map?)?['id'] as String? ??
      widget.post['user_id'] as String;
  String? get _myId => Supabase.instance.client.auth.currentUser?.id;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _scroll.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final all = await SocialService.instance.comments(_postId);
    if (!mounted) return;
    final top = <Map<String, dynamic>>[];
    final replies = <String, List<Map<String, dynamic>>>{};
    for (final c in all) {
      final parent = c['parent_id'] as String?;
      if (parent == null) {
        top.add(c);
      } else {
        (replies[parent] ??= []).add(c);
      }
    }
    setState(() {
      _top = top;
      _replies
        ..clear()
        ..addAll(replies);
      _loading = false;
    });
  }

  int get _count =>
      _top.length + _replies.values.fold(0, (s, l) => s + l.length);

  Future<void> _send() async {
    final text = _ctrl.text.trim();
    if (text.isEmpty || _sending) return;
    setState(() => _sending = true);
    try {
      final row = await SocialService.instance.addComment(
        postId: _postId,
        authorId: _authorId,
        body: text,
        parentId: _replyTo?.id,
      );
      if (row != null && mounted) {
        _ctrl.clear();
        setState(() => _replyTo = null);
        await _load();
        widget.onChanged?.call();
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('No se pudo comentar',
              style: TextStyle(fontFamily: 'Poppins')),
          backgroundColor: Colors.redAccent,
        ));
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _delete(String id) async {
    await SocialService.instance.deleteComment(id);
    await _load();
    widget.onChanged?.call();
  }

  void _startReply(String parentId, String name) {
    setState(() => _replyTo = (id: parentId, name: name));
    _focus.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.72,
        minChildSize: 0.4,
        maxChildSize: 0.95,
        builder: (context, sc) => Column(
          children: [
            const SizedBox(height: 10),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(
                _count == 0 ? 'Comentarios' : 'Comentarios · $_count',
                style: const TextStyle(
                    fontFamily: 'Poppins',
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 15),
              ),
            ),
            const Divider(color: Colors.white12, height: 1),
            Expanded(
              child: _loading
                  ? const Center(
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white30))
                  : _top.isEmpty
                      ? Center(
                          child: Text('Sé el primero en comentar',
                              style: TextStyle(
                                  fontFamily: 'Poppins',
                                  color: Colors.white.withOpacity(0.4))),
                        )
                      : ListView.builder(
                          controller: _scroll,
                          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                          itemCount: _top.length,
                          itemBuilder: (_, i) {
                            final c = _top[i];
                            final rs = _replies[c['id']] ?? const [];
                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                _tile(c, isReply: false),
                                for (final r in rs)
                                  _tile(r, isReply: true),
                              ],
                            );
                          },
                        ),
            ),
            _composer(),
          ],
        ),
      ),
    );
  }

  Widget _tile(Map<String, dynamic> c, {required bool isReply}) {
    final author = (c['author'] as Map?)?.cast<String, dynamic>() ?? const {};
    final name = _nameOf(author);
    final avatar = (author['avatar_url'] as String?) ?? '';
    final mine = c['user_id'] == _myId;
    final canDelete = mine || _authorId == _myId;
    final replyToName =
        c['reply_to'] != null ? _nameOf(c['reply_to'] as Map?) : null;
    final r = isReply ? 12.0 : 15.0;

    return Padding(
      padding: EdgeInsets.only(bottom: 12, left: isReply ? 34 : 0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: r,
            backgroundColor: Colors.white12,
            backgroundImage:
                avatar.isNotEmpty ? CachedNetworkImageProvider(avatar) : null,
            child: avatar.isEmpty
                ? Text(name.substring(0, 1).toUpperCase(),
                    style: TextStyle(
                        fontFamily: 'Poppins',
                        color: Colors.white,
                        fontSize: isReply ? 10 : 12))
                : null,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name,
                    style: TextStyle(
                        fontFamily: 'Poppins',
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                        fontSize: isReply ? 11.5 : 12.5)),
                const SizedBox(height: 2),
                Text.rich(
                  TextSpan(children: [
                    if (replyToName != null)
                      TextSpan(
                        text: '@$replyToName ',
                        style: const TextStyle(
                            fontFamily: 'Poppins',
                            color: Color(0xFF69FF47),
                            fontSize: 13),
                      ),
                    TextSpan(
                      text: c['body'] as String? ?? '',
                      style: TextStyle(
                          fontFamily: 'Poppins',
                          color: Colors.white70,
                          fontSize: isReply ? 12.5 : 13),
                    ),
                  ]),
                ),
                if (widget.canInteract)
                  Padding(
                    padding: const EdgeInsets.only(top: 3),
                    child: GestureDetector(
                      onTap: () => _startReply(
                        (c['parent_id'] as String?) ?? c['id'] as String,
                        name,
                      ),
                      child: Text('Responder',
                          style: TextStyle(
                              fontFamily: 'Poppins',
                              color: Colors.white.withOpacity(0.4),
                              fontSize: 11,
                              fontWeight: FontWeight.w600)),
                    ),
                  ),
              ],
            ),
          ),
          if (canDelete)
            GestureDetector(
              onTap: () => _delete(c['id'] as String),
              child: const Padding(
                padding: EdgeInsets.only(left: 8, top: 2),
                child: Icon(Icons.close, size: 15, color: Colors.white30),
              ),
            ),
        ],
      ),
    );
  }

  Widget _composer() {
    if (!widget.canInteract) {
      return Container(
        width: double.infinity,
        padding: EdgeInsets.fromLTRB(
            16, 12, 16, 12 + MediaQuery.of(context).padding.bottom),
        color: Colors.white.withOpacity(0.03),
        child: Text(
          'Solo puedes comentar si tú y esta persona se siguen mutuamente.',
          textAlign: TextAlign.center,
          style: TextStyle(
              fontFamily: 'Poppins',
              color: Colors.white.withOpacity(0.5),
              fontSize: 12),
        ),
      );
    }
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.04),
        border: Border(top: BorderSide(color: Colors.white.withOpacity(0.08))),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_replyTo != null)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(16, 8, 12, 4),
              child: Row(
                children: [
                  Expanded(
                    child: Text('Respondiendo a @${_replyTo!.name}',
                        style: TextStyle(
                            fontFamily: 'Poppins',
                            color: Colors.white.withOpacity(0.5),
                            fontSize: 11.5)),
                  ),
                  GestureDetector(
                    onTap: () => setState(() => _replyTo = null),
                    child: const Icon(Icons.close,
                        size: 15, color: Colors.white38),
                  ),
                ],
              ),
            ),
          Padding(
            padding: EdgeInsets.fromLTRB(
                12, 6, 8, 8 + MediaQuery.of(context).padding.bottom),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _ctrl,
                    focusNode: _focus,
                    minLines: 1,
                    maxLines: 4,
                    textCapitalization: TextCapitalization.sentences,
                    style: const TextStyle(
                        fontFamily: 'Poppins',
                        color: Colors.white,
                        fontSize: 14),
                    decoration: InputDecoration(
                      hintText: _replyTo != null
                          ? 'Responde a @${_replyTo!.name}…'
                          : 'Escribe un comentario…',
                      hintStyle: TextStyle(
                          fontFamily: 'Poppins',
                          color: Colors.white.withOpacity(0.4)),
                      filled: true,
                      fillColor: Colors.white.withOpacity(0.05),
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 10),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(22),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                ),
                IconButton(
                  onPressed: _sending ? null : _send,
                  icon: _sending
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white54))
                      : const Icon(Icons.send_rounded,
                          color: Color(0xFF69FF47)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

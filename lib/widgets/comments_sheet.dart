import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/social_service.dart';

/// Hoja inferior con los comentarios de un momento. Comentar solo si hay
/// follow mutuo ([canInteract]).
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
  List<Map<String, dynamic>> _comments = [];
  bool _loading = true;
  bool _sending = false;

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
    super.dispose();
  }

  Future<void> _load() async {
    final c = await SocialService.instance.comments(_postId);
    if (!mounted) return;
    setState(() {
      _comments = c;
      _loading = false;
    });
  }

  Future<void> _send() async {
    final text = _ctrl.text.trim();
    if (text.isEmpty || _sending) return;
    setState(() => _sending = true);
    try {
      final row = await SocialService.instance.addComment(
        postId: _postId,
        authorId: _authorId,
        body: text,
      );
      if (row != null && mounted) {
        _ctrl.clear();
        await _load();
        widget.onChanged?.call();
        _scroll.animateTo(_scroll.position.maxScrollExtent + 80,
            duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
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

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.7,
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
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Text('Comentarios',
                  style: TextStyle(
                      fontFamily: 'Poppins',
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 15)),
            ),
            const Divider(color: Colors.white12, height: 1),
            Expanded(
              child: _loading
                  ? const Center(
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white30))
                  : _comments.isEmpty
                      ? Center(
                          child: Text('Sé el primero en comentar',
                              style: TextStyle(
                                  fontFamily: 'Poppins',
                                  color: Colors.white.withOpacity(0.4))),
                        )
                      : ListView.builder(
                          controller: _scroll,
                          padding: const EdgeInsets.all(16),
                          itemCount: _comments.length,
                          itemBuilder: (_, i) => _tile(_comments[i]),
                        ),
            ),
            _composer(),
          ],
        ),
      ),
    );
  }

  Widget _tile(Map<String, dynamic> c) {
    final author = (c['author'] as Map?)?.cast<String, dynamic>() ?? const {};
    final u = (author['username'] as String?)?.trim();
    final f = (author['full_name'] as String?)?.trim();
    final name = (u != null && u.isNotEmpty)
        ? u
        : (f != null && f.isNotEmpty ? f : 'Ciclista');
    final avatar = (author['avatar_url'] as String?) ?? '';
    final mine = c['user_id'] == _myId;
    final canDelete = mine || _authorId == _myId;
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 15,
            backgroundColor: Colors.white12,
            backgroundImage:
                avatar.isNotEmpty ? CachedNetworkImageProvider(avatar) : null,
            child: avatar.isEmpty
                ? Text(name.substring(0, 1).toUpperCase(),
                    style: const TextStyle(
                        fontFamily: 'Poppins',
                        color: Colors.white,
                        fontSize: 12))
                : null,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name,
                    style: const TextStyle(
                        fontFamily: 'Poppins',
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                        fontSize: 12.5)),
                const SizedBox(height: 2),
                Text(c['body'] as String? ?? '',
                    style: const TextStyle(
                        fontFamily: 'Poppins',
                        color: Colors.white70,
                        fontSize: 13)),
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
      padding: EdgeInsets.fromLTRB(
          12, 8, 8, 8 + MediaQuery.of(context).padding.bottom),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.04),
        border: Border(top: BorderSide(color: Colors.white.withOpacity(0.08))),
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _ctrl,
              minLines: 1,
              maxLines: 4,
              style: const TextStyle(
                  fontFamily: 'Poppins', color: Colors.white, fontSize: 14),
              decoration: InputDecoration(
                hintText: 'Escribe un comentario…',
                hintStyle: TextStyle(
                    fontFamily: 'Poppins', color: Colors.white.withOpacity(0.4)),
                filled: true,
                fillColor: Colors.white.withOpacity(0.05),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
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
                : const Icon(Icons.send_rounded, color: Color(0xFF69FF47)),
          ),
        ],
      ),
    );
  }
}

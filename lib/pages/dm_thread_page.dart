import 'dart:async';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../core/glass.dart';
import '../services/dm_service.dart';
import '../services/chat_notifications_service.dart';
import '../widgets/plus_medal.dart';
import 'public_profile_page.dart';

/// Conversación 1 a 1.
class DmThreadPage extends StatefulWidget {
  final String otherUserId;
  final String otherName;
  final String? otherAvatar;
  final bool otherIsPlus;
  final int otherBadgeVariant;

  const DmThreadPage({
    super.key,
    required this.otherUserId,
    required this.otherName,
    this.otherAvatar,
    this.otherIsPlus = false,
    this.otherBadgeVariant = 0,
  });

  @override
  State<DmThreadPage> createState() => _DmThreadPageState();
}

class _DmThreadPageState extends State<DmThreadPage> {
  final _dm = DmService.instance;
  final _sb = Supabase.instance.client;
  final _ctrl = TextEditingController();
  final _scroll = ScrollController();

  final List<Map<String, dynamic>> _messages = [];
  String? _threadId;
  bool _loading = true;
  bool _sending = false;
  RealtimeChannel? _channel;

  String get _me => _sb.auth.currentUser?.id ?? '';

  @override
  void initState() {
    super.initState();
    ChatNotificationsService.activeDmUserId = widget.otherUserId;
    _boot();
  }

  @override
  void dispose() {
    if (ChatNotificationsService.activeDmUserId == widget.otherUserId) {
      ChatNotificationsService.activeDmUserId = null;
    }
    _channel?.unsubscribe();
    _ctrl.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _boot() async {
    _threadId = await _dm.threadIdWith(widget.otherUserId);
    if (_threadId != null) {
      final msgs = await _dm.messages(_threadId!);
      if (!mounted) return;
      setState(() {
        _messages
          ..clear()
          ..addAll(msgs);
      });
      _dm.markRead(_threadId!);
    }
    if (mounted) setState(() => _loading = false);
    _scrollToBottom();
    _subscribe();
  }

  void _subscribe() {
    _channel = _sb.channel('dm-${widget.otherUserId}-$_me');
    _channel!
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'dm_messages',
          filter: PostgresChangeFilter(
            column: 'recipient_id',
            value: _me,
            type: PostgresChangeFilterType.eq,
          ),
          callback: (payload) {
            final row = payload.newRecord;
            if (row['sender_id'] != widget.otherUserId) return;
            if (_messages.any((m) => m['id'] == row['id'])) return;
            setState(() => _messages.add(Map<String, dynamic>.from(row)));
            _scrollToBottom();
            _threadId ??= row['thread_id'] as String?;
            if (_threadId != null) _dm.markRead(_threadId!);
          },
        )
        .subscribe();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(_scroll.position.maxScrollExtent,
            duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
      }
    });
  }

  Future<void> _send() async {
    final text = _ctrl.text.trim();
    if (text.isEmpty || _sending) return;
    setState(() => _sending = true);
    _ctrl.clear();
    // Optimista.
    final temp = {
      'id': 'temp_${DateTime.now().microsecondsSinceEpoch}',
      'sender_id': _me,
      'recipient_id': widget.otherUserId,
      'body': text,
      'created_at': DateTime.now().toUtc().toIso8601String(),
      'read_at': null,
      '_pending': true,
    };
    setState(() => _messages.add(temp));
    _scrollToBottom();
    try {
      final tid = await _dm.send(widget.otherUserId, text);
      _threadId ??= tid;
      if (mounted) {
        setState(() {
          final i = _messages.indexWhere((m) => m['id'] == temp['id']);
          if (i != -1) _messages[i]['_pending'] = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _messages.removeWhere((m) => m['id'] == temp['id']));
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(
            e.toString().contains('not_allowed')
                ? 'Ya no pueden escribirse (dejaron de seguirse o hay un bloqueo).'
                : 'No se pudo enviar el mensaje.',
            style: const TextStyle(fontFamily: 'Poppins'),
          ),
          backgroundColor: Colors.redAccent,
        ));
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBgDark,
      appBar: AppBar(
        backgroundColor: const Color(0xFF12121C),
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        titleSpacing: 0,
        title: InkWell(
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
                builder: (_) => PublicProfilePage(userId: widget.otherUserId)),
          ),
          child: Row(
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  CircleAvatar(
                    radius: 16,
                    backgroundColor: Colors.white12,
                    backgroundImage:
                        (widget.otherAvatar != null && widget.otherAvatar!.isNotEmpty)
                            ? CachedNetworkImageProvider(widget.otherAvatar!)
                            : null,
                    child: (widget.otherAvatar == null ||
                            widget.otherAvatar!.isEmpty)
                        ? Text(widget.otherName.substring(0, 1).toUpperCase(),
                            style: const TextStyle(
                                fontFamily: 'Poppins',
                                color: Colors.white,
                                fontSize: 13))
                        : null,
                  ),
                  if (widget.otherIsPlus)
                    Positioned(
                      bottom: -3,
                      right: -3,
                      child: PlusMedal(
                          size: 13,
                          variant: widget.otherBadgeVariant,
                          ringColor: const Color(0xFF12121C)),
                    ),
                ],
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(widget.otherName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontFamily: 'Poppins',
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 15)),
              ),
            ],
          ),
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: _loading
                ? const Center(
                    child: CircularProgressIndicator(color: Colors.greenAccent))
                : _messages.isEmpty
                    ? Center(
                        child: Text(
                          'Escríbele a ${widget.otherName} para empezar',
                          style: TextStyle(
                              fontFamily: 'Poppins',
                              color: Colors.white.withOpacity(0.4)),
                        ),
                      )
                    : ListView.builder(
                        controller: _scroll,
                        padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
                        itemCount: _messages.length,
                        itemBuilder: (_, i) => _bubble(_messages[i]),
                      ),
          ),
          _composer(),
        ],
      ),
    );
  }

  Widget _bubble(Map<String, dynamic> m) {
    final mine = m['sender_id'] == _me;
    final pending = m['_pending'] == true;
    final t = DateTime.tryParse(m['created_at'] as String? ?? '')?.toLocal();
    final time = t == null
        ? ''
        : '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 6),
        constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width * 0.75),
        decoration: BoxDecoration(
          color: mine
              ? const Color(0xFF69FF47).withOpacity(pending ? 0.10 : 0.16)
              : Colors.white.withOpacity(0.06),
          borderRadius: BorderRadius.circular(16).copyWith(
            bottomRight: mine ? const Radius.circular(4) : null,
            bottomLeft: mine ? null : const Radius.circular(4),
          ),
          border: Border.all(
            color: mine
                ? const Color(0xFF69FF47).withOpacity(0.35)
                : Colors.white12,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(m['body'] as String? ?? '',
                style: const TextStyle(
                    fontFamily: 'Poppins', color: Colors.white, fontSize: 14)),
            const SizedBox(height: 2),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(time,
                    style: TextStyle(
                        fontFamily: 'Poppins',
                        color: Colors.white.withOpacity(0.35),
                        fontSize: 9)),
                if (mine) ...[
                  const SizedBox(width: 3),
                  Icon(
                    pending
                        ? Icons.access_time
                        : (m['read_at'] != null
                            ? Icons.done_all_rounded
                            : Icons.done_rounded),
                    size: 12,
                    color: m['read_at'] != null
                        ? const Color(0xFF69FF47)
                        : Colors.white.withOpacity(0.35),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _composer() {
    return Container(
      padding: EdgeInsets.fromLTRB(
          12, 8, 8, 8 + MediaQuery.of(context).padding.bottom),
      decoration: const BoxDecoration(
        color: Color(0xFF12121C),
        border: Border(top: BorderSide(color: Colors.white12)),
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _ctrl,
              minLines: 1,
              maxLines: 5,
              textCapitalization: TextCapitalization.sentences,
              style: const TextStyle(
                  fontFamily: 'Poppins', color: Colors.white, fontSize: 14),
              decoration: InputDecoration(
                hintText: 'Mensaje…',
                hintStyle: TextStyle(
                    fontFamily: 'Poppins',
                    color: Colors.white.withOpacity(0.4)),
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
            icon: const Icon(Icons.send_rounded, color: Color(0xFF69FF47)),
          ),
        ],
      ),
    );
  }
}

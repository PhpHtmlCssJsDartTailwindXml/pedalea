import 'dart:async';
import 'dart:io';
import 'package:audioplayers/audioplayers.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../core/glass.dart';
import '../core/time_format.dart';
import '../services/dm_service.dart';
import '../services/chat_notifications_service.dart';
import '../widgets/plus_medal.dart';
import 'public_profile_page.dart';

const _kAccent = Color(0xFF69FF47);
const _kBar = Color(0xFF12121C);

/// Conversación 1 a 1 estilo WhatsApp/Instagram: leídos, hace cuánto,
/// responder, copiar, eliminar para todos, fotos y mensajes de voz.
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
  final _focus = FocusNode();
  final _picker = ImagePicker();
  final _recorder = AudioRecorder();

  final List<Map<String, dynamic>> _messages = [];
  String? _threadId;
  bool _loading = true;
  bool _hasText = false;
  RealtimeChannel? _inboxChannel; // inserts para mí (antes de conocer el hilo)
  RealtimeChannel? _threadChannel; // inserts/updates del hilo
  RealtimeChannel? _roomChannel; // "escribiendo…" y "en línea"

  Map<String, dynamic>? _replyTo;

  // Estado del otro
  DateTime? _otherSeenAt;
  DateTime? _otherTypingAt;
  Timer? _ticker;
  Timer? _heartbeat;
  DateTime _lastTypingSent = DateTime.fromMillisecondsSinceEpoch(0);

  // Grabación
  bool _recording = false;
  DateTime? _recStart;
  Timer? _recTimer;
  Duration _recElapsed = Duration.zero;

  String get _me => _sb.auth.currentUser?.id ?? '';
  bool get _rich => _dm.richSupported != false;

  bool get _otherOnline =>
      _otherSeenAt != null &&
      DateTime.now().difference(_otherSeenAt!) < const Duration(seconds: 35);
  bool get _otherTyping =>
      _otherTypingAt != null &&
      DateTime.now().difference(_otherTypingAt!) < const Duration(seconds: 4);

  @override
  void initState() {
    super.initState();
    ChatNotificationsService.activeDmUserId = widget.otherUserId;
    _ctrl.addListener(_onTextChanged);
    _ticker = Timer.periodic(const Duration(seconds: 5), (_) {
      if (mounted) setState(() {}); // refresca "hace X" y en línea
    });
    _boot();
  }

  @override
  void dispose() {
    if (ChatNotificationsService.activeDmUserId == widget.otherUserId) {
      ChatNotificationsService.activeDmUserId = null;
    }
    _roomChannel?.sendBroadcastMessage(event: 'bye', payload: {'u': _me});
    _inboxChannel?.unsubscribe();
    _threadChannel?.unsubscribe();
    _roomChannel?.unsubscribe();
    _ticker?.cancel();
    _heartbeat?.cancel();
    _recTimer?.cancel();
    _recorder.dispose();
    _AudioBubbleState.stopAll();
    _ctrl.dispose();
    _scroll.dispose();
    _focus.dispose();
    super.dispose();
  }

  // ── Carga y tiempo real ───────────────────────────────────────────────────

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
      _subscribeThread();
    } else {
      _subscribeInbox();
    }
    if (mounted) setState(() => _loading = false);
    _scrollToBottom(jump: true);
  }

  /// Antes de que exista el hilo: escucha mensajes nuevos para mí.
  void _subscribeInbox() {
    _inboxChannel = _sb
        .channel('dm-${widget.otherUserId}-$_me')
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
            _onInsert(row);
            final tid = row['thread_id'] as String?;
            if (tid != null && _threadId == null) {
              _threadId = tid;
              _subscribeThread();
            }
          },
        )
        .subscribe();
  }

  void _subscribeThread() {
    final tid = _threadId;
    if (tid == null || _threadChannel != null) return;
    _inboxChannel?.unsubscribe();
    _inboxChannel = null;
    final filter = PostgresChangeFilter(
      column: 'thread_id',
      value: tid,
      type: PostgresChangeFilterType.eq,
    );
    _threadChannel = _sb
        .channel('dm-thread-$tid-$_me')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'dm_messages',
          filter: filter,
          callback: (p) => _onInsert(p.newRecord),
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'dm_messages',
          filter: filter,
          callback: (p) => _onUpdate(p.newRecord),
        )
        .subscribe();

    _roomChannel = _sb
        .channel('dm-room-$tid')
        .onBroadcast(
          event: 'typing',
          callback: (p) {
            if (p['u'] == widget.otherUserId && mounted) {
              setState(() {
                _otherTypingAt = DateTime.now();
                _otherSeenAt = DateTime.now();
              });
            }
          },
        )
        .onBroadcast(
          event: 'here',
          callback: (p) {
            if (p['u'] == widget.otherUserId && mounted) {
              final wasOnline = _otherOnline;
              setState(() => _otherSeenAt = DateTime.now());
              // Responde para que el otro también nos vea en línea al tiro.
              if (!wasOnline) _sendHere();
            }
          },
        )
        .onBroadcast(
          event: 'bye',
          callback: (p) {
            if (p['u'] == widget.otherUserId && mounted) {
              setState(() {
                _otherSeenAt = null;
                _otherTypingAt = null;
              });
            }
          },
        )
        .subscribe((status, _) {
      if (status == RealtimeSubscribeStatus.subscribed) _sendHere();
    });
    _heartbeat?.cancel();
    _heartbeat =
        Timer.periodic(const Duration(seconds: 15), (_) => _sendHere());
  }

  void _sendHere() {
    _roomChannel?.sendBroadcastMessage(event: 'here', payload: {'u': _me});
  }

  void _onTextChanged() {
    final has = _ctrl.text.trim().isNotEmpty;
    if (has != _hasText) setState(() => _hasText = has);
    if (has &&
        DateTime.now().difference(_lastTypingSent) >
            const Duration(seconds: 2)) {
      _lastTypingSent = DateTime.now();
      _roomChannel?.sendBroadcastMessage(event: 'typing', payload: {'u': _me});
    }
  }

  void _onInsert(Map<String, dynamic> row) {
    if (!mounted) return;
    final id = row['id'];
    if (_messages.any((m) => m['id'] == id)) return;
    final msg = Map<String, dynamic>.from(row);
    setState(() {
      if (msg['sender_id'] == _me) {
        // Reemplaza el mensaje optimista correspondiente.
        final i = _messages.indexWhere((m) =>
            m['_pending'] != null &&
            (m['kind'] ?? 'text') == (msg['kind'] ?? 'text') &&
            (m['body'] ?? '') == (msg['body'] ?? ''));
        if (i != -1) {
          _messages[i] = msg;
          return;
        }
      } else {
        _otherTypingAt = null;
      }
      _messages.add(msg);
    });
    if (msg['sender_id'] != _me && _threadId != null) _dm.markRead(_threadId!);
    _scrollToBottom();
  }

  void _onUpdate(Map<String, dynamic> row) {
    if (!mounted) return;
    final i = _messages.indexWhere((m) => m['id'] == row['id']);
    if (i == -1) return;
    setState(() => _messages[i] = {..._messages[i], ...row});
  }

  void _scrollToBottom({bool jump = false}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      final max = _scroll.position.maxScrollExtent;
      if (jump) {
        _scroll.jumpTo(max);
      } else {
        _scroll.animateTo(max,
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeOut);
      }
    });
  }

  // ── Envío ──────────────────────────────────────────────────────────────────

  void _snack(String msg, {Color color = Colors.redAccent}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg, style: const TextStyle(fontFamily: 'Poppins')),
      backgroundColor: color,
      behavior: SnackBarBehavior.floating,
    ));
  }

  String _errorText(Object e) {
    final s = e.toString();
    if (s.contains('not_allowed')) {
      return 'Ya no pueden escribirse (dejaron de seguirse o hay un bloqueo).';
    }
    return 'No se pudo enviar el mensaje.';
  }

  Map<String, dynamic> _optimistic(
    String kind,
    String body, {
    String? localPath,
    int? durationMs,
  }) {
    return {
      'id': 'temp_${DateTime.now().microsecondsSinceEpoch}',
      'sender_id': _me,
      'recipient_id': widget.otherUserId,
      'body': body,
      'kind': kind,
      'media_duration_ms': durationMs,
      'reply_to': _replyTo?['id'],
      'created_at': DateTime.now().toUtc().toIso8601String(),
      'read_at': null,
      '_pending': 'sending',
      '_local': localPath,
    };
  }

  void _markSent(Map<String, dynamic> temp) {
    if (!mounted) return;
    setState(() {
      final i = _messages.indexWhere((m) => m['id'] == temp['id']);
      if (i != -1) _messages[i]['_pending'] = 'sent';
    });
  }

  void _dropTemp(Map<String, dynamic> temp) {
    if (!mounted) return;
    setState(() => _messages.removeWhere((m) => m['id'] == temp['id']));
  }

  Future<void> _sendText() async {
    final text = _ctrl.text.trim();
    if (text.isEmpty) return;
    _ctrl.clear();
    final reply = _replyTo;
    final temp = _optimistic('text', text);
    setState(() {
      _messages.add(temp);
      _replyTo = null;
    });
    _scrollToBottom();
    try {
      final tid = await _dm.send(widget.otherUserId, text,
          replyTo: _rich ? (reply?['id'] as String?) : null);
      _afterSend(tid);
      _markSent(temp);
    } catch (e) {
      _dropTemp(temp);
      _snack(_errorText(e));
    }
  }

  void _afterSend(String? tid) {
    if (_threadId == null && tid != null) {
      _threadId = tid;
      _subscribeThread();
    }
  }

  bool _requireRich() {
    if (_rich) return true;
    _snack(
      'Fotos, audios y eliminar para todos se activan cuando se actualice el servidor.',
      color: Colors.orange,
    );
    return false;
  }

  Future<String?> _threadForMedia() async {
    if (_threadId != null) return _threadId;
    try {
      final tid = await _dm.ensureThread(widget.otherUserId);
      _afterSend(tid);
      return tid;
    } catch (e) {
      _snack(_errorText(e));
      return null;
    }
  }

  Future<void> _pickImage(ImageSource source) async {
    if (!_requireRich()) return;
    final x = await _picker.pickImage(
      source: source,
      imageQuality: 78,
      maxWidth: 1600,
      maxHeight: 1600,
    );
    if (x == null || !mounted) return;
    final caption = await _confirmImage(File(x.path));
    if (caption == null) return; // canceló

    final reply = _replyTo;
    final temp = _optimistic('image', caption, localPath: x.path);
    setState(() {
      _messages.add(temp);
      _replyTo = null;
    });
    _scrollToBottom();
    String? uploaded;
    try {
      final tid = await _threadForMedia();
      if (tid == null) {
        _dropTemp(temp);
        return;
      }
      final ext = x.path.toLowerCase().endsWith('.png') ? 'png' : 'jpg';
      uploaded = await _dm.uploadMedia(tid, File(x.path),
          ext: ext, contentType: ext == 'png' ? 'image/png' : 'image/jpeg');
      await _dm.send(widget.otherUserId, caption,
          kind: 'image', mediaPath: uploaded, replyTo: reply?['id'] as String?);
      _markSent(temp);
    } catch (e) {
      if (uploaded != null) _dm.removeMedia(uploaded);
      _dropTemp(temp);
      _snack(_errorText(e));
    }
  }

  /// Vista previa de la foto con campo para agregar un texto.
  /// Devuelve el texto ('' si no escribió) o null si canceló.
  Future<String?> _confirmImage(File file) {
    final caption = TextEditingController();
    return showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.black,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
        child: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  IconButton(
                    onPressed: () => Navigator.pop(ctx),
                    icon: const Icon(Icons.close_rounded, color: Colors.white),
                  ),
                  const Text('Enviar foto',
                      style: TextStyle(
                          fontFamily: 'Poppins',
                          color: Colors.white,
                          fontWeight: FontWeight.w600)),
                ],
              ),
              ConstrainedBox(
                constraints: BoxConstraints(
                    maxHeight: MediaQuery.of(ctx).size.height * 0.6),
                child: Image.file(file, fit: BoxFit.contain),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 12, 8, 12),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: caption,
                        textCapitalization: TextCapitalization.sentences,
                        style: const TextStyle(
                            fontFamily: 'Poppins', color: Colors.white),
                        decoration: InputDecoration(
                          hintText: 'Añade un comentario…',
                          hintStyle: TextStyle(
                              fontFamily: 'Poppins',
                              color: Colors.white.withOpacity(0.4)),
                          filled: true,
                          fillColor: Colors.white.withOpacity(0.08),
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 12),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(24),
                            borderSide: BorderSide.none,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    _roundButton(
                      icon: Icons.send_rounded,
                      onTap: () => Navigator.pop(ctx, caption.text.trim()),
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

  void _openAttachMenu() {
    if (!_requireRich()) return;
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        margin: EdgeInsets.fromLTRB(
            12, 0, 12, 12 + MediaQuery.of(ctx).padding.bottom),
        padding: const EdgeInsets.fromLTRB(16, 18, 16, 18),
        decoration: BoxDecoration(
          color: const Color(0xFF16161F),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: Colors.white.withOpacity(0.08)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            _attachOption(ctx, Icons.photo_library_rounded, 'Galería',
                const Color(0xFFB388FF), ImageSource.gallery),
            _attachOption(ctx, Icons.photo_camera_rounded, 'Cámara',
                const Color(0xFFFF6E9C), ImageSource.camera),
          ],
        ),
      ),
    );
  }

  Widget _attachOption(BuildContext ctx, IconData icon, String label,
      Color color, ImageSource source) {
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: () {
        Navigator.pop(ctx);
        _pickImage(source);
      },
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Column(
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: color.withOpacity(0.18),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: color, size: 26),
            ),
            const SizedBox(height: 6),
            Text(label,
                style: const TextStyle(
                    fontFamily: 'Poppins', color: Colors.white70, fontSize: 12)),
          ],
        ),
      ),
    );
  }

  // ── Mensajes de voz ────────────────────────────────────────────────────────

  Future<void> _startRecording() async {
    if (!_requireRich()) return;
    try {
      if (!await _recorder.hasPermission()) {
        _snack('Necesitas dar permiso de micrófono para grabar audios.',
            color: Colors.orange);
        return;
      }
      _AudioBubbleState.stopAll();
      final dir = await getTemporaryDirectory();
      final path =
          '${dir.path}/pedalea_voz_${DateTime.now().millisecondsSinceEpoch}.m4a';
      await _recorder.start(
        const RecordConfig(
            encoder: AudioEncoder.aacLc, bitRate: 64000, sampleRate: 44100),
        path: path,
      );
      HapticFeedback.mediumImpact();
      setState(() {
        _recording = true;
        _recStart = DateTime.now();
        _recElapsed = Duration.zero;
      });
      _recTimer?.cancel();
      _recTimer = Timer.periodic(const Duration(milliseconds: 250), (_) {
        if (!mounted || _recStart == null) return;
        setState(() => _recElapsed = DateTime.now().difference(_recStart!));
        if (_recElapsed >= const Duration(minutes: 5)) _stopRecording(send: true);
      });
    } catch (e) {
      _snack('No se pudo iniciar la grabación.');
    }
  }

  Future<void> _stopRecording({required bool send}) async {
    _recTimer?.cancel();
    final elapsed = _recElapsed;
    String? path;
    try {
      path = await _recorder.stop();
    } catch (_) {}
    if (!mounted) return;
    setState(() {
      _recording = false;
      _recStart = null;
    });
    if (!send || path == null) {
      if (path != null) {
        try {
          File(path).deleteSync();
        } catch (_) {}
      }
      return;
    }
    if (elapsed < const Duration(milliseconds: 800)) {
      _snack('Mantén la grabación un poco más.', color: Colors.orange);
      return;
    }
    final reply = _replyTo;
    final durationMs = elapsed.inMilliseconds;
    final temp = _optimistic('audio', '', localPath: path, durationMs: durationMs);
    setState(() {
      _messages.add(temp);
      _replyTo = null;
    });
    _scrollToBottom();
    String? uploaded;
    try {
      final tid = await _threadForMedia();
      if (tid == null) {
        _dropTemp(temp);
        return;
      }
      uploaded = await _dm.uploadMedia(tid, File(path),
          ext: 'm4a', contentType: 'audio/mp4');
      await _dm.send(widget.otherUserId, '',
          kind: 'audio',
          mediaPath: uploaded,
          durationMs: durationMs,
          replyTo: reply?['id'] as String?);
      _markSent(temp);
    } catch (e) {
      if (uploaded != null) _dm.removeMedia(uploaded);
      _dropTemp(temp);
      _snack(_errorText(e));
    }
  }

  // ── Acciones sobre un mensaje ──────────────────────────────────────────────

  void _setReply(Map<String, dynamic> m) {
    if (m['deleted_at'] != null || m['_pending'] != null) return;
    HapticFeedback.selectionClick();
    setState(() => _replyTo = m);
    _focus.requestFocus();
  }

  Future<void> _deleteForAll(Map<String, dynamic> m) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF16161F),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('¿Eliminar para todos?',
            style: TextStyle(fontFamily: 'Poppins', color: Colors.white)),
        content: Text(
          'El mensaje desaparecerá también para ${widget.otherName}.',
          style: TextStyle(
              fontFamily: 'Poppins', color: Colors.white.withOpacity(0.7)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar',
                style: TextStyle(fontFamily: 'Poppins', color: Colors.white54)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Eliminar',
                style: TextStyle(
                    fontFamily: 'Poppins',
                    color: Colors.redAccent,
                    fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await _dm.deleteForAll(m['id'] as String);
      final i = _messages.indexWhere((x) => x['id'] == m['id']);
      if (i != -1 && mounted) {
        setState(() => _messages[i] = {
              ..._messages[i],
              'deleted_at': DateTime.now().toUtc().toIso8601String(),
              'body': '',
              'media_path': null,
            });
      }
    } catch (_) {
      _snack('No se pudo eliminar el mensaje.');
    }
  }

  void _openMessageActions(Map<String, dynamic> m) {
    if (m['_pending'] != null) return;
    final mine = m['sender_id'] == _me;
    final deleted = m['deleted_at'] != null;
    final kind = (m['kind'] as String?) ?? 'text';
    final body = (m['body'] as String?) ?? '';
    final created = DateTime.tryParse(m['created_at'] as String? ?? '')?.toLocal();
    final readAt = DateTime.tryParse(m['read_at'] as String? ?? '')?.toLocal();
    HapticFeedback.mediumImpact();

    Widget action(IconData icon, String label, VoidCallback onTap,
            {Color color = Colors.white}) =>
        ListTile(
          leading: Icon(icon, color: color, size: 22),
          title: Text(label,
              style: TextStyle(
                  fontFamily: 'Poppins', color: color, fontSize: 14.5)),
          onTap: onTap,
        );

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        margin: EdgeInsets.fromLTRB(
            12, 0, 12, 12 + MediaQuery.of(ctx).padding.bottom),
        decoration: BoxDecoration(
          color: const Color(0xFF16161F),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: Colors.white.withOpacity(0.08)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 38,
              height: 4,
              margin: const EdgeInsets.only(top: 10, bottom: 6),
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            if (created != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 6, 20, 6),
                child: Row(
                  children: [
                    Icon(Icons.schedule_rounded,
                        size: 15, color: Colors.white.withOpacity(0.45)),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        mine && readAt != null
                            ? 'Enviado ${timeAgoLong(created)} · Leído ${timeAgoLong(readAt)}'
                            : 'Enviado ${timeAgoLong(created)}',
                        style: TextStyle(
                            fontFamily: 'Poppins',
                            color: Colors.white.withOpacity(0.5),
                            fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ),
            if (!deleted && _rich)
              action(Icons.reply_rounded, 'Responder', () {
                Navigator.pop(ctx);
                _setReply(m);
              }),
            if (!deleted && kind == 'text' && body.isNotEmpty)
              action(Icons.copy_rounded, 'Copiar', () {
                Clipboard.setData(ClipboardData(text: body));
                Navigator.pop(ctx);
                _snack('Mensaje copiado', color: Colors.green);
              }),
            if (mine && !deleted && _rich)
              action(Icons.delete_outline_rounded, 'Eliminar para todos', () {
                Navigator.pop(ctx);
                _deleteForAll(m);
              }, color: Colors.redAccent),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  // ── UI ─────────────────────────────────────────────────────────────────────

  String get _statusText {
    if (_otherTyping) return 'escribiendo…';
    if (_otherOnline) return 'en línea';
    return 'toca para ver el perfil';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBgDark,
      appBar: _appBar(),
      body: Column(
        children: [
          Expanded(
            child: Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0xFF0A0A12), Color(0xFF0D0F14)],
                ),
              ),
              child: _loading
                  ? const Center(
                      child: CircularProgressIndicator(
                          color: _kAccent, strokeWidth: 2))
                  : _messages.isEmpty
                      ? _emptyState()
                      : ListView.builder(
                          controller: _scroll,
                          padding: const EdgeInsets.fromLTRB(10, 12, 10, 10),
                          itemCount: _messages.length,
                          itemBuilder: (_, i) => _messageAt(i),
                        ),
            ),
          ),
          _composer(),
        ],
      ),
    );
  }

  PreferredSizeWidget _appBar() {
    final hasAvatar =
        widget.otherAvatar != null && widget.otherAvatar!.isNotEmpty;
    return AppBar(
      backgroundColor: _kBar,
      surfaceTintColor: _kBar,
      elevation: 0,
      iconTheme: const IconThemeData(color: Colors.white),
      titleSpacing: 0,
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(1),
        child: Container(height: 1, color: Colors.white.withOpacity(0.06)),
      ),
      title: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
              builder: (_) => PublicProfilePage(userId: widget.otherUserId)),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  CircleAvatar(
                    radius: 19,
                    backgroundColor: Colors.white12,
                    backgroundImage: hasAvatar
                        ? CachedNetworkImageProvider(widget.otherAvatar!)
                        : null,
                    child: hasAvatar
                        ? null
                        : Text(
                            widget.otherName.isNotEmpty
                                ? widget.otherName.substring(0, 1).toUpperCase()
                                : '?',
                            style: const TextStyle(
                                fontFamily: 'Poppins',
                                color: Colors.white,
                                fontSize: 14)),
                  ),
                  if (_otherOnline)
                    Positioned(
                      right: -1,
                      bottom: -1,
                      child: Container(
                        width: 12,
                        height: 12,
                        decoration: BoxDecoration(
                          color: _kAccent,
                          shape: BoxShape.circle,
                          border: Border.all(color: _kBar, width: 2),
                        ),
                      ),
                    )
                  else if (widget.otherIsPlus)
                    Positioned(
                      bottom: -3,
                      right: -3,
                      child: PlusMedal(
                          size: 14,
                          variant: widget.otherBadgeVariant,
                          ringColor: _kBar),
                    ),
                ],
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(widget.otherName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontFamily: 'Poppins',
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                            fontSize: 15.5)),
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 200),
                      child: Text(
                        _statusText,
                        key: ValueKey(_statusText),
                        style: TextStyle(
                          fontFamily: 'Poppins',
                          color: (_otherTyping || _otherOnline)
                              ? _kAccent
                              : Colors.white.withOpacity(0.45),
                          fontSize: 11.5,
                          fontStyle:
                              _otherTyping ? FontStyle.italic : FontStyle.normal,
                        ),
                      ),
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

  Widget _emptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 76,
              height: 76,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _kAccent.withOpacity(0.08),
                border: Border.all(color: _kAccent.withOpacity(0.25)),
              ),
              child: const Icon(Icons.waving_hand_rounded,
                  color: _kAccent, size: 32),
            ),
            const SizedBox(height: 14),
            Text(
              'Saluda a ${widget.otherName}',
              textAlign: TextAlign.center,
              style: const TextStyle(
                  fontFamily: 'Poppins',
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 4),
            Text(
              'Coordinen una salida o compartan su ruta favorita.',
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontFamily: 'Poppins',
                  color: Colors.white.withOpacity(0.45),
                  fontSize: 12.5),
            ),
          ],
        ),
      ),
    );
  }

  DateTime? _time(Map<String, dynamic> m) =>
      DateTime.tryParse(m['created_at'] as String? ?? '')?.toLocal();

  Widget _messageAt(int i) {
    final m = _messages[i];
    final t = _time(m);
    final prev = i > 0 ? _messages[i - 1] : null;
    final next = i < _messages.length - 1 ? _messages[i + 1] : null;
    final prevT = prev == null ? null : _time(prev);
    final showDay = t != null && (prevT == null || !sameDay(prevT, t));
    // Agrupa mensajes seguidos del mismo autor (menos espacio, una sola cola).
    final groupedWithNext = next != null &&
        next['sender_id'] == m['sender_id'] &&
        _time(next) != null &&
        t != null &&
        _time(next)!.difference(t).inMinutes < 3;

    return Column(
      children: [
        if (showDay) _dayChip(t),
        _SwipeToReply(
          enabled: _rich && m['deleted_at'] == null && m['_pending'] == null,
          onReply: () => _setReply(m),
          child: _bubble(m, tail: !groupedWithNext),
        ),
        SizedBox(height: groupedWithNext ? 2 : 8),
      ],
    );
  }

  Widget _dayChip(DateTime t) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.07),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            dayLabel(t),
            style: TextStyle(
              fontFamily: 'Poppins',
              color: Colors.white.withOpacity(0.6),
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }

  Map<String, dynamic>? _findMessage(String? id) {
    if (id == null) return null;
    for (final m in _messages) {
      if (m['id'] == id) return m;
    }
    return null;
  }

  String _previewOf(Map<String, dynamic> m) {
    if (m['deleted_at'] != null) return 'Mensaje eliminado';
    switch ((m['kind'] as String?) ?? 'text') {
      case 'image':
        final b = (m['body'] as String?) ?? '';
        return b.isEmpty ? '📷 Foto' : '📷 $b';
      case 'audio':
        return '🎤 Mensaje de voz';
      default:
        return (m['body'] as String?) ?? '';
    }
  }

  Widget _quote(Map<String, dynamic> q, {required bool mine}) {
    final qMine = q['sender_id'] == _me;
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.22),
        borderRadius: BorderRadius.circular(10),
        border: Border(
          left: BorderSide(
              color: qMine ? _kAccent : const Color(0xFF7CC4FF), width: 3),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            qMine ? 'Tú' : widget.otherName,
            style: TextStyle(
              fontFamily: 'Poppins',
              color: qMine ? _kAccent : const Color(0xFF7CC4FF),
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
            ),
          ),
          Text(
            _previewOf(q),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontFamily: 'Poppins',
              color: Colors.white.withOpacity(0.7),
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  Widget _ticks(Map<String, dynamic> m) {
    final pending = m['_pending'];
    if (pending == 'sending') {
      return Icon(Icons.schedule_rounded,
          size: 13, color: Colors.white.withOpacity(0.5));
    }
    final read = m['read_at'] != null;
    return Icon(
      read ? Icons.done_all_rounded : Icons.done_rounded,
      size: 15,
      color: read ? const Color(0xFF4FC3F7) : Colors.white.withOpacity(0.55),
    );
  }

  Widget _bubble(Map<String, dynamic> m, {required bool tail}) {
    final mine = m['sender_id'] == _me;
    final deleted = m['deleted_at'] != null;
    final kind = (m['kind'] as String?) ?? 'text';
    final body = (m['body'] as String?) ?? '';
    final t = _time(m);
    final time = t == null ? '' : hhmm(t);
    final quote = _findMessage(m['reply_to'] as String?);
    final maxW = MediaQuery.of(context).size.width * 0.78;

    final radius = BorderRadius.only(
      topLeft: const Radius.circular(18),
      topRight: const Radius.circular(18),
      bottomLeft: Radius.circular(!mine && tail ? 4 : 18),
      bottomRight: Radius.circular(mine && tail ? 4 : 18),
    );

    final meta = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(time,
            style: TextStyle(
                fontFamily: 'Poppins',
                color: Colors.white.withOpacity(0.5),
                fontSize: 10)),
        if (mine && !deleted) ...[const SizedBox(width: 3), _ticks(m)],
      ],
    );

    Widget content;
    EdgeInsets padding = const EdgeInsets.fromLTRB(12, 8, 10, 6);
    if (deleted) {
      content = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.block_rounded,
              size: 15, color: Colors.white.withOpacity(0.45)),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              mine ? 'Eliminaste este mensaje' : 'Se eliminó este mensaje',
              style: TextStyle(
                fontFamily: 'Poppins',
                color: Colors.white.withOpacity(0.5),
                fontSize: 13.5,
                fontStyle: FontStyle.italic,
              ),
            ),
          ),
          const SizedBox(width: 8),
          meta,
        ],
      );
    } else if (kind == 'image') {
      padding = const EdgeInsets.all(4);
      content = Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (quote != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 4, 4, 0),
              child: _quote(quote, mine: mine),
            ),
          Stack(
            children: [
              _ChatImage(
                path: m['media_path'] as String?,
                localPath: m['_local'] as String?,
                uploading: m['_pending'] == 'sending',
                onOpen: (provider) => _openImage(provider),
              ),
              if (body.isEmpty)
                Positioned(
                  right: 6,
                  bottom: 6,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.45),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: meta,
                  ),
                ),
            ],
          ),
          if (body.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 6, 6, 2),
              child: _textWithMeta(body, meta),
            ),
        ],
      );
    } else if (kind == 'audio') {
      padding = const EdgeInsets.fromLTRB(6, 6, 10, 6);
      content = Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (quote != null) _quote(quote, mine: mine),
          _AudioBubble(
            path: m['media_path'] as String?,
            localPath: m['_local'] as String?,
            durationMs: (m['media_duration_ms'] as num?)?.toInt(),
            mine: mine,
          ),
          meta,
        ],
      );
    } else {
      content = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (quote != null) _quote(quote, mine: mine),
          _textWithMeta(body, meta),
        ],
      );
    }

    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: GestureDetector(
        onLongPress: () => _openMessageActions(m),
        child: Container(
          constraints: BoxConstraints(maxWidth: maxW),
          padding: padding,
          decoration: BoxDecoration(
            gradient: mine && !deleted
                ? LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      const Color(0xFF1F5F2C),
                      const Color(0xFF17491F)
                          .withOpacity(m['_pending'] == 'sending' ? 0.7 : 1),
                    ],
                  )
                : null,
            color: mine && !deleted
                ? null
                : (deleted
                    ? Colors.white.withOpacity(0.04)
                    : const Color(0xFF1E2029)),
            borderRadius: radius,
            border: deleted
                ? Border.all(color: Colors.white.withOpacity(0.08))
                : null,
          ),
          child: content,
        ),
      ),
    );
  }

  /// Texto con la hora al final de la última línea (como WhatsApp).
  Widget _textWithMeta(String text, Widget meta) {
    return Wrap(
      alignment: WrapAlignment.end,
      crossAxisAlignment: WrapCrossAlignment.end,
      spacing: 8,
      children: [
        Text(text,
            style: const TextStyle(
                fontFamily: 'Poppins',
                color: Colors.white,
                fontSize: 14.5,
                height: 1.35)),
        Padding(padding: const EdgeInsets.only(top: 2), child: meta),
      ],
    );
  }

  void _openImage(ImageProvider provider) {
    Navigator.push(
      context,
      PageRouteBuilder(
        opaque: false,
        barrierColor: Colors.black,
        pageBuilder: (ctx, _, _) => Scaffold(
          backgroundColor: Colors.black,
          appBar: AppBar(
            backgroundColor: Colors.black,
            iconTheme: const IconThemeData(color: Colors.white),
          ),
          body: Center(
            child: InteractiveViewer(
              maxScale: 5,
              child: Image(image: provider, fit: BoxFit.contain),
            ),
          ),
        ),
      ),
    );
  }

  Widget _roundButton({
    Key? key,
    required IconData icon,
    required VoidCallback? onTap,
    Color color = _kAccent,
    Color iconColor = Colors.black,
  }) {
    return Material(
      key: key,
      color: color,
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: SizedBox(
          width: 46,
          height: 46,
          child: Icon(icon, color: iconColor, size: 22),
        ),
      ),
    );
  }

  String _fmtDur(Duration d) =>
      '${d.inMinutes}:${(d.inSeconds % 60).toString().padLeft(2, '0')}';

  Widget _composer() {
    final bottom = MediaQuery.of(context).padding.bottom;
    return Container(
      padding: EdgeInsets.fromLTRB(8, 8, 8, 8 + bottom),
      decoration: BoxDecoration(
        color: _kBar,
        border: Border(top: BorderSide(color: Colors.white.withOpacity(0.06))),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_replyTo != null)
            Container(
              margin: const EdgeInsets.fromLTRB(4, 0, 4, 8),
              padding: const EdgeInsets.fromLTRB(10, 6, 4, 6),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.05),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(
                children: [
                  const Icon(Icons.reply_rounded, color: _kAccent, size: 18),
                  const SizedBox(width: 8),
                  Expanded(child: _quote(_replyTo!, mine: false)),
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    onPressed: () => setState(() => _replyTo = null),
                    icon: const Icon(Icons.close_rounded,
                        color: Colors.white54, size: 18),
                  ),
                ],
              ),
            ),
          _recording ? _recordingBar() : _inputRow(),
        ],
      ),
    );
  }

  Widget _inputRow() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.06),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: Colors.white.withOpacity(0.06)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                IconButton(
                  tooltip: 'Adjuntar foto',
                  onPressed: _openAttachMenu,
                  icon: Icon(Icons.add_photo_alternate_rounded,
                      color: Colors.white.withOpacity(0.6), size: 23),
                ),
                Expanded(
                  child: TextField(
                    controller: _ctrl,
                    focusNode: _focus,
                    minLines: 1,
                    maxLines: 5,
                    textCapitalization: TextCapitalization.sentences,
                    style: const TextStyle(
                        fontFamily: 'Poppins',
                        color: Colors.white,
                        fontSize: 14.5),
                    cursorColor: _kAccent,
                    decoration: InputDecoration(
                      hintText: 'Mensaje',
                      hintStyle: TextStyle(
                          fontFamily: 'Poppins',
                          color: Colors.white.withOpacity(0.4)),
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.fromLTRB(0, 12, 12, 12),
                    ),
                  ),
                ),
                if (!_hasText)
                  IconButton(
                    tooltip: 'Cámara',
                    onPressed: () {
                      if (_requireRich()) _pickImage(ImageSource.camera);
                    },
                    icon: Icon(Icons.photo_camera_rounded,
                        color: Colors.white.withOpacity(0.6), size: 22),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 6),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 160),
          transitionBuilder: (c, a) => ScaleTransition(scale: a, child: c),
          child: _hasText
              ? _roundButton(
                  key: const ValueKey('send'),
                  icon: Icons.send_rounded,
                  onTap: _sendText,
                )
              : _roundButton(
                  key: const ValueKey('mic'),
                  icon: Icons.mic_rounded,
                  onTap: _startRecording,
                ),
        ),
      ],
    );
  }

  Widget _recordingBar() {
    return Row(
      children: [
        IconButton(
          tooltip: 'Descartar',
          onPressed: () => _stopRecording(send: false),
          icon: const Icon(Icons.delete_outline_rounded,
              color: Colors.redAccent, size: 26),
        ),
        Expanded(
          child: Container(
            height: 46,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.06),
              borderRadius: BorderRadius.circular(24),
            ),
            child: Row(
              children: [
                _BlinkingDot(),
                const SizedBox(width: 10),
                Text(
                  _fmtDur(_recElapsed),
                  style: const TextStyle(
                    fontFamily: 'Poppins',
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    fontFeatures: [FontFeature.tabularFigures()],
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Grabando mensaje de voz…',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      color: Colors.white.withOpacity(0.5),
                      fontSize: 12.5,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 6),
        _roundButton(
          icon: Icons.send_rounded,
          onTap: () => _stopRecording(send: true),
        ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
//  Widgets auxiliares
// ═══════════════════════════════════════════════════════════════════════════

/// Desliza un mensaje hacia la derecha para responderlo.
class _SwipeToReply extends StatefulWidget {
  final Widget child;
  final VoidCallback onReply;
  final bool enabled;
  const _SwipeToReply({
    required this.child,
    required this.onReply,
    required this.enabled,
  });

  @override
  State<_SwipeToReply> createState() => _SwipeToReplyState();
}

class _SwipeToReplyState extends State<_SwipeToReply> {
  double _dx = 0;
  bool _fired = false;
  static const _trigger = 64.0;

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled) return widget.child;
    return GestureDetector(
      onHorizontalDragUpdate: (d) {
        setState(() => _dx = (_dx + d.delta.dx).clamp(0.0, 90.0));
        if (!_fired && _dx >= _trigger) {
          _fired = true;
          HapticFeedback.lightImpact();
        }
      },
      onHorizontalDragEnd: (_) {
        if (_fired) widget.onReply();
        setState(() {
          _dx = 0;
          _fired = false;
        });
      },
      onHorizontalDragCancel: () => setState(() {
        _dx = 0;
        _fired = false;
      }),
      child: Stack(
        alignment: Alignment.centerLeft,
        children: [
          Opacity(
            opacity: (_dx / _trigger).clamp(0.0, 1.0),
            child: Padding(
              padding: const EdgeInsets.only(left: 6),
              child: Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.reply_rounded,
                    color: Colors.white70, size: 18),
              ),
            ),
          ),
          AnimatedContainer(
            duration: Duration(milliseconds: _dx == 0 ? 180 : 0),
            curve: Curves.easeOut,
            transform: Matrix4.translationValues(_dx, 0, 0),
            child: widget.child,
          ),
        ],
      ),
    );
  }
}

/// Foto del chat: local mientras sube; luego desde el bucket privado.
class _ChatImage extends StatefulWidget {
  final String? path;
  final String? localPath;
  final bool uploading;
  final void Function(ImageProvider) onOpen;
  const _ChatImage({
    required this.path,
    required this.localPath,
    required this.uploading,
    required this.onOpen,
  });

  @override
  State<_ChatImage> createState() => _ChatImageState();
}

class _ChatImageState extends State<_ChatImage> {
  String? _url;

  @override
  void initState() {
    super.initState();
    _resolve();
  }

  @override
  void didUpdateWidget(covariant _ChatImage old) {
    super.didUpdateWidget(old);
    if (old.path != widget.path) _resolve();
  }

  Future<void> _resolve() async {
    final p = widget.path;
    if (p == null) return;
    final url = await DmService.instance.mediaUrl(p);
    if (mounted) setState(() => _url = url);
  }

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.of(context).size.width * 0.66;
    ImageProvider? provider;
    if (widget.localPath != null && File(widget.localPath!).existsSync()) {
      provider = FileImage(File(widget.localPath!));
    } else if (_url != null) {
      provider = CachedNetworkImageProvider(_url!, cacheKey: widget.path);
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: SizedBox(
        width: w,
        height: w * 1.1,
        child: provider == null
            ? Container(
                color: Colors.white.withOpacity(0.05),
                child: const Center(
                  child: CircularProgressIndicator(
                      color: _kAccent, strokeWidth: 2),
                ),
              )
            : GestureDetector(
                onTap: () => widget.onOpen(provider!),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Image(
                      image: provider,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => Container(
                        color: Colors.white.withOpacity(0.05),
                        child: const Icon(Icons.broken_image_outlined,
                            color: Colors.white38),
                      ),
                    ),
                    if (widget.uploading)
                      Container(
                        color: Colors.black.withOpacity(0.35),
                        child: const Center(
                          child: SizedBox(
                            width: 34,
                            height: 34,
                            child: CircularProgressIndicator(
                                color: Colors.white, strokeWidth: 2.5),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
      ),
    );
  }
}

/// Mensaje de voz con play/pausa, barra de progreso y duración.
class _AudioBubble extends StatefulWidget {
  final String? path;
  final String? localPath;
  final int? durationMs;
  final bool mine;
  const _AudioBubble({
    required this.path,
    required this.localPath,
    required this.durationMs,
    required this.mine,
  });

  @override
  State<_AudioBubble> createState() => _AudioBubbleState();
}

class _AudioBubbleState extends State<_AudioBubble> {
  static final Set<_AudioBubbleState> _all = {};
  static void stopAll() {
    for (final s in _all.toList()) {
      s._player.stop();
    }
  }

  final _player = AudioPlayer();
  bool _playing = false;
  bool _loading = false;
  Duration _pos = Duration.zero;
  Duration? _dur;
  final List<StreamSubscription> _subs = [];

  @override
  void initState() {
    super.initState();
    _all.add(this);
    if (widget.durationMs != null) {
      _dur = Duration(milliseconds: widget.durationMs!);
    }
    _subs.add(_player.onPositionChanged.listen((p) {
      if (mounted) setState(() => _pos = p);
    }));
    _subs.add(_player.onDurationChanged.listen((d) {
      if (mounted && d > Duration.zero) setState(() => _dur = d);
    }));
    _subs.add(_player.onPlayerStateChanged.listen((s) {
      if (mounted) setState(() => _playing = s == PlayerState.playing);
    }));
    _subs.add(_player.onPlayerComplete.listen((_) {
      if (mounted) setState(() => _pos = Duration.zero);
    }));
  }

  @override
  void dispose() {
    _all.remove(this);
    for (final s in _subs) {
      s.cancel();
    }
    _player.dispose();
    super.dispose();
  }

  Future<void> _toggle() async {
    if (_playing) {
      await _player.pause();
      return;
    }
    for (final s in _all) {
      if (s != this) s._player.pause();
    }
    if (_player.source != null && _pos > Duration.zero) {
      await _player.resume();
      return;
    }
    setState(() => _loading = true);
    try {
      if (widget.localPath != null && File(widget.localPath!).existsSync()) {
        await _player.play(DeviceFileSource(widget.localPath!));
      } else if (widget.path != null) {
        final url = await DmService.instance.mediaUrl(widget.path!);
        if (url != null) await _player.play(UrlSource(url));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('No se pudo reproducir el audio',
              style: TextStyle(fontFamily: 'Poppins')),
        ));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _fmt(Duration d) =>
      '${d.inMinutes}:${(d.inSeconds % 60).toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final total = _dur ?? Duration.zero;
    final progress = total.inMilliseconds == 0
        ? 0.0
        : (_pos.inMilliseconds / total.inMilliseconds).clamp(0.0, 1.0);
    final accent = widget.mine ? _kAccent : const Color(0xFF7CC4FF);
    return SizedBox(
      width: MediaQuery.of(context).size.width * 0.6,
      child: Row(
        children: [
          Material(
            color: accent,
            shape: const CircleBorder(),
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: _loading ? null : _toggle,
              child: SizedBox(
                width: 40,
                height: 40,
                child: _loading
                    ? const Padding(
                        padding: EdgeInsets.all(11),
                        child: CircularProgressIndicator(
                            color: Colors.black, strokeWidth: 2),
                      )
                    : Icon(
                        _playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                        color: Colors.black,
                        size: 24,
                      ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // "Onda" decorativa que se rellena con el progreso.
                SizedBox(
                  height: 24,
                  child: LayoutBuilder(
                    builder: (_, c) {
                      const bars = 26;
                      return Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: List.generate(bars, (i) {
                          final h = 6 +
                              ((i * 37 + 11) % 17) +
                              (i.isEven ? 2.0 : 0.0);
                          final filled = (i + 0.5) / bars <= progress;
                          return Container(
                            width: (c.maxWidth / bars) * 0.55,
                            height: h.toDouble(),
                            decoration: BoxDecoration(
                              color: filled
                                  ? accent
                                  : Colors.white.withOpacity(0.3),
                              borderRadius: BorderRadius.circular(2),
                            ),
                          );
                        }),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  _playing || _pos > Duration.zero ? _fmt(_pos) : _fmt(total),
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    color: Colors.white.withOpacity(0.6),
                    fontSize: 10.5,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _BlinkingDot extends StatefulWidget {
  @override
  State<_BlinkingDot> createState() => _BlinkingDotState();
}

class _BlinkingDotState extends State<_BlinkingDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 700),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: Tween(begin: 0.25, end: 1.0).animate(_c),
      child: Container(
        width: 10,
        height: 10,
        decoration: const BoxDecoration(
          color: Colors.redAccent,
          shape: BoxShape.circle,
        ),
      ),
    );
  }
}

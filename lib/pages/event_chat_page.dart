import 'dart:async';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../widgets/plus_medal.dart';
import '../services/plus_prefs_service.dart';
import '../services/chat_notifications_service.dart';
import 'public_profile_page.dart';

class EventChatPage extends StatefulWidget {
  final String eventId;
  final String eventTitle;

  const EventChatPage({
    super.key,
    required this.eventId,
    required this.eventTitle,
  });

  @override
  State<EventChatPage> createState() => _EventChatPageState();
}

class _EventChatPageState extends State<EventChatPage>
    with TickerProviderStateMixin {
  final _messageController = TextEditingController();
  final _scrollController = ScrollController();
  List<Map<String, dynamic>> _messages = [];
  late final SupabaseClient _supabase;
  String? _eventCreatorId;
  bool _isLoading = true;
  final Map<String, String> _userNames = {};
  final Map<String, String?> _userAvatars = {};
  final Map<String, bool> _userIsPlus = {};
  final Map<String, int> _userBadgeVariant = {}; // variante de medalla por user
  final Set<String> _blockedUserIds = {};
  RealtimeChannel? _channel;

  // Typing indicator
  final Map<String, String> _typingUsers = {}; // userId -> userName
  Timer? _typingDebounce;
  bool _isSendingTyping = false;

  // Dots animation
  late AnimationController _dotsController;

  @override
  void initState() {
    super.initState();
    _supabase = Supabase.instance.client;
    // No notificar los mensajes del chat que el usuario está viendo.
    ChatNotificationsService.activeEventId = widget.eventId;
    _dotsController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();
    _loadEventCreator();
    _loadMyName();
    _loadBlockedUsers();
    _loadMessages();
    _setupRealtimeChannel();
  }

  Future<void> _loadMyName() async {
    final myId = _supabase.auth.currentUser?.id;
    if (myId != null) await _getUserName(myId);
  }

  Future<void> _loadEventCreator() async {
    try {
      final response = await _supabase
          .from('events')
          .select('user_id')
          .eq('id', widget.eventId)
          .single();
      if (mounted) setState(() => _eventCreatorId = response['user_id']);
    } catch (e) {
      debugPrint('Error cargando creador: $e');
    }
  }

  Future<void> _loadBlockedUsers() async {
    final myId = _supabase.auth.currentUser?.id;
    if (myId == null) return;
    try {
      final rows = await _supabase
          .from('blocked_users')
          .select('blocked_id')
          .eq('blocker_id', myId);
      if (!mounted) return;
      setState(() {
        _blockedUserIds
          ..clear()
          ..addAll(rows.map((r) => r['blocked_id'] as String));
      });
    } catch (e) {
      debugPrint('Error cargando bloqueados: $e');
    }
  }

  Future<void> _blockUser(String userId, String userName) async {
    final myId = _supabase.auth.currentUser?.id;
    if (myId == null || userId == myId) return;
    try {
      await _supabase.from('blocked_users').insert({
        'blocker_id': myId,
        'blocked_id': userId,
      });
      if (!mounted) return;
      setState(() {
        _blockedUserIds.add(userId);
        _typingUsers.remove(userId);
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Bloqueaste a $userName. Ya no verás sus mensajes.',
              style: const TextStyle(fontFamily: 'Poppins')),
          backgroundColor: Colors.grey[800],
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al bloquear: $e',
                style: const TextStyle(fontFamily: 'Poppins')),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    }
  }

  Future<void> _reportUser(String userId, String reason) async {
    final myId = _supabase.auth.currentUser?.id;
    if (myId == null || userId == myId || reason.trim().isEmpty) return;
    try {
      await _supabase.from('user_reports').insert({
        'reporter_id': myId,
        'reported_id': userId,
        'event_id': widget.eventId,
        'reason': reason.trim(),
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Gracias, revisaremos tu reporte.',
                style: TextStyle(fontFamily: 'Poppins')),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al reportar: $e',
                style: const TextStyle(fontFamily: 'Poppins')),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    }
  }

  Future<String> _getUserName(String userId) async {
    if (_userNames.containsKey(userId)) return _userNames[userId]!;
    try {
      final response = await _supabase
          .from('profiles')
          .select('username, full_name, avatar_url, is_plus, plus_badge_variant')
          .eq('id', userId)
          .maybeSingle();
      String name = 'Usuario';
      if (response != null) {
        if (response['username']?.toString().isNotEmpty == true) {
          name = response['username'];
        } else if (response['full_name']?.toString().isNotEmpty == true) {
          name = response['full_name'];
        }
      }
      _userNames[userId] = name;
      _userAvatars[userId] = response?['avatar_url'] as String?;
      _userIsPlus[userId] = response?['is_plus'] as bool? ?? false;
      _userBadgeVariant[userId] =
          (response?['plus_badge_variant'] as num?)?.toInt() ?? 0;
      return name;
    } catch (_) {
      return 'Usuario';
    }
  }

  Future<void> _showParticipantInfo(String userId, String userName, bool isCreator) async {
    showDialog(
      context: context,
      builder: (ctx) => _ParticipantInfoDialog(
        supabase: _supabase,
        userId: userId,
        userName: userName,
        isCreator: isCreator,
        fallbackAvatarUrl: _userAvatars[userId],
        fallbackIsPlus: _userIsPlus[userId] ?? false,
        fallbackBadgeVariant: _userBadgeVariant[userId] ?? 0,
        color: _getUserColor(userId),
        initial: _getUserInitial(userName),
        onBlock: () => _blockUser(userId, userName),
        onReport: (reason) => _reportUser(userId, reason),
      ),
    );
  }

  void _setupRealtimeChannel() {
    final myId = _supabase.auth.currentUser?.id;
    _channel = _supabase.channel('event_chat_${widget.eventId}');

    // Mensajes en tiempo real
    _channel!.onPostgresChanges(
      event: PostgresChangeEvent.insert,
      schema: 'public',
      table: 'event_messages',
      filter: PostgresChangeFilter(
        column: 'event_id',
        value: widget.eventId,
        type: PostgresChangeFilterType.eq,
      ),
      callback: (payload) async {
        final msg = Map<String, dynamic>.from(payload.newRecord);
        final userId = msg['user_id'] as String?;
        final myId = _supabase.auth.currentUser?.id;

        // Los mensajes propios ya se agregan localmente al enviar
        if (userId == myId) return;

        if (userId != null && !_userNames.containsKey(userId)) {
          await _getUserName(userId);
        }
        if (!mounted) return;
        setState(() {
          _messages.add(msg);
          if (userId != null) _typingUsers.remove(userId);
        });
        _scrollToBottom();
      },
    );

    // Typing broadcast
    _channel!.onBroadcast(
      event: 'typing',
      callback: (payload) async {
        final userId = payload['user_id'] as String?;
        final isTyping = payload['is_typing'] as bool? ?? false;
        if (userId == null || userId == myId) return;
        if (_blockedUserIds.contains(userId)) return;
        String? name = _userNames[userId];
        name ??= await _getUserName(userId);
        if (!mounted) return;
        setState(() {
          if (isTyping) {
            _typingUsers[userId] = name!;
          } else {
            _typingUsers.remove(userId);
          }
        });
      },
    );

    _channel!.subscribe((status, [error]) {
      debugPrint('📡 Canal estado: $status');
    });
  }

  Future<void> _loadMessages() async {
    try {
      final messages = await _supabase
          .from('event_messages')
          .select()
          .eq('event_id', widget.eventId)
          .order('created_at', ascending: true);

      for (final msg in messages) {
        final uid = msg['user_id'] as String?;
        if (uid != null && !_userNames.containsKey(uid)) {
          await _getUserName(uid);
        }
      }
      if (mounted) {
        setState(() {
          _messages = List<Map<String, dynamic>>.from(messages);
          _isLoading = false;
        });
        WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
      }
    } catch (e) {
      debugPrint('Error cargando mensajes: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _scrollToBottom() {
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
  }

  void _onTextChanged(String value) {
    final myId = _supabase.auth.currentUser?.id;
    if (myId == null) return;
    final myName = _userNames[myId] ?? 'Yo';

    if (value.isNotEmpty && !_isSendingTyping) {
      _isSendingTyping = true;
      _channel?.sendBroadcastMessage(
        event: 'typing',
        payload: {'user_id': myId, 'user_name': myName, 'is_typing': true},
      );
    }

    _typingDebounce?.cancel();
    _typingDebounce = Timer(const Duration(seconds: 2), () {
      _isSendingTyping = false;
      _channel?.sendBroadcastMessage(
        event: 'typing',
        payload: {'user_id': myId, 'user_name': myName, 'is_typing': false},
      );
    });
  }

  Future<void> _sendMessage() async {
    final text = _messageController.text.trim();
    if (text.isEmpty) return;
    final userId = _supabase.auth.currentUser?.id;
    final userEmail = _supabase.auth.currentUser?.email;
    if (userId == null || userEmail == null) return;

    // Cancelar typing
    _typingDebounce?.cancel();
    _isSendingTyping = false;
    _channel?.sendBroadcastMessage(
      event: 'typing',
      payload: {'user_id': userId, 'is_typing': false},
    );

    _messageController.clear();

    // ── Optimistic update: mostrar el mensaje INMEDIATAMENTE ─────────────────
    final now = DateTime.now().toUtc().toIso8601String();
    final optimisticMsg = {
      'event_id': widget.eventId,
      'user_id': userId,
      'message': text,
      'user_email': userEmail,
      'created_at': now,
    };
    if (mounted) {
      setState(() => _messages.add(optimisticMsg));
      _scrollToBottom();
    }

    try {
      await _supabase.from('event_messages').insert({
        'event_id': widget.eventId,
        'user_id': userId,
        'message': text,
        'user_email': userEmail,
        'created_at': now,
      });
    } catch (e) {
      debugPrint('Error enviando: $e');
      if (mounted) {
        setState(() => _messages.remove(optimisticMsg));
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Error al enviar', style: TextStyle(fontFamily: 'Poppins')),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    }
  }

  /// Mensajes visibles, ocultando los de usuarios que bloqueaste.
  List<Map<String, dynamic>> get _visibleMessages => _messages
      .where((m) => !_blockedUserIds.contains(m['user_id'] as String? ?? ''))
      .toList();

  String _getUserInitial(String name) =>
      name.isNotEmpty ? name[0].toUpperCase() : '?';

  Color _getUserColor(String userId) {
    const colors = [
      Colors.blueAccent, Colors.purpleAccent, Colors.tealAccent,
      Colors.pinkAccent, Colors.amberAccent, Colors.indigoAccent,
    ];
    return colors[userId.hashCode.abs() % colors.length];
  }

  String _formatTime(DateTime dateTime) {
    final local = dateTime.toLocal();
    final h = local.hour.toString().padLeft(2, '0');
    final m = local.minute.toString().padLeft(2, '0');
    final timeStr = '$h:$m';

    final diff = DateTime.now().difference(local);
    String rel;
    if (diff.inSeconds < 30) {
      rel = 'ahora';
    } else if (diff.inMinutes < 1) {
      rel = 'hace ${diff.inSeconds} s';
    } else if (diff.inHours < 1) {
      rel = 'hace ${diff.inMinutes} min';
    } else if (diff.inDays < 1) {
      rel = 'hace ${diff.inHours} h';
    } else if (diff.inDays < 7) {
      rel = 'hace ${diff.inDays} d';
    } else {
      rel = '${local.day}/${local.month}/${local.year}';
    }

    return '$timeStr · $rel';
  }

  @override
  void dispose() {
    if (ChatNotificationsService.activeEventId == widget.eventId) {
      ChatNotificationsService.activeEventId = null;
    }
    _typingDebounce?.cancel();
    _dotsController.dispose();
    _channel?.unsubscribe();
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F0F0F),
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Chat del evento',
              style: TextStyle(
                fontFamily: 'Poppins', color: Colors.white,
                fontSize: 16, fontWeight: FontWeight.w400,
              ),
            ),
            Text(
              widget.eventTitle,
              style: const TextStyle(
                fontFamily: 'Poppins', color: Colors.greenAccent,
                fontSize: 14, fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        backgroundColor: Colors.black.withOpacity(0.8),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Colors.greenAccent))
          : Column(
              children: [
                Expanded(
                  child: _visibleMessages.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.chat_bubble_outline, size: 60, color: Colors.grey[700]),
                              const SizedBox(height: 16),
                              Text('No hay mensajes aún',
                                  style: TextStyle(fontFamily: 'Poppins', color: Colors.grey[500], fontSize: 16)),
                              const SizedBox(height: 8),
                              Text('¡Sé el primero en escribir!',
                                  style: TextStyle(fontFamily: 'Poppins', color: Colors.grey[600], fontSize: 14)),
                            ],
                          ),
                        )
                      : ListView.builder(
                          controller: _scrollController,
                          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                          itemCount: _visibleMessages.length,
                          itemBuilder: (context, i) =>
                              _buildMessage(_visibleMessages[i]),
                        ),
                ),
                // Indicador de escritura
                if (_typingUsers.isNotEmpty) _buildTypingIndicator(),
                // Input
                _buildInputBar(),
              ],
            ),
    );
  }

  Widget _buildMessage(Map<String, dynamic> message) {
    final userId = message['user_id'] as String? ?? '';
    final isMe = userId == _supabase.auth.currentUser?.id;
    final isCreator = userId == _eventCreatorId;
    final userName = _userNames[userId] ?? 'Usuario';
    final isUserPlus = _userIsPlus[userId] ?? false;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      child: Row(
        mainAxisAlignment: isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (!isMe) ...[
            _buildAvatar(userId, userName, isCreator, isMe: false),
            const SizedBox(width: 8),
          ],
          Flexible(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: isMe
                    ? const Color(0xFFFC4C02).withOpacity(0.18)
                    : Colors.grey[900],
                borderRadius: BorderRadius.circular(16).copyWith(
                  bottomLeft: isMe ? const Radius.circular(16) : const Radius.circular(4),
                  bottomRight: isMe ? const Radius.circular(4) : const Radius.circular(16),
                ),
                border: Border.all(
                  color: isMe
                      ? const Color(0xFFFC4C02).withOpacity(0.45)
                      : Colors.white10,
                ),
              ),
              child: Column(
                crossAxisAlignment: isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                children: [
                  if (!isMe) ...[
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          userName,
                          style: TextStyle(
                            fontFamily: 'Poppins',
                            color: _getUserColor(userId),
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        if (isUserPlus) ...[
                          const SizedBox(width: 4),
                          Builder(builder: (_) {
                            final pc = PlusPrefsService.medalVariants[
                                    PlusPrefsService.clampVariant(
                                        _userBadgeVariant[userId] ?? 0)]
                                .$2;
                            return Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 5, vertical: 1),
                              decoration: BoxDecoration(
                                color: pc.withOpacity(0.2),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                'PLUS',
                                style: TextStyle(
                                  fontFamily: 'Poppins',
                                  color: pc,
                                  fontSize: 8,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            );
                          }),
                        ],
                        if (isCreator) ...[
                          const SizedBox(width: 4),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                            decoration: BoxDecoration(
                              color: Colors.orange.withOpacity(0.2),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Text(
                              'Creador',
                              style: TextStyle(
                                fontFamily: 'Poppins', color: Colors.orange,
                                fontSize: 8, fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 3),
                  ],
                  Text(
                    message['message'] ?? '',
                    style: const TextStyle(
                      fontFamily: 'Poppins', color: Colors.white, fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _formatTime(DateTime.parse(message['created_at'])),
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      color: isMe ? const Color(0xFFFC4C02).withOpacity(0.6) : Colors.grey[600],
                      fontSize: 10,
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (isMe) ...[
            const SizedBox(width: 8),
            _buildAvatar(userId, userName, isCreator, isMe: true),
          ],
        ],
      ),
    );
  }

  Widget _buildAvatar(String userId, String userName, bool isCreator, {required bool isMe}) {
    final color = isMe ? const Color(0xFFFC4C02) : _getUserColor(userId);
    final avatarUrl = _userAvatars[userId];
    final isUserPlus = _userIsPlus[userId] ?? false;
    return GestureDetector(
      onTap: () => _showParticipantInfo(userId, userName, isCreator),
      child: Container(
        width: 34,
        height: 34,
        decoration: BoxDecoration(
          color: color.withOpacity(0.15),
          shape: BoxShape.circle,
          border: Border.all(
            color: isUserPlus
                ? Colors.amber
                : (isCreator ? Colors.orange : color.withOpacity(0.5)),
            width: (isUserPlus || isCreator) ? 2 : 1.5,
          ),
        ),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            ClipOval(
              child: (avatarUrl != null && avatarUrl.isNotEmpty)
                  ? CachedNetworkImage(
                      imageUrl: avatarUrl,
                      fit: BoxFit.cover,
                      width: 34,
                      height: 34,
                      fadeInDuration: Duration.zero,
                      placeholder: (_, _) => Center(
                        child: Text(
                          _getUserInitial(userName),
                          style: TextStyle(
                            fontFamily: 'Poppins', color: color,
                            fontWeight: FontWeight.w700, fontSize: 13,
                          ),
                        ),
                      ),
                      errorWidget: (_, _, _) => Center(
                        child: Text(
                          _getUserInitial(userName),
                          style: TextStyle(
                            fontFamily: 'Poppins', color: color,
                            fontWeight: FontWeight.w700, fontSize: 13,
                          ),
                        ),
                      ),
                    )
                  : Center(
                      child: Text(
                        _getUserInitial(userName),
                        style: TextStyle(
                          fontFamily: 'Poppins', color: color,
                          fontWeight: FontWeight.w700, fontSize: 13,
                        ),
                      ),
                    ),
            ),
            if (isCreator)
              Positioned(
                bottom: -2, right: -2,
                child: Container(
                  width: 14, height: 14,
                  decoration: BoxDecoration(
                    color: Colors.orange, shape: BoxShape.circle,
                    border: Border.all(color: const Color(0xFF0F0F0F), width: 1.5),
                  ),
                  child: const Icon(Icons.star, color: Colors.black, size: 8),
                ),
              )
            else if (isUserPlus)
              Positioned(
                bottom: -3, right: -3,
                child: PlusMedal(
                  size: 15,
                  variant: _userBadgeVariant[userId] ?? 0,
                  ringColor: const Color(0xFF0F0F0F),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildTypingIndicator() {
    final names = _typingUsers.values.toList();
    final label = names.length == 1
        ? '${names[0]} está escribiendo'
        : '${names.length} personas están escribiendo';

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
      child: Row(
        children: [
          _TypingDots(controller: _dotsController),
          const SizedBox(width: 8),
          Text(
            label,
            style: TextStyle(
              fontFamily: 'Poppins',
              color: Colors.grey[500],
              fontSize: 12,
              fontStyle: FontStyle.italic,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInputBar() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.85),
        border: const Border(top: BorderSide(color: Colors.white10)),
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _messageController,
              onChanged: _onTextChanged,
              style: const TextStyle(fontFamily: 'Poppins', color: Colors.white, fontSize: 14),
              decoration: InputDecoration(
                hintText: 'Escribe un mensaje...',
                hintStyle: TextStyle(fontFamily: 'Poppins', color: Colors.grey[600]),
                filled: true,
                fillColor: Colors.grey[900],
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(22),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              ),
              maxLines: null,
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => _sendMessage(),
            ),
          ),
          const SizedBox(width: 8),
          Container(
            decoration: const BoxDecoration(
              color: Color(0xFFFC4C02), shape: BoxShape.circle,
            ),
            child: IconButton(
              icon: const Icon(Icons.send, color: Colors.black, size: 20),
              onPressed: _sendMessage,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Diálogo de info del participante (con estrella de popularidad) ───────────

class _ParticipantInfoDialog extends StatefulWidget {
  final SupabaseClient supabase;
  final String userId;
  final String userName;
  final bool isCreator;
  final String? fallbackAvatarUrl;
  final bool fallbackIsPlus;
  final int fallbackBadgeVariant;
  final Color color;
  final String initial;
  final VoidCallback onBlock;
  final void Function(String reason) onReport;

  const _ParticipantInfoDialog({
    required this.supabase,
    required this.userId,
    required this.userName,
    required this.isCreator,
    required this.fallbackAvatarUrl,
    required this.fallbackIsPlus,
    required this.fallbackBadgeVariant,
    required this.color,
    required this.initial,
    required this.onBlock,
    required this.onReport,
  });

  @override
  State<_ParticipantInfoDialog> createState() => _ParticipantInfoDialogState();
}

class _ParticipantInfoDialogState extends State<_ParticipantInfoDialog> {
  static const _meses = [
    'enero', 'febrero', 'marzo', 'abril', 'mayo', 'junio',
    'julio', 'agosto', 'septiembre', 'octubre', 'noviembre', 'diciembre',
  ];

  bool _loading = true;
  String? _avatarUrl;
  bool _isPlus = false;
  int _badgeVariant = 0;
  String? _commune;
  double? _totalKm;
  DateTime? _joinedAt;
  int _starCount = 0;
  bool _starredByMe = false;
  bool _isSelf = false;

  @override
  void initState() {
    super.initState();
    _isSelf = widget.supabase.auth.currentUser?.id == widget.userId;
    _isPlus = widget.fallbackIsPlus;
    _badgeVariant = widget.fallbackBadgeVariant;
    _load();
  }

  Future<void> _load() async {
    try {
      final results = await Future.wait<dynamic>([
        widget.supabase
            .from('profiles')
            .select('avatar_url, commune, total_km, created_at, is_plus, plus_badge_variant')
            .eq('id', widget.userId)
            .maybeSingle(),
        widget.supabase
            .from('user_stars')
            .select('id')
            .eq('rated_user_id', widget.userId),
        if (!_isSelf)
          widget.supabase
              .from('user_stars')
              .select('id')
              .eq('rater_id', widget.supabase.auth.currentUser!.id)
              .eq('rated_user_id', widget.userId)
              .maybeSingle(),
      ]);

      final profile = results[0] as Map<String, dynamic>?;
      final stars = results[1] as List;
      final myStar = !_isSelf ? results[2] as Map<String, dynamic>? : null;

      if (!mounted) return;
      setState(() {
        _avatarUrl = profile?['avatar_url'] as String? ?? widget.fallbackAvatarUrl;
        _isPlus = profile?['is_plus'] as bool? ?? widget.fallbackIsPlus;
        _badgeVariant = (profile?['plus_badge_variant'] as num?)?.toInt() ??
            widget.fallbackBadgeVariant;
        _commune = profile?['commune'] as String?;
        _totalKm = (profile?['total_km'] as num?)?.toDouble();
        final createdAt = profile?['created_at'] as String?;
        _joinedAt = createdAt != null ? DateTime.tryParse(createdAt) : null;
        _starCount = stars.length;
        _starredByMe = myStar != null;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _toggleStar() async {
    final myId = widget.supabase.auth.currentUser?.id;
    if (myId == null || _isSelf) return;

    final wasStarred = _starredByMe;
    setState(() {
      _starredByMe = !wasStarred;
      _starCount += _starredByMe ? 1 : -1;
    });

    try {
      if (wasStarred) {
        await widget.supabase
            .from('user_stars')
            .delete()
            .eq('rater_id', myId)
            .eq('rated_user_id', widget.userId);
      } else {
        await widget.supabase.from('user_stars').insert({
          'rater_id': myId,
          'rated_user_id': widget.userId,
        });
      }
    } catch (_) {
      // Revierte si falló
      if (mounted) {
        setState(() {
          _starredByMe = wasStarred;
          _starCount += wasStarred ? 1 : -1;
        });
      }
    }
  }

  String _formatJoinDate(DateTime date) {
    final local = date.toLocal();
    return 'Se unió en ${_meses[local.month - 1]} ${local.year}';
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: const Color(0xFF161616),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    color: widget.color.withOpacity(0.15),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: _isPlus
                          ? Colors.amber
                          : (widget.isCreator ? Colors.orange : widget.color.withOpacity(0.6)),
                      width: (_isPlus || widget.isCreator) ? 2.5 : 1.5,
                    ),
                  ),
                  child: ClipOval(
                    child: (_avatarUrl != null && _avatarUrl!.isNotEmpty)
                        ? CachedNetworkImage(
                            imageUrl: _avatarUrl!,
                            fit: BoxFit.cover,
                            fadeInDuration: Duration.zero,
                            placeholder: (_, _) => Center(
                              child: Text(
                                widget.initial,
                                style: TextStyle(
                                  fontFamily: 'Poppins', color: widget.color,
                                  fontWeight: FontWeight.w700, fontSize: 28,
                                ),
                              ),
                            ),
                            errorWidget: (_, _, _) => Center(
                              child: Text(
                                widget.initial,
                                style: TextStyle(
                                  fontFamily: 'Poppins', color: widget.color,
                                  fontWeight: FontWeight.w700, fontSize: 28,
                                ),
                              ),
                            ),
                          )
                        : Center(
                            child: Text(
                              widget.initial,
                              style: TextStyle(
                                fontFamily: 'Poppins', color: widget.color,
                                fontWeight: FontWeight.w700, fontSize: 28,
                              ),
                            ),
                          ),
                  ),
                ),
                if (_isPlus)
                  Positioned(
                    bottom: -2,
                    right: -2,
                    child: PlusMedal(
                      size: 24,
                      variant: _badgeVariant,
                      ringColor: const Color(0xFF161616),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  widget.userName,
                  style: const TextStyle(
                    fontFamily: 'Poppins', color: Colors.white,
                    fontSize: 18, fontWeight: FontWeight.w700,
                  ),
                ),
                if (_isPlus) ...[
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.amber.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Text(
                      'PLUS',
                      style: TextStyle(
                        fontFamily: 'Poppins',
                        color: Colors.amber,
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
                if (widget.isCreator) ...[
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.orange.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Text(
                      'Creador',
                      style: TextStyle(
                        fontFamily: 'Poppins', color: Colors.orange,
                        fontSize: 10, fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ],
            ),
            if (_loading) ...[
              const SizedBox(height: 16),
              const SizedBox(
                width: 18, height: 18,
                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.greenAccent),
              ),
            ] else ...[
              if (_joinedAt != null) ...[
                const SizedBox(height: 8),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.emoji_events_outlined, size: 14, color: Colors.grey[500]),
                    const SizedBox(width: 4),
                    Text(
                      _formatJoinDate(_joinedAt!),
                      style: TextStyle(fontFamily: 'Poppins', color: Colors.grey[400], fontSize: 13),
                    ),
                  ],
                ),
              ],
              if (_commune != null && _commune!.isNotEmpty) ...[
                const SizedBox(height: 6),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.place_outlined, size: 14, color: Colors.grey[500]),
                    const SizedBox(width: 4),
                    Text(
                      _commune!,
                      style: TextStyle(fontFamily: 'Poppins', color: Colors.grey[400], fontSize: 13),
                    ),
                  ],
                ),
              ],
              if (_totalKm != null && _totalKm! > 0) ...[
                const SizedBox(height: 6),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.pedal_bike, size: 14, color: Colors.grey[500]),
                    const SizedBox(width: 4),
                    Text(
                      '${_totalKm!.toStringAsFixed(1)} km recorridos',
                      style: TextStyle(fontFamily: 'Poppins', color: Colors.grey[400], fontSize: 13),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 18),
              // ── Estrella de popularidad ──────────────────────────
              GestureDetector(
                onTap: _isSelf ? null : _toggleStar,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: _starredByMe
                        ? Colors.amber.withOpacity(0.15)
                        : Colors.white.withOpacity(0.05),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: _starredByMe
                          ? Colors.amber.withOpacity(0.5)
                          : Colors.white12,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        _starredByMe ? Icons.star_rounded : Icons.star_outline_rounded,
                        color: _starredByMe ? Colors.amber : Colors.grey[400],
                        size: 20,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        '$_starCount ${_starCount == 1 ? "estrella" : "estrellas"}',
                        style: TextStyle(
                          fontFamily: 'Poppins',
                          color: _starredByMe ? Colors.amber : Colors.grey[400],
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: TextButton.icon(
                onPressed: () {
                  Navigator.pop(context);
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => PublicProfilePage(userId: widget.userId)),
                  );
                },
                icon: const Icon(Icons.person_rounded, size: 16, color: Color(0xFF7CF0BC)),
                label: const Text(
                  'Ver perfil',
                  style: TextStyle(fontFamily: 'Poppins', color: Color(0xFF7CF0BC), fontSize: 12.5, fontWeight: FontWeight.w600),
                ),
                style: TextButton.styleFrom(
                  backgroundColor: const Color(0xFF7CF0BC).withOpacity(0.08),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  padding: const EdgeInsets.symmetric(vertical: 10),
                ),
              ),
            ),
            if (!_isSelf) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: TextButton.icon(
                      onPressed: () {
                        Navigator.pop(context);
                        widget.onBlock();
                      },
                      icon: const Icon(Icons.block, size: 16, color: Colors.orangeAccent),
                      label: const Text(
                        'Bloquear',
                        style: TextStyle(fontFamily: 'Poppins', color: Colors.orangeAccent, fontSize: 12),
                      ),
                      style: TextButton.styleFrom(
                        backgroundColor: Colors.orangeAccent.withOpacity(0.08),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        padding: const EdgeInsets.symmetric(vertical: 10),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextButton.icon(
                      onPressed: () {
                        Navigator.pop(context);
                        _showReportDialog(context);
                      },
                      icon: const Icon(Icons.flag_outlined, size: 16, color: Colors.redAccent),
                      label: const Text(
                        'Reportar',
                        style: TextStyle(fontFamily: 'Poppins', color: Colors.redAccent, fontSize: 12),
                      ),
                      style: TextButton.styleFrom(
                        backgroundColor: Colors.redAccent.withOpacity(0.08),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        padding: const EdgeInsets.symmetric(vertical: 10),
                      ),
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: TextButton(
                onPressed: () => Navigator.pop(context),
                style: TextButton.styleFrom(
                  backgroundColor: Colors.white.withOpacity(0.06),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
                child: const Text(
                  'Cerrar',
                  style: TextStyle(fontFamily: 'Poppins', color: Colors.white70, fontWeight: FontWeight.w600),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showReportDialog(BuildContext parentContext) {
    final reasonCtrl = TextEditingController();
    showDialog(
      context: parentContext,
      builder: (ctx) => Dialog(
        backgroundColor: const Color(0xFF161616),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Reportar a ${widget.userName}',
                style: const TextStyle(
                  fontFamily: 'Poppins', color: Colors.white,
                  fontSize: 16, fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                '¿Qué está pasando? Cuéntanos brevemente.',
                style: TextStyle(fontFamily: 'Poppins', color: Colors.white54, fontSize: 12),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: reasonCtrl,
                autofocus: true,
                maxLines: 3,
                style: const TextStyle(fontFamily: 'Poppins', color: Colors.white, fontSize: 14),
                decoration: InputDecoration(
                  hintText: 'Ej: mensajes ofensivos, acoso, spam...',
                  hintStyle: const TextStyle(fontFamily: 'Poppins', color: Colors.white30),
                  filled: true,
                  fillColor: Colors.white.withOpacity(0.05),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding: const EdgeInsets.all(12),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: TextButton(
                      onPressed: () => Navigator.pop(ctx),
                      style: TextButton.styleFrom(foregroundColor: Colors.white38),
                      child: const Text('Cancelar', style: TextStyle(fontFamily: 'Poppins')),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () {
                        final reason = reasonCtrl.text.trim();
                        if (reason.isEmpty) return;
                        Navigator.pop(ctx);
                        widget.onReport(reason);
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.redAccent,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        textStyle: const TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w700),
                      ),
                      child: const Text('Enviar'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Animación de tres puntos ──────────────────────────────────────────────────

class _TypingDots extends StatelessWidget {
  final AnimationController controller;
  const _TypingDots({required this.controller});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (_, _) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: List.generate(3, (i) {
            // Cada punto tiene un desfase de 0.2 en el ciclo
            final phase = (controller.value - i * 0.2).clamp(0.0, 1.0);
            final bounce = (phase < 0.5)
                ? phase * 2
                : (1.0 - phase) * 2;
            return Container(
              margin: const EdgeInsets.symmetric(horizontal: 2),
              width: 7,
              height: 7,
              decoration: BoxDecoration(
                color: Color.lerp(
                  Colors.grey[700], Colors.greenAccent, bounce,
                ),
                shape: BoxShape.circle,
              ),
              transform: Matrix4.translationValues(0, -4 * bounce, 0),
            );
          }),
        );
      },
    );
  }
}

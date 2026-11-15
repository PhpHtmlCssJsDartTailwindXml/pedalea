import 'dart:io';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../core/glass.dart';
import '../services/achievements_service.dart';
import 'achievements_page.dart';
import '../services/karma_service.dart';
import '../services/co2_service.dart';
import '../services/subscription_service.dart';
import '../services/cache_service.dart';
import '../services/connectivity_service.dart';
import 'dart:async';
import 'paywall_page.dart';
import 'manage_subscription_page.dart';
import 'plus_unlocked_page.dart';
import '../widgets/achievement_unlock_toast.dart';
import '../widgets/plus_medal.dart';
import '../widgets/rider_activity.dart';
import '../services/plus_prefs_service.dart';
import '../services/social_service.dart';
import 'public_profile_page.dart';
import 'follow_requests_page.dart';
import 'moments_page.dart';
import 'my_bikes_page.dart';
import '../services/bike_service.dart';
import '../services/alert_impact_service.dart';

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  final _supabase = Supabase.instance.client;
  final _usernameCtrl = TextEditingController();
  final _fullNameCtrl = TextEditingController();
  final _avatarUrlCtrl = TextEditingController();
  final _communeCtrl = TextEditingController();
  final _emergencyNameCtrl = TextEditingController();
  final _emergencyPhoneCtrl = TextEditingController();

  final _achievementsService = AchievementsService();
  final _karmaService = KarmaService();
  final ImagePicker _picker = ImagePicker();
  bool _uploadingAvatar = false;

  Map<String, dynamic>? _profile;
  List<Map<String, dynamic>> _achievements = [];
  bool _loading = true;
  bool _saving = false;
  bool _editing = false;
  int _karma = 0;

  bool _isOffline = !ConnectivityService.isOnline;
  StreamSubscription<bool>? _connectivitySub;

  int _followers = 0, _following = 0, _momentCount = 0, _pendingReqs = 0;
  List<Map<String, dynamic>> _myPosts = [];
  RiderActivity? _activity;
  AlertImpact _impact = AlertImpact.empty;

  @override
  void initState() {
    super.initState();
    _showCachedDataImmediately();
    _loadProfile();
    _loadSocial();
    BikeService.instance.load();
    AlertImpactService.myImpact().then((v) {
      if (mounted) setState(() => _impact = v);
    });
    PlusPrefsService.refresh(); // trae medalla/acento/estilo desde la BD
    _connectivitySub = ConnectivityService.stream.listen((online) {
      if (mounted) setState(() => _isOffline = !online);
    });
  }

  /// Muestra perfil y logros guardados en disco de inmediato, sin esperar
  /// red, mientras _loadProfile() los refresca por detrás. Evita el spinner
  /// en cada entrada al perfil cuando ya se cargó antes.
  void _showCachedDataImmediately() {
    final cachedProfile = CacheService.loadProfile();
    final cachedAchievements = CacheService.loadAchievements(ignoreExpiry: true);
    if (cachedProfile == null && cachedAchievements == null) return;
    setState(() {
      if (cachedProfile != null) {
        _profile = cachedProfile;
        _usernameCtrl.text = cachedProfile['username'] ?? '';
        _fullNameCtrl.text = cachedProfile['full_name'] ?? '';
        _avatarUrlCtrl.text = cachedProfile['avatar_url'] ?? '';
        _communeCtrl.text = cachedProfile['commune'] ?? '';
        _emergencyNameCtrl.text = cachedProfile['emergency_contact_name'] ?? '';
        _emergencyPhoneCtrl.text = cachedProfile['emergency_contact_phone'] ?? '';
        _loading = false;
      }
      if (cachedAchievements != null) _achievements = cachedAchievements;
    });
  }

  @override
  void dispose() {
    _usernameCtrl.dispose();
    _fullNameCtrl.dispose();
    _avatarUrlCtrl.dispose();
    _communeCtrl.dispose();
    _emergencyNameCtrl.dispose();
    _emergencyPhoneCtrl.dispose();
    _connectivitySub?.cancel();
    super.dispose();
  }

  User? get _user => _supabase.auth.currentUser;

  bool get _isGoogleUser {
    final identities = _user?.identities ?? [];
    return identities.any((id) => id.provider == 'google');
  }

  Future<void> _loadSocial() async {
    final uid = _user?.id;
    if (uid == null) return;
    RiderActivity.load(uid).then((a) {
      if (mounted) setState(() => _activity = a);
    });
    try {
      final results = await Future.wait([
        SocialService.instance.counts(uid),
        SocialService.instance.userPosts(uid),
        SocialService.instance.pendingRequestCount(),
      ]);
      if (!mounted) return;
      final c = results[0] as ({int followers, int following});
      setState(() {
        _followers = c.followers;
        _following = c.following;
        _myPosts = (results[1] as List).cast<Map<String, dynamic>>();
        _momentCount = _myPosts.length;
        _pendingReqs = results[2] as int;
      });
    } catch (_) {}
  }

  Future<void> _loadProfile() async {
    try {
      final userId = _user?.id;
      if (userId == null) return;

      // Perfil y karma son 2 consultas rápidas: con eso ya se puede mostrar
      // la pantalla. Los logros (checkAndUnlock) pueden implicar hasta ~14
      // consultas en serie contra Supabase, así que se cargan aparte en
      // segundo plano en vez de bloquear el spinner inicial.
      final results = await Future.wait<dynamic>([
        _supabase.from('profiles').select().eq('id', userId).maybeSingle(),
        _karmaService.getMyKarma(),
      ]);
      final data = results[0] as Map<String, dynamic>?;
      final karma = results[1] as int;

      if (data != null) await CacheService.saveProfile(data);

      if (mounted) {
        setState(() {
          _profile = data;
          _karma = karma;
          _usernameCtrl.text = data?['username'] ?? '';
          _fullNameCtrl.text = data?['full_name'] ?? '';
          _avatarUrlCtrl.text = data?['avatar_url'] ?? '';
          _communeCtrl.text = data?['commune'] ?? '';
          _emergencyNameCtrl.text = data?['emergency_contact_name'] ?? '';
          _emergencyPhoneCtrl.text = data?['emergency_contact_phone'] ?? '';
          _loading = false;
        });
        _loadAchievementsInBackground();
      }
    } catch (e) {
      // Sin internet u otro error de red: mostrar lo último que se guardó en
      // caché en vez de un error crudo — el perfil casi no cambia, así que
      // mostrar datos viejos es mucho mejor que no mostrar nada.
      final cached = CacheService.loadProfile();
      if (mounted) {
        setState(() {
          _loading = false;
          if (cached != null) {
            _profile = cached;
            _usernameCtrl.text = cached['username'] ?? '';
            _fullNameCtrl.text = cached['full_name'] ?? '';
            _avatarUrlCtrl.text = cached['avatar_url'] ?? '';
            _communeCtrl.text = cached['commune'] ?? '';
            _emergencyNameCtrl.text = cached['emergency_contact_name'] ?? '';
            _emergencyPhoneCtrl.text = cached['emergency_contact_phone'] ?? '';
          }
        });
        // El banner naranja de "sin conexión" (igual al del mapa) ya se
        // muestra solo via ConnectivityService — no hace falta un SnackBar
        // extra con el error crudo.
      }
    }
  }

  /// Chequea y trae los logros después de que el perfil ya se mostró, para
  /// no bloquear la pantalla con las ~14 consultas en serie que puede hacer
  /// checkAndUnlock(). Si el caché de logros sigue vigente (< 15 min), se
  /// omite por completo para no repetir esas consultas cada vez que se
  /// entra al perfil.
  Future<void> _loadAchievementsInBackground() async {
    if (CacheService.loadAchievements() != null) return;
    try {
      final newlyUnlockedIds = await _achievementsService.checkAndUnlock();
      final achievements = await _achievementsService.getAllWithStatus();
      await CacheService.saveAchievements(achievements);
      if (!mounted) return;
      setState(() => _achievements = achievements);
      if (newlyUnlockedIds.isNotEmpty) {
        final unlockedDetails = newlyUnlockedIds
            .map((id) => achievements.firstWhere(
                  (a) => a['id'] == id,
                  orElse: () => <String, dynamic>{},
                ))
            .where((a) => a.isNotEmpty)
            .map((a) => {
                  'icon': a['icon'] as String? ?? '🏅',
                  'title': a['title'] as String? ?? 'Nuevo logro',
                })
            .toList();
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) showAchievementUnlockedToasts(context, unlockedDetails);
        });
      }
    } catch (e) {
      debugPrint('Error cargando logros en segundo plano: $e');
    }
  }

  /// Abre la galería, sube la imagen elegida y la fija como foto de perfil.
  Future<void> _pickAndUploadAvatar() async {
    final userId = _user?.id;
    if (userId == null || _uploadingAvatar) return;
    try {
      final picked = await _picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 600,
        imageQuality: 80,
      );
      if (picked == null) return;
      setState(() => _uploadingAvatar = true);

      final file = File(picked.path);
      final path = 'avatars/${userId}_${DateTime.now().millisecondsSinceEpoch}.jpg';
      await _supabase.storage.from('alert-photos').upload(path, file);
      final url = _supabase.storage.from('alert-photos').getPublicUrl(path);

      await _supabase.from('profiles').upsert({'id': userId, 'avatar_url': url});
      await _loadProfile();
      if (mounted) _showSnack('Foto de perfil actualizada');
    } catch (e) {
      if (mounted) _showSnack('No se pudo subir la foto: $e', isError: true);
    } finally {
      if (mounted) setState(() => _uploadingAvatar = false);
    }
  }

  Future<void> _saveProfile() async {
    final userId = _user?.id;
    if (userId == null) return;
    setState(() => _saving = true);
    try {
      await _supabase.from('profiles').upsert({
        'id': userId,
        'username': _usernameCtrl.text.trim(),
        'full_name': _fullNameCtrl.text.trim(),
        'avatar_url': _avatarUrlCtrl.text.trim().isEmpty
            ? null
            : _avatarUrlCtrl.text.trim(),
        'commune': _communeCtrl.text.trim().isEmpty
            ? null
            : _communeCtrl.text.trim(),
        'emergency_contact_name': _emergencyNameCtrl.text.trim().isEmpty
            ? null
            : _emergencyNameCtrl.text.trim(),
        'emergency_contact_phone': _emergencyPhoneCtrl.text.trim().isEmpty
            ? null
            : _emergencyPhoneCtrl.text.trim(),
      });
      await _loadProfile();
      if (mounted) {
        setState(() => _editing = false);
        _showSnack('Perfil actualizado');
      }
    } catch (e) {
      if (mounted) _showSnack('Error guardando: $e', isError: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _showSnack(String msg, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg, style: const TextStyle(fontFamily: 'Poppins')),
        backgroundColor: isError ? Colors.redAccent : Colors.green,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        margin: const EdgeInsets.all(16),
      ),
    );
  }

  String _memberSince() {
    final raw = _profile?['created_at'] as String?;
    if (raw == null) return '—';
    final dt = DateTime.tryParse(raw);
    if (dt == null) return '—';
    const months = [
      'ene', 'feb', 'mar', 'abr', 'may', 'jun',
      'jul', 'ago', 'sep', 'oct', 'nov', 'dic',
    ];
    return '${dt.day} ${months[dt.month - 1]} ${dt.year}';
  }

  String _initials() {
    final full = (_profile?['full_name'] as String? ?? '').trim();
    final user = (_profile?['username'] as String? ?? '').trim();
    final name = full.isNotEmpty ? full : user;
    if (name.isEmpty) return '?';
    final parts = name.split(' ');
    if (parts.length >= 2) return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    return name[0].toUpperCase();
  }

  // ══════════════════════════════════════════════════════════════════════
  // Interfaz: lista limpia, mismo estilo que el menú lateral. Fondo sólido,
  // filas con íconos de línea, grupos con títulos chicos y sin tarjetas.
  // ══════════════════════════════════════════════════════════════════════
  static const _accent = Color(0xFF7CF0BC);
  static const _bg = Color(0xFF0F1117);
  static const _gold = Color(0xFFF2C94C);
  static const _warn = Color(0xFFFFB74D);

  static const _months = [
    'ene', 'feb', 'mar', 'abr', 'may', 'jun',
    'jul', 'ago', 'sep', 'oct', 'nov', 'dic',
  ];

  TextStyle _txt(double size,
          {FontWeight w = FontWeight.w500, Color? c, double? h}) =>
      TextStyle(
        fontFamily: 'Poppins',
        fontSize: size,
        fontWeight: w,
        color: c ?? Colors.white,
        height: h,
      );

  String get _displayName {
    final full = (_profile?['full_name'] as String? ?? '').trim();
    final user = (_profile?['username'] as String? ?? '').trim();
    if (full.isNotEmpty) return full;
    if (user.isNotEmpty) return user;
    return 'Ciclista Pedalea';
  }

  void _openMyMoments() {
    final uid = _user?.id;
    if (uid == null) return;
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => PublicProfilePage(userId: uid)),
    ).then((_) => _loadSocial());
  }

  void _cancelEdit() => setState(() {
        _editing = false;
        _usernameCtrl.text = _profile?['username'] ?? '';
        _fullNameCtrl.text = _profile?['full_name'] ?? '';
        _avatarUrlCtrl.text = _profile?['avatar_url'] ?? '';
        _communeCtrl.text = _profile?['commune'] ?? '';
        _emergencyNameCtrl.text = _profile?['emergency_contact_name'] ?? '';
        _emergencyPhoneCtrl.text = _profile?['emergency_contact_phone'] ?? '';
      });

  Future<void> _confirmLogout() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF161622),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        title: Text('Cerrar sesión', style: _txt(18, w: FontWeight.w700)),
        content: Text('¿Seguro que quieres salir de tu cuenta?',
            style: _txt(14, w: FontWeight.w400, c: Colors.white70)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Cancelar', style: _txt(14, c: Colors.white54)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Salir',
                style: _txt(14, w: FontWeight.w700, c: Colors.redAccent)),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await _supabase.auth.signOut();
    if (mounted) {
      Navigator.pushNamedAndRemoveUntil(context, '/', (route) => false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      body: Stack(
        children: [
          SafeArea(
            bottom: false,
            child: Column(
              children: [
                _topBar(),
                Expanded(
                  child: _loading
                      ? const Center(
                          child: CircularProgressIndicator(
                              color: _accent, strokeWidth: 2),
                        )
                      : LayoutBuilder(
                          builder: (context, c) {
                            final side = c.maxWidth > 640
                                ? (c.maxWidth - 560) / 2
                                : 0.0;
                            return ListView(
                              padding: EdgeInsets.fromLTRB(side, 0, side, 40),
                              children: [
                                _header(),
                                if (_editing)
                                  _buildEditForm()
                                else
                                  ..._sections(),
                              ],
                            );
                          },
                        ),
                ),
              ],
            ),
          ),
          if (_isOffline)
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: SafeArea(
                top: false,
                child: Container(
                  color: Colors.orange.shade800.withOpacity(0.95),
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.wifi_off_rounded,
                          color: Colors.white, size: 14),
                      const SizedBox(width: 6),
                      Text('Sin conexión · Mostrando datos en caché',
                          style: _txt(11, w: FontWeight.w600)),
                    ],
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
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 0),
      child: Row(
        children: [
          IconButton(
            tooltip: 'Volver',
            icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
            onPressed: () => Navigator.pop(context),
          ),
          Expanded(
            child: Text(
              _editing ? 'Editar perfil' : 'Perfil',
              style: _txt(17, w: FontWeight.w600),
            ),
          ),
          if (!_loading && !_editing)
            IconButton(
              tooltip: 'Editar perfil',
              icon: const Icon(Icons.edit_outlined, color: Colors.white70),
              onPressed: () => setState(() => _editing = true),
            ),
          if (_editing)
            TextButton(
              onPressed: _cancelEdit,
              child: Text('Cancelar', style: _txt(14, c: Colors.white54)),
            ),
        ],
      ),
    );
  }

  // ── Encabezado ─────────────────────────────────────────────────────────
  Widget _header() {
    final username = (_profile?['username'] as String? ?? '').trim();
    final commune = (_profile?['commune'] as String? ?? '').trim();
    final isPlus = _profile?['is_plus'] as bool? ?? false;
    final sub = [
      if (username.isNotEmpty) '@$username',
      if (commune.isNotEmpty) commune,
    ].join('  ·  ');

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 4),
      child: Column(
        children: [
          _buildAvatar(),
          const SizedBox(height: 14),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Flexible(
                child: Text(
                  _displayName,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: _txt(22, w: FontWeight.w700, h: 1.2),
                ),
              ),
              if (isPlus) ...[const SizedBox(width: 8), _plusChip()],
            ],
          ),
          if (sub.isNotEmpty) ...[
            const SizedBox(height: 3),
            Text(sub,
                textAlign: TextAlign.center,
                style: _txt(13, w: FontWeight.w400, c: Colors.white54)),
          ],
          if (!_editing) ...[
            const SizedBox(height: 20),
            Row(
              children: [
                _socialStat('$_momentCount', 'Momentos', _openMyMoments),
                _socialStat('$_followers', 'Seguidores', null),
                _socialStat('$_following', 'Siguiendo', null),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildAvatar() {
    final avatarUrl = _profile?['avatar_url'] as String?;
    final isPlus = _profile?['is_plus'] as bool? ?? false;
    return Semantics(
      button: true,
      label: 'Cambiar foto de perfil',
      child: GestureDetector(
        onTap: _uploadingAvatar ? null : _pickAndUploadAvatar,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Container(
              width: 100,
              height: 100,
              padding: const EdgeInsets.all(3),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: isPlus ? _gold : Colors.white24,
                  width: 1.6,
                ),
              ),
              child: ClipOval(
                child: _uploadingAvatar
                    ? Container(
                        color: Colors.black54,
                        child: const Center(
                          child: CircularProgressIndicator(
                              color: _accent, strokeWidth: 2.5),
                        ),
                      )
                    : (avatarUrl != null && avatarUrl.isNotEmpty
                        ? CachedNetworkImage(
                            imageUrl: avatarUrl,
                            fit: BoxFit.cover,
                            fadeInDuration: Duration.zero,
                            placeholder: (_, _) => _avatarFallback(),
                            errorWidget: (_, _, _) => _avatarFallback(),
                          )
                        : _avatarFallback()),
              ),
            ),
            Positioned(
              right: 0,
              bottom: 0,
              child: Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                  border: Border.all(color: _bg, width: 3),
                ),
                child: const Icon(Icons.photo_camera_outlined,
                    color: Colors.black, size: 15),
              ),
            ),
            if (isPlus)
              const Positioned(
                top: -2,
                left: -2,
                child: PlusMedal(size: 26, ringColor: _bg),
              ),
          ],
        ),
      ),
    );
  }

  Widget _avatarFallback() {
    return Container(
      color: Colors.white.withOpacity(0.08),
      child: Center(
        child: Text(_initials(),
            style: _txt(32, w: FontWeight.w600, c: Colors.white70)),
      ),
    );
  }

  Widget _plusChip() {
    return ValueListenableBuilder<int>(
      valueListenable: PlusPrefsService.medalVariant,
      builder: (context, variant, _) {
        final c = PlusPrefsService.medalVariants[
                variant.clamp(0, PlusPrefsService.medalVariants.length - 1)]
            .$2;
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: c.withOpacity(0.7)),
          ),
          child: Text('PLUS',
              style: _txt(10, w: FontWeight.w700, c: c)
                  .copyWith(letterSpacing: 0.8)),
        );
      },
    );
  }

  Widget _socialStat(String value, String label, VoidCallback? onTap) {
    return Expanded(
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Column(
            children: [
              Text(value, style: _txt(19, w: FontWeight.w700, h: 1.1)),
              const SizedBox(height: 2),
              Text(label,
                  style: _txt(12, w: FontWeight.w400, c: Colors.white54)),
            ],
          ),
        ),
      ),
    );
  }

  // ── Piezas de la lista ─────────────────────────────────────────────────
  Widget _group(String text, {String? action, VoidCallback? onAction}) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 26, 12, 6),
      child: Row(
        children: [
          Expanded(
            child: Text(
              text,
              style: _txt(11, w: FontWeight.w600, c: Colors.white38)
                  .copyWith(letterSpacing: 1.4),
            ),
          ),
          if (action != null)
            TextButton(
              onPressed: onAction,
              style: TextButton.styleFrom(
                minimumSize: const Size(44, 32),
                padding: const EdgeInsets.symmetric(horizontal: 12),
              ),
              child: Text(action,
                  style: _txt(12.5, w: FontWeight.w600, c: _accent)),
            ),
        ],
      ),
    );
  }

  Widget _line() => Padding(
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
        child: Container(height: 1, color: Colors.white.withOpacity(0.06)),
      );

  /// Fila de lista: ícono, título, ayuda opcional y algo a la derecha.
  Widget _row({
    required IconData icon,
    required String label,
    String? hint,
    String? value,
    Color? color,
    Color? valueColor,
    int badge = 0,
    Widget? leading,
    VoidCallback? onTap,
  }) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 12, 20, 12),
        child: Row(
          children: [
            leading ?? Icon(icon, color: color ?? Colors.white70, size: 22),
            const SizedBox(width: 18),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: _txt(15, c: color ?? Colors.white)),
                  if (hint != null)
                    Text(hint,
                        style: _txt(11.5,
                            w: FontWeight.w400, c: Colors.white38, h: 1.3)),
                ],
              ),
            ),
            if (value != null)
              Flexible(
                child: Padding(
                  padding: const EdgeInsets.only(left: 12),
                  child: Text(
                    value,
                    textAlign: TextAlign.end,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: _txt(14,
                        w: FontWeight.w400, c: valueColor ?? Colors.white60),
                  ),
                ),
              ),
            if (badge > 0)
              Container(
                margin: const EdgeInsets.only(left: 8),
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: _accent,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(badge > 9 ? '9+' : '$badge',
                    style: _txt(11, w: FontWeight.w700, c: Colors.black)),
              ),
            if (onTap != null && value == null)
              const Padding(
                padding: EdgeInsets.only(left: 6),
                child: Icon(Icons.chevron_right_rounded,
                    color: Colors.white24, size: 22),
              ),
          ],
        ),
      ),
    );
  }

  // ── Secciones ──────────────────────────────────────────────────────────
  List<Widget> _sections() {
    final isPlusLive = SubscriptionService.instance.isPlus.value;
    final emergencyName =
        (_profile?['emergency_contact_name'] as String? ?? '').trim();
    final emergencyPhone =
        (_profile?['emergency_contact_phone'] as String? ?? '').trim();
    final hasEmergency = emergencyName.isNotEmpty && emergencyPhone.isNotEmpty;

    return [
      _line(),
      _statsStrip(),
      if (_impact.headline != null)
        _row(
          icon: Icons.volunteer_activism_outlined,
          color: _accent,
          label: _impact.headline!,
          hint: _impact.week > 0
              ? '${_impact.week} esta semana · vieron tus alertas'
              : 'Vieron tus alertas al pasar cerca o al abrirlas',
        ),
      _line(),

      _group('ACTIVIDAD'),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: RiderActivityCard(data: _activity, accent: _accent),
      ),

      _group('MIS BICIS',
          action: BikeService.instance.bikes.value.isEmpty ? null : 'Ver todas',
          onAction: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const MyBikesPage()),
              )),
      _bikesList(),

      _group('MOMENTOS',
          action: _myPosts.isEmpty ? null : 'Ver todos',
          onAction: _openMyMoments),
      _momentsGrid(),

      if (_achievements.isNotEmpty) ...[
        _group(
          'LOGROS · ${_achievements.where((a) => a['unlocked'] == true).length} de ${_achievements.length}',
          action: 'Ver todos',
          onAction: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const AchievementsPage()),
          ),
        ),
        _achievementsStrip(),
      ],
      _line(),

      _group('COMUNIDAD'),
      _row(
        icon: Icons.auto_awesome_outlined,
        label: 'Ver el feed de Momentos',
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const MomentsPage()),
        ).then((_) => _loadSocial()),
      ),
      _row(
        icon: Icons.person_add_alt_outlined,
        label: 'Solicitudes de seguimiento',
        badge: _pendingReqs,
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const FollowRequestsPage()),
        ).then((_) => _loadSocial()),
      ),
      _line(),

      _group('PEDALEA PLUS'),
      _row(
        icon: Icons.workspace_premium_outlined,
        color: _gold,
        label: isPlusLive ? 'Pedalea Plus activo' : 'Hazte Pedalea Plus',
        hint: isPlusLive
            ? 'Gestiona tu suscripción'
            : 'Estadísticas avanzadas, eventos ilimitados y más',
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => isPlusLive
                ? const ManageSubscriptionPage()
                : const PaywallPage(),
          ),
        ),
      ),
      _buildMedalPicker(isPlusLive),
      _line(),

      _group('INFORMACIÓN'),
      _row(
          icon: Icons.alternate_email_rounded,
          label: 'Usuario',
          value: (_profile?['username'] as String? ?? '').isNotEmpty
              ? _profile!['username']
              : '—'),
      _row(
          icon: Icons.badge_outlined,
          label: 'Nombre',
          value: (_profile?['full_name'] as String? ?? '').isNotEmpty
              ? _profile!['full_name']
              : '—'),
      _row(
          icon: Icons.location_city_outlined,
          label: 'Comuna',
          value: (_profile?['commune'] as String? ?? '').isNotEmpty
              ? _profile!['commune']
              : '—'),
      _row(
          icon: Icons.calendar_today_outlined,
          label: 'Miembro desde',
          value: _memberSince()),
      _line(),

      _group('CONTACTO DE EMERGENCIA'),
      if (hasEmergency) ...[
        _row(
            icon: Icons.contact_emergency_outlined,
            label: 'Nombre',
            value: emergencyName),
        _row(icon: Icons.phone_outlined, label: 'Teléfono', value: emergencyPhone),
      ] else
        _row(
          icon: Icons.warning_amber_rounded,
          color: _warn,
          label: 'Agrega un contacto de emergencia',
          hint: 'Se le avisa por SMS si la app detecta una caída',
          onTap: () => setState(() => _editing = true),
        ),
      if (hasEmergency)
        Padding(
          padding: const EdgeInsets.fromLTRB(64, 0, 24, 4),
          child: Text('Se le avisa por SMS si la app detecta una caída.',
              style: _txt(11.5, w: FontWeight.w400, c: Colors.white38)),
        ),
      _line(),

      _group('CUENTA'),
      _row(
        icon: Icons.mail_outline_rounded,
        leading: _isGoogleUser ? const _GoogleIcon(size: 20) : null,
        label: 'Correo',
        value: _user?.email ?? '—',
      ),
      _row(
        icon: Icons.login_outlined,
        label: 'Acceso',
        value: _isGoogleUser ? 'Google' : 'Correo y contraseña',
      ),
      _row(
        icon: Icons.verified_outlined,
        label: 'Estado',
        value: _user?.emailConfirmedAt != null ? 'Verificado' : 'Sin verificar',
        valueColor: _user?.emailConfirmedAt != null ? _accent : _warn,
      ),
      _row(
        icon: Icons.logout_rounded,
        color: Colors.redAccent.shade100,
        label: 'Cerrar sesión',
        onTap: _confirmLogout,
      ),
    ];
  }

  /// Tres cifras en grande: km, CO₂ y nivel de karma.
  Widget _statsStrip() {
    final totalKm = (_profile?['total_km'] as num?)?.toDouble() ?? 0.0;
    final co2Kg = Co2Service.savedKg(totalKm);
    final level = KarmaService.getLevel(_karma);
    final kmText = totalKm >= 100
        ? totalKm.toStringAsFixed(0)
        : totalKm.toStringAsFixed(1);

    Widget cell(String value, String unit, String label, {VoidCallback? onTap}) {
      return Expanded(
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Column(
              children: [
                Text.rich(
                  TextSpan(children: [
                    TextSpan(text: value),
                    if (unit.isNotEmpty)
                      TextSpan(
                          text: ' $unit',
                          style: _txt(13, w: FontWeight.w500, c: Colors.white54)),
                  ]),
                  maxLines: 1,
                  style: _txt(22, w: FontWeight.w700, h: 1.1),
                ),
                const SizedBox(height: 3),
                Text(label,
                    style: _txt(11.5, w: FontWeight.w400, c: Colors.white54)),
              ],
            ),
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
      child: Row(
        children: [
          cell(kmText, 'km', 'pedaleados'),
          cell(Co2Service.format(co2Kg), '', 'CO₂ ahorrado'),
          cell('${level.emoji} ${level.title}', '', '$_karma karma',
              onTap: _showKarmaInfo),
        ],
      ),
    );
  }

  void _showKarmaInfo() {
    final level = KarmaService.getLevel(_karma);
    final progress = KarmaService.getLevelProgress(_karma);
    final idx = KarmaService.levels.indexOf(level);
    final next = idx < KarmaService.levels.length - 1
        ? KarmaService.levels[idx + 1]
        : null;
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF161622),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('${level.emoji}  ${level.title}',
                  style: _txt(20, w: FontWeight.w700)),
              const SizedBox(height: 4),
              Text('$_karma karma',
                  style: _txt(14, w: FontWeight.w400, c: Colors.white60)),
              const SizedBox(height: 14),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: progress,
                  minHeight: 6,
                  backgroundColor: Colors.white10,
                  valueColor: const AlwaysStoppedAnimation(_accent),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                next != null
                    ? 'Próximo nivel: ${next.emoji} ${next.title} (${next.minKarma} karma)'
                    : 'Llegaste al nivel máximo',
                style: _txt(12.5, w: FontWeight.w400, c: Colors.white54),
              ),
              const SizedBox(height: 16),
              Text(
                'El karma sube cuando otros ciclistas votan a favor de tus reportes y baja con los votos en contra.',
                style: _txt(13, w: FontWeight.w400, c: Colors.white70, h: 1.45),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _bikesList() {
    return ValueListenableBuilder<List<Bike>>(
      valueListenable: BikeService.instance.bikes,
      builder: (context, bikes, _) {
        if (bikes.isEmpty) {
          return _row(
            icon: Icons.pedal_bike_outlined,
            color: _accent,
            label: 'Registra tu bici',
            hint: 'Sus km y avisos de mantención',
            onTap: () => showBikeEditor(context),
          );
        }
        return Column(
          children: [
            for (final b in bikes.take(3))
              _row(
                icon: Icons.pedal_bike_outlined,
                leading: _bikeThumb(b),
                label: b.name,
                hint: _bikeHint(b),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => BikeDetailPage(bikeId: b.id)),
                ),
              ),
          ],
        );
      },
    );
  }

  String _bikeHint(Bike b) {
    final odo = b.odometerKm;
    final km = odo >= 100 ? odo.toStringAsFixed(0) : odo.toStringAsFixed(1);
    final due = b.dueMaintenance;
    final state = due.isEmpty
        ? 'mantención al día'
        : 'toca: ${due.first.kind.label.toLowerCase()}';
    return '${b.isActive ? 'Activa · ' : ''}$km km · $state';
  }

  Widget _bikeThumb(Bike b) {
    final url = b.photoUrl ?? '';
    return ClipOval(
      child: SizedBox(
        width: 26,
        height: 26,
        child: url.isNotEmpty
            ? CachedNetworkImage(imageUrl: url, fit: BoxFit.cover)
            : Container(
                color: Colors.white.withOpacity(0.08),
                alignment: Alignment.center,
                child: Text(b.type.emoji, style: const TextStyle(fontSize: 13)),
              ),
      ),
    );
  }

  Widget _momentsGrid() {
    if (_myPosts.isEmpty) {
      return _row(
        icon: Icons.add_a_photo_outlined,
        color: _accent,
        label: 'Comparte tu primer momento',
        hint: 'Una foto de tu ruta para la comunidad',
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const MomentsPage()),
        ).then((_) => _loadSocial()),
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: GridView.count(
        crossAxisCount: 3,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        mainAxisSpacing: 3,
        crossAxisSpacing: 3,
        children: [
          for (final p in _myPosts.take(6))
            GestureDetector(
              onTap: _openMyMoments,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: CachedNetworkImage(
                  imageUrl: p['image_url'] as String,
                  fit: BoxFit.cover,
                  placeholder: (_, _) => Container(color: Colors.white10),
                  errorWidget: (_, _, _) => Container(color: Colors.white10),
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// Logros en una fila deslizable: primero los desbloqueados.
  Widget _achievementsStrip() {
    final unlocked = _achievements.where((a) => a['unlocked'] == true);
    final locked = _achievements.where((a) => a['unlocked'] != true);
    final items = [...unlocked, ...locked].take(12).toList();
    return SizedBox(
      height: 96,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        itemCount: items.length,
        separatorBuilder: (_, _) => const SizedBox(width: 6),
        itemBuilder: (_, i) {
          final a = items[i];
          final on = a['unlocked'] == true;
          return GestureDetector(
            onTap: () => _showAchievementDetail(a, on),
            child: SizedBox(
              width: 70,
              child: Column(
                children: [
                  Container(
                    width: 54,
                    height: 54,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white.withOpacity(on ? 0.08 : 0.03),
                      border: Border.all(
                        color: on
                            ? _accent.withOpacity(0.5)
                            : Colors.white.withOpacity(0.06),
                      ),
                    ),
                    child: Opacity(
                      opacity: on ? 1 : 0.3,
                      child: Text(a['icon'] as String? ?? '🏅',
                          style: const TextStyle(fontSize: 24)),
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    a['title'] as String? ?? '',
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: _txt(10,
                        w: FontWeight.w500,
                        c: on ? Colors.white70 : Colors.white30,
                        h: 1.15),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  /// Variante de la medalla Plus. Si no es Plus se ve bloqueada.
  Widget _buildMedalPicker(bool isPlus) {
    return ValueListenableBuilder<int>(
      valueListenable: PlusPrefsService.medalVariant,
      builder: (context, sel, _) {
        void openPaywall() => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => const PaywallPage(
                  reason:
                      'Personaliza tu medalla y lúcela en el perfil y el chat con Pedalea Plus.',
                ),
              ),
            );
        return Padding(
          padding: const EdgeInsets.fromLTRB(64, 2, 20, 6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                isPlus
                    ? 'Tu medalla: elige el brillo con el que te ven'
                    : 'Medalla Plus: disponible con la suscripción',
                style: _txt(12, w: FontWeight.w400, c: Colors.white54),
              ),
              const SizedBox(height: 10),
              Opacity(
                opacity: isPlus ? 1 : 0.4,
                child: Wrap(
                  spacing: 14,
                  runSpacing: 10,
                  children: [
                    for (int i = 0;
                        i < PlusPrefsService.medalVariants.length;
                        i++)
                      GestureDetector(
                        onTap: isPlus
                            ? () => PlusPrefsService.setMedalVariant(i)
                            : openPaywall,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              padding: const EdgeInsets.all(3),
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: (isPlus && sel == i)
                                      ? Colors.white
                                      : Colors.transparent,
                                  width: 1.6,
                                ),
                              ),
                              child: PlusMedal(
                                  size: 30, variant: i, ringColor: _bg),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              PlusPrefsService.medalVariants[i].$1,
                              style: _txt(10,
                                  w: FontWeight.w500,
                                  c: (isPlus && sel == i)
                                      ? Colors.white
                                      : Colors.white38),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  // ── Edición ────────────────────────────────────────────────────────────
  InputDecoration _input(String label, IconData icon,
      {String? helper, String? hint}) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      helperText: helper,
      labelStyle: _txt(13.5, w: FontWeight.w400, c: Colors.white54),
      hintStyle: _txt(14, w: FontWeight.w400, c: Colors.white24),
      helperStyle: _txt(11.5, w: FontWeight.w400, c: Colors.white38),
      prefixIcon: Icon(icon, color: Colors.white54, size: 20),
      filled: true,
      fillColor: Colors.white.withOpacity(0.05),
      contentPadding: const EdgeInsets.symmetric(vertical: 16, horizontal: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: _accent, width: 1.3),
      ),
    );
  }

  Widget _field(TextEditingController c, String label, IconData icon,
      {String? helper, String? hint, TextInputType? keyboard}) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
      child: TextField(
        controller: c,
        keyboardType: keyboard,
        cursorColor: _accent,
        style: _txt(15, w: FontWeight.w400),
        decoration: _input(label, icon, helper: helper, hint: hint),
      ),
    );
  }

  Widget _buildEditForm() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 4, 24, 8),
          child: Text('Toca tu foto para cambiarla.',
              textAlign: TextAlign.center,
              style: _txt(12, w: FontWeight.w400, c: Colors.white38)),
        ),
        _group('TUS DATOS'),
        _field(_usernameCtrl, 'Nombre de usuario', Icons.alternate_email_rounded),
        _field(_fullNameCtrl, 'Nombre completo', Icons.badge_outlined),
        _field(_communeCtrl, 'Comuna (opcional)', Icons.location_city_outlined,
            hint: 'Ej: Maipú, Providencia, Ñuñoa'),
        _group('CONTACTO DE EMERGENCIA'),
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 12),
          child: Text(
            'Se le avisa por SMS con tu ubicación si la app detecta una caída.',
            style: _txt(12, w: FontWeight.w400, c: Colors.white38),
          ),
        ),
        _field(_emergencyNameCtrl, 'Nombre del contacto',
            Icons.contact_emergency_outlined),
        _field(_emergencyPhoneCtrl, 'Teléfono', Icons.phone_outlined,
            hint: '+56912345678', keyboard: TextInputType.phone),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
          child: SizedBox(
            height: 52,
            child: ElevatedButton(
              onPressed: _saving ? null : _saveProfile,
              style: ElevatedButton.styleFrom(
                backgroundColor: _accent,
                foregroundColor: Colors.black,
                elevation: 0,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
              ),
              child: _saving
                  ? const SizedBox(
                      height: 22,
                      width: 22,
                      child: CircularProgressIndicator(
                          color: Colors.black, strokeWidth: 2),
                    )
                  : Text('Guardar cambios',
                      style: _txt(15, w: FontWeight.w700, c: Colors.black)),
            ),
          ),
        ),
      ],
    );
  }

  void _showAchievementDetail(Map<String, dynamic> achievement, bool unlocked) {
    final icon = achievement['icon'] as String? ?? '🏅';
    final title = achievement['title'] as String? ?? '';
    final description = achievement['description'] as String? ?? '';
    final unlockedAt = achievement['unlocked_at'] as String?;
    String dateStr = '';
    if (unlockedAt != null) {
      final dt = DateTime.tryParse(unlockedAt)?.toLocal();
      if (dt != null) {
        dateStr = '${dt.day} ${_months[dt.month - 1]} ${dt.year}';
      }
    }
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF161622),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Opacity(
                opacity: unlocked ? 1 : 0.35,
                child: Text(icon, style: const TextStyle(fontSize: 52)),
              ),
              const SizedBox(height: 12),
              Text(title,
                  textAlign: TextAlign.center,
                  style: _txt(20,
                      w: FontWeight.w700,
                      c: unlocked ? Colors.white : Colors.white54)),
              const SizedBox(height: 6),
              Text(description,
                  textAlign: TextAlign.center,
                  style: _txt(14, w: FontWeight.w400, c: Colors.white60)),
              const SizedBox(height: 14),
              Text(
                unlocked
                    ? (dateStr.isNotEmpty
                        ? 'Desbloqueado el $dateStr'
                        : 'Desbloqueado')
                    : 'Aún no desbloqueado',
                style: _txt(12.5,
                    w: FontWeight.w600,
                    c: unlocked ? _accent : Colors.white30),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _GoogleIcon extends StatelessWidget {
  final double size;
  const _GoogleIcon({this.size = 18});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(painter: _GooglePainter()),
    );
  }
}

class _GooglePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;
    canvas.drawCircle(center, radius, Paint()..color = Colors.white);
    const sweepAngle = 2 * 3.14159265 / 4;
    final colors = [Colors.blue, Colors.red, Colors.yellow, Colors.green];
    for (int i = 0; i < 4; i++) {
      final paint = Paint()
        ..color = colors[i]
        ..style = PaintingStyle.stroke
        ..strokeWidth = size.width * 0.28
        ..strokeCap = StrokeCap.butt;
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius * 0.62),
        -3.14159265 / 2 + sweepAngle * i,
        sweepAngle * 0.97,
        false,
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

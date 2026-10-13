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

  @override
  void initState() {
    super.initState();
    _showCachedDataImmediately();
    _loadProfile();
    _loadSocial();
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      extendBodyBehindAppBar: true,
      body: Stack(
        children: [
          Container(
        decoration: kPageGradient,
        child: Column(
          children: [
            // AppBar glass
            SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Row(
                  children: [
                    GestureDetector(
                      onTap: () => Navigator.pop(context),
                      child: Container(
                        width: 40,
                        height: 40,
                        decoration: glassDecoration(radius: 12),
                        child: const Icon(
                          Icons.arrow_back_ios_new,
                          color: Colors.white,
                          size: 18,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    const Text(
                      'Mi Perfil',
                      style: TextStyle(
                        fontFamily: 'Poppins',
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                        fontSize: 18,
                      ),
                    ),
                    const Spacer(),
                    if (!_loading && !_editing)
                      GestureDetector(
                        onTap: () => setState(() => _editing = true),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 8,
                          ),
                          decoration: glassDecoration(
                            radius: 12,
                            tint: Colors.greenAccent,
                            opacity: 0.1,
                            borderOpacity: 0.2,
                          ),
                          child: const Row(
                            children: [
                              Icon(
                                Icons.edit_outlined,
                                color: Colors.greenAccent,
                                size: 16,
                              ),
                              SizedBox(width: 6),
                              Text(
                                'Editar',
                                style: TextStyle(
                                  fontFamily: 'Poppins',
                                  color: Colors.greenAccent,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    if (_editing)
                      TextButton(
                        onPressed: () => setState(() {
                          _editing = false;
                          _usernameCtrl.text = _profile?['username'] ?? '';
                          _fullNameCtrl.text = _profile?['full_name'] ?? '';
                          _avatarUrlCtrl.text = _profile?['avatar_url'] ?? '';
                          _communeCtrl.text = _profile?['commune'] ?? '';
                          _emergencyNameCtrl.text =
                              _profile?['emergency_contact_name'] ?? '';
                          _emergencyPhoneCtrl.text =
                              _profile?['emergency_contact_phone'] ?? '';
                        }),
                        child: const Text(
                          'Cancelar',
                          style: TextStyle(
                            fontFamily: 'Poppins',
                            color: Colors.white38,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),

            Expanded(
              child: _loading
                  ? const Center(
                      child: CircularProgressIndicator(
                        color: Colors.greenAccent,
                        strokeWidth: 2,
                      ),
                    )
                  : LayoutBuilder(
                      builder: (context, constraints) {
                        final isWide = constraints.maxWidth > 600;
                        return SingleChildScrollView(
                          padding: EdgeInsets.symmetric(
                            horizontal: isWide
                                ? constraints.maxWidth * 0.15
                                : 20,
                            vertical: 24,
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              _buildHero(),
                              const SizedBox(height: 14),
                              if (_editing)
                                _buildEditForm()
                              else ...[
                                _buildQuickActions(),
                                const SizedBox(height: 24),
                                activitySectionLabel('ACTIVIDAD', _accent),
                                const SizedBox(height: 10),
                                SizedBox(
                                  width: double.infinity,
                                  child: RiderActivityCard(
                                      data: _activity, accent: _accent),
                                ),
                                const SizedBox(height: 12),
                                _buildStatsRow(),
                                const SizedBox(height: 24),
                                _buildMomentsPreview(),
                                const SizedBox(height: 14),
                                _buildPlusCard(),
                                if (_achievements.isNotEmpty) ...[
                                  const SizedBox(height: 28),
                                  _buildAchievements(),
                                ],
                                const SizedBox(height: 28),
                                _buildProfileInfo(),
                              ],
                            ],
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
          ),
          if (_isOffline)
            Positioned(
              bottom: 0, left: 0, right: 0,
              child: SafeArea(
                top: false,
                child: Container(
                  color: Colors.orange.shade800.withOpacity(0.95),
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.wifi_off_rounded, color: Colors.white, size: 14),
                      SizedBox(width: 6),
                      Text(
                        'Sin conexión · Mostrando datos en caché',
                        style: TextStyle(
                          fontFamily: 'Poppins',
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  static const _accent = Color(0xFF7CF0BC);
  static const _heroMid = Color(0xFF1E5C41);

  /// Tarjeta principal: foto, nombre, Plus, correo y contadores sociales.
  Widget _buildHero() {
    final fullName = (_profile?['full_name'] as String? ?? '').trim();
    final username = (_profile?['username'] as String? ?? '').trim();
    final isPlus = _profile?['is_plus'] as bool? ?? false;
    final displayName = fullName.isNotEmpty
        ? fullName
        : (username.isNotEmpty ? username : 'Ciclista Pedalea');
    final uid = _user?.id;

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(26),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF2F8F63), _heroMid, Color(0xFF153F2E)],
          stops: [0.0, 0.55, 1.0],
        ),
        border: Border.all(color: _accent.withOpacity(0.22)),
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
            // Círculos decorativos (como una rueda).
            Positioned(
              right: -40,
              top: -40,
              child: Container(
                width: 150,
                height: 150,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: Colors.white.withOpacity(0.07),
                    width: 16,
                  ),
                ),
              ),
            ),
            Positioned(
              left: -30,
              bottom: -40,
              child: Container(
                width: 90,
                height: 90,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withOpacity(0.04),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 20, 18, 14),
              child: Column(
                children: [
                  Row(
                    children: [
                      _buildAvatar(),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              displayName,
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
                            const SizedBox(height: 6),
                            Wrap(
                              spacing: 6,
                              runSpacing: 4,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              children: [
                                if (isPlus) _plusChip(),
                                if (username.isNotEmpty)
                                  Text(
                                    '@$username',
                                    style: TextStyle(
                                      fontFamily: 'Poppins',
                                      color: Colors.white.withOpacity(0.7),
                                      fontSize: 13,
                                    ),
                                  ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            Row(
                              children: [
                                if (_isGoogleUser) ...[
                                  const _GoogleIcon(size: 12),
                                  const SizedBox(width: 5),
                                ] else ...[
                                  Icon(Icons.email_outlined,
                                      color: Colors.white.withOpacity(0.5),
                                      size: 13),
                                  const SizedBox(width: 5),
                                ],
                                Flexible(
                                  child: Text(
                                    _user?.email ?? '—',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontFamily: 'Poppins',
                                      color: Colors.white.withOpacity(0.55),
                                      fontSize: 11.5,
                                    ),
                                  ),
                                ),
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
                        _socialStat('$_momentCount', 'Momentos', () {
                          if (uid != null) {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => PublicProfilePage(userId: uid),
                              ),
                            ).then((_) => _loadSocial());
                          }
                        }),
                        _statDivider(),
                        _socialStat('$_followers', 'Seguidores', null),
                        _statDivider(),
                        _socialStat('$_following', 'Siguiendo', null),
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

  Widget _plusChip() {
    return ValueListenableBuilder<int>(
      valueListenable: PlusPrefsService.medalVariant,
      builder: (context, variant, _) {
        final c = PlusPrefsService.medalVariants[
                variant.clamp(0, PlusPrefsService.medalVariants.length - 1)]
            .$2;
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [c.withOpacity(0.35), c.withOpacity(0.15)],
            ),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: c.withOpacity(0.55)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.workspace_premium_rounded, color: c, size: 12),
              const SizedBox(width: 3),
              Text(
                'PLUS',
                style: TextStyle(
                  fontFamily: 'Poppins',
                  color: c,
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.6,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _statDivider() => Container(
        width: 1,
        height: 28,
        color: Colors.white.withOpacity(0.12),
      );

  Widget _buildAvatar() {
    final avatarUrl = _profile?['avatar_url'] as String?;
    final isPlus = _profile?['is_plus'] as bool? ?? false;
    final ringColor = isPlus ? Colors.amber : _accent;
    return GestureDetector(
      onTap: _uploadingAvatar ? null : _pickAndUploadAvatar,
      child: Stack(
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
                  blurRadius: 16,
                ),
              ],
            ),
            child: ClipOval(
              child: _uploadingAvatar
                  ? Container(
                      color: Colors.black54,
                      child: const Center(
                        child: CircularProgressIndicator(
                          color: Colors.greenAccent,
                          strokeWidth: 2.5,
                        ),
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
          // Badge de cámara para indicar que se puede cambiar la foto
          Positioned(
            right: -2,
            bottom: -2,
            child: Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: _accent,
                shape: BoxShape.circle,
                border: Border.all(color: _heroMid, width: 2.5),
              ),
              child: const Icon(Icons.photo_camera_rounded,
                  color: Colors.black, size: 14),
            ),
          ),
          // Medalla Plus con brillo (variante elegida por el ciclista)
          if (isPlus)
            const Positioned(
              top: -4,
              left: -4,
              child: PlusMedal(size: 26, ringColor: _heroMid),
            ),
        ],
      ),
    );
  }

  Widget _avatarFallback() {
    return Container(
      color: const Color(0xFF153F2E),
      child: Center(
        child: Text(
          _initials(),
          style: const TextStyle(
            fontFamily: 'Poppins',
            color: _accent,
            fontSize: 28,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }

  /// Vista previa de mis últimos momentos (hasta 6).
  Widget _buildMomentsPreview() {
    final uid = _user?.id;
    void openAll() {
      if (uid == null) return;
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => PublicProfilePage(userId: uid)),
      ).then((_) => _loadSocial());
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        activitySectionLabel(
          'MIS MOMENTOS',
          _accent,
          trailing: _momentCount > 0 ? '$_momentCount' : null,
        ),
        const SizedBox(height: 10),
        if (_myPosts.isEmpty)
          Material(
            color: Colors.white.withOpacity(0.03),
            borderRadius: BorderRadius.circular(20),
            child: InkWell(
              borderRadius: BorderRadius.circular(20),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const MomentsPage()),
              ).then((_) => _loadSocial()),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(vertical: 22, horizontal: 16),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: Colors.white.withOpacity(0.07)),
                ),
                child: Column(
                  children: [
                    Icon(Icons.add_a_photo_rounded,
                        color: _accent.withOpacity(0.7), size: 28),
                    const SizedBox(height: 8),
                    Text(
                      'Comparte tu primer momento pedaleando',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontFamily: 'Poppins',
                        color: Colors.white.withOpacity(0.6),
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          )
        else ...[
          GridView.count(
            crossAxisCount: 3,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 4,
            crossAxisSpacing: 4,
            children: [
              for (final p in _myPosts.take(6))
                GestureDetector(
                  onTap: openAll,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: CachedNetworkImage(
                      imageUrl: p['image_url'] as String,
                      fit: BoxFit.cover,
                      placeholder: (_, _) => Container(color: Colors.white10),
                      errorWidget: (_, _, _) =>
                          Container(color: Colors.white10),
                    ),
                  ),
                ),
            ],
          ),
          if (_myPosts.length > 6)
            TextButton(
              onPressed: openAll,
              child: Text(
                'Ver los $_momentCount momentos',
                style: const TextStyle(
                  fontFamily: 'Poppins',
                  color: _accent,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
        ],
      ],
    );
  }

  /// Accesos rápidos de la parte social.
  Widget _buildQuickActions() {
    final uid = _user?.id;
    return Row(
      children: [
        _quickAction(
          icon: Icons.grid_view_rounded,
          label: 'Mis momentos',
          color: const Color(0xFF69FF47),
          highlighted: true,
          onTap: uid == null
              ? null
              : () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => PublicProfilePage(userId: uid),
                    ),
                  ).then((_) => _loadSocial()),
        ),
        const SizedBox(width: 10),
        _quickAction(
          icon: Icons.auto_awesome_rounded,
          label: 'Ver feed',
          color: const Color(0xFF69FF47),
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const MomentsPage()),
          ).then((_) => _loadSocial()),
        ),
        const SizedBox(width: 10),
        _quickAction(
          icon: _pendingReqs > 0
              ? Icons.group_add_rounded
              : Icons.group_add_outlined,
          label: 'Solicitudes',
          color: _pendingReqs > 0 ? Colors.amber : Colors.white70,
          badge: _pendingReqs,
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const FollowRequestsPage()),
          ).then((_) => _loadSocial()),
        ),
      ],
    );
  }

  Widget _quickAction({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback? onTap,
    bool highlighted = false,
    int badge = 0,
  }) {
    return Expanded(
      child: Material(
        color: highlighted
            ? color.withOpacity(0.14)
            : Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: highlighted
                    ? color.withOpacity(0.35)
                    : Colors.white.withOpacity(0.08),
              ),
            ),
            child: Column(
              children: [
                Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Icon(icon, color: color, size: 24),
                    if (badge > 0)
                      Positioned(
                        right: -10,
                        top: -6,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 5, vertical: 1),
                          decoration: BoxDecoration(
                            color: Colors.amber,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            '$badge',
                            style: const TextStyle(
                              fontFamily: 'Poppins',
                              color: Colors.black,
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    color: highlighted ? Colors.white : Colors.white70,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Nivel de karma e impacto ecológico, lado a lado.
  Widget _buildStatsRow() {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(child: _buildKarmaCard()),
          const SizedBox(width: 10),
          Expanded(child: _buildCo2Card()),
        ],
      ),
    );
  }

  Widget _miniCard({required Color tint, required Widget child}) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: glassDecoration(
        radius: 20,
        tint: tint,
        opacity: 0.07,
        borderOpacity: 0.12,
      ),
      child: child,
    );
  }

  Widget _miniCardHeader(String title, Color color, {Widget? trailing}) {
    return Row(
      children: [
        Container(
          width: 6,
          height: 6,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            title,
            style: TextStyle(
              fontFamily: 'Poppins',
              color: Colors.white.withOpacity(0.55),
              fontSize: 11,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.4,
            ),
          ),
        ),
        ?trailing,
      ],
    );
  }

  Widget _buildKarmaCard() {
    final level = KarmaService.getLevel(_karma);
    final progress = KarmaService.getLevelProgress(_karma);
    final levelColor = Color(level.colorValue);

    // Próximo nivel
    final levelIndex = KarmaService.levels.indexOf(level);
    final isMax = levelIndex >= KarmaService.levels.length - 1;
    final nextLevel =
        isMax ? null : KarmaService.levels[levelIndex + 1];

    return _miniCard(
      tint: levelColor,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _miniCardHeader(
            'NIVEL',
            levelColor,
            trailing: Tooltip(
              triggerMode: TooltipTriggerMode.tap,
              showDuration: const Duration(seconds: 4),
              message:
                  'El karma sube con votos positivos en tus reportes y baja con votos negativos.',
              child: const Icon(Icons.info_outline,
                  color: Colors.white38, size: 15),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Text(level.emoji, style: const TextStyle(fontSize: 26)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  level.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    color: levelColor,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    height: 1.2,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '$_karma karma',
            style: const TextStyle(
              fontFamily: 'Poppins',
              color: Colors.white,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: progress,
              backgroundColor: Colors.white10,
              valueColor: AlwaysStoppedAnimation(levelColor),
              minHeight: 5,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            !isMax && nextLevel != null
                ? 'Próximo: ${nextLevel.emoji} ${nextLevel.title} (${nextLevel.minKarma} pts)'
                : 'Nivel máximo alcanzado',
            style: const TextStyle(
              fontFamily: 'Poppins',
              color: Colors.white38,
              fontSize: 10.5,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCo2Card() {
    final totalKm = (_profile?['total_km'] as num?)?.toDouble() ?? 0.0;
    final co2Kg   = Co2Service.savedKg(totalKm);
    final co2Str  = Co2Service.format(co2Kg);
    final treeStr = Co2Service.treeEquivalent(co2Kg);

    return _miniCard(
      tint: Colors.lightGreenAccent,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _miniCardHeader('IMPACTO', Colors.lightGreenAccent,
              trailing: const Text('🌱', style: TextStyle(fontSize: 15))),
          const SizedBox(height: 10),
          Text(
            '${totalKm.toStringAsFixed(1)} km',
            style: const TextStyle(
              fontFamily: 'Poppins',
              color: Colors.lightGreenAccent,
              fontSize: 22,
              fontWeight: FontWeight.w700,
              height: 1.1,
            ),
          ),
          Text(
            'pedaleados',
            style: TextStyle(
              fontFamily: 'Poppins',
              color: Colors.white.withOpacity(0.45),
              fontSize: 11,
            ),
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: Colors.lightGreenAccent.withOpacity(0.1),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                  color: Colors.lightGreenAccent.withOpacity(0.25)),
            ),
            child: Text(
              '$co2Str CO₂ ahorrado',
              style: const TextStyle(
                fontFamily: 'Poppins',
                color: Colors.lightGreenAccent,
                fontSize: 10.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          if (treeStr.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              treeStr,
              style: const TextStyle(
                fontFamily: 'Poppins',
                color: Colors.white38,
                fontSize: 10.5,
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// Pedalea Plus: estado de la suscripción + selector de medalla, en una
  /// sola tarjeta.
  Widget _buildPlusCard() {
    return ValueListenableBuilder<bool>(
      valueListenable: SubscriptionService.instance.isPlus,
      builder: (context, isPlus, _) {
        final color = isPlus ? Colors.amber : Colors.greenAccent;
        return Container(
          decoration: glassDecoration(
            radius: 20,
            tint: Colors.amber,
            opacity: isPlus ? 0.07 : 0.04,
            borderOpacity: isPlus ? 0.2 : 0.12,
          ),
          child: Column(
            children: [
              InkWell(
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(20)),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => isPlus
                        ? const ManageSubscriptionPage()
                        : const PaywallPage(),
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 14, 14),
                  child: Row(
                    children: [
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: color.withOpacity(0.14),
                          borderRadius: BorderRadius.circular(13),
                          border: Border.all(color: color.withOpacity(0.25)),
                        ),
                        child: Icon(
                          isPlus
                              ? Icons.workspace_premium_rounded
                              : Icons.workspace_premium_outlined,
                          color: color,
                          size: 22,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              isPlus
                                  ? 'Pedalea Plus activo'
                                  : 'Hazte Pedalea Plus',
                              style: TextStyle(
                                fontFamily: 'Poppins',
                                color: isPlus ? Colors.amber : Colors.white,
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 1),
                            Text(
                              isPlus
                                  ? 'Toca para gestionar tu suscripción'
                                  : 'Estadísticas avanzadas, eventos ilimitados y más',
                              style: TextStyle(
                                fontFamily: 'Poppins',
                                color: Colors.white.withOpacity(0.5),
                                fontSize: 11.5,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const Icon(Icons.chevron_right_rounded,
                          color: Colors.white38, size: 22),
                    ],
                  ),
                ),
              ),
              Divider(
                height: 1,
                color: Colors.white.withOpacity(0.07),
                indent: 16,
                endIndent: 16,
              ),
              _buildMedalPicker(isPlus),
            ],
          ),
        );
      },
    );
  }

  /// Selector de variante de medalla Plus. Siempre visible: si no eres Plus se
  /// muestra bloqueado (ves las opciones pero no puedes aplicarlas).
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
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: isPlus ? null : openPaywall,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Text(
                      'Tu medalla',
                      style: TextStyle(
                        fontFamily: 'Poppins',
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (!isPlus) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.amber.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.lock_outline_rounded,
                                size: 10, color: Colors.amber),
                            SizedBox(width: 3),
                            Text('PLUS',
                                style: TextStyle(
                                    fontFamily: 'Poppins',
                                    color: Colors.amber,
                                    fontSize: 9,
                                    fontWeight: FontWeight.w800)),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  isPlus
                      ? 'Elige el brillo con el que te ven en el perfil y el chat'
                      : 'Vuelve a Pedalea Plus para lucir tu medalla',
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    color: Colors.white.withOpacity(0.5),
                    fontSize: 11,
                  ),
                ),
                const SizedBox(height: 12),
                Opacity(
                  opacity: isPlus ? 1 : 0.45,
                  child: Wrap(
                    spacing: 16,
                    runSpacing: 12,
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
                                    width: 2,
                                  ),
                                ),
                                child: PlusMedal(
                                  size: 32,
                                  variant: i,
                                  ringColor: const Color(0xFF16161F),
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                PlusPrefsService.medalVariants[i].$1,
                                style: TextStyle(
                                  fontFamily: 'Poppins',
                                  color: (isPlus && sel == i)
                                      ? Colors.white
                                      : Colors.white.withOpacity(0.45),
                                  fontSize: 10,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
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
      },
    );
  }

  Widget _socialStat(String value, String label, VoidCallback? onTap) {
    return Expanded(
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
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
      ),
    );
  }

  Widget _buildProfileInfo() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _sectionLabel('INFORMACIÓN'),
        const SizedBox(height: 10),
        Container(
          decoration: glassDecoration(radius: 18),
          child: Column(children: [
            _infoRow(Icons.person_outline, 'Usuario',
                _profile?['username'] ?? '—'),
            _divider(),
            _infoRow(Icons.badge_outlined, 'Nombre completo',
                _profile?['full_name'] ?? '—'),
            _divider(),
            _infoRow(
              Icons.location_city_outlined,
              'Comuna',
              (_profile?['commune'] as String? ?? '').isNotEmpty
                  ? _profile!['commune']
                  : '—',
              valueColor: (_profile?['commune'] as String? ?? '').isNotEmpty
                  ? Colors.amberAccent
                  : null,
            ),
            _divider(),
            _infoRow(
              Icons.calendar_today_outlined,
              'Miembro desde',
              _memberSince(),
            ),
          ]),
        ),
        const SizedBox(height: 28),
        _sectionLabel('CONTACTO DE EMERGENCIA'),
        const SizedBox(height: 10),
        Container(
          decoration: glassDecoration(
            radius: 18,
            tint: Colors.redAccent,
            opacity: 0.05,
            borderOpacity: 0.14,
          ),
          child: Column(children: [
            _infoRow(
              Icons.person_pin_circle_outlined,
              'Nombre',
              (_profile?['emergency_contact_name'] as String? ?? '')
                      .isNotEmpty
                  ? _profile!['emergency_contact_name']
                  : 'No configurado',
              valueColor:
                  (_profile?['emergency_contact_name'] as String? ?? '')
                          .isNotEmpty
                      ? Colors.white
                      : Colors.orange,
            ),
            _divider(),
            _infoRow(
              Icons.phone_outlined,
              'Teléfono',
              (_profile?['emergency_contact_phone'] as String? ?? '')
                      .isNotEmpty
                  ? _profile!['emergency_contact_phone']
                  : 'No configurado',
              valueColor:
                  (_profile?['emergency_contact_phone'] as String? ?? '')
                          .isNotEmpty
                      ? Colors.white
                      : Colors.orange,
            ),
          ]),
        ),
        const SizedBox(height: 6),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Text(
            'Se avisará a esta persona por SMS si se detecta una caída.',
            style: TextStyle(
              fontFamily: 'Poppins',
              color: Colors.white.withOpacity(0.35),
              fontSize: 11,
            ),
          ),
        ),
        const SizedBox(height: 28),
        _sectionLabel('CUENTA'),
        const SizedBox(height: 10),
        Container(
          decoration: glassDecoration(radius: 18),
          child: Column(children: [
            _infoRow(Icons.email_outlined, 'Correo', _user?.email ?? '—'),
            _divider(),
            _infoRow(
              Icons.login_outlined,
              'Proveedor',
              _isGoogleUser ? 'Google' : 'Email / contraseña',
              valueColor: _isGoogleUser ? Colors.lightBlue : null,
            ),
            _divider(),
            _infoRow(
              Icons.verified_user_outlined,
              'Estado',
              _user?.emailConfirmedAt != null ? 'Verificado' : 'Sin verificar',
              valueColor: _user?.emailConfirmedAt != null
                  ? Colors.greenAccent
                  : Colors.orange,
            ),
          ]),
        ),
        const SizedBox(height: 32),
        OutlinedButton.icon(
          onPressed: () async {
            await _supabase.auth.signOut();
            if (mounted) {
              Navigator.pushNamedAndRemoveUntil(
                  context, '/', (route) => false);
            }
          },
          icon: const Icon(Icons.logout, size: 17),
          label: const Text(
            'Cerrar sesión',
            style: TextStyle(
              fontFamily: 'Poppins',
              fontWeight: FontWeight.w500,
            ),
          ),
          style: OutlinedButton.styleFrom(
            foregroundColor: Colors.redAccent,
            side: BorderSide(color: Colors.redAccent.withOpacity(0.5)),
            backgroundColor: Colors.redAccent.withOpacity(0.06),
            padding: const EdgeInsets.symmetric(vertical: 14),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          ),
        ),
      ],
    );
  }

  Widget _buildEditForm() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _sectionLabel('EDITAR PERFIL'),
        const SizedBox(height: 16),
        TextField(
          controller: _usernameCtrl,
          style: const TextStyle(
            fontFamily: 'Poppins',
            color: Colors.white,
            fontSize: 15,
          ),
          decoration: glassInput('Nombre de usuario', Icons.person_outline),
        ),
        const SizedBox(height: 14),
        TextField(
          controller: _fullNameCtrl,
          style: const TextStyle(
            fontFamily: 'Poppins',
            color: Colors.white,
            fontSize: 15,
          ),
          decoration: glassInput('Nombre completo', Icons.badge_outlined),
        ),
        const SizedBox(height: 14),
        const Text(
          'Para cambiar tu foto, toca tu avatar arriba y elígela de la galería.',
          style: TextStyle(
            fontFamily: 'Poppins',
            color: Colors.white38,
            fontSize: 12,
          ),
        ),
        const SizedBox(height: 14),
        TextField(
          controller: _communeCtrl,
          style: const TextStyle(
            fontFamily: 'Poppins',
            color: Colors.white,
            fontSize: 15,
          ),
          decoration: glassInput(
            'Mi comuna (opcional)',
            Icons.location_city_outlined,
            helper: 'Ej: Providencia, Ñuñoa, Las Condes...',
            accentColor: Colors.amberAccent,
          ),
        ),
        const SizedBox(height: 20),
        _sectionLabel('CONTACTO DE EMERGENCIA'),
        const SizedBox(height: 6),
        const Text(
          'Se le avisará por SMS si la app detecta una caída.',
          style: TextStyle(
            fontFamily: 'Poppins',
            color: Colors.white38,
            fontSize: 12,
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _emergencyNameCtrl,
          style: const TextStyle(
            fontFamily: 'Poppins',
            color: Colors.white,
            fontSize: 15,
          ),
          decoration: glassInput(
            'Nombre del contacto',
            Icons.person_pin_circle_outlined,
            accentColor: Colors.redAccent,
          ),
        ),
        const SizedBox(height: 14),
        TextField(
          controller: _emergencyPhoneCtrl,
          keyboardType: TextInputType.phone,
          style: const TextStyle(
            fontFamily: 'Poppins',
            color: Colors.white,
            fontSize: 15,
          ),
          decoration: glassInput(
            'Teléfono (ej: +56912345678)',
            Icons.phone_outlined,
            accentColor: Colors.redAccent,
          ),
        ),
        const SizedBox(height: 28),
        SizedBox(
          height: 52,
          child: ElevatedButton(
            onPressed: _saving ? null : _saveProfile,
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.greenAccent,
              foregroundColor: Colors.black,
              elevation: 0,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14)),
              textStyle: const TextStyle(
                fontFamily: 'Poppins',
                fontWeight: FontWeight.w600,
                fontSize: 16,
              ),
            ),
            child: _saving
                ? const SizedBox(
                    height: 22,
                    width: 22,
                    child: CircularProgressIndicator(
                        color: Colors.black, strokeWidth: 2),
                  )
                : const Text('Guardar cambios'),
          ),
        ),
      ],
    );
  }

  Widget _buildAchievements() {
    final unlocked = _achievements.where((a) => a['unlocked'] == true).toList();
    final locked = _achievements.where((a) => a['unlocked'] != true).toList();
    final unlockedCount = unlocked.length;
    final total = _achievements.length;

    // Vista previa: primero los desbloqueados (para celebrar el progreso),
    // completando con bloqueados hasta un máximo de 6 — el resto se ve
    // completo en "Ver más".
    final preview = [...unlocked, ...locked].take(6).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            _sectionLabel('LOGROS'),
            const Spacer(),
            Text(
              '$unlockedCount / $total',
              style: const TextStyle(
                fontFamily: 'Poppins',
                color: Colors.white38,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        // Barra de progreso
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: total > 0 ? unlockedCount / total : 0,
            backgroundColor: Colors.white10,
            valueColor: const AlwaysStoppedAnimation(Colors.greenAccent),
            minHeight: 4,
          ),
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: preview.map((a) => _badgeTile(a, a['unlocked'] == true)).toList(),
        ),
        if (total > preview.length) ...[
          const SizedBox(height: 14),
          GestureDetector(
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const AchievementsPage()),
            ),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 12),
              decoration: glassDecoration(radius: 14, tint: Colors.greenAccent, opacity: 0.06),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text(
                    'Ver todos los logros',
                    style: TextStyle(fontFamily: 'Poppins', color: Colors.greenAccent, fontSize: 13, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(width: 6),
                  const Icon(Icons.chevron_right, color: Colors.greenAccent, size: 18),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _badgeTile(Map<String, dynamic> achievement, bool unlocked) {
    final icon = achievement['icon'] as String? ?? '🏅';
    final title = achievement['title'] as String? ?? '';

    return GestureDetector(
      onTap: () => _showAchievementDetail(achievement, unlocked),
      child: Container(
        width: 80,
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        decoration: glassDecoration(
          radius: 16,
          tint: unlocked ? Colors.greenAccent : Colors.white,
          opacity: unlocked ? 0.08 : 0.03,
          borderOpacity: unlocked ? 0.2 : 0.07,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ColorFiltered(
              colorFilter: unlocked
                  ? const ColorFilter.mode(Colors.transparent, BlendMode.dst)
                  : const ColorFilter.matrix([
                      0.2126, 0.7152, 0.0722, 0, 0,
                      0.2126, 0.7152, 0.0722, 0, 0,
                      0.2126, 0.7152, 0.0722, 0, 0,
                      0,      0,      0,      0.3, 0,
                    ]),
              child: Text(icon, style: const TextStyle(fontSize: 28)),
            ),
            const SizedBox(height: 6),
            Text(
              title,
              style: TextStyle(
                fontFamily: 'Poppins',
                color: unlocked ? Colors.white : Colors.white24,
                fontSize: 10,
                fontWeight: FontWeight.w600,
              ),
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
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
        const months = [
          'ene', 'feb', 'mar', 'abr', 'may', 'jun',
          'jul', 'ago', 'sep', 'oct', 'nov', 'dic',
        ];
        dateStr = '${dt.day} ${months[dt.month - 1]} ${dt.year}';
      }
    }

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => Container(
        margin: const EdgeInsets.all(16),
        padding: const EdgeInsets.all(24),
        decoration: glassDecoration(
          radius: 24,
          tint: unlocked ? Colors.greenAccent : Colors.white,
          opacity: unlocked ? 0.1 : 0.05,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(icon, style: const TextStyle(fontSize: 52)),
            const SizedBox(height: 12),
            Text(
              title,
              style: TextStyle(
                fontFamily: 'Poppins',
                color: unlocked ? Colors.white : Colors.white38,
                fontSize: 20,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              description,
              style: const TextStyle(
                fontFamily: 'Poppins',
                color: Colors.white60,
                fontSize: 14,
              ),
              textAlign: TextAlign.center,
            ),
            if (unlocked && dateStr.isNotEmpty) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.greenAccent.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: Colors.greenAccent.withOpacity(0.2)),
                ),
                child: Text(
                  'Desbloqueado el $dateStr',
                  style: const TextStyle(
                    fontFamily: 'Poppins',
                    color: Colors.greenAccent,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
            if (!unlocked) ...[
              const SizedBox(height: 16),
              const Text(
                'Aún no desbloqueado',
                style: TextStyle(
                  fontFamily: 'Poppins',
                  color: Colors.white24,
                  fontSize: 12,
                ),
              ),
            ],
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Widget _sectionLabel(String text) => Padding(
        padding: const EdgeInsets.only(left: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 3,
              height: 12,
              decoration: BoxDecoration(
                color: _accent,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              text,
              style: TextStyle(
                fontFamily: 'Poppins',
                color: Colors.white.withOpacity(0.55),
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.2,
              ),
            ),
          ],
        ),
      );

  Widget _infoRow(IconData icon, String label, String value,
      {Color? valueColor}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: _accent.withOpacity(0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: _accent, size: 16),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                fontFamily: 'Poppins',
                color: Colors.white38,
                fontSize: 13,
              ),
            ),
          ),
          Flexible(
            child: Text(
              value,
              style: TextStyle(
                fontFamily: 'Poppins',
                color: valueColor ?? Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
              textAlign: TextAlign.end,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _divider() => Divider(
        height: 1,
        color: Colors.white.withOpacity(0.06),
        indent: 58,
        endIndent: 14,
      );
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

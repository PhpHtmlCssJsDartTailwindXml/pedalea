import 'dart:convert';
import 'dart:io' show Platform;
import 'package:pedalea/pages/map_page.dart';
import 'package:pedalea/pages/onboarding_page.dart';
import 'package:android_intent_plus/android_intent.dart';
import 'package:android_intent_plus/flag.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/co2_service.dart';
import '../widgets/loop_bike_lane_painter.dart';
import 'terms_page.dart';

// Colores de marca Pedalea
const _kNavy = Color(0xFF12233F);
const _kGreen = Color(0xFF2E9C5A); // verde ciclovía
const _kHiVis = Color(0xFFC9FF5C); // verde alta visibilidad
const _kCream = Color(0xFF0E1116); // fondo del login: modo oscuro, igual al splash

// Client ID "Web application" de Google Cloud Console: es el que valida
// Supabase (aud del id_token), no el de Android.
const _kGoogleWebClientId =
    '820970550808-b9nl5fnsfubkjdsijcv4tnhf0m4ctj5m.apps.googleusercontent.com';

class AuthPage extends StatefulWidget {
  const AuthPage({super.key});

  @override
  State<AuthPage> createState() => _AuthPageState();
}

class _AuthPageState extends State<AuthPage> with TickerProviderStateMixin {
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _usernameCtrl = TextEditingController();
  final _newPasswordCtrl = TextEditingController();
  final _confirmPasswordCtrl = TextEditingController();
  final _resetEmailCtrl = TextEditingController();
  final _confirmSignupPasswordCtrl = TextEditingController();

  bool _isLogin = true;
  Map<String, dynamic>? _community; // totales de la comunidad
  bool _loading = false;
  bool _obscure = true;
  bool _keepSession = true;
  bool _showAuthChoice = false;
  bool _showEmailForm = false;
  int _carouselPage = 0;
  bool _isDarkMode = true;

  Color get _pageBg => _isDarkMode ? const Color(0xFF0E1116) : Colors.white;
  Color get _pageFg => _isDarkMode ? Colors.white : _kNavy;

  bool _showWelcome = true;
  late final AnimationController _welcomeCtrl;
  late final AnimationController _loopCtrl;

  bool _awaitingVerification = false;
  bool _justVerified = false;
  bool _verificationDialogOpen = false;

  bool _passwordRecovery = false;
  bool _newObscure = true;
  bool _resettingPassword = false;

  // 0 = pedir correo, 1 = esperando que confirmes desde el correo,
  // 2 = ya se puede escribir la nueva contraseña.
  ValueNotifier<int>? _forgotStageNotifier;

  late final AnimationController _entranceCtrl;
  late final Animation<double> _entranceFade;
  late final AnimationController _verifiedCtrl;

  SupabaseClient get supabase => Supabase.instance.client;

  @override
  void initState() {
    super.initState();
    SystemChrome.setEnabledSystemUIMode(
      SystemUiMode.manual,
      overlays: [SystemUiOverlay.bottom],
    );
    _entranceCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    )..forward();
    _entranceFade = CurvedAnimation(parent: _entranceCtrl, curve: Curves.easeOut);
    _verifiedCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );
    _welcomeCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );
    _loopCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    );
    _runWelcomeSequence();
    _loadCommunity();

    supabase.auth.onAuthStateChange.listen((data) {
      final session = data.session;
      final event = data.event;
      if (event == AuthChangeEvent.signedIn && session != null && mounted) {
        if (_awaitingVerification) {
          if (_verificationDialogOpen) {
            Navigator.of(context, rootNavigator: true).pop();
            _verificationDialogOpen = false;
          }
          setState(() {
            _justVerified = true;
            _awaitingVerification = false;
          });
          _verifiedCtrl.forward(from: 0);
          Future.delayed(const Duration(milliseconds: 1900), () {
            if (mounted) _goToMapAfterAuth();
          });
        } else {
          _goToMapAfterAuth();
        }
      } else if (event == AuthChangeEvent.passwordRecovery && mounted) {
        _passwordRecovery = true;
        if (_forgotStageNotifier != null) {
          _forgotStageNotifier!.value = 2;
        } else {
          _showForgotPasswordDialog(initialStage: 2);
        }
      }
    });
  }

  Future<void> _runWelcomeSequence() async {
    await _loopCtrl.forward();
    if (!mounted) return;
    await _welcomeCtrl.forward();
    if (!mounted) return;
    await Future.delayed(const Duration(milliseconds: 400));
    if (!mounted) return;
    await Future.wait([
      _welcomeCtrl.reverse(),
      _loopCtrl.reverse(),
    ]);
    if (!mounted) return;
    setState(() => _showWelcome = false);
    _entranceCtrl.forward(from: 0);
  }

  @override
  void dispose() {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    _entranceCtrl.dispose();
    _verifiedCtrl.dispose();
    _welcomeCtrl.dispose();
    _loopCtrl.dispose();
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    _usernameCtrl.dispose();
    _newPasswordCtrl.dispose();
    _confirmPasswordCtrl.dispose();
    _resetEmailCtrl.dispose();
    _confirmSignupPasswordCtrl.dispose();
    _forgotStageNotifier?.dispose();
    super.dispose();
  }

  /// Tras un login/registro exitoso: si es la primera vez, muestra el
  /// onboarding (con "Empezar") antes del mapa; si ya se vio, va directo.
  Future<void> _goToMapAfterAuth() async {
    if (!mounted) return;
    final prefs = await SharedPreferences.getInstance();
    final seen = prefs.getBool('onboarding_seen') ?? false;
    if (!mounted) return;
    if (seen) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const MapPage()),
      );
    } else {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (innerContext) => OnboardingPage(
            onDone: () {
              Navigator.of(innerContext).pushReplacement(
                MaterialPageRoute(builder: (_) => const MapPage()),
              );
            },
          ),
        ),
      );
    }
  }

  Future<void> _submit() async {
    if (!_isLogin) {
      final pass = _passwordCtrl.text.trim();
      if (pass.length < 8 ||
          !RegExp(r'[A-Z]').hasMatch(pass) ||
          !RegExp(r'[0-9]').hasMatch(pass)) {
        _showSnack('Tu contraseña no cumple todos los requisitos',
            color: Colors.redAccent);
        return;
      }
      if (pass != _confirmSignupPasswordCtrl.text.trim()) {
        _showSnack('Las contraseñas no coinciden', color: Colors.redAccent);
        return;
      }
    }
    setState(() => _loading = true);
    try {
      if (_isLogin) {
        await supabase.auth.signInWithPassword(
          email: _emailCtrl.text.trim(),
          password: _passwordCtrl.text.trim(),
        );
        if (!_keepSession) {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setBool('keep_session', false);
        } else {
          final prefs = await SharedPreferences.getInstance();
          await prefs.remove('keep_session');
        }
      } else {
        final response = await supabase.auth.signUp(
          email: _emailCtrl.text.trim(),
          password: _passwordCtrl.text.trim(),
          data: {'username': _usernameCtrl.text.trim()},
        );
        if (mounted) {
          final user = response.user;
          final session = response.session;
          // Supabase, para no revelar qué correos existen, responde con
          // "éxito" aunque el correo ya esté registrado; la única pista es
          // que no viene ninguna identidad asociada al usuario devuelto.
          final alreadyRegistered = user != null && (user.identities?.isEmpty ?? false);
          if (alreadyRegistered) {
            _showSnack(
              'Ese correo ya tiene una cuenta. Inicia sesión en su lugar.',
              color: Colors.redAccent,
            );
          } else if (user != null && session == null) {
            _awaitingVerification = true;
            _showVerificationDialog();
          } else {
            _showSnack('¡Cuenta creada con éxito!', color: _kGreen);
          }
        }
      }
      if (!mounted) return;
      if (supabase.auth.currentSession != null) {
        _goToMapAfterAuth();
      }
    } on AuthException catch (e) {
      if (!mounted) return;
      _showSnack(e.message, color: Colors.redAccent);
    } catch (e) {
      if (!mounted) return;
      _showSnack('Error: $e', color: Colors.redAccent);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _submitNewPassword(void Function(void Function()) setDialogState) async {
    final pass = _newPasswordCtrl.text.trim();
    final confirm = _confirmPasswordCtrl.text.trim();
    if (pass.length < 8 ||
        !RegExp(r'[A-Z]').hasMatch(pass) ||
        !RegExp(r'[0-9]').hasMatch(pass)) {
      _showSnack('Tu contraseña no cumple todos los requisitos',
          color: Colors.redAccent);
      return;
    }
    if (pass != confirm) {
      _showSnack('Las contraseñas no coinciden', color: Colors.redAccent);
      return;
    }
    setDialogState(() => _resettingPassword = true);
    try {
      await supabase.auth.updateUser(UserAttributes(password: pass));
      // Cerramos la sesión de recuperación: no queremos dejarlo logeado
      // solo, vuelve al login para entrar con la contraseña nueva.
      await supabase.auth.signOut();
      _newPasswordCtrl.clear();
      _confirmPasswordCtrl.clear();
      _resetEmailCtrl.clear();
      _passwordRecovery = false;
      if (mounted) Navigator.of(context, rootNavigator: true).pop();
      if (mounted) {
        setState(() => _isLogin = true);
        _showSnack(
          '¡Contraseña actualizada! Inicia sesión con tu nueva contraseña.',
          color: _kGreen,
        );
      }
    } catch (e) {
      setDialogState(() => _resettingPassword = false);
      if (mounted) _showSnack('Error: $e', color: Colors.redAccent);
    }
  }

  void _showSnack(String msg, {Color color = _kGreen}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg, style: const TextStyle(fontFamily: 'Poppins')),
        backgroundColor: color,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        margin: const EdgeInsets.all(16),
      ),
    );
  }

  Future<void> _openMailApp() async {
    if (!kIsWeb && Platform.isAndroid) {
      try {
        await const AndroidIntent(
          action: 'android.intent.action.MAIN',
          package: 'com.google.android.gm',
          componentName: 'com.google.android.gm.ConversationListActivityGmail',
          flags: [Flag.FLAG_ACTIVITY_NEW_TASK],
        ).launch();
        return;
      } catch (_) {
        // Gmail no está instalado o falló el intent directo: probamos mailto.
      }
    }
    try {
      await launchUrl(Uri(scheme: 'mailto'), mode: LaunchMode.externalApplication);
    } catch (_) {
      if (mounted) {
        _showSnack('No pudimos abrir tu app de correo', color: Colors.redAccent);
      }
    }
  }

  void _showVerificationDialog() {
    _verificationDialogOpen = true;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => Dialog(
        backgroundColor: _kCream,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(28, 32, 28, 28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _kGreen.withOpacity(0.15),
                ),
                child: const Icon(
                  Icons.mark_email_unread_rounded,
                  color: _kGreen,
                  size: 30,
                ),
              ),
              const SizedBox(height: 18),
              const Text(
                'Revisa tu correo',
                style: TextStyle(
                  fontFamily: 'Poppins',
                  color: Colors.white,
                  fontSize: 19,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                'Te enviamos un link de confirmación a',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: 'Poppins',
                  color: Colors.white.withOpacity(0.55),
                  fontSize: 13.5,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                _emailCtrl.text.trim(),
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontFamily: 'Poppins',
                  color: _kGreen,
                  fontWeight: FontWeight.w700,
                  fontSize: 15,
                ),
              ),
              const SizedBox(height: 22),
              Container(
                padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.05),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: _kGreen,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Flexible(
                      child: Text(
                        'Esperando confirmación...',
                        style: TextStyle(
                          fontFamily: 'Poppins',
                          color: Colors.white.withOpacity(0.6),
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton.icon(
                  onPressed: _openMailApp,
                  icon: const Icon(Icons.open_in_new_rounded, size: 18),
                  label: const Text('Abrir correo'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _kNavy,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    textStyle: const TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: () {
                  _verificationDialogOpen = false;
                  Navigator.pop(context);
                  setState(() {
                    _awaitingVerification = false;
                    _isLogin = true;
                    _emailCtrl.clear();
                    _passwordCtrl.clear();
                    _usernameCtrl.clear();
                  });
                },
                style: TextButton.styleFrom(foregroundColor: Colors.white.withOpacity(0.4)),
                child: const Text(
                  'Volver',
                  style: TextStyle(fontFamily: 'Poppins', fontSize: 13),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _signInWithGoogle() async {
    if (kIsWeb) {
      setState(() => _loading = true);
      try {
        await supabase.auth.signInWithOAuth(
          OAuthProvider.google,
          authScreenLaunchMode: LaunchMode.platformDefault,
        );
      } on AuthException catch (e) {
        if (!mounted) return;
        _showSnack(e.message, color: Colors.redAccent);
      } catch (e) {
        if (!mounted) return;
        _showSnack('Error con Google: $e', color: Colors.redAccent);
      } finally {
        if (mounted) setState(() => _loading = false);
      }
      return;
    }

    setState(() => _loading = true);
    try {
      final googleSignIn = GoogleSignIn(serverClientId: _kGoogleWebClientId);
      await googleSignIn.signOut(); // fuerza que muestre el selector de cuenta
      final account = await googleSignIn.signIn();
      if (account == null) {
        // El usuario cerró el selector de cuenta.
        return;
      }
      final googleAuth = await account.authentication;
      final idToken = googleAuth.idToken;
      if (idToken == null) {
        throw Exception('No se pudo obtener el id_token de Google');
      }
      await supabase.auth.signInWithIdToken(
        provider: OAuthProvider.google,
        idToken: idToken,
        accessToken: googleAuth.accessToken,
      );
    } on AuthException catch (e) {
      if (!mounted) return;
      _showSnack(e.message, color: Colors.redAccent);
    } catch (e) {
      if (!mounted) return;
      _showSnack('Error con Google: $e', color: Colors.redAccent);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (supabase.auth.currentSession != null &&
        !_justVerified &&
        !_passwordRecovery) {
      return const MapPage();
    }

    if (_justVerified) {
      return _buildVerifiedSuccess();
    }

    if (_showWelcome) {
      return _buildWelcomeScreen();
    }

    final bottomSafe = MediaQuery.of(context).padding.bottom;

    return Scaffold(
      backgroundColor: _pageBg,
      resizeToAvoidBottomInset: true,
      body: FadeTransition(
        opacity: _entranceFade,
        child: SafeArea(
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 300),
            switchInCurve: Curves.easeOut,
            switchOutCurve: Curves.easeIn,
            child: _showEmailForm
                ? SingleChildScrollView(
                    key: const ValueKey('email-page'),
                    physics: const ClampingScrollPhysics(),
                    padding: EdgeInsets.fromLTRB(24, 64, 24, 24 + bottomSafe),
                    child: _buildEmailFieldsSection(),
                  )
                : Padding(
                    key: const ValueKey('carousel-page'),
                    padding: EdgeInsets.fromLTRB(24, 20, 24, 20 + bottomSafe),
                    child: Column(
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            GestureDetector(
                              onTap: () => setState(() => _isDarkMode = !_isDarkMode),
                              child: Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: _pageFg.withOpacity(0.08),
                                ),
                                child: Icon(
                                  _isDarkMode
                                      ? Icons.dark_mode_rounded
                                      : Icons.wb_sunny_rounded,
                                  color: _isDarkMode ? Colors.white70 : Colors.orange,
                                  size: 20,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        RichText(
                          textAlign: TextAlign.center,
                          text: TextSpan(
                            style: const TextStyle(
                              fontFamily: 'Sora',
                              fontSize: 30,
                              fontWeight: FontWeight.w900,
                            ),
                            children: [
                              const TextSpan(
                                text: 'Pedalea ',
                                style: TextStyle(
                                  color: _kGreen,
                                  fontStyle: FontStyle.italic,
                                ),
                              ),
                              TextSpan(
                                text: 'seguro',
                                style: TextStyle(color: _pageFg),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 12),
                        _buildCommunityStrip(),
                        const SizedBox(height: 16),
                        Expanded(child: _buildImageCarousel()),
                        const SizedBox(height: 36),
                        AnimatedSwitcher(
                          duration: const Duration(milliseconds: 280),
                          switchInCurve: Curves.easeOut,
                          switchOutCurve: Curves.easeIn,
                          transitionBuilder: (child, animation) => FadeTransition(
                            opacity: animation,
                            child: SizeTransition(sizeFactor: animation, child: child),
                          ),
                          child: _showAuthChoice
                              ? _buildLoginChoiceButtons()
                              : _buildInitialAuthButtons(),
                        ),
                      ],
                    ),
                  ),
          ),
        ),
      ),
    );
  }

  static const _kCommunityKey = 'community_stats_v1';

  /// Totales de la comunidad: primero lo último guardado (instantáneo y sin
  /// red), luego el valor fresco desde Supabase.
  Future<void> _loadCommunity() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cached = prefs.getString(_kCommunityKey);
      if (cached != null && mounted && _community == null) {
        setState(() =>
            _community = Map<String, dynamic>.from(jsonDecode(cached) as Map));
      }
      final res = await supabase.rpc('community_stats');
      final map = Map<String, dynamic>.from(
          res is String ? jsonDecode(res) as Map : res as Map);
      await prefs.setString(_kCommunityKey, jsonEncode(map));
      if (mounted) setState(() => _community = map);
    } catch (e) {
      debugPrint('community_stats: $e');
    }
  }

  static String _fmtInt(num n) {
    final v = n.round();
    if (v >= 10000) return '${(v / 1000).toStringAsFixed(1)}k';
    final s = v.toString();
    final buf = StringBuffer();
    for (int i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) buf.write('.');
      buf.write(s[i]);
    }
    return buf.toString();
  }

  /// Franja "en vivo" con cifras reales de la comunidad (cuenta hacia arriba).
  Widget _buildCommunityStrip() {
    final c = _community;
    if (c == null) return const SizedBox(height: 34);
    final cyclists = (c['cyclists'] as num?)?.toDouble() ?? 0;
    final km = (c['total_km'] as num?)?.toDouble() ?? 0;
    final co2 = Co2Service.savedKg(km);

    Widget item(double value, String Function(double) fmt, String label) {
      return TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: value),
        duration: const Duration(milliseconds: 1400),
        curve: Curves.easeOutCubic,
        builder: (_, v, _) => Text.rich(
          TextSpan(children: [
            TextSpan(
              text: fmt(v),
              style: TextStyle(
                color: _pageFg,
                fontWeight: FontWeight.w800,
              ),
            ),
            TextSpan(
              text: ' $label',
              style: TextStyle(color: _pageFg.withOpacity(0.55)),
            ),
          ]),
          style: const TextStyle(fontFamily: 'Sora', fontSize: 12.5),
        ),
      );
    }

    Widget dot() => Padding(
          padding: const EdgeInsets.symmetric(horizontal: 7),
          child: Text('·',
              style: TextStyle(
                  color: _pageFg.withOpacity(0.35),
                  fontWeight: FontWeight.w900)),
        );

    return AnimatedOpacity(
      opacity: 1,
      duration: const Duration(milliseconds: 400),
      child: Container(
        height: 34,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: _kGreen.withOpacity(_isDarkMode ? 0.12 : 0.08),
          borderRadius: BorderRadius.circular(17),
          border: Border.all(color: _kGreen.withOpacity(0.3)),
        ),
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const _LiveDot(color: _kGreen),
              const SizedBox(width: 8),
              item(cyclists, _fmtInt, 'ciclistas'),
              dot(),
              item(km, _fmtInt, 'km'),
              dot(),
              item(co2, (v) => Co2Service.format(v), 'CO₂'),
            ],
          ),
        ),
      ),
    );
  }

  // ── Carrusel: foto real de ciclismo + tarjeta de la app flotando encima ──
  // Fotos en assets/carousel/1.jpg … 4.jpg (ver LEEME.txt en esa carpeta).
  // Si falta una, se usa un fondo de respaldo para no mostrar nada roto.
  static const _kSlides = <({String image, String title, String subtitle})>[
    (
      image: 'assets/carousel/1.jpg',
      title: 'Ciclovías de todo Chile en tu mapa',
      subtitle: 'Rutas, estacionamientos y talleres cerca de ti',
    ),
    (
      image: 'assets/carousel/2.jpg',
      title: 'Sal a pedalear con tu comunidad',
      subtitle: 'Únete a salidas grupales o crea la tuya',
    ),
    (
      image: 'assets/carousel/3.jpg',
      title: 'Pedalea seguro',
      subtitle: 'Alertas en vivo y SOS a un toque',
    ),
    (
      image: 'assets/carousel/4.jpg',
      title: 'Mide tu progreso',
      subtitle: 'Km, rachas, logros y rankings',
    ),
  ];

  Widget _slideFallback(int i) {
    if (i == 0) {
      return Image.asset(
        'assets/branding/pedalea-ciclovia-foto.png',
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => _slideGradient(i),
      );
    }
    return _slideGradient(i);
  }

  Widget _slideGradient(int i) {
    const palettes = [
      [Color(0xFF1E5C41), Color(0xFF0B1A14)],
      [Color(0xFF6B3A12), Color(0xFF150D06)],
      [Color(0xFF14284A), Color(0xFF070B14)],
      [Color(0xFF3B1E5C), Color(0xFF0E0716)],
    ];
    final p = palettes[i % palettes.length];
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: p,
        ),
      ),
      child: CustomPaint(
        painter: LoopBikeLanePainter(
          color: Colors.white.withOpacity(0.08),
          progress: 1,
          strokeWidth: 3,
        ),
      ),
    );
  }

  // Tarjetas de ejemplo (diseño real de la app, datos ilustrativos).
  Widget _mockCard({required Widget child}) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
      decoration: BoxDecoration(
        color: const Color(0xFF0E0E18).withOpacity(0.92),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withOpacity(0.1)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.45),
            blurRadius: 24,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: child,
    );
  }

  Widget _mockIcon(IconData icon, Color color) => Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [color, Color.lerp(color, Colors.black, 0.3)!],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(13),
        ),
        child: Icon(icon, color: Colors.white, size: 21),
      );

  Widget _mockTexts(String title, String sub) => Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    fontFamily: 'Poppins',
                    color: Colors.white,
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700)),
            Text(sub,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontFamily: 'Poppins',
                    color: Colors.white.withOpacity(0.55),
                    fontSize: 11.5)),
          ],
        ),
      );

  Widget _mockPill(String text, Color color, {IconData? icon}) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 13, color: Colors.black),
              const SizedBox(width: 3),
            ],
            Text(text,
                style: const TextStyle(
                    fontFamily: 'Poppins',
                    color: Colors.black,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700)),
          ],
        ),
      );

  Widget _slideCard(int i) {
    switch (i) {
      case 0:
        return _mockCard(
          child: Row(children: [
            _mockIcon(Icons.route_rounded, const Color(0xFF2E9C5A)),
            const SizedBox(width: 10),
            _mockTexts('Ciclovía Pocuro', '3,2 km · Providencia'),
            const SizedBox(width: 8),
            _mockPill('Ir aquí', const Color(0xFF69FF47),
                icon: Icons.navigation_rounded),
          ]),
        );
      case 1:
        return _mockCard(
          child: Row(children: [
            Container(
              width: 46,
              padding: const EdgeInsets.symmetric(vertical: 5),
              decoration: BoxDecoration(
                color: Colors.orange.withOpacity(0.14),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.orange.withOpacity(0.4)),
              ),
              child: const Column(children: [
                Text('SÁB',
                    style: TextStyle(
                        fontFamily: 'Poppins',
                        color: Colors.orange,
                        fontSize: 9,
                        fontWeight: FontWeight.w700)),
                Text('14',
                    style: TextStyle(
                        fontFamily: 'Poppins',
                        color: Colors.white,
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                        height: 1.1)),
              ]),
            ),
            const SizedBox(width: 10),
            _mockTexts('Rodada al San Cristóbal', '10:00 · 12 ciclistas'),
            const SizedBox(width: 8),
            _mockPill('Unirme', const Color(0xFF69FF47),
                icon: Icons.add_rounded),
          ]),
        );
      case 2:
        return Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: _mockCard(
                child: Row(children: [
                  _mockIcon(Icons.warning_rounded, Colors.red),
                  const SizedBox(width: 10),
                  _mockTexts('Bache en ciclovía', 'hace 5 min · 👍 8'),
                ]),
              ),
            ),
            const SizedBox(width: 10),
            Container(
              width: 54,
              height: 54,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: const Color(0xFFC62828),
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                      color: Colors.black.withOpacity(0.45), blurRadius: 16),
                ],
              ),
              child: const Text('SOS',
                  style: TextStyle(
                      fontFamily: 'Poppins',
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w700)),
            ),
          ],
        );
      default:
        const bars = [0.3, 0.55, 0.2, 0.8, 0.6, 1.0, 0.7];
        return _mockCard(
          child: Row(children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text.rich(
                    TextSpan(children: [
                      TextSpan(
                          text: '42',
                          style: TextStyle(
                              color: Colors.white,
                              fontSize: 22,
                              fontWeight: FontWeight.w800)),
                      TextSpan(
                          text: ' km esta semana',
                          style: TextStyle(
                              color: Colors.white60, fontSize: 11.5)),
                    ]),
                    style: TextStyle(fontFamily: 'Poppins'),
                  ),
                  const SizedBox(height: 4),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.orange.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Text('🔥 5 días seguidos',
                        style: TextStyle(
                            fontFamily: 'Poppins',
                            color: Colors.orangeAccent,
                            fontSize: 10.5,
                            fontWeight: FontWeight.w700)),
                  ),
                ],
              ),
            ),
            SizedBox(
              height: 44,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  for (int b = 0; b < bars.length; b++)
                    Container(
                      width: 7,
                      height: 44 * bars[b],
                      margin: const EdgeInsets.only(left: 4),
                      decoration: BoxDecoration(
                        color: b == bars.length - 1
                            ? const Color(0xFF69FF47)
                            : const Color(0xFF69FF47).withOpacity(0.45),
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                ],
              ),
            ),
          ]),
        );
    }
  }

  Widget _buildSlide(int i) {
    final slide = _kSlides[i];
    return ClipRRect(
      borderRadius: BorderRadius.circular(32),
      child: Stack(
        fit: StackFit.expand,
        children: [
          Image.asset(
            slide.image,
            fit: BoxFit.cover,
            errorBuilder: (_, _, _) => _slideFallback(i),
          ),
          // Degradado para que el texto y la tarjeta se lean sobre la foto.
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Color(0x33000000),
                  Color(0x00000000),
                  Color(0x99000000),
                  Color(0xE6000000),
                ],
                stops: [0.0, 0.35, 0.68, 1.0],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 18, 18, 22),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Spacer(),
                _slideCard(i),
                const SizedBox(height: 20),
                Text(
                  slide.title,
                  style: const TextStyle(
                    fontFamily: 'Sora',
                    color: Colors.white,
                    fontSize: 21,
                    fontWeight: FontWeight.w800,
                    height: 1.2,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  slide.subtitle,
                  style: TextStyle(
                    fontFamily: 'Sora',
                    color: Colors.white.withOpacity(0.75),
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildImageCarousel() {
    final n = _kSlides.length;
    void goTo(int delta) {
      setState(() {
        _carouselPage = (_carouselPage + delta) % n;
        if (_carouselPage < 0) _carouselPage += n;
      });
    }

    return Column(
      children: [
        Expanded(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onHorizontalDragEnd: (details) {
              final velocity = details.primaryVelocity ?? 0;
              if (velocity.abs() < 150) return;
              goTo(velocity < 0 ? 1 : -1);
            },
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 420),
              switchInCurve: Curves.easeOut,
              switchOutCurve: Curves.easeIn,
              transitionBuilder: (child, animation) => FadeTransition(
                opacity: animation,
                child: ScaleTransition(
                  scale: Tween(begin: 0.97, end: 1.0).animate(animation),
                  child: child,
                ),
              ),
              child: KeyedSubtree(
                key: ValueKey(_carouselPage),
                child: _buildSlide(_carouselPage),
              ),
            ),
          ),
        ),
        const SizedBox(height: 16),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(n, (i) {
            final active = i == _carouselPage;
            return AnimatedContainer(
              duration: const Duration(milliseconds: 250),
              margin: const EdgeInsets.symmetric(horizontal: 4),
              width: active ? 20 : 6,
              height: 6,
              decoration: BoxDecoration(
                color: active ? _kGreen : _pageFg.withOpacity(0.25),
                borderRadius: BorderRadius.circular(3),
              ),
            );
          }),
        ),
      ],
    );
  }

  // ── Pantalla de bienvenida (fondo oscuro sólido, frase que se desvanece) ──
  Widget _buildWelcomeScreen() {
    return Scaffold(
      backgroundColor: const Color(0xFF0E1116),
      body: Center(
        child: SizedBox(
          width: 300,
          height: 190,
          child: Stack(
            alignment: Alignment.center,
            children: [
              AnimatedBuilder(
                animation: _loopCtrl,
                builder: (context, child) {
                  return CustomPaint(
                    size: const Size(300, 190),
                    painter: LoopBikeLanePainter(
                      color: _kGreen,
                      progress: _loopCtrl.value,
                      strokeWidth: 3,
                    ),
                  );
                },
              ),
              FadeTransition(
                opacity: _welcomeCtrl,
                child: ScaleTransition(
                  scale: Tween<double>(begin: 0.96, end: 1.0).animate(
                    CurvedAnimation(parent: _welcomeCtrl, curve: Curves.easeOut),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      RichText(
                        textAlign: TextAlign.center,
                        text: const TextSpan(
                          style: TextStyle(
                            fontFamily: 'Poppins',
                            fontSize: 32,
                            fontWeight: FontWeight.w900,
                          ),
                          children: [
                            TextSpan(
                              text: 'Pedalea ',
                              style: TextStyle(color: _kHiVis, fontStyle: FontStyle.italic),
                            ),
                            TextSpan(
                              text: 'seguro',
                              style: TextStyle(color: Colors.white),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        'Tu ruta, tu seguridad',
                        style: TextStyle(
                          fontFamily: 'Poppins',
                          color: Colors.white.withOpacity(0.5),
                          fontSize: 15,
                          fontWeight: FontWeight.w400,
                        ),
                      ),
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

  // ── Pantalla de éxito al volver del link de confirmación ────────────
  Widget _buildVerifiedSuccess() {
    return Scaffold(
      backgroundColor: _kNavy,
      body: Center(
        child: ScaleTransition(
          scale: CurvedAnimation(
            parent: _verifiedCtrl,
            curve: Curves.elasticOut,
          ),
          child: FadeTransition(
            opacity: CurvedAnimation(
              parent: _verifiedCtrl,
              curve: const Interval(0, 0.4, curve: Curves.easeOut),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 96,
                  height: 96,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    color: _kGreen,
                  ),
                  child: const Icon(
                    Icons.check_rounded,
                    color: Colors.white,
                    size: 52,
                  ),
                ),
                const SizedBox(height: 26),
                const Text(
                  '¡Cuenta verificada!',
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Bienvenido a Pedalea',
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    color: Colors.white.withOpacity(0.55),
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── Elegir método: Google o correo ───────────────────────────────────
  // ── Etapa inicial: elegir Unirse ahora o Iniciar sesión ──────────────
  Widget _buildInitialAuthButtons() {
    return Column(
      key: const ValueKey('initial'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          height: 54,
          child: ElevatedButton(
            onPressed: _loading
                ? null
                : () => setState(() {
                      _isLogin = false;
                      _showAuthChoice = true;
                    }),
            style: ElevatedButton.styleFrom(
              backgroundColor: _kGreen,
              foregroundColor: Colors.black,
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
              textStyle: const TextStyle(
                fontFamily: 'Sora',
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
            child: const Text('Unirse ahora'),
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 54,
          child: TextButton(
            onPressed: _loading
                ? null
                : () => setState(() {
                      _isLogin = true;
                      _showAuthChoice = true;
                    }),
            style: TextButton.styleFrom(
              foregroundColor: _pageFg,
            ),
            child: const Text(
              'Iniciar sesión',
              style: TextStyle(
                fontFamily: 'Sora',
                fontSize: 15,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildLoginChoiceButtons() {
    return Column(
      key: const ValueKey('choice'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        InkWell(
          onTap: _loading ? null : () => setState(() => _showAuthChoice = false),
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.arrow_back_rounded,
                    color: _pageFg.withOpacity(0.5), size: 16),
                const SizedBox(width: 4),
                Text(
                  'Volver',
                  style: TextStyle(
                    fontFamily: 'Sora',
                    color: _pageFg.withOpacity(0.5),
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
        ),
        RichText(
          textAlign: TextAlign.center,
          text: TextSpan(
            style: const TextStyle(
              fontFamily: 'Sora',
              fontSize: 22,
              fontWeight: FontWeight.w900,
            ),
            children: [
              TextSpan(
                text: _isLogin ? 'Bienvenido ' : 'Únete a ',
                style: TextStyle(color: _pageFg),
              ),
              TextSpan(
                text: _isLogin ? 'de vuelta' : 'Pedalea',
                style: const TextStyle(
                  color: _kGreen,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        _buildGoogleButton(),
        const SizedBox(height: 14),
        SizedBox(
          height: 52,
          child: OutlinedButton(
            onPressed: _loading ? null : () => setState(() => _showEmailForm = true),
            style: OutlinedButton.styleFrom(
              side: BorderSide(color: _pageFg.withOpacity(0.18)),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.mail_outline_rounded, color: _pageFg, size: 20),
                const SizedBox(width: 10),
                Text(
                  _isLogin ? 'Iniciar con Email' : 'Registrarse con Email',
                  style: TextStyle(
                    fontFamily: 'Sora',
                    color: _pageFg,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        _buildTermsNotice(),
      ],
    );
  }

  // ── Formulario de correo/contraseña ──────────────────────────────────
  Widget _buildEmailFieldsSection() {
    return Column(
      key: const ValueKey('email-fields'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        InkWell(
          onTap: _loading ? null : () => setState(() => _showEmailForm = false),
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.arrow_back_rounded,
                    color: _pageFg.withOpacity(0.5), size: 16),
                const SizedBox(width: 4),
                Text(
                  'Volver',
                  style: TextStyle(
                    fontFamily: 'Sora',
                    color: _pageFg.withOpacity(0.5),
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        RichText(
          textAlign: TextAlign.center,
          text: TextSpan(
            style: const TextStyle(
              fontFamily: 'Sora',
              fontSize: 22,
              fontWeight: FontWeight.w900,
            ),
            children: [
              TextSpan(
                text: _isLogin ? 'Bienvenido ' : 'Únete a ',
                style: TextStyle(color: _pageFg),
              ),
              TextSpan(
                text: _isLogin ? 'de vuelta' : 'Pedalea',
                style: const TextStyle(
                  color: _kGreen,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 28),
        AnimatedSize(
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeInOut,
          child: Column(
            children: [
              if (!_isLogin) ...[
                _buildTextField(
                  controller: _usernameCtrl,
                  label: 'NOMBRE DE USUARIO',
                  hint: 'tu_usuario',
                ),
                const SizedBox(height: 20),
              ],
              _buildTextField(
                controller: _emailCtrl,
                label: 'CORREO ELECTRÓNICO',
                hint: 'tu@correo.cl',
                keyboardType: TextInputType.emailAddress,
              ),
              const SizedBox(height: 20),
              _buildTextField(
                controller: _passwordCtrl,
                label: 'CONTRASEÑA',
                hint: '••••••••',
                obscure: _obscure,
                onChanged: !_isLogin ? (_) => setState(() {}) : null,
                suffix: IconButton(
                  icon: Icon(
                    _obscure
                        ? Icons.visibility_off_outlined
                        : Icons.visibility_outlined,
                    color: _pageFg.withOpacity(0.4),
                    size: 20,
                  ),
                  onPressed: () => setState(() => _obscure = !_obscure),
                ),
              ),
              if (!_isLogin) ...[
                const SizedBox(height: 10),
                _buildPasswordStrengthBar(_passwordCtrl.text, base: _pageFg),
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildPasswordRequirement(
                        'Mínimo 8 caracteres',
                        _passwordCtrl.text.length >= 8,
                        base: _pageFg,
                      ),
                      _buildPasswordRequirement(
                        'Al menos una mayúscula',
                        RegExp(r'[A-Z]').hasMatch(_passwordCtrl.text),
                        base: _pageFg,
                      ),
                      _buildPasswordRequirement(
                        'Al menos un número',
                        RegExp(r'[0-9]').hasMatch(_passwordCtrl.text),
                        base: _pageFg,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                _buildTextField(
                  controller: _confirmSignupPasswordCtrl,
                  label: 'REPETIR CONTRASEÑA',
                  hint: '••••••••',
                  obscure: _obscure,
                  onChanged: (_) => setState(() {}),
                ),
                if (_confirmSignupPasswordCtrl.text.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: _buildPasswordRequirement(
                      'Las contraseñas coinciden',
                      _confirmSignupPasswordCtrl.text == _passwordCtrl.text,
                      base: _pageFg,
                    ),
                  ),
                ],
              ],
            ],
          ),
        ),

        if (_isLogin) ...[
          const SizedBox(height: 14),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              InkWell(
                onTap: _loading
                    ? null
                    : () => setState(() => _keepSession = !_keepSession),
                borderRadius: BorderRadius.circular(8),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        width: 20,
                        height: 20,
                        child: Checkbox(
                          value: _keepSession,
                          onChanged: _loading
                              ? null
                              : (v) => setState(() => _keepSession = v ?? true),
                          activeColor: _kGreen,
                          side: BorderSide(color: _pageFg.withOpacity(0.3)),
                          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Mantener sesión',
                        style: TextStyle(
                          fontFamily: 'Sora',
                          color: _pageFg.withOpacity(0.6),
                          fontSize: 12.5,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              TextButton(
                onPressed: _loading ? null : () => _showForgotPasswordDialog(),
                style: TextButton.styleFrom(
                  padding: EdgeInsets.zero,
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: const Text(
                  '¿Olvidaste tu contraseña?',
                  style: TextStyle(
                    fontFamily: 'Sora',
                    color: _kGreen,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ),
            ],
          ),
        ],

        const SizedBox(height: 24),
        _buildMainButton(),
        const SizedBox(height: 16),
        _buildTermsNotice(),
      ],
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required String hint,
    TextInputType? keyboardType,
    bool obscure = false,
    Widget? suffix,
    ValueChanged<String>? onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontFamily: 'Sora',
            color: _kGreen,
            fontSize: 12,
            fontWeight: FontWeight.w700,
            fontStyle: FontStyle.italic,
          ),
        ),
        const SizedBox(height: 6),
        TextField(
          controller: controller,
          keyboardType: keyboardType,
          obscureText: obscure,
          onChanged: onChanged,
          style: TextStyle(
            fontFamily: 'Sora',
            color: _pageFg,
            fontSize: 15,
          ),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: TextStyle(
              fontFamily: 'Sora',
              color: _pageFg.withOpacity(0.25),
              fontSize: 15,
            ),
            suffixIcon: suffix,
            filled: true,
            fillColor: _pageFg.withOpacity(0.04),
            contentPadding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide(color: _pageFg.withOpacity(0.12)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide(color: _pageFg.withOpacity(0.12)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: _kGreen, width: 1.6),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildMainButton() {
    return SizedBox(
      height: 54,
      child: ElevatedButton(
        onPressed: _loading ? null : _submit,
        style: ElevatedButton.styleFrom(
          backgroundColor: _kNavy,
          disabledBackgroundColor: _kNavy.withOpacity(0.5),
          foregroundColor: Colors.white,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          textStyle: const TextStyle(
            fontFamily: 'Sora',
            fontSize: 16,
            fontWeight: FontWeight.w700,
          ),
        ),
        child: _loading
            ? const SizedBox(
                height: 22,
                width: 22,
                child: CircularProgressIndicator(
                  color: Colors.white,
                  strokeWidth: 2.5,
                ),
              )
            : Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(_isLogin ? 'Iniciar sesión' : 'Crear cuenta'),
                  const SizedBox(width: 8),
                  const Icon(Icons.arrow_forward_rounded, size: 18),
                ],
              ),
      ),
    );
  }

  Widget _buildTermsNotice() {
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: RichText(
        textAlign: TextAlign.center,
        text: TextSpan(
          style: TextStyle(
            fontFamily: 'Sora',
            color: _pageFg.withOpacity(0.4),
            fontSize: 11.5,
            height: 1.4,
          ),
          children: [
            TextSpan(
              text: _isLogin
                  ? 'Al iniciar sesión, aceptas nuestros '
                  : 'Al registrarte, aceptas nuestros ',
            ),
            TextSpan(
              text: 'Términos y Condiciones',
              style: const TextStyle(
                color: _kGreen,
                fontWeight: FontWeight.w700,
                decoration: TextDecoration.underline,
              ),
              recognizer: TapGestureRecognizer()
                ..onTap = () {
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const TermsPage()),
                  );
                },
            ),
            const TextSpan(text: '.'),
          ],
        ),
      ),
    );
  }

  Widget _buildGoogleButton() {
    return SizedBox(
      height: 52,
      child: OutlinedButton(
        onPressed: _loading ? null : _signInWithGoogle,
        style: OutlinedButton.styleFrom(
          backgroundColor: Colors.white,
          side: BorderSide(color: _kNavy.withOpacity(0.12)),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(
              width: 20,
              height: 20,
              child: SvgPicture.asset('assets/branding/google_logo.svg'),
            ),
            const SizedBox(width: 10),
            Text(
              _isLogin ? 'Iniciar con Google' : 'Registrarse con Google',
              style: TextStyle(
                fontFamily: 'Sora',
                color: _kNavy.withOpacity(0.8),
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showForgotPasswordDialog({int initialStage = 0}) {
    _forgotStageNotifier = ValueNotifier(initialStage);

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => ValueListenableBuilder<int>(
        valueListenable: _forgotStageNotifier!,
        builder: (ctx, stage, _) {
          return Dialog(
            backgroundColor: _kCream,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(28, 32, 28, 28),
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 280),
                child: switch (stage) {
                  1 => _buildForgotWaiting(),
                  2 => _buildForgotNewPasswordForm(),
                  _ => _buildForgotEmailForm(),
                },
              ),
            ),
          );
        },
      ),
    ).then((_) {
      if (_passwordRecovery) {
        // Se cerró el modal con una sesión de recuperación activa sin
        // guardar: cerramos esa sesión para no dejarlo logeado a medias.
        supabase.auth.signOut();
        _passwordRecovery = false;
      }
      _forgotStageNotifier?.dispose();
      _forgotStageNotifier = null;
    });
  }

  Widget _buildForgotEmailForm() {
    return StatefulBuilder(
      key: const ValueKey('forgot-email'),
      builder: (ctx, setDialogState) {
        bool sending = false;
        return StatefulBuilder(
          builder: (ctx, setSendingState) => Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _kGreen.withOpacity(0.15),
                ),
                child: const Icon(Icons.lock_reset_rounded, color: _kGreen, size: 30),
              ),
              const SizedBox(height: 18),
              const Text(
                'Recuperar contraseña',
                style: TextStyle(
                  fontFamily: 'Poppins',
                  color: Colors.white,
                  fontSize: 19,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                'Ingresa tu correo y te enviaremos un link para\nrestablecer tu contraseña.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: 'Poppins',
                  color: Colors.white.withOpacity(0.55),
                  fontSize: 13.5,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 24),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'CORREO ELECTRÓNICO',
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    color: Colors.white.withOpacity(0.45),
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.0,
                  ),
                ),
              ),
              const SizedBox(height: 6),
              TextField(
                controller: _resetEmailCtrl,
                keyboardType: TextInputType.emailAddress,
                style: const TextStyle(fontFamily: 'Poppins', color: Colors.white, fontSize: 16),
                decoration: InputDecoration(
                  isDense: true,
                  hintText: 'tu@correo.cl',
                  hintStyle: TextStyle(color: Colors.white.withOpacity(0.25)),
                  enabledBorder: UnderlineInputBorder(
                    borderSide: BorderSide(color: Colors.white.withOpacity(0.15)),
                  ),
                  focusedBorder: const UnderlineInputBorder(
                    borderSide: BorderSide(color: _kGreen, width: 1.6),
                  ),
                  contentPadding: const EdgeInsets.symmetric(vertical: 10),
                ),
              ),
              const SizedBox(height: 26),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  onPressed: sending
                      ? null
                      : () async {
                          final email = _resetEmailCtrl.text.trim();
                          if (email.isEmpty) return;
                          setSendingState(() => sending = true);
                          try {
                            await supabase.auth.resetPasswordForEmail(email);
                            _forgotStageNotifier?.value = 1;
                          } catch (e) {
                            setSendingState(() => sending = false);
                            if (mounted) {
                              _showSnack('Error: $e', color: Colors.redAccent);
                            }
                          }
                        },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _kNavy,
                    disabledBackgroundColor: _kNavy.withOpacity(0.5),
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    textStyle: const TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  child: sending
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.4),
                        )
                      : const Text('Enviar enlace'),
                ),
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: sending ? null : () => Navigator.of(context, rootNavigator: true).pop(),
                style: TextButton.styleFrom(foregroundColor: Colors.white.withOpacity(0.4)),
                child: const Text('Cancelar', style: TextStyle(fontFamily: 'Poppins', fontSize: 13)),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildForgotWaiting() {
    return Column(
      key: const ValueKey('forgot-waiting'),
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 64,
          height: 64,
          decoration: BoxDecoration(shape: BoxShape.circle, color: _kGreen.withOpacity(0.15)),
          child: const Padding(
            padding: EdgeInsets.all(18),
            child: CircularProgressIndicator(color: _kGreen, strokeWidth: 2.6),
          ),
        ),
        const SizedBox(height: 18),
        const Text(
          'Revisa tu correo',
          style: TextStyle(
            fontFamily: 'Poppins',
            color: Colors.white,
            fontSize: 19,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 10),
        Text(
          'Te enviamos un link a\n${_resetEmailCtrl.text.trim()}',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontFamily: 'Poppins',
            color: Colors.white.withOpacity(0.55),
            fontSize: 13.5,
            height: 1.4,
          ),
        ),
        const SizedBox(height: 22),
        Container(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.05),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2, color: _kGreen),
              ),
              const SizedBox(width: 12),
              Flexible(
                child: Text(
                  'Verificando confirmación...',
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    color: Colors.white.withOpacity(0.6),
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        SizedBox(
          width: double.infinity,
          height: 50,
          child: ElevatedButton.icon(
            onPressed: _openMailApp,
            icon: const Icon(Icons.open_in_new_rounded, size: 18),
            label: const Text('Abrir correo'),
            style: ElevatedButton.styleFrom(
              backgroundColor: _kNavy,
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              textStyle: const TextStyle(
                fontFamily: 'Poppins',
                fontSize: 15,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        TextButton(
          onPressed: () => Navigator.of(context, rootNavigator: true).pop(),
          style: TextButton.styleFrom(foregroundColor: Colors.white.withOpacity(0.4)),
          child: const Text('Cancelar', style: TextStyle(fontFamily: 'Poppins', fontSize: 13)),
        ),
      ],
    );
  }

  // 0..4: cantidad de requisitos cumplidos.
  int _passwordScore(String pass) {
    int score = 0;
    if (pass.length >= 8) score++;
    if (RegExp(r'[A-Z]').hasMatch(pass)) score++;
    if (RegExp(r'[0-9]').hasMatch(pass)) score++;
    if (RegExp(r'[^A-Za-z0-9]').hasMatch(pass)) score++;
    return score;
  }

  Widget _buildPasswordStrengthBar(String pass, {Color base = Colors.white}) {
    final score = _passwordScore(pass);
    const labels = ['Muy débil', 'Débil', 'Media', 'Fuerte', 'Muy fuerte'];
    const colors = [
      Color(0xFFE24C4C),
      Color(0xFFE2914C),
      Color(0xFFE2C94C),
      Color(0xFF8BC44C),
      _kGreen,
    ];
    final color = pass.isEmpty ? base.withOpacity(0.12) : colors[score];
    final label = pass.isEmpty ? '' : labels[score];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: List.generate(4, (i) {
            final filled = pass.isNotEmpty && i < score;
            return Expanded(
              child: Container(
                margin: EdgeInsets.only(right: i == 3 ? 0 : 4),
                height: 4,
                decoration: BoxDecoration(
                  color: filled ? color : base.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            );
          }),
        ),
        if (label.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(
            label,
            style: TextStyle(
              fontFamily: 'Poppins',
              color: color,
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildPasswordRequirement(String text, bool met, {Color base = Colors.white}) {
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        children: [
          Icon(
            met ? Icons.check_circle_rounded : Icons.circle_outlined,
            size: 15,
            color: met ? _kGreen : base.withOpacity(0.25),
          ),
          const SizedBox(width: 6),
          Text(
            text,
            style: TextStyle(
              fontFamily: 'Poppins',
              fontSize: 12,
              color: met ? base.withOpacity(0.7) : base.withOpacity(0.35),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildForgotNewPasswordForm() {
    return StatefulBuilder(
      key: const ValueKey('forgot-new-password'),
      builder: (ctx, setDialogState) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(shape: BoxShape.circle, color: _kGreen.withOpacity(0.15)),
            child: const Icon(Icons.check_circle_rounded, color: _kGreen, size: 30),
          ),
          const SizedBox(height: 18),
          const Text(
            'Crea tu nueva contraseña',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: 'Poppins',
              color: Colors.white,
              fontSize: 19,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            'Confirmado. Escribe tu nueva contraseña.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: 'Poppins',
              color: Colors.white.withOpacity(0.55),
              fontSize: 13.5,
            ),
          ),
          const SizedBox(height: 24),
          _buildTextField(
            controller: _newPasswordCtrl,
            label: 'NUEVA CONTRASEÑA',
            hint: '••••••••',
            obscure: _newObscure,
            onChanged: (_) => setDialogState(() {}),
            suffix: IconButton(
              icon: Icon(
                _newObscure ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                color: Colors.white.withOpacity(0.4),
                size: 20,
              ),
              onPressed: () => setDialogState(() => _newObscure = !_newObscure),
            ),
          ),
          const SizedBox(height: 10),
          _buildPasswordStrengthBar(_newPasswordCtrl.text),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerLeft,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildPasswordRequirement(
                  'Mínimo 8 caracteres',
                  _newPasswordCtrl.text.length >= 8,
                ),
                _buildPasswordRequirement(
                  'Al menos una mayúscula',
                  RegExp(r'[A-Z]').hasMatch(_newPasswordCtrl.text),
                ),
                _buildPasswordRequirement(
                  'Al menos un número',
                  RegExp(r'[0-9]').hasMatch(_newPasswordCtrl.text),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          _buildTextField(
            controller: _confirmPasswordCtrl,
            label: 'CONFIRMAR CONTRASEÑA',
            hint: '••••••••',
            obscure: _newObscure,
            onChanged: (_) => setDialogState(() {}),
          ),
          const SizedBox(height: 6),
          Align(
            alignment: Alignment.centerLeft,
            child: _buildPasswordRequirement(
              'Las contraseñas coinciden',
              _confirmPasswordCtrl.text.isNotEmpty &&
                  _confirmPasswordCtrl.text == _newPasswordCtrl.text,
            ),
          ),
          const SizedBox(height: 26),
          SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton(
              onPressed: _resettingPassword ? null : () => _submitNewPassword(setDialogState),
              style: ElevatedButton.styleFrom(
                backgroundColor: _kNavy,
                disabledBackgroundColor: _kNavy.withOpacity(0.5),
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                textStyle: const TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
              child: _resettingPassword
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.4),
                    )
                  : const Text('Guardar contraseña'),
            ),
          ),
        ],
      ),
    );
  }
}

/// Punto verde que late suavemente (indicador "en vivo").
class _LiveDot extends StatefulWidget {
  final Color color;
  const _LiveDot({required this.color});

  @override
  State<_LiveDot> createState() => _LiveDotState();
}

class _LiveDotState extends State<_LiveDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  )..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 14,
      height: 14,
      child: AnimatedBuilder(
        animation: _c,
        builder: (_, _) => Stack(
          alignment: Alignment.center,
          children: [
            Transform.scale(
              scale: 1 + _c.value * 1.2,
              child: Container(
                width: 7,
                height: 7,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: widget.color.withOpacity(0.45 * (1 - _c.value)),
                ),
              ),
            ),
            Container(
              width: 7,
              height: 7,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: widget.color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

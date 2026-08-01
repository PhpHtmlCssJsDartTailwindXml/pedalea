import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'pages/auth_page.dart';
import 'services/cache_service.dart';
import 'services/connectivity_service.dart';
import 'services/notification_service.dart';
import 'services/ride_stats_service.dart';
import 'services/subscription_service.dart';
import 'core/route_observer.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Supabase.initialize(
    url: 'https://ocheyavlacprkvbongno.supabase.co',
    anonKey: 'sb_publishable_2Zn9aWBMJW3Yll2x8gTfdQ_aA5TbDqW',
  );

  await CacheService.init();
  await ConnectivityService.init();
  await NotificationService.instance.init();
  await RideStatsService.init();
  unawaited(SubscriptionService.instance.init());

  runApp(const PedaleaApp());
}

class PedaleaApp extends StatelessWidget {
  const PedaleaApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Pedalea',
      theme: ThemeData(primarySwatch: Colors.green),
      navigatorObservers: [routeObserver],
      home: const _StartupGate(),
    );
  }
}

/// El onboarding ("Empezar") ya no se muestra antes del login: ahora
/// AuthPage lo muestra después de iniciar sesión/registrarse, solo la
/// primera vez (ver AuthPage._goToMapAfterAuth).
class _StartupGate extends StatefulWidget {
  const _StartupGate();

  @override
  State<_StartupGate> createState() => _StartupGateState();
}

class _StartupGateState extends State<_StartupGate> {
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    _check();
  }

  Future<void> _check() async {
    final prefs = await SharedPreferences.getInstance();
    // Si el usuario desmarcó "mantener sesión iniciada" en su último login,
    // no lo dejamos entrar solo la próxima vez que abra la app.
    final keepSession = prefs.getBool('keep_session') ?? true;
    if (!keepSession) {
      await Supabase.instance.client.auth.signOut();
      await prefs.remove('keep_session');
    }
    if (mounted) setState(() => _ready = true);
  }

  @override
  Widget build(BuildContext context) {
    if (!_ready) {
      return const Scaffold(
        backgroundColor: Color(0xFF12213F),
        body: Center(
          child: CircularProgressIndicator(color: Color(0xFFC9FF5C)),
        ),
      );
    }
    return const AuthPage();
  }
}

import 'dart:async';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../core/push_config.dart';
import 'chat_notifications_service.dart';
import 'notification_service.dart';

/// Notificaciones push reales (FCM): llegan aunque la app esté cerrada.
///
/// Cómo encaja con lo que ya había:
///  - El servidor (Edge Function `send-push`, disparada por triggers de la
///    BD) envía el aviso al teléfono del destinatario.
///  - App cerrada o en segundo plano: Android muestra la notificación solo.
///  - App abierta: FCM no la muestra; la recibimos aquí y la mostramos como
///    notificación local, salvo que estés mirando justo ese chat.
///  - Mientras el push esté activo ([active]), los avisos por Realtime
///    (ChatNotificationsService / SocialNotificationsService) se callan para
///    no duplicar. Si el push no está configurado o falla, siguen
///    funcionando como respaldo.
class PushService {
  PushService._();
  static final PushService instance = PushService._();

  SupabaseClient get _sb => Supabase.instance.client;

  bool _started = false;
  bool _registered = false;
  String? _token;

  /// true cuando este teléfono tiene su token registrado para la cuenta
  /// actual: el servidor ya puede avisarle por push.
  static bool get active => instance._registered;

  /// Se llama una vez al arrancar la app (no bloquea el inicio).
  Future<void> init() async {
    if (_started || !PushConfig.isConfigured) return;
    _started = true;
    try {
      await Firebase.initializeApp(options: PushConfig.options);
      final fm = FirebaseMessaging.instance;
      await fm.requestPermission();

      FirebaseMessaging.onMessage.listen(_onForegroundMessage);
      FirebaseMessaging.onMessageOpenedApp.listen(_onOpened);
      fm.onTokenRefresh.listen((t) {
        _token = t;
        _register();
      });

      _sb.auth.onAuthStateChange.listen((state) {
        switch (state.event) {
          case AuthChangeEvent.signedIn:
          case AuthChangeEvent.initialSession:
            _register();
            break;
          case AuthChangeEvent.signedOut:
            _unregister();
            break;
          default:
            break;
        }
      });

      _token = await fm.getToken();
      await _register();

      // La app se abrió tocando una notificación estando cerrada.
      final initial = await fm.getInitialMessage();
      if (initial != null) _onOpened(initial);
    } catch (e) {
      debugPrint('PushService.init: $e');
    }
  }

  /// Asocia el token de este teléfono a la cuenta con sesión iniciada.
  Future<void> _register() async {
    final token = _token;
    if (token == null || _sb.auth.currentUser == null) return;
    try {
      await _sb.rpc(
        'register_device_token',
        params: {'p_token': token, 'p_platform': 'android'},
      );
      _registered = true;
    } catch (e) {
      _registered = false;
      debugPrint('PushService._register: $e');
    }
  }

  /// Al cerrar sesión, este teléfono deja de recibir avisos de esa cuenta.
  Future<void> _unregister() async {
    _registered = false;
    final token = _token;
    if (token == null) return;
    try {
      await _sb.rpc('unregister_device_token', params: {'p_token': token});
    } catch (e) {
      debugPrint('PushService._unregister: $e');
    }
  }

  /// Push recibido con la app abierta: se muestra como notificación local.
  Future<void> _onForegroundMessage(RemoteMessage m) async {
    final d = m.data;
    final type = d['type'] as String? ?? '';
    final title = d['title'] as String? ?? m.notification?.title ?? 'Pedalea';
    final body = d['body'] as String? ?? m.notification?.body ?? '';
    final payload = d['payload'] as String? ?? '';
    final notifs = NotificationService.instance;

    switch (type) {
      case 'chat':
        final eventId = d['event_id'] as String? ?? '';
        if (eventId.isEmpty) return;
        if (ChatNotificationsService.activeEventId == eventId) return;
        await notifs.showChatMessage(
          eventId: eventId,
          groupTitle: title,
          sender: d['sender_name'] as String? ?? 'Alguien',
          body: d['text'] as String? ?? body,
        );
        break;
      case 'dm':
        final senderId = d['sender_id'] as String? ?? '';
        if (ChatNotificationsService.activeDmUserId == senderId) return;
        await notifs.showSocial(
          id: 310000 + (senderId.hashCode.abs() % 80000),
          title: title,
          body: body,
          payload: payload,
        );
        break;
      default:
        await notifs.showSocial(
          id: _socialIds[type] ?? 300199,
          title: title,
          body: body,
          payload: payload,
        );
    }
  }

  /// Mismos ids que usaba el aviso por Realtime, para que un aviso nuevo del
  /// mismo tipo reemplace al anterior en vez de apilarse.
  static const _socialIds = <String, int>{
    'follow_req': 300001,
    'follow_accept': 300002,
    'like': 300100,
    'comment': 300101,
    'reply': 300102,
  };

  /// El usuario tocó una notificación push: abre la pantalla que corresponde.
  void _onOpened(RemoteMessage m) {
    final payload = m.data['payload'] as String?;
    if (payload == null || payload.isEmpty) return;
    _openWhenReady(payload, attempts: 0);
  }

  /// Si la app venía cerrada, el Navigator todavía no existe: se reintenta
  /// unos segundos hasta que esté listo.
  void _openWhenReady(String payload, {required int attempts}) {
    if (NotificationService.openPayload(payload) || attempts >= 20) return;
    Future.delayed(
      const Duration(milliseconds: 400),
      () => _openWhenReady(payload, attempts: attempts + 1),
    );
  }
}

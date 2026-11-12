import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;
import '../core/app_navigator.dart';
import '../pages/event_chat_page.dart';
import '../pages/follow_requests_page.dart';
import '../pages/public_profile_page.dart';
import '../pages/dm_thread_page.dart';
import '../pages/my_bikes_page.dart';
import '../pages/profile_page.dart';

/// Servicio centralizado de notificaciones locales (alertas push).
///
/// Cubre el requerimiento del Acta/Informe: "Alertas push en tiempo real al
/// acercarse a incidentes activos en el trayecto". Las notificaciones son
/// locales (no requieren servidor push) y se disparan desde la propia app
/// cuando la lógica de proximidad lo determina.
class NotificationService {
  NotificationService._();
  static final NotificationService instance = NotificationService._();

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  bool _initialized = false;

  static const String _proximityChannelId = 'proximity_alerts';
  static const String _proximityChannelName = 'Alertas de proximidad';
  static const String _emergencyChannelId = 'emergency_alerts';
  static const String _emergencyChannelName = 'Emergencias';
  static const String _eventReminderChannelId = 'event_reminders';
  static const String _eventReminderChannelName = 'Recordatorios de eventos';
  static const String _chatChannelId = 'group_chat_messages';
  static const String _chatChannelName = 'Mensajes de grupos';
  static const String _socialChannelId = 'social_activity';
  static const String _socialChannelName = 'Momentos y seguidores';
  static const String _maintenanceChannelId = 'bike_maintenance';
  static const String _maintenanceChannelName = 'Mantención de tu bici';

  /// Inicializa el plugin y solicita permiso de notificaciones (Android 13+).
  Future<void> init() async {
    if (_initialized) return;
    try {
      tzdata.initializeTimeZones();
      tz.setLocalLocation(tz.getLocation('America/Santiago'));

      const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
      const initSettings = InitializationSettings(android: androidInit);
      await _plugin.initialize(
        initSettings,
        onDidReceiveNotificationResponse: _onNotificationTap,
      );

      final androidImpl = _plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >();
      await androidImpl?.requestNotificationsPermission();

      // Los canales de mensajes y actividad social se crean desde ya (antes
      // se creaban al mostrar el primer aviso): las notificaciones push
      // llegan con la app cerrada y necesitan que el canal exista.
      await androidImpl?.createNotificationChannel(
        const AndroidNotificationChannel(
          _chatChannelId,
          _chatChannelName,
          description:
              'Avisa cuando alguien escribe en un grupo del que eres parte',
          importance: Importance.high,
        ),
      );
      await androidImpl?.createNotificationChannel(
        const AndroidNotificationChannel(
          _socialChannelId,
          _socialChannelName,
          description: 'Solicitudes de seguimiento y actividad en tus momentos',
          importance: Importance.high,
        ),
      );

      _initialized = true;
    } catch (e) {
      debugPrint('NotificationService init error: $e');
    }
  }

  /// Programa un recordatorio local 1 hora antes de un evento al que el
  /// usuario se unió. Si la hora ya pasó, no programa nada.
  Future<void> scheduleEventReminder({
    required String eventId,
    required String title,
    required DateTime eventDate,
  }) async {
    await _ensureInit();
    final reminderTime = eventDate.subtract(const Duration(hours: 1));
    if (reminderTime.isBefore(DateTime.now())) return;
    try {
      await _plugin.zonedSchedule(
        _eventNotificationId(eventId),
        '🚴 $title empieza pronto',
        'Tu evento comienza en 1 hora',
        tz.TZDateTime.from(reminderTime, tz.local),
        const NotificationDetails(
          android: AndroidNotificationDetails(
            _eventReminderChannelId,
            _eventReminderChannelName,
            channelDescription: 'Avisa antes de que empiece un evento al que te uniste',
            importance: Importance.high,
            priority: Priority.high,
            icon: '@mipmap/ic_launcher',
          ),
        ),
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
      );
    } catch (e) {
      debugPrint('scheduleEventReminder error: $e');
    }
  }

  /// Cancela el recordatorio de un evento (al salir o cancelarlo).
  Future<void> cancelEventReminder(String eventId) async {
    await _ensureInit();
    try {
      await _plugin.cancel(_eventNotificationId(eventId));
    } catch (e) {
      debugPrint('cancelEventReminder error: $e');
    }
  }

  int _eventNotificationId(String eventId) =>
      100000 + (eventId.hashCode.abs() % 900000);

  /// Notificación de un incidente cercano en la ruta del ciclista.
  Future<void> showProximityAlert({
    required int id,
    required String title,
    required String body,
  }) async {
    await _ensureInit();
    try {
      await _plugin.show(
        id,
        title,
        body,
        const NotificationDetails(
          android: AndroidNotificationDetails(
            _proximityChannelId,
            _proximityChannelName,
            channelDescription:
                'Avisa cuando te acercas a un incidente reportado',
            importance: Importance.high,
            priority: Priority.high,
            icon: '@mipmap/ic_launcher',
          ),
        ),
      );
    } catch (e) {
      debugPrint('showProximityAlert error: $e');
    }
  }

  /// Notificación de emergencia (usada por la detección de caídas).
  Future<void> showEmergencyAlert({
    required String title,
    required String body,
  }) async {
    await _ensureInit();
    try {
      await _plugin.show(
        99000,
        title,
        body,
        const NotificationDetails(
          android: AndroidNotificationDetails(
            _emergencyChannelId,
            _emergencyChannelName,
            channelDescription: 'Avisos de seguridad y detección de caídas',
            importance: Importance.max,
            priority: Priority.max,
            icon: '@mipmap/ic_launcher',
            color: Color(0xFFE53935),
          ),
        ),
      );
    } catch (e) {
      debugPrint('showEmergencyAlert error: $e');
    }
  }

  /// Notificación de un mensaje nuevo en un grupo (evento) del que el usuario
  /// forma parte. Usa un id estable por evento: los mensajes siguientes del
  /// mismo grupo actualizan la misma notificación en vez de apilarse.
  Future<void> showChatMessage({
    required String eventId,
    required String groupTitle,
    required String sender,
    required String body,
  }) async {
    await _ensureInit();
    try {
      await _plugin.show(
        _chatNotifId(eventId),
        groupTitle,
        '$sender: $body',
        NotificationDetails(
          android: AndroidNotificationDetails(
            _chatChannelId,
            _chatChannelName,
            channelDescription:
                'Avisa cuando alguien escribe en un grupo del que eres parte',
            importance: Importance.high,
            priority: Priority.high,
            icon: '@mipmap/ic_launcher',
            styleInformation: BigTextStyleInformation('$sender: $body'),
          ),
        ),
        payload: 'chat|$eventId|$groupTitle',
      );
    } catch (e) {
      debugPrint('showChatMessage error: $e');
    }
  }

  int _chatNotifId(String eventId) =>
      200000 + (eventId.hashCode.abs() % 700000); // id estable por grupo

  /// Notificación de actividad social: solicitud de seguimiento, aceptación,
  /// like o comentario en un momento.
  Future<void> showSocial({
    required int id,
    required String title,
    required String body,
    required String payload,
  }) async {
    await _ensureInit();
    try {
      await _plugin.show(
        id,
        title,
        body,
        NotificationDetails(
          android: AndroidNotificationDetails(
            _socialChannelId,
            _socialChannelName,
            channelDescription:
                'Solicitudes de seguimiento y actividad en tus momentos',
            importance: Importance.high,
            priority: Priority.high,
            icon: '@mipmap/ic_launcher',
            styleInformation: BigTextStyleInformation(body),
          ),
        ),
        payload: payload,
      );
    } catch (e) {
      debugPrint('showSocial error: $e');
    }
  }

  /// Aviso de que a una bici le toca mantención (lubricar, frenos…).
  Future<void> showMaintenance({
    required int id,
    required String title,
    required String body,
    required String payload,
  }) async {
    await _ensureInit();
    try {
      await _plugin.show(
        id,
        title,
        body,
        NotificationDetails(
          android: AndroidNotificationDetails(
            _maintenanceChannelId,
            _maintenanceChannelName,
            channelDescription:
                'Avisa cuando a tu bici le toca una mantención según sus km',
            importance: Importance.defaultImportance,
            priority: Priority.defaultPriority,
            icon: '@mipmap/ic_launcher',
            styleInformation: BigTextStyleInformation(body),
          ),
        ),
        payload: payload,
      );
    } catch (e) {
      debugPrint('showMaintenance error: $e');
    }
  }

  /// Abre la pantalla correspondiente al tocar una notificación.
  static void _onNotificationTap(NotificationResponse response) {
    final payload = response.payload;
    if (payload == null) return;
    openPayload(payload);
  }

  /// Abre la pantalla que corresponde a un [payload] de notificación (local
  /// o push). Devuelve false si la app aún no tiene Navigator (recién
  /// arrancando) para que quien llama pueda reintentar.
  static bool openPayload(String payload) {
    final nav = appNavigatorKey.currentState;
    if (nav == null) return false;
    final parts = payload.split('|');

    if (payload.startsWith('chat|') && parts.length >= 3) {
      nav.push(MaterialPageRoute(
        builder: (_) => EventChatPage(
          eventId: parts[1],
          eventTitle: parts.sublist(2).join('|'),
        ),
      ));
    } else if (payload == 'follow_req') {
      nav.push(MaterialPageRoute(builder: (_) => const FollowRequestsPage()));
    } else if (payload.startsWith('dm|') && parts.length >= 3) {
      nav.push(MaterialPageRoute(
        builder: (_) => DmThreadPage(
          otherUserId: parts[1],
          otherName: parts.sublist(2).join('|'),
        ),
      ));
    } else if (payload == 'my_impact') {
      nav.push(MaterialPageRoute(builder: (_) => const ProfilePage()));
    } else if (payload.startsWith('bike|') && parts.length >= 2) {
      nav.push(MaterialPageRoute(
        builder: (_) => BikeDetailPage(bikeId: parts[1]),
      ));
    } else if ((payload.startsWith('follow_accept|') ||
            payload.startsWith('post_activity|')) &&
        parts.length >= 2) {
      nav.push(MaterialPageRoute(
        builder: (_) => PublicProfilePage(userId: parts[1]),
      ));
    }
    return true;
  }

  Future<void> _ensureInit() async {
    if (!_initialized) await init();
  }
}

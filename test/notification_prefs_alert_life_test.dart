import 'package:flutter_test/flutter_test.dart';
import 'package:pedalea/services/alert_life.dart';
import 'package:pedalea/services/notification_prefs_service.dart';

void main() {
  group('NotificationPrefs.keyForPayload', () {
    test('mensajes directos y de grupos', () {
      expect(NotificationPrefs.keyForPayload('dm|abc|Ana'), 'messages');
      expect(NotificationPrefs.keyForPayload('chat|ev1|Grupo'), 'messages');
    });
    test('actividad social', () {
      expect(NotificationPrefs.keyForPayload('follow_req|u1'), 'social');
      expect(NotificationPrefs.keyForPayload('follow_accept|u1'), 'social');
      expect(NotificationPrefs.keyForPayload('post_activity|u1'), 'social');
    });
    test('impacto y novedades', () {
      expect(NotificationPrefs.keyForPayload('my_impact'), 'impact');
      expect(NotificationPrefs.keyForPayload('plus_promo'), 'news');
    });
    test('tipos sin preferencia siempre se muestran', () {
      expect(NotificationPrefs.keyForPayload('sos'), isNull);
      expect(NotificationPrefs.allowsPayload('sos'), isTrue);
    });
    test('un tipo apagado no se muestra', () {
      NotificationPrefs.prefs.value = {
        ...NotificationPrefs.prefs.value,
        'social': false,
      };
      expect(NotificationPrefs.allowsPayload('follow_req|u1'), isFalse);
      expect(NotificationPrefs.allowsPayload('dm|u1|Ana'), isTrue);
    });
  });

  group('AlertLife', () {
    final now = DateTime(2026, 11, 27, 12);
    Map<String, dynamic> alert(String type, Duration age,
            {Duration? confirmedAgo, int up = 0, int down = 0}) =>
        {
          'type': type,
          'created_at': now.subtract(age).toUtc().toIso8601String(),
          if (confirmedAgo != null)
            'confirmed_at': now.subtract(confirmedAgo).toUtc().toIso8601String(),
          'votes_up': up,
          'votes_down': down,
        };

    test('un accidente vence a las 24 h', () {
      expect(AlertLife.isExpired(alert('accident', const Duration(hours: 23)), now: now), isFalse);
      expect(AlertLife.isExpired(alert('accident', const Duration(hours: 25)), now: now), isTrue);
    });
    test('las obras duran 21 días', () {
      expect(AlertLife.isExpired(alert('construction', const Duration(days: 20)), now: now), isFalse);
      expect(AlertLife.isExpired(alert('construction', const Duration(days: 22)), now: now), isTrue);
    });
    test('confirmar «Sigue ahí» renueva la vigencia', () {
      final a = alert('theft', const Duration(hours: 60),
          confirmedAgo: const Duration(hours: 2));
      expect(AlertLife.isExpired(a, now: now), isFalse);
    });
    test('3 «Ya no está» (más que «Sigue ahí») la quitan', () {
      expect(AlertLife.isExpired(alert('danger', const Duration(hours: 1), down: 3), now: now), isTrue);
      expect(AlertLife.isExpired(alert('danger', const Duration(hours: 1), up: 4, down: 3), now: now), isFalse);
      expect(AlertLife.isExpired(alert('danger', const Duration(hours: 1), down: 2), now: now), isFalse);
    });
  });
}

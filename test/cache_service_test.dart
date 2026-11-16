import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pedalea/services/cache_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    // Estado limpio de SharedPreferences antes de cada test.
    SharedPreferences.setMockInitialValues({});
    await CacheService.init();
  });

  final sampleAlerts = [
    {'id': '1', 'title': 'Bache', 'type': 'danger'},
    {'id': '2', 'title': 'Robo', 'type': 'theft'},
  ];

  group('CacheService alertas', () {
    test('guarda y recupera alertas', () async {
      await CacheService.saveAlerts(sampleAlerts);
      final loaded = CacheService.loadAlerts(ignoreExpiry: true);
      expect(loaded, isNotNull);
      expect(loaded!.length, 2);
      expect(loaded.first['title'], 'Bache');
    });

    test('sin datos devuelve null', () {
      expect(CacheService.loadAlerts(ignoreExpiry: true), isNull);
    });

    test('recién guardado no está expirado', () async {
      await CacheService.saveAlerts(sampleAlerts);
      expect(CacheService.loadAlerts(ignoreExpiry: false), isNotNull);
    });
  });

  group('CacheService eventos', () {
    test('guarda y recupera eventos', () async {
      final events = [
        {'id': 'e1', 'title': 'Cleta nocturna'},
      ];
      await CacheService.saveEvents(events);
      final loaded = CacheService.loadEvents(ignoreExpiry: true);
      expect(loaded, isNotNull);
      expect(loaded!.single['title'], 'Cleta nocturna');
    });
  });

  group('CacheService ciclovías', () {
    test('ya no se guardan en preferencias (vienen incluidas en la app)', () async {
      await CacheService.saveCiclovias('{"type":"FeatureCollection","features":[]}');
      expect(CacheService.loadCiclovias(), isNull);
    });

    test('init borra la copia antigua de 3,6 MB', () async {
      SharedPreferences.setMockInitialValues({'cache_ciclovias_v2': '{"x":1}'});
      await CacheService.init();
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.containsKey('cache_ciclovias_v2'), isFalse);
    });
  });

  group('CacheService.clearAll', () {
    test('borra alertas y eventos', () async {
      await CacheService.saveAlerts(sampleAlerts);
      await CacheService.saveEvents([
        {'id': 'e1'},
      ]);
      await CacheService.clearAll();

      expect(CacheService.loadAlerts(ignoreExpiry: true), isNull);
      expect(CacheService.loadEvents(ignoreExpiry: true), isNull);
    });
  });
}

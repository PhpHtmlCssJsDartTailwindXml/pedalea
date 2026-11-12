import 'package:flutter_test/flutter_test.dart';
import 'package:pedalea/services/alert_impact_service.dart';
import 'package:pedalea/services/bike_service.dart';

Map<String, dynamic> _bikeRow({
  String id = 'b1',
  String name = 'La Negra',
  String type = 'ruta',
  num baseKm = 0,
  num appKm = 0,
  bool active = false,
  String createdAt = '2026-11-01T10:00:00Z',
  List<Map<String, dynamic>> maintenance = const [],
}) => {
  'id': id,
  'name': name,
  'type': type,
  'photo_url': null,
  'base_km': baseKm,
  'app_km': appKm,
  'is_active': active,
  'created_at': createdAt,
  'bike_maintenance': maintenance,
};

Map<String, dynamic> _maint(String kind, num interval, num lastDone) => {
  'id': 'm-$kind',
  'kind': kind,
  'interval_km': interval,
  'last_done_km': lastDone,
  'last_done_at': null,
};

void main() {
  group('BikeService.maintenanceProgress', () {
    test('recién hecha es 0 y a mitad de intervalo es 0,5', () {
      expect(BikeService.maintenanceProgress(100, 100, 300), 0);
      expect(BikeService.maintenanceProgress(250, 100, 300), closeTo(0.5, 1e-9));
    });

    test('se limita a 1 cuando ya pasó el intervalo', () {
      expect(BikeService.maintenanceProgress(900, 100, 300), 1);
    });

    test('intervalo inválido no divide por cero', () {
      expect(BikeService.maintenanceProgress(500, 0, 0), 0);
    });
  });

  group('Maintenance', () {
    test('faltan km y no está pendiente antes del intervalo', () {
      final m = Maintenance.fromMap(_maint('chain', 1500, 200));
      expect(m.remainingKm(1000), 700);
      expect(m.isDue(1000), isFalse);
    });

    test('queda pendiente justo al cumplir el intervalo', () {
      final m = Maintenance.fromMap(_maint('lube', 300, 0));
      expect(m.isDue(299.9), isFalse);
      expect(m.isDue(300), isTrue);
    });
  });

  group('Bike', () {
    test('el odómetro suma km previos y km de la app', () {
      final b = Bike.fromMap(_bikeRow(baseKm: 1200, appKm: 34.5));
      expect(b.odometerKm, 1234.5);
    });

    test('lee el tipo y usa urbana si viene uno desconocido', () {
      expect(Bike.fromMap(_bikeRow(type: 'montana')).type, BikeType.montana);
      expect(Bike.fromMap(_bikeRow(type: 'patineta')).type, BikeType.urbana);
    });

    test('lista solo las mantenciones pendientes, en orden fijo', () {
      final b = Bike.fromMap(_bikeRow(
        baseKm: 0,
        appKm: 1600,
        maintenance: [
          _maint('tires', 3000, 0),
          _maint('chain', 1500, 0),
          _maint('lube', 300, 1500),
        ],
      ));
      expect(b.maintenance.map((m) => m.kind).toList(),
          [MaintenanceKind.lube, MaintenanceKind.chain, MaintenanceKind.tires]);
      expect(b.dueMaintenance.map((m) => m.kind).toList(), [MaintenanceKind.chain]);
    });
  });

  group('BikeService.sortBikes', () {
    test('la activa va primero y el resto por fecha', () {
      final list = [
        Bike.fromMap(_bikeRow(id: 'a', createdAt: '2026-10-01T00:00:00Z')),
        Bike.fromMap(_bikeRow(id: 'b', createdAt: '2026-09-01T00:00:00Z')),
        Bike.fromMap(_bikeRow(id: 'c', createdAt: '2026-11-01T00:00:00Z', active: true)),
      ];
      expect(BikeService.sortBikes(list).map((b) => b.id).toList(), ['c', 'b', 'a']);
    });
  });

  group('BikeService.maintenanceMessage', () {
    test('nombra la bici, sus km y la acción', () {
      expect(
        BikeService.maintenanceMessage('La Negra', 1503.7, MaintenanceKind.chain),
        '"La Negra" lleva 1504 km: toca revisar el desgaste de la cadena.',
      );
    });
  });

  group('AlertImpact', () {
    test('sin ciclistas no muestra frase', () {
      expect(AlertImpact.empty.headline, isNull);
    });

    test('usa singular y plural', () {
      expect(AlertImpact.fromMap({'total': 1}).headline,
          'Tus reportes ayudaron a 1 ciclista');
      expect(AlertImpact.fromMap({'total': 34, 'week': 5, 'alerts': 2}).headline,
          'Tus reportes ayudaron a 34 ciclistas');
    });
  });
}

import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'notification_service.dart';

/// Tipos de bici que se pueden registrar.
enum BikeType { ruta, urbana, montana, electrica, otra }

extension BikeTypeInfo on BikeType {
  String get label => switch (this) {
    BikeType.ruta => 'Ruta',
    BikeType.urbana => 'Urbana',
    BikeType.montana => 'Montaña',
    BikeType.electrica => 'Eléctrica',
    BikeType.otra => 'Otra',
  };

  String get emoji => switch (this) {
    BikeType.ruta => '🚴',
    BikeType.urbana => '🚲',
    BikeType.montana => '🚵',
    BikeType.electrica => '⚡',
    BikeType.otra => '🛞',
  };

  static BikeType parse(String? s) => BikeType.values.firstWhere(
    (t) => t.name == s,
    orElse: () => BikeType.urbana,
  );
}

/// Tipos de mantención, con su intervalo de referencia en km.
enum MaintenanceKind { lube, brakes, chain, tires }

extension MaintenanceKindInfo on MaintenanceKind {
  String get label => switch (this) {
    MaintenanceKind.lube => 'Lubricar cadena',
    MaintenanceKind.brakes => 'Revisar frenos',
    MaintenanceKind.chain => 'Revisar desgaste de cadena',
    MaintenanceKind.tires => 'Revisar neumáticos',
  };

  /// Cómo se nombra dentro de una frase: "toca revisar la cadena".
  String get action => switch (this) {
    MaintenanceKind.lube => 'lubricar la cadena',
    MaintenanceKind.brakes => 'revisar los frenos',
    MaintenanceKind.chain => 'revisar el desgaste de la cadena',
    MaintenanceKind.tires => 'revisar los neumáticos',
  };

  double get defaultIntervalKm => switch (this) {
    MaintenanceKind.lube => 300,
    MaintenanceKind.brakes => 1000,
    MaintenanceKind.chain => 1500,
    MaintenanceKind.tires => 3000,
  };

  static MaintenanceKind? parse(String? s) {
    for (final k in MaintenanceKind.values) {
      if (k.name == s) return k;
    }
    return null;
  }
}

class Maintenance {
  final String id;
  final MaintenanceKind kind;
  final double intervalKm;
  final double lastDoneKm;
  final DateTime? lastDoneAt;

  const Maintenance({
    required this.id,
    required this.kind,
    required this.intervalKm,
    required this.lastDoneKm,
    this.lastDoneAt,
  });

  factory Maintenance.fromMap(Map<String, dynamic> m) => Maintenance(
    id: m['id'] as String,
    kind: MaintenanceKindInfo.parse(m['kind'] as String?) ?? MaintenanceKind.lube,
    intervalKm: (m['interval_km'] as num?)?.toDouble() ?? 0,
    lastDoneKm: (m['last_done_km'] as num?)?.toDouble() ?? 0,
    lastDoneAt: DateTime.tryParse(m['last_done_at'] as String? ?? ''),
  );

  /// Avance hacia la próxima mantención (0 = recién hecha, 1 = toca hacerla).
  double progress(double odometerKm) =>
      BikeService.maintenanceProgress(odometerKm, lastDoneKm, intervalKm);

  /// Km que faltan (negativo si ya pasó).
  double remainingKm(double odometerKm) =>
      intervalKm - (odometerKm - lastDoneKm);

  bool isDue(double odometerKm) => remainingKm(odometerKm) <= 0;
}

class Bike {
  final String id;
  final String name;
  final BikeType type;
  final String? photoUrl;
  final double baseKm; // km que ya tenía al registrarla
  final double appKm; // km pedaleados con la app
  final bool isActive;
  final DateTime createdAt;
  final List<Maintenance> maintenance;

  const Bike({
    required this.id,
    required this.name,
    required this.type,
    required this.photoUrl,
    required this.baseKm,
    required this.appKm,
    required this.isActive,
    required this.createdAt,
    required this.maintenance,
  });

  /// Kilometraje total de la bici.
  double get odometerKm => baseKm + appKm;

  List<Maintenance> get dueMaintenance =>
      maintenance.where((m) => m.isDue(odometerKm)).toList();

  factory Bike.fromMap(Map<String, dynamic> m) {
    final maint = ((m['bike_maintenance'] as List?) ?? const [])
        .cast<Map<String, dynamic>>()
        .map(Maintenance.fromMap)
        .toList()
      ..sort((a, b) => a.kind.index.compareTo(b.kind.index));
    return Bike(
      id: m['id'] as String,
      name: (m['name'] as String?) ?? 'Mi bici',
      type: BikeTypeInfo.parse(m['type'] as String?),
      photoUrl: m['photo_url'] as String?,
      baseKm: (m['base_km'] as num?)?.toDouble() ?? 0,
      appKm: (m['app_km'] as num?)?.toDouble() ?? 0,
      isActive: m['is_active'] == true,
      createdAt: DateTime.tryParse(m['created_at'] as String? ?? '') ??
          DateTime.now(),
      maintenance: maint,
    );
  }
}

/// Error al registrar una bici más de las que permite el plan gratis.
class BikeLimitException implements Exception {
  const BikeLimitException();
}

/// "Mis bicis": registro de bicis, km por bici y avisos de mantención.
///
/// Los datos viven en Supabase (`bikes`, `bike_maintenance`). Los km se suman
/// a la bici activa con el RPC `add_bike_km`, que además devuelve las
/// mantenciones que se acaban de cumplir para avisar con una notificación.
class BikeService {
  BikeService._();
  static final BikeService instance = BikeService._();

  SupabaseClient get _sb => Supabase.instance.client;

  /// Bicis del usuario, la activa primero. Vacía si no tiene o si la función
  /// aún no está disponible en el servidor.
  final ValueNotifier<List<Bike>> bikes = ValueNotifier(const []);

  Bike? get activeBike {
    for (final b in bikes.value) {
      if (b.isActive) return b;
    }
    return bikes.value.isEmpty ? null : bikes.value.first;
  }

  // ── Lógica pura (con pruebas en test/bike_service_test.dart) ──────────

  /// Avance de una mantención entre 0 y 1.
  static double maintenanceProgress(
    double odometerKm,
    double lastDoneKm,
    double intervalKm,
  ) {
    if (intervalKm <= 0) return 0;
    return ((odometerKm - lastDoneKm) / intervalKm).clamp(0.0, 1.0);
  }

  /// Texto del aviso de mantención.
  static String maintenanceMessage(
    String bikeName,
    double odometerKm,
    MaintenanceKind kind,
  ) =>
      '"$bikeName" lleva ${odometerKm.toStringAsFixed(0)} km: '
      'toca ${kind.action}.';

  /// Ordena: la activa primero, luego por fecha de registro.
  static List<Bike> sortBikes(List<Bike> list) => [...list]
    ..sort((a, b) {
      if (a.isActive != b.isActive) return a.isActive ? -1 : 1;
      return a.createdAt.compareTo(b.createdAt);
    });

  // ── Datos ──────────────────────────────────────────────────────────────

  Future<List<Bike>> load() async {
    if (_sb.auth.currentUser == null) {
      bikes.value = const [];
      return const [];
    }
    try {
      final rows = await _sb
          .from('bikes')
          .select('*, bike_maintenance(*)')
          .order('created_at');
      final list = sortBikes(
        (rows as List).cast<Map<String, dynamic>>().map(Bike.fromMap).toList(),
      );
      bikes.value = list;
      return list;
    } catch (e) {
      debugPrint('BikeService.load: $e');
      return bikes.value;
    }
  }

  Future<String?> uploadPhoto(File file) async {
    final uid = _sb.auth.currentUser?.id;
    if (uid == null) return null;
    final path = '$uid/bikes/${DateTime.now().millisecondsSinceEpoch}.jpg';
    await _sb.storage.from('post-images').upload(path, file);
    return _sb.storage.from('post-images').getPublicUrl(path);
  }

  Future<void> create({
    required String name,
    required BikeType type,
    double baseKm = 0,
    String? photoUrl,
  }) async {
    try {
      await _sb.from('bikes').insert({
        'name': name.trim(),
        'type': type.name,
        'base_km': baseKm,
        'photo_url': ?photoUrl,
      });
    } on PostgrestException catch (e) {
      if (e.message.contains('bike_limit_free')) {
        throw const BikeLimitException();
      }
      rethrow;
    }
    await load();
  }

  Future<void> update(
    String id, {
    required String name,
    required BikeType type,
    required double baseKm,
    String? photoUrl,
  }) async {
    await _sb.from('bikes').update({
      'name': name.trim(),
      'type': type.name,
      'base_km': baseKm,
      'photo_url': ?photoUrl,
    }).eq('id', id);
    await load();
  }

  Future<void> delete(String id) async {
    final wasActive = bikes.value.any((b) => b.id == id && b.isActive);
    await _sb.from('bikes').delete().eq('id', id);
    await load();
    // Si se borró la activa, pasa a serlo la siguiente.
    if (wasActive && bikes.value.isNotEmpty) {
      await setActive(bikes.value.first.id);
    }
  }

  Future<void> setActive(String id) async {
    await _sb.rpc('set_active_bike', params: {'p_bike': id});
    await load();
  }

  Future<void> setInterval(String maintenanceId, double km) async {
    await _sb
        .from('bike_maintenance')
        .update({'interval_km': km, 'notified': false})
        .eq('id', maintenanceId);
    await load();
  }

  Future<void> markDone(String maintenanceId) async {
    await _sb.rpc('mark_maintenance_done', params: {'p_id': maintenanceId});
    await load();
  }

  /// Suma km a la bici activa (se llama junto con el guardado de km del
  /// perfil) y avisa si se cumplió alguna mantención.
  Future<void> addKm(double km) async {
    if (km <= 0 || _sb.auth.currentUser == null) return;
    try {
      final res = await _sb.rpc('add_bike_km', params: {'p_km': km});
      if (res is! Map) return;
      final name = res['name'] as String? ?? 'Tu bici';
      final odo = (res['odometer'] as num?)?.toDouble() ?? 0;
      final bikeId = res['bike_id'] as String? ?? '';
      for (final d in (res['due'] as List? ?? const [])) {
        final kind = MaintenanceKindInfo.parse((d as Map)['kind'] as String?);
        if (kind == null) continue;
        await NotificationService.instance.showMaintenance(
          id: 320000 + ((bikeId + kind.name).hashCode.abs() % 40000),
          title: '🔧 Toca mantención: ${kind.label}',
          body: maintenanceMessage(name, odo, kind),
          payload: 'bike|$bikeId',
        );
      }
      // Refresca el odómetro en memoria sin otra consulta completa.
      bikes.value = [
        for (final b in bikes.value)
          if (b.id == bikeId)
            Bike(
              id: b.id,
              name: b.name,
              type: b.type,
              photoUrl: b.photoUrl,
              baseKm: b.baseKm,
              appKm: odo - b.baseKm,
              isActive: b.isActive,
              createdAt: b.createdAt,
              maintenance: b.maintenance,
            )
          else
            b,
      ];
    } catch (e) {
      debugPrint('BikeService.addKm: $e'); // sin bicis o función no instalada
    }
  }
}

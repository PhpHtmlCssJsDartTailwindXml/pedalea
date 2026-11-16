import 'dart:async';
import 'dart:collection';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:sensors_plus/sensors_plus.dart';

/// Detector del PATRÓN de golpe, con lógica pura (sin sensores), para poder
/// probarlo alimentándolo con muestras de magnitud.
///
/// Patrón clásico de caída de un ciclista:
///   1. Caída libre breve → la magnitud de la aceleración cae cerca de 0.
///   2. Impacto contra el suelo → pico fuerte de magnitud.
/// También reconoce un impacto muy fuerte aunque no haya caída libre previa.
///
/// Ojo: esto solo detecta un GOLPE. Que el golpe sea una caída lo decide
/// [FallAnalyzer] mirando qué pasó antes y después (velocidad, orientación,
/// quietud y giro del teléfono).
class FallDetector {
  FallDetector({
    this.freeFallThreshold = 2.0, // m/s² (en reposo la magnitud ≈ 9.8)
    this.impactThreshold = 34.0, // m/s² pico tras la caída
    this.hardImpactThreshold = 50.0, // m/s² golpe seco directo
    this.freeFallWindow = const Duration(milliseconds: 1200),
  });

  final double freeFallThreshold;
  final double impactThreshold;
  final double hardImpactThreshold;
  final Duration freeFallWindow;

  DateTime? _lastFreeFall;

  /// Tipo del último golpe reconocido por [process].
  FallTrigger lastTrigger = FallTrigger.impact;

  /// Magnitud euclidiana del vector de aceleración.
  static double magnitude(double x, double y, double z) =>
      math.sqrt(x * x + y * y + z * z);

  /// Procesa una muestra de magnitud en el instante [now]. Devuelve `true` si
  /// se reconoce un golpe compatible con una caída. Luego se reinicia.
  bool process(double mag, DateTime now) {
    // Golpe seco directo: impacto extremo sin requerir caída libre previa.
    if (mag >= hardImpactThreshold) {
      _lastFreeFall = null;
      lastTrigger = FallTrigger.hardImpact;
      return true;
    }

    // Fase 1: caída libre.
    if (mag < freeFallThreshold) {
      _lastFreeFall = now;
      return false;
    }

    // Fase 2: impacto dentro de la ventana posterior a una caída libre.
    if (mag >= impactThreshold && _lastFreeFall != null) {
      if (now.difference(_lastFreeFall!) <= freeFallWindow) {
        _lastFreeFall = null;
        lastTrigger = FallTrigger.impact;
        return true;
      }
    }
    return false;
  }

  void reset() => _lastFreeFall = null;
}

/// Qué originó la sospecha de caída.
enum FallTrigger {
  /// Caída libre seguida de impacto.
  impact,

  /// Golpe seco muy fuerte (≥ 5 g).
  hardImpact,

  /// Frenada imposible según el GPS (el teléfono pudo no recibir el golpe,
  /// por ejemplo si va en un soporte del manubrio).
  suddenStop,
}

/// Todo lo que se midió alrededor de un golpe y la decisión tomada. Sirve
/// para explicar la alerta y para ajustar los umbrales con casos reales.
class FallEvidence {
  FallEvidence({
    required this.trigger,
    required this.at,
    required this.confirmed,
    required this.reason,
    required this.strict,
    this.peakAccel,
    this.peakGyro,
    this.speedBeforeKmh,
    this.speedAfterKmh,
    this.orientationChangeDeg,
    this.stillnessStd,
  });

  final FallTrigger trigger;
  final DateTime at;

  /// `true` → se avisa al ciclista (cuenta regresiva). `false` → descartado.
  final bool confirmed;

  /// Motivo de la decisión (texto corto, en español, para registro).
  final String reason;

  /// Sin datos de GPS se exigen más señales físicas (modo estricto).
  final bool strict;

  final double? peakAccel; // m/s²
  final double? peakGyro; // rad/s
  final double? speedBeforeKmh;
  final double? speedAfterKmh;
  final double? orientationChangeDeg;
  final double? stillnessStd; // m/s² (desviación de la magnitud tras el golpe)

  Map<String, dynamic> toJson() => {
    'trigger': trigger.name,
    'confirmed': confirmed,
    'reason': reason,
    'strict': strict,
    'peak_accel': _r(peakAccel),
    'peak_gyro': _r(peakGyro),
    'speed_before': _r(speedBeforeKmh),
    'speed_after': _r(speedAfterKmh),
    'orientation_change': _r(orientationChangeDeg),
    'stillness': _r(stillnessStd),
  };

  static double? _r(double? v) =>
      v == null || v.isNaN || v.isInfinite ? null : (v * 100).round() / 100;

  @override
  String toString() => 'FallEvidence(${toJson()})';
}

class _Vec {
  const _Vec(this.t, this.x, this.y, this.z);
  final DateTime t;
  final double x, y, z;
  double get mag => FallDetector.magnitude(x, y, z);
}

class _Scalar {
  const _Scalar(this.t, this.v);
  final DateTime t;
  final double v;
}

class _Pending {
  _Pending(this.trigger, this.at, this.peak);
  final FallTrigger trigger;
  final DateTime at;
  final double? peak;
}

/// Decide si un golpe fue realmente una caída, con lógica pura (sin
/// sensores ni temporizadores reales) para poder probarla.
///
/// Una caída se confirma solo si se cumplen las tres condiciones:
///  1. **Ibas pedaleando**: el GPS marcó ≥ [ridingSpeedKmh] en los segundos
///     previos. Con el teléfono en la mesa, el bolsillo o caminando, no hay
///     alerta.
///  2. **Hubo un golpe** (o una frenada imposible según el GPS).
///  3. **Después te detuviste**: la velocidad cae bajo [stoppedSpeedKmh] y
///     el teléfono muestra señales físicas de caída: cambió de orientación
///     (quedó de lado), quedó quieto en el suelo o giró bruscamente.
///     Si sigues avanzando, era un bache y se descarta.
class FallAnalyzer {
  FallAnalyzer({
    this.ridingSpeedKmh = 10,
    this.stoppedSpeedKmh = 5,
    this.ridingLookback = const Duration(seconds: 8),
    this.gpsMemory = const Duration(seconds: 30),
    this.settleDelay = const Duration(milliseconds: 1500),
    this.confirmWindow = const Duration(seconds: 7),
    this.stillStd = 1.5,
    this.lyingStd = 0.3,
    this.orientationDeg = 40,
    this.gyroSpikeRad = 5.0,
  });

  final double ridingSpeedKmh;
  final double stoppedSpeedKmh;
  final Duration ridingLookback;

  /// Si no hubo ningún dato de GPS en este tiempo, no se sabe si ibas
  /// pedaleando y se usa el modo estricto.
  final Duration gpsMemory;

  /// Se ignora lo que pasa justo después del golpe (rebotes, deslizamiento).
  final Duration settleDelay;

  /// Tiempo que se observa después del golpe antes de decidir.
  final Duration confirmWindow;

  final double stillStd;

  /// Quietud casi total (tendido en el suelo), más exigente que [stillStd].
  final double lyingStd;
  final double orientationDeg;
  final double gyroSpikeRad;

  static const _keep = Duration(seconds: 40);

  final _accel = ListQueue<_Vec>();
  final _gyro = ListQueue<_Scalar>();
  final _speed = ListQueue<_Scalar>();
  _Pending? _pending;

  bool get hasPending => _pending != null;

  void addAccel(double x, double y, double z, DateTime t) {
    _accel.add(_Vec(t, x, y, z));
    _trim(_accel, t, (e) => e.t);
  }

  void addGyro(double x, double y, double z, DateTime t) {
    _gyro.add(_Scalar(t, FallDetector.magnitude(x, y, z)));
    _trim(_gyro, t, (e) => e.t);
  }

  void addSpeed(double kmh, DateTime t) {
    if (kmh.isNaN || kmh < 0) kmh = 0;
    _speed.add(_Scalar(t, kmh));
    _trim(_speed, t, (e) => e.t);
  }

  void _trim<T>(ListQueue<T> q, DateTime now, DateTime Function(T) at) {
    while (q.isNotEmpty && now.difference(at(q.first)) > _keep) {
      q.removeFirst();
    }
  }

  bool _hasGps(DateTime t) =>
      _speed.any((s) => !s.t.isAfter(t) && t.difference(s.t) <= gpsMemory);

  double? _maxSpeedBefore(DateTime t) {
    double? best;
    for (final s in _speed) {
      if (s.t.isAfter(t) || t.difference(s.t) > ridingLookback) continue;
      if (best == null || s.v > best) best = s.v;
    }
    return best;
  }

  /// Registra una sospecha. Devuelve la evidencia si se descarta de inmediato
  /// (no ibas pedaleando) o `null` si queda en observación.
  FallEvidence? startCandidate(FallTrigger trigger, DateTime t, {double? peak}) {
    if (_pending != null) return null; // ya se está observando un golpe
    final gps = _hasGps(t);
    final before = _maxSpeedBefore(t);
    if (trigger == FallTrigger.suddenStop && !gps) return null;
    if (gps && (before == null || before < ridingSpeedKmh)) {
      return FallEvidence(
        trigger: trigger,
        at: t,
        confirmed: false,
        reason: 'no_pedaleando',
        strict: false,
        peakAccel: peak,
        speedBeforeKmh: before,
      );
    }
    _pending = _Pending(trigger, t, peak);
    return null;
  }

  /// Revisa el golpe en observación. Devuelve la decisión cuando la hay
  /// (confirmada o descartada) y `null` mientras sigue observando.
  FallEvidence? evaluate(DateTime now) {
    final p = _pending;
    if (p == null) return null;
    final settleAt = p.at.add(settleDelay);

    // Si después del golpe vuelves a ir a velocidad de pedaleo, era un bache.
    final resumed = _speed.where(
      (s) => s.t.isAfter(p.at.add(const Duration(seconds: 2))) &&
          !s.t.isAfter(now) &&
          s.v >= ridingSpeedKmh,
    );
    if (resumed.length >= 2) {
      _pending = null;
      return _build(p, now, confirmed: false, reason: 'siguio_pedaleando');
    }

    if (now.difference(p.at) < confirmWindow) return null;
    _pending = null;

    final strict = !_hasGps(p.at);
    final speedAfter = _medianSpeed(p.at.add(const Duration(seconds: 2)), now);
    final orient = _orientationChange(p.at, settleAt, now);
    final still = _stillness(settleAt, now);
    final gyroPeak = _gyroPeak(p.at);

    final stopped = speedAfter == null || speedAfter < stoppedSpeedKmh;
    final turned = orient != null && orient >= orientationDeg;
    final isStill = still != null && still < stillStd;
    final spun = gyroPeak != null && gyroPeak >= gyroSpikeRad;

    String? fail;
    if (!stopped) {
      fail = 'no_se_detuvo';
    } else if (strict) {
      // Sin GPS no se sabe si ibas en bici: se exige quedar de lado y quieto.
      if (!(turned && isStill)) fail = 'sin_gps_pocas_senales';
    } else {
      switch (p.trigger) {
        case FallTrigger.hardImpact:
          // Quedar tendido es mucho más quieto que estar de pie esperando
          // un semáforo: aquí se pide una quietud casi total.
          final lying = still != null && still < lyingStd;
          if (!(turned || spun || lying)) fail = 'sin_senales_fisicas';
        case FallTrigger.impact:
          if (!(turned || (isStill && spun))) fail = 'sin_senales_fisicas';
        case FallTrigger.suddenStop:
          // Frenar fuerte en un semáforo también te deja quieto: aquí se
          // exige que el teléfono haya cambiado de posición o girado.
          if (!(turned || spun)) fail = 'frenada_sin_caida';
      }
    }

    return _build(
      p,
      now,
      confirmed: fail == null,
      reason: fail ?? 'caida_confirmada',
      strict: strict,
      speedAfter: speedAfter,
      orient: orient,
      still: still,
      gyroPeak: gyroPeak,
    );
  }

  FallEvidence _build(
    _Pending p,
    DateTime now, {
    required bool confirmed,
    required String reason,
    bool strict = false,
    double? speedAfter,
    double? orient,
    double? still,
    double? gyroPeak,
  }) {
    return FallEvidence(
      trigger: p.trigger,
      at: p.at,
      confirmed: confirmed,
      reason: reason,
      strict: strict,
      peakAccel: p.peak,
      peakGyro: gyroPeak ?? _gyroPeak(p.at),
      speedBeforeKmh: _maxSpeedBefore(p.at),
      speedAfterKmh: speedAfter,
      orientationChangeDeg: orient,
      stillnessStd: still,
    );
  }

  double? _medianSpeed(DateTime from, DateTime to) {
    final v = _speed
        .where((s) => s.t.isAfter(from) && !s.t.isAfter(to))
        .map((s) => s.v)
        .toList()
      ..sort();
    if (v.isEmpty) return null;
    return v[v.length ~/ 2];
  }

  /// Ángulo entre la gravedad promedio antes y después del golpe.
  double? _orientationChange(DateTime at, DateTime settleAt, DateTime now) {
    final before = _avg(
      at.subtract(const Duration(seconds: 3)),
      at.subtract(const Duration(milliseconds: 300)),
    );
    final after = _avg(settleAt, now);
    if (before == null || after == null) return null;
    final dot = before.x * after.x + before.y * after.y + before.z * after.z;
    final den = before.mag * after.mag;
    if (den == 0) return null;
    final c = (dot / den).clamp(-1.0, 1.0);
    return math.acos(c) * 180 / math.pi;
  }

  _Vec? _avg(DateTime from, DateTime to) {
    var n = 0;
    var x = 0.0, y = 0.0, z = 0.0;
    for (final a in _accel) {
      if (a.t.isBefore(from) || a.t.isAfter(to)) continue;
      x += a.x;
      y += a.y;
      z += a.z;
      n++;
    }
    if (n < 3) return null;
    return _Vec(to, x / n, y / n, z / n);
  }

  double? _stillness(DateTime from, DateTime to) {
    final m = _accel
        .where((a) => !a.t.isBefore(from) && !a.t.isAfter(to))
        .map((a) => a.mag)
        .toList();
    if (m.length < 5) return null;
    final mean = m.reduce((a, b) => a + b) / m.length;
    final varc =
        m.map((v) => (v - mean) * (v - mean)).reduce((a, b) => a + b) /
        m.length;
    return math.sqrt(varc);
  }

  double? _gyroPeak(DateTime at) {
    double? best;
    for (final g in _gyro) {
      if (g.t.difference(at).inMilliseconds.abs() > 1500) continue;
      if (best == null || g.v > best) best = g.v;
    }
    return best;
  }

  void reset() {
    _pending = null;
    _accel.clear();
    _gyro.clear();
    _speed.clear();
  }
}

/// Conecta el detector y el analizador a los sensores del teléfono (acelerómetro,
/// giroscopio) y a la velocidad del GPS que le entrega el mapa. Avisa con
/// [start]'s `onFall` solo cuando la caída queda confirmada.
class FallDetectionService {
  /// [events], [gyroEvents] y [clock] permiten inyectar sensores y reloj en
  /// las pruebas; por defecto se usan los sensores reales y la hora actual.
  FallDetectionService({
    FallDetector? detector,
    FallAnalyzer? analyzer,
    Stream<AccelerometerEvent>? events,
    Stream<GyroscopeEvent>? gyroEvents,
    DateTime Function()? clock,
    bool useTimer = true,
  }) : _detector = detector ?? FallDetector(),
       _analyzer = analyzer ?? FallAnalyzer(),
       _events = events,
       _gyroEvents = gyroEvents,
       _clock = clock ?? DateTime.now,
       _useTimer = useTimer;

  final FallDetector _detector;
  final FallAnalyzer _analyzer;
  final Stream<AccelerometerEvent>? _events;
  final Stream<GyroscopeEvent>? _gyroEvents;
  final DateTime Function() _clock;
  final bool _useTimer;

  StreamSubscription<AccelerometerEvent>? _sub;
  StreamSubscription<GyroscopeEvent>? _gyroSub;
  Timer? _timer;
  DateTime? _lastTrigger;
  VoidCallback? _onFall;
  void Function(FallEvidence)? _onEvidence;

  /// Lo que se midió en la última caída confirmada (para el diálogo y el
  /// registro de falsas alarmas).
  FallEvidence? lastEvidence;

  bool get isRunning => _sub != null;

  static const Duration _cooldown = Duration(seconds: 20);

  /// Comienza a escuchar. [onFall] se invoca solo con caídas confirmadas;
  /// [onEvidence] recibe además los golpes descartados (para registro).
  void start(VoidCallback onFall, {void Function(FallEvidence)? onEvidence}) {
    _onFall = onFall;
    _onEvidence = onEvidence;
    if (_sub != null) return;
    _detector.reset();
    try {
      final stream =
          _events ??
          accelerometerEventStream(samplingPeriod: SensorInterval.gameInterval);
      _sub = stream.listen(
        _onAccel,
        onError: (e) => debugPrint('FallDetectionService error: $e'),
      );
    } catch (e) {
      debugPrint('No se pudo iniciar el acelerómetro: $e');
    }
    try {
      final g =
          _gyroEvents ??
          gyroscopeEventStream(samplingPeriod: SensorInterval.gameInterval);
      _gyroSub = g.listen(
        (e) => _analyzer.addGyro(e.x, e.y, e.z, _clock()),
        onError: (e) => debugPrint('Giroscopio no disponible: $e'),
      );
    } catch (e) {
      // Algunos teléfonos baratos no tienen giroscopio: se sigue sin él.
      debugPrint('No se pudo iniciar el giroscopio: $e');
    }
    if (_useTimer) {
      _timer = Timer.periodic(const Duration(milliseconds: 500), (_) => tick());
    }
  }

  void _onAccel(AccelerometerEvent event) {
    final now = _clock();
    _analyzer.addAccel(event.x, event.y, event.z, now);
    final mag = FallDetector.magnitude(event.x, event.y, event.z);
    if (_detector.process(mag, now)) {
      _candidate(_detector.lastTrigger, now, mag);
    }
    tick();
  }

  /// Velocidad actual según el GPS (km/h). El mapa la entrega en cada fix.
  void reportSpeed(double kmh) {
    if (!isRunning) return;
    _analyzer.addSpeed(kmh, _clock());
  }

  /// Frenada imposible detectada por el GPS: queda en observación igual
  /// que un golpe, no alerta por sí sola.
  void reportSuddenStop() {
    if (!isRunning) return;
    _candidate(FallTrigger.suddenStop, _clock(), null);
  }

  void _candidate(FallTrigger trigger, DateTime now, double? peak) {
    if (_lastTrigger != null && now.difference(_lastTrigger!) < _cooldown) {
      return; // todavía en enfriamiento tras una alerta
    }
    final rejected = _analyzer.startCandidate(trigger, now, peak: peak);
    if (rejected != null) _emit(rejected);
  }

  /// Revisa si el golpe en observación ya se puede decidir.
  void tick() {
    if (!isRunning) return;
    final ev = _analyzer.evaluate(_clock());
    if (ev != null) _emit(ev);
  }

  void _emit(FallEvidence ev) {
    debugPrint('Caída: $ev');
    _onEvidence?.call(ev);
    if (!ev.confirmed) return;
    _lastTrigger = _clock();
    lastEvidence = ev;
    _onFall?.call();
  }

  void stop() {
    _sub?.cancel();
    _sub = null;
    _gyroSub?.cancel();
    _gyroSub = null;
    _timer?.cancel();
    _timer = null;
    _detector.reset();
    _analyzer.reset();
  }
}

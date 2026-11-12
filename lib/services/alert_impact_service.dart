import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Totales de "Tu aporte ayudó a…".
class AlertImpact {
  final int total; // ciclistas distintos que vieron tus alertas
  final int week; // ídem, últimos 7 días
  final int alerts; // alertas tuyas que vio al menos una persona

  const AlertImpact({this.total = 0, this.week = 0, this.alerts = 0});

  static const empty = AlertImpact();

  factory AlertImpact.fromMap(Map m) => AlertImpact(
    total: (m['total'] as num?)?.toInt() ?? 0,
    week: (m['week'] as num?)?.toInt() ?? 0,
    alerts: (m['alerts'] as num?)?.toInt() ?? 0,
  );

  /// Frase del perfil, o null si todavía no hay nada que mostrar.
  String? get headline {
    if (total <= 0) return null;
    return total == 1
        ? 'Tus reportes ayudaron a 1 ciclista'
        : 'Tus reportes ayudaron a $total ciclistas';
  }
}

/// Cuenta cuántos ciclistas ven cada alerta (al abrirla o al pasar cerca) y
/// entrega al autor sus totales. Solo se guardan conteos: el autor nunca ve
/// quiénes fueron. El aviso push al autor lo dispara el servidor al llegar a
/// 3, 10, 25… ciclistas (ver register_alert_view en Supabase).
class AlertImpactService {
  AlertImpactService._();

  static final Set<String> _sentThisSession = {};

  /// [kind]: 'open' (abrió el detalle) o 'nearby' (le avisamos al pasar cerca).
  static Future<void> registerView(String? alertId, String kind) async {
    if (alertId == null || alertId.isEmpty) return;
    final sb = Supabase.instance.client;
    if (sb.auth.currentUser == null) return;
    // Una vez por alerta y sesión basta: el servidor igual cuenta una vez
    // por persona.
    if (!_sentThisSession.add(alertId)) return;
    try {
      await sb.rpc(
        'register_alert_view',
        params: {'p_alert': alertId, 'p_kind': kind},
      );
    } catch (e) {
      _sentThisSession.remove(alertId);
      debugPrint('AlertImpactService.registerView: $e');
    }
  }

  static Future<AlertImpact> myImpact() async {
    try {
      final res = await Supabase.instance.client.rpc('my_alert_impact');
      if (res is Map) return AlertImpact.fromMap(res);
    } catch (e) {
      debugPrint('AlertImpactService.myImpact: $e');
    }
    return AlertImpact.empty;
  }
}

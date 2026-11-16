import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'fall_detection_service.dart';

/// Registro ANÓNIMO de lo que midió el detector de caídas (sin usuario ni
/// ubicación), para ajustar los umbrales con casos reales: cuántas alertas
/// fueron caídas de verdad y cuántas el ciclista marcó como «Estoy bien».
class FallLogService {
  FallLogService._();

  static int _dismissedThisSession = 0;
  static const _maxDismissedPerSession = 15;

  /// [outcome]: descartada · estoy_bien · llamo · llamada_automatica ·
  /// desactivo.
  static Future<void> log(FallEvidence ev, String outcome) async {
    // Los golpes descartados son muchos (baches): se registran solo algunos,
    // y nunca los del teléfono quieto o caminando (no aportan).
    if (!ev.confirmed) {
      if (ev.reason == 'no_pedaleando') return;
      if (_dismissedThisSession >= _maxDismissedPerSession) return;
      _dismissedThisSession++;
    }
    try {
      final client = Supabase.instance.client;
      if (client.auth.currentUser == null) return;
      await client.from('fall_events').insert({
        ...ev.toJson(),
        'outcome': outcome,
      });
    } catch (e) {
      // Sin conexión o tabla aún no creada: el registro es opcional.
      debugPrint('No se pudo registrar el evento de caída: $e');
    }
  }
}

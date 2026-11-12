import 'package:flutter/foundation.dart';
import 'package:in_app_review/in_app_review.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'ride_stats_service.dart';

/// Pide calificar la app en Google Play con la ventana oficial de Google
/// (sin salir de la app), solo a quien ya la usó de verdad.
///
/// Condiciones para pedirla:
///  - pedaleó con la app al menos [_minDays] días distintos y [_minKm] km;
///  - no se le pidió en los últimos [_cooldown];
///  - como mucho [_maxAsks] veces en total.
///
/// Google además limita por su cuenta cuántas veces muestra la ventana, así
/// que pedirla no garantiza que aparezca (y nunca se sabe si calificó).
class ReviewPromptService {
  static const _kLastAsk = 'review_prompt_last_ask';
  static const _kAsks = 'review_prompt_asks';

  static const _minDays = 2;
  static const _minKm = 3.0;
  static const _cooldown = Duration(days: 45);
  static const _maxAsks = 3;

  static bool _askedThisSession = false;

  /// Llama a esto en momentos tranquilos (no en medio de un recorrido):
  /// al abrir la app o al terminar una navegación.
  static Future<void> maybeAsk() async {
    if (_askedThisSession) return;
    try {
      if (RideStatsService.activeDays() < _minDays) return;
      if (RideStatsService.totalKm() < _minKm) return;

      final prefs = await SharedPreferences.getInstance();
      final asks = prefs.getInt(_kAsks) ?? 0;
      if (asks >= _maxAsks) return;
      final last = prefs.getInt(_kLastAsk);
      if (last != null &&
          DateTime.now().difference(DateTime.fromMillisecondsSinceEpoch(last)) <
              _cooldown) {
        return;
      }

      final review = InAppReview.instance;
      if (!await review.isAvailable()) return;

      _askedThisSession = true;
      await prefs.setInt(_kLastAsk, DateTime.now().millisecondsSinceEpoch);
      await prefs.setInt(_kAsks, asks + 1);
      await review.requestReview();
    } catch (e) {
      debugPrint('ReviewPromptService: $e');
    }
  }
}

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:in_app_update/in_app_update.dart';

/// Actualización OBLIGATORIA desde Play Store.
///
/// Usa la API "In-App Update" de Google Play en modo *immediate*: si hay una
/// versión nueva publicada, Play muestra una pantalla completa que bloquea la
/// app hasta que el usuario actualiza. No se puede saltar.
///
/// Solo funciona en Android y si la app se instaló desde Play Store (en debug o
/// con un APK suelto `checkForUpdate` tira excepción y simplemente se ignora).
class AppUpdateService {
  static bool _checkedThisSession = false;

  /// Revisa si hay actualización y, de haberla, lanza el flujo inmediato.
  /// Pensado para llamarse al arrancar la app.
  static Future<void> enforceUpdate() async {
    if (!Platform.isAndroid) return;
    if (_checkedThisSession) return;
    _checkedThisSession = true;
    try {
      final info = await InAppUpdate.checkForUpdate();
      if (info.updateAvailability == UpdateAvailability.updateAvailable &&
          info.immediateUpdateAllowed) {
        await InAppUpdate.performImmediateUpdate();
      }
    } catch (e) {
      debugPrint('AppUpdateService: no se pudo comprobar la actualización: $e');
    }
  }

  /// Si el usuario dejó a medias una actualización inmediata (mandó la app a
  /// segundo plano), Play deja el estado en "en progreso": al volver hay que
  /// retomarla. Llamar desde `resumed` del ciclo de vida.
  static Future<void> resumeIfInProgress() async {
    if (!Platform.isAndroid) return;
    try {
      final info = await InAppUpdate.checkForUpdate();
      if (info.updateAvailability ==
          UpdateAvailability.developerTriggeredUpdateInProgress) {
        await InAppUpdate.performImmediateUpdate();
      }
    } catch (e) {
      debugPrint('AppUpdateService: no se pudo retomar la actualización: $e');
    }
  }
}

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:in_app_update/in_app_update.dart';

/// Actualización OBLIGATORIA desde Play Store.
///
/// Usa la API "In-App Update" de Google Play en modo *immediate*: si hay una
/// versión nueva publicada, Play muestra una pantalla completa que bloquea la
/// app hasta que el usuario actualiza. No se puede saltar.
///
/// Se revisa al arrancar, al volver a la app tras 30 min y al tocar el aviso
/// push "Nueva versión de Pedalea" (payload `app_update`).
///
/// Solo funciona en Android y si la app se instaló desde Play Store (en debug o
/// con un APK suelto `checkForUpdate` tira excepción y simplemente se ignora).
class AppUpdateService {
  static DateTime? _lastCheck;
  static bool _running = false;

  /// Cada cuánto se vuelve a revisar al volver a la app.
  static const _recheckAfter = Duration(minutes: 30);

  /// Revisa si hay actualización y, de haberla, lanza el flujo inmediato.
  /// Con [force] revisa aunque se haya revisado hace poco (al tocar el aviso
  /// de nueva versión).
  static Future<void> enforceUpdate({bool force = false}) async {
    if (!Platform.isAndroid || _running) return;
    final last = _lastCheck;
    if (!force && last != null && DateTime.now().difference(last) < _recheckAfter) {
      return;
    }
    _running = true;
    _lastCheck = DateTime.now();
    try {
      final info = await InAppUpdate.checkForUpdate();
      if (info.updateAvailability == UpdateAvailability.updateAvailable &&
          info.immediateUpdateAllowed) {
        await InAppUpdate.performImmediateUpdate();
      }
    } catch (e) {
      debugPrint('AppUpdateService: no se pudo comprobar la actualización: $e');
    } finally {
      _running = false;
    }
  }

  /// Al volver a la app: retoma una actualización dejada a medias y, si pasó
  /// suficiente tiempo, vuelve a revisar si hay versión nueva (la app puede
  /// estar días abierta en segundo plano sin reiniciarse).
  static Future<void> resumeIfInProgress() async {
    if (!Platform.isAndroid) return;
    try {
      final info = await InAppUpdate.checkForUpdate();
      if (info.updateAvailability ==
          UpdateAvailability.developerTriggeredUpdateInProgress) {
        await InAppUpdate.performImmediateUpdate();
        return;
      }
    } catch (e) {
      debugPrint('AppUpdateService: no se pudo retomar la actualización: $e');
    }
    await enforceUpdate();
  }
}

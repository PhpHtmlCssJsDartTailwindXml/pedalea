import 'package:firebase_core/firebase_core.dart';

/// Datos del proyecto de Firebase para las notificaciones push (FCM).
///
/// Mientras estén vacíos, el push queda APAGADO y la app sigue avisando como
/// antes (solo con la app abierta o en segundo plano).
///
/// Cómo llenarlos: en la consola de Firebase → Configuración del proyecto →
/// "Tus apps" → app Android `com.pedalea.app` → descargar
/// `google-services.json` y copiar desde ese archivo:
///
///   projectId          ← project_info.project_id
///   messagingSenderId  ← project_info.project_number
///   appId              ← client[0].client_info.mobilesdk_app_id
///   apiKey             ← client[0].api_key[0].current_key
///
/// No son secretos (van dentro de cualquier APK); la clave que sí es secreta
/// es la cuenta de servicio, que vive solo en el servidor (Edge Function).
class PushConfig {
  static const projectId = 'pedaleaapp-d9541';
  static const messagingSenderId = '528635082057';
  static const appId = '1:528635082057:android:d2b11df9dc19364a809698';
  static const apiKey = 'AIzaSyDU-NX9h4Jwi6HxmqSYDv_DqqoSIsWLsa4';

  static bool get isConfigured =>
      projectId.isNotEmpty &&
      messagingSenderId.isNotEmpty &&
      appId.isNotEmpty &&
      apiKey.isNotEmpty;

  static FirebaseOptions get options => const FirebaseOptions(
    apiKey: apiKey,
    appId: appId,
    messagingSenderId: messagingSenderId,
    projectId: projectId,
  );
}

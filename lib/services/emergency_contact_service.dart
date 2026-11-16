import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Contacto de emergencia del usuario actual, compartido por toda la app.
///
/// Antes el botón SOS lo leía una sola vez al abrir el mapa, así que un
/// contacto recién guardado no aparecía hasta reiniciar la app. Ahora el perfil
/// avisa al guardar y el SOS lo vuelve a leer cada vez que se abre.
class EmergencyContactService {
  EmergencyContactService._();

  /// (nombre, teléfono). Vacío si no hay contacto o no hay sesión.
  static final ValueNotifier<({String? name, String? phone})> contact =
      ValueNotifier((name: null, phone: null));

  static String? _uid;

  /// Lee el contacto del servidor (solo su dueño puede hacerlo).
  static Future<void> refresh() async {
    final uid = Supabase.instance.client.auth.currentUser?.id;
    if (uid != _uid) {
      // Cambio de cuenta: nunca mostrar el contacto de otra persona.
      _uid = uid;
      contact.value = (name: null, phone: null);
    }
    if (uid == null) return;
    try {
      final res = await Supabase.instance.client.rpc('my_private_profile');
      if (Supabase.instance.client.auth.currentUser?.id != uid) return;
      final data = res is Map ? res : null;
      String? clean(Object? v) {
        final s = (v as String?)?.trim();
        return (s == null || s.isEmpty) ? null : s;
      }

      contact.value = (
        name: clean(data?['emergency_contact_name']),
        phone: clean(data?['emergency_contact_phone']),
      );
    } catch (_) {
      // Sin conexión: se mantiene lo último conocido.
    }
  }

  /// El perfil lo llama justo después de guardar, sin esperar al servidor.
  static void setLocal(String name, String phone) {
    _uid = Supabase.instance.client.auth.currentUser?.id;
    contact.value = (
      name: name.trim().isEmpty ? null : name.trim(),
      phone: phone.trim().isEmpty ? null : phone.trim(),
    );
  }
}

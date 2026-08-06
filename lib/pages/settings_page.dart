import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'compass_calibration_page.dart';
import 'auth_page.dart';
import '../core/confirm_word_dialog.dart';

/// Pantalla de configuración de la app: agrupa ajustes de sensores y
/// otras opciones clave que no dependen de la cuenta (a diferencia de
/// "Cerrar sesión", que vive en el drawer).
class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  bool _deleting = false;

  Future<void> _deleteAccount() async {
    final confirmed = await confirmWithWord(
      context,
      title: '¿Eliminar tu cuenta?',
      message: 'Esto borra permanentemente tu perfil, rutas favoritas, '
          'logros, alertas y toda tu actividad en Pedalea. Los eventos que '
          'creaste pasan a otro participante (o se borran si estabas solo). '
          'No se puede deshacer.',
      requiredWord: 'ELIMINAR',
      confirmLabel: 'Eliminar cuenta',
    );
    if (!confirmed || !mounted) return;

    setState(() => _deleting = true);
    try {
      final session = Supabase.instance.client.auth.currentSession;
      if (session == null) throw Exception('Sesión no válida');

      final response = await Supabase.instance.client.functions.invoke(
        'delete-account',
        headers: {'Authorization': 'Bearer ${session.accessToken}'},
      );
      if (response.status != 200) {
        throw Exception(
          response.data is Map ? response.data['error'] : 'Error desconocido',
        );
      }

      await Supabase.instance.client.auth.signOut();
      if (!mounted) return;
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => const AuthPage()),
        (route) => false,
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _deleting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo eliminar la cuenta: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF08080F),
      appBar: AppBar(
        backgroundColor: const Color(0xFF08080F),
        elevation: 0,
        title: const Text(
          'Configuración',
          style: TextStyle(fontFamily: 'Poppins', color: Colors.white),
        ),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: SafeArea(
        child: Stack(
          children: [
            ListView(
              children: [
                const Padding(
                  padding: EdgeInsets.only(left: 16, top: 16, bottom: 8),
                  child: Text(
                    'SENSORES',
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      color: Colors.grey,
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
                ListTile(
                  leading: const Icon(Icons.explore_rounded,
                      color: Color(0xFF7CF0BC)),
                  title: const Text(
                    'Calibrar brújula',
                    style:
                        TextStyle(fontFamily: 'Poppins', color: Colors.white),
                  ),
                  subtitle: Text(
                    'Mejora la precisión del cono de dirección en el mapa',
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      color: Colors.grey[400],
                      fontSize: 12,
                    ),
                  ),
                  trailing: const Icon(Icons.chevron_right,
                      color: Colors.white38, size: 20),
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const CompassCalibrationPage(),
                      ),
                    );
                  },
                ),
                const Divider(color: Colors.white24, height: 32),
                const Padding(
                  padding: EdgeInsets.only(left: 16, bottom: 8),
                  child: Text(
                    'CUENTA',
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      color: Colors.grey,
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
                ListTile(
                  leading: const Icon(Icons.delete_forever_rounded,
                      color: Colors.redAccent),
                  title: const Text(
                    'Eliminar cuenta',
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      color: Colors.redAccent,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  subtitle: Text(
                    'Borra tu cuenta y todos tus datos de forma permanente',
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      color: Colors.grey[400],
                      fontSize: 12,
                    ),
                  ),
                  onTap: _deleting ? null : _deleteAccount,
                ),
              ],
            ),
            if (_deleting)
              Container(
                color: Colors.black54,
                child: const Center(
                  child: CircularProgressIndicator(color: Color(0xFF7CF0BC)),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

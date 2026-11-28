import 'package:flutter/material.dart';
import 'package:in_app_review/in_app_review.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'compass_calibration_page.dart';
import 'auth_page.dart';
import 'terms_page.dart';
import '../core/confirm_word_dialog.dart';
import '../services/notification_prefs_service.dart';

/// Pantalla de configuración: qué avisos recibir, sensores, información de
/// la app y la cuenta ("Cerrar sesión" vive en el menú lateral).
class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  bool _deleting = false;

  static const _accent = Color(0xFF7CF0BC);

  /// Tipos de aviso: (clave, ícono, título, descripción).
  static const _notifTypes = <(String, IconData, String, String)>[
    ('messages', Icons.forum_outlined, 'Mensajes',
        'Mensajes directos y chats de grupos'),
    ('social', Icons.people_outline_rounded, 'Actividad social',
        'Seguidores, me gusta y comentarios en tus momentos'),
    ('impact', Icons.volunteer_activism_outlined, 'Impacto de tus alertas',
        'Cuando tus reportes ayudan a otros ciclistas'),
    ('weekly', Icons.insights_rounded, 'Resumen semanal',
        'Los lunes, tus km y logros de la semana'),
    ('streak', Icons.local_fire_department_outlined, 'Recordatorio de racha',
        'Si no has pedaleado y tu racha está por cortarse'),
    ('news', Icons.campaign_outlined, 'Novedades y promociones',
        'Versiones nuevas de la app y ofertas de Pedalea Plus'),
  ];

  @override
  void initState() {
    super.initState();
    NotificationPrefs.load(); // trae lo guardado en el servidor
  }

  Future<void> _toggleNotif(String key, bool value) async {
    final ok = await NotificationPrefs.set(key, value);
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Se guardó en este teléfono. Se sincroniza al tener conexión.'),
        ),
      );
    }
  }

  Future<void> _rateApp() async {
    try {
      await InAppReview.instance.openStoreListing();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No se pudo abrir Google Play')),
      );
    }
  }

  Widget _section(String title, {double top = 16}) => Padding(
    padding: EdgeInsets.only(left: 16, top: top, bottom: 8),
    child: Text(
      title,
      style: const TextStyle(
        fontFamily: 'Poppins',
        color: Colors.grey,
        fontSize: 12,
        fontWeight: FontWeight.w500,
        letterSpacing: 0.5,
      ),
    ),
  );

  Widget _tile({
    required IconData icon,
    required String title,
    String? subtitle,
    Widget? trailing,
    VoidCallback? onTap,
    Color iconColor = _accent,
  }) => ListTile(
    leading: Icon(icon, color: iconColor),
    title: Text(
      title,
      style: const TextStyle(fontFamily: 'Poppins', color: Colors.white),
    ),
    subtitle: subtitle == null
        ? null
        : Text(
            subtitle,
            style: TextStyle(
              fontFamily: 'Poppins',
              color: Colors.grey[400],
              fontSize: 12,
            ),
          ),
    trailing: trailing ??
        (onTap == null
            ? null
            : const Icon(Icons.chevron_right, color: Colors.white38, size: 20)),
    onTap: onTap,
  );

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
                _section('NOTIFICACIONES'),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
                  child: Text(
                    'Lo que apagues no te llegará como notificación, pero '
                    'seguirá en la campana del menú.',
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      color: Colors.grey[500],
                      fontSize: 12,
                    ),
                  ),
                ),
                ValueListenableBuilder<Map<String, bool>>(
                  valueListenable: NotificationPrefs.prefs,
                  builder: (context, prefs, _) => Column(
                    children: [
                      for (final (key, icon, title, desc) in _notifTypes)
                        SwitchListTile(
                          secondary: Icon(icon, color: _accent),
                          title: Text(
                            title,
                            style: const TextStyle(
                              fontFamily: 'Poppins',
                              color: Colors.white,
                            ),
                          ),
                          subtitle: Text(
                            desc,
                            style: TextStyle(
                              fontFamily: 'Poppins',
                              color: Colors.grey[400],
                              fontSize: 12,
                            ),
                          ),
                          value: prefs[key] ?? true,
                          activeThumbColor: _accent,
                          onChanged: (v) => _toggleNotif(key, v),
                        ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
                  child: Text(
                    'Los avisos de peligro cercano y de emergencia se '
                    'configuran en el menú del mapa.',
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      color: Colors.grey[500],
                      fontSize: 12,
                    ),
                  ),
                ),
                const Divider(color: Colors.white24, height: 32),
                _section('SENSORES', top: 0),
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
                _section('ACERCA DE PEDALEA', top: 0),
                _tile(
                  icon: Icons.star_outline_rounded,
                  title: 'Califica Pedalea',
                  subtitle: 'Tu reseña en Google Play nos ayuda muchísimo',
                  onTap: _rateApp,
                ),
                _tile(
                  icon: Icons.description_outlined,
                  title: 'Términos y privacidad',
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const TermsPage()),
                  ),
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

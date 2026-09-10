import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../core/glass.dart';
import '../services/social_service.dart';
import 'moment_editor_page.dart';
import 'paywall_page.dart';

/// Publica un "momento": foto (con editor) + texto opcional. Tope diario en
/// el plan gratis.
class CreateMomentPage extends StatefulWidget {
  const CreateMomentPage({super.key});

  @override
  State<CreateMomentPage> createState() => _CreateMomentPageState();
}

class _CreateMomentPageState extends State<CreateMomentPage> {
  final _picker = ImagePicker();
  final _captionCtrl = TextEditingController();
  File? _image;
  bool _publishing = false;

  @override
  void dispose() {
    _captionCtrl.dispose();
    super.dispose();
  }

  Future<void> _pick(ImageSource source) async {
    try {
      final picked = await _picker.pickImage(
        source: source,
        maxWidth: 1440,
        imageQuality: 82,
      );
      if (picked == null) return;
      await _openEditor(File(picked.path));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('No se pudo abrir la imagen: $e',
              style: const TextStyle(fontFamily: 'Poppins')),
          backgroundColor: Colors.redAccent,
        ));
      }
    }
  }

  Future<void> _openEditor(File file) async {
    final edited = await Navigator.push<File>(
      context,
      MaterialPageRoute(builder: (_) => MomentEditorPage(source: file)),
    );
    if (edited != null && mounted) {
      setState(() => _image = edited);
    } else if (_image == null && mounted) {
      // Canceló el editor sin haber tenido una foto antes: deja la original.
      setState(() => _image = file);
    }
  }

  Future<void> _publish() async {
    if (_image == null || _publishing) return;
    setState(() => _publishing = true);
    try {
      await SocialService.instance.createPost(
        image: _image!,
        caption: _captionCtrl.text,
      );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _publishing = false);
      if (e.toString().contains('daily_post_limit')) {
        showDialog<void>(
          context: context,
          builder: (_) => AlertDialog(
            backgroundColor: const Color(0xFF161622),
            title: const Text('Límite diario',
                style: TextStyle(fontFamily: 'Poppins', color: Colors.white)),
            content: const Text(
              'El plan gratis permite 2 momentos al día. Hazte Pedalea Plus '
              'para publicar sin límite.',
              style: TextStyle(fontFamily: 'Poppins', color: Colors.white70),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Entendido',
                    style: TextStyle(
                        fontFamily: 'Poppins', color: Colors.white54)),
              ),
              TextButton(
                onPressed: () {
                  Navigator.pop(context);
                  Navigator.pushReplacement(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const PaywallPage(
                        reason:
                            'Publica momentos sin límite con Pedalea Plus.',
                      ),
                    ),
                  );
                },
                child: const Text('Ver Plus',
                    style: TextStyle(
                        fontFamily: 'Poppins', color: Color(0xFF69FF47))),
              ),
            ],
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('No se pudo publicar: $e',
              style: const TextStyle(fontFamily: 'Poppins')),
          backgroundColor: Colors.redAccent,
        ));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBgDark,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        title: const Text('Nuevo momento',
            style: TextStyle(
                fontFamily: 'Poppins',
                color: Colors.white,
                fontWeight: FontWeight.w700)),
        actions: [
          TextButton(
            onPressed: (_image == null || _publishing) ? null : _publish,
            child: _publishing
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white54))
                : Text('Publicar',
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      fontWeight: FontWeight.w700,
                      color: _image == null
                          ? Colors.white24
                          : const Color(0xFF69FF47),
                    )),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          AspectRatio(
            aspectRatio: 1,
            child: GestureDetector(
              onTap: _image == null ? _showPickSheet : null,
              child: Stack(
                children: [
                  Positioned.fill(
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.05),
                        borderRadius: BorderRadius.circular(16),
                        border:
                            Border.all(color: Colors.white.withOpacity(0.12)),
                        image: _image != null
                            ? DecorationImage(
                                image: FileImage(_image!), fit: BoxFit.cover)
                            : null,
                      ),
                      child: _image == null
                          ? Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.add_a_photo_outlined,
                                    size: 40,
                                    color: Colors.white.withOpacity(0.4)),
                                const SizedBox(height: 10),
                                Text('Elegir foto',
                                    style: TextStyle(
                                        fontFamily: 'Poppins',
                                        color: Colors.white.withOpacity(0.5))),
                              ],
                            )
                          : null,
                    ),
                  ),
                  if (_image != null)
                    Positioned(
                      right: 10,
                      bottom: 10,
                      child: Row(
                        children: [
                          _pillButton(Icons.tune_rounded, 'Editar',
                              () => _openEditor(_image!)),
                          const SizedBox(width: 8),
                          _pillButton(Icons.swap_horiz_rounded, 'Cambiar',
                              _showPickSheet),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _captionCtrl,
            maxLines: 4,
            maxLength: 500,
            style: const TextStyle(fontFamily: 'Poppins', color: Colors.white),
            decoration: InputDecoration(
              hintText: 'Cuenta algo de este momento… (opcional)',
              hintStyle: TextStyle(
                  fontFamily: 'Poppins', color: Colors.white.withOpacity(0.4)),
              filled: true,
              fillColor: Colors.white.withOpacity(0.05),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide.none,
              ),
              counterStyle: const TextStyle(color: Colors.white30),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Cualquier ciclista podrá ver tu momento. Solo quienes se sigan '
            'mutuamente contigo podrán reaccionar o comentar.',
            style: TextStyle(
                fontFamily: 'Poppins',
                color: Colors.white.withOpacity(0.4),
                fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _pillButton(IconData icon, String label, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.55),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          children: [
            Icon(icon, color: Colors.white, size: 15),
            const SizedBox(width: 5),
            Text(label,
                style: const TextStyle(
                    fontFamily: 'Poppins',
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }

  void _showPickSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF161622),
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_library_outlined,
                  color: Colors.white70),
              title: const Text('Galería',
                  style:
                      TextStyle(fontFamily: 'Poppins', color: Colors.white)),
              onTap: () {
                Navigator.pop(context);
                _pick(ImageSource.gallery);
              },
            ),
            ListTile(
              leading:
                  const Icon(Icons.camera_alt_outlined, color: Colors.white70),
              title: const Text('Cámara',
                  style:
                      TextStyle(fontFamily: 'Poppins', color: Colors.white)),
              onTap: () {
                Navigator.pop(context);
                _pick(ImageSource.camera);
              },
            ),
          ],
        ),
      ),
    );
  }
}

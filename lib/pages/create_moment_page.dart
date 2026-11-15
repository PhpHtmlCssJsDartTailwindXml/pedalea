import 'dart:io';
import 'dart:ui';
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
  static const _green = Colors.greenAccent;
  static const _mint = Color(0xFF7CF0BC);
  static const _captionMax = 500;

  final _picker = ImagePicker();
  final _captionCtrl = TextEditingController();
  File? _image;
  bool _publishing = false;

  @override
  void initState() {
    super.initState();
    // Refresca el contador de caracteres propio.
    _captionCtrl.addListener(() => setState(() {}));
  }

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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'No se pudo abrir la imagen: $e',
              style: const TextStyle(fontFamily: 'Poppins'),
            ),
            backgroundColor: Colors.redAccent,
          ),
        );
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
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(24),
            ),
            title: const Text(
              'Límite diario',
              style: TextStyle(
                fontFamily: 'Poppins',
                color: Colors.white,
                fontWeight: FontWeight.w700,
              ),
            ),
            content: const Text(
              'El plan gratis permite 2 momentos al día. Hazte Pedalea Plus '
              'para publicar sin límite.',
              style: TextStyle(fontFamily: 'Poppins', color: Colors.white70),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text(
                  'Entendido',
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    color: Colors.white54,
                  ),
                ),
              ),
              TextButton(
                onPressed: () {
                  Navigator.pop(context);
                  Navigator.pushReplacement(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const PaywallPage(
                        reason: 'Publica momentos sin límite con Pedalea Plus.',
                      ),
                    ),
                  );
                },
                child: const Text(
                  'Ver Plus',
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    color: _green,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'No se pudo publicar: $e',
              style: const TextStyle(fontFamily: 'Poppins'),
            ),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasImage = _image != null;
    return Scaffold(
      backgroundColor: kBgDark,
      body: Stack(
        children: [
          SafeArea(
            child: Column(
              children: [
                _topBar(hasImage),
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                    children: [
                      AspectRatio(
                        aspectRatio: 1,
                        child: AnimatedSwitcher(
                          duration: const Duration(milliseconds: 280),
                          child: hasImage
                              ? _preview(key: ValueKey(_image!.path))
                              : _emptyPicker(key: const ValueKey('empty')),
                        ),
                      ),
                      const SizedBox(height: 16),
                      _captionField(),
                      const SizedBox(height: 12),
                      _privacyNote(),
                    ],
                  ),
                ),
                _publishBar(hasImage),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _topBar(bool hasImage) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 8, 16, 6),
      child: Row(
        children: [
          Tooltip(
            message: 'Cerrar',
            child: Material(
              color: Colors.white.withOpacity(0.07),
              shape: CircleBorder(
                side: BorderSide(color: Colors.white.withOpacity(0.10)),
              ),
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: () => Navigator.maybePop(context),
                child: const SizedBox(
                  width: 44,
                  height: 44,
                  child: Icon(
                    Icons.close_rounded,
                    color: Colors.white,
                    size: 21,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Nuevo momento',
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    color: Colors.white,
                    fontSize: 21,
                    height: 1.2,
                    letterSpacing: -0.3,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                Text(
                  hasImage
                      ? 'Dale el último toque y publícalo'
                      : 'Empieza eligiendo una foto',
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    color: Colors.white.withOpacity(0.5),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          // Progreso: foto → publicar
          Row(
            children: [
              _stepDot(true),
              const SizedBox(width: 5),
              _stepDot(hasImage),
            ],
          ),
        ],
      ),
    );
  }

  Widget _stepDot(bool on) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 260),
      width: on ? 22 : 8,
      height: 8,
      decoration: BoxDecoration(
        color: on ? _green : Colors.white.withOpacity(0.16),
        borderRadius: BorderRadius.circular(4),
      ),
    );
  }

  /// Estado inicial: sin foto. Galería y cámara a un toque.
  Widget _emptyPicker({Key? key}) {
    return CustomPaint(
      key: key,
      painter: _DashedBorderPainter(
        color: _green.withOpacity(0.45),
        radius: 30,
      ),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(30),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [_green.withOpacity(0.10), Colors.white.withOpacity(0.03)],
          ),
        ),
        padding: const EdgeInsets.all(22),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 84,
              height: 84,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [_green, _mint],
                ),
              ),
              child: const Icon(
                Icons.add_a_photo_rounded,
                size: 34,
                color: Colors.black,
              ),
            ),
            const SizedBox(height: 18),
            const Text(
              'Sube tu mejor foto',
              style: TextStyle(
                fontFamily: 'Poppins',
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 3),
            Text(
              'Después podrás añadir filtros, dibujo y stickers',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: 'Poppins',
                color: Colors.white.withOpacity(0.5),
                fontSize: 12.5,
              ),
            ),
            const SizedBox(height: 22),
            Row(
              children: [
                Expanded(
                  child: _sourceButton(
                    icon: Icons.photo_library_rounded,
                    label: 'Galería',
                    filled: true,
                    onTap: () => _pick(ImageSource.gallery),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _sourceButton(
                    icon: Icons.camera_alt_rounded,
                    label: 'Cámara',
                    filled: false,
                    onTap: () => _pick(ImageSource.camera),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _sourceButton({
    required IconData icon,
    required String label,
    required bool filled,
    required VoidCallback onTap,
  }) {
    return Material(
      color: filled ? _green : Colors.white.withOpacity(0.08),
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Container(
          height: 52,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: filled
                ? null
                : Border.all(color: Colors.white.withOpacity(0.14)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 20, color: filled ? Colors.black : Colors.white),
              const SizedBox(width: 8),
              Text(
                label,
                style: TextStyle(
                  fontFamily: 'Poppins',
                  color: filled ? Colors.black : Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Foto elegida, con accesos de cristal para editarla o cambiarla.
  Widget _preview({Key? key}) {
    return Container(
      key: key,
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(30)),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(30),
        child: Stack(
          fit: StackFit.expand,
          children: [
            Image.file(_image!, fit: BoxFit.cover),
            // Sombra inferior para que los botones se lean sobre la foto.
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              height: 110,
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.black.withOpacity(0),
                        Colors.black.withOpacity(0.55),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              left: 12,
              right: 12,
              bottom: 12,
              child: Row(
                children: [
                  Expanded(
                    child: _glassPill(
                      Icons.auto_fix_high_rounded,
                      'Editar',
                      () => _openEditor(_image!),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _glassPill(
                      Icons.swap_horiz_rounded,
                      'Cambiar',
                      _showPickSheet,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _glassPill(IconData icon, String label, VoidCallback onTap) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
        child: Material(
          color: Colors.black.withOpacity(0.35),
          child: InkWell(
            onTap: onTap,
            child: Container(
              height: 48,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: Colors.white.withOpacity(0.22)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(icon, color: Colors.white, size: 18),
                  const SizedBox(width: 7),
                  Text(
                    label,
                    style: const TextStyle(
                      fontFamily: 'Poppins',
                      color: Colors.white,
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _captionField() {
    final len = _captionCtrl.text.characters.length;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: Colors.white.withOpacity(0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.edit_note_rounded, color: _mint, size: 19),
              const SizedBox(width: 6),
              Text(
                'Descripción',
                style: TextStyle(
                  fontFamily: 'Poppins',
                  color: Colors.white.withOpacity(0.75),
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                'opcional',
                style: TextStyle(
                  fontFamily: 'Poppins',
                  color: Colors.white.withOpacity(0.35),
                  fontSize: 11.5,
                ),
              ),
              const Spacer(),
              Text(
                '$len/$_captionMax',
                style: TextStyle(
                  fontFamily: 'Poppins',
                  color: len > _captionMax - 40
                      ? _green
                      : Colors.white.withOpacity(0.35),
                  fontSize: 11.5,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
          TextField(
            controller: _captionCtrl,
            minLines: 2,
            maxLines: 5,
            maxLength: _captionMax,
            cursorColor: _green,
            textCapitalization: TextCapitalization.sentences,
            style: const TextStyle(
              fontFamily: 'Poppins',
              color: Colors.white,
              fontSize: 14.5,
            ),
            decoration: InputDecoration(
              hintText: 'Cuenta algo de este momento…',
              hintStyle: TextStyle(
                fontFamily: 'Poppins',
                color: Colors.white.withOpacity(0.35),
              ),
              border: InputBorder.none,
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(vertical: 10),
              counterText: '',
            ),
          ),
        ],
      ),
    );
  }

  Widget _privacyNote() {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 11, 14, 11),
      decoration: BoxDecoration(
        color: _mint.withOpacity(0.06),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _mint.withOpacity(0.14)),
      ),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: _mint.withOpacity(0.14),
              borderRadius: BorderRadius.circular(11),
            ),
            child: const Icon(Icons.public_rounded, color: _mint, size: 18),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Text(
              'Cualquier ciclista podrá ver tu momento, darle me gusta y '
              'comentarlo.',
              style: TextStyle(
                fontFamily: 'Poppins',
                color: Colors.white.withOpacity(0.6),
                fontSize: 11.5,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _publishBar(bool hasImage) {
    final enabled = hasImage && !_publishing;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 12),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: enabled ? _publish : null,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 240),
            height: 56,
            decoration: BoxDecoration(
              gradient: hasImage
                  ? const LinearGradient(colors: [_green, _mint])
                  : null,
              color: hasImage ? null : Colors.white.withOpacity(0.07),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (_publishing)
                  const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.2,
                      color: Colors.black,
                    ),
                  )
                else
                  Icon(
                    Icons.send_rounded,
                    size: 19,
                    color: hasImage ? Colors.black : Colors.white30,
                  ),
                const SizedBox(width: 10),
                Text(
                  _publishing
                      ? 'Publicando…'
                      : hasImage
                      ? 'Publicar'
                      : 'Elige una foto para publicar',
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    color: hasImage ? Colors.black : Colors.white38,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showPickSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => Container(
        decoration: BoxDecoration(
          color: const Color(0xFF161622),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
          border: Border(
            top: BorderSide(color: Colors.white.withOpacity(0.10)),
          ),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 10, 18, 18),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.white24,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Cambiar foto',
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    color: Colors.white,
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: _sheetTile(
                        icon: Icons.photo_library_rounded,
                        label: 'Galería',
                        hint: 'Elige una foto guardada',
                        color: _green,
                        source: ImageSource.gallery,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _sheetTile(
                        icon: Icons.camera_alt_rounded,
                        label: 'Cámara',
                        hint: 'Toma una ahora',
                        color: _mint,
                        source: ImageSource.camera,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _sheetTile({
    required IconData icon,
    required String label,
    required String hint,
    required Color color,
    required ImageSource source,
  }) {
    return Material(
      color: color.withOpacity(0.08),
      borderRadius: BorderRadius.circular(22),
      child: InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: () {
          Navigator.pop(context);
          _pick(source);
        },
        child: Container(
          padding: const EdgeInsets.fromLTRB(14, 16, 14, 16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: color.withOpacity(0.25)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: color.withOpacity(0.16),
                  borderRadius: BorderRadius.circular(15),
                ),
                child: Icon(icon, color: color, size: 22),
              ),
              const SizedBox(height: 12),
              Text(
                label,
                style: const TextStyle(
                  fontFamily: 'Poppins',
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
              Text(
                hint,
                style: TextStyle(
                  fontFamily: 'Poppins',
                  color: Colors.white.withOpacity(0.5),
                  fontSize: 11.5,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Borde punteado redondeado para la zona de "elegir foto".
class _DashedBorderPainter extends CustomPainter {
  final Color color;
  final double radius;
  _DashedBorderPainter({required this.color, required this.radius});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6
      ..strokeCap = StrokeCap.round;
    final path = Path()
      ..addRRect(
        RRect.fromRectAndRadius(
          (Offset.zero & size).deflate(1),
          Radius.circular(radius),
        ),
      );
    for (final metric in path.computeMetrics()) {
      double d = 0;
      while (d < metric.length) {
        canvas.drawPath(metric.extractPath(d, d + 9), paint);
        d += 17;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DashedBorderPainter old) =>
      old.color != color || old.radius != radius;
}

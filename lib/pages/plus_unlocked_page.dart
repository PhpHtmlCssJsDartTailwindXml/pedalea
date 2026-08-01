import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

const _kNavy = Color(0xFF12213F);

/// Se muestra justo después de que la compra (real o simulada) se confirma:
/// un mini-tutorial de lo que el usuario acaba de desbloquear con Plus.
class PlusUnlockedPage extends StatefulWidget {
  const PlusUnlockedPage({super.key});

  @override
  State<PlusUnlockedPage> createState() => _PlusUnlockedPageState();
}

class _PlusUnlockedPageState extends State<PlusUnlockedPage> {
  final _controller = PageController();
  int _page = 0;

  static const _slides = [
    _UnlockSlide(
      icon: Icons.workspace_premium_rounded,
      title: '¡Bienvenido a Pedalea Plus!',
      body: 'Dale un plus a tu pedalear. Esto es lo que acabas de desbloquear.',
    ),
    _UnlockSlide(
      icon: Icons.ios_share_rounded,
      title: 'Comparte tus viajes',
      body:
          'Ahora puedes compartir tus rutas y resúmenes como historias, con el trazado de tu recorrido y tus estadísticas.',
    ),
    _UnlockSlide(
      icon: Icons.event_available_rounded,
      title: 'Eventos ilimitados',
      body: 'Crea todas las salidas grupales que quieras, sin el tope de 2 del plan gratis.',
    ),
    _UnlockSlide(
      icon: Icons.bar_chart_rounded,
      title: 'Estadísticas avanzadas',
      body: 'Accede a tu histórico completo y gráficos detallados de tu progreso.',
    ),
    _UnlockSlide(
      icon: Icons.military_tech_rounded,
      title: 'Insignia distintiva',
      body: 'Un marco especial en tu perfil y en el chat de eventos, para que se note.',
    ),
  ];

  // +1 por la pantalla final de "compartir en redes".
  int get _totalPages => _slides.length + 1;
  bool get _isLast => _page == _totalPages - 1;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _kNavy,
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: PageView.builder(
                controller: _controller,
                itemCount: _totalPages,
                onPageChanged: (i) => setState(() => _page = i),
                itemBuilder: (context, i) {
                  if (i == _slides.length) return const _ShareSlideView();
                  return _SlideView(slide: _slides[i]);
                },
              ),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(_totalPages, (i) {
                final active = i == _page;
                return AnimatedContainer(
                  duration: const Duration(milliseconds: 250),
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  width: active ? 22 : 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: active ? Colors.amber : Colors.white24,
                    borderRadius: BorderRadius.circular(4),
                  ),
                );
              }),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
              child: SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  onPressed: () {
                    if (_isLast) {
                      Navigator.pop(context);
                    } else {
                      _controller.nextPage(
                        duration: const Duration(milliseconds: 300),
                        curve: Curves.easeOut,
                      );
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.amber,
                    foregroundColor: Colors.black,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    textStyle: const TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  child: Text(_isLast ? 'Empezar a disfrutar' : 'Siguiente'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _UnlockSlide {
  final IconData icon;
  final String title;
  final String body;
  const _UnlockSlide({required this.icon, required this.title, required this.body});
}

class _SlideView extends StatelessWidget {
  final _UnlockSlide slide;
  const _SlideView({required this.slide});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 140,
            height: 140,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.amber.withOpacity(0.1),
              border: Border.all(color: Colors.amber.withOpacity(0.35), width: 1.5),
            ),
            child: Icon(slide.icon, color: Colors.amber, size: 64),
          ),
          const SizedBox(height: 40),
          Text(
            slide.title,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontFamily: 'Poppins',
              color: Colors.white,
              fontSize: 22,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 14),
          Text(
            slide.body,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: 'Poppins',
              color: Colors.white.withOpacity(0.6),
              fontSize: 15,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }
}

/// Última pantalla: tarjeta lista para compartir en redes anunciando que
/// el usuario ahora es Pedalea Plus.
class _ShareSlideView extends StatefulWidget {
  const _ShareSlideView();

  @override
  State<_ShareSlideView> createState() => _ShareSlideViewState();
}

class _ShareSlideViewState extends State<_ShareSlideView> {
  final GlobalKey _cardKey = GlobalKey();
  bool _sharing = false;

  Future<void> _share() async {
    if (_sharing) return;
    setState(() => _sharing = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await Future.delayed(const Duration(milliseconds: 60));
      final boundary =
          _cardKey.currentContext!.findRenderObject() as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 3.0);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) throw Exception('No se pudo generar la imagen');
      final dir = await getTemporaryDirectory();
      final file = File(
        '${dir.path}/pedalea_plus_${DateTime.now().millisecondsSinceEpoch}.png',
      );
      await file.writeAsBytes(byteData.buffer.asUint8List());

      await Share.shareXFiles(
        [XFile(file.path)],
        text: '🚴 Ahora soy Pedalea Plus. Dale un plus a tu pedalear 💚',
      );
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(
          content: Text('No se pudo compartir: $e'),
          backgroundColor: Colors.redAccent,
        ),
      );
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          RepaintBoundary(
            key: _cardKey,
            child: Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(24),
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xFF2A2000), _kNavy],
                ),
                border: Border.all(color: Colors.amber.withOpacity(0.3)),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.workspace_premium_rounded, color: Colors.amber, size: 56),
                  const SizedBox(height: 16),
                  const Text(
                    'Ahora soy',
                    style: TextStyle(
                      fontFamily: 'Poppins', color: Colors.white70, fontSize: 14,
                    ),
                  ),
                  const Text(
                    'Pedalea Plus',
                    style: TextStyle(
                      fontFamily: 'Poppins', color: Colors.white,
                      fontSize: 26, fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'Dale un plus a tu pedalear 🚴💚',
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      color: Colors.amber.withOpacity(0.9),
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 28),
          const Text(
            '¡Cuéntale a tus amigos!',
            style: TextStyle(
              fontFamily: 'Poppins', color: Colors.white,
              fontSize: 18, fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Comparte que ahora eres Plus en tus redes',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: 'Poppins',
              color: Colors.white.withOpacity(0.5),
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _sharing ? null : _share,
              icon: _sharing
                  ? const SizedBox(
                      width: 16, height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.amber),
                    )
                  : const Icon(Icons.share_rounded, color: Colors.amber, size: 18),
              label: const Text('Compartir en redes'),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.amber,
                side: const BorderSide(color: Colors.amber),
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                textStyle: const TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w700),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

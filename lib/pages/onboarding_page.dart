import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _kNavy = Color(0xFF12213F);
const _kGreen = Color(0xFFC9FF5C);

class OnboardingPage extends StatefulWidget {
  final VoidCallback onDone;
  const OnboardingPage({super.key, required this.onDone});

  @override
  State<OnboardingPage> createState() => _OnboardingPageState();
}

class _OnboardingPageState extends State<OnboardingPage> {
  final _controller = PageController();
  int _page = 0;

  static const _slides = [
    _OnboardingSlide(
      icon: Icons.map_rounded,
      title: 'El mapa de ciclovías',
      body:
          'Todas las ciclovías, estacionamientos, talleres y puntos de agua de la Región Metropolitana, en un solo mapa.',
    ),
    _OnboardingSlide(
      icon: Icons.add_alert_rounded,
      title: 'Reporta y evita problemas',
      body:
          'Mantén presionado el mapa para reportar un incidente. Recibirás una alerta si te acercas a uno reportado por otros.',
    ),
    _OnboardingSlide(
      icon: Icons.groups_rounded,
      title: 'Eventos con otros ciclistas',
      body:
          'Únete o crea salidas grupales y coordina todo en el chat del evento.',
    ),
    _OnboardingSlide(
      icon: Icons.health_and_safety_rounded,
      title: 'Detección de caídas',
      body:
          'Si detectamos una caída fuerte, te preguntamos si estás bien. Si no respondes, llamamos a emergencias automáticamente.',
    ),
    _OnboardingSlide(
      icon: Icons.sos_rounded,
      title: 'Botón de pánico',
      body:
          'Guarda un contacto de confianza en tu perfil: con un toque puedes avisarle por SMS tu ubicación, o llamar a Carabineros/SAMU/Bomberos.',
    ),
  ];

  Future<void> _finish() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('onboarding_seen', true);
    widget.onDone();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isLast = _page == _slides.length - 1;
    return Scaffold(
      backgroundColor: _kNavy,
      body: SafeArea(
        child: Column(
          children: [
            Align(
              alignment: Alignment.topRight,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: TextButton(
                  onPressed: _finish,
                  child: Text(
                    'Saltar',
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      color: Colors.white.withOpacity(0.5),
                      fontSize: 14,
                    ),
                  ),
                ),
              ),
            ),
            Expanded(
              child: PageView.builder(
                controller: _controller,
                itemCount: _slides.length,
                onPageChanged: (i) => setState(() => _page = i),
                itemBuilder: (context, i) => _SlideView(slide: _slides[i]),
              ),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(_slides.length, (i) {
                final active = i == _page;
                return AnimatedContainer(
                  duration: const Duration(milliseconds: 250),
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  width: active ? 22 : 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: active ? _kGreen : Colors.white24,
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
                    if (isLast) {
                      _finish();
                    } else {
                      _controller.nextPage(
                        duration: const Duration(milliseconds: 300),
                        curve: Curves.easeOut,
                      );
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _kGreen,
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
                  child: Text(isLast ? 'Empezar' : 'Siguiente'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _OnboardingSlide {
  final IconData icon;
  final String title;
  final String body;
  const _OnboardingSlide({
    required this.icon,
    required this.title,
    required this.body,
  });
}

class _SlideView extends StatelessWidget {
  final _OnboardingSlide slide;
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
              color: _kGreen.withOpacity(0.1),
              border: Border.all(color: _kGreen.withOpacity(0.3), width: 1.5),
            ),
            child: Icon(slide.icon, color: _kGreen, size: 64),
          ),
          const SizedBox(height: 40),
          Text(
            slide.title,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontFamily: 'Poppins',
              color: Colors.white,
              fontSize: 24,
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

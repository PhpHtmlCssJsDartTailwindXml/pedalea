import 'package:flutter/material.dart';

const _kNavy = Color(0xFF12213F);

/// Se muestra justo después de que la compra (real o simulada) se confirma:
/// un mini-tutorial de lo que el usuario acaba de desbloquear con Plus.
class PlusUnlockedPage extends StatefulWidget {
  const PlusUnlockedPage({super.key, this.giftUntil});

  /// Si es un Plus de regalo, hasta cuándo dura (cambia la bienvenida).
  final DateTime? giftUntil;

  @override
  State<PlusUnlockedPage> createState() => _PlusUnlockedPageState();
}

class _PlusUnlockedPageState extends State<PlusUnlockedPage> {
  final _controller = PageController();
  int _page = 0;

  static const _baseSlides = [
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
      icon: Icons.all_inclusive_rounded,
      title: 'Sin límites',
      body: 'Planifica todas las rutas, publica todos los momentos que quieras y registra todas tus bicis.',
    ),
    _UnlockSlide(
      icon: Icons.local_fire_department_outlined,
      title: 'Mapa de calor y mapas premium',
      body: 'Activa tu mapa de calor y los estilos satélite, exterior y minimalista desde el menú lateral.',
    ),
    _UnlockSlide(
      icon: Icons.military_tech_rounded,
      title: 'Insignia distintiva',
      body: 'Un marco especial en tu perfil y en el chat de eventos, para que se note.',
    ),
  ];

  static const _months = [
    'enero', 'febrero', 'marzo', 'abril', 'mayo', 'junio', 'julio',
    'agosto', 'septiembre', 'octubre', 'noviembre', 'diciembre',
  ];

  /// Última pantalla: agradecimiento y lo que viene (en vez de compartir).
  _UnlockSlide get _closingSlide => widget.giftUntil == null
      ? const _UnlockSlide(
          icon: Icons.favorite_rounded,
          title: 'Gracias por apoyar Pedalea 💚',
          body:
              'Tu Plus nos ayuda a seguir creciendo. Vamos a seguir sumando '
              'funciones nuevas para quienes son Plus, pensadas para que '
              'pedalees mejor y más seguro.',
        )
      : const _UnlockSlide(
          icon: Icons.favorite_rounded,
          title: 'Esperamos que lo disfrutes 💚',
          body:
              'Vamos a seguir sumando funciones nuevas para quienes son Plus. '
              'Si te gusta, cuando termine tu regalo puedes seguir con Plus '
              'y apoyar a Pedalea.',
        );

  /// Con regalo, la primera pantalla lo anuncia; el resto es igual.
  List<_UnlockSlide> get _slides {
    final until = widget.giftUntil;
    if (until == null) return [..._baseSlides, _closingSlide];
    final d = until.toLocal();
    return [
      _UnlockSlide(
        icon: Icons.card_giftcard_rounded,
        title: '¡Te regalamos Pedalea Plus! 🎁',
        body:
            'El equipo de Pedalea te regala Plus hasta el ${d.day} de ${_months[d.month - 1]}. '
            'No tiene cobro ni se renueva solo. Esto es lo que desbloqueaste.',
      ),
      ..._baseSlides.skip(1),
      _closingSlide,
    ];
  }

  int get _totalPages => _slides.length;
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
                itemBuilder: (context, i) => _SlideView(slide: _slides[i]),
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

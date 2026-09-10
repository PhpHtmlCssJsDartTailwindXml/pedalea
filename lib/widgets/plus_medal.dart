import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../services/plus_prefs_service.dart';

/// Medalla Plus con brillo animado. Se usa en el perfil, el chat y el mapa
/// para distinguir a los ciclistas Pedalea Plus.
///
/// [variant] es el índice dentro de [PlusPrefsService.medalVariants]. Si no se
/// pasa, usa la variante que el propio usuario eligió en su perfil (por eso
/// para medallas de OTROS usuarios conviene pasar `variant: 0`).
class PlusMedal extends StatefulWidget {
  final double size;
  final int? variant;

  /// Borde oscuro alrededor de la medalla (para separarla del avatar).
  final Color ringColor;

  const PlusMedal({
    super.key,
    this.size = 22,
    this.variant,
    this.ringColor = const Color(0xFF08080F),
  });

  @override
  State<PlusMedal> createState() => _PlusMedalState();
}

class _PlusMedalState extends State<PlusMedal>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    )..repeat();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Si no se fija una variante, se sigue la que el usuario eligió y se
    // reacciona en vivo a los cambios.
    if (widget.variant == null) {
      return ValueListenableBuilder<int>(
        valueListenable: PlusPrefsService.medalVariant,
        builder: (context, idx, _) => _medal(idx),
      );
    }
    return _medal(widget.variant!);
  }

  Widget _medal(int idx) {
    final variants = PlusPrefsService.medalVariants; // (nombre, color)
    final glow = variants[idx.clamp(0, variants.length - 1)].$2;
    final isHolo = idx == variants.length - 1; // última = Holográfico
    final iconPad = widget.size * 0.16; // aro interno

    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) {
        // Pulso suave 0..1..0
        final t = (math.sin(_c.value * 2 * math.pi) + 1) / 2;
        final blur = 4.0 + t * 8.0;
        final spread = t * 1.5;
        return Container(
          padding: EdgeInsets.all(iconPad),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: isHolo
                ? SweepGradient(
                    transform: GradientRotation(_c.value * 2 * math.pi),
                    colors: const [
                      Color(0xFFBA68C8),
                      Color(0xFF4FC3F7),
                      Color(0xFF69FF47),
                      Color(0xFFFFCA28),
                      Color(0xFFEC407A),
                      Color(0xFFBA68C8),
                    ],
                  )
                : null,
            color: isHolo ? null : glow,
            border: Border.all(color: widget.ringColor, width: widget.size * 0.09),
            boxShadow: [
              BoxShadow(
                color: glow.withOpacity(0.55),
                blurRadius: blur,
                spreadRadius: spread,
              ),
            ],
          ),
          child: Icon(
            Icons.workspace_premium_rounded,
            size: widget.size * 0.72,
            color: isHolo ? Colors.white : _readableOn(glow),
          ),
        );
      },
    );
  }

  Color _readableOn(Color bg) {
    return bg.computeLuminance() > 0.5 ? Colors.black87 : Colors.white;
  }
}

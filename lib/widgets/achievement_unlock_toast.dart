import 'package:flutter/material.dart';
import 'achievement_badge.dart';

/// Notificación flotante ("toast") que se muestra dentro de la misma app
/// cuando el usuario acaba de completar un logro. Se apila sobre lo que
/// esté en pantalla usando el Overlay, con una entrada/salida animada,
/// y se cierra sola después de unos segundos (o al tocarla).
class AchievementUnlockToast extends StatefulWidget {
  final String achievementId;
  final String title;
  final VoidCallback onDismiss;

  const AchievementUnlockToast({
    super.key,
    required this.achievementId,
    required this.title,
    required this.onDismiss,
  });

  @override
  State<AchievementUnlockToast> createState() => _AchievementUnlockToastState();
}

class _AchievementUnlockToastState extends State<AchievementUnlockToast>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<Offset> _slide;
  late final Animation<double> _fade;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 450),
    );
    _slide = Tween<Offset>(begin: const Offset(0, -0.4), end: Offset.zero)
        .animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOutBack));
    _fade = CurvedAnimation(parent: _ctrl, curve: const Interval(0, 0.6, curve: Curves.easeOut));
    _ctrl.forward();
    Future.delayed(const Duration(milliseconds: 3200), _close);
  }

  Future<void> _close() async {
    if (!mounted) return;
    await _ctrl.reverse();
    widget.onDismiss();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SlideTransition(
        position: _slide,
        child: FadeTransition(
          opacity: _fade,
          child: Align(
            alignment: Alignment.topCenter,
            child: GestureDetector(
              onTap: _close,
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0xFF1E5C41), Color(0xFF12121C)],
                  ),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: const Color(0xFF7CF0BC).withOpacity(0.4)),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.35),
                      blurRadius: 18,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    AchievementBadge(id: widget.achievementId, size: 44),
                    const SizedBox(width: 12),
                    Flexible(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '¡Logro completado! 🎉',
                            style: TextStyle(
                              fontFamily: 'Poppins',
                              color: const Color(0xFFC9FF5C),
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.2,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            widget.title,
                            style: const TextStyle(
                              fontFamily: 'Poppins',
                              color: Colors.white,
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Muestra uno o varios toasts de logro desbloqueado, uno detrás de otro
/// (con un pequeño espacio entre cada uno si hay más de uno).
void showAchievementUnlockedToasts(
  BuildContext context,
  List<Map<String, String>> achievements,
) {
  if (achievements.isEmpty) return;
  final overlay = Overlay.of(context, rootOverlay: true);

  Future<void> showAt(int index) async {
    if (index >= achievements.length) return;
    final a = achievements[index];
    late OverlayEntry entry;
    entry = OverlayEntry(
      builder: (_) => AchievementUnlockToast(
        achievementId: a['id'] ?? '',
        title: a['title'] ?? 'Nuevo logro',
        onDismiss: () => entry.remove(),
      ),
    );
    overlay.insert(entry);
    await Future.delayed(const Duration(milliseconds: 3800));
    showAt(index + 1);
  }

  showAt(0);
}

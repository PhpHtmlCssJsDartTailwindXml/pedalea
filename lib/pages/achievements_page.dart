import 'package:flutter/material.dart';
import '../core/glass.dart';
import '../services/achievements_service.dart';
import '../widgets/achievement_badge.dart';

const _kCategoryOrder = [
  'kilometros', 'racha', 'mejor_dia', 'karma', 'co2',
  'alertas', 'eventos', 'rutas', 'fotos', 'plus', 'perfil',
];

const _kCategories = <String, (IconData, String)>{
  'kilometros': (Icons.directions_bike_rounded, 'Kilómetros'),
  'racha': (Icons.local_fire_department_rounded, 'Racha'),
  'mejor_dia': (Icons.bolt_rounded, 'Mejor día'),
  'karma': (Icons.shield_rounded, 'Karma'),
  'co2': (Icons.eco_rounded, 'CO₂ ahorrado'),
  'alertas': (Icons.warning_amber_rounded, 'Alertas'),
  'eventos': (Icons.celebration_rounded, 'Eventos'),
  'rutas': (Icons.map_rounded, 'Rutas favoritas'),
  'fotos': (Icons.photo_camera_rounded, 'Fotos de referencia'),
  'plus': (Icons.favorite_rounded, 'Pedalea Plus'),
  'perfil': (Icons.person_rounded, 'Perfil'),
};

const _kMonths = ['ene', 'feb', 'mar', 'abr', 'may', 'jun', 'jul', 'ago', 'sep', 'oct', 'nov', 'dic'];
const _kAccent = Color(0xFF7CF0BC);

TextStyle _t(double size, {FontWeight w = FontWeight.w500, Color c = Colors.white, double? h, double? ls}) =>
    TextStyle(fontFamily: 'Poppins', fontSize: size, fontWeight: w, color: c, height: h, letterSpacing: ls);

/// Muestra el detalle de un logro (también se usa desde el perfil).
void showAchievementDetailSheet(BuildContext context, Map<String, dynamic> achievement, bool unlocked) {
  final id = achievement['id'] as String?;
  final title = achievement['title'] as String? ?? '';
  final description = achievement['description'] as String? ?? '';
  final unlockedAt = achievement['unlocked_at'] as String?;
  String dateStr = '';
  if (unlockedAt != null) {
    final dt = DateTime.tryParse(unlockedAt)?.toLocal();
    if (dt != null) dateStr = '${dt.day} ${_kMonths[dt.month - 1]} ${dt.year}';
  }
  final tier = achievementTier(id);

  showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    builder: (_) => Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      padding: const EdgeInsets.fromLTRB(24, 14, 24, 26),
      decoration: BoxDecoration(
        color: const Color(0xFF12141C),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: Colors.white.withOpacity(0.07)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2)),
            ),
            const SizedBox(height: 22),
            AchievementBadge(id: id, unlocked: unlocked, size: 104),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.06),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(tierName(tier).toUpperCase(), style: _t(10.5, w: FontWeight.w700, c: Colors.white60, ls: 1.4)),
            ),
            const SizedBox(height: 10),
            Text(title, textAlign: TextAlign.center, style: _t(20, w: FontWeight.w700, c: unlocked ? Colors.white : Colors.white60)),
            const SizedBox(height: 6),
            Text(description, textAlign: TextAlign.center, style: _t(14, w: FontWeight.w400, c: Colors.white60, h: 1.4)),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(unlocked ? Icons.check_circle_rounded : Icons.lock_outline_rounded,
                    size: 16, color: unlocked ? _kAccent : Colors.white30),
                const SizedBox(width: 6),
                Text(
                  unlocked ? (dateStr.isNotEmpty ? 'Conseguido el $dateStr' : 'Conseguido') : 'Aún no conseguido',
                  style: _t(12.5, w: FontWeight.w600, c: unlocked ? _kAccent : Colors.white38),
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}

/// Pantalla completa de logros, agrupada por categoría — se abre desde
/// "Ver más" en el perfil.
class AchievementsPage extends StatefulWidget {
  const AchievementsPage({super.key});

  @override
  State<AchievementsPage> createState() => _AchievementsPageState();
}

class _AchievementsPageState extends State<AchievementsPage> {
  final _service = AchievementsService();
  List<Map<String, dynamic>> _achievements = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final data = await _service.getAllWithStatus();
    if (mounted) {
      setState(() {
        _achievements = data;
        _loading = false;
      });
    }
  }

  Map<String, List<Map<String, dynamic>>> get _byCategory {
    final map = <String, List<Map<String, dynamic>>>{};
    for (final a in _achievements) {
      final cat = a['category'] as String? ?? 'otros';
      map.putIfAbsent(cat, () => []).add(a);
    }
    return map;
  }

  @override
  Widget build(BuildContext context) {
    final byCategory = _byCategory;
    final categories = [
      ..._kCategoryOrder.where(byCategory.containsKey),
      ...byCategory.keys.where((c) => !_kCategoryOrder.contains(c)),
    ];

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Container(
        decoration: kPageGradient,
        child: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 4, 16, 4),
                child: Row(
                  children: [
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
                    ),
                    const SizedBox(width: 4),
                    Text('Logros', style: _t(19, w: FontWeight.w700)),
                  ],
                ),
              ),
              Expanded(
                child: _loading
                    ? const Center(child: CircularProgressIndicator(color: _kAccent))
                    : ListView(
                        padding: const EdgeInsets.fromLTRB(16, 4, 16, 28),
                        children: [
                          _summary(),
                          const SizedBox(height: 26),
                          for (final cat in categories) _section(cat, byCategory[cat]!),
                        ],
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Resumen: anillo de progreso y cuántas insignias hay de cada nivel.
  Widget _summary() {
    final unlocked = _achievements.where((a) => a['unlocked'] == true).toList();
    final total = _achievements.length;
    final pct = total > 0 ? unlocked.length / total : 0.0;
    int count(BadgeTier t) => unlocked.where((a) => achievementTier(a['id'] as String?) == t).length;

    Widget tierChip(BadgeTier t, Color c) => Column(
          children: [
            Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(shape: BoxShape.circle, color: c),
            ),
            const SizedBox(height: 6),
            Text('${count(t)}', style: _t(16, w: FontWeight.w800)),
            Text(tierName(t), style: _t(10.5, c: Colors.white54)),
          ],
        );

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.04),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withOpacity(0.06)),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 92,
            height: 92,
            child: Stack(
              alignment: Alignment.center,
              children: [
                SizedBox.expand(
                  child: CircularProgressIndicator(
                    value: pct,
                    strokeWidth: 7,
                    strokeCap: StrokeCap.round,
                    backgroundColor: Colors.white.withOpacity(0.08),
                    valueColor: const AlwaysStoppedAnimation(_kAccent),
                  ),
                ),
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('${unlocked.length}', style: _t(24, w: FontWeight.w800, h: 1.1)),
                    Text('de $total', style: _t(11, c: Colors.white54)),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 18),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Tu colección', style: _t(15, w: FontWeight.w700)),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    tierChip(BadgeTier.bronze, const Color(0xFFD08A55)),
                    tierChip(BadgeTier.silver, const Color(0xFFC3CBD8)),
                    tierChip(BadgeTier.gold, const Color(0xFFF2C230)),
                    tierChip(BadgeTier.platinum, const Color(0xFF9AA6FF)),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _section(String cat, List<Map<String, dynamic>> items) {
    final (icon, label) = _kCategories[cat] ?? (Icons.emoji_events_rounded, cat);
    final done = items.where((a) => a['unlocked'] == true).length;
    return Padding(
      padding: const EdgeInsets.only(bottom: 26),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: Colors.white70, size: 18),
              const SizedBox(width: 8),
              Text(label, style: _t(15, w: FontWeight.w700)),
              const Spacer(),
              Text('$done de ${items.length}', style: _t(12, c: Colors.white38)),
            ],
          ),
          const SizedBox(height: 14),
          LayoutBuilder(
            builder: (_, c) {
              const cols = 4;
              const gap = 10.0;
              final w = (c.maxWidth - gap * (cols - 1)) / cols;
              return Wrap(
                spacing: gap,
                runSpacing: 16,
                children: [for (final a in items) SizedBox(width: w, child: _badgeTile(a, a['unlocked'] == true))],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _badgeTile(Map<String, dynamic> achievement, bool unlocked) {
    final title = achievement['title'] as String? ?? '';
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => showAchievementDetailSheet(context, achievement, unlocked),
      child: Column(
        children: [
          AchievementBadge(id: achievement['id'] as String?, unlocked: unlocked, size: 62),
          const SizedBox(height: 8),
          Text(
            title,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: _t(10.5, w: FontWeight.w600, c: unlocked ? Colors.white : Colors.white38, h: 1.2),
          ),
        ],
      ),
    );
  }
}

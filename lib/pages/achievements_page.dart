import 'package:flutter/material.dart';
import '../core/glass.dart';
import '../services/achievements_service.dart';

const _kCategoryOrder = [
  'kilometros', 'racha', 'mejor_dia', 'karma', 'co2',
  'alertas', 'eventos', 'rutas', 'fotos', 'plus', 'perfil',
];

const _kCategoryLabels = {
  'kilometros': '🚴 Kilómetros',
  'racha': '🔥 Racha',
  'mejor_dia': '⚡ Mejor día',
  'karma': '🛡️ Karma',
  'co2': '🌱 CO₂ ahorrado',
  'alertas': '🚨 Alertas',
  'eventos': '🎉 Eventos',
  'rutas': '🗺️ Rutas favoritas',
  'fotos': '📸 Fotos de referencia',
  'plus': '💚 Pedalea Plus',
  'perfil': '🧑 Perfil',
};

/// Pantalla completa de logros, agrupada por categoría — se abre desde
/// "Ver más" en el perfil, en vez de mostrar todos los logros ahí mismo.
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
    if (mounted) setState(() { _achievements = data; _loading = false; });
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
    final unlockedCount = _achievements.where((a) => a['unlocked'] == true).length;
    final total = _achievements.length;
    final byCategory = _byCategory;
    final categories = [
      ..._kCategoryOrder.where(byCategory.containsKey),
      ...byCategory.keys.where((c) => !_kCategoryOrder.contains(c)),
    ];

    return Scaffold(
      backgroundColor: Colors.transparent,
      extendBodyBehindAppBar: true,
      body: Container(
        decoration: kPageGradient,
        child: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Row(
                  children: [
                    GestureDetector(
                      onTap: () => Navigator.pop(context),
                      child: Container(
                        width: 40,
                        height: 40,
                        decoration: glassDecoration(radius: 12),
                        child: const Icon(Icons.arrow_back_ios_new, color: Colors.white, size: 18),
                      ),
                    ),
                    const SizedBox(width: 12),
                    const Text(
                      'Mis Logros',
                      style: TextStyle(fontFamily: 'Poppins', color: Colors.white, fontWeight: FontWeight.w600, fontSize: 18),
                    ),
                    const Spacer(),
                    if (!_loading)
                      Text(
                        '$unlockedCount / $total',
                        style: const TextStyle(fontFamily: 'Poppins', color: Colors.greenAccent, fontSize: 13, fontWeight: FontWeight.w700),
                      ),
                  ],
                ),
              ),
              if (!_loading)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: total > 0 ? unlockedCount / total : 0,
                      backgroundColor: Colors.white10,
                      valueColor: const AlwaysStoppedAnimation(Colors.greenAccent),
                      minHeight: 5,
                    ),
                  ),
                ),
              Expanded(
                child: _loading
                    ? const Center(child: CircularProgressIndicator(color: Colors.greenAccent))
                    : ListView.builder(
                        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                        itemCount: categories.length,
                        itemBuilder: (_, i) {
                          final cat = categories[i];
                          final items = byCategory[cat]!;
                          final unlockedInCat = items.where((a) => a['unlocked'] == true).length;
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 22),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Text(
                                      _kCategoryLabels[cat] ?? cat,
                                      style: const TextStyle(fontFamily: 'Poppins', color: Colors.white, fontSize: 14, fontWeight: FontWeight.w700),
                                    ),
                                    const Spacer(),
                                    Text(
                                      '$unlockedInCat/${items.length}',
                                      style: TextStyle(fontFamily: 'Poppins', color: Colors.grey[500], fontSize: 12),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 10),
                                Wrap(
                                  spacing: 10,
                                  runSpacing: 10,
                                  children: items.map((a) => _badgeTile(a, a['unlocked'] == true)).toList(),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _badgeTile(Map<String, dynamic> achievement, bool unlocked) {
    final icon = achievement['icon'] as String? ?? '🏅';
    final title = achievement['title'] as String? ?? '';

    return GestureDetector(
      onTap: () => _showAchievementDetail(achievement, unlocked),
      child: Container(
        width: 84,
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        decoration: glassDecoration(
          radius: 16,
          tint: unlocked ? Colors.greenAccent : Colors.white,
          opacity: unlocked ? 0.08 : 0.03,
          borderOpacity: unlocked ? 0.2 : 0.07,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ColorFiltered(
              colorFilter: unlocked
                  ? const ColorFilter.mode(Colors.transparent, BlendMode.dst)
                  : const ColorFilter.matrix([
                      0.2126, 0.7152, 0.0722, 0, 0,
                      0.2126, 0.7152, 0.0722, 0, 0,
                      0.2126, 0.7152, 0.0722, 0, 0,
                      0,      0,      0,      0.3, 0,
                    ]),
              child: Text(icon, style: const TextStyle(fontSize: 28)),
            ),
            const SizedBox(height: 6),
            Text(
              title,
              style: TextStyle(
                fontFamily: 'Poppins',
                color: unlocked ? Colors.white : Colors.white24,
                fontSize: 10,
                fontWeight: FontWeight.w600,
              ),
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }

  void _showAchievementDetail(Map<String, dynamic> achievement, bool unlocked) {
    final icon = achievement['icon'] as String? ?? '🏅';
    final title = achievement['title'] as String? ?? '';
    final description = achievement['description'] as String? ?? '';
    final unlockedAt = achievement['unlocked_at'] as String?;

    String dateStr = '';
    if (unlockedAt != null) {
      final dt = DateTime.tryParse(unlockedAt)?.toLocal();
      if (dt != null) {
        const months = ['ene', 'feb', 'mar', 'abr', 'may', 'jun', 'jul', 'ago', 'sep', 'oct', 'nov', 'dic'];
        dateStr = '${dt.day} ${months[dt.month - 1]} ${dt.year}';
      }
    }

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => Container(
        margin: const EdgeInsets.all(16),
        padding: const EdgeInsets.all(24),
        decoration: glassDecoration(
          radius: 24,
          tint: unlocked ? Colors.greenAccent : Colors.white,
          opacity: unlocked ? 0.1 : 0.05,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(icon, style: const TextStyle(fontSize: 52)),
            const SizedBox(height: 12),
            Text(
              title,
              style: TextStyle(fontFamily: 'Poppins', color: unlocked ? Colors.white : Colors.white38, fontSize: 20, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Text(
              description,
              style: const TextStyle(fontFamily: 'Poppins', color: Colors.white60, fontSize: 14),
              textAlign: TextAlign.center,
            ),
            if (unlocked && dateStr.isNotEmpty) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.greenAccent.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: Colors.greenAccent.withOpacity(0.2)),
                ),
                child: Text(
                  'Desbloqueado el $dateStr',
                  style: const TextStyle(fontFamily: 'Poppins', color: Colors.greenAccent, fontSize: 12, fontWeight: FontWeight.w500),
                ),
              ),
            ],
            if (!unlocked) ...[
              const SizedBox(height: 16),
              const Text('Aún no desbloqueado', style: TextStyle(fontFamily: 'Poppins', color: Colors.white24, fontSize: 12)),
            ],
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

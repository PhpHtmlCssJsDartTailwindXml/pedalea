import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../core/glass.dart';
import '../services/ride_stats_service.dart';
import '../services/co2_service.dart';
import '../services/subscription_service.dart';
import '../widgets/bike_lane_painter.dart';
import 'paywall_page.dart';

/// Pantalla de progreso del ciclista: hoy, semana, racha y totales.
class StatsPage extends StatefulWidget {
  const StatsPage({super.key});

  @override
  State<StatsPage> createState() => _StatsPageState();
}

class _StatsPageState extends State<StatsPage> {
  static const _accent = Color(0xFF69FF47);

  late List<DayStat> _week;
  late double _today;
  late double _weekKm;
  late double _total;
  late int _streak;
  late int _activeDays;
  late double _bestDay;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  void _refresh() {
    _week = RideStatsService.last7Days();
    _today = RideStatsService.todayKm();
    _weekKm = RideStatsService.weekKm();
    _total = RideStatsService.totalKm();
    _streak = RideStatsService.currentStreak();
    _activeDays = RideStatsService.activeDays();
    _bestDay = RideStatsService.bestDayKm();
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: kPageGradient,
        child: SafeArea(
          child: Column(
            children: [
              _buildHeader(),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
                  children: [
                    _buildTodayHero(),
                    const SizedBox(height: 16),
                    _buildWeekChart(),
                    const SizedBox(height: 16),
                    _buildStatGrid(),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
            onPressed: () => Navigator.pop(context),
          ),
          const Text(
            'Mis estadísticas',
            style: TextStyle(
              fontFamily: 'Poppins',
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.w700,
            ),
          ),
          const Spacer(),
          IconButton(
            icon: const Icon(Icons.ios_share_rounded, color: _accent),
            tooltip: 'Compartir resumen',
            onPressed: _openShareSheet,
          ),
          IconButton(
            icon: const Icon(Icons.refresh_rounded, color: Colors.white54),
            onPressed: _refresh,
          ),
        ],
      ),
    );
  }

  void _openShareSheet() {
    if (!SubscriptionService.instance.isPlus.value) {
      showModalBottomSheet(
        context: context,
        backgroundColor: Colors.transparent,
        builder: (_) => _StatsShareUpsellSheet(
          onUpgrade: () {
            Navigator.pop(context);
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => const PaywallPage(
                  reason: 'Comparte tus estadísticas en historias con Pedalea Plus.',
                ),
              ),
            );
          },
        ),
      );
      return;
    }
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _ShareSheet(
        today: _today,
        total: _total,
        weekKm: _weekKm,
        streak: _streak,
        bestDay: _bestDay,
        activeDays: _activeDays,
      ),
    );
  }

  Widget _buildTodayHero() {
    final co2 = Co2Service.savedKg(_today);
    final tree = Co2Service.treeEquivalent(co2);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [_accent.withOpacity(0.18), _accent.withOpacity(0.04)],
        ),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: _accent.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'HOY',
            style: TextStyle(
              fontFamily: 'Poppins',
              color: Colors.white54,
              fontSize: 13,
              fontWeight: FontWeight.w600,
              letterSpacing: 1.5,
            ),
          ),
          const SizedBox(height: 6),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                _today.toStringAsFixed(1),
                style: const TextStyle(
                  fontFamily: 'Poppins',
                  color: Colors.white,
                  fontSize: 52,
                  fontWeight: FontWeight.w800,
                  height: 1,
                ),
              ),
              const SizedBox(width: 8),
              const Padding(
                padding: EdgeInsets.only(bottom: 8),
                child: Text(
                  'km',
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    color: _accent,
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              const Icon(Icons.eco_rounded, color: _accent, size: 18),
              const SizedBox(width: 6),
              Text(
                '${Co2Service.format(co2)} de CO₂ ahorrado hoy',
                style: const TextStyle(
                  fontFamily: 'Poppins',
                  color: Colors.white70,
                  fontSize: 14,
                ),
              ),
            ],
          ),
          if (tree.isNotEmpty) ...[
            const SizedBox(height: 4),
            Padding(
              padding: const EdgeInsets.only(left: 24),
              child: Text(
                tree,
                style: const TextStyle(
                  fontFamily: 'Poppins',
                  color: Colors.white38,
                  fontSize: 12,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildWeekChart() {
    final maxKm = _week.fold<double>(
      0.1,
      (m, e) => e.km > m ? e.km : m,
    );
    const labels = ['L', 'M', 'M', 'J', 'V', 'S', 'D']; // weekday 1..7
    final todayKey = RideStatsService.dayKey(DateTime.now());

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 12),
      decoration: glassDecoration(radius: 22, opacity: 0.06),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Últimos 7 días',
                style: TextStyle(
                  fontFamily: 'Poppins',
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Text(
                '${_weekKm.toStringAsFixed(1)} km',
                style: const TextStyle(
                  fontFamily: 'Poppins',
                  color: _accent,
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 130,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: _week.map((d) {
                final isToday = RideStatsService.dayKey(d.date) == todayKey;
                final h = (d.km / maxKm) * 96;
                return Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      Text(
                        d.km > 0 ? d.km.toStringAsFixed(1) : '',
                        style: TextStyle(
                          fontFamily: 'Poppins',
                          color: isToday ? _accent : Colors.white54,
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Container(
                        width: 18,
                        height: h < 4 ? 4 : h,
                        decoration: BoxDecoration(
                          color: isToday
                              ? _accent
                              : Colors.white.withOpacity(0.22),
                          borderRadius: BorderRadius.circular(6),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        labels[d.date.weekday - 1],
                        style: TextStyle(
                          fontFamily: 'Poppins',
                          color: isToday ? _accent : Colors.white38,
                          fontSize: 11,
                          fontWeight: isToday
                              ? FontWeight.w700
                              : FontWeight.w400,
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatGrid() {
    final co2Total = Co2Service.savedKg(_total);
    final tiles = [
      _StatTile('🔥', 'Racha', '$_streak ${_streak == 1 ? "día" : "días"}',
          'seguidos'),
      _StatTile('🏆', 'Mejor día', _bestDay.toStringAsFixed(1), 'km'),
      _StatTile('🛣️', 'Total', _total.toStringAsFixed(1), 'km'),
      _StatTile('📅', 'Días activos', '$_activeDays', 'días'),
      _StatTile('🌱', 'CO₂ total', Co2Service.format(co2Total), 'ahorrado'),
      _StatTile('🚴', 'Esta semana', _weekKm.toStringAsFixed(1), 'km'),
    ];
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 12,
      crossAxisSpacing: 12,
      childAspectRatio: 1.55,
      children: tiles,
    );
  }
}

/// Invita a suscribirse a Pedalea Plus cuando el usuario gratis intenta
/// compartir su resumen de estadísticas.
class _StatsShareUpsellSheet extends StatelessWidget {
  final VoidCallback onUpgrade;
  const _StatsShareUpsellSheet({required this.onUpgrade});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).padding.bottom + 16,
        left: 16,
        right: 16,
        top: 16,
      ),
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFF0F0F1A),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: Colors.amber.withOpacity(0.25)),
        ),
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.amber.withOpacity(0.12),
                border: Border.all(color: Colors.amber.withOpacity(0.35)),
              ),
              child: const Icon(Icons.ios_share_rounded, color: Colors.amber, size: 30),
            ),
            const SizedBox(height: 16),
            const Text(
              'Compartir tus estadísticas es Plus',
              style: TextStyle(
                fontFamily: 'Poppins', color: Colors.white,
                fontSize: 17, fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Hazte Pedalea Plus para compartir tu progreso como imagen en tus historias.',
              textAlign: TextAlign.center,
              style: TextStyle(fontFamily: 'Poppins', color: Colors.white60, fontSize: 13),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: onUpgrade,
                icon: const Icon(Icons.workspace_premium_rounded, size: 18),
                label: const Text('Ver Pedalea Plus'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.amber,
                  foregroundColor: Colors.black,
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  textStyle: const TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w700),
                ),
              ),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () => Navigator.pop(context),
              style: TextButton.styleFrom(foregroundColor: Colors.white38),
              child: const Text('Ahora no', style: TextStyle(fontFamily: 'Poppins')),
            ),
          ],
        ),
      ),
    );
  }
}

/// Hoja inferior con la tarjeta de resumen lista para compartir como imagen.
class _ShareSheet extends StatefulWidget {
  final double today;
  final double total;
  final double weekKm;
  final int streak;
  final double bestDay;
  final int activeDays;
  const _ShareSheet({
    required this.today,
    required this.total,
    required this.weekKm,
    required this.streak,
    required this.bestDay,
    required this.activeDays,
  });

  @override
  State<_ShareSheet> createState() => _ShareSheetState();
}

class _ShareSheetState extends State<_ShareSheet> {
  final GlobalKey _cardKey = GlobalKey();
  bool _sharing = false;

  // ── Personalización de la tarjeta ─────────────────────────────────────
  // Mapa de metadata (emoji + etiqueta) de cada estadística reordenable.
  // "co2" se maneja aparte porque tiene su propio diseño destacado en la
  // tarjeta y siempre va al final.
  static const _statMeta = {
    'today': ('🚴', 'Hoy'),
    'weekKm': ('📆', 'Semana'),
    'streak': ('🔥', 'Racha'),
    'bestDay': ('🏆', 'Mejor día'),
    'activeDays': ('📅', 'Días activo'),
  };
  // Orden actual de las mini-estadísticas: se puede arrastrar para cambiarlo.
  final List<String> _order = ['streak', 'bestDay', 'activeDays', 'today', 'weekKm'];
  final Set<String> _shownStats = {
    'streak', 'bestDay', 'activeDays', 'co2',
  };

  static const _colorPresets = [
    Color(0xFF69FF47), // verde (por defecto)
    Color(0xFF4FC3F7), // celeste
    Color(0xFFFF7043), // naranjo
    Color(0xFFBA68C8), // púrpura
    Color(0xFFFFCA28), // ámbar
    Color(0xFFEC407A), // rosado
  ];
  Color _accentColor = _colorPresets.first;

  void _toggleStat(String key) {
    setState(() {
      if (_shownStats.contains(key)) {
        _shownStats.remove(key);
      } else {
        _shownStats.add(key);
      }
    });
  }

  Future<void> _share() async {
    if (_sharing) return;
    setState(() => _sharing = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      // Pequeña espera para garantizar que la tarjeta esté pintada.
      await Future.delayed(const Duration(milliseconds: 60));
      final boundary =
          _cardKey.currentContext!.findRenderObject() as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 3.0);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) throw Exception('No se pudo generar la imagen');
      final dir = await getTemporaryDirectory();
      final file = File(
        '${dir.path}/pedalea_resumen_${DateTime.now().millisecondsSinceEpoch}.png',
      );
      await file.writeAsBytes(byteData.buffer.asUint8List());

      final co2 = Co2Service.savedKg(widget.total);
      await Share.shareXFiles(
        [XFile(file.path)],
        text:
            '🚴 Mi resumen en Pedalea: ${widget.total.toStringAsFixed(1)} km '
            'pedaleados y ${Co2Service.format(co2)} de CO₂ ahorrado. '
            '¡Pedalea Santiago! 🌱',
      );
      if (mounted) Navigator.pop(context);
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(
          content: Text('No se pudo compartir: $e'),
          backgroundColor: Colors.redAccent,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xF50A0A12),
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.fromLTRB(
        16,
        12,
        16,
        MediaQuery.of(context).padding.bottom + 16,
      ),
      child: SingleChildScrollView(
        child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 40,
            height: 4,
            margin: const EdgeInsets.only(bottom: 16),
            decoration: BoxDecoration(
              color: Colors.white24,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          // La tarjeta que se exporta como imagen.
          RepaintBoundary(
            key: _cardKey,
            child: _ShareCard(
              today: widget.today,
              total: widget.total,
              weekKm: widget.weekKm,
              streak: widget.streak,
              bestDay: widget.bestDay,
              activeDays: widget.activeDays,
              accentColor: _accentColor,
              shownStats: _shownStats,
              statOrder: _order,
            ),
          ),
          const SizedBox(height: 20),
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              'COLOR DE FONDO',
              style: TextStyle(
                fontFamily: 'Poppins',
                color: Colors.white.withOpacity(0.4),
                fontSize: 11,
                fontWeight: FontWeight.w600,
                letterSpacing: 1,
              ),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: _colorPresets.map((c) {
              final isSelected = c == _accentColor;
              return Padding(
                padding: const EdgeInsets.only(right: 12),
                child: GestureDetector(
                  onTap: () => setState(() => _accentColor = c),
                  child: Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: c,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: isSelected ? Colors.white : Colors.transparent,
                        width: 2.5,
                      ),
                    ),
                    child: isSelected
                        ? const Icon(Icons.check, color: Colors.black, size: 16)
                        : null,
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 20),
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              'QUÉ MOSTRAR (mantén presionado y arrastra para ordenar)',
              style: TextStyle(
                fontFamily: 'Poppins',
                color: Colors.white.withOpacity(0.4),
                fontSize: 11,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.5,
              ),
            ),
          ),
          const SizedBox(height: 10),
          ReorderableListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            buildDefaultDragHandles: false,
            itemCount: _order.length,
            onReorder: (oldIndex, newIndex) {
              setState(() {
                if (newIndex > oldIndex) newIndex--;
                final item = _order.removeAt(oldIndex);
                _order.insert(newIndex, item);
              });
            },
            itemBuilder: (context, i) {
              final key = _order[i];
              final (emoji, label) = _statMeta[key]!;
              final selected = _shownStats.contains(key);
              return Container(
                key: ValueKey(key),
                margin: const EdgeInsets.only(bottom: 8),
                decoration: BoxDecoration(
                  color: selected ? _accentColor.withOpacity(0.12) : Colors.white.withOpacity(0.04),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: selected ? _accentColor.withOpacity(0.4) : Colors.white12,
                  ),
                ),
                child: ListTile(
                  dense: true,
                  onTap: () => _toggleStat(key),
                  leading: Icon(
                    selected ? Icons.check_circle : Icons.circle_outlined,
                    color: selected ? _accentColor : Colors.white38,
                    size: 20,
                  ),
                  title: Text(
                    '$emoji $label',
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 13,
                      color: selected ? Colors.white : Colors.white54,
                      fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                    ),
                  ),
                  trailing: ReorderableDragStartListener(
                    index: i,
                    child: const Icon(Icons.drag_handle_rounded, color: Colors.white38),
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 8),
          FilterChip(
            selected: _shownStats.contains('co2'),
            onSelected: (_) => _toggleStat('co2'),
            showCheckmark: false,
            label: const Text('🌱 CO₂ ahorrado'),
            labelStyle: TextStyle(
              fontFamily: 'Poppins',
              fontSize: 12,
              color: _shownStats.contains('co2') ? Colors.black : Colors.white70,
              fontWeight: _shownStats.contains('co2') ? FontWeight.w700 : FontWeight.w400,
            ),
            backgroundColor: Colors.white.withOpacity(0.06),
            selectedColor: _accentColor,
            side: BorderSide(
              color: _shownStats.contains('co2') ? Colors.transparent : Colors.white24,
            ),
          ),
          const SizedBox(height: 18),
          SizedBox(
            width: double.infinity,
            height: 50,
            child: ElevatedButton.icon(
              onPressed: _sharing ? null : _share,
              icon: _sharing
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        color: Colors.black,
                        strokeWidth: 2,
                      ),
                    )
                  : const Icon(Icons.ios_share_rounded, size: 18),
              label: Text(_sharing ? 'Generando...' : 'Compartir mi resumen'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF69FF47),
                foregroundColor: Colors.black,
                disabledBackgroundColor: Colors.white12,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                textStyle: const TextStyle(
                  fontFamily: 'Poppins',
                  fontWeight: FontWeight.w700,
                  fontSize: 15,
                ),
                elevation: 0,
              ),
            ),
          ),
        ],
        ),
      ),
    );
  }
}

/// Tarjeta visual del resumen (diseño pensado para redes sociales).
class _ShareCard extends StatelessWidget {
  final double today;
  final double total;
  final double weekKm;
  final int streak;
  final double bestDay;
  final int activeDays;
  final Color accentColor;
  final Set<String> shownStats;
  final List<String> statOrder;
  const _ShareCard({
    required this.today,
    required this.total,
    required this.weekKm,
    required this.streak,
    required this.bestDay,
    required this.activeDays,
    required this.accentColor,
    required this.shownStats,
    required this.statOrder,
  });

  Widget? _buildStat(String key) {
    switch (key) {
      case 'today':
        return _miniStat('🚴', today.toStringAsFixed(1), 'hoy (km)');
      case 'weekKm':
        return _miniStat('📆', weekKm.toStringAsFixed(1), 'semana (km)');
      case 'streak':
        return _miniStat('🔥', '$streak', streak == 1 ? 'día racha' : 'días racha');
      case 'bestDay':
        return _miniStat('🏆', bestDay.toStringAsFixed(0), 'mejor día');
      case 'activeDays':
        return _miniStat('📅', '$activeDays', 'días activo');
      default:
        return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final co2 = Co2Service.savedKg(total);
    final accent = accentColor;

    final miniStats = statOrder
        .where(shownStats.contains)
        .map(_buildStat)
        .whereType<Widget>()
        .toList();

    return Container(
      width: 320,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: accent.withOpacity(0.25)),
      ),
      child: Stack(
        children: [
          // Fondo degradado
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Color.lerp(accent, Colors.black, 0.82)!,
                    const Color(0xFF06060C),
                  ],
                ),
              ),
            ),
          ),
          // Línea de ciclovía de fondo — siempre presente, marca de Pedalea.
          Positioned.fill(
            child: IgnorePointer(
              child: CustomPaint(
                painter: BikeLanePainter(color: accent.withOpacity(0.28)),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Marca
                Row(
                  children: [
                    Image.asset(
                      'assets/icono_ciclista.png',
                      width: 28,
                      height: 28,
                      errorBuilder: (_, _, _) =>
                          Icon(Icons.directions_bike, color: accent, size: 26),
                    ),
                    const SizedBox(width: 8),
                    const Text(
                      'Pedalea',
                      style: TextStyle(
                        fontFamily: 'Poppins',
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const Spacer(),
                    const Text(
                      '🚴',
                      style: TextStyle(fontSize: 20),
                    ),
                  ],
                ),
                const SizedBox(height: 22),
                // Total destacado
                const Text(
                  'KILÓMETROS PEDALEADOS',
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    color: Colors.white54,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 1.5,
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Text(
                      total.toStringAsFixed(1),
                      style: const TextStyle(
                        fontFamily: 'Poppins',
                        color: Colors.white,
                        fontSize: 56,
                        fontWeight: FontWeight.w800,
                        height: 1,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Text(
                        'km',
                        style: TextStyle(
                          fontFamily: 'Poppins',
                          color: accent,
                          fontSize: 24,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
                if (miniStats.isNotEmpty) ...[
                  const SizedBox(height: 18),
                  Container(height: 1, color: Colors.white12),
                  const SizedBox(height: 18),
                  Wrap(
                    alignment: WrapAlignment.spaceBetween,
                    runSpacing: 14,
                    children: miniStats,
                  ),
                ],
                if (shownStats.contains('co2')) ...[
                  const SizedBox(height: 18),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    decoration: BoxDecoration(
                      color: accent.withOpacity(0.10),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.eco_rounded, color: accent, size: 20),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            '${Co2Service.format(co2)} de CO₂ que no contaminaste',
                            style: const TextStyle(
                              fontFamily: 'Poppins',
                              color: Colors.white,
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                const Center(
                  child: Text(
                    'Pedalea Santiago 🇨🇱',
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      color: Colors.white38,
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _miniStat(String emoji, String value, String label) {
    return SizedBox(
      width: 84,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(emoji, style: const TextStyle(fontSize: 18)),
          const SizedBox(height: 4),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              value,
              maxLines: 1,
              style: const TextStyle(
                fontFamily: 'Poppins',
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          Text(
            label,
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontFamily: 'Poppins',
              color: Colors.white54,
              fontSize: 10,
            ),
          ),
        ],
      ),
    );
  }
}

class _StatTile extends StatelessWidget {
  final String emoji;
  final String label;
  final String value;
  final String unit;
  const _StatTile(this.emoji, this.label, this.value, this.unit);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: glassDecoration(radius: 18, opacity: 0.06),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Row(
            children: [
              Text(emoji, style: const TextStyle(fontSize: 18)),
              const SizedBox(width: 6),
              Text(
                label,
                style: const TextStyle(
                  fontFamily: 'Poppins',
                  color: Colors.white54,
                  fontSize: 13,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Flexible(
                child: Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontFamily: 'Poppins',
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const SizedBox(width: 4),
              Text(
                unit,
                style: const TextStyle(
                  fontFamily: 'Poppins',
                  color: Colors.white38,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

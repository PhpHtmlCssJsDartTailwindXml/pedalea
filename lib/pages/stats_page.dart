import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../core/glass.dart';
import '../services/ride_stats_service.dart';
import '../services/ride_stats_sync_service.dart';
import '../services/co2_service.dart';
import '../services/stats_prefs_service.dart';
import '../services/plus_prefs_service.dart';
import '../services/subscription_service.dart';
import '../widgets/bike_lane_painter.dart';
import 'paywall_page.dart';
import 'rider_ranking_page.dart';

const _mesesCortos = [
  'ene', 'feb', 'mar', 'abr', 'may', 'jun',
  'jul', 'ago', 'sep', 'oct', 'nov', 'dic',
];

String _fmtDia(DateTime d) => '${d.day} ${_mesesCortos[d.month - 1]}';

/// Pantalla de progreso del ciclista: hoy, gráfico y totales.
///
/// Se puede personalizar (botón «afinar» en la cabecera): reordenar y ocultar
/// tarjetas, elegir el color de acento y el rango del gráfico. Todo se guarda
/// en el dispositivo vía [StatsPrefsService].
class StatsPage extends StatefulWidget {
  const StatsPage({super.key});

  @override
  State<StatsPage> createState() => _StatsPageState();
}

class _StatsPageState extends State<StatsPage> {
  // Metadatos (emoji + etiqueta) de cada tarjeta reordenable del grid.
  static const _tileMeta = <String, (String, String)>{
    'streak': ('🔥', 'Racha'),
    'bestDay': ('🏆', 'Mejor día'),
    'total': ('🛣️', 'Total'),
    'activeDays': ('📅', 'Días activos'),
    'co2': ('🌱', 'CO₂ total'),
    'week': ('🚴', 'Esta semana'),
    'maxSpeed': ('⚡', 'Vel. máx'),
  };

  late List<DayStat> _chartDays;
  int _chartRange = 7; // 7 o 30 días
  int _selectedBar = -1;

  double _today = 0, _weekKm = 0, _total = 0, _bestDay = 0, _maxSpeed = 0;
  int _streak = 0, _activeDays = 0;
  double? _serverTotal; // total histórico real (profiles.total_km)
  bool _syncing = false;

  bool get _isPlus => SubscriptionService.instance.isPlus.value;

  /// Índice de acento efectivo (acotado y con fallback si dejó de ser Plus).
  int get _accentIndex => StatsPrefsService.effectiveAccentIndex(
      PlusPrefsService.accentIndex.value, _isPlus);
  Color get _accent => StatsPrefsService.allAccentColors[_accentIndex];
  List<Color> get _accentGrad =>
      StatsPrefsService.accentGradientFor(_accentIndex);

  final List<String> _order = StatsPrefsService.tileOrder;
  final Set<String> _hidden = {...StatsPrefsService.hiddenTiles};
  bool _editMode = false;

  @override
  void initState() {
    super.initState();
    _chartRange = StatsPrefsService.chartRange;
    PlusPrefsService.accentIndex.addListener(_onPrefsChanged);
    SubscriptionService.instance.isPlus.addListener(_onPrefsChanged);
    PlusPrefsService.refresh(); // por si cambió en otro dispositivo
    _load();
    _syncFromServer();
  }

  void _onPrefsChanged() {
    if (mounted) setState(() {}); // repinta con el acento nuevo
  }

  @override
  void dispose() {
    PlusPrefsService.accentIndex.removeListener(_onPrefsChanged);
    SubscriptionService.instance.isPlus.removeListener(_onPrefsChanged);
    super.dispose();
  }

  void _load() {
    _chartDays = RideStatsService.lastNDays(_chartRange);
    _today = RideStatsService.todayKm();
    _weekKm = RideStatsService.weekKm();
    _total = _serverTotal ?? RideStatsService.totalKm();
    _streak = RideStatsService.currentStreak();
    _activeDays = RideStatsService.activeDays();
    _bestDay = RideStatsService.bestDayKm();
    _maxSpeed = RideStatsService.maxSpeedKmh();
    _selectedBar = -1;
    setState(() {});
  }

  /// Baja las estadísticas del servidor (Supabase) y refresca la vista. Así
  /// "Mis estadísticas" refleja los km reales aunque se haya reinstalado la
  /// app o se pedalee desde otro teléfono.
  Future<void> _syncFromServer() async {
    if (_syncing) return;
    setState(() => _syncing = true);
    try {
      final total = await RideStatsSyncService.instance.pull();
      if (!mounted) return;
      if (total != null) _serverTotal = total;
    } finally {
      if (mounted) {
        setState(() => _syncing = false);
        _load();
      }
    }
  }

  (String, String) _tileValue(String key) {
    switch (key) {
      case 'streak':
        return ('$_streak', _streak == 1 ? 'día seguido' : 'días seguidos');
      case 'bestDay':
        return (_bestDay.toStringAsFixed(1), 'km');
      case 'total':
        return (_total.toStringAsFixed(1), 'km');
      case 'activeDays':
        return ('$_activeDays', _activeDays == 1 ? 'día' : 'días');
      case 'co2':
        return (Co2Service.format(Co2Service.savedKg(_total)), 'ahorrado');
      case 'week':
        return (_weekKm.toStringAsFixed(1), 'km');
      case 'maxSpeed':
        return (_maxSpeed <= 0 ? '—' : _maxSpeed.toStringAsFixed(1), 'km/h');
      default:
        return ('', '');
    }
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
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                  children: [
                    _buildTodayHero(),
                    const SizedBox(height: 16),
                    _buildChartCard(),
                    const SizedBox(height: 16),
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 200),
                      child: _editMode
                          ? _buildEditPanel()
                          : _buildStatGrid(),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Cabecera ──────────────────────────────────────────────────────────
  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 8, 4, 4),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
            onPressed: () => Navigator.pop(context),
          ),
          const Expanded(
            child: Text(
              'Mis estadísticas',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontFamily: 'Poppins',
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          IconButton(
            icon: Icon(
              _editMode ? Icons.check_rounded : Icons.tune_rounded,
              color: _editMode ? _accent : Colors.white54,
            ),
            tooltip: _editMode ? 'Listo' : 'Personalizar',
            onPressed: () => setState(() => _editMode = !_editMode),
          ),
          IconButton(
            icon: Icon(Icons.ios_share_rounded, color: _accent),
            tooltip: 'Compartir resumen',
            onPressed: _openShareSheet,
          ),
          if (!_editMode) ...[
            IconButton(
              icon: const Icon(Icons.emoji_events_rounded,
                  color: Colors.white54),
              tooltip: 'Ranking de ciclistas',
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const RiderRankingPage()),
              ),
            ),
            IconButton(
              icon: _syncing
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white54),
                    )
                  : const Icon(Icons.refresh_rounded, color: Colors.white54),
              onPressed: _syncing ? null : _syncFromServer,
            ),
          ],
        ],
      ),
    );
  }

  // ── Hero de hoy ───────────────────────────────────────────────────────
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
          colors: [
            _accentGrad.first.withOpacity(0.22),
            _accentGrad.last.withOpacity(0.05),
          ],
        ),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: _accentGrad.first.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 7,
                height: 7,
                decoration: BoxDecoration(
                  color: _accent,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(color: _accent.withOpacity(0.6), blurRadius: 6),
                  ],
                ),
              ),
              const SizedBox(width: 8),
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
            ],
          ),
          const SizedBox(height: 10),
          _AnimatedKm(value: _today, accent: _accent, gradient: _accentGrad),
          const SizedBox(height: 12),
          Row(
            children: [
              Icon(Icons.eco_rounded, color: _accent, size: 18),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  '${Co2Service.format(co2)} de CO₂ ahorrado hoy',
                  style: const TextStyle(
                    fontFamily: 'Poppins',
                    color: Colors.white70,
                    fontSize: 14,
                  ),
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

  // ── Gráfico ───────────────────────────────────────────────────────────
  Widget _buildChartCard() {
    final days = _chartDays;
    final maxKm = days.fold<double>(0.1, (m, e) => e.km > m ? e.km : m);
    final rangeKm = days.fold<double>(0, (s, e) => s + e.km);
    final todayKey = RideStatsService.dayKey(DateTime.now());
    const wd = ['L', 'M', 'M', 'J', 'V', 'S', 'D']; // weekday 1..7
    final narrow = _chartRange == 30;

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
      decoration: glassDecoration(radius: 22, opacity: 0.06),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                narrow ? 'Últimos 30 días' : 'Últimos 7 días',
                style: const TextStyle(
                  fontFamily: 'Poppins',
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Text(
                '${rangeKm.toStringAsFixed(1)} km',
                style: TextStyle(
                  fontFamily: 'Poppins',
                  color: _accent,
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              _rangePill('7 días', 7),
              const SizedBox(width: 8),
              _rangePill('30 días', 30),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 16,
            child: (_selectedBar >= 0 && _selectedBar < days.length)
                ? Text(
                    '${_fmtDia(days[_selectedBar].date)}  ·  '
                    '${days[_selectedBar].km.toStringAsFixed(1)} km',
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      color: _accent,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  )
                : const Text(
                    'Toca una barra para ver el detalle',
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      color: Colors.white30,
                      fontSize: 12,
                    ),
                  ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 120,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (int i = 0; i < days.length; i++)
                  Expanded(
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => setState(
                          () => _selectedBar = _selectedBar == i ? -1 : i),
                      child: _Bar(
                        heightFactor: (days[i].km / maxKm).clamp(0.0, 1.0),
                        isToday:
                            RideStatsService.dayKey(days[i].date) == todayKey,
                        isSelected: _selectedBar == i,
                        accent: _accent,
                        narrow: narrow,
                        label: narrow ? null : wd[days[i].date.weekday - 1],
                      ),
                    ),
                  ),
              ],
            ),
          ),
          if (narrow) ...[
            const SizedBox(height: 6),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  _fmtDia(days.first.date),
                  style: const TextStyle(
                    fontFamily: 'Poppins',
                    color: Colors.white38,
                    fontSize: 10,
                  ),
                ),
                Text(
                  'hoy',
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    color: _accent.withOpacity(0.7),
                    fontSize: 10,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _rangePill(String label, int range) {
    final sel = _chartRange == range;
    return GestureDetector(
      onTap: () {
        if (_chartRange == range) return;
        setState(() {
          _chartRange = range;
          _selectedBar = -1;
          _chartDays = RideStatsService.lastNDays(range);
        });
        StatsPrefsService.setChartRange(range);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: sel ? _accent.withOpacity(0.15) : Colors.white.withOpacity(0.05),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: sel ? _accent.withOpacity(0.5) : Colors.white12,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontFamily: 'Poppins',
            color: sel ? _accent : Colors.white54,
            fontSize: 12,
            fontWeight: sel ? FontWeight.w700 : FontWeight.w400,
          ),
        ),
      ),
    );
  }

  // ── Grid de tarjetas (modo normal) ───────────────────────────────────
  Widget _buildStatGrid() {
    final visible = _order.where((k) => !_hidden.contains(k)).toList();
    if (visible.isEmpty) {
      return Container(
        key: const ValueKey('empty'),
        padding: const EdgeInsets.all(20),
        decoration: glassDecoration(radius: 18, opacity: 0.05),
        child: Row(
          children: [
            const Icon(Icons.visibility_off_rounded,
                color: Colors.white38, size: 18),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Ocultaste todas las tarjetas. Toca el botón de personalizar '
                'para volver a mostrarlas.',
                style: TextStyle(
                  fontFamily: 'Poppins',
                  color: Colors.white54,
                  fontSize: 12,
                ),
              ),
            ),
          ],
        ),
      );
    }
    return GridView.count(
      key: const ValueKey('grid'),
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 12,
      crossAxisSpacing: 12,
      childAspectRatio: 1.55,
      children: [
        for (final k in visible)
          _StatTile(
            emoji: _tileMeta[k]!.$1,
            label: _tileMeta[k]!.$2,
            value: _tileValue(k).$1,
            unit: _tileValue(k).$2,
            accent: _accent,
          ),
      ],
    );
  }

  /// Cambia el color de acento; si es un acento Plus y el ciclista no lo es,
  /// abre el paywall.
  void _selectAccent(int index) {
    if (StatsPrefsService.isPlusAccentIndex(index) && !_isPlus) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => const PaywallPage(
            reason:
                'Los temas y colores de acento premium son parte de Pedalea Plus.',
          ),
        ),
      );
      return;
    }
    // Guarda en el perfil (BD); el notifier hace el setState vía _onPrefsChanged.
    PlusPrefsService.setAccentIndex(index);
  }

  Widget _accentSwatch(int index) {
    final grad = StatsPrefsService.accentGradientFor(index);
    final isGradient = grad.first.value != grad.last.value;
    final selected = _accentIndex == index;
    return GestureDetector(
      onTap: () => _selectAccent(index),
      child: Container(
        width: 30,
        height: 30,
        decoration: BoxDecoration(
          color: isGradient ? null : grad.first,
          gradient: isGradient
              ? LinearGradient(
                  colors: grad,
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                )
              : null,
          shape: BoxShape.circle,
          border: Border.all(
            color: selected ? Colors.white : Colors.transparent,
            width: 2.5,
          ),
        ),
        child: selected
            ? const Icon(Icons.check, color: Colors.black, size: 15)
            : null,
      ),
    );
  }

  // ── Panel de personalización (modo edición) ──────────────────────────
  Widget _buildEditPanel() {
    return Column(
      key: const ValueKey('edit'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
          decoration: glassDecoration(radius: 18, opacity: 0.05),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _sectionLabel('COLOR DE ACENTO'),
              const SizedBox(height: 12),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  for (int i = 0;
                      i < StatsPrefsService.freeAccentCount;
                      i++)
                    _accentSwatch(i),
                ],
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Text(
                    'PLUS',
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      color: Colors.amber.withOpacity(0.9),
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    _isPlus ? 'colores y degradados' : 'toca para probar',
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      color: Colors.white.withOpacity(0.4),
                      fontSize: 10,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Opacity(
                opacity: _isPlus ? 1 : 0.55,
                child: Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    for (int i = StatsPrefsService.freeAccentCount;
                        i < StatsPrefsService.allAccentColors.length;
                        i++)
                      _accentSwatch(i),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        _sectionLabel('TARJETAS'),
        const SizedBox(height: 4),
        Text(
          'Arrastra para ordenar · toca el ojo para mostrar u ocultar',
          style: TextStyle(
            fontFamily: 'Poppins',
            color: Colors.white.withOpacity(0.4),
            fontSize: 11,
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
            StatsPrefsService.setTileOrder(_order);
          },
          itemBuilder: (context, i) {
            final key = _order[i];
            final hidden = _hidden.contains(key);
            final (emoji, label) = _tileMeta[key]!;
            final (value, unit) = _tileValue(key);
            return Container(
              key: ValueKey(key),
              margin: const EdgeInsets.only(bottom: 8),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(hidden ? 0.02 : 0.05),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: hidden ? Colors.white10 : _accent.withOpacity(0.25),
                ),
              ),
              child: ListTile(
                dense: true,
                leading: Opacity(
                  opacity: hidden ? 0.35 : 1,
                  child: Text(emoji, style: const TextStyle(fontSize: 20)),
                ),
                title: Text(
                  label,
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: hidden ? Colors.white38 : Colors.white,
                  ),
                ),
                subtitle: Text(
                  '$value $unit',
                  style: const TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 12,
                    color: Colors.white38,
                  ),
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      icon: Icon(
                        hidden
                            ? Icons.visibility_off_rounded
                            : Icons.visibility_rounded,
                        color: hidden ? Colors.white30 : _accent,
                        size: 20,
                      ),
                      onPressed: () {
                        setState(() {
                          if (hidden) {
                            _hidden.remove(key);
                          } else {
                            _hidden.add(key);
                          }
                        });
                        StatsPrefsService.setHiddenTiles(_hidden);
                      },
                    ),
                    ReorderableDragStartListener(
                      index: i,
                      child: const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 4),
                        child: Icon(Icons.drag_handle_rounded,
                            color: Colors.white38),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ],
    );
  }

  Widget _sectionLabel(String text) => Text(
        text,
        style: TextStyle(
          fontFamily: 'Poppins',
          color: Colors.white.withOpacity(0.4),
          fontSize: 11,
          fontWeight: FontWeight.w600,
          letterSpacing: 1,
        ),
      );

  // ── Hoja para compartir ──────────────────────────────────────────────
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
                  reason:
                      'Comparte tus estadísticas en historias con Pedalea Plus.',
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
}

/// Número de km grande con animación de conteo al aparecer.
class _AnimatedKm extends StatelessWidget {
  final double value;
  final Color accent;
  final List<Color>? gradient;
  const _AnimatedKm({required this.value, required this.accent, this.gradient});

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: value),
      duration: const Duration(milliseconds: 900),
      curve: Curves.easeOutCubic,
      builder: (_, v, _) => Row(
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          _gradientNumber(v.toStringAsFixed(1)),
          const SizedBox(width: 8),
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              'km',
              style: TextStyle(
                fontFamily: 'Poppins',
                color: accent,
                fontSize: 22,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _gradientNumber(String text) {
    const style = TextStyle(
      fontFamily: 'Poppins',
      color: Colors.white,
      fontSize: 52,
      fontWeight: FontWeight.w800,
      height: 1,
    );
    final g = gradient;
    if (g == null || g.length < 2 || g.first.value == g.last.value) {
      return Text(text, style: style);
    }
    return ShaderMask(
      blendMode: BlendMode.srcIn,
      shaderCallback: (bounds) => LinearGradient(
        colors: g,
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ).createShader(bounds),
      child: Text(text, style: style),
    );
  }
}

/// Una barra del gráfico, con animación de crecimiento.
class _Bar extends StatelessWidget {
  final double heightFactor;
  final bool isToday;
  final bool isSelected;
  final bool narrow;
  final Color accent;
  final String? label;
  const _Bar({
    required this.heightFactor,
    required this.isToday,
    required this.isSelected,
    required this.narrow,
    required this.accent,
    this.label,
  });

  @override
  Widget build(BuildContext context) {
    final active = isToday || isSelected;
    return Column(
      children: [
        Expanded(
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: heightFactor),
            duration: const Duration(milliseconds: 700),
            curve: Curves.easeOutCubic,
            builder: (_, v, _) => FractionallySizedBox(
              alignment: Alignment.bottomCenter,
              heightFactor: v <= 0.02 ? 0.02 : v,
              child: Container(
                width: narrow ? 6 : 18,
                decoration: BoxDecoration(
                  color: active
                      ? accent
                      : Colors.white.withOpacity(isSelected ? 0.5 : 0.22),
                  borderRadius: BorderRadius.circular(narrow ? 3 : 6),
                  boxShadow: active
                      ? [BoxShadow(color: accent.withOpacity(0.4), blurRadius: 8)]
                      : null,
                ),
              ),
            ),
          ),
        ),
        if (label != null) ...[
          const SizedBox(height: 6),
          Text(
            label!,
            style: TextStyle(
              fontFamily: 'Poppins',
              color: active ? accent : Colors.white38,
              fontSize: 11,
              fontWeight: active ? FontWeight.w700 : FontWeight.w400,
            ),
          ),
        ],
      ],
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
              child: const Icon(Icons.ios_share_rounded,
                  color: Colors.amber, size: 30),
            ),
            const SizedBox(height: 16),
            const Text(
              'Compartir tus estadísticas es Plus',
              style: TextStyle(
                fontFamily: 'Poppins',
                color: Colors.white,
                fontSize: 17,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Hazte Pedalea Plus para compartir tu progreso como imagen en tus historias.',
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontFamily: 'Poppins', color: Colors.white60, fontSize: 13),
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
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                  textStyle: const TextStyle(
                      fontFamily: 'Poppins', fontWeight: FontWeight.w700),
                ),
              ),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () => Navigator.pop(context),
              style: TextButton.styleFrom(foregroundColor: Colors.white38),
              child: const Text('Ahora no',
                  style: TextStyle(fontFamily: 'Poppins')),
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
  static const _statMeta = {
    'today': ('🚴', 'Hoy'),
    'weekKm': ('📆', 'Semana'),
    'streak': ('🔥', 'Racha'),
    'bestDay': ('🏆', 'Mejor día'),
    'activeDays': ('📅', 'Días activo'),
  };
  final List<String> _order = [
    'streak',
    'bestDay',
    'activeDays',
    'today',
    'weekKm'
  ];
  final Set<String> _shownStats = {'streak', 'bestDay', 'activeDays', 'co2'};

  // Arranca desde el color que el ciclista eligió en la pantalla principal.
  Color _accentColor = StatsPrefsService.allAccentColors[
      StatsPrefsService.effectiveAccentIndex(
          PlusPrefsService.accentIndex.value,
          SubscriptionService.instance.isPlus.value)];

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

  Widget _sectionLabel(String text) => Align(
        alignment: Alignment.centerLeft,
        child: Text(
          text,
          style: TextStyle(
            fontFamily: 'Poppins',
            color: Colors.white.withOpacity(0.4),
            fontSize: 11,
            fontWeight: FontWeight.w600,
            letterSpacing: 1,
          ),
        ),
      );

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
            const Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Personaliza tu tarjeta',
                style: TextStyle(
                  fontFamily: 'Poppins',
                  color: Colors.white,
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(height: 16),
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
            const SizedBox(height: 22),
            _sectionLabel('COLOR'),
            const SizedBox(height: 10),
            Row(
              children: StatsPrefsService.accentPalette.map((c) {
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
                          color: isSelected
                              ? Colors.white
                              : Colors.transparent,
                          width: 2.5,
                        ),
                      ),
                      child: isSelected
                          ? const Icon(Icons.check,
                              color: Colors.black, size: 16)
                          : null,
                    ),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 20),
            _sectionLabel('QUÉ MOSTRAR  ·  arrastra para ordenar'),
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
                    color: selected
                        ? _accentColor.withOpacity(0.12)
                        : Colors.white.withOpacity(0.04),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: selected
                          ? _accentColor.withOpacity(0.4)
                          : Colors.white12,
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
                        fontWeight:
                            selected ? FontWeight.w600 : FontWeight.w400,
                      ),
                    ),
                    trailing: ReorderableDragStartListener(
                      index: i,
                      child: const Icon(Icons.drag_handle_rounded,
                          color: Colors.white38),
                    ),
                  ),
                );
              },
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: FilterChip(
                selected: _shownStats.contains('co2'),
                onSelected: (_) => _toggleStat('co2'),
                showCheckmark: false,
                label: const Text('🌱 CO₂ ahorrado'),
                labelStyle: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 12,
                  color: _shownStats.contains('co2')
                      ? Colors.black
                      : Colors.white70,
                  fontWeight: _shownStats.contains('co2')
                      ? FontWeight.w700
                      : FontWeight.w400,
                ),
                backgroundColor: Colors.white.withOpacity(0.06),
                selectedColor: _accentColor,
                side: BorderSide(
                  color: _shownStats.contains('co2')
                      ? Colors.transparent
                      : Colors.white24,
                ),
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
                  backgroundColor: _accentColor,
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
        return _miniStat(
            '🔥', '$streak', streak == 1 ? 'día racha' : 'días racha');
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
                    const Text('🚴', style: TextStyle(fontSize: 20)),
                  ],
                ),
                const SizedBox(height: 22),
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
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 12),
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

/// Tarjeta del grid de estadísticas.
class _StatTile extends StatelessWidget {
  final String emoji;
  final String label;
  final String value;
  final String unit;
  final Color accent;
  const _StatTile({
    required this.emoji,
    required this.label,
    required this.value,
    required this.unit,
    required this.accent,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withOpacity(0.10)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Row(
            children: [
              Container(
                width: 30,
                height: 30,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: accent.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Text(emoji, style: const TextStyle(fontSize: 15)),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontFamily: 'Poppins',
                    color: Colors.white54,
                    fontSize: 13,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
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

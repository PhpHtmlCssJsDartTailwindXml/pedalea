import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:gal/gal.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../core/glass.dart';
import '../services/ride_stats_service.dart';
import '../services/ride_stats_sync_service.dart';
import '../services/co2_service.dart';
import '../services/stats_prefs_service.dart';
import '../services/stats_summary.dart';
import '../services/plus_prefs_service.dart';
import '../services/subscription_service.dart';
import '../services/plus_share_quota.dart';
import 'paywall_page.dart';
import 'rider_ranking_page.dart';

const _meses = [
  'enero',
  'febrero',
  'marzo',
  'abril',
  'mayo',
  'junio',
  'julio',
  'agosto',
  'septiembre',
  'octubre',
  'noviembre',
  'diciembre',
];
const _mesesCortos = ['ene', 'feb', 'mar', 'abr', 'may', 'jun', 'jul', 'ago', 'sep', 'oct', 'nov', 'dic'];
const _diasSemana = ['lun', 'mar', 'mié', 'jue', 'vie', 'sáb', 'dom'];

String _fmtDia(DateTime d) => '${d.day} ${_mesesCortos[d.month - 1]}';

/// Km con coma decimal; sin decimales y con punto de miles desde 1.000.
String fmtKm(double v) {
  if (v >= 1000) {
    final s = v.round().toString();
    final b = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) b.write('.');
      b.write(s[i]);
    }
    return b.toString();
  }
  return v.toStringAsFixed(1).replaceAll('.', ',');
}

/// CO₂ evitado por [km], en g, kg o t con coma decimal.
(String, String) fmtCo2(double km) {
  final kg = Co2Service.savedKg(km);
  if (kg >= 1000) return ((kg / 1000).toStringAsFixed(1).replaceAll('.', ','), 't');
  if (kg >= 1) return (kg.toStringAsFixed(1).replaceAll('.', ','), 'kg');
  return ((kg * 1000).toStringAsFixed(0), 'g');
}

String _periodCaption(StatsPeriod p, DateTime now) {
  switch (p) {
    case StatsPeriod.week:
      final s = weekStart(now);
      final e = s.add(const Duration(days: 6));
      return s.month == e.month
          ? 'Esta semana · ${s.day}–${e.day} ${_mesesCortos[e.month - 1]}'
          : 'Esta semana · ${_fmtDia(s)} – ${_fmtDia(e)}';
    case StatsPeriod.month:
      final m = _meses[now.month - 1];
      return '${m[0].toUpperCase()}${m.substring(1)} ${now.year}';
    case StatsPeriod.year:
      return 'Año ${now.year}';
    case StatsPeriod.all:
      return 'Desde que usas Pedalea';
  }
}

String _prevLabel(StatsPeriod p) => switch (p) {
  StatsPeriod.week => 'la semana pasada',
  StatsPeriod.month => 'el mes pasado',
  StatsPeriod.year => 'el año pasado',
  StatsPeriod.all => '',
};

const _periodTabs = [
  (StatsPeriod.week, 'Semana'),
  (StatsPeriod.month, 'Mes'),
  (StatsPeriod.year, 'Año'),
  (StatsPeriod.all, 'Total'),
];

/// Ícono y etiqueta de cada dato (cuadrícula e imagen para compartir).
const kStatMeta = <String, (IconData, String)>{
  'streak': (Icons.local_fire_department_rounded, 'Racha actual'),
  'bestDay': (Icons.bolt_rounded, 'Mejor día'),
  'total': (Icons.route_rounded, 'Total histórico'),
  'activeDays': (Icons.calendar_today_rounded, 'Días activos'),
  'co2': (Icons.eco_rounded, 'CO₂ evitado'),
  'week': (Icons.speed_rounded, 'Promedio por día'),
  'maxSpeed': (Icons.flash_on_rounded, 'Vel. máxima'),
};

/// Etiqueta corta de cada dato para la imagen (caben 3 por fila).
const kStatShort = <String, String>{
  'streak': 'RACHA',
  'bestDay': 'MEJOR DÍA',
  'total': 'TOTAL',
  'activeDays': 'DÍAS ACTIVOS',
  'co2': 'CO₂ EVITADO',
  'week': 'PROMEDIO DIARIO',
  'maxSpeed': 'VEL. MÁXIMA',
};

/// Valor y unidad de un dato según el periodo del resumen.
(String, String) statValue(
  String key,
  PeriodSummary sum, {
  required double total,
  required int streak,
  required double maxSpeed,
}) {
  switch (key) {
    case 'streak':
      return ('$streak', streak == 1 ? 'día' : 'días');
    case 'bestDay':
      return (fmtKm(sum.bestDayKm), 'km');
    case 'total':
      return (fmtKm(total), 'km');
    case 'activeDays':
      return ('${sum.activeDays}', sum.activeDays == 1 ? 'día' : 'días');
    case 'co2':
      return fmtCo2(sum.period == StatsPeriod.all ? total : sum.km);
    case 'week':
      return (fmtKm(sum.avgPerActiveDay), 'km');
    case 'maxSpeed':
      return (maxSpeed <= 0 ? '—' : maxSpeed.toStringAsFixed(1).replaceAll('.', ','), 'km/h');
    default:
      return ('', '');
  }
}

TextStyle _t(double size, {FontWeight w = FontWeight.w500, Color c = Colors.white, double? h, double? ls}) =>
    TextStyle(fontFamily: 'Poppins', fontSize: size, fontWeight: w, color: c, height: h, letterSpacing: ls);

/// Pantalla de progreso del ciclista, al estilo de las apps deportivas:
/// periodo (semana/mes/año/total), un número principal, comparación con el
/// periodo anterior, gráfico, cuadrícula de datos y récords personales.
///
/// Se puede personalizar (botón «afinar»): color de acento (Plus), orden y
/// visibilidad de los datos. Todo se guarda vía [StatsPrefsService].
class StatsPage extends StatefulWidget {
  /// Abre la hoja de compartir al entrar (sugerencia al terminar un viaje).
  final bool openShare;
  const StatsPage({super.key, this.openShare = false});

  @override
  State<StatsPage> createState() => _StatsPageState();
}

class _StatsPageState extends State<StatsPage> {
  static const _tileMeta = kStatMeta;

  StatsPeriod _period = StatsPeriod.week;
  late PeriodSummary _sum;
  late PersonalRecords _rec;
  int _selectedBar = -1;

  double _total = 0, _maxSpeed = 0;
  int _streak = 0;
  double? _serverTotal; // total histórico real (profiles.total_km)
  bool _syncing = false;

  bool get _isPlus => SubscriptionService.instance.isPlus.value;

  int get _accentIndex => StatsPrefsService.effectiveAccentIndex(PlusPrefsService.accentIndex.value, _isPlus);
  Color get _accent => StatsPrefsService.allAccentColors[_accentIndex];
  List<Color> get _accentGrad => StatsPrefsService.accentGradientFor(_accentIndex);

  final List<String> _order = StatsPrefsService.tileOrder;

  @override
  void initState() {
    super.initState();
    PlusPrefsService.accentIndex.addListener(_onPrefsChanged);
    SubscriptionService.instance.isPlus.addListener(_onPrefsChanged);
    PlusPrefsService.refresh(); // por si cambió en otro dispositivo
    _load();
    _syncFromServer();
    if (widget.openShare) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _openShareSheet();
      });
    }
  }

  void _onPrefsChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    PlusPrefsService.accentIndex.removeListener(_onPrefsChanged);
    SubscriptionService.instance.isPlus.removeListener(_onPrefsChanged);
    super.dispose();
  }

  void _load() {
    final days = RideStatsService.allDays();
    _sum = summarize(days, _period);
    _rec = records(days);
    _total = _serverTotal ?? RideStatsService.totalKm();
    _streak = RideStatsService.currentStreak();
    _maxSpeed = RideStatsService.maxSpeedKmh();
    _selectedBar = -1;
    if (mounted) setState(() {});
  }

  /// Baja las estadísticas del servidor y refresca la vista, para que los km
  /// sean los reales aunque se haya reinstalado la app o se use otro teléfono.
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

  void _setPeriod(StatsPeriod p) {
    if (p == _period) return;
    _period = p;
    _load();
  }

  /// Valor y unidad de cada dato de la cuadrícula (según el periodo).
  (String, String) _tileValue(String key) => statValue(key, _sum, total: _total, streak: _streak, maxSpeed: _maxSpeed);

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
                child: RefreshIndicator(
                  color: _accent,
                  backgroundColor: const Color(0xFF12121C),
                  onRefresh: _syncFromServer,
                  child: ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(20, 6, 20, 36),
                    children: [
                      ...[
                        _buildActions(),
                        const SizedBox(height: 16),
                        _buildPeriodTabs(),
                        const SizedBox(height: 26),
                        _buildHero(),
                        const SizedBox(height: 22),
                        _BarsChart(
                          bars: _sum.bars,
                          period: _period,
                          accent: _accent,
                          gradient: _accentGrad,
                          selected: _selectedBar,
                          onSelect: (i) => setState(() => _selectedBar = _selectedBar == i ? -1 : i),
                        ),
                        const SizedBox(height: 26),
                        _buildStatGrid(),
                        const SizedBox(height: 32),
                        _buildRecords(),
                        const SizedBox(height: 20),
                        _buildRankingLink(),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Cabecera ──────────────────────────────────────────────────────────
  Widget _iconBtn(IconData icon, String tip, VoidCallback onTap, {Color? color}) => IconButton(
    tooltip: tip,
    onPressed: onTap,
    icon: Icon(icon, color: color ?? Colors.white70, size: 22),
  );

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 4, 8, 4),
      child: Row(
        children: [
          _iconBtn(Icons.arrow_back_rounded, 'Volver', () => Navigator.pop(context), color: Colors.white),
          const SizedBox(width: 2),
          Expanded(
            child: Text('Estadísticas', style: _t(19, w: FontWeight.w700)),
          ),
          if (_syncing)
            Padding(
              padding: const EdgeInsets.all(14),
              child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: _accent)),
            )
          else
            _iconBtn(Icons.sync_rounded, 'Actualizar', _syncFromServer),
        ],
      ),
    );
  }

  // ── Acciones con texto (para quien no reconoce los íconos) ───────────
  Widget _buildActions() {
    Widget btn({
      required IconData icon,
      required String label,
      required VoidCallback onTap,
      bool primary = false,
      Widget? badge,
    }) => Material(
      color: primary ? Colors.white : Colors.white.withOpacity(0.07),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: SizedBox(
          height: 46,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 19, color: primary ? Colors.black : Colors.white),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: _t(13.5, w: FontWeight.w700, c: primary ? Colors.black : Colors.white),
                ),
              ),
              if (badge != null) ...[const SizedBox(width: 6), badge],
            ],
          ),
        ),
      ),
    );

    return Row(
      children: [
        Expanded(
          child: btn(icon: Icons.ios_share_rounded, label: 'Compartir estadísticas', primary: true, onTap: _openShareSheet),
        ),
      ],
    );
  }

  // ── Periodo ───────────────────────────────────────────────────────────
  Widget _buildPeriodTabs() {
    return Container(
      height: 42,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(color: Colors.white.withOpacity(0.05), borderRadius: BorderRadius.circular(14)),
      child: Row(
        children: [
          for (final (p, label) in _periodTabs)
            Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => _setPeriod(p),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: _period == p ? Colors.white.withOpacity(0.12) : Colors.transparent,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    label,
                    style: _t(
                      13,
                      w: _period == p ? FontWeight.w700 : FontWeight.w500,
                      c: _period == p ? Colors.white : Colors.white54,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  // ── Número principal ─────────────────────────────────────────────────
  Widget _buildHero() {
    final km = _period == StatsPeriod.all ? _total : _sum.km;
    final change = _sum.changePct;
    final sel = _selectedBar >= 0 && _selectedBar < _sum.bars.length ? _sum.bars[_selectedBar] : null;

    Widget comparison;
    if (sel != null) {
      final d = sel.start;
      final what = (_period == StatsPeriod.year || _period == StatsPeriod.all)
          ? '${_meses[d.month - 1]} ${d.year}'
          : '${_diasSemana[d.weekday - 1]} ${_fmtDia(d)}';
      comparison = Text(
        '${fmtKm(sel.km)} km el $what',
        style: _t(13.5, w: FontWeight.w600, c: _accent),
      );
    } else if (change != null) {
      final up = change >= 0;
      final color = up ? _accent : const Color(0xFFFF7A7A);
      comparison = Row(
        children: [
          Icon(up ? Icons.trending_up_rounded : Icons.trending_down_rounded, color: color, size: 18),
          const SizedBox(width: 6),
          Text(
            '${up ? '+' : ''}${change.round()} %',
            style: _t(13.5, w: FontWeight.w700, c: color),
          ),
          const SizedBox(width: 6),
          Flexible(
            child: Text('vs ${_prevLabel(_period)}', style: _t(13.5, c: Colors.white54)),
          ),
        ],
      );
    } else if (_period != StatsPeriod.all && (_sum.prevKm ?? 0) < 0.1 && km > 0) {
      comparison = Text('Sin actividad ${_prevLabel(_period)}', style: _t(13.5, c: Colors.white54));
    } else {
      comparison = Text(
        _period == StatsPeriod.all ? '${_rec.longestStreak} días de racha máxima' : 'Sal a pedalear para sumar km',
        style: _t(13.5, c: Colors.white54),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          _periodCaption(_period, DateTime.now()).toUpperCase(),
          style: _t(11.5, w: FontWeight.w700, c: Colors.white54, ls: 1.4),
        ),
        const SizedBox(height: 6),
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            TweenAnimationBuilder<double>(
              key: ValueKey(_period),
              tween: Tween(begin: 0, end: km),
              duration: const Duration(milliseconds: 700),
              curve: Curves.easeOutCubic,
              builder: (_, v, _) => Text(fmtKm(v), style: _t(60, w: FontWeight.w800, h: 1.0, ls: -2)),
            ),
            const SizedBox(width: 8),
            Text(
              'km',
              style: _t(20, w: FontWeight.w600, c: Colors.white54),
            ),
          ],
        ),
        const SizedBox(height: 10),
        comparison,
      ],
    );
  }

  // ── Cuadrícula de datos ──────────────────────────────────────────────
  Widget _buildStatGrid() {
    final keys = _order;
    if (keys.isEmpty) return const SizedBox.shrink();
    final rows = <List<String>>[];
    for (var i = 0; i < keys.length; i += 3) {
      rows.add(keys.sublist(i, (i + 3).clamp(0, keys.length)));
    }
    final line = Container(height: 1, color: Colors.white.withOpacity(0.07));
    return Column(
      children: [
        line,
        for (final r in rows) ...[
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [for (var j = 0; j < 3; j++) Expanded(child: j < r.length ? _statCell(r[j]) : const SizedBox.shrink())],
            ),
          ),
          line,
        ],
      ],
    );
  }

  Widget _statCell(String key) {
    final (icon, label) = _tileMeta[key]!;
    final (value, unit) = _tileValue(key);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 13, color: Colors.white38),
            const SizedBox(width: 5),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: _t(11, c: Colors.white54),
              ),
            ),
          ],
        ),
        const SizedBox(height: 5),
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Flexible(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(value, maxLines: 1, style: _t(20, w: FontWeight.w700, h: 1.1)),
              ),
            ),
            if (unit.isNotEmpty) ...[const SizedBox(width: 3), Text(unit, style: _t(11.5, c: Colors.white54))],
          ],
        ),
      ],
    );
  }

  // ── Récords personales ───────────────────────────────────────────────
  Widget _buildRecords() {
    Widget row(IconData icon, Color color, String title, String value, String? sub) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(color: color.withOpacity(0.14), borderRadius: BorderRadius.circular(12)),
            child: Icon(icon, color: color, size: 21),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: _t(14, w: FontWeight.w600)),
                if (sub != null) Text(sub, style: _t(11.5, c: Colors.white38)),
              ],
            ),
          ),
          Text(value, style: _t(15, w: FontWeight.w700)),
        ],
      ),
    );

    final r = _rec;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Récords personales', style: _t(16, w: FontWeight.w700)),
        const SizedBox(height: 8),
        row(
          Icons.bolt_rounded,
          const Color(0xFFFFC94D),
          'Día más largo',
          r.bestDayKm > 0 ? '${fmtKm(r.bestDayKm)} km' : '—',
          r.bestDayDate != null ? '${_fmtDia(r.bestDayDate!)} ${r.bestDayDate!.year}' : null,
        ),
        row(
          Icons.date_range_rounded,
          const Color(0xFF6FB6FF),
          'Mejor semana',
          r.bestWeekKm > 0 ? '${fmtKm(r.bestWeekKm)} km' : '—',
          r.bestWeekStart != null ? 'Desde el ${_fmtDia(r.bestWeekStart!)}' : null,
        ),
        row(
          Icons.local_fire_department_rounded,
          const Color(0xFFFF8A4C),
          'Racha más larga',
          r.longestStreak > 0 ? '${r.longestStreak} ${r.longestStreak == 1 ? 'día' : 'días'}' : '—',
          r.longestStreakEnd != null && r.longestStreak > 0 ? 'Hasta el ${_fmtDia(r.longestStreakEnd!)}' : null,
        ),
        row(
          Icons.flash_on_rounded,
          const Color(0xFFB98BFF),
          'Velocidad máxima',
          _maxSpeed > 0 ? '${_maxSpeed.toStringAsFixed(1).replaceAll('.', ',')} km/h' : '—',
          null,
        ),
      ],
    );
  }

  Widget _buildRankingLink() {
    return Material(
      color: Colors.white.withOpacity(0.04),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const RiderRankingPage())),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
          child: Row(
            children: [
              const Icon(Icons.leaderboard_rounded, color: Colors.white70, size: 21),
              const SizedBox(width: 12),
              Expanded(
                child: Text('Ranking de ciclistas', style: _t(14, w: FontWeight.w600)),
              ),
              const Icon(Icons.chevron_right_rounded, color: Colors.white38),
            ],
          ),
        ),
      ),
    );
  }

  // ── Compartir ────────────────────────────────────────────────────────
  void _openShareSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _ShareSheet(
        initialPeriod: _period,
        accentIndex: _accentIndex,
        total: _total,
        streak: _streak,
        maxSpeed: _maxSpeed,
        order: List.of(_order),
        shown: _order.where((k) => !StatsPrefsService.hiddenTiles.contains(k)).toSet(),
      ),
    );
  }
}

/// Gráfico de barras limpio: una barra por día (semana/mes) o por mes.
class _BarsChart extends StatelessWidget {
  final List<StatsBar> bars;
  final StatsPeriod period;
  final Color accent;
  final List<Color> gradient;
  final int selected;
  final ValueChanged<int> onSelect;
  const _BarsChart({
    required this.bars,
    required this.period,
    required this.accent,
    required this.gradient,
    required this.selected,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    final maxKm = bars.fold<double>(0, (m, b) => b.km > m ? b.km : m);
    final today = DateTime.now();
    final dense = bars.length > 14;
    return SizedBox(
      height: 150,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (var i = 0; i < bars.length; i++)
            Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => onSelect(i),
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: dense ? 1.2 : 5),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      Expanded(
                        child: Align(
                          alignment: Alignment.bottomCenter,
                          child: TweenAnimationBuilder<double>(
                            tween: Tween(begin: 0, end: maxKm <= 0 ? 0 : bars[i].km / maxKm),
                            duration: const Duration(milliseconds: 600),
                            curve: Curves.easeOutCubic,
                            builder: (_, f, _) => FractionallySizedBox(
                              heightFactor: f < 0.02 ? 0.02 : f,
                              child: Container(
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(dense ? 2 : 6),
                                  gradient: bars[i].km <= 0
                                      ? null
                                      : LinearGradient(
                                          begin: Alignment.bottomCenter,
                                          end: Alignment.topCenter,
                                          colors: [
                                            gradient.first.withOpacity(selected == -1 || selected == i ? 0.95 : 0.35),
                                            gradient.last.withOpacity(selected == -1 || selected == i ? 1 : 0.4),
                                          ],
                                        ),
                                  color: bars[i].km <= 0 ? Colors.white.withOpacity(0.08) : null,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      SizedBox(
                        height: 14,
                        child: Text(
                          _showLabel(i) ? bars[i].label : '',
                          maxLines: 1,
                          overflow: TextOverflow.visible,
                          softWrap: false,
                          style: _t(
                            10.5,
                            w: _isCurrent(bars[i].start, today) ? FontWeight.w700 : FontWeight.w500,
                            c: _isCurrent(bars[i].start, today) ? Colors.white : Colors.white38,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  bool _showLabel(int i) {
    if (bars.length <= 14) return true;
    final d = bars[i].start.day;
    return d == 1 || d % 5 == 0;
  }

  bool _isCurrent(DateTime s, DateTime now) {
    if (period == StatsPeriod.year || period == StatsPeriod.all) {
      return s.year == now.year && s.month == now.month;
    }
    return s.year == now.year && s.month == now.month && s.day == now.day;
  }
}

// ═══════════════════════════════════════════════════════════════════════
// Imagen para compartir (formato historia 9:16)
// ═══════════════════════════════════════════════════════════════════════

/// Estilo de la imagen para compartir.
enum ShareStyle { dark, photo, clear }

class _ShareSheet extends StatefulWidget {
  final StatsPeriod initialPeriod;
  final int accentIndex;
  final double total;
  final int streak;
  final double maxSpeed;
  final List<String> order;
  final Set<String> shown;
  const _ShareSheet({
    required this.initialPeriod,
    required this.accentIndex,
    required this.total,
    required this.streak,
    required this.maxSpeed,
    required this.order,
    required this.shown,
  });

  @override
  State<_ShareSheet> createState() => _ShareSheetState();
}

class _ShareSheetState extends State<_ShareSheet> {
  final GlobalKey _cardKey = GlobalKey();
  late StatsPeriod _period = widget.initialPeriod;
  late int _accentIdx = widget.accentIndex;
  ShareStyle _style = ShareStyle.dark;
  File? _photo;
  bool _sharing = false;
  bool _saving = false;
  bool _saved = false; // muestra «Imagen guardada» en el botón unos segundos

  bool get _isPlus => SubscriptionService.instance.isPlus.value;

  /// Imágenes Plus gratis que quedan esta semana (null = cargando).
  int? _plusLeft;

  /// ¿La imagen actual usa algo de Plus? (foto, sin fondo o color Plus)
  bool get _usesPlus => _style != ShareStyle.dark || StatsPrefsService.isPlusAccentIndex(_accentIdx);

  @override
  void initState() {
    super.initState();
    if (!_isPlus) {
      PlusShareQuota.remaining().then((n) {
        if (mounted) setState(() => _plusLeft = n);
      });
    }
  }

  /// Antes de exportar: si la imagen usa Plus y no es Plus, usa una de las
  /// imágenes gratis de la semana (preguntando antes) o muestra las opciones.
  /// Devuelve true si se puede seguir.
  Future<bool> _passQuota() async {
    if (_isPlus || !_usesPlus) return true;
    final left = _plusLeft ?? await PlusShareQuota.remaining();
    if (!mounted) return false;
    if (left == -1) return true;
    if (left <= 0) return _showLimitSheet();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF161822),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        title: Text('Imagen con funciones Plus', style: _t(17, w: FontWeight.w700)),
        content: Text(
          'Esta imagen usa ${_plusParts()}. Te ${left == 1 ? 'queda 1 imagen Plus gratis' : 'quedan $left imágenes Plus gratis'} esta semana.',
          style: _t(14, c: Colors.white70, h: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Cancelar', style: _t(14, c: Colors.white54)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              'Usar 1',
              style: _t(14, w: FontWeight.w700, c: const Color(0xFF7CF0BC)),
            ),
          ),
        ],
      ),
    );
    if (ok != true) return false;
    final after = await PlusShareQuota.use();
    if (!mounted) return false;
    if (after == null) {
      setState(() => _plusLeft = 0);
      return _showLimitSheet();
    }
    setState(() => _plusLeft = after);
    return true;
  }

  String _plusParts() {
    final parts = <String>[
      if (_style == ShareStyle.photo) 'foto de fondo',
      if (_style == ShareStyle.clear) 'imagen sin fondo',
      if (StatsPrefsService.isPlusAccentIndex(_accentIdx)) 'un color Plus',
    ];
    if (parts.length <= 1) return parts.join();
    return '${parts.sublist(0, parts.length - 1).join(', ')} y ${parts.last}';
  }

  /// Sin imágenes Plus gratis: hacerse Plus o seguir con el estilo gratis.
  /// Devuelve true si eligió seguir sin lo Plus.
  Future<bool> _showLimitSheet() async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        margin: EdgeInsets.fromLTRB(12, 0, 12, 12 + MediaQuery.of(ctx).padding.bottom),
        padding: const EdgeInsets.fromLTRB(22, 22, 22, 14),
        decoration: BoxDecoration(
          color: const Color(0xFF12141C),
          borderRadius: BorderRadius.circular(26),
          border: Border.all(color: Colors.amber.withOpacity(0.25)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 58,
              height: 58,
              decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.amber.withOpacity(0.14)),
              child: const Icon(Icons.workspace_premium_rounded, color: Colors.amber, size: 30),
            ),
            const SizedBox(height: 14),
            Text('Te quedó increíble', style: _t(19, w: FontWeight.w800)),
            const SizedBox(height: 6),
            Text(
              'Ya usaste tus ${PlusShareQuota.weeklyLimit} imágenes Plus gratis de esta semana. Con Pedalea Plus puedes usar foto de fondo, sin fondo y todos los colores cuando quieras.',
              textAlign: TextAlign.center,
              style: _t(13.5, c: Colors.white60, h: 1.45),
            ),
            const SizedBox(height: 18),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton.icon(
                onPressed: () => Navigator.pop(ctx, 'plus'),
                icon: const Icon(Icons.workspace_premium_rounded, size: 19),
                label: const Text('Hazte Plus'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.amber,
                  foregroundColor: Colors.black,
                  elevation: 0,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                  textStyle: const TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w700, fontSize: 15),
                ),
              ),
            ),
            const SizedBox(height: 6),
            TextButton(
              onPressed: () => Navigator.pop(ctx, 'free'),
              child: Text(
                'Seguir con el estilo oscuro',
                style: _t(14, w: FontWeight.w600, c: Colors.white70),
              ),
            ),
          ],
        ),
      ),
    );
    if (!mounted) return false;
    if (choice == 'plus') {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => const PaywallPage(reason: 'Comparte tus estadísticas con foto, sin fondo y todos los colores.'),
        ),
      );
      return false;
    }
    if (choice == 'free') {
      setState(() {
        _style = ShareStyle.dark;
        if (StatsPrefsService.isPlusAccentIndex(_accentIdx)) _accentIdx = 0;
      });
      await Future.delayed(const Duration(milliseconds: 80)); // que se repinte antes de exportar
      return true;
    }
    return false;
  }

  /// Datos que van en la imagen (máximo 6 para que se lean bien).
  static const _maxStats = 6;
  late final Set<String> _shown = widget.order.where(widget.shown.contains).take(_maxStats).toSet();

  /// Guarda la selección para la próxima vez.
  void _rememberStats() => StatsPrefsService.setHiddenTiles(widget.order.where((k) => !_shown.contains(k)).toSet());

  /// El color elegido también queda como color de «Mis estadísticas».
  void _pickColor(int i) {
    setState(() => _accentIdx = i);
    if (_isPlus || !StatsPrefsService.isPlusAccentIndex(i)) PlusPrefsService.setAccentIndex(i);
  }

  void _toggleStat(String key) {
    if (_shown.contains(key)) {
      setState(() => _shown.remove(key));
      _rememberStats();
    } else if (_shown.length < _maxStats) {
      setState(() => _shown.add(key));
      _rememberStats();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Puedes mostrar hasta 6 datos. Quita uno para agregar otro.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  static const _styles = [
    (ShareStyle.dark, Icons.dark_mode_rounded, 'Oscuro'),
    (ShareStyle.photo, Icons.image_rounded, 'Con foto'),
    (ShareStyle.clear, Icons.layers_clear_rounded, 'Sin fondo'),
  ];

  Future<void> _pickPhoto() async {
    try {
      final x = await ImagePicker().pickImage(source: ImageSource.gallery, maxWidth: 1600, imageQuality: 88);
      if (x == null) return;
      setState(() {
        _photo = File(x.path);
        _style = ShareStyle.photo;
      });
    } catch (e) {
      debugPrint('No se pudo elegir la foto: $e');
    }
  }

  /// Genera el PNG de la tarjeta (360×640 → 1080×1920, formato historia).
  Future<File> _renderPng() async {
    await Future.delayed(const Duration(milliseconds: 60));
    final boundary = _cardKey.currentContext!.findRenderObject() as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: 3.0);
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    if (byteData == null) throw Exception('No se pudo generar la imagen');
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/pedalea_${DateTime.now().millisecondsSinceEpoch}.png');
    await file.writeAsBytes(byteData.buffer.asUint8List());
    return file;
  }

  /// Guarda la imagen en la galería del teléfono.
  Future<void> _download() async {
    if (_sharing || _saving) return;
    if (!await _passQuota() || !mounted) return;
    setState(() => _saving = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      if (!await Gal.hasPermission(toAlbum: true) && !await Gal.requestPermission(toAlbum: true)) {
        messenger.showSnackBar(
          const SnackBar(content: Text('Necesitamos permiso para guardar en tu galería.'), behavior: SnackBarBehavior.floating),
        );
        return;
      }
      final file = await _renderPng();
      await Gal.putImage(file.path, album: 'Pedalea');
      if (mounted) setState(() => _saved = true);
      messenger.showSnackBar(
        const SnackBar(content: Text('Imagen guardada'), backgroundColor: Color(0xFF1F7A55), behavior: SnackBarBehavior.floating),
      );
      Future.delayed(const Duration(milliseconds: 2500), () {
        if (mounted) setState(() => _saved = false);
      });
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(
          content: Text('No se pudo guardar la imagen: $e'),
          backgroundColor: Colors.redAccent,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _share() async {
    if (_sharing || _saving) return;
    if (!await _passQuota() || !mounted) return;
    setState(() => _sharing = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final file = await _renderPng();

      final s = summarize(RideStatsService.allDays(), _period);
      final km = _period == StatsPeriod.all ? widget.total : s.km;
      final what = switch (_period) {
        StatsPeriod.week => 'Mi semana en bici',
        StatsPeriod.month => 'Mi mes en bici',
        StatsPeriod.year => 'Mi año en bici',
        StatsPeriod.all => 'Mis km en bici',
      };
      await Share.shareXFiles([XFile(file.path)], text: '$what: ${fmtKm(km)} km con Pedalea');
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

  Widget _plusTag() => Container(
    margin: const EdgeInsets.only(left: 6),
    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
    decoration: BoxDecoration(color: Colors.amber, borderRadius: BorderRadius.circular(6)),
    child: Text(
      'PLUS',
      style: _t(8.5, w: FontWeight.w800, c: Colors.black),
    ),
  );

  Widget _chip(String label, bool on, VoidCallback onTap, {IconData? icon, bool plus = false}) => GestureDetector(
    onTap: onTap,
    child: AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
      decoration: BoxDecoration(
        color: on ? Colors.white : Colors.white.withOpacity(0.06),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[Icon(icon, size: 16, color: on ? Colors.black : Colors.white70), const SizedBox(width: 6)],
          Text(
            label,
            style: _t(13, w: FontWeight.w600, c: on ? Colors.black : Colors.white70),
          ),
          if (plus && !_isPlus) _plusTag(),
        ],
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final s = summarize(RideStatsService.allDays(), _period);
    final items = <(String, String, String)>[
      for (final k in widget.order)
        if (_shown.contains(k))
          (
            statValue(k, s, total: widget.total, streak: widget.streak, maxSpeed: widget.maxSpeed).$1,
            statValue(k, s, total: widget.total, streak: widget.streak, maxSpeed: widget.maxSpeed).$2,
            kStatShort[k] ?? kStatMeta[k]!.$2.toUpperCase(),
          ),
    ];
    final screenH = MediaQuery.of(context).size.height;
    final previewH = (screenH * 0.42).clamp(260.0, 420.0);

    return Container(
      constraints: BoxConstraints(maxHeight: screenH * 0.94),
      decoration: const BoxDecoration(
        color: Color(0xFF0B0C12),
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 10, 8, 4),
            child: Column(
              children: [
                Container(
                  width: 38,
                  height: 4,
                  decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2)),
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Expanded(
                      child: Text('Compartir estadísticas', style: _t(18, w: FontWeight.w700)),
                    ),
                    IconButton(
                      tooltip: 'Cerrar',
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close_rounded, color: Colors.white60),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Vista previa (la tarjeta real mide 360×640 y se escala).
                  Center(
                    child: Container(
                      height: previewH,
                      width: previewH * 9 / 16,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(18),
                        color: _style == ShareStyle.clear ? const Color(0xFF3A3F4B) : null,
                        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.5), blurRadius: 24, offset: const Offset(0, 10))],
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: FittedBox(
                        child: RepaintBoundary(
                          key: _cardKey,
                          child: StoryCard(
                            summary: s,
                            total: widget.total,
                            gradient: StatsPrefsService.accentGradientFor(_accentIdx),
                            style: _style,
                            photo: _photo,
                            items: items,
                          ),
                        ),
                      ),
                    ),
                  ),
                  if (!_isPlus && _plusLeft != null && _plusLeft! >= 0)
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.workspace_premium_rounded, color: Colors.amber, size: 16),
                          const SizedBox(width: 6),
                          Flexible(
                            child: Text(
                              _plusLeft == 0
                                  ? 'Ya usaste tus imágenes Plus gratis de esta semana'
                                  : 'Te ${_plusLeft == 1 ? 'queda 1 imagen Plus gratis' : 'quedan $_plusLeft imágenes Plus gratis'} esta semana',
                              textAlign: TextAlign.center,
                              style: _t(12, w: FontWeight.w600, c: Colors.amber),
                            ),
                          ),
                        ],
                      ),
                    ),
                  if (_style == ShareStyle.clear)
                    Padding(
                      padding: const EdgeInsets.only(top: 10),
                      child: Center(
                        child: Text('Imagen sin fondo: pégala sobre tu propia historia', style: _t(11.5, c: Colors.white38)),
                      ),
                    ),
                  const SizedBox(height: 22),
                  Text(
                    'PERIODO',
                    style: _t(11, w: FontWeight.w700, c: Colors.white54, ls: 1.2),
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final (p, label) in _periodTabs) _chip(label, _period == p, () => setState(() => _period = p)),
                    ],
                  ),
                  const SizedBox(height: 20),
                  Text(
                    'ESTILO',
                    style: _t(11, w: FontWeight.w700, c: Colors.white54, ls: 1.2),
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final (st, icon, label) in _styles)
                        _chip(
                          label,
                          _style == st,
                          () {
                            if (st == ShareStyle.photo && _photo == null) {
                              _pickPhoto();
                            } else {
                              setState(() => _style = st);
                            }
                          },
                          icon: icon,
                          plus: st != ShareStyle.dark,
                        ),
                    ],
                  ),
                  if (_style == ShareStyle.photo && _photo != null)
                    TextButton.icon(
                      onPressed: _pickPhoto,
                      icon: const Icon(Icons.photo_library_rounded, size: 18),
                      label: const Text('Cambiar foto'),
                      style: TextButton.styleFrom(
                        foregroundColor: Colors.white70,
                        textStyle: _t(13, w: FontWeight.w600),
                      ),
                    ),
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      Text(
                        'DATOS',
                        style: _t(11, w: FontWeight.w700, c: Colors.white54, ls: 1.2),
                      ),
                      const Spacer(),
                      Text('${_shown.length} de $_maxStats', style: _t(11, c: Colors.white38)),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final k in widget.order)
                        _chip(kStatMeta[k]!.$2, _shown.contains(k), () => _toggleStat(k), icon: kStatMeta[k]!.$1),
                    ],
                  ),
                  const SizedBox(height: 20),
                  Text(
                    'COLOR',
                    style: _t(11, w: FontWeight.w700, c: Colors.white54, ls: 1.2),
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [for (var i = 0; i < StatsPrefsService.freeAccentCount; i++) _swatch(i)],
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Text(
                        'Colores Plus',
                        style: _t(11.5, w: FontWeight.w600, c: Colors.white54),
                      ),
                      if (!_isPlus) _plusTag(),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      for (var i = StatsPrefsService.freeAccentCount; i < StatsPrefsService.allAccentColors.length; i++)
                        _swatch(i),
                    ],
                  ),
                ],
              ),
            ),
          ),
          _footer(),
        ],
      ),
    );
  }

  Widget _swatch(int i) => GestureDetector(
    onTap: () => _pickColor(i),
    child: Container(
      width: 30,
      height: 30,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: StatsPrefsService.accentGradientFor(i),
        ),
        border: Border.all(color: i == _accentIdx ? Colors.white : Colors.transparent, width: 2.5),
      ),
      child: i == _accentIdx ? const Icon(Icons.check_rounded, color: Colors.black, size: 16) : null,
    ),
  );

  Widget _footer() {
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 8, 20, MediaQuery.of(context).padding.bottom + 14),
      child: Row(
        children: [
          Expanded(
            child: SizedBox(
              height: 52,
              child: OutlinedButton.icon(
                onPressed: (_sharing || _saving) ? null : _download,
                icon: _saving
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                    : Icon(_saved ? Icons.check_circle_rounded : Icons.download_rounded, size: 20),
                label: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(_saving ? 'Guardando…' : (_saved ? 'Imagen guardada' : 'Descargar')),
                ),
                style: OutlinedButton.styleFrom(
                  foregroundColor: _saved ? const Color(0xFF7CF0BC) : Colors.white,
                  side: BorderSide(color: _saved ? const Color(0xFF7CF0BC) : Colors.white.withOpacity(0.25)),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  textStyle: const TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w700, fontSize: 15),
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: SizedBox(
              height: 52,
              child: ElevatedButton.icon(
                onPressed: (_sharing || _saving) ? null : _share,
                icon: _sharing
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(color: Colors.black, strokeWidth: 2))
                    : const Icon(Icons.ios_share_rounded, size: 19),
                label: Text(_sharing ? 'Generando…' : 'Compartir'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: Colors.black,
                  disabledBackgroundColor: Colors.white12,
                  elevation: 0,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  textStyle: const TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w700, fontSize: 15),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// La imagen que se comparte: 360×640 lógicos (1080×1920 al exportar).
class StoryCard extends StatelessWidget {
  final PeriodSummary summary;
  final double total;

  /// Color de acento: dos tonos (iguales si es un color sólido).
  final List<Color> gradient;
  final ShareStyle style;
  final File? photo;

  /// Datos a mostrar: (valor, unidad, etiqueta).
  final List<(String, String, String)> items;
  const StoryCard({
    super.key,
    required this.summary,
    required this.total,
    required this.gradient,
    required this.style,
    required this.photo,
    required this.items,
  });

  @override
  Widget build(BuildContext context) {
    final accent = gradient.first;
    final now = DateTime.now();
    final p = summary.period;
    final km = p == StatsPeriod.all ? total : summary.km;
    final title = switch (p) {
      StatsPeriod.week => 'MI SEMANA EN BICI',
      StatsPeriod.month => 'MI MES EN BICI',
      StatsPeriod.year => 'MI AÑO EN BICI',
      StatsPeriod.all => 'MIS KM EN BICI',
    };
    final when = switch (p) {
      StatsPeriod.week => '${_fmtDia(weekStart(now))} – ${_fmtDia(weekStart(now).add(const Duration(days: 6)))}',
      StatsPeriod.month => '${_meses[now.month - 1]} ${now.year}',
      StatsPeriod.year => '${now.year}',
      StatsPeriod.all => 'desde siempre',
    }.toUpperCase();
    final shadows = style == ShareStyle.dark ? null : [Shadow(color: Colors.black.withOpacity(0.55), blurRadius: 12)];
    TextStyle s(double size, {FontWeight w = FontWeight.w700, Color c = Colors.white, double? h, double? ls}) =>
        TextStyle(fontFamily: 'Poppins', fontSize: size, fontWeight: w, color: c, height: h, letterSpacing: ls, shadows: shadows);

    Widget stat(String value, String unit, String label) => Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(value, maxLines: 1, style: s(24, w: FontWeight.w800, h: 1.1)),
                ),
              ),
              if (unit.isNotEmpty) ...[
                const SizedBox(width: 3),
                Text(
                  unit,
                  style: s(12, w: FontWeight.w600, c: Colors.white70),
                ),
              ],
            ],
          ),
          const SizedBox(height: 2),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: s(9.5, w: FontWeight.w700, c: Colors.white60, ls: 1.2),
          ),
        ],
      ),
    );

    final maxKm = summary.bars.fold<double>(0, (m, b) => b.km > m ? b.km : m);
    final cols = items.length == 4 ? 2 : 3;

    final content = Padding(
      padding: const EdgeInsets.fromLTRB(30, 34, 30, 30),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              // Logo de la app en círculo.
              Container(
                width: 22,
                height: 22,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white.withOpacity(0.25), width: 1),
                  image: const DecorationImage(
                    image: AssetImage('assets/branding/pedalea-icono-fondo-oscuro.png'),
                    fit: BoxFit.cover,
                  ),
                ),
              ),
              const SizedBox(width: 7),
              Text('pedalea', style: s(15, w: FontWeight.w800, ls: -0.3)),
              const Spacer(),
              Text(
                when,
                style: s(10, w: FontWeight.w700, c: Colors.white70, ls: 1.2),
              ),
            ],
          ),
          const Spacer(),
          Text(
            title,
            style: s(13, w: FontWeight.w700, c: Colors.white70, ls: 2.2),
          ),
          const SizedBox(height: 4),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(fmtKm(km), style: s(104, w: FontWeight.w800, h: 1.0, ls: -4)),
          ),
          ShaderMask(
            blendMode: BlendMode.srcIn,
            shaderCallback: (r) => LinearGradient(colors: gradient).createShader(r),
            child: Text('KILÓMETROS', style: s(14, w: FontWeight.w800, ls: 3)),
          ),
          const SizedBox(height: 26),
          SizedBox(
            height: 64,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                for (final b in summary.bars)
                  Expanded(
                    child: Padding(
                      padding: EdgeInsets.symmetric(horizontal: summary.bars.length > 14 ? 1 : 4),
                      child: FractionallySizedBox(
                        heightFactor: maxKm <= 0 ? 0.04 : (b.km / maxKm).clamp(0.04, 1.0),
                        alignment: Alignment.bottomCenter,
                        child: Container(
                          decoration: BoxDecoration(
                            color: b.km > 0 ? null : Colors.white.withOpacity(0.25),
                            gradient: b.km > 0
                                ? LinearGradient(begin: Alignment.bottomCenter, end: Alignment.topCenter, colors: gradient)
                                : null,
                            borderRadius: BorderRadius.circular(3),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          // Datos elegidos: de a 3 por fila (2 si son 4, para que no quede uno solo).
          for (var i = 0; i < items.length; i += cols) ...[
            SizedBox(height: i == 0 ? 26 : 18),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var j = i; j < i + cols; j++)
                  if (j < items.length) stat(items[j].$1, items[j].$2, items[j].$3) else const Expanded(child: SizedBox()),
              ],
            ),
          ],
          const SizedBox(height: 26),
          Container(height: 1, color: Colors.white.withOpacity(0.18)),
          const SizedBox(height: 12),
          Row(
            children: [
              Text(
                'Descarga Pedalea en Google Play',
                style: s(10.5, w: FontWeight.w600, c: Colors.white60),
              ),
              const Spacer(),
              Icon(Icons.shop_rounded, size: 14, color: Colors.white60, shadows: shadows),
            ],
          ),
        ],
      ),
    );

    Widget background;
    switch (style) {
      case ShareStyle.dark:
        background = Stack(
          children: [
            const Positioned.fill(child: ColoredBox(color: Color(0xFF07080C))),
            Positioned(
              top: -120,
              right: -140,
              child: Container(
                width: 420,
                height: 420,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(colors: [accent.withOpacity(0.35), accent.withOpacity(0)]),
                ),
              ),
            ),
            Positioned(
              bottom: -160,
              left: -120,
              child: Container(
                width: 380,
                height: 380,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(colors: [gradient.last.withOpacity(0.16), gradient.last.withOpacity(0)]),
                ),
              ),
            ),
          ],
        );
      case ShareStyle.photo:
        background = Stack(
          fit: StackFit.expand,
          children: [
            if (photo != null) Image.file(photo!, fit: BoxFit.cover) else const ColoredBox(color: Color(0xFF1B1E26)),
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0x66000000), Color(0x00000000), Color(0xCC000000)],
                  stops: [0, 0.35, 0.75],
                ),
              ),
            ),
          ],
        );
      case ShareStyle.clear:
        background = const SizedBox.shrink();
    }

    return Material(
      type: MaterialType.transparency,
      child: SizedBox(
        width: 360,
        height: 640,
        child: Stack(
          children: [
            Positioned.fill(child: background),
            Positioned.fill(child: content),
          ],
        ),
      ),
    );
  }
}

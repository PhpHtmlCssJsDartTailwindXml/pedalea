import 'package:flutter/material.dart';
import '../core/glass.dart';
import '../services/ride_stats_sync_service.dart';
import '../widgets/leaderboard.dart';
import 'public_profile_page.dart';

/// Ranking de ciclistas: km del día, km de la semana y velocidad máxima.
/// Se alimenta de la tabla `ride_stats` de Supabase (RPC `ride_ranking`).
class RiderRankingPage extends StatefulWidget {
  const RiderRankingPage({super.key});

  @override
  State<RiderRankingPage> createState() => _RiderRankingPageState();
}

class _RiderRankingPageState extends State<RiderRankingPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 3, vsync: this);

  static const _accent = Color(0xFF69FF47);

  static const _boards = <_BoardSpec>[
    _BoardSpec(label: 'Hoy', metric: 'km', sinceDays: 1, unit: 'km'),
    _BoardSpec(label: 'Semana', metric: 'km', sinceDays: 7, unit: 'km'),
    _BoardSpec(
      label: 'Vel. máx',
      metric: 'max_speed',
      sinceDays: 30,
      unit: 'km/h',
    ),
  ];

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: kPageGradient,
        child: SafeArea(
          child: Column(
            children: [
              const LeaderboardHeader(
                title: 'Ranking de ciclistas',
                icon: Icons.emoji_events_rounded,
                accent: _accent,
              ),
              LeaderboardTabs(
                controller: _tabs,
                labels: [for (final b in _boards) b.label],
                accent: _accent,
              ),
              Expanded(
                child: TabBarView(
                  controller: _tabs,
                  children: [for (final b in _boards) _Board(spec: b)],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BoardSpec {
  final String label;
  final String metric;
  final int sinceDays;
  final String unit;
  const _BoardSpec({
    required this.label,
    required this.metric,
    required this.sinceDays,
    required this.unit,
  });
}

class _Board extends StatefulWidget {
  final _BoardSpec spec;
  const _Board({required this.spec});

  @override
  State<_Board> createState() => _BoardState();
}

class _BoardState extends State<_Board>
    with AutomaticKeepAliveClientMixin {
  static const _accent = Color(0xFF69FF47);
  late Future<List<RankingEntry>> _future;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _future = _fetch();
  }

  Future<List<RankingEntry>> _fetch() => RideStatsSyncService.instance
      .fetchRanking(metric: widget.spec.metric, sinceDays: widget.spec.sinceDays);

  Future<void> _refresh() async {
    final data = await _fetch();
    if (mounted) setState(() => _future = Future.value(data));
  }

  String _fmt(double v) => v.toStringAsFixed(1);

  void _openProfile(String userId) {
    Navigator.push(context,
        MaterialPageRoute(builder: (_) => PublicProfilePage(userId: userId)));
  }

  Widget _avatar(RankingEntry e) => RankAvatar(name: e.username, url: e.avatarUrl);

  /// Texto competitivo: cuánto falta para pasar al de arriba o la ventaja.
  String? _chaseText(List<RankingEntry> rows, int myIndex) {
    final unit = widget.spec.unit;
    final me = rows[myIndex];
    if (myIndex == 0) {
      if (rows.length < 2) return '¡Lideras este ranking! 🏆';
      final gap = me.value - rows[1].value;
      return '¡Lideras! Ventaja de ${_fmt(gap)} $unit sobre ${rows[1].username}';
    }
    final ahead = rows[myIndex - 1];
    final gap = (ahead.value - me.value).clamp(0.1, double.infinity);
    return 'Te faltan ${_fmt(gap)} $unit para pasar a ${ahead.username}';
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final unit = widget.spec.unit;
    return RefreshIndicator(
      onRefresh: _refresh,
      color: _accent,
      backgroundColor: kBgCard,
      child: FutureBuilder<List<RankingEntry>>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(
              child: CircularProgressIndicator(color: _accent, strokeWidth: 2),
            );
          }
          final rows = snap.data ?? const <RankingEntry>[];
          if (rows.isEmpty) {
            return ListView(
              padding: const EdgeInsets.symmetric(horizontal: 40),
              children: [
                const SizedBox(height: 110),
                Center(
                  child: Container(
                    width: 84,
                    height: 84,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: _accent.withOpacity(0.08),
                      border: Border.all(color: _accent.withOpacity(0.25)),
                    ),
                    child: Icon(Icons.flag_rounded,
                        color: _accent.withOpacity(0.8), size: 36),
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Nadie ha tomado la delantera',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Pedalea con el "Modo activo" encendido para aparecer y ser el primero.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    color: Colors.white.withOpacity(0.45),
                    fontSize: 13,
                  ),
                ),
              ],
            );
          }

          final myIndex = rows.indexWhere((r) => r.isMe);
          final leader = rows.first.value <= 0 ? 1.0 : rows.first.value;
          final hasPodium = rows.length >= 3;
          final rest = hasPodium ? rows.sublist(3) : rows;
          final restOffset = hasPodium ? 3 : 0;

          return ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
            children: [
              MyRankCard(
                rank: myIndex >= 0 ? myIndex + 1 : null,
                total: rows.length,
                value: myIndex >= 0 ? _fmt(rows[myIndex].value) : '',
                unit: unit,
                accent: _accent,
                emptyText:
                    'Activa el "Modo activo" y pedalea para entrar al ranking.',
                chaseText: myIndex >= 0 ? _chaseText(rows, myIndex) : null,
              ),
              if (hasPodium) ...[
                const SizedBox(height: 22),
                Podium(
                  top: [
                    for (final e in rows.take(3))
                      PodiumEntry(
                        name: e.username,
                        value: _fmt(e.value),
                        unit: unit,
                        avatar: _avatar(e),
                        isMe: e.isMe,
                        onTap: () => _openProfile(e.userId),
                      ),
                  ],
                ),
              ],
              if (rest.isNotEmpty) ...[
                const SizedBox(height: 22),
                LeaderSectionLabel(
                  'CLASIFICACIÓN',
                  accent: _accent,
                  trailing: '${rows.length} ciclistas',
                ),
                const SizedBox(height: 10),
                for (int i = 0; i < rest.length; i++)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: LeaderRow(
                      rank: restOffset + i + 1,
                      avatar: _avatar(rest[i]),
                      name: rest[i].username,
                      value: _fmt(rest[i].value),
                      unit: unit,
                      progress: rest[i].value / leader,
                      isMe: rest[i].isMe,
                      accent: _accent,
                      onTap: () => _openProfile(rest[i].userId),
                    ),
                  ),
              ],
            ],
          );
        },
      ),
    );
  }
}

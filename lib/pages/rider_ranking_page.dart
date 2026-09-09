import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import '../core/glass.dart';
import '../services/ride_stats_sync_service.dart';

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
              _header(),
              TabBar(
                controller: _tabs,
                indicatorColor: _accent,
                indicatorSize: TabBarIndicatorSize.label,
                labelColor: _accent,
                unselectedLabelColor: Colors.white54,
                labelStyle: const TextStyle(
                  fontFamily: 'Poppins',
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                ),
                unselectedLabelStyle: const TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 13,
                ),
                tabs: [for (final b in _boards) Tab(text: b.label)],
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

  Widget _header() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 8, 16, 4),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
            onPressed: () => Navigator.pop(context),
          ),
          const Expanded(
            child: Text(
              'Ranking de ciclistas',
              style: TextStyle(
                fontFamily: 'Poppins',
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
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

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return RefreshIndicator(
      onRefresh: _refresh,
      color: const Color(0xFF69FF47),
      backgroundColor: kBgCard,
      child: FutureBuilder<List<RankingEntry>>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(
              child: CircularProgressIndicator(color: Color(0xFF69FF47)),
            );
          }
          final rows = snap.data ?? const <RankingEntry>[];
          if (rows.isEmpty) {
            return ListView(
              padding: const EdgeInsets.symmetric(horizontal: 40),
              children: const [
                SizedBox(height: 120),
                Icon(Icons.pedal_bike_rounded,
                    color: Colors.white24, size: 44),
                SizedBox(height: 12),
                Text(
                  'Todavía no hay datos en este ranking.\n'
                  'Pedalea con el "Modo activo" encendido para aparecer.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    color: Colors.white38,
                    fontSize: 13,
                  ),
                ),
              ],
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
            itemCount: rows.length,
            separatorBuilder: (_, _) => const SizedBox(height: 8),
            itemBuilder: (_, i) => _row(rows[i], i + 1),
          );
        },
      ),
    );
  }

  Widget _row(RankingEntry e, int rank) {
    final medal = switch (rank) {
      1 => '🥇',
      2 => '🥈',
      3 => '🥉',
      _ => null,
    };
    final value = e.value.toStringAsFixed(1);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: glassDecoration(
        radius: 16,
        opacity: e.isMe ? 0.10 : 0.05,
        tint: e.isMe ? const Color(0xFF69FF47) : null,
        borderOpacity: e.isMe ? 0.35 : 0.12,
      ),
      child: Row(
        children: [
          SizedBox(
            width: 30,
            child: Center(
              child: medal != null
                  ? Text(medal, style: const TextStyle(fontSize: 20))
                  : Text(
                      '$rank',
                      style: const TextStyle(
                        fontFamily: 'Poppins',
                        color: Colors.white54,
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                      ),
                    ),
            ),
          ),
          const SizedBox(width: 8),
          _avatar(e),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              e.isMe ? '${e.username} (tú)' : e.username,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontFamily: 'Poppins',
                color: Colors.white,
                fontSize: 14,
                fontWeight: e.isMe ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ),
          const SizedBox(width: 8),
          RichText(
            text: TextSpan(
              children: [
                TextSpan(
                  text: value,
                  style: const TextStyle(
                    fontFamily: 'Poppins',
                    color: Color(0xFF69FF47),
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                TextSpan(
                  text: ' ${widget.spec.unit}',
                  style: const TextStyle(
                    fontFamily: 'Poppins',
                    color: Colors.white38,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _avatar(RankingEntry e) {
    final initial =
        e.username.isNotEmpty ? e.username.characters.first.toUpperCase() : '?';
    Widget fallback() => Container(
          color: Colors.white.withOpacity(0.08),
          alignment: Alignment.center,
          child: Text(
            initial,
            style: const TextStyle(
              fontFamily: 'Poppins',
              color: Colors.white70,
              fontWeight: FontWeight.w700,
            ),
          ),
        );
    return SizedBox(
      width: 36,
      height: 36,
      child: ClipOval(
        child: (e.avatarUrl != null && e.avatarUrl!.isNotEmpty)
            ? CachedNetworkImage(
                imageUrl: e.avatarUrl!,
                fit: BoxFit.cover,
                fadeInDuration: Duration.zero,
                placeholder: (_, _) => fallback(),
                errorWidget: (_, _, _) => fallback(),
              )
            : fallback(),
      ),
    );
  }
}

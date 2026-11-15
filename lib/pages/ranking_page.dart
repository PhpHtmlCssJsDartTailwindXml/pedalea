import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../core/glass.dart';
import '../services/cache_service.dart';
import '../services/karma_service.dart';
import '../widgets/leaderboard.dart';
import 'public_profile_page.dart';

class RankingPage extends StatefulWidget {
  const RankingPage({super.key});

  @override
  State<RankingPage> createState() => _RankingPageState();
}

class _RankingPageState extends State<RankingPage>
    with SingleTickerProviderStateMixin {
  static const _accent = Colors.greenAccent;

  late TabController _tabController;
  final KarmaService _karmaService = KarmaService();

  List<Map<String, dynamic>> _topCyclists = [];
  List<Map<String, dynamic>> _comunasRanking = [];
  bool _loadingCyclists = true;
  bool _loadingComunas = true;

  final String? _myId = Supabase.instance.client.auth.currentUser?.id;
  final String _myCommune =
      (CacheService.loadProfile()?['commune'] as String? ?? '').trim();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    final cyclists = await _karmaService.getTopCyclists();
    final comunas = await _karmaService.getRankingByComunas();
    if (mounted) {
      setState(() {
        _topCyclists = cyclists;
        _loadingCyclists = false;
        _comunasRanking = comunas;
        _loadingComunas = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      extendBodyBehindAppBar: true,
      body: Container(
        decoration: kPageGradient,
        child: SafeArea(
          bottom: false,
          child: Column(
            children: [
              LeaderboardHeader(
                title: 'Ranking local',
                icon: Icons.leaderboard_rounded,
                accent: _accent,
                onRefresh: () {
                  setState(() {
                    _loadingCyclists = true;
                    _loadingComunas = true;
                  });
                  _loadData();
                },
              ),
              LeaderboardTabs(
                controller: _tabController,
                labels: const ['Por comunas', 'Top karma'],
                accent: _accent,
              ),
              Expanded(
                child: TabBarView(
                  controller: _tabController,
                  children: [
                    _buildComunasTab(),
                    _buildCyclistsTab(),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Tab: Comunas ───────────────────────────────────────────────────────────

  double _km(Map<String, dynamic> c) =>
      (c['total_km'] as num?)?.toDouble() ?? 0.0;

  String _comunaSecondary(Map<String, dynamic> c) {
    final cyclists = c['cyclists_count'] as int? ?? 0;
    final alerts = c['alerts_count'] as int? ?? 0;
    return cyclists > 0
        ? '$cyclists ${cyclists == 1 ? 'ciclista' : 'ciclistas'}'
        : '$alerts alertas';
  }

  Widget _buildComunasTab() {
    if (_loadingComunas) return _loader();

    if (_comunasRanking.isEmpty) {
      return _buildEmptyState(
        icon: Icons.location_city_rounded,
        title: 'Sin datos de comunas',
        subtitle:
            'Activa el GPS y pedalea para que tu comuna aparezca aquí. Asegúrate de reportar alertas con nombre de ubicación.',
      );
    }

    final list = _comunasRanking;
    final leader = _km(list.first) <= 0 ? 1.0 : _km(list.first);
    final myIndex = _myCommune.isEmpty
        ? -1
        : list.indexWhere((c) =>
            (c['commune'] as String? ?? '').toLowerCase() ==
            _myCommune.toLowerCase());
    final hasPodium = list.length >= 3;
    final rest = hasPodium ? list.sublist(3) : list;
    final offset = hasPodium ? 3 : 0;

    String? chase() {
      if (myIndex < 0) return null;
      if (myIndex == 0) return '¡Tu comuna lidera la región! 🏆';
      final ahead = list[myIndex - 1];
      final gap = (_km(ahead) - _km(list[myIndex])).clamp(0.1, double.infinity);
      return 'A ${gap.toStringAsFixed(1)} km de ${ahead['commune']}';
    }

    return RefreshIndicator(
      onRefresh: _loadData,
      color: _accent,
      backgroundColor: kBgCard,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: [
          MyRankCard(
            rank: myIndex >= 0 ? myIndex + 1 : null,
            total: list.length,
            value: myIndex >= 0 ? _km(list[myIndex]).toStringAsFixed(1) : '',
            unit: myIndex >= 0 ? 'km · ${list[myIndex]['commune']}' : 'km',
            accent: _accent,
            emptyText: _myCommune.isEmpty
                ? 'Agrega tu comuna en el perfil para ver su posición.'
                : '$_myCommune aún no suma km. ¡Pedalea para subirla!',
            chaseText: chase(),
          ),
          if (hasPodium) ...[
            const SizedBox(height: 22),
            Podium(
              top: [
                for (int i = 0; i < 3; i++)
                  PodiumEntry(
                    name: list[i]['commune'] as String? ?? '—',
                    value: _km(list[i]).toStringAsFixed(1),
                    unit: 'km',
                    avatar: RankAvatar(
                      name: list[i]['commune'] as String? ?? '—',
                      icon: Icons.location_city_rounded,
                    ),
                    isMe: i == myIndex,
                  ),
              ],
            ),
          ],
          if (rest.isNotEmpty) ...[
            const SizedBox(height: 22),
            LeaderSectionLabel(
              'CLASIFICACIÓN',
              accent: _accent,
              trailing: '${list.length} comunas',
            ),
            const SizedBox(height: 10),
            for (int i = 0; i < rest.length; i++)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: LeaderRow(
                  rank: offset + i + 1,
                  avatar: RankAvatar(
                    name: rest[i]['commune'] as String? ?? '—',
                    icon: Icons.location_city_rounded,
                  ),
                  name: rest[i]['commune'] as String? ?? '—',
                  subtitle: _comunaSecondary(rest[i]),
                  value: _km(rest[i]).toStringAsFixed(1),
                  unit: 'km',
                  progress: _km(rest[i]) / leader,
                  isMe: offset + i == myIndex,
                  accent: _accent,
                ),
              ),
          ],
          const SizedBox(height: 14),
          _buildHint(
            'Los km se acumulan mientras pedaleas con GPS activo. Asegúrate de tener el modo activo encendido.',
          ),
        ],
      ),
    );
  }

  // ── Tab: Top karma ─────────────────────────────────────────────────────────

  int _karma(Map<String, dynamic> c) => c['karma'] as int? ?? 0;

  String _name(Map<String, dynamic> c) =>
      (c['username'] as String? ?? '').isNotEmpty
          ? '@${c['username']}'
          : (c['user_name'] as String? ?? 'Usuario');

  void _openProfile(Map<String, dynamic> c) {
    final id = c['user_id'] as String?;
    if (id == null) return;
    Navigator.push(context,
        MaterialPageRoute(builder: (_) => PublicProfilePage(userId: id)));
  }

  Widget _buildCyclistsTab() {
    if (_loadingCyclists) return _loader();

    if (_topCyclists.isEmpty) {
      return _buildEmptyState(
        icon: Icons.emoji_events_rounded,
        title: 'Sin datos todavía',
        subtitle:
            'Reporta alertas y recibe votos de la comunidad para aparecer en el ranking.',
      );
    }

    final list = _topCyclists;
    final leader = _karma(list.first) <= 0 ? 1 : _karma(list.first);
    final myIndex = _myId == null
        ? -1
        : list.indexWhere((c) => c['user_id'] == _myId);
    final hasPodium = list.length >= 3;
    final rest = hasPodium ? list.sublist(3) : list;
    final offset = hasPodium ? 3 : 0;

    String? chase() {
      if (myIndex < 0) return null;
      if (myIndex == 0) {
        if (list.length < 2) return '¡Eres el ciclista con más karma! 🏆';
        final gap = _karma(list[0]) - _karma(list[1]);
        return '¡Lideras! $gap pts sobre ${_name(list[1])}';
      }
      final ahead = list[myIndex - 1];
      final gap = (_karma(ahead) - _karma(list[myIndex])) + 1;
      return 'Te faltan $gap pts para pasar a ${_name(ahead)}';
    }

    return RefreshIndicator(
      onRefresh: _loadData,
      color: _accent,
      backgroundColor: kBgCard,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: [
          MyRankCard(
            rank: myIndex >= 0 ? myIndex + 1 : null,
            total: list.length,
            value: myIndex >= 0 ? '${_karma(list[myIndex])}' : '',
            unit: 'pts de karma',
            accent: _accent,
            emptyText:
                'Reporta alertas útiles y recibe votos para entrar al top.',
            chaseText: chase(),
          ),
          if (hasPodium) ...[
            const SizedBox(height: 22),
            Podium(
              top: [
                for (int i = 0; i < 3; i++)
                  PodiumEntry(
                    name: _name(list[i]),
                    value: '${_karma(list[i])}',
                    unit:
                        '${KarmaService.getLevel(_karma(list[i])).emoji} pts',
                    avatar: RankAvatar(name: _name(list[i])),
                    isMe: i == myIndex,
                    onTap: () => _openProfile(list[i]),
                  ),
              ],
            ),
          ],
          if (rest.isNotEmpty) ...[
            const SizedBox(height: 22),
            LeaderSectionLabel(
              'CLASIFICACIÓN',
              accent: _accent,
              trailing: '${list.length} ciclistas',
            ),
            const SizedBox(height: 10),
            for (int i = 0; i < rest.length; i++)
              Builder(builder: (_) {
                final c = rest[i];
                final level = KarmaService.getLevel(_karma(c));
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: LeaderRow(
                    rank: offset + i + 1,
                    avatar: RankAvatar(name: _name(c)),
                    name: _name(c),
                    subtitle: '${level.emoji} ${level.title}',
                    value: '${_karma(c)}',
                    unit: 'pts',
                    progress: _karma(c) / leader,
                    isMe: offset + i == myIndex,
                    accent: _accent,
                    valueColor: Color(level.colorValue),
                    onTap: () => _openProfile(c),
                  ),
                );
              }),
          ],
          const SizedBox(height: 14),
          _buildHint(
            'El karma sube cuando la comunidad vota positivo tus reportes de alertas.',
          ),
        ],
      ),
    );
  }

  // ── Widgets reutilizables ─────────────────────────────────────────────────

  Widget _loader() => const Center(
        child: CircularProgressIndicator(color: _accent, strokeWidth: 2),
      );

  Widget _buildEmptyState({
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 84,
              height: 84,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _accent.withOpacity(0.08),
                border: Border.all(color: _accent.withOpacity(0.25)),
              ),
              child: Icon(icon, color: _accent.withOpacity(0.8), size: 36),
            ),
            const SizedBox(height: 16),
            Text(
              title,
              style: const TextStyle(
                fontFamily: 'Poppins',
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              subtitle,
              style: TextStyle(
                fontFamily: 'Poppins',
                color: Colors.white.withOpacity(0.45),
                fontSize: 13,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHint(String text) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.info_outline_rounded,
            color: Colors.white.withOpacity(0.35), size: 15),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: TextStyle(
              fontFamily: 'Poppins',
              color: Colors.white.withOpacity(0.38),
              fontSize: 11.5,
              height: 1.4,
            ),
          ),
        ),
      ],
    );
  }
}

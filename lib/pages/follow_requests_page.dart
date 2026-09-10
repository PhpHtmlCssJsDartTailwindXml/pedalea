import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import '../core/glass.dart';
import '../services/social_service.dart';
import '../widgets/plus_medal.dart';
import 'public_profile_page.dart';

/// Solicitudes de seguimiento pendientes de aprobar o rechazar.
class FollowRequestsPage extends StatefulWidget {
  const FollowRequestsPage({super.key});

  @override
  State<FollowRequestsPage> createState() => _FollowRequestsPageState();
}

class _FollowRequestsPageState extends State<FollowRequestsPage> {
  final _social = SocialService.instance;
  List<Map<String, dynamic>> _reqs = [];
  bool _loading = true;
  final Set<String> _busy = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final r = await _social.pendingRequests();
    if (!mounted) return;
    setState(() {
      _reqs = r;
      _loading = false;
    });
  }

  Future<void> _act(String followerId, bool accept) async {
    setState(() => _busy.add(followerId));
    if (accept) {
      await _social.acceptRequest(followerId);
    } else {
      await _social.removeFollower(followerId);
    }
    if (!mounted) return;
    setState(() {
      _reqs.removeWhere((e) => e['id'] == followerId);
      _busy.remove(followerId);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBgDark,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        title: const Text('Solicitudes',
            style: TextStyle(
                fontFamily: 'Poppins',
                color: Colors.white,
                fontWeight: FontWeight.w700)),
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: Colors.greenAccent))
          : _reqs.isEmpty
              ? Center(
                  child: Text('No tienes solicitudes pendientes',
                      style: TextStyle(
                          fontFamily: 'Poppins',
                          color: Colors.white.withOpacity(0.4))),
                )
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView.separated(
                    padding: const EdgeInsets.all(16),
                    itemCount: _reqs.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 10),
                    itemBuilder: (_, i) => _tile(_reqs[i]),
                  ),
                ),
    );
  }

  Widget _tile(Map<String, dynamic> r) {
    final id = r['id'] as String;
    final u = (r['username'] as String?)?.trim();
    final f = (r['full_name'] as String?)?.trim();
    final name = (f != null && f.isNotEmpty)
        ? f
        : (u != null && u.isNotEmpty ? u : 'Ciclista');
    final avatar = (r['avatar_url'] as String?) ?? '';
    final isPlus = r['is_plus'] == true;
    final busy = _busy.contains(id);

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.04),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withOpacity(0.08)),
      ),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (_) => PublicProfilePage(userId: id)),
            ).then((_) => _load()),
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                CircleAvatar(
                  radius: 20,
                  backgroundColor: Colors.white12,
                  backgroundImage: avatar.isNotEmpty
                      ? CachedNetworkImageProvider(avatar)
                      : null,
                  child: avatar.isEmpty
                      ? Text(name.substring(0, 1).toUpperCase(),
                          style: const TextStyle(
                              fontFamily: 'Poppins', color: Colors.white))
                      : null,
                ),
                if (isPlus)
                  Positioned(
                    bottom: -3,
                    right: -3,
                    child: PlusMedal(
                      size: 14,
                      variant:
                          (r['plus_badge_variant'] as num?)?.toInt() ?? 0,
                      ringColor: const Color(0xFF12121C),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    fontFamily: 'Poppins',
                    color: Colors.white,
                    fontWeight: FontWeight.w600)),
          ),
          if (busy)
            const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                  strokeWidth: 2, color: Colors.white30),
            )
          else ...[
            IconButton(
              onPressed: () => _act(id, false),
              icon: const Icon(Icons.close_rounded, color: Colors.white54),
            ),
            IconButton(
              onPressed: () => _act(id, true),
              icon: const Icon(Icons.check_circle_rounded,
                  color: Color(0xFF69FF47)),
            ),
          ],
        ],
      ),
    );
  }
}

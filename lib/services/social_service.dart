import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Backend de "Momentos": seguir (con aprobación), feed de fotos, likes y
/// comentarios. Like y comentario abiertos a cualquier ciclista con sesión,
/// salvo bloqueo entre ambos (lo obliga la RLS con not_blocked).
class SocialService {
  SocialService._();
  static final SocialService instance = SocialService._();

  SupabaseClient get _sb => Supabase.instance.client;
  String? get _uid => _sb.auth.currentUser?.id;

  // ── Perfiles ────────────────────────────────────────────────────────
  Future<Map<String, Map<String, dynamic>>> _profilesByIds(
      List<String> ids) async {
    if (ids.isEmpty) return {};
    final rows = await _sb
        .from('profiles')
        .select(
            'id, username, full_name, avatar_url, commune, total_km, is_plus, plus_badge_variant')
        .inFilter('id', ids);
    return {
      for (final r in rows) r['id'] as String: Map<String, dynamic>.from(r)
    };
  }

  Future<Map<String, dynamic>?> profile(String userId) async {
    try {
      final r = await _sb
          .from('profiles')
          .select(
              'id, username, full_name, avatar_url, commune, total_km, is_plus, plus_badge_variant')
          .eq('id', userId)
          .maybeSingle();
      return r == null ? null : Map<String, dynamic>.from(r);
    } catch (e) {
      debugPrint('SocialService.profile: $e');
      return null;
    }
  }

  // ── Seguir ──────────────────────────────────────────────────────────
  /// Relación con [otherId]: `outgoing` = lo que yo hice hacia esa persona,
  /// `incoming` = lo que esa persona hizo hacia mí. Valores: none | pending |
  /// accepted.
  Future<({String outgoing, String incoming})> relationWith(
      String otherId) async {
    final me = _uid;
    if (me == null || me == otherId) {
      return (outgoing: 'none', incoming: 'none');
    }
    try {
      final out = await _sb
          .from('follows')
          .select('status')
          .eq('follower_id', me)
          .eq('following_id', otherId)
          .maybeSingle();
      final inc = await _sb
          .from('follows')
          .select('status')
          .eq('follower_id', otherId)
          .eq('following_id', me)
          .maybeSingle();
      return (
        outgoing: (out?['status'] as String?) ?? 'none',
        incoming: (inc?['status'] as String?) ?? 'none',
      );
    } catch (e) {
      debugPrint('SocialService.relationWith: $e');
      return (outgoing: 'none', incoming: 'none');
    }
  }

  Future<void> requestFollow(String otherId) async {
    final me = _uid;
    if (me == null || me == otherId) return;
    try {
      await _sb.from('follows').upsert({
        'follower_id': me,
        'following_id': otherId,
        'status': 'pending',
      }, onConflict: 'follower_id,following_id', ignoreDuplicates: true);
    } catch (e) {
      debugPrint('SocialService.requestFollow: $e');
    }
  }

  /// Cancela una solicitud pendiente o deja de seguir.
  Future<void> unfollow(String otherId) async {
    final me = _uid;
    if (me == null) return;
    try {
      await _sb
          .from('follows')
          .delete()
          .eq('follower_id', me)
          .eq('following_id', otherId);
    } catch (e) {
      debugPrint('SocialService.unfollow: $e');
    }
  }

  Future<void> acceptRequest(String followerId) async {
    final me = _uid;
    if (me == null) return;
    try {
      await _sb
          .from('follows')
          .update({'status': 'accepted'})
          .eq('follower_id', followerId)
          .eq('following_id', me);
    } catch (e) {
      debugPrint('SocialService.acceptRequest: $e');
    }
  }

  /// Rechaza una solicitud entrante o quita a un seguidor.
  Future<void> removeFollower(String followerId) async {
    final me = _uid;
    if (me == null) return;
    try {
      await _sb
          .from('follows')
          .delete()
          .eq('follower_id', followerId)
          .eq('following_id', me);
    } catch (e) {
      debugPrint('SocialService.removeFollower: $e');
    }
  }

  Future<List<Map<String, dynamic>>> pendingRequests() async {
    final me = _uid;
    if (me == null) return [];
    try {
      final rows = await _sb
          .from('follows')
          .select('follower_id, created_at')
          .eq('following_id', me)
          .eq('status', 'pending')
          .order('created_at', ascending: false);
      if (rows.isEmpty) return [];
      final ids = rows.map((r) => r['follower_id'] as String).toList();
      final profs = await _profilesByIds(ids);
      return rows
          .map((r) => {
                ...?profs[r['follower_id']],
                'id': r['follower_id'],
                'requested_at': r['created_at'],
              })
          .toList();
    } catch (e) {
      debugPrint('SocialService.pendingRequests: $e');
      return [];
    }
  }

  Future<int> pendingRequestCount() async {
    final me = _uid;
    if (me == null) return 0;
    try {
      final rows = await _sb
          .from('follows')
          .select('follower_id')
          .eq('following_id', me)
          .eq('status', 'pending');
      return rows.length;
    } catch (_) {
      return 0;
    }
  }

  Future<({int followers, int following})> counts(String userId) async {
    try {
      final f1 = await _sb
          .from('follows')
          .select('follower_id')
          .eq('following_id', userId)
          .eq('status', 'accepted');
      final f2 = await _sb
          .from('follows')
          .select('following_id')
          .eq('follower_id', userId)
          .eq('status', 'accepted');
      return (followers: f1.length, following: f2.length);
    } catch (e) {
      debugPrint('SocialService.counts: $e');
      return (followers: 0, following: 0);
    }
  }

  /// IDs de las personas con las que el usuario tiene follow mutuo aceptado
  /// (puede darles like / comentar).
  Future<Set<String>> mutualFollowIds() async {
    final me = _uid;
    if (me == null) return {};
    try {
      final iFollow = await _sb
          .from('follows')
          .select('following_id')
          .eq('follower_id', me)
          .eq('status', 'accepted');
      final followMe = await _sb
          .from('follows')
          .select('follower_id')
          .eq('following_id', me)
          .eq('status', 'accepted');
      final a = iFollow.map((r) => r['following_id'] as String).toSet();
      final b = followMe.map((r) => r['follower_id'] as String).toSet();
      return a.intersection(b);
    } catch (e) {
      debugPrint('SocialService.mutualFollowIds: $e');
      return {};
    }
  }

  // ── Momentos (posts) ────────────────────────────────────────────────
  Future<List<Map<String, dynamic>>> feed({
    int limit = 20,
    DateTime? before,
  }) async {
    try {
      var q = _sb.from('posts').select(
          'id, user_id, image_url, caption, like_count, comment_count, created_at');
      if (before != null) {
        q = q.lt('created_at', before.toIso8601String());
      }
      final rows = await q.order('created_at', ascending: false).limit(limit);
      return _hydratePosts(rows);
    } catch (e) {
      debugPrint('SocialService.feed: $e');
      return [];
    }
  }

  Future<List<Map<String, dynamic>>> userPosts(String userId) async {
    try {
      final rows = await _sb
          .from('posts')
          .select(
              'id, user_id, image_url, caption, like_count, comment_count, created_at')
          .eq('user_id', userId)
          .order('created_at', ascending: false)
          .limit(90);
      return _hydratePosts(rows);
    } catch (e) {
      debugPrint('SocialService.userPosts: $e');
      return [];
    }
  }

  Future<List<Map<String, dynamic>>> _hydratePosts(List<dynamic> rows) async {
    if (rows.isEmpty) return [];
    final me = _uid;
    final list = rows.map((r) => Map<String, dynamic>.from(r)).toList();
    final userIds =
        list.map((r) => r['user_id'] as String).toSet().toList();
    final profs = await _profilesByIds(userIds);
    var myLikes = <String>{};
    if (me != null) {
      final ids = list.map((r) => r['id'] as String).toList();
      final likes = await _sb
          .from('post_likes')
          .select('post_id')
          .eq('user_id', me)
          .inFilter('post_id', ids);
      myLikes = likes.map((r) => r['post_id'] as String).toSet();
    }
    for (final r in list) {
      r['author'] = profs[r['user_id']] ?? {'id': r['user_id']};
      r['liked_by_me'] = myLikes.contains(r['id']);
    }
    return list;
  }

  /// Tope de momentos al día del plan gratis (Plus es ilimitado; lo obliga un
  /// trigger en la BD).
  static const freeDailyPostLimit = 2;

  /// Usa la hora del servidor (RPC), no la del dispositivo: adelantar el reloj
  /// del teléfono no cambia el resultado. El límite real igual lo impone un
  /// trigger en la BD.
  Future<int> myPostsToday() async {
    if (_uid == null) return 0;
    try {
      final r = await _sb.rpc('my_moments_today');
      return (r as num?)?.toInt() ?? 0;
    } catch (e) {
      debugPrint('SocialService.myPostsToday: $e');
      return 0;
    }
  }

  Future<Map<String, dynamic>?> createPost({
    required File image,
    String? caption,
  }) async {
    final me = _uid;
    if (me == null) return null;
    try {
      final path = '$me/${DateTime.now().millisecondsSinceEpoch}.jpg';
      await _sb.storage.from('post-images').upload(path, image);
      final url = _sb.storage.from('post-images').getPublicUrl(path);
      final trimmed = caption?.trim();
      final row = await _sb.from('posts').insert({
        'user_id': me,
        'image_url': url,
        'caption': (trimmed == null || trimmed.isEmpty) ? null : trimmed,
      }).select().single();
      return Map<String, dynamic>.from(row);
    } catch (e) {
      debugPrint('SocialService.createPost: $e');
      rethrow;
    }
  }

  Future<void> deletePost(String postId) async {
    try {
      await _sb.from('posts').delete().eq('id', postId);
    } catch (e) {
      debugPrint('SocialService.deletePost: $e');
    }
  }

  /// Alterna el like. Devuelve el nuevo estado. Lanza si la RLS lo rechaza
  /// (p. ej. dejaron de seguirse).
  Future<bool> toggleLike({
    required String postId,
    required String authorId,
    required bool currentlyLiked,
  }) async {
    final me = _uid;
    if (me == null) return currentlyLiked;
    if (currentlyLiked) {
      await _sb
          .from('post_likes')
          .delete()
          .eq('post_id', postId)
          .eq('user_id', me);
      return false;
    }
    await _sb.from('post_likes').insert({
      'post_id': postId,
      'user_id': me,
      'post_author_id': authorId,
    });
    return true;
  }

  Future<List<Map<String, dynamic>>> comments(String postId) async {
    try {
      final rows = await _sb
          .from('post_comments')
          .select(
              'id, user_id, body, created_at, parent_id, reply_to_user_id')
          .eq('post_id', postId)
          .order('created_at', ascending: true);
      final list = rows.map((r) => Map<String, dynamic>.from(r)).toList();
      if (list.isEmpty) return [];
      final ids = <String>{
        for (final r in list) ...[
          r['user_id'] as String,
          if (r['reply_to_user_id'] != null) r['reply_to_user_id'] as String,
        ]
      }.toList();
      final profs = await _profilesByIds(ids);
      for (final r in list) {
        r['author'] = profs[r['user_id']] ?? {'id': r['user_id']};
        if (r['reply_to_user_id'] != null) {
          r['reply_to'] = profs[r['reply_to_user_id']];
        }
      }
      return list;
    } catch (e) {
      debugPrint('SocialService.comments: $e');
      return [];
    }
  }

  Future<Map<String, dynamic>?> addComment({
    required String postId,
    required String authorId,
    required String body,
    String? parentId,
  }) async {
    final me = _uid;
    if (me == null) return null;
    final data = <String, dynamic>{
      'post_id': postId,
      'user_id': me,
      'post_author_id': authorId,
      'body': body.trim(),
    };
    if (parentId != null) data['parent_id'] = parentId;
    final row = await _sb
        .from('post_comments')
        .insert(data)
        .select('id, user_id, body, created_at, parent_id, reply_to_user_id')
        .single();
    return Map<String, dynamic>.from(row);
  }

  Future<void> deleteComment(String id) async {
    try {
      await _sb.from('post_comments').delete().eq('id', id);
    } catch (e) {
      debugPrint('SocialService.deleteComment: $e');
    }
  }
}

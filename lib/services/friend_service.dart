import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../models/user_model.dart';
import 'music_memory_cycle_service.dart';
import 'user_service.dart';

/// 友達 1 人分の表示データ。
class FriendEntry {
  final UserModel user;

  /// 現在の 15s Day（通知 〜 次の通知）に投稿済みか。
  /// true なら緑、false ならグレーのリングで表示する。
  final bool postedToday;

  const FriendEntry({required this.user, required this.postedToday});
}

/// 「知り合いかも」1 人分。
class FriendSuggestion {
  final UserModel user;

  /// 共通の友達の人数（0 なら別の理由で出している）。
  final int mutualCount;

  /// 同じ ADL 班に所属しているか。
  final bool sameAdlTeam;

  const FriendSuggestion({
    required this.user,
    required this.mutualCount,
    required this.sameAdlTeam,
  });

  /// カードに出す 1 行の理由。
  String get reason {
    if (mutualCount > 0) return '$mutualCount人の共通の友達';
    if (sameAdlTeam) return 'ADLメンバーかも';
    return '15sを使っています';
  }
}

/// 「友達」を扱うサービス。
///
/// # 友達の定義
/// **相互フォロー**（自分がフォローしていて、相手もフォローし返している）を
/// 友達とする。データは既存の `users.following` / `users.followers` をそのまま使い、
/// 専用のコレクションは持たない。
///
/// 片方向のフォローは「申請中」に相当し、友達一覧には出ない。
class FriendService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final UserService _userService = UserService();

  static const String _usersCollection = 'users';
  static const String _postsCollection = 'posts';

  /// 相互フォローになっている uid（＝友達）。
  static List<String> friendUidsOf(UserModel user) {
    final followers = user.followers.toSet();
    return user.following.where(followers.contains).toList();
  }

  /// 自分がフォローしているが、相手からは返ってきていない uid（申請中）。
  static List<String> pendingUidsOf(UserModel user) {
    final followers = user.followers.toSet();
    return user.following.where((u) => !followers.contains(u)).toList();
  }

  /// 友達一覧を「今日投稿したか」付きで返す。表示名の昇順。
  Future<List<FriendEntry>> loadFriends(String uid) async {
    try {
      final me = await _userService.getUser(uid);
      if (me == null) return const [];
      final friendUids = friendUidsOf(me);
      if (friendUids.isEmpty) return const [];

      final users = await _fetchUsers(friendUids);
      final postedUids = await _uidsPostedInCurrentCycle(friendUids);

      final entries = [
        for (final u in users)
          FriendEntry(user: u, postedToday: postedUids.contains(u.uid)),
      ];
      // 投稿済みを先に、その中で表示名順にする（緑が上に集まって見やすい）。
      entries.sort((a, b) {
        if (a.postedToday != b.postedToday) return a.postedToday ? -1 : 1;
        return _displayName(a.user)
            .toLowerCase()
            .compareTo(_displayName(b.user).toLowerCase());
      });
      return entries;
    } catch (e) {
      if (kDebugMode) print('FriendService.loadFriends error: $e');
      return const [];
    }
  }

  /// 「知り合いかも」候補。共通の友達が多い順、次に同じ ADL 班。
  Future<List<FriendSuggestion>> loadSuggestions(String uid,
      {int limit = 12}) async {
    try {
      final me = await _userService.getUser(uid);
      if (me == null) return const [];

      final friendUids = friendUidsOf(me);
      final exclude = <String>{uid, ...me.following, ...me.followers};

      // 友達の友達を数える（共通の友達の人数になる）。
      final mutual = <String, int>{};
      if (friendUids.isNotEmpty) {
        final friends = await _fetchUsers(friendUids);
        for (final f in friends) {
          for (final candidate in friendUidsOf(f)) {
            if (exclude.contains(candidate)) continue;
            mutual[candidate] = (mutual[candidate] ?? 0) + 1;
          }
        }
      }

      // 同じ ADL 班のメンバー。共通の友達が居ないときの補完に使う。
      final sameTeam = <String>{};
      final teamId = me.adlTeamId;
      if (teamId != null && teamId.isNotEmpty && mutual.length < limit) {
        try {
          final snap = await _firestore
              .collection(_usersCollection)
              .where('adlTeamId', isEqualTo: teamId)
              .limit(limit * 3)
              .get();
          for (final d in snap.docs) {
            if (exclude.contains(d.id) || d.id == teamId) continue;
            sameTeam.add(d.id);
          }
        } catch (_) {}
      }

      final candidates = <String>{...mutual.keys, ...sameTeam}.toList()
        ..sort((a, b) => (mutual[b] ?? 0).compareTo(mutual[a] ?? 0));
      final picked = candidates.take(limit).toList();
      if (picked.isEmpty) return const [];

      final users = await _fetchUsers(picked);
      final byUid = {for (final u in users) u.uid: u};
      return [
        for (final id in picked)
          if (byUid[id] != null)
            FriendSuggestion(
              user: byUid[id]!,
              mutualCount: mutual[id] ?? 0,
              sameAdlTeam: sameTeam.contains(id),
            ),
      ];
    } catch (e) {
      if (kDebugMode) print('FriendService.loadSuggestions error: $e');
      return const [];
    }
  }

  /// 友達申請（＝フォロー）。相手が既に自分をフォローしていれば即座に友達になる。
  Future<void> addFriend({
    required String currentUserId,
    required String targetUserId,
  }) {
    return _userService.followUser(
      currentUserId: currentUserId,
      targetUserId: targetUserId,
    );
  }

  /// 友達を解除（＝フォローを外す）。相互ではなくなるので相手の一覧からも消える。
  Future<void> removeFriend({
    required String currentUserId,
    required String targetUserId,
  }) {
    return _userService.unfollowUser(
      currentUserId: currentUserId,
      targetUserId: targetUserId,
    );
  }

  // ── 内部 ────────────────────────────────────────────────

  static String _displayName(UserModel u) =>
      (u.name?.isNotEmpty == true) ? u.name! : (u.username ?? '');

  /// uid 群のユーザーをまとめて取得する（whereIn は 30 件上限）。
  Future<List<UserModel>> _fetchUsers(List<String> uids) async {
    if (uids.isEmpty) return const [];
    final out = <UserModel>[];
    for (var i = 0; i < uids.length; i += 30) {
      final chunk = uids.skip(i).take(30).toList();
      try {
        final snap = await _firestore
            .collection(_usersCollection)
            .where(FieldPath.documentId, whereIn: chunk)
            .get();
        out.addAll(snap.docs.map(UserModel.fromFirestore));
      } catch (e) {
        if (kDebugMode) print('FriendService._fetchUsers chunk failed: $e');
      }
    }
    return out;
  }

  /// 現在の 15s Day に投稿したユーザーの uid 集合。
  /// タイムラインに載らない投稿（ダミー / Vibe ストーリー）は数えない。
  Future<Set<String>> _uidsPostedInCurrentCycle(List<String> uids) async {
    if (uids.isEmpty) return const {};
    final cutoff = MusicMemoryCycleService().currentCycleStart;
    final posted = <String>{};
    for (var i = 0; i < uids.length; i += 30) {
      final chunk = uids.skip(i).take(30).toList();
      try {
        final snap = await _firestore
            .collection(_postsCollection)
            .where('userId', whereIn: chunk)
            .where('createdAt', isGreaterThan: Timestamp.fromDate(cutoff))
            .get();
        for (final d in snap.docs) {
          final data = d.data();
          if (data['isDummyPost'] == true || data['isVibe'] == true) continue;
          final uid = data['userId'] as String?;
          if (uid != null) posted.add(uid);
        }
      } catch (e) {
        if (kDebugMode) print('FriendService._uidsPosted chunk failed: $e');
      }
    }
    return posted;
  }
}

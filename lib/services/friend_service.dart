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

  /// 共通の友達の人数。[FriendService.minMutualForSuggestion] 未満なら
  /// 共通の友達を理由には使わない。
  final int mutualCount;

  /// 自分と同じ人の招待コードで登録したか（＝招待者が同じ）。
  final bool sameInviter;

  /// 同じ ADL 班に所属しているか。
  final bool sameAdlTeam;

  const FriendSuggestion({
    required this.user,
    required this.mutualCount,
    required this.sameInviter,
    required this.sameAdlTeam,
  });

  /// カードに出す 1 行の理由。強い順に選ぶ。
  String get reason {
    if (mutualCount >= FriendService.minMutualForSuggestion) {
      return '$mutualCount人の共通の友達';
    }
    if (sameInviter) return '同じ人からの招待';
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
  /// [me] を渡すと自分のドキュメントを取り直さない。呼び出し側が既に
  /// 持っているときは渡すこと（同じ読み取りが 2 回走るのを避ける）。
  Future<List<FriendEntry>> loadFriends(String uid, {UserModel? me}) async {
    try {
      me ??= await _userService.getUser(uid);
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

  /// 共通の友達を「知り合いかも」の理由にする最小人数。
  /// 1 人だけだと精度が低く無関係な人が並ぶため 2 人以上にしている。
  static const int minMutualForSuggestion = 2;

  /// 「知り合いかも」候補。
  ///
  /// 採用する理由は次の 3 つ。強い順に並べる。
  ///  1. 共通の友達が [minMutualForSuggestion] 人以上
  ///  2. 自分と同じ人の招待コードで登録した（＝招待者が同じ）
  ///  3. 同じ ADL 班
  /// [me] については [loadFriends] と同じ。
  Future<List<FriendSuggestion>> loadSuggestions(String uid,
      {int limit = 12, UserModel? me}) async {
    try {
      me ??= await _userService.getUser(uid);
      if (me == null) return const [];

      final friendUids = friendUidsOf(me);
      final exclude = <String>{uid, ...me.following, ...me.followers};

      // ① 友達の友達を数える（その人数がそのまま共通の友達の数になる）。
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

      // ② 自分と同じ招待者から入った人。
      final sameInviter = await _sameInviterUids(uid, exclude);

      // ③ 同じ ADL 班。
      final sameTeam = <String>{};
      final teamId = me.adlTeamId;
      if (teamId != null && teamId.isNotEmpty) {
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

      final strongMutual = mutual.entries
          .where((e) => e.value >= minMutualForSuggestion)
          .map((e) => e.key)
          .toSet();

      // 並び順: 共通の友達が多い順 → 同じ招待者 → 同じ班。
      final candidates = <String>{...strongMutual, ...sameInviter, ...sameTeam}
          .toList()
        ..sort((a, b) {
          final m = (mutual[b] ?? 0).compareTo(mutual[a] ?? 0);
          if (m != 0) return m;
          final i = (sameInviter.contains(b) ? 1 : 0)
              .compareTo(sameInviter.contains(a) ? 1 : 0);
          return i;
        });

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
              sameInviter: sameInviter.contains(id),
              sameAdlTeam: sameTeam.contains(id),
            ),
      ];
    } catch (e) {
      if (kDebugMode) print('FriendService.loadSuggestions error: $e');
      return const [];
    }
  }

  /// 登録直後に出す「知り合いかも」。**同じ人の招待で入った人だけ**を返す。
  ///
  /// 登録直後は友達も ADL 班も無いので共通の友達では候補が作れない。
  /// 招待者が同じ人＝同じコミュニティから来た可能性が高いので、これだけを使う。
  Future<List<FriendSuggestion>> loadSameInviterSuggestions(String uid,
      {int limit = 20}) async {
    try {
      final me = await _userService.getUser(uid);
      if (me == null) return const [];
      final exclude = <String>{uid, ...me.following, ...me.followers};
      final uids = (await _sameInviterUids(uid, exclude)).take(limit).toList();
      if (uids.isEmpty) return const [];

      final users = await _fetchUsers(uids);
      users.sort((a, b) => _displayName(a)
          .toLowerCase()
          .compareTo(_displayName(b).toLowerCase()));
      return [
        for (final u in users)
          FriendSuggestion(
            user: u,
            mutualCount: 0,
            sameInviter: true,
            sameAdlTeam: false,
          ),
      ];
    } catch (e) {
      if (kDebugMode) print('FriendService.loadSameInviterSuggestions error: $e');
      return const [];
    }
  }

  /// 自分と同じ人の招待コードで登録したユーザー。

  ///
  /// `invite_usages` に「誰(ownerUid)の招待で誰(usedBy)が入ったか」が残っている。
  /// 自分の招待者を引き、その人が招待した他の人を兄弟として返す。
  Future<Set<String>> _sameInviterUids(String uid, Set<String> exclude) async {
    try {
      final mine = await _firestore
          .collection('invite_usages')
          .where('usedBy', isEqualTo: uid)
          .limit(1)
          .get();
      if (mine.docs.isEmpty) return const {};
      final ownerUid = mine.docs.first.data()['ownerUid'] as String?;
      if (ownerUid == null || ownerUid.isEmpty) return const {};

      final siblings = await _firestore
          .collection('invite_usages')
          .where('ownerUid', isEqualTo: ownerUid)
          .limit(50)
          .get();
      return {
        for (final d in siblings.docs)
          if (d.data()['usedBy'] is String) d.data()['usedBy'] as String,
      }..removeWhere(exclude.contains);
    } catch (e) {
      if (kDebugMode) print('FriendService._sameInviterUids error: $e');
      return const {};
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

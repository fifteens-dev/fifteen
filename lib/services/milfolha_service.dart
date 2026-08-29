import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../constants/milfolha_teams.dart';
import '../models/milfolha_team_score.dart';
import '../models/milfolha_team_model.dart';
import '../models/user_model.dart';

enum MilfolhaJoinResult {
  success,
  switched,
  alreadyJoined,
  invalidCode,
  disabled,
  error,
}

enum MilfolhaLeaveResult { success, notJoined, error }

/// Milfolha 対抗バトルイベントの参加・設定・集計サービス。
///
/// ADL とは独立。班アカウント/相互フォローは持たず、
/// `milfolha_memberships/{uid}` と `users.milfolhaTeamId` のみで所属を管理する。
class MilfolhaService {
  static const _configDoc = 'milfolha_config/current';
  final _db = FirebaseFirestore.instance;

  // ---- モード / 期間設定 ----

  Stream<bool> watchIsActive() {
    return _db.doc(_configDoc).snapshots().map((snap) {
      if (!snap.exists) return false;
      return (snap.data() as Map<String, dynamic>?)?['isActive'] == true;
    });
  }

  Future<bool> isActive() async {
    final snap = await _db.doc(_configDoc).get();
    return snap.exists && snap.data()?['isActive'] == true;
  }

  Future<void> setActive(bool active) async {
    await _db.doc(_configDoc).set({
      'isActive': active,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  /// イベント期間（8/30 0:00〜8/31 23:59 JST が既定）を取得。
  Future<MilfolhaPeriods> getPeriods() async {
    final snap = await _db.doc(_configDoc).get();
    return MilfolhaPeriods.fromMap(snap.data());
  }

  Stream<MilfolhaPeriods> watchPeriods() {
    return _db
        .doc(_configDoc)
        .snapshots()
        .map((snap) => MilfolhaPeriods.fromMap(snap.data()));
  }

  Future<void> setPeriods({DateTime? start, DateTime? end}) async {
    final map = <String, dynamic>{'updatedAt': FieldValue.serverTimestamp()};
    if (start != null) map['periodStart'] = Timestamp.fromDate(start);
    if (end != null) map['periodEnd'] = Timestamp.fromDate(end);
    await _db.doc(_configDoc).set(map, SetOptions(merge: true));
  }

  Stream<bool> watchResultFinalized() {
    return _db.doc(_configDoc).snapshots().map((snap) {
      if (!snap.exists) return false;
      return snap.data()?['resultFinalized'] == true;
    });
  }

  Future<bool> isResultFinalizedOnce() async {
    final snap = await _db.doc(_configDoc).get();
    return snap.exists && snap.data()?['resultFinalized'] == true;
  }

  Future<void> setResultFinalized(bool finalized) async {
    await _db.doc(_configDoc).set({
      'resultFinalized': finalized,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  // ---- ランキング非公開（ブラックアウト）----

  /// 非公開ウィンドウ設定を取得。
  Future<MilfolhaBlackout> getBlackout() async {
    final snap = await _db.doc(_configDoc).get();
    return MilfolhaBlackout.fromMap(snap.data());
  }

  Stream<MilfolhaBlackout> watchBlackout() {
    return _db
        .doc(_configDoc)
        .snapshots()
        .map((snap) => MilfolhaBlackout.fromMap(snap.data()));
  }

  /// 非公開ウィンドウを更新。null の項目は変更しない。
  Future<void> setBlackout({
    bool? enabled,
    DateTime? start,
    DateTime? end,
  }) async {
    final map = <String, dynamic>{'updatedAt': FieldValue.serverTimestamp()};
    if (enabled != null) map['blackoutEnabled'] = enabled;
    if (start != null) map['blackoutStart'] = Timestamp.fromDate(start);
    if (end != null) map['blackoutEnd'] = Timestamp.fromDate(end);
    await _db.doc(_configDoc).set(map, SetOptions(merge: true));
  }

  // ---- 参加 / 離脱 ----

  Future<Map<String, dynamic>?> getMembership(String uid) async {
    final snap = await _db.doc('milfolha_memberships/$uid').get();
    if (!snap.exists) return null;
    return snap.data();
  }

  Stream<Map<String, dynamic>?> watchMembership(String uid) {
    return _db
        .doc('milfolha_memberships/$uid')
        .snapshots()
        .map((snap) => snap.exists ? snap.data() : null);
  }

  /// チームコードで参加する（切替対応）。班アカウント（users/{teamId}）と相互フォロー同期。
  Future<MilfolhaJoinResult> joinTeamWithCode(String code) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return MilfolhaJoinResult.error;

    final teamId = MilfolhaTeamDefinitions.normalizeCode(code);
    if (teamId == null) return MilfolhaJoinResult.invalidCode;

    if (!await isActive()) return MilfolhaJoinResult.disabled;

    final membershipRef = _db.doc('milfolha_memberships/$uid');
    final userRef = _db.collection('users').doc(uid);
    final newTeamAccountRef = _db.collection('users').doc(teamId);

    try {
      return await _db.runTransaction<MilfolhaJoinResult>((tx) async {
        // ── 読み取り（書き込みより前） ──
        final memberSnap = await tx.get(membershipRef);
        final userSnap = await tx.get(userRef);

        String? oldTeamId;
        if (memberSnap.exists) {
          oldTeamId = memberSnap.data()?['teamId'] as String?;
          if (oldTeamId == teamId) return MilfolhaJoinResult.alreadyJoined;
        }

        // ユーザーの following/followers を Dart 側で計算（旧班を外し新班を追加）
        final userData = userSnap.data() ?? <String, dynamic>{};
        final following = ((userData['following'] as List?)
                    ?.whereType<String>()
                    .toList() ??
                <String>[])
            .toSet();
        final followers = ((userData['followers'] as List?)
                    ?.whereType<String>()
                    .toList() ??
                <String>[])
            .toSet();
        if (oldTeamId != null) {
          following.remove(oldTeamId);
          followers.remove(oldTeamId);
        }
        following.add(teamId);
        followers.add(teamId);

        // ── 書き込み ──
        // 1. 旧班から離脱（memberCount -1 + 相互フォロー解除）
        if (oldTeamId != null) {
          tx.set(_db.collection('milfolha_teams').doc(oldTeamId), {
            'memberCount': FieldValue.increment(-1),
          }, SetOptions(merge: true));
          tx.set(_db.collection('users').doc(oldTeamId), {
            'followers': FieldValue.arrayRemove([uid]),
            'following': FieldValue.arrayRemove([uid]),
            'updatedAt': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));
        }

        // 2. メンバーシップ登録（joinedAt は新規時のみ）
        final membershipData = <String, dynamic>{
          'userId': uid,
          'teamId': teamId,
          'updatedAt': FieldValue.serverTimestamp(),
        };
        if (!memberSnap.exists) {
          membershipData['joinedAt'] = FieldValue.serverTimestamp();
        }
        tx.set(membershipRef, membershipData, SetOptions(merge: true));

        // 3. 新班統計 memberCount +1
        tx.set(_db.collection('milfolha_teams').doc(teamId), {
          'memberCount': FieldValue.increment(1),
        }, SetOptions(merge: true));

        // 4. ユーザードキュメント更新（milfolhaTeamId + 相互フォロー配列）
        tx.set(userRef, {
          'milfolhaTeamId': teamId,
          'following': following.toList(),
          'followers': followers.toList(),
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));

        // 5. 新班アカウントへ自分を相互フォロー追加
        tx.set(newTeamAccountRef, {
          'followers': FieldValue.arrayUnion([uid]),
          'following': FieldValue.arrayUnion([uid]),
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));

        return oldTeamId != null
            ? MilfolhaJoinResult.switched
            : MilfolhaJoinResult.success;
      });
    } catch (_) {
      return MilfolhaJoinResult.error;
    }
  }

  Future<MilfolhaLeaveResult> leaveTeam() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return MilfolhaLeaveResult.error;

    final membershipRef = _db.doc('milfolha_memberships/$uid');
    final userRef = _db.collection('users').doc(uid);
    try {
      return await _db.runTransaction<MilfolhaLeaveResult>((tx) async {
        final memberSnap = await tx.get(membershipRef);
        if (!memberSnap.exists) return MilfolhaLeaveResult.notJoined;
        final teamId = memberSnap.data()?['teamId'] as String?;

        final userSnap = await tx.get(userRef);
        final userData = userSnap.data() ?? <String, dynamic>{};
        final following = ((userData['following'] as List?)
                    ?.whereType<String>()
                    .toList() ??
                <String>[])
            .toSet();
        final followers = ((userData['followers'] as List?)
                    ?.whereType<String>()
                    .toList() ??
                <String>[])
            .toSet();
        if (teamId != null) {
          following.remove(teamId);
          followers.remove(teamId);
        }

        tx.delete(membershipRef);
        if (teamId != null) {
          tx.set(_db.collection('milfolha_teams').doc(teamId), {
            'memberCount': FieldValue.increment(-1),
          }, SetOptions(merge: true));
          tx.set(_db.collection('users').doc(teamId), {
            'followers': FieldValue.arrayRemove([uid]),
            'following': FieldValue.arrayRemove([uid]),
            'updatedAt': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));
        }
        tx.set(userRef, {
          'milfolhaTeamId': FieldValue.delete(),
          'following': following.toList(),
          'followers': followers.toList(),
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));

        return MilfolhaLeaveResult.success;
      });
    } catch (_) {
      return MilfolhaLeaveResult.error;
    }
  }

  // ---- 班プロフィール ----

  /// 班統計/プロフィールを取得。
  Future<MilfolhaTeamModel?> getTeam(String teamId) async {
    final snap = await _db.collection('milfolha_teams').doc(teamId).get();
    if (!snap.exists) return null;
    return MilfolhaTeamModel.fromFirestore(snap);
  }

  /// 班プロフィール（アイコン/紹介文）を更新。班アカウント users/{teamId} にも同期。
  Future<void> updateTeamProfile({
    required String teamId,
    String? profileImageUrl,
    String? description,
  }) async {
    final teamUpdate = <String, dynamic>{};
    if (profileImageUrl != null) teamUpdate['profileImageUrl'] = profileImageUrl;
    if (description != null) teamUpdate['description'] = description;
    if (teamUpdate.isEmpty) return;

    final batch = _db.batch();
    batch.set(_db.collection('milfolha_teams').doc(teamId), teamUpdate,
        SetOptions(merge: true));
    final userUpdate = <String, dynamic>{};
    if (profileImageUrl != null) userUpdate['profileImageUrl'] = profileImageUrl;
    if (description != null) userUpdate['bio'] = description;
    batch.set(_db.collection('users').doc(teamId), userUpdate,
        SetOptions(merge: true));
    await batch.commit();
  }

  /// 班メンバー（milfolha_memberships で teamId 一致）の uid 一覧。
  Future<List<String>> getTeamMemberUids(String teamId) async {
    final snap = await _db
        .collection('milfolha_memberships')
        .where('teamId', isEqualTo: teamId)
        .get();
    return snap.docs.map((d) => d.id).toList();
  }

  /// 班メンバーを UserModel で返す。
  ///
  /// 所属の正は `milfolha_memberships`（ランキングのポイント集計と同じ基準）。
  /// ユーザー本体は `users` を milfolhaTeamId で 1 クエリ引いて突き合わせるので、
  /// 通常は uid ごとの get が発生しない（従来の N+1 read を解消）。
  /// milfolhaTeamId が欠けている等でクエリに載らなかった uid だけ個別に取得する。
  ///
  /// 読み取りに失敗した場合は**例外を投げる**（呼び出し側で再試行を出すため）。
  /// 「メンバー数」と「一覧」がズレないよう、両方この戻り値から数えること。
  Future<List<UserModel>> getTeamMembers(String teamId) async {
    // 班アカウント users/{teamId} 自身はメンバーではないので常に除外する。
    final memberUids = (await getTeamMemberUids(teamId))
        .where((uid) => uid != teamId)
        .toSet();
    if (memberUids.isEmpty) return const [];

    final resolved = <String, UserModel>{};

    final byTeamField = await _db
        .collection('users')
        .where('milfolhaTeamId', isEqualTo: teamId)
        .get();
    for (final doc in byTeamField.docs) {
      if (!memberUids.contains(doc.id)) continue;
      resolved[doc.id] = UserModel.fromFirestore(doc);
    }

    // 取りこぼした uid のみ個別 get。ドキュメントが本当に無い場合だけ諦める。
    final missing =
        memberUids.where((uid) => !resolved.containsKey(uid)).toList();
    if (missing.isNotEmpty) {
      final snaps = await Future.wait(
        missing.map((uid) => _db.collection('users').doc(uid).get()),
      );
      for (final snap in snaps) {
        if (snap.exists) resolved[snap.id] = UserModel.fromFirestore(snap);
      }
    }

    // 参加順ではなく uid 順だと不安定なので表示名で安定ソートする。
    final members = resolved.values.toList()
      ..sort((a, b) {
        final an = (a.name?.isNotEmpty == true ? a.name! : (a.username ?? ''));
        final bn = (b.name?.isNotEmpty == true ? b.name! : (b.username ?? ''));
        return an.toLowerCase().compareTo(bn.toLowerCase());
      });
    return members;
  }

  // ---- 集計（クライアント計算） ----

  /// JST(UTC+9) の暦日キー "yyyy-MM-dd" を返す。1日1投稿の日境界に使う。
  static String _jstDayKey(DateTime dt) {
    final j = dt.toUtc().add(const Duration(hours: 9));
    return '${j.year}-${j.month.toString().padLeft(2, '0')}-${j.day.toString().padLeft(2, '0')}';
  }

  /// チーム別のみが欲しい呼び出し元用（管理タブ等）。
  Future<List<MilfolhaTeamScore>> computeTeamRanking() async {
    final r = await computeRanking();
    return r.teams;
  }

  /// ランキングを集計する。期間の全 posts / 全 memberships / 期間の invite_usages を
  /// 読み、メモリ上でチーム別＋個人別のポイントを計算して返す。
  Future<MilfolhaRankingResult> computeRanking() async {
    final periods = await getPeriods();
    final start = periods.start;
    final end = periods.end;

    // ── 1) メンバーシップ（uid → teamId, joinedAt） ──
    final memberSnap = await _db.collection('milfolha_memberships').get();
    final uidToTeam = <String, String>{};
    final joinedAt = <String, DateTime?>{};
    for (final d in memberSnap.docs) {
      final data = d.data();
      final teamId = data['teamId'] as String?;
      if (teamId == null) continue;
      uidToTeam[d.id] = teamId;
      joinedAt[d.id] = (data['joinedAt'] as Timestamp?)?.toDate();
    }
    final memberUids = uidToTeam.keys.toSet();

    // ── 2) 期間内の投稿（1クエリ） ──
    final postSnap = await _db
        .collection('posts')
        .where('createdAt', isGreaterThanOrEqualTo: Timestamp.fromDate(start))
        .where('createdAt', isLessThanOrEqualTo: Timestamp.fromDate(end))
        .get();
    // uid → 投稿日(JST)の集合
    final postDaysByUid = <String, Set<String>>{};
    for (final d in postSnap.docs) {
      final data = d.data();
      final uid = data['userId'] as String?;
      final ts = (data['createdAt'] as Timestamp?)?.toDate();
      if (uid == null || ts == null) continue;
      (postDaysByUid[uid] ??= <String>{}).add(_jstDayKey(ts));
    }

    // ── 3) 期間内の招待記録（外部ユーザーの帰属） ──
    final usageSnap = await _db
        .collection('invite_usages')
        .where('usedAt', isGreaterThanOrEqualTo: Timestamp.fromDate(start))
        .where('usedAt', isLessThanOrEqualTo: Timestamp.fromDate(end))
        .get();
    // 外部ユーザー(usedBy) → (最古 usedAt, 招待者チーム / 招待者uid)
    final extEarliest = <String, DateTime>{};
    final extToTeam = <String, String>{};
    final extToOwner = <String, String>{};
    for (final d in usageSnap.docs) {
      final data = d.data();
      final owner = data['ownerUid'] as String?;
      final invited = data['usedBy'] as String?;
      final ts = (data['usedAt'] as Timestamp?)?.toDate();
      if (owner == null || invited == null || ts == null) continue;
      // 招待者がメンバー、被招待者が外部(メンバーでない)のみ対象
      if (!memberUids.contains(owner)) continue;
      if (memberUids.contains(invited)) continue;
      final team = uidToTeam[owner];
      if (team == null) continue;
      final prev = extEarliest[invited];
      if (prev == null || ts.isBefore(prev)) {
        extEarliest[invited] = ts;
        extToTeam[invited] = team; // 最初に招待したメンバーのチームへ帰属
        extToOwner[invited] = owner; // 個人ポイント帰属用
      }
    }

    // ── 4) チーム別ポイント集計 ＋ 個人別ポイント ──
    final reg = <String, int>{};
    final memberPost = <String, int>{};
    final extReg = <String, int>{};
    final extPost = <String, int>{};
    final memberCount = <String, int>{};
    final individual = <String, int>{}; // uid → 個人貢献ポイント

    // メンバー登録 +1（期間中に参加した人）＋ メンバー投稿 +3/日
    for (final entry in uidToTeam.entries) {
      final uid = entry.key;
      final team = entry.value;
      memberCount[team] = (memberCount[team] ?? 0) + 1;
      final jat = joinedAt[uid];
      if (jat != null && !jat.isBefore(start) && !jat.isAfter(end)) {
        reg[team] = (reg[team] ?? 0) + 1;
        individual[uid] = (individual[uid] ?? 0) + 1;
      }
      final days = postDaysByUid[uid];
      if (days != null && days.isNotEmpty) {
        memberPost[team] = (memberPost[team] ?? 0) + days.length * 3;
        individual[uid] = (individual[uid] ?? 0) + days.length * 3;
      }
    }

    // 外部登録 +3 ＋ 外部投稿 +5/日（チーム＝最古招待者のチーム、個人＝最古招待者）
    for (final entry in extToTeam.entries) {
      final ext = entry.key;
      final team = entry.value;
      final owner = extToOwner[ext];
      extReg[team] = (extReg[team] ?? 0) + 3;
      if (owner != null) individual[owner] = (individual[owner] ?? 0) + 3;
      final days = postDaysByUid[ext];
      if (days != null && days.isNotEmpty) {
        extPost[team] = (extPost[team] ?? 0) + days.length * 5;
        if (owner != null) {
          individual[owner] = (individual[owner] ?? 0) + days.length * 5;
        }
      }
    }

    // ── 5) 全チーム（定義順）をスコア化して降順ソート ──
    final scores = [
      for (final def in MilfolhaTeamDefinitions.all)
        MilfolhaTeamScore(
          teamId: def.id,
          displayName: def.displayName,
          regPt: reg[def.id] ?? 0,
          memberPostPt: memberPost[def.id] ?? 0,
          extRegPt: extReg[def.id] ?? 0,
          extPostPt: extPost[def.id] ?? 0,
          memberCount: memberCount[def.id] ?? 0,
        ),
    ]..sort((a, b) => b.total.compareTo(a.total));

    return MilfolhaRankingResult(
      teams: scores,
      individualPoints: individual,
      individualRank: _rankMap(individual),
    );
  }

  /// uid→ポイント を、ポイント降順の順位(1始まり)に変換。同点は同順位。
  static Map<String, int> _rankMap(Map<String, int> points) {
    final entries = points.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final rank = <String, int>{};
    int lastPt = -1;
    int lastRank = 0;
    for (int i = 0; i < entries.length; i++) {
      final e = entries[i];
      if (e.value != lastPt) {
        lastRank = i + 1;
        lastPt = e.value;
      }
      rank[e.key] = lastRank;
    }
    return rank;
  }
}

/// 集計結果（チーム＋個人）。
class MilfolhaRankingResult {
  final List<MilfolhaTeamScore> teams;

  /// uid → 個人貢献ポイント。
  final Map<String, int> individualPoints;

  /// uid → 個人ポイント順位（1始まり・同点同順位）。
  final Map<String, int> individualRank;

  const MilfolhaRankingResult({
    required this.teams,
    required this.individualPoints,
    required this.individualRank,
  });
}

/// Milfolha イベント期間。未設定時は 2026-08-30 0:00〜2026-08-31 23:59 JST を既定とする。
class MilfolhaPeriods {
  final DateTime start;
  final DateTime end;

  const MilfolhaPeriods({required this.start, required this.end});

  /// JST の日時を UTC の DateTime として保持するためのヘルパ。
  /// （Firestore Timestamp は UTC 基準。JST 8/30 0:00 = UTC 8/29 15:00）
  static DateTime _jst(int y, int mo, int d, int h, int mi) =>
      DateTime.utc(y, mo, d, h, mi).subtract(const Duration(hours: 9));

  static MilfolhaPeriods get defaults => MilfolhaPeriods(
        start: _jst(2026, 8, 30, 0, 0),
        end: _jst(2026, 8, 31, 21, 20),
      );

  factory MilfolhaPeriods.fromMap(Map<String, dynamic>? data) {
    if (data == null) return defaults;
    final s = (data['periodStart'] as Timestamp?)?.toDate();
    final e = (data['periodEnd'] as Timestamp?)?.toDate();
    return MilfolhaPeriods(
      start: s ?? defaults.start,
      end: e ?? defaults.end,
    );
  }
}

/// ランキングの非公開（ブラックアウト）ウィンドウ。
///
/// ポイント計算・投稿の集計には一切影響しない。ユーザー向けランキング画面の
/// 表示だけを止めるための設定で、管理パネルから時刻変更と即時公開ができる。
class MilfolhaBlackout {
  final bool enabled;
  final DateTime start;
  final DateTime end;

  const MilfolhaBlackout({
    required this.enabled,
    required this.start,
    required this.end,
  });

  /// JST の日時を UTC の DateTime として保持するためのヘルパ。
  static DateTime _jst(int y, int mo, int d, int h, int mi) =>
      DateTime.utc(y, mo, d, h, mi).subtract(const Duration(hours: 9));

  /// 既定は 8/31 18:20〜21:30 JST（集計終了 21:20 の 10 分後に公開）。
  static MilfolhaBlackout get defaults => MilfolhaBlackout(
        enabled: true,
        start: _jst(2026, 8, 31, 18, 20),
        end: _jst(2026, 8, 31, 21, 30),
      );

  factory MilfolhaBlackout.fromMap(Map<String, dynamic>? data) {
    if (data == null) return defaults;
    final s = (data['blackoutStart'] as Timestamp?)?.toDate();
    final e = (data['blackoutEnd'] as Timestamp?)?.toDate();
    final en = data['blackoutEnabled'];
    return MilfolhaBlackout(
      // 明示的に false が入っているときだけ無効。未設定は既定どおり有効。
      enabled: en is bool ? en : defaults.enabled,
      start: s ?? defaults.start,
      end: e ?? defaults.end,
    );
  }

  /// [now] がウィンドウ内か（開始以上・終了未満）。
  bool isHiddenAt(DateTime now) {
    if (!enabled) return false;
    if (!end.isAfter(start)) return false;
    final t = now.toUtc();
    return !t.isBefore(start.toUtc()) && t.isBefore(end.toUtc());
  }

  /// 公開までの残り時間。非公開中でなければ null。
  Duration? remainingAt(DateTime now) {
    if (!isHiddenAt(now)) return null;
    return end.toUtc().difference(now.toUtc());
  }
}

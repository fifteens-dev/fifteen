import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../constants/milfolha_teams.dart';
import '../models/milfolha_team_score.dart';

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

  /// チームコードで参加する（切替対応）。班アカウント連携なし。
  Future<MilfolhaJoinResult> joinTeamWithCode(String code) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return MilfolhaJoinResult.error;

    final teamId = MilfolhaTeamDefinitions.normalizeCode(code);
    if (teamId == null) return MilfolhaJoinResult.invalidCode;

    if (!await isActive()) return MilfolhaJoinResult.disabled;

    final membershipRef = _db.doc('milfolha_memberships/$uid');
    final userRef = _db.collection('users').doc(uid);

    try {
      final existing = await membershipRef.get();
      final oldTeamId =
          existing.exists ? (existing.data()?['teamId'] as String?) : null;
      if (oldTeamId == teamId) return MilfolhaJoinResult.alreadyJoined;

      final membershipData = <String, dynamic>{
        'userId': uid,
        'teamId': teamId,
        'updatedAt': FieldValue.serverTimestamp(),
      };
      // 既存があれば joinedAt を維持、無ければ現在時刻を記録（登録+1判定用）。
      if (!existing.exists) {
        membershipData['joinedAt'] = FieldValue.serverTimestamp();
      }

      final batch = _db.batch();
      batch.set(membershipRef, membershipData, SetOptions(merge: true));
      batch.set(userRef, {
        'milfolhaTeamId': teamId,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      await batch.commit();

      return oldTeamId != null
          ? MilfolhaJoinResult.switched
          : MilfolhaJoinResult.success;
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
      final existing = await membershipRef.get();
      if (!existing.exists) return MilfolhaLeaveResult.notJoined;

      final batch = _db.batch();
      batch.delete(membershipRef);
      batch.set(userRef, {
        'milfolhaTeamId': FieldValue.delete(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      await batch.commit();
      return MilfolhaLeaveResult.success;
    } catch (_) {
      return MilfolhaLeaveResult.error;
    }
  }

  // ---- 集計（クライアント計算） ----

  /// JST(UTC+9) の暦日キー "yyyy-MM-dd" を返す。1日1投稿の日境界に使う。
  static String _jstDayKey(DateTime dt) {
    final j = dt.toUtc().add(const Duration(hours: 9));
    return '${j.year}-${j.month.toString().padLeft(2, '0')}-${j.day.toString().padLeft(2, '0')}';
  }

  /// ランキングを集計する。期間の全 posts / 全 memberships / 期間の invite_usages を
  /// 読み、メモリ上でポイントを計算して降順で返す。
  Future<List<MilfolhaTeamScore>> computeRanking() async {
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
    // 外部ユーザー(usedBy) → (最古 usedAt, 招待者チーム)
    final extEarliest = <String, DateTime>{};
    final extToTeam = <String, String>{};
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
      }
    }

    // ── 4) チーム別ポイント集計 ──
    final reg = <String, int>{};
    final memberPost = <String, int>{};
    final extReg = <String, int>{};
    final extPost = <String, int>{};
    final memberCount = <String, int>{};

    // メンバー登録 +1（期間中に参加した人）＋ メンバー投稿 +3/日
    for (final entry in uidToTeam.entries) {
      final uid = entry.key;
      final team = entry.value;
      memberCount[team] = (memberCount[team] ?? 0) + 1;
      final jat = joinedAt[uid];
      if (jat != null &&
          !jat.isBefore(start) &&
          !jat.isAfter(end)) {
        reg[team] = (reg[team] ?? 0) + 1;
      }
      final days = postDaysByUid[uid];
      if (days != null && days.isNotEmpty) {
        memberPost[team] = (memberPost[team] ?? 0) + days.length * 3;
      }
    }

    // 外部登録 +3 ＋ 外部投稿 +5/日
    for (final entry in extToTeam.entries) {
      final ext = entry.key;
      final team = entry.value;
      extReg[team] = (extReg[team] ?? 0) + 3;
      final days = postDaysByUid[ext];
      if (days != null && days.isNotEmpty) {
        extPost[team] = (extPost[team] ?? 0) + days.length * 5;
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
    return scores;
  }
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
        end: _jst(2026, 8, 31, 23, 59),
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

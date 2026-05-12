import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/adl_event_model.dart';
import '../models/adl_team_model.dart';

enum AdlJoinResult { success, invalidCode, expired, alreadyJoined, error }

class AdlService {
  static const _configDoc = 'adl_config/current';
  final _db = FirebaseFirestore.instance;

  // ---- ADLモード ----

  /// ADLモードが有効かどうかをリアルタイム監視
  Stream<bool> watchAdlMode() {
    return _db.doc(_configDoc).snapshots().map((snap) {
      if (!snap.exists) return false;
      return (snap.data() as Map<String, dynamic>?)?['isActive'] == true;
    });
  }

  Future<bool> isAdlModeActive() async {
    final snap = await _db.doc(_configDoc).get();
    if (!snap.exists) return false;
    return (snap.data() as Map<String, dynamic>?)?['isActive'] == true;
  }

  Future<String?> getActiveEventId() async {
    final snap = await _db.doc(_configDoc).get();
    if (!snap.exists) return null;
    final data = snap.data() as Map<String, dynamic>?;
    if (data?['isActive'] != true) return null;
    return data?['eventId'] as String?;
  }

  // ---- イベント管理（管理者用）----

  Future<AdlEventModel> createEvent({
    required String name,
    required DateTime startTime,
    required Duration inviteCodeDuration, // 最大4時間
  }) async {
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    final clampedDuration = inviteCodeDuration.inMinutes > 240
        ? const Duration(hours: 4)
        : inviteCodeDuration;

    final ref = _db.collection('adl_events').doc();
    final event = AdlEventModel(
      eventId: ref.id,
      name: name,
      isActive: false,
      startTime: startTime,
      inviteCodeExpiresAt: startTime.add(clampedDuration),
      createdAt: DateTime.now(),
      createdBy: uid,
    );
    await ref.set(event.toMap());
    return event;
  }

  Future<void> activateEvent(String eventId) async {
    final batch = _db.batch();
    // 既存のアクティブイベントを非アクティブ化
    final existing = await _db
        .collection('adl_events')
        .where('isActive', isEqualTo: true)
        .get();
    for (final doc in existing.docs) {
      batch.update(doc.reference, {'isActive': false});
    }
    // 対象イベントをアクティブ化
    batch.update(_db.collection('adl_events').doc(eventId), {'isActive': true});
    // グローバル設定を更新
    batch.set(_db.doc(_configDoc), {
      'isActive': true,
      'eventId': eventId,
      'updatedAt': FieldValue.serverTimestamp(),
    });
    await batch.commit();
  }

  Future<void> deactivateAdlMode() async {
    final eventId = await getActiveEventId();
    final batch = _db.batch();
    if (eventId != null) {
      batch.update(
          _db.collection('adl_events').doc(eventId), {'isActive': false});
    }
    batch.set(_db.doc(_configDoc), {
      'isActive': false,
      'eventId': null,
      'updatedAt': FieldValue.serverTimestamp(),
    });
    await batch.commit();
  }

  Future<List<AdlEventModel>> getEvents() async {
    final snap = await _db
        .collection('adl_events')
        .orderBy('createdAt', descending: true)
        .limit(20)
        .get();
    return snap.docs.map(AdlEventModel.fromFirestore).toList();
  }

  Future<AdlEventModel?> getActiveEvent() async {
    final snap = await _db
        .collection('adl_events')
        .where('isActive', isEqualTo: true)
        .limit(1)
        .get();
    if (snap.docs.isEmpty) return null;
    return AdlEventModel.fromFirestore(snap.docs.first);
  }

  // ---- チーム管理（管理者用）----

  Future<AdlTeamModel> createTeam({
    required String eventId,
    required String name,
    required DateTime inviteCodeExpiresAt,
  }) async {
    final code = _generateCode();
    final ref = _db.collection('adl_teams').doc();
    final team = AdlTeamModel(
      teamId: ref.id,
      eventId: eventId,
      name: name,
      inviteCode: code,
      inviteCodeExpiresAt: inviteCodeExpiresAt,
      createdAt: DateTime.now(),
    );
    await ref.set(team.toMap());
    return team;
  }

  Future<void> regenerateInviteCode(
      String teamId, DateTime newExpiry) async {
    await _db.collection('adl_teams').doc(teamId).update({
      'inviteCode': _generateCode(),
      'inviteCodeExpiresAt': Timestamp.fromDate(newExpiry),
    });
  }

  Future<void> deleteTeam(String teamId) async {
    await _db.collection('adl_teams').doc(teamId).delete();
  }

  Stream<List<AdlTeamModel>> watchTeams(String eventId) {
    return _db
        .collection('adl_teams')
        .where('eventId', isEqualTo: eventId)
        .orderBy('likeCount', descending: true)
        .snapshots()
        .map((s) => s.docs.map(AdlTeamModel.fromFirestore).toList());
  }

  // ---- 招待コード・メンバー参加（ユーザー用）----

  Future<AdlJoinResult> joinTeamWithCode(String code) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return AdlJoinResult.error;

    try {
      // 既に参加済みか確認
      final memberSnap = await _db.doc('adl_memberships/$uid').get();
      if (memberSnap.exists) return AdlJoinResult.alreadyJoined;

      // コードでチームを検索
      final teamSnap = await _db
          .collection('adl_teams')
          .where('inviteCode', isEqualTo: code.toUpperCase().trim())
          .limit(1)
          .get();

      if (teamSnap.docs.isEmpty) return AdlJoinResult.invalidCode;

      final team = AdlTeamModel.fromFirestore(teamSnap.docs.first);

      // 有効期限確認
      if (!team.isInviteCodeValid) return AdlJoinResult.expired;

      // メンバー登録（トランザクション）
      await _db.runTransaction((tx) async {
        tx.set(_db.doc('adl_memberships/$uid'), {
          'userId': uid,
          'teamId': team.teamId,
          'teamName': team.name,
          'eventId': team.eventId,
          'joinedAt': FieldValue.serverTimestamp(),
        });
        tx.update(_db.collection('adl_teams').doc(team.teamId),
            {'memberCount': FieldValue.increment(1)});
        tx.update(_db.collection('users').doc(uid), {
          'adlTeamId': team.teamId,
          'adlTeamName': team.name,
          'adlEventId': team.eventId,
        });
      });

      return AdlJoinResult.success;
    } catch (_) {
      return AdlJoinResult.error;
    }
  }

  Future<Map<String, dynamic>?> getCurrentMembership(String uid) async {
    final snap = await _db.doc('adl_memberships/$uid').get();
    if (!snap.exists) return null;
    return snap.data() as Map<String, dynamic>;
  }

  Stream<Map<String, dynamic>?> watchMembership(String uid) {
    return _db.doc('adl_memberships/$uid').snapshots().map((snap) {
      if (!snap.exists) return null;
      return snap.data() as Map<String, dynamic>;
    });
  }

  // ---- ランキング ----

  Stream<List<AdlTeamModel>> watchRanking(String eventId) => watchTeams(eventId);

  // ---- ユーティリティ ----

  String _generateCode() {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final rng = Random.secure();
    return List.generate(6, (_) => chars[rng.nextInt(chars.length)]).join();
  }
}

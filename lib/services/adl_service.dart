import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../constants/adl_teams.dart';
import '../models/adl_event_model.dart';
import '../models/adl_team_model.dart';

enum AdlJoinResult {
  success,
  switched,
  alreadyJoined,
  invalidCode,
  notSeeded,
  error,
}

enum AdlLeaveResult { success, notJoined, error }

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

  /// 任意の班を手動作成する（旧API・現在は固定9班のシード推奨）
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

  /// 固定9班を likeCount 降順で監視する。
  Stream<List<AdlTeamModel>> watchFixedTeams() {
    final ids = AdlTeamDefinitions.all.map((t) => t.id).toList();
    return _db
        .collection('adl_teams')
        .where(FieldPath.documentId, whereIn: ids)
        .snapshots()
        .map((s) {
      final teams = s.docs.map(AdlTeamModel.fromFirestore).toList()
        ..sort((a, b) => b.likeCount.compareTo(a.likeCount));
      return teams;
    });
  }

  // ---- 招待コード・メンバー参加（ユーザー用）----

  /// 固定9班のいずれかの招待コードで参加する。
  ///
  /// - 既に同じ班に所属していれば [AdlJoinResult.alreadyJoined]
  /// - 別の班に所属していれば自動的に切替（[AdlJoinResult.switched]）
  /// - 班アカウントとの相互フォローを自動同期
  Future<AdlJoinResult> joinTeamWithCode(String code) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return AdlJoinResult.error;

    final teamId = AdlTeamDefinitions.normalizeCode(code);
    if (teamId == null) return AdlJoinResult.invalidCode;

    final newTeamRef = _db.collection('adl_teams').doc(teamId);
    final newTeamAccountRef = _db.collection('users').doc(teamId);
    final membershipRef = _db.doc('adl_memberships/$uid');
    final userRef = _db.collection('users').doc(uid);

    // 班統計の事前取得（トランザクション内では再読み込みされる）
    final teamSnap = await newTeamRef.get();
    if (!teamSnap.exists) return AdlJoinResult.notSeeded;

    bool alreadyInSameTeam = false;
    String? oldTeamId;

    try {
      await _db.runTransaction((tx) async {
        // ── 読み取り（必ず書き込みより前） ──
        final memberSnap = await tx.get(membershipRef);
        final userSnap = await tx.get(userRef);
        final freshTeamSnap = await tx.get(newTeamRef);
        if (!freshTeamSnap.exists) {
          throw Exception('team document missing');
        }
        final team = AdlTeamModel.fromFirestore(freshTeamSnap);

        if (memberSnap.exists) {
          oldTeamId = memberSnap.data()?['teamId'] as String?;
          if (oldTeamId == teamId) {
            alreadyInSameTeam = true;
            return;
          }
        }

        // ユーザーのフォロー配列を Dart 側で計算
        // （arrayUnion と arrayRemove を同一フィールドに同時適用できないため）
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

        // 1. 旧班から離脱（あれば）
        if (oldTeamId != null) {
          tx.update(_db.collection('adl_teams').doc(oldTeamId!), {
            'memberCount': FieldValue.increment(-1),
          });
          tx.update(_db.collection('users').doc(oldTeamId!), {
            'followers': FieldValue.arrayRemove([uid]),
            'following': FieldValue.arrayRemove([uid]),
            'updatedAt': FieldValue.serverTimestamp(),
          });
        }

        // 2. メンバーシップ登録（set: 切替時は上書き、新規時は作成）
        tx.set(membershipRef, {
          'userId': uid,
          'teamId': teamId,
          'teamName': team.name,
          'eventId': team.eventId,
          'joinedAt': FieldValue.serverTimestamp(),
        });

        // 3. 新班統計 +1
        tx.update(newTeamRef, {
          'memberCount': FieldValue.increment(1),
        });

        // 4. ユーザードキュメント更新（adlTeam系 + 相互フォロー配列）
        tx.update(userRef, {
          'adlTeamId': teamId,
          'adlTeamName': team.name,
          'adlEventId': team.eventId,
          'following': following.toList(),
          'followers': followers.toList(),
          'updatedAt': FieldValue.serverTimestamp(),
        });

        // 5. 新班アカウントへ自分を相互フォロー追加
        tx.update(newTeamAccountRef, {
          'followers': FieldValue.arrayUnion([uid]),
          'following': FieldValue.arrayUnion([uid]),
          'updatedAt': FieldValue.serverTimestamp(),
        });
      });

      if (alreadyInSameTeam) return AdlJoinResult.alreadyJoined;
      return oldTeamId != null
          ? AdlJoinResult.switched
          : AdlJoinResult.success;
    } catch (_) {
      return AdlJoinResult.error;
    }
  }

  /// 現在所属している班から離脱する。
  /// 班アカウントとの相互フォローも自動解除。
  Future<AdlLeaveResult> leaveTeam() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return AdlLeaveResult.error;

    final membershipRef = _db.doc('adl_memberships/$uid');
    final userRef = _db.collection('users').doc(uid);

    bool wasJoined = false;

    try {
      await _db.runTransaction((tx) async {
        // ── 読み取り ──
        final memberSnap = await tx.get(membershipRef);
        if (!memberSnap.exists) {
          wasJoined = false;
          return;
        }
        wasJoined = true;
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

        // ── 書き込み ──

        // メンバーシップ削除
        tx.delete(membershipRef);

        if (teamId != null) {
          // 班統計 -1
          tx.update(_db.collection('adl_teams').doc(teamId), {
            'memberCount': FieldValue.increment(-1),
          });

          // 班アカウントから自分を相互フォロー解除
          tx.update(_db.collection('users').doc(teamId), {
            'followers': FieldValue.arrayRemove([uid]),
            'following': FieldValue.arrayRemove([uid]),
            'updatedAt': FieldValue.serverTimestamp(),
          });
        }

        // ユーザードキュメント更新
        tx.update(userRef, {
          'adlTeamId': null,
          'adlTeamName': null,
          'adlEventId': null,
          'following': following.toList(),
          'followers': followers.toList(),
          'updatedAt': FieldValue.serverTimestamp(),
        });
      });

      return wasJoined ? AdlLeaveResult.success : AdlLeaveResult.notJoined;
    } catch (_) {
      return AdlLeaveResult.error;
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

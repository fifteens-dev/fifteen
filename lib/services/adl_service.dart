import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../constants/adl_teams.dart';
import '../models/adl_event_model.dart';
import '../models/adl_periods.dart';
import '../models/adl_team_model.dart';

enum AdlJoinResult {
  success,
  switched,
  alreadyJoined,
  invalidCode,
  notSeeded,
  disabled,
  error,
}

enum AdlLeaveResult { success, notJoined, error }

/// 招待人数ランキングの1エントリ
class InviteRankingEntry {
  final String uid;
  final String name;
  final String username;
  final String? profileImageUrl;
  final int inviteCount;

  const InviteRankingEntry({
    required this.uid,
    required this.name,
    required this.username,
    required this.profileImageUrl,
    required this.inviteCount,
  });

  String get displayName =>
      name.isNotEmpty ? name : (username.isNotEmpty ? username : '名前未設定');
}

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

  // ADLモード値の短期キャッシュ（複数画面からの重複読み取りを抑止）。
  // TTL は短めにして管理者の切替が反映されないリスクを抑える。
  static bool? _cachedAdlActive;
  static DateTime? _cachedAdlActiveAt;
  static const _adlModeCacheTtl = Duration(seconds: 30);

  Future<bool> isAdlModeActive({bool useCache = true}) async {
    if (useCache &&
        _cachedAdlActive != null &&
        _cachedAdlActiveAt != null &&
        DateTime.now().difference(_cachedAdlActiveAt!) < _adlModeCacheTtl) {
      return _cachedAdlActive!;
    }
    final snap = await _db.doc(_configDoc).get();
    final active = snap.exists && snap.data()?['isActive'] == true;
    _cachedAdlActive = active;
    _cachedAdlActiveAt = DateTime.now();
    return active;
  }

  /// ADLモードのキャッシュを破棄（管理者切替時など）
  static void invalidateAdlModeCache() {
    _cachedAdlActive = null;
    _cachedAdlActiveAt = null;
  }

  Future<String?> getActiveEventId() async {
    final snap = await _db.doc(_configDoc).get();
    if (!snap.exists) return null;
    final data = snap.data() as Map<String, dynamic>?;
    if (data?['isActive'] != true) return null;
    return data?['eventId'] as String?;
  }

  /// 現在のユーザーが「ADL専用コンテンツの対象」かを判定する。
  /// ADLモードがONで、かつユーザーが班に所属しているときだけ true。
  Future<bool> isCurrentUserAdlParticipant() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return false;
    final active = await isAdlModeActive();
    if (!active) return false;
    final member = await getCurrentMembership(uid);
    return member != null;
  }

  // ---- 期間設定 ----

  /// adl_config/current から期間設定を取得（リアルタイム監視）
  Stream<AdlPeriods> watchAdlPeriods() {
    return _db.doc(_configDoc).snapshots().map((snap) {
      if (!snap.exists) return const AdlPeriods();
      return AdlPeriods.fromMap(snap.data());
    });
  }

  Future<AdlPeriods> getAdlPeriods() async {
    final snap = await _db.doc(_configDoc).get();
    if (!snap.exists) return const AdlPeriods();
    return AdlPeriods.fromMap(snap.data());
  }

  /// 期間設定を更新する（部分更新）
  Future<void> setAdlPeriods(AdlPeriods periods) async {
    final map = periods.toPartialMap();
    if (map.isEmpty) return;
    map['updatedAt'] = FieldValue.serverTimestamp();
    await _db.doc(_configDoc).set(map, SetOptions(merge: true));
  }

  // ---- 結果確定 ----

  /// 結果確定フラグをリアルタイム監視する。
  /// 計画書の 6/27（結果連絡日）に管理者が確定すると true になり、
  /// ユーザー側ランキング画面が「最終結果」モードに切り替わる。
  Stream<bool> watchResultFinalized() {
    return _db.doc(_configDoc).snapshots().map((snap) {
      if (!snap.exists) return false;
      return snap.data()?['resultFinalized'] == true;
    });
  }

  Future<bool> isResultFinalized() async {
    final snap = await _db.doc(_configDoc).get();
    if (!snap.exists) return false;
    return snap.data()?['resultFinalized'] == true;
  }

  Future<void> setResultFinalized(bool finalized) async {
    await _db.doc(_configDoc).set({
      'resultFinalized': finalized,
      'resultFinalizedAt':
          finalized ? FieldValue.serverTimestamp() : null,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  // ---- イベント管理（管理者用）----

  Future<AdlEventModel> createEvent({
    required String name,
    required DateTime startTime,
  }) async {
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    final ref = _db.collection('adl_events').doc();
    final event = AdlEventModel(
      eventId: ref.id,
      name: name,
      isActive: false,
      startTime: startTime,
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

  /// ADLモードのON/OFFを直接切り替える（イベント不要）。
  /// 固定9班での運用に使う。
  Future<void> setAdlMode(bool isActive) async {
    await _db.doc(_configDoc).set({
      'isActive': isActive,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    // 切替が即座に反映されるようキャッシュを破棄
    invalidateAdlModeCache();
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

  Future<void> deleteTeam(String teamId) async {
    await _db.collection('adl_teams').doc(teamId).delete();
  }

  /// 班プロフィールを更新（画像URL・紹介文）。Firestore ルールにより admin のみ書き込み可。
  /// 同時に `users/{teamId}` の班アカウントドキュメントも同期更新する。
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
    batch.update(_db.collection('adl_teams').doc(teamId), teamUpdate);
    // users/{teamId} の班アカウントにも反映（投稿カード等のアイコン表示で利用）
    final userUpdate = <String, dynamic>{};
    if (profileImageUrl != null) userUpdate['profileImageUrl'] = profileImageUrl;
    if (description != null) userUpdate['bio'] = description;
    if (userUpdate.isNotEmpty) {
      batch.set(_db.collection('users').doc(teamId), userUpdate, SetOptions(merge: true));
    }
    await batch.commit();
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

    // 管理者パネルでADLモードがONになっていない間は参加不可
    final modeActive = await isAdlModeActive();
    if (!modeActive) return AdlJoinResult.disabled;

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

  // ---- 個人賞ランキング（招待人数） ----

  /// 招待人数ランキングを集計する。
  ///
  /// invite_usages を期間でクエリ → ownerUid ごとに件数を数え、上位N名を返す。
  /// ADL個人賞（期間中の新規ユーザー招待人数）の集計に使う。
  ///
  /// - [from] / [to] は省略可。指定すれば usedAt の範囲で絞る。
  /// - [limit] は返却件数の上限。
  ///
  /// 集計対象が大規模になるとクライアント集計が重くなる点に注意。
  /// ADL本番想定の最大スケール（300人 × 平均数招待）では十分軽い。
  Future<List<InviteRankingEntry>> getInviteRanking({
    DateTime? from,
    DateTime? to,
    int limit = 20,
  }) async {
    Query<Map<String, dynamic>> q = _db.collection('invite_usages');
    if (from != null) {
      q = q.where('usedAt', isGreaterThanOrEqualTo: Timestamp.fromDate(from));
    }
    if (to != null) {
      q = q.where('usedAt', isLessThan: Timestamp.fromDate(to));
    }
    final snap = await q.get();

    // ownerUid ごとに件数集計
    final counts = <String, int>{};
    for (final doc in snap.docs) {
      final owner = doc.data()['ownerUid'] as String?;
      if (owner == null || owner.isEmpty) continue;
      counts[owner] = (counts[owner] ?? 0) + 1;
    }
    if (counts.isEmpty) return const [];

    // ADL班所属チェック: 招待者全員のユーザードキュメントを取得し
    // adlTeamId が設定されているユーザーのみを集計対象にする
    final allUids = counts.keys.toList();
    final userDocs = await Future.wait(
      allUids.map((uid) => _db.collection('users').doc(uid).get()),
    );
    final uidToDoc = {for (final doc in userDocs) doc.id: doc};

    final adlCounts = <String, int>{};
    for (final doc in userDocs) {
      if (!doc.exists) continue;
      final teamId = doc.data()?['adlTeamId'];
      if (teamId == null || (teamId as String).isEmpty) continue;
      adlCounts[doc.id] = counts[doc.id]!;
    }
    if (adlCounts.isEmpty) return const [];

    // 件数降順で上位N
    final sortedUids = adlCounts.keys.toList()
      ..sort((a, b) => adlCounts[b]!.compareTo(adlCounts[a]!));
    final topUids = sortedUids.take(limit).toList();

    return [
      for (final uid in topUids)
        if (uidToDoc[uid]?.exists == true)
          InviteRankingEntry(
            uid: uid,
            name: (uidToDoc[uid]!.data()?['name'] as String?) ?? '',
            username: (uidToDoc[uid]!.data()?['username'] as String?) ?? '',
            profileImageUrl: uidToDoc[uid]!.data()?['profileImageUrl'] as String?,
            inviteCount: adlCounts[uid] ?? 0,
          )
    ];
  }

  // ---- 再集計（管理者用） ----

  /// adlRecomputeLikeCounts Cloud Function を呼び出し、
  /// posts コレクション全走査で各班の likeCount/postCount を再計算する。
  /// 戻り値: {teamId: {likeCount, postCount}}
  Future<Map<String, Map<String, int>>> recomputeLikeCounts() async {
    final result = await FirebaseFunctions.instance
        .httpsCallable('adlRecomputeLikeCounts')
        .call();
    final data = result.data as Map<dynamic, dynamic>;
    final totals = (data['totals'] as Map<dynamic, dynamic>?) ?? const {};
    return totals.map((teamId, value) {
      final m = value as Map<dynamic, dynamic>;
      return MapEntry(teamId.toString(), {
        'likeCount': (m['likeCount'] as num?)?.toInt() ?? 0,
        'postCount': (m['postCount'] as num?)?.toInt() ?? 0,
      });
    });
  }

  /// recomputeVibeTopicPostCounts Cloud Function を呼び出し、
  /// posts コレクションを走査して vibe_topics.postCount を再集計する。
  /// 戻り値: {topicCount, nonZeroCount}
  Future<Map<String, int>> recomputeVibeTopicPostCounts() async {
    final result = await FirebaseFunctions.instance
        .httpsCallable('recomputeVibeTopicPostCounts')
        .call();
    final data = result.data as Map<dynamic, dynamic>;
    return {
      'topicCount': (data['topicCount'] as num?)?.toInt() ?? 0,
      'nonZeroCount': (data['nonZeroCount'] as num?)?.toInt() ?? 0,
    };
  }

  /// adlRecomputeMemberCounts Cloud Function を呼び出し、
  /// users.adlTeamId を全走査して各班の memberCount を再集計する。
  /// 戻り値: {teamId: count}
  Future<Map<String, int>> recomputeMemberCounts() async {
    final result = await FirebaseFunctions.instance
        .httpsCallable('adlRecomputeMemberCounts')
        .call();
    final data = result.data as Map<dynamic, dynamic>;
    final counts = (data['counts'] as Map<dynamic, dynamic>?) ?? const {};
    return counts.map(
      (k, v) => MapEntry(k.toString(), (v as num?)?.toInt() ?? 0),
    );
  }

  // ---- プレテスト用: 大量ダミーユーザー ----

  /// 600人のダミーユーザーを9班に均等配分して作成する。
  /// 戻り値: {createdCount, distribution: [{teamId, count}]}
  Future<Map<String, dynamic>> createBulkDummyUsers({int count = 600}) async {
    final result = await FirebaseFunctions.instance
        .httpsCallable('createBulkDummyUsers')
        .call({'count': count});
    return Map<String, dynamic>.from(result.data as Map);
  }

  /// createBulkDummyUsers で作成したダミーユーザーと投稿を全削除する。
  /// Auth アカウント・テストフォローも連鎖削除する。
  /// 戻り値: {deletedUsers, deletedPosts, followsRemoved, authDeleted}
  Future<Map<String, dynamic>> cleanupBulkDummyUsers() async {
    final result = await FirebaseFunctions.instance
        .httpsCallable('cleanupBulkDummyUsers')
        .call();
    return Map<String, dynamic>.from(result.data as Map);
  }

  /// 600人のダミーユーザーに Firebase Auth アカウントを付与する。
  /// 戻り値: {created, skipped, failed, total}
  Future<Map<String, dynamic>> createBulkDummyAuthAccounts() async {
    final result = await FirebaseFunctions.instance
        .httpsCallable('createBulkDummyAuthAccounts')
        .call();
    return Map<String, dynamic>.from(result.data as Map);
  }

  /// バルクダミーユーザーの Auth アカウントを削除する。
  /// 戻り値: {deleted, failed}
  Future<Map<String, dynamic>> cleanupBulkDummyAuthAccounts() async {
    final result = await FirebaseFunctions.instance
        .httpsCallable('cleanupBulkDummyAuthAccounts')
        .call();
    return Map<String, dynamic>.from(result.data as Map);
  }

  /// 指定ユーザー（省略時は自分）が全ダミーを双方向フォローする。
  /// 通知暴発検証・実機タイムライン表示確認用。
  Future<Map<String, dynamic>> setupTestFollows({
    String? targetUid,
    int? count,
    bool bidirectional = true,
  }) async {
    final args = <String, dynamic>{'bidirectional': bidirectional};
    if (targetUid != null) args['targetUid'] = targetUid;
    if (count != null) args['count'] = count;
    final result = await FirebaseFunctions.instance
        .httpsCallable('setupTestFollows')
        .call(args);
    return Map<String, dynamic>.from(result.data as Map);
  }

  /// setupTestFollows で設定したフォローを解除する。
  Future<Map<String, dynamic>> cleanupTestFollows() async {
    final result = await FirebaseFunctions.instance
        .httpsCallable('cleanupTestFollows')
        .call();
    return Map<String, dynamic>.from(result.data as Map);
  }

  /// 既存バルクダミーユーザーの不足フィールド（uid, name, bio, savedPosts）を補完する。
  Future<Map<String, dynamic>> fixBulkDummyUserFields() async {
    final result = await FirebaseFunctions.instance
        .httpsCallable('fixBulkDummyUserFields')
        .call();
    return Map<String, dynamic>.from(result.data as Map);
  }

  /// 既存ダミー投稿の isDummyPost フラグを外し、タイムラインに表示されるようにする。
  Future<Map<String, dynamic>> unflagBulkDummyPosts() async {
    final result = await FirebaseFunctions.instance
        .httpsCallable('unflagBulkDummyPosts')
        .call();
    return Map<String, dynamic>.from(result.data as Map);
  }

}

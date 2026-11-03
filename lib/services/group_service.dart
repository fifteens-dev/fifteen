import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';

import '../models/group_model.dart';
import '../models/post_model.dart';
import '../models/user_model.dart';
import '../utils/app_log.dart';
import 'music_memory_cycle_service.dart';
import 'post_photo_service.dart';

/// グループ 1 つ分の「今のサイクル」の状況。ホームのグループ枠に出す。
class GroupCycleStatus {
  final GroupModel group;

  /// 今のサイクルに投稿したメンバーの投稿（uid → 最新の 1 件）。
  final Map<String, PostModel> postsByMember;

  /// 写真を付けた投稿の写真（postId → URL）。カメラマークと裏面に使う。
  final Map<String, String> photoUrls;

  Set<String> get postIdsWithPhoto => photoUrls.keys.toSet();

  const GroupCycleStatus({
    required this.group,
    required this.postsByMember,
    this.photoUrls = const {},
  });

  int get memberCount => group.memberIds.length;
  int get postedCount => postsByMember.length;
}

/// グループを扱うサービス。
///
/// 作成・招待の画面はまだ無い（別途作成）。それまではテスト用に管理者
/// パネルから [createGroup] / [deleteGroup] を呼ぶ。
class GroupService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  static const String _groupsCollection = 'groups';
  static const String _postsCollection = 'posts';
  static const String _usersCollection = 'users';

  /// 自分が入っているグループ。作った順（古い順）。
  ///
  /// orderBy を付けると複合インデックスが要るので、並べ替えは手元で行う。
  Stream<List<GroupModel>> watchMyGroups(String uid) {
    return _firestore
        .collection(_groupsCollection)
        .where('memberIds', arrayContains: uid)
        .snapshots()
        .map((snap) {
      final groups = snap.docs.map(GroupModel.fromFirestore).toList()
        ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
      return groups;
    });
  }

  /// 自分と同じグループにいる人の uid（自分は除く、重複なし）。
  ///
  /// ウィジェットや他人のプロフィールの「見せてよい相手か」に使う。
  Future<Set<String>> groupmateUids(String uid) async {
    final snap = await _firestore
        .collection(_groupsCollection)
        .where('memberIds', arrayContains: uid)
        .get();
    return {
      for (final d in snap.docs) ...GroupModel.fromFirestore(d).memberIds,
    }..remove(uid);
  }

  /// [uid] と [otherUid] が同じグループにいるか。
  Future<bool> isGroupmate(String uid, String otherUid) async {
    if (uid == otherUid) return true;
    final snap = await _firestore
        .collection(_groupsCollection)
        .where('memberIds', arrayContains: uid)
        .get();
    return snap.docs.any((d) =>
        (d.data()['memberIds'] as List? ?? const []).contains(otherUid));
  }

  /// uid 群のユーザーをまとめて取得する（whereIn は 30 件上限）。
  Future<List<UserModel>> fetchUsers(Iterable<String> uids) async {
    final list = uids.toList();
    final out = <UserModel>[];
    for (var i = 0; i < list.length; i += 30) {
      final chunk = list.skip(i).take(30).toList();
      try {
        final snap = await _firestore
            .collection(_usersCollection)
            .where(FieldPath.documentId, whereIn: chunk)
            .get();
        out.addAll(snap.docs.map(UserModel.fromFirestore));
      } catch (e) {
        if (kDebugMode) {
          AppLog.debug('GroupService.fetchUsers chunk failed: $e');
        }
      }
    }
    return out;
  }

  /// グループを作る。[memberIds] に [ownerId] が無ければ足す。
  /// [GroupModel.maxMembers] 人を超えると [ArgumentError]。
  Future<String> createGroup({
    required String name,
    required String ownerId,
    required List<String> memberIds,
  }) async {
    final members = {ownerId, ...memberIds}.toList();
    if (members.length > GroupModel.maxMembers) {
      throw ArgumentError('グループは${GroupModel.maxMembers}人までです');
    }
    final ref = await _firestore.collection(_groupsCollection).add({
      'name': name,
      'ownerId': ownerId,
      'memberIds': members,
      // アイコンは既定のイラストからランダム。あとから設定で変えられる。
      'iconIndex': _random.nextInt(GroupModel.iconCount),
      'inviteCode': newInviteCode(),
      'joinClosed': false,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    return ref.id;
  }

  static bool _peersRefreshed = false;

  /// 同じグループの人の一覧（group_peers）をサーバーで作り直してもらう。
  /// 写真を見せる相手の判定に使う。アプリを開いて最初の 1 回だけ呼ぶ。
  Future<void> refreshMyPeersOnce() async {
    if (_peersRefreshed) return;
    _peersRefreshed = true;
    try {
      await FirebaseFunctions.instance
          .httpsCallable('refreshMyGroupPeers')
          .call<void>();
    } catch (e) {
      _peersRefreshed = false;
      AppLog.debug('GroupService.refreshMyPeersOnce failed: $e');
    }
  }

  /// グループを作る（ホームの＋→「グループを作成」）。作った人だけのグループ。
  /// 名前は必須（空ならサーバーが断る）。
  Future<({String groupId, String name, String inviteCode})> createMyGroup(
      String name) async {
    final res = await FirebaseFunctions.instance
        .httpsCallable('createGroup')
        .call({'name': name});
    final data = Map<String, dynamic>.from(res.data as Map);
    return (
      groupId: data['groupId'] as String,
      name: data['name'] as String,
      inviteCode: data['inviteCode'] as String,
    );
  }

  /// 招待コードで参加する。締め切り・10 人・コード違いはサーバーが弾き、
  /// [GroupJoinException] の message にそのまま出せる文言が入る。
  Future<({String groupId, String name, bool alreadyMember})> joinByCode(
      String code) async {
    try {
      final res = await FirebaseFunctions.instance
          .httpsCallable('joinGroupByCode')
          .call({'code': code.trim().toLowerCase()});
      final data = Map<String, dynamic>.from(res.data as Map);
      return (
        groupId: data['groupId'] as String,
        name: (data['name'] as String?) ?? '',
        alreadyMember: data['alreadyMember'] == true,
      );
    } on FirebaseFunctionsException catch (e) {
      throw GroupJoinException(e.message ?? '参加できませんでした');
    }
  }

  /// 友達（どこかのグループで一緒の人）のうち、[group] にまだいない人。
  Future<List<UserModel>> fetchFriendsNotIn(GroupModel group, String uid) async {
    final snap = await _firestore
        .collection(_groupsCollection)
        .where('memberIds', arrayContains: uid)
        .get();
    final ids = <String>{
      for (final d in snap.docs) ...GroupModel.fromFirestore(d).memberIds,
    }
      ..remove(uid)
      ..removeAll(group.memberIds);
    final users = await fetchUsers(ids);
    users.sort((a, b) => (a.name ?? a.username ?? '')
        .compareTo(b.name ?? b.username ?? ''));
    return users;
  }

  /// 友達をグループに追加する。追加された人は確認なしで参加になる。
  /// 断られたら [GroupJoinException] の message にそのまま出せる文言が入る。
  Future<int> addMembers(String groupId, List<String> uids) async {
    try {
      final res = await FirebaseFunctions.instance
          .httpsCallable('addGroupMembers')
          .call({'groupId': groupId, 'uids': uids});
      final data = Map<String, dynamic>.from(res.data as Map);
      return (data['added'] as List?)?.length ?? 0;
    } on FirebaseFunctionsException catch (e) {
      throw GroupJoinException(e.message ?? '追加できませんでした');
    }
  }

  /// 招待リンク（QR にもこれを入れる）。開くと Web からアプリへ渡る。
  static String inviteUrl(String code) =>
      'https://fifteens-39cfe.web.app/g/$code';

    static final Random _random = Random.secure();

  /// 招待コード（6 桁、小文字英字と数字）。紛らわしい 0/o/1/l は使わない。
  static String newInviteCode() {
    const chars = 'abcdefghijkmnpqrstuvwxyz23456789';
    return List.generate(6, (_) => chars[_random.nextInt(chars.length)]).join();
  }

  /// 1 グループを購読する（グループ画面・設定）。消えたら null。
  Stream<GroupModel?> watchGroup(String groupId) => _firestore
      .collection(_groupsCollection)
      .doc(groupId)
      .snapshots()
      .map((d) => d.exists ? GroupModel.fromFirestore(d) : null);

  /// 設定を変える。メンバーなら誰でも変えられる（ルールで許可している項目だけ）。
  Future<void> updateSettings(
    String groupId, {
    String? name,
    int? iconIndex,
    bool? joinClosed,
    String? inviteCode,
  }) {
    return _firestore.collection(_groupsCollection).doc(groupId).update({
      if (name != null) 'name': name,
      if (iconIndex != null) 'iconIndex': iconIndex,
      if (joinClosed != null) 'joinClosed': joinClosed,
      if (inviteCode != null) 'inviteCode': inviteCode,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  /// このグループの通知を受け取るか（自分のぶんだけ）。
  Future<void> setNotificationsEnabled(String groupId, String uid, bool on) {
    return _firestore.collection(_groupsCollection).doc(groupId).update({
      'mutedMemberIds':
          on ? FieldValue.arrayRemove([uid]) : FieldValue.arrayUnion([uid]),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  /// グループを抜ける。最後の 1 人ならグループごと消す。
  ///
  /// 抜けた人の投稿は posts にそのまま残る（Music Memory・プレイリスト用）。
  Future<void> leaveGroup(String groupId, String uid) {
    final ref = _firestore.collection(_groupsCollection).doc(groupId);
    return _firestore.runTransaction((tx) async {
      final snap = await tx.get(ref);
      if (!snap.exists) return;
      final members =
          List<String>.from(snap.data()?['memberIds'] as List? ?? const []);
      if (!members.contains(uid)) return;
      if (members.length <= 1) {
        tx.delete(ref);
      } else {
        tx.update(ref, {
          'memberIds': FieldValue.arrayRemove([uid]),
          'mutedMemberIds': FieldValue.arrayRemove([uid]),
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }
    });
  }

  Future<void> deleteGroup(String groupId) =>
      _firestore.collection(_groupsCollection).doc(groupId).delete();

  /// 自分の今のサイクルの投稿（無ければ null）。リアクションが付くたびに流れる。
  ///
  /// ホームの「投稿前 / 投稿後」の切り替えと、今日の 1 曲のカードに使う。
  /// サイクルの境目は購読を始めた時点のもの。21:00 をまたいだら呼び直すこと。
  Stream<PostModel?> watchMyCyclePost(String uid) {
    final cutoff = MusicMemoryCycleService().currentCycleStart;
    return _firestore
        .collection(_postsCollection)
        .where('userId', isEqualTo: uid)
        .where('createdAt', isGreaterThan: Timestamp.fromDate(cutoff))
        .snapshots()
        .map((snap) {
      PostModel? latest;
      for (final d in snap.docs) {
        final data = d.data();
        if (data['isDummyPost'] == true || data['isVibe'] == true) continue;
        final post = PostModel.fromFirestore(d);
        if (latest == null || post.createdAt.isAfter(latest.createdAt)) {
          latest = post;
        }
      }
      return latest;
    });
  }

  /// 今のサイクル（直近の 21:00 以降）に各メンバーが投稿したか。
  ///
  /// タイムラインに載らない投稿（ダミー / Vibe）は数えない。同じ人が
  /// 複数あれば新しい方を採る。
  Future<GroupCycleStatus> loadCycleStatus(GroupModel group) async {
    final cutoff = MusicMemoryCycleService().currentCycleStart;
    final posts = <String, PostModel>{};
    final uids = group.memberIds;
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
          final post = PostModel.fromFirestore(d);
          final prev = posts[post.userId];
          if (prev == null || post.createdAt.isAfter(prev.createdAt)) {
            posts[post.userId] = post;
          }
        }
      } catch (e) {
        if (kDebugMode) {
          AppLog.debug('GroupService.loadCycleStatus chunk failed: $e');
        }
      }
    }
    // 写真は post_photos にある。hasPhoto を書く前の投稿もあるので、
    // 旗に頼らず投稿ごとに引く（多くて 10 件）。
    final photos = <String, String>{};
    await Future.wait([
      for (final p in posts.values)
        PostPhotoService.instance.photoUrl(p.postId).then((url) {
          if (url != null) photos[p.postId] = url;
        }),
    ]);
    return GroupCycleStatus(
      group: group,
      postsByMember: posts,
      photoUrls: photos,
    );
  }
}

/// 招待コードで参加できなかった理由（そのまま画面に出せる文言）。
class GroupJoinException implements Exception {
  final String message;
  const GroupJoinException(this.message);
  @override
  String toString() => message;
}

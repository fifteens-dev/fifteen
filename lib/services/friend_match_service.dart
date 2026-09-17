import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../models/user_model.dart';
import '../screens/friend_match_screen.dart';
import 'friend_service.dart';

/// 「最初の N 人と友達になった」瞬間を検出して、お祝いアニメーションを出す。
///
/// ## なぜ「追加した直後」だけでは足りないか
/// このアプリの友達は相互フォロー（[FriendService.friendUidsOf]）で成立する。
/// 自分が「追加」を押した時点ではまだ片思いで、相手が追加し返してはじめて
/// 友達になる。つまり成立の瞬間はアプリを開いていないときにも来る。
///
/// そこで「祝った相手の uid」を Firestore に残し、**今の友達との差分**で
/// 判定する。これなら追加直後・相手の承認後・別端末、どの経路で成立しても、
/// 次にアプリを開いたときに 1 回だけ出せる。
///
/// ## 既存ユーザーを誤って祝わないための初期化
/// [_field] がまだ無いユーザーは、初回に今の友達を全員「祝い済み」として
/// 書き込むだけで何も出さない。お祝いはこの機能が入ったあとに増えた友達から
/// 始まる。序数も祝い済みの人数から数えるので、すでに 5 人友達がいる人の
/// 次の友達は 6 人目＝対象外になる。
class FriendMatchService {
  FriendMatchService._();
  static final FriendMatchService instance = FriendMatchService._();

  /// 何人目までお祝いするか。
  static const int celebrateUntil = 3;

  static const String _collection = 'users';
  static const String _field = 'friendMatchCelebrated';

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// 多重表示の防止。アニメーション中に別の経路から呼ばれても無視する。
  bool _showing = false;

  /// 友達成立が溜まっていればお祝い画面を出す。
  ///
  /// 条件を満たさないときは何もしないので、呼び出し側は結果を気にせず
  /// 「友達を追加したあと」「アプリを開いたとき」などに素朴に呼べばよい。
  Future<void> maybeCelebrate(BuildContext context) async {
    if (_showing) return;
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    _Pending? pending;
    try {
      pending = await _consumePending(uid);
    } catch (e) {
      if (kDebugMode) print('FriendMatchService.maybeCelebrate error: $e');
      return;
    }
    if (pending == null || !context.mounted) return;

    _showing = true;
    try {
      await FriendMatchScreen.show(
        context,
        meImageUrl: pending.me.profileImageUrl,
        meName: _displayName(pending.me),
        friendImageUrl: pending.friend.profileImageUrl,
        friendName: _displayName(pending.friend),
        ordinal: pending.ordinal,
      );
    } finally {
      _showing = false;
    }
  }

  /// 未お祝いの友達が居れば 1 件返し、その相手を「祝い済み」として記録する。
  ///
  /// 返す前に記録を済ませているので、表示に失敗しても同じ相手で二度は出ない
  /// （取りこぼす可能性は許容する。二重に出るより害が小さい）。
  Future<_Pending?> _consumePending(String uid) async {
    final doc = _firestore.collection(_collection).doc(uid);
    final snap = await doc.get();
    if (!snap.exists) return null;

    final me = UserModel.fromFirestore(snap);
    final friendUids = FriendService.friendUidsOf(me);

    final raw = snap.data()?[_field];
    // フィールドが無い＝この機能を一度も通っていないユーザー。
    if (raw is! List) {
      await doc.update({_field: friendUids});
      return null;
    }

    final celebrated = <String>{
      for (final v in raw)
        if (v is String) v,
    };
    final pending = friendUids.where((u) => !celebrated.contains(u)).toList();
    if (pending.isEmpty) return null;

    // 対象外（4 人目以降）でも記録だけは進める。そうしないと友達が増えるたびに
    // 差分が残り続け、毎回ここまで読みに来ることになる。
    if (celebrated.length >= celebrateUntil) {
      await doc.update({_field: FieldValue.arrayUnion(pending)});
      return null;
    }

    final targetUid = pending.first;
    await doc.update({
      _field: FieldValue.arrayUnion([targetUid]),
    });

    final friendSnap =
        await _firestore.collection(_collection).doc(targetUid).get();
    // 退会済みなどで引けない相手は記録だけ進めて出さない。
    if (!friendSnap.exists) return null;

    return _Pending(
      me: me,
      friend: UserModel.fromFirestore(friendSnap),
      ordinal: celebrated.length + 1,
    );
  }

  static String _displayName(UserModel u) =>
      (u.name?.isNotEmpty == true) ? u.name! : (u.username ?? 'ユーザー');
}

/// お祝い 1 件分の材料。
class _Pending {
  final UserModel me;
  final UserModel friend;
  final int ordinal;

  const _Pending({
    required this.me,
    required this.friend,
    required this.ordinal,
  });
}

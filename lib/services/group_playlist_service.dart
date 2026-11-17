import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../models/group_model.dart';
import '../models/group_playlist.dart';
import '../utils/app_log.dart';

/// グループの最新のプレイリストと、自分が見た時刻。
class GroupPlaylistEntry {
  final GroupModel group;
  final GroupPlaylist playlist;

  /// 自分が初めて開いた時刻。まだなら null。
  final DateTime? viewedAt;

  const GroupPlaylistEntry({
    required this.group,
    required this.playlist,
    required this.viewedAt,
  });

  bool get viewed => viewedAt != null;

  /// ホームの上に出すか。
  ///
  /// - 見ていなければ、次の週と入れ替わる（届いて 7 日後の 21:00）まで。
  /// - 見たら、見た日の翌日の 21:00 まで（輪はグレー）。
  bool showOnHome(DateTime now) {
    if (!now.isBefore(playlist.replacedAt)) return false;
    final v = viewedAt;
    if (v == null) return true;
    final until = DateTime(v.year, v.month, v.day + 1, 21);
    return now.isBefore(until);
  }
}

/// 週のプレイリスト（Functions の weeklyGroupPlaylists が作る）を読む。
class GroupPlaylistService {
  GroupPlaylistService._();
  static final GroupPlaylistService instance = GroupPlaylistService._();

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> _playlists(String groupId) =>
      _firestore.collection('groups').doc(groupId).collection('playlists');

  /// グループの最新のプレイリスト（まだ 1 つも無ければ null）。
  ///
  /// グループ画面には、次の週のものが届くまでこれを出し続ける。
  Stream<GroupPlaylist?> watchLatest(String groupId) => _playlists(groupId)
          .orderBy('weekKey', descending: true)
          .limit(1)
          .snapshots()
          .map((snap) => snap.docs.isEmpty
              ? null
              : GroupPlaylist.fromFirestore(groupId, snap.docs.first))
          .handleError((Object e) {
        if (kDebugMode) AppLog.debug('GroupPlaylistService.watchLatest: $e');
      });

  /// 自分がそのプレイリストを見た時刻（まだなら null）。
  Stream<DateTime?> watchViewedAt(String groupId, String weekKey, String uid) =>
      _playlists(groupId)
          .doc(weekKey)
          .collection('views')
          .doc(uid)
          .snapshots()
          .map((d) {
        final v = d.data()?['viewedAt'];
        // 書いた直後は serverTimestamp が未確定なので、今を見た時刻とみなす。
        if (d.exists && v == null) return DateTime.now();
        return v is Timestamp ? v.toDate() : null;
      }).handleError((Object e) {
        if (kDebugMode) AppLog.debug('GroupPlaylistService.watchViewedAt: $e');
      });

  /// 最新のプレイリストと見た時刻をまとめて流す。
  Stream<GroupPlaylistEntry?> watchEntry(GroupModel group, String uid) {
    late StreamController<GroupPlaylistEntry?> controller;
    StreamSubscription<GroupPlaylist?>? latestSub;
    StreamSubscription<DateTime?>? viewSub;
    controller = StreamController<GroupPlaylistEntry?>(
      onListen: () {
        latestSub = watchLatest(group.groupId).listen((playlist) {
          viewSub?.cancel();
          if (playlist == null) {
            controller.add(null);
            return;
          }
          viewSub = watchViewedAt(group.groupId, playlist.weekKey, uid).listen(
            (viewedAt) => controller.add(GroupPlaylistEntry(
              group: group,
              playlist: playlist,
              viewedAt: viewedAt,
            )),
          );
        });
      },
      onCancel: () async {
        await viewSub?.cancel();
        await latestSub?.cancel();
      },
    );
    return controller.stream;
  }

  /// 開いた印を付ける。最初の 1 回だけ（2 回目以降で時刻を延ばさない）。
  Future<void> markViewed(String groupId, String weekKey, String uid) async {
    final ref = _playlists(groupId).doc(weekKey).collection('views').doc(uid);
    try {
      final snap = await ref.get();
      if (snap.exists) return;
      await ref.set({'viewedAt': FieldValue.serverTimestamp()});
    } catch (e) {
      if (kDebugMode) AppLog.debug('GroupPlaylistService.markViewed: $e');
    }
  }
}

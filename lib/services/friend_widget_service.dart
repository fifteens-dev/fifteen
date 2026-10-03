import 'dart:io' show Platform;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../models/post_model.dart';
import 'friend_service.dart';
import 'live_activity_service.dart';
import 'music_memory_cycle_service.dart';

/// ホーム画面ウィジェット「友達が今聴いてる曲」へデータを渡す。
///
/// 現在のサイクル（15s Day）に友達が投稿した曲を新しい順に集め、App Group の
/// ファイルへ書き出す。ウィジェット側は更新のたびに次の 1 件へ送る。
///
/// 画像（アルバムアート・友達のアイコン）は Live Activity と同じ置き場に
/// 入れる。既に持っているものは送らないので、毎回ダウンロードし直さない。
class FriendWidgetService {
  FriendWidgetService._();
  static final FriendWidgetService instance = FriendWidgetService._();

  static const MethodChannel _channel = MethodChannel('com.fifteen.liveactivity');

  /// ウィジェットに渡す最大件数。多すぎても一巡しないうちに次の日になる。
  static const int _maxItems = 8;

  final FriendService _friendService = FriendService();

  /// 短時間に何度も呼ばれても実際に走らせるのは 1 回だけ。
  DateTime? _lastRun;
  static const Duration _throttle = Duration(minutes: 5);

  /// 友達の投稿をウィジェットへ反映する。
  ///
  /// 失敗してもアプリ側には影響しない（ウィジェットが前のまま残るだけ）。
  Future<void> refresh({bool force = false}) async {
    if (!Platform.isIOS) return;

    final now = DateTime.now();
    if (!force && _lastRun != null && now.difference(_lastRun!) < _throttle) {
      return;
    }
    _lastRun = now;

    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null) {
        await _log('未ログイン');
        return;
      }

      final items = await _collect(uid);
      await _send(items);
    } catch (e) {
      await _log('失敗: $e');
    }
  }

  /// ウィジェットが読むファイルの中身を見る（開発者ツール用）。
  Future<String> diagnostics() async {
    final buf = StringBuffer();
    try {
      final res = await _channel
          .invokeMethod<dynamic>('friendWidgetDiagnostics');
      final map = (res as Map?) ?? {};
      buf.writeln('保存件数   : ${map['count'] ?? 0}');
      buf.writeln('ファイル   : ${map['file']}');
      buf.writeln('存在       : ${map['fileExists']}');
      final items = (map['items'] as List?) ?? const [];
      if (items.isEmpty) {
        buf.writeln('\n中身がありません。');
      } else {
        buf.writeln('\n中身:');
        for (final i in items) {
          buf.writeln('  $i');
        }
      }
    } catch (e) {
      buf.writeln('取得に失敗: $e');
    }
    return buf.toString();
  }

  /// Live Activity と同じログに残す。ウィジェットは実機でしか動かず、
  /// 画面にも何も出ないので、どこで止まったかはこれでしか分からない。
  Future<void> _log(String message) async {
    if (kDebugMode) print('FriendWidget: $message');
    try {
      await _channel.invokeMethod('log', {
        'tag': 'friendWidget',
        'message': message,
      });
    } catch (_) {/* ログが出せなくても本体は続ける */}
  }

  /// 現在のサイクルに友達が投稿した曲を新しい順に集める。
  Future<List<_Item>> _collect(String uid) async {
    final friends = await _friendService.loadFriends(uid);
    if (friends.isEmpty) {
      await _log('友達が 0 人');
      return const [];
    }

    final cycleStart = MusicMemoryCycleService().currentCycleStart;
    final byUid = {for (final f in friends) f.user.uid: f.user};

    // ここで getRecentPostsGroupedByUser は使えない。あれは Vibe ストーリー
    // バー用で isMoodPost を弾くが、今の投稿フローで作られる投稿は
    // すべて isMoodPost。候補が常に 0 件になる。
    final latest = await _latestPostPerFriend(
      uids: byUid.keys.toList(),
      since: cycleStart,
    );
    await _log('友達 ${friends.length} 人 / サイクル内の投稿 ${latest.length} 件'
        '（開始 ${cycleStart.toIso8601String()}）');

    return [
      for (final p in latest.take(_maxItems))
        if (byUid[p.userId] case final user?)
          _Item(
            trackName: p.track.trackName,
            artistName: p.track.artistName,
            artworkId: p.postId,
            artworkUrl: p.track.albumImageUrl,
            // 同じ人のアイコンを何度も落とさないよう uid で固定する。
            // art_friend_ 始まりはウィジェット用として掃除の対象にしている。
            avatarId: 'friend_${user.uid}',
            avatarUrl: user.profileImageUrl ?? '',
            friendName: (user.name?.isNotEmpty == true)
                ? user.name!
                : (user.username ?? ''),
            // 音楽サービスは投稿には入っていない。バッジは既定
            // （Apple Music）で出す。出し分けが要るなら投稿に持たせる。
            service: null,
          ),
    ];
  }

  /// 友達ごとの「現サイクルの最新 1 件」を新しい順に返す。
  ///
  /// 同じ人の投稿で埋まらないよう 1 人 1 件に絞る。
  Future<List<PostModel>> _latestPostPerFriend({
    required List<String> uids,
    required DateTime since,
  }) async {
    final byUser = <String, PostModel>{};
    // whereIn は 30 件まで。
    for (var i = 0; i < uids.length; i += 30) {
      final chunk = uids.skip(i).take(30).toList();
      try {
        final snap = await FirebaseFirestore.instance
            .collection('posts')
            .where('userId', whereIn: chunk)
            .where('createdAt', isGreaterThan: Timestamp.fromDate(since))
            .orderBy('createdAt', descending: true)
            .get();
        for (final doc in snap.docs) {
          final data = doc.data();
          if (data['isDummyPost'] == true) continue;
          final post = PostModel.fromFirestore(doc);
          // Vibe ストーリーは「今日の 1 曲」ではないので出さない。
          if (post.isVibe) continue;
          byUser.putIfAbsent(post.userId, () => post);
        }
      } catch (e) {
        await _log('投稿の取得に失敗: $e');
      }
    }
    final list = byUser.values.toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return list;
  }

  /// ネイティブへ渡す。未取得の画像だけダウンロードして同梱する。
  Future<void> _send(List<_Item> items) async {
    if (items.isEmpty) {
      await _log('出すものが無いので空で送る');
      await _channel.invokeMethod('syncFriends', {'items': <dynamic>[]});
      return;
    }

    // 既に保存済みの画像は送らない（毎回落とすと通信も時間も無駄）。
    final ids = <String>[
      for (final i in items) ...[i.artworkId, i.avatarId],
    ];
    Set<String> missing;
    try {
      final res = await _channel.invokeMethod<List<dynamic>>(
        'missingArtwork',
        {'ids': ids},
      );
      missing = (res ?? const []).map((e) => e.toString()).toSet();
    } catch (_) {
      missing = ids.toSet();
    }

    final payload = <Map<String, dynamic>>[];
    for (final item in items) {
      final entry = <String, dynamic>{
        'trackName': item.trackName,
        'artistName': item.artistName,
        'friendName': item.friendName,
        'artworkId': item.artworkId,
        'avatarId': item.avatarId,
        if (item.service != null) 'service': item.service,
      };
      if (missing.contains(item.artworkId)) {
        final bytes = await LiveActivityService().downloadImage(item.artworkUrl);
        if (bytes != null) entry['artworkBytes'] = bytes;
      }
      if (missing.contains(item.avatarId)) {
        final bytes = await LiveActivityService().downloadImage(item.avatarUrl);
        if (bytes != null) entry['avatarBytes'] = bytes;
      }
      payload.add(entry);
    }

    await _log('送信 ${payload.length} 件 / 画像の新規取得 ${missing.length} 件');
    await _channel.invokeMethod('syncFriends', {'items': payload});
  }
}

/// 書き出す 1 件分。画像は URL のまま持ち、必要なときだけ落とす。
class _Item {
  final String trackName;
  final String artistName;
  final String artworkId;
  final String artworkUrl;
  final String avatarId;
  final String avatarUrl;
  final String friendName;
  final String? service;

  const _Item({
    required this.trackName,
    required this.artistName,
    required this.artworkId,
    required this.artworkUrl,
    required this.avatarId,
    required this.avatarUrl,
    required this.friendName,
    required this.service,
  });
}

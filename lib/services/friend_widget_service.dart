import 'dart:io' show Platform;

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../models/post_model.dart';
import 'friend_service.dart';
import 'live_activity_service.dart';
import 'music_memory_cycle_service.dart';
import 'post_service.dart';

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
  final PostService _postService = PostService();

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
      if (uid == null) return;

      final items = await _collect(uid);
      await _send(items);
    } catch (e) {
      if (kDebugMode) print('FriendWidgetService.refresh error: $e');
    }
  }

  /// 現在のサイクルに友達が投稿した曲を新しい順に集める。
  Future<List<_Item>> _collect(String uid) async {
    final friends = await _friendService.loadFriends(uid);
    if (friends.isEmpty) return const [];

    final cycleStart = MusicMemoryCycleService().currentCycleStart;
    final byUid = {for (final f in friends) f.user.uid: f.user};

    final posts = await _postService.getRecentPostsGroupedByUser(
      userIds: byUid.keys.toList(),
      // 友達＝相互フォローなので、鍵投稿も見える。
      viewerFollowsAuthor: (_) => true,
    );

    // ユーザーごとの最新 1 件だけを見る。同じ人で埋まらないようにするため。
    final latest = <PostModel>[];
    for (final group in posts) {
      for (final p in group) {
        // タイムラインに載らない投稿は出さない（Vibe ストーリー等）。
        if (p.isVibe) continue;
        if (!p.createdAt.isAfter(cycleStart)) continue;
        latest.add(p);
        break;
      }
    }
    latest.sort((a, b) => b.createdAt.compareTo(a.createdAt));

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

  /// ネイティブへ渡す。未取得の画像だけダウンロードして同梱する。
  Future<void> _send(List<_Item> items) async {
    if (items.isEmpty) {
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

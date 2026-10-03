import 'dart:io' show Platform;

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'friend_service.dart';
import 'apple_music_service.dart';
import 'live_activity_service.dart';
import 'now_playing_share_service.dart';

/// ホーム画面ウィジェット「友達が今聴いてる曲」へデータを渡す。
///
/// 友達が**今 Apple Music で再生している曲**を集めて App Group のファイルへ
/// 書き出す。ウィジェット側は更新のたびに次の 1 人へ送る。
///
/// 友達の端末の再生状態を直接知る API は無いので、各自が自分のぶんを
/// Firestore に書いたものを読む（[NowPlayingShareService]）。
/// 報告が古い人は「聴いていない」として出さない。
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

  /// 友達が今 Apple Music で聴いている曲を集める。
  Future<List<_Item>> _collect(String uid) async {
    final friends = await _friendService.loadFriends(uid);
    if (friends.isEmpty) {
      await _log('友達が 0 人');
      return const [];
    }

    final byUid = {for (final f in friends) f.user.uid: f.user};
    final playing = await NowPlayingShareService.instance
        .fetch(byUid.keys.toList());

    // 報告が新しい順。「今」に近い人から見せる。
    final entries = playing.entries.toList()
      ..sort((a, b) => b.value.updatedAt.compareTo(a.value.updatedAt));

    await _log('友達 ${friends.length} 人 / 再生中 ${entries.length} 人');

    return [
      for (final e in entries.take(_maxItems))
        if (byUid[e.key] case final user?)
          _Item(
            trackName: e.value.trackName,
            artistName: e.value.artistName,
            // アートワークは曲ごとに固定。同じ曲なら落とし直さない。
            artworkId: e.value.storeId != null
                ? 'track_${e.value.storeId}'
                : 'track_${e.value.trackName.hashCode}',
            artworkUrl: await _artworkUrl(e.value),
            // 同じ人のアイコンを何度も落とさないよう uid で固定する。
            // art_friend_ 始まりはウィジェット用として掃除の対象にしている。
            avatarId: 'friend_${user.uid}',
            avatarUrl: user.profileImageUrl ?? '',
            friendName: (user.name?.isNotEmpty == true)
                ? user.name!
                : (user.username ?? ''),
            // 共有しているのは Apple Music の再生状態だけ。
            service: 'appleMusic',
          ),
    ];
  }

  /// 曲のアートワーク URL。カタログ ID があればそこから引く。
  Future<String> _artworkUrl(NowPlayingEntry entry) async {
    final id = entry.storeId;
    if (id == null || id.isEmpty) return '';
    try {
      final track = await AppleMusicService().getCatalogSongById(id);
      return track?.albumImageUrl ?? '';
    } catch (_) {
      return '';
    }
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

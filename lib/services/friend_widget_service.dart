import 'dart:io' show Platform;

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'group_service.dart';
import 'apple_music_service.dart';
import 'itunes_search_service.dart';
import 'live_activity_service.dart';
import 'now_playing_share_service.dart';
import '../utils/app_log.dart';

/// ホーム画面ウィジェット「友達の1曲」へデータを渡す。
///
/// 同じグループの人が**今、または最近 Apple Music で聴いた曲**を集めて
/// App Group のファイルへ書き出す。ウィジェット側は更新のたびに次の 1 人へ
/// 送り、「今」か「◯時間前」かを添えて出す。
///
/// 相手の端末の再生状態を直接知る API は無いので、各自が自分のぶんを
/// Firestore に書いたものを読む（[NowPlayingShareService]）。
///
/// 画像（アルバムアート・友達のアイコン）は Live Activity と同じ置き場に
/// 入れる。既に持っているものは送らないので、毎回ダウンロードし直さない。
class FriendWidgetService {
  FriendWidgetService._();
  static final FriendWidgetService instance = FriendWidgetService._();

  static const MethodChannel _channel = MethodChannel('com.fifteen.liveactivity');

  /// ウィジェットに渡す最大件数。多すぎても一巡しないうちに次の日になる。
  static const int _maxItems = 8;

  final GroupService _groupService = GroupService();

  /// 短時間に何度も呼ばれても実際に走らせるのは 1 回だけ。
  DateTime? _lastRun;
  static const Duration _throttle = Duration(minutes: 5);

  /// ダミーを流している間は、本物の更新で上書きしない（開発者ツール用）。
  DateTime? _dummyUntil;

  /// 友達の投稿をウィジェットへ反映する。
  ///
  /// 失敗してもアプリ側には影響しない（ウィジェットが前のまま残るだけ）。
  /// [force] はダミー表示中でも本物に戻す。
  Future<void> refresh({bool force = false}) async {
    if (!Platform.isIOS) return;

    final now = DateTime.now();
    if (force) {
      _dummyUntil = null;
    } else if (_dummyUntil != null && now.isBefore(_dummyUntil!)) {
      return;
    }
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

  /// ダミーの友達と曲をウィジェットに流す（開発者ツール用）。
  ///
  /// 「今聴いてる」「◯分前」「◯時間前」「◯日前」が一通り出るように時刻を
  /// ずらしてある。Firestore には何も書かず、この端末のウィジェットだけが
  /// 変わる。1 時間は本物の更新で上書きしない（[refresh] の force で戻せる）。
  Future<void> sendDummy() async {
    if (!Platform.isIOS) return;
    final now = DateTime.now();
    const dummies = [
      ('Ryota', 'ゴミ人間、俺', 'ヤングスキニー', Duration.zero, true),
      ('Nanami', 'Magnetic', 'ILLIT', Duration(minutes: 12), false),
      ('Kenta', 'Lose Yourself', 'Eminem', Duration(hours: 3), false),
      ('Mio', 'Pretender', 'Official髭男dism', Duration(hours: 9), false),
      ('Sota', 'アイドル', 'YOASOBI', Duration(hours: 26), false),
    ];
    final itunes = ITunesSearchService();
    final items = <_Item>[];
    for (final (i, (name, track, artist, ago, isNow)) in dummies.indexed) {
      String artworkUrl = '';
      try {
        final hits = await itunes.searchTracks('$track $artist', limit: 1);
        if (hits.isNotEmpty) artworkUrl = hits.first.albumImageUrl;
      } catch (_) {/* 画像が無くてもダミーとしては足りる */}
      items.add(_Item(
        trackName: track,
        artistName: artist,
        // friend_ 始まりにして、本物に戻したとき掃除されるようにする。
        artworkId: 'friend_dummy_art_$i',
        artworkUrl: artworkUrl,
        // アイコンは用意しない（頭文字で出る）。
        avatarId: 'friend_dummy_$i',
        avatarUrl: '',
        friendName: name,
        service: 'appleMusic',
        playedAt: now.subtract(ago),
        isNow: isNow,
      ));
    }
    _dummyUntil = now.add(const Duration(hours: 1));
    await _log('ダミーを送信 ${items.length} 件');
    await _send(items);
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
    if (kDebugMode) AppLog.debug('FriendWidget: $message');
    try {
      await _channel.invokeMethod('log', {
        'tag': 'friendWidget',
        'message': message,
      });
    } catch (_) {/* ログが出せなくても本体は続ける */}
  }

  /// 友達が今、または最近 Apple Music で聴いた曲を集める。
  Future<List<_Item>> _collect(String uid) async {
    // 友達機能は廃止したので、相手は同じグループの人（2026-11-01）。
    final mateUids = await _groupService.groupmateUids(uid);
    if (mateUids.isEmpty) {
      await _log('同じグループの人が 0 人');
      return const [];
    }

    final mates = await _groupService.fetchUsers(mateUids);
    final byUid = {for (final u in mates) u.uid: u};
    final playing = await NowPlayingShareService.instance
        .fetch(byUid.keys.toList());

    // 聴いた時刻が新しい順。「今」に近い人から見せる。
    final entries = playing.entries.toList()
      ..sort((a, b) => b.value.playedAt.compareTo(a.value.playedAt));

    final nowCount = entries.where((e) => e.value.isNow).length;
    await _log('グループの人 ${mates.length} 人 / 再生中 $nowCount 人 / '
        '最近聴いた ${entries.length} 人');

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
            playedAt: e.value.playedAt,
            isNow: e.value.isNow,
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
        // ウィジェット側で表示の瞬間に「◯分前」を数え直すため、時刻で渡す。
        'playedAt': item.playedAt.millisecondsSinceEpoch / 1000,
        'isNow': item.isNow,
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
  final DateTime playedAt;
  final bool isNow;

  const _Item({
    required this.trackName,
    required this.artistName,
    required this.artworkId,
    required this.artworkUrl,
    required this.avatarId,
    required this.avatarUrl,
    required this.friendName,
    required this.service,
    required this.playedAt,
    required this.isNow,
  });
}

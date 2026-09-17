import 'package:flutter/foundation.dart';

import '../models/music_service_type.dart';
import 'music_service_manager.dart';
import 'now_playing_service.dart';
import 'playback_history_service.dart';

/// 「最近よく聴いている」を集計するための再生履歴。
///
/// ## なぜ Web API だけでは足りないか
/// Apple Music の `/me/recent/played/tracks` は、このアプリのユーザー層では
/// ほとんど埋まらないことが分かっている（[PlaybackHistoryService] と
/// [NowPlayingService] のコメント参照）。反映が遅く、購入曲以外を拾えず、
/// あまりストリーミングしない人だと何年も前の曲が先頭に残る。
/// 実際に 100 件要求して 1 件しか返らないアカウントがあった。
///
/// 投稿フローの選曲画面が充実して見えるのは、Web API だけでなく
/// アプリ内で記録した履歴と端末ライブラリの再生ログを合わせているため。
/// 集計もそれに揃える。
///
/// ## 並べ方
///  1. Web API の再生順（**重複をそのまま残す**）。繰り返し聴いた分が効く。
///  2. そこに出てこなかった曲を、アプリ内履歴 → 端末ライブラリの順に新しい順で足す。
///
/// 2 は曲ごとに 1 件しか持てない（[NowPlayingService] は lastPlayedDate を
/// 1 曲 1 件でしか返さない）ので再生回数は乗らない。つまり Web API が
/// 埋まっているアカウントでは「再生回数の合計」、そうでなければ
/// 「聴いた曲数」に近い集計になる。どちらでも順位の意味は保たれる。
///
/// ## Spotify では 2 を足さない
/// アプリ内履歴も端末ライブラリも、iOS のミュージックプレイヤー（Apple Music /
/// ローカル曲）の再生を見ている。Spotify での再生はそこに現れないので、
/// 混ぜると「Spotify で聴いていない曲」がランキングに入ってしまう。
/// Spotify は API の履歴（直近 50 件）だけを使う。
class ListeningHistoryService {
  ListeningHistoryService._();
  static final ListeningHistoryService instance = ListeningHistoryService._();

  final MusicServiceManager _music = MusicServiceManager();

  /// 直近に聴いた曲のアーティスト名を、新しい順・重複ありで返す。
  ///
  /// 返す件数は [limit] まで。取れるものが少なければそのぶん短くなる。
  Future<List<String>> recentArtistNames({required int limit}) async {
    final service = await _music.getSelectedService();
    final names = <String>[];

    /// 既に数えた曲。曲名＋アーティストで見る（ソースごとに ID 体系が違うため）。
    final countedSongs = <String>{};
    String songKey(String title, String artist) =>
        '${title.toLowerCase().trim()}|${artist.toLowerCase().trim()}';

    // 1) Web API（再生順・重複あり）
    try {
      final tracks =
          await _music.getRecentlyPlayedTracks(limit: limit, deduplicate: false);
      for (final t in tracks) {
        if (t.artistName.trim().isEmpty) continue;
        names.add(t.artistName.trim());
        countedSongs.add(songKey(t.trackName, t.artistName));
      }
    } catch (e) {
      if (kDebugMode) print('ListeningHistory: web api failed: $e');
    }

    // Spotify はここで打ち切り。以降の 2 つは iOS のミュージックプレイヤーの
    // 再生ログで、Spotify での再生は含まれない。
    if (service != MusicServiceType.appleMusic) return names.take(limit).toList();

    // 2) アプリ内で記録した再生履歴（直近 24 時間）
    try {
      for (final t in PlaybackHistoryService().recentTracks()) {
        if (names.length >= limit) break;
        if (t.artistName.trim().isEmpty) continue;
        if (!countedSongs.add(songKey(t.trackName, t.artistName))) continue;
        names.add(t.artistName.trim());
      }
    } catch (e) {
      if (kDebugMode) print('ListeningHistory: playback history failed: $e');
    }

    // 3) 端末ライブラリの再生ログ（lastPlayedDate の新しい順）
    try {
      final device =
          await NowPlayingService().getDeviceRecentlyPlayed(limit: limit);
      for (final e in device) {
        if (names.length >= limit) break;
        if (e.artist.trim().isEmpty) continue;
        if (!countedSongs.add(songKey(e.title, e.artist))) continue;
        names.add(e.artist.trim());
      }
    } catch (e) {
      if (kDebugMode) print('ListeningHistory: device history failed: $e');
    }

    return names.take(limit).toList();
  }

  /// どのソースから何件取れたかの内訳。原因の切り分け用（開発者ツールから呼ぶ）。
  Future<Map<String, int>> sourceBreakdown({required int limit}) async {
    Future<int> count(Future<int> Function() f) async {
      try {
        return await f();
      } catch (_) {
        return -1; // 取得自体が失敗
      }
    }

    return {
      'webApi': await count(() async => (await _music.getRecentlyPlayedTracks(
            limit: limit,
            deduplicate: false,
          ))
              .length),
      // 以下 2 つは Apple Music のときだけ集計に混ぜる。

      'inApp': await count(
          () async => PlaybackHistoryService().recentTracks().length),
      'device': await count(() async =>
          (await NowPlayingService().getDeviceRecentlyPlayed(limit: limit))
              .length),
      'merged': (await recentArtistNames(limit: limit)).length,
    };
  }
}

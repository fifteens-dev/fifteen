import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import '../models/track_model.dart';

/// 端末の音楽ライブラリ / 再生状態（iOS ネイティブ）から
/// 「今聞いている曲」「最後に再生した時刻」を取得し、TrackModel を補強する。
///
/// ネイティブ側は AppDelegate の `com.fifteen.musicmemory` チャンネル。
/// iOS 以外・取得失敗時は元のリストをそのまま返す（安全なフォールバック）。
class NowPlayingService {
  static const MethodChannel _channel = MethodChannel('com.fifteen.musicmemory');

  static String _norm(String? s) =>
      (s ?? '').toLowerCase().replaceAll(RegExp(r'\s+'), ' ').trim();

  static String _key(String? title, String? artist) =>
      '${_norm(title)}|${_norm(artist)}';

  /// tracks に playedAt / isNowPlaying を付与し、実際の再生時刻で並べ替える。
  ///
  /// Apple Music の Web API `/me/recent/played/tracks` の順は実時刻とズレることが
  /// あり（あまりストリーミングしないユーザーだと何年も前の曲が先頭に残る）、その
  /// ままだと投稿フローの先頭に古い曲が出てしまう。そこで:
  ///   - 今再生中の曲（isNowPlaying）は最優先で先頭にする。
  ///   - タイムスタンプ（端末ライブラリの lastPlayedDate）が取れた曲は、その時刻の
  ///     新しい順に並べ、古い曲は後ろへ回す。
  ///   - タイムスタンプが取れない曲（＝最近のストリーミングとみなす）は Web API 順の
  ///     まま上位に残す（実際の最新はこちらであることが多い）。
  ///   - 安定ソートで同条件の相対順は維持する。
  Future<List<TrackModel>> enrich(List<TrackModel> tracks) async {
    if (!Platform.isIOS || tracks.isEmpty) return tracks;

    // 今聞いている曲
    String? npKey;
    bool npPlaying = false;
    try {
      final np = await _channel.invokeMethod<Map>('getNowPlaying');
      // 【診断ログ】ネイティブから返った now playing の中身。
      print('[MM nowPlaying] raw=$np');
      if (np != null && (np['isPlaying'] == true)) {
        npKey = _key(np['title'] as String?, np['artist'] as String?);
        npPlaying = true;
      }
    } catch (e) {
      print('[MM nowPlaying] error=$e');
    }

    // 最後に再生した時刻（曲キー → DateTime）
    final Map<String, DateTime> playedAt = {};
    try {
      final list =
          await _channel.invokeMethod<List>('getRecentlyPlayed', {'limit': 30});
      if (list != null) {
        for (final e in list) {
          final m = e as Map;
          final ms = (m['playedAtMs'] as num?)?.toInt();
          if (ms != null && ms > 0) {
            playedAt[_key(m['title'] as String?, m['artist'] as String?)] =
                DateTime.fromMillisecondsSinceEpoch(ms);
          }
        }
      }
    } catch (_) {}

    if (npKey == null && playedAt.isEmpty) return tracks;

    return orderTracks(
      tracks,
      npKey: npKey,
      npPlaying: npPlaying,
      playedAt: playedAt,
    );
  }

  /// 並べ替え本体（純粋関数・テスト可能）。
  /// - 今再生中の曲（npKey と一致 & npPlaying）は最優先で先頭。
  /// - playedAt が取れた曲は実時刻の新しい順。古い曲は後ろへ。
  /// - playedAt が無い曲は「最近」とみなし now を基準に上位へ（Web API 順を維持）。
  /// - 安定ソートで同条件の相対順は保つ。
  @visibleForTesting
  static List<TrackModel> orderTracks(
    List<TrackModel> tracks, {
    required String? npKey,
    required bool npPlaying,
    required Map<String, DateTime> playedAt,
    DateTime? now,
  }) {
    final resolvedNow = now ?? DateTime.now();
    final enriched = tracks.map((t) {
      final key = _key(t.trackName, t.artistName);
      return t.copyWith(
        playedAt: playedAt[key],
        isNowPlaying: npPlaying && npKey != null && key == npKey,
      );
    }).toList();

    final farFuture = DateTime.utc(9999);
    DateTime effTime(TrackModel t) =>
        t.isNowPlaying ? farFuture : (t.playedAt ?? resolvedNow);
    final indexed = [for (var i = 0; i < enriched.length; i++) (i, enriched[i])];
    indexed.sort((a, b) {
      final c = effTime(b.$2).compareTo(effTime(a.$2)); // 新しい→古い
      return c != 0 ? c : a.$1.compareTo(b.$1); // 同条件は Web API 順を維持
    });
    return [for (final e in indexed) e.$2];
  }

  /// テスト用に正規化キーを公開。
  @visibleForTesting
  static String keyForTest(String? title, String? artist) => _key(title, artist);
}

import 'dart:io';
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

  /// tracks に playedAt / isNowPlaying を付与し、Now Playing の曲があれば先頭へ。
  Future<List<TrackModel>> enrich(List<TrackModel> tracks) async {
    if (!Platform.isIOS || tracks.isEmpty) return tracks;

    // 今聞いている曲
    String? npKey;
    bool npPlaying = false;
    try {
      final np = await _channel.invokeMethod<Map>('getNowPlaying');
      if (np != null && (np['isPlaying'] == true)) {
        npKey = _key(np['title'] as String?, np['artist'] as String?);
        npPlaying = true;
      }
    } catch (_) {}

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

    final enriched = tracks.map((t) {
      final key = _key(t.trackName, t.artistName);
      return t.copyWith(
        playedAt: playedAt[key],
        isNowPlaying: npPlaying && npKey != null && key == npKey,
      );
    }).toList();

    // Now Playing の曲があれば先頭へ（「最初に表示するのは今聞いている曲」）。
    final npIndex = enriched.indexWhere((t) => t.isNowPlaying);
    if (npIndex > 0) {
      final np = enriched.removeAt(npIndex);
      enriched.insert(0, np);
    }
    return enriched;
  }
}

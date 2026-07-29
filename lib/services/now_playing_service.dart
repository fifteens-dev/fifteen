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
  /// 今 Apple Music（システムミュージックプレイヤー）で再生中の曲情報を返す。
  /// iOS 以外・取得不可・曲情報が無い場合は null。
  /// [includeArtwork] false で埋め込みアートを付けない（履歴ポーリング用の軽量版）。
  Future<NowPlayingInfo?> getNowPlaying({bool includeArtwork = true}) async {
    if (!Platform.isIOS) return null;
    try {
      final np = await _channel.invokeMethod<Map>(
          'getNowPlaying', {'includeArtwork': includeArtwork});
      if (includeArtwork) {
        // 【診断ログ】ネイティブから返った now playing の中身（ポーリング時は抑制）。
        print('[MM nowPlaying] raw=$np');
      }
      if (np == null) return null;
      final title = (np['title'] as String?)?.trim() ?? '';
      final artist = (np['artist'] as String?)?.trim() ?? '';
      if (title.isEmpty) return null;
      // "0"/空 は非ストア曲＝カタログID無しとして扱う。
      final rawStore = (np['storeId'] as String?)?.trim() ?? '';
      final storeId = (rawStore.isEmpty || rawStore == '0') ? null : rawStore;
      final art = (np['artworkDataUri'] as String?);
      return NowPlayingInfo(
        title: title,
        artist: artist,
        isPlaying: np['isPlaying'] == true,
        storeId: storeId,
        artworkDataUri: (art != null && art.isNotEmpty) ? art : null,
      );
    } catch (e) {
      print('[MM nowPlaying] error=$e');
      return null;
    }
  }

  Future<List<TrackModel>> enrich(List<TrackModel> tracks) async {
    if (!Platform.isIOS || tracks.isEmpty) return tracks;

    // 今聞いている曲
    String? npKey;
    bool npPlaying = false;
    final np = await getNowPlaying();
    if (np != null && np.isPlaying) {
      npKey = _key(np.title, np.artist);
      npPlaying = true;
    }

    // 最後に再生した時刻（曲キー → DateTime）
    final playedAt = await _fetchPlayedAtMap();

    if (npKey == null && playedAt.isEmpty) return tracks;

    return orderTracks(
      tracks,
      npKey: npKey,
      npPlaying: npPlaying,
      playedAt: playedAt,
    );
  }

  /// 端末ライブラリの「最近再生した曲」を新しい順で取得する（title/artist/playedAt）。
  ///
  /// `lastPlayedDate` は端末側で**ほぼリアルタイム**に更新されるため、
  /// Web API（サーバ反映が遅い）がまだ返さない直近の再生曲を拾うのに使う。
  /// ※ライブラリに追加済みの曲のみが対象（純ストリーミングは含まれない）。
  Future<List<({String title, String artist, DateTime playedAt})>>
      getDeviceRecentlyPlayed({int limit = 30}) =>
          _fetchDeviceRecentEntries(limit: limit);

  /// MediaPlayer と MusicKit(iOS16+) 両方から再生履歴を取得してマージする。
  /// 同じ曲は「より新しい方の時刻」を採用。どちらか一方でしか lastPlayedDate が
  /// 付かないケース（Apple Music クラウド曲など）を両取りで拾うのが狙い。
  Future<List<({String title, String artist, DateTime playedAt})>>
      _fetchDeviceRecentEntries({int limit = 30}) async {
    if (!Platform.isIOS) return const [];
    final byKey = <String, ({String title, String artist, DateTime playedAt})>{};

    Future<void> pull(String method) async {
      try {
        final list = await _channel.invokeMethod<List>(method, {'limit': limit});
        if (list == null) return;
        for (final e in list) {
          final m = e as Map;
          final ms = (m['playedAtMs'] as num?)?.toInt();
          final title = (m['title'] as String?)?.trim() ?? '';
          if (ms == null || ms <= 0 || title.isEmpty) continue;
          final artist = (m['artist'] as String?)?.trim() ?? '';
          final at = DateTime.fromMillisecondsSinceEpoch(ms);
          final k = _key(title, artist);
          final ex = byKey[k];
          if (ex == null || at.isAfter(ex.playedAt)) {
            byKey[k] = (title: title, artist: artist, playedAt: at);
          }
        }
      } catch (_) {}
    }

    await pull('getRecentlyPlayed'); // MediaPlayer（MPMediaItem.lastPlayedDate）
    await pull('getLibraryRecentlyPlayed'); // MusicKit（Song.lastPlayedDate, iOS16+）

    final out = byKey.values.toList()
      ..sort((a, b) => b.playedAt.compareTo(a.playedAt)); // 新しい順
    return out;
  }

  /// 端末ライブラリの lastPlayedDate を「曲キー → 時刻」で取得する（両ソースをマージ）。
  Future<Map<String, DateTime>> _fetchPlayedAtMap() async {
    final entries = await _fetchDeviceRecentEntries();
    return {for (final e in entries) _key(e.title, e.artist): e.playedAt};
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

/// 「今再生中の曲」情報。
class NowPlayingInfo {
  final String title;
  final String artist;
  final bool isPlaying;

  /// Apple Music カタログID（playbackStoreID）。非ストア曲や取得不可のときは null。
  final String? storeId;

  /// 端末の曲データに埋め込まれたアートワーク（data URI）。カタログ解決できない
  /// ローカル/取り込み曲を完璧一致で表示するためのフォールバック。無ければ null。
  final String? artworkDataUri;

  const NowPlayingInfo({
    required this.title,
    required this.artist,
    required this.isPlaying,
    this.storeId,
    this.artworkDataUri,
  });
}

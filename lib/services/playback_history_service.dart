import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/track_model.dart';
import 'apple_music_service.dart';
import 'now_playing_service.dart';

/// アプリ起動時から、システムミュージックプレイヤーで再生された曲を
/// 「手動で」履歴化するサービス（Apple Music の Web API 履歴が遅い・購入曲以外を
/// 拾えない問題を補うため）。
///
/// 仕組み:
///  - 一定間隔で [NowPlayingService.getNowPlaying]（軽量版）をポーリング。
///  - 「再生中」かつ「直前に記録した曲と別の曲」に変わった瞬間だけ 1 件記録する。
///  - 記録時に一度だけアート付きで取得し、埋め込みアート（data URI）も保存する
///    （購入曲以外・ローカル曲でもジャケットを正しく表示できるように）。
///  - SharedPreferences に永続化し、アプリ再起動をまたいでも当日分を保持する。
///
/// 記録された曲は [recentTracks] で新しい順の [TrackModel] として取得できる。
class PlaybackHistoryService {
  PlaybackHistoryService._();
  static final PlaybackHistoryService _instance = PlaybackHistoryService._();
  factory PlaybackHistoryService() => _instance;

  static const String _prefsKey = 'playback_history_v1';
  static const Duration _pollInterval = Duration(seconds: 12);
  static const int _maxEntries = 40;
  static const Duration _maxAge = Duration(hours: 36);

  Timer? _timer;
  final List<_HistoryEntry> _entries = []; // 新しい順（先頭が最新）
  String? _lastRecordedKey;
  bool _started = false;

  static String _norm(String? s) =>
      (s ?? '').toLowerCase().replaceAll(RegExp(r'\s+'), ' ').trim();
  static String _key(String? title, String? artist) =>
      '${_norm(title)}|${_norm(artist)}';

  /// アプリ起動時に一度呼ぶ。永続データを読み込み、ポーリングを開始する。
  Future<void> start() async {
    if (_started) return;
    _started = true;
    await _load();
    _lastRecordedKey =
        _entries.isNotEmpty ? _key(_entries.first.title, _entries.first.artist) : null;
    // 初回即チェック → 以降は定期ポーリング。
    _tick();
    _timer = Timer.periodic(_pollInterval, (_) => _tick());
  }

  void dispose() {
    _timer?.cancel();
    _timer = null;
    _started = false;
  }

  Future<void> _tick() async {
    try {
      // ポーリングは軽量版（アート無し）で曲の変化だけ見る。
      final np = await NowPlayingService().getNowPlaying(includeArtwork: false);
      if (np == null || !np.isPlaying || np.title.isEmpty) return;
      final key = _key(np.title, np.artist);
      if (key == _lastRecordedKey) return; // 連続同一はスキップ

      // 変化を検知した曲だけ、アート付きで取り直して記録する。
      final full =
          await NowPlayingService().getNowPlaying(includeArtwork: true);
      final title = (full?.title.isNotEmpty ?? false) ? full!.title : np.title;
      final artist = full?.artist ?? np.artist;
      final storeId = full?.storeId ?? np.storeId;

      // アートは「URL で引き戻せる」形を優先する:
      //  - カタログ配信曲 → storeId から https アート URL を解決して保存（軽量）。
      //  - URL が取れないローカル/取り込み曲のみ、埋め込み画像(data URI)を保存。
      String? artUrl;
      if (storeId != null) {
        try {
          final catalog =
              await AppleMusicService().getCatalogSongById(storeId);
          if (catalog != null && catalog.albumImageUrl.startsWith('http')) {
            artUrl = catalog.albumImageUrl;
          }
        } catch (_) {}
      }
      final entry = _HistoryEntry(
        title: title,
        artist: artist,
        storeId: storeId,
        artUrl: artUrl,
        // https URL が取れたときは重い data URI を持たない。
        artworkDataUri: artUrl == null ? full?.artworkDataUri : null,
        playedAtMs: DateTime.now().millisecondsSinceEpoch,
      );
      _lastRecordedKey = key;
      _entries.insert(0, entry);
      _prune();
      await _save();
    } catch (e) {
      if (kDebugMode) print('[PlaybackHistory] tick error: $e');
    }
  }

  void _prune() {
    // 古すぎるものを除去 + 上限件数でカット。
    final cutoff = DateTime.now().subtract(_maxAge).millisecondsSinceEpoch;
    _entries.removeWhere((e) => e.playedAtMs < cutoff);
    if (_entries.length > _maxEntries) {
      _entries.removeRange(_maxEntries, _entries.length);
    }
  }

  /// 手動履歴を新しい順の [TrackModel] で返す。
  /// albumImageUrl には埋め込みアート（data URI）を入れるので、購入曲以外でも
  /// 正しいジャケットで表示できる。playedAt には実際の検知時刻を入れる。
  List<TrackModel> recentTracks() {
    _prune();
    return [
      for (final e in _entries)
        TrackModel(
          trackId: (e.storeId != null && e.storeId!.isNotEmpty)
              ? e.storeId!
              : 'hist_${_key(e.title, e.artist)}',
          trackName: e.title,
          artistName: e.artist,
          // https URL を優先、無ければ埋め込み画像(data URI)、それも無ければ空。
          albumImageUrl: e.artUrl ?? e.artworkDataUri ?? '',
          playedAt: DateTime.fromMillisecondsSinceEpoch(e.playedAtMs),
        ),
    ];
  }

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_prefsKey);
      if (raw == null) return;
      final list = json.decode(raw) as List;
      _entries
        ..clear()
        ..addAll(list.map((e) => _HistoryEntry.fromJson(e as Map<String, dynamic>)));
      _prune();
    } catch (_) {}
  }

  Future<void> _save() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
          _prefsKey, json.encode([for (final e in _entries) e.toJson()]));
    } catch (_) {}
  }
}

class _HistoryEntry {
  final String title;
  final String artist;
  final String? storeId;

  /// カタログの https アート URL（軽量・恒久的に引き戻せる）。取れたときのみ。
  final String? artUrl;

  /// 埋め込みアート(data URI)。URL が取れないローカル曲のフォールバックのみ。
  final String? artworkDataUri;
  final int playedAtMs;

  _HistoryEntry({
    required this.title,
    required this.artist,
    required this.storeId,
    this.artUrl,
    this.artworkDataUri,
    required this.playedAtMs,
  });

  Map<String, dynamic> toJson() => {
        't': title,
        'a': artist,
        's': storeId,
        'url': artUrl,
        'art': artworkDataUri,
        'ms': playedAtMs,
      };

  factory _HistoryEntry.fromJson(Map<String, dynamic> m) => _HistoryEntry(
        title: (m['t'] as String?) ?? '',
        artist: (m['a'] as String?) ?? '',
        storeId: m['s'] as String?,
        artUrl: m['url'] as String?,
        artworkDataUri: m['art'] as String?,
        playedAtMs: (m['ms'] as num?)?.toInt() ?? 0,
      );
}

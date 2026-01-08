import 'dart:convert';
import 'package:http/http.dart' as http;

/// 歌詞の取得元
enum LyricsSource {
  lrclib, // LRCLIB API
  appleMusicSnippet, // Apple Music歌詞スニペット
  none, // 取得失敗
}

/// 歌詞の1行（タイムスタンプ付き）
class LyricLine {
  final int timestampMs; // ミリ秒単位のタイムスタンプ
  final String text; // 歌詞テキスト

  LyricLine({required this.timestampMs, required this.text});

  @override
  String toString() => '[$timestampMs ms] $text';
}

/// 歌詞データモデル
class LyricsData {
  final String plainLyrics; // プレーン歌詞
  final String? syncedLyrics; // タイムスタンプ付き歌詞（LRC形式）
  final List<LyricLine>? lines; // パース済み歌詞行
  final LyricsSource source; // 取得元

  LyricsData({
    required this.plainLyrics,
    this.syncedLyrics,
    this.lines,
    required this.source,
  });

  @override
  String toString() {
    return 'LyricsData(source: $source, plainLength: ${plainLyrics.length}, hasSync: ${syncedLyrics != null}, lines: ${lines?.length ?? 0})';
  }
}

/// 歌詞取得サービス（LRCLIB + Apple Music Snippet）
class LyricsService {
  static final LyricsService _instance = LyricsService._internal();
  factory LyricsService() => _instance;
  LyricsService._internal();

  final _lrclibBaseUrl = 'https://lrclib.net/api';

  /// フォールバック戦略で歌詞を取得
  ///
  /// 優先順位:
  /// 1. LRCLIB API（タイムスタンプ付き完全な歌詞）
  /// 2. Apple Music Snippet（歌詞の一部）
  Future<LyricsData?> getLyrics({
    required String trackName,
    required String artistName,
    int? durationSeconds,
    String? appleDevToken,
  }) async {
    print('🎵 歌詞取得開始: $trackName by $artistName');

    // Step 1: LRCLIB APIで取得
    final lrclibLyrics = await _getLyricsFromLRCLIB(
      trackName: trackName,
      artistName: artistName,
      duration: durationSeconds,
    );

    if (lrclibLyrics != null) {
      print('✅ LRCLIB APIで歌詞取得成功');
      return lrclibLyrics;
    }

    // Step 2: Apple Music Snippetで取得
    if (appleDevToken != null && appleDevToken.isNotEmpty) {
      final snippetLyrics = await _getLyricsFromAppleMusicSnippet(
        trackName: trackName,
        artistName: artistName,
        developerToken: appleDevToken,
      );

      if (snippetLyrics != null) {
        print('⚪ Apple Music Snippetで歌詞の一部を取得');
        return snippetLyrics;
      }
    }

    print('❌ 歌詞取得失敗（すべてのソースで見つからず）');
    return null;
  }

  /// LRCLIB APIから歌詞を取得
  Future<LyricsData?> _getLyricsFromLRCLIB({
    required String trackName,
    required String artistName,
    int? duration,
  }) async {
    try {
      final url = '$_lrclibBaseUrl/get?'
          'track_name=${Uri.encodeComponent(trackName)}&'
          'artist_name=${Uri.encodeComponent(artistName)}'
          '${duration != null ? "&duration=$duration" : ""}';

      print('  → LRCLIB URL: $url');

      final response = await http.get(Uri.parse(url));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final plainLyrics = data['plainLyrics'] as String?;
        final syncedLyrics = data['syncedLyrics'] as String?;

        if (plainLyrics != null && plainLyrics.isNotEmpty) {
          // タイムスタンプ付き歌詞をパース
          List<LyricLine>? lines;
          if (syncedLyrics != null && syncedLyrics.isNotEmpty) {
            lines = _parseLRCLyrics(syncedLyrics);
            print('  → タイムスタンプ付き歌詞: ${lines.length}行');
          }

          return LyricsData(
            plainLyrics: plainLyrics,
            syncedLyrics: syncedLyrics,
            lines: lines,
            source: LyricsSource.lrclib,
          );
        }
      } else if (response.statusCode == 404) {
        print('  → LRCLIB: 404 Not Found');
      } else {
        print('  → LRCLIB: Error ${response.statusCode}');
      }
    } catch (e) {
      print('  → LRCLIB: Exception - $e');
    }
    return null;
  }

  /// Apple Music歌詞スニペットから取得
  Future<LyricsData?> _getLyricsFromAppleMusicSnippet({
    required String trackName,
    required String artistName,
    required String developerToken,
  }) async {
    try {
      final query = Uri.encodeComponent('$trackName $artistName');
      final url = 'https://api.music.apple.com/v1/catalog/jp/search?'
          'term=$query&types=songs&limit=1&with=lyrics';

      print('  → Apple Music Snippet URL: $url');

      final response = await http.get(
        Uri.parse(url),
        headers: {'Authorization': 'Bearer $developerToken'},
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final songs = data['results']?['songs']?['data'] as List?;

        if (songs != null && songs.isNotEmpty) {
          final song = songs[0];
          final meta = song['meta'];
          final snippets = meta?['snippets'] as List?;

          if (snippets != null && snippets.isNotEmpty) {
            // 歌詞スニペットを探す
            for (final snippet in snippets) {
              if (snippet['kind'] == 'lyric') {
                final lyricText = snippet['text'] as String;
                print('  → スニペット取得: ${lyricText.length}文字');

                return LyricsData(
                  plainLyrics: lyricText,
                  syncedLyrics: null,
                  lines: null,
                  source: LyricsSource.appleMusicSnippet,
                );
              }
            }
          }
        }
      }

      print('  → Apple Music Snippet: 歌詞なし');
    } catch (e) {
      print('  → Apple Music Snippet: Exception - $e');
    }
    return null;
  }

  /// LRC形式の歌詞をパース
  ///
  /// 形式例: [00:12.50] 歌詞テキスト
  List<LyricLine> _parseLRCLyrics(String lrcText) {
    final lines = <LyricLine>[];
    final regex = RegExp(r'\[(\d+):(\d+\.\d+)\]\s*(.*)');

    for (final line in lrcText.split('\n')) {
      final match = regex.firstMatch(line);
      if (match != null) {
        final minutes = int.parse(match.group(1)!);
        final seconds = double.parse(match.group(2)!);
        final text = match.group(3)!;

        // 空行はスキップ
        if (text.trim().isEmpty) continue;

        final timestampMs = ((minutes * 60 + seconds) * 1000).round();

        lines.add(LyricLine(
          timestampMs: timestampMs,
          text: text,
        ));
      }
    }

    // タイムスタンプ順にソート
    lines.sort((a, b) => a.timestampMs.compareTo(b.timestampMs));

    return lines;
  }

  /// 現在の再生位置に対応する歌詞行を取得
  LyricLine? getCurrentLyricLine(List<LyricLine> lines, int currentPositionMs) {
    if (lines.isEmpty) return null;

    // 現在位置を過ぎた最後の歌詞行を返す
    LyricLine? current;
    for (final line in lines) {
      if (line.timestampMs <= currentPositionMs) {
        current = line;
      } else {
        break;
      }
    }
    return current;
  }

  /// 次の歌詞行を取得
  LyricLine? getNextLyricLine(List<LyricLine> lines, int currentPositionMs) {
    for (final line in lines) {
      if (line.timestampMs > currentPositionMs) {
        return line;
      }
    }
    return null;
  }

  /// 歌詞を指定行数に短縮（歌詞カード表示用）
  String truncateLyrics(String lyrics, {int maxLines = 4}) {
    final lines = lyrics.split('\n');
    if (lines.length <= maxLines) {
      return lyrics;
    }

    return lines.take(maxLines).join('\n');
  }
}

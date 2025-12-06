import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter_dotenv/flutter_dotenv.dart';

/// Musixmatch API サービス
class MusixmatchService {
  static final MusixmatchService _instance = MusixmatchService._internal();
  factory MusixmatchService() => _instance;
  MusixmatchService._internal();

  /// APIキーを取得
  String get _apiKey => dotenv.env['MUSIXMATCH_API_KEY'] ?? '';

  /// 楽曲をマッチング（トラック名とアーティスト名から楽曲を検索）
  Future<int?> matchTrack({
    required String trackName,
    required String artistName,
  }) async {
    if (_apiKey.isEmpty) {
      print('Musixmatch API key is not set');
      return null;
    }

    try {
      final encodedTrack = Uri.encodeComponent(trackName);
      final encodedArtist = Uri.encodeComponent(artistName);

      final url = 'https://api.musixmatch.com/ws/1.1/matcher.track.get'
          '?q_track=$encodedTrack'
          '&q_artist=$encodedArtist'
          '&apikey=$_apiKey';

      final response = await http.get(Uri.parse(url));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final statusCode = data['message']['header']['status_code'];

        if (statusCode == 200) {
          final trackId = data['message']['body']['track']['track_id'] as int;
          return trackId;
        } else {
          print('Musixmatch matcher error: status_code $statusCode');
          return null;
        }
      } else {
        print('Musixmatch HTTP error: ${response.statusCode}');
        return null;
      }
    } catch (e) {
      print('Error matching track: $e');
      return null;
    }
  }

  /// トラックIDから歌詞を取得
  Future<String?> getLyrics({required int trackId}) async {
    if (_apiKey.isEmpty) {
      print('Musixmatch API key is not set');
      return null;
    }

    try {
      final url = 'https://api.musixmatch.com/ws/1.1/track.lyrics.get'
          '?track_id=$trackId'
          '&apikey=$_apiKey';

      final response = await http.get(Uri.parse(url));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final statusCode = data['message']['header']['status_code'];

        if (statusCode == 200) {
          final lyrics = data['message']['body']['lyrics']['lyrics_body'] as String?;

          if (lyrics != null) {
            // Musixmatchの無料プランでは歌詞の最後に著作権表示が含まれるため削除
            return _cleanLyrics(lyrics);
          }
          return null;
        } else {
          print('Musixmatch lyrics error: status_code $statusCode');
          return null;
        }
      } else {
        print('Musixmatch HTTP error: ${response.statusCode}');
        return null;
      }
    } catch (e) {
      print('Error getting lyrics: $e');
      return null;
    }
  }

  /// トラック名とアーティスト名から直接歌詞を取得（便利メソッド）
  Future<String?> getLyricsByTrackInfo({
    required String trackName,
    required String artistName,
  }) async {
    // 1. トラックをマッチング
    final trackId = await matchTrack(
      trackName: trackName,
      artistName: artistName,
    );

    if (trackId == null) {
      print('Could not match track: $trackName by $artistName');
      return null;
    }

    // 2. 歌詞を取得
    final lyrics = await getLyrics(trackId: trackId);
    return lyrics;
  }

  /// 歌詞をクリーンアップ（Musixmatchの著作権表示を削除）
  String _cleanLyrics(String lyrics) {
    // "******* This Lyrics is NOT for Commercial use *******"などの文言を削除
    final lines = lyrics.split('\n');
    final cleanedLines = <String>[];

    for (final line in lines) {
      // 著作権表示や制限に関する行をスキップ
      if (line.contains('This Lyrics is NOT for Commercial use') ||
          line.contains('...') && line.length < 10) {
        continue;
      }
      cleanedLines.add(line);
    }

    return cleanedLines.join('\n').trim();
  }

  /// 歌詞を指定行数に短縮（歌詞カード表示用）
  String truncateLyrics(String lyrics, {int maxLines = 4}) {
    final lines = lyrics.split('\n');
    if (lines.length <= maxLines) {
      return lyrics;
    }

    return lines.take(maxLines).join('\n') + '...';
  }
}

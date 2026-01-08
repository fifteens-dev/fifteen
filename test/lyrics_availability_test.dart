import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_dotenv/flutter_dotenv.dart';

/// 様々な楽曲で歌詞が取得できるかテスト
void main() {
  setUpAll(() async {
    await dotenv.load(fileName: '.env');
  });

  group('Apple Music Lyrics Availability Tests', () {
    late String developerToken;

    setUp(() {
      developerToken = dotenv.env['APPLE_MUSIC_DEVELOPER_TOKEN'] ?? '';
    });

    // テストする楽曲リスト（アーティスト名と曲名）
    final testTracks = [
      {'artist': 'YOASOBI', 'song': '夜に駆ける'},
      {'artist': 'YOASOBI', 'song': 'アイドル'},
      {'artist': '米津玄師', 'song': 'Lemon'},
      {'artist': 'Official髭男dism', 'song': 'Pretender'},
      {'artist': 'あいみょん', 'song': 'マリーゴールド'},
      {'artist': 'Ado', 'song': 'うっせぇわ'},
    ];

    for (var track in testTracks) {
      test('${track['artist']} - ${track['song']} の歌詞取得テスト', () async {
        // 1. 楽曲を検索
        final query = Uri.encodeComponent('${track['song']} ${track['artist']}');
        final searchResponse = await http.get(
          Uri.parse('https://api.music.apple.com/v1/catalog/jp/search?term=$query&types=songs&limit=1'),
          headers: {'Authorization': 'Bearer $developerToken'},
        );

        expect(searchResponse.statusCode, 200);
        final searchData = json.decode(searchResponse.body);
        final songs = searchData['results']['songs']['data'] as List;

        if (songs.isEmpty) {
          print('⚠️  ${track['artist']} - ${track['song']}: 楽曲が見つかりませんでした');
          return;
        }

        final trackId = songs[0]['id'] as String;
        final trackName = songs[0]['attributes']['name'];
        final artistName = songs[0]['attributes']['artistName'];
        print('🎵 Track ID: $trackId ($trackName by $artistName)');

        // 2. 歌詞を取得
        final lyricsResponse = await http.get(
          Uri.parse('https://api.music.apple.com/v1/catalog/jp/songs/$trackId/lyrics'),
          headers: {'Authorization': 'Bearer $developerToken'},
        );

        print('   Lyrics API Status: ${lyricsResponse.statusCode}');

        if (lyricsResponse.statusCode == 200) {
          final lyricsData = json.decode(lyricsResponse.body);
          if (lyricsData['data'] != null && lyricsData['data'].isNotEmpty) {
            final ttml = lyricsData['data'][0]['attributes']['ttml'] as String;

            // TTMLから歌詞を抽出
            final RegExp pTagPattern = RegExp(r'<p[^>]*>(.*?)</p>', dotAll: true);
            final matches = pTagPattern.allMatches(ttml);
            final lyrics = matches.map((match) {
              String line = match.group(1) ?? '';
              line = line.replaceAll(RegExp(r'<[^>]+>'), '');
              return line.trim();
            }).where((line) => line.isNotEmpty).join('\n');

            print('   ✅ 歌詞取得成功（${lyrics.length}文字）');
            print('   歌詞プレビュー（最初の100文字）:');
            print('   ${lyrics.substring(0, lyrics.length > 100 ? 100 : lyrics.length)}...\n');
          } else {
            print('   ⚠️  レスポンスに歌詞データが含まれていません\n');
          }
        } else if (lyricsResponse.statusCode == 404) {
          print('   ⚠️  この楽曲には歌詞データがありません (404)\n');
        } else if (lyricsResponse.statusCode == 400) {
          print('   ⚠️  Bad Request (400) - APIパラメータエラーまたは歌詞非対応\n');
        } else {
          print('   ❌ エラー: ${lyricsResponse.statusCode}\n');
        }
      }, timeout: const Timeout(Duration(seconds: 30)));
    }

    test('歌詞APIのエンドポイント仕様確認', () async {
      // トップチャートから最初の曲を取得
      final chartsResponse = await http.get(
        Uri.parse('https://api.music.apple.com/v1/catalog/jp/charts?types=songs&limit=1'),
        headers: {'Authorization': 'Bearer $developerToken'},
      );

      expect(chartsResponse.statusCode, 200);
      final chartsData = json.decode(chartsResponse.body);
      final songs = chartsData['results']['songs'][0]['data'] as List;

      if (songs.isNotEmpty) {
        final trackId = songs[0]['id'];
        final trackName = songs[0]['attributes']['name'];
        final artistName = songs[0]['attributes']['artistName'];

        print('📊 チャート1位: $trackName by $artistName');
        print('   Track ID: $trackId');

        // 歌詞エンドポイントをテスト
        final lyricsResponse = await http.get(
          Uri.parse('https://api.music.apple.com/v1/catalog/jp/songs/$trackId/lyrics'),
          headers: {'Authorization': 'Bearer $developerToken'},
        );

        print('   Lyrics API Status: ${lyricsResponse.statusCode}');

        if (lyricsResponse.statusCode == 200) {
          print('   ✅ チャート1位の曲は歌詞データを持っています');
        } else {
          print('   ⚠️  チャート1位の曲でも歌詞データが取得できませんでした (${lyricsResponse.statusCode})');
        }
      }
    }, timeout: const Timeout(Duration(seconds: 30)));
  });
}

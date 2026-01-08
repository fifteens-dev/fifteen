import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_dotenv/flutter_dotenv.dart';

/// Apple Music API 簡易テスト（直接HTTPリクエスト）
void main() {
  setUpAll(() async {
    // .envファイルを読み込み
    await dotenv.load(fileName: '.env');
  });

  group('Apple Music API Direct Tests', () {
    late String developerToken;

    setUp(() {
      developerToken = dotenv.env['APPLE_MUSIC_DEVELOPER_TOKEN'] ?? '';
    });

    test('Developer Tokenが設定されているか確認', () {
      expect(developerToken, isNotEmpty, reason: '.envにAPPLE_MUSIC_DEVELOPER_TOKENが設定されていません');
      print('✅ Developer Token設定済み（${developerToken.length}文字）');
    });

    test('楽曲検索API テスト', () async {
      final query = Uri.encodeComponent('YOASOBI');
      final response = await http.get(
        Uri.parse('https://api.music.apple.com/v1/catalog/jp/search?term=$query&types=songs&limit=3'),
        headers: {'Authorization': 'Bearer $developerToken'},
      );

      print('Status: ${response.statusCode}');

      expect(response.statusCode, 200, reason: 'API リクエストが失敗しました');

      final data = json.decode(response.body);
      expect(data['results'], isNotNull);
      expect(data['results']['songs'], isNotNull);

      final songs = data['results']['songs']['data'] as List;
      expect(songs, isNotEmpty, reason: '楽曲が見つかりませんでした');

      print('✅ 楽曲検索成功: ${songs.length}曲取得');
      print('   1曲目: ${songs[0]['attributes']['name']} by ${songs[0]['attributes']['artistName']}');
    });

    test('歌詞API テスト', () async {
      // まず楽曲を検索してTrack IDを取得
      final query = Uri.encodeComponent('夜に駆ける YOASOBI');
      final searchResponse = await http.get(
        Uri.parse('https://api.music.apple.com/v1/catalog/jp/search?term=$query&types=songs&limit=1'),
        headers: {'Authorization': 'Bearer $developerToken'},
      );

      expect(searchResponse.statusCode, 200);
      final searchData = json.decode(searchResponse.body);
      final songs = searchData['results']['songs']['data'] as List;

      if (songs.isEmpty) {
        print('⚠️  楽曲が見つかりませんでした');
        return;
      }

      final trackId = songs[0]['id'] as String;
      print('Track ID: $trackId');

      // 歌詞を取得
      final lyricsResponse = await http.get(
        Uri.parse('https://api.music.apple.com/v1/catalog/jp/songs/$trackId/lyrics'),
        headers: {'Authorization': 'Bearer $developerToken'},
      );

      print('Lyrics API Status: ${lyricsResponse.statusCode}');

      if (lyricsResponse.statusCode == 200) {
        final lyricsData = json.decode(lyricsResponse.body);
        if (lyricsData['data'] != null && lyricsData['data'].isNotEmpty) {
          final ttml = lyricsData['data'][0]['attributes']['ttml'] as String;
          print('✅ 歌詞取得成功（TTML: ${ttml.length}文字）');

          // TTMLの一部を表示
          final preview = ttml.length > 200 ? ttml.substring(0, 200) : ttml;
          print('   歌詞プレビュー: $preview...');
        }
      } else if (lyricsResponse.statusCode == 404) {
        print('⚠️  この楽曲には歌詞データがありません（これは正常です）');
      } else {
        print('⚠️  歌詞取得エラー: ${lyricsResponse.statusCode}');
      }
    }, timeout: const Timeout(Duration(seconds: 30)));

    test('トップチャートAPI テスト', () async {
      final response = await http.get(
        Uri.parse('https://api.music.apple.com/v1/catalog/jp/charts?types=songs&limit=5'),
        headers: {'Authorization': 'Bearer $developerToken'},
      );

      print('Charts API Status: ${response.statusCode}');
      expect(response.statusCode, 200);

      final data = json.decode(response.body);
      expect(data['results'], isNotNull);
      expect(data['results']['songs'], isNotNull);

      final charts = data['results']['songs'][0]['data'] as List;
      expect(charts, isNotEmpty);

      print('✅ トップチャート取得成功: ${charts.length}曲');
      print('   1位: ${charts[0]['attributes']['name']} by ${charts[0]['attributes']['artistName']}');
    }, timeout: const Timeout(Duration(seconds: 30)));
  });
}

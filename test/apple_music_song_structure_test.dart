import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_dotenv/flutter_dotenv.dart';

/// Apple Music Song APIのレスポンス構造を調査
void main() {
  setUpAll(() async {
    await dotenv.load(fileName: '.env');
  });

  group('Apple Music Song Structure Tests', () {
    late String developerToken;

    setUp(() {
      developerToken = dotenv.env['APPLE_MUSIC_DEVELOPER_TOKEN'] ?? '';
    });

    test('Song APIのフル レスポンスを調査', () async {
      // 楽曲を検索
      final query = Uri.encodeComponent('YOASOBI 夜に駆ける');
      final searchResponse = await http.get(
        Uri.parse('https://api.music.apple.com/v1/catalog/jp/search?term=$query&types=songs&limit=1'),
        headers: {'Authorization': 'Bearer $developerToken'},
      );

      expect(searchResponse.statusCode, 200);
      final searchData = json.decode(searchResponse.body);
      final songs = searchData['results']['songs']['data'] as List;
      expect(songs, isNotEmpty);

      final trackId = songs[0]['id'] as String;
      print('=== Track ID: $trackId ===\n');

      // Song詳細を取得（すべてのrelationshipsを含む）
      final songResponse = await http.get(
        Uri.parse('https://api.music.apple.com/v1/catalog/jp/songs/$trackId?include=albums,artists'),
        headers: {'Authorization': 'Bearer $developerToken'},
      );

      expect(songResponse.statusCode, 200);
      final songData = json.decode(songResponse.body);

      // JSONを整形して出力
      final prettyJson = const JsonEncoder.withIndent('  ').convert(songData);
      print('=== Song API Full Response ===');
      print(prettyJson);
      print('\n');

      // attributesとrelationshipsを詳しく調査
      final data = songData['data'][0];
      final attributes = data['attributes'] as Map<String, dynamic>;

      print('=== Available Attributes ===');
      attributes.forEach((key, value) {
        print('  $key: ${value.runtimeType}');
      });
      print('\n');

      if (data['relationships'] != null) {
        print('=== Available Relationships ===');
        (data['relationships'] as Map<String, dynamic>).forEach((key, value) {
          print('  $key: ${value.runtimeType}');
        });
        print('\n');
      }

      // 歌詞関連のフィールドを探す
      final lyricsRelatedKeys = attributes.keys.where((key) =>
        key.toLowerCase().contains('lyric') ||
        key.toLowerCase().contains('text') ||
        key.toLowerCase().contains('caption')
      ).toList();

      if (lyricsRelatedKeys.isNotEmpty) {
        print('✅ 歌詞関連のフィールド発見:');
        for (final key in lyricsRelatedKeys) {
          print('  - $key: ${attributes[key]}');
        }
      } else {
        print('⚠️  歌詞関連のフィールドは見つかりませんでした');
      }
    }, timeout: const Timeout(Duration(seconds: 30)));

    test('異なるincludeパラメータでテスト', () async {
      final query = Uri.encodeComponent('YOASOBI');
      final searchResponse = await http.get(
        Uri.parse('https://api.music.apple.com/v1/catalog/jp/search?term=$query&types=songs&limit=1'),
        headers: {'Authorization': 'Bearer $developerToken'},
      );

      final searchData = json.decode(searchResponse.body);
      final trackId = searchData['results']['songs']['data'][0]['id'] as String;

      // 異なるincludeパラメータを試す
      final includeParams = [
        '',
        'albums',
        'artists',
        'albums,artists',
        'genres',
        'station',
        'music-videos',
      ];

      for (final include in includeParams) {
        final url = include.isEmpty
            ? 'https://api.music.apple.com/v1/catalog/jp/songs/$trackId'
            : 'https://api.music.apple.com/v1/catalog/jp/songs/$trackId?include=$include';

        final response = await http.get(
          Uri.parse(url),
          headers: {'Authorization': 'Bearer $developerToken'},
        );

        print('\n--- include=${include.isEmpty ? "(none)" : include} ---');
        print('Status: ${response.statusCode}');

        if (response.statusCode == 200) {
          final data = json.decode(response.body);
          final relationships = data['data'][0]['relationships'];
          if (relationships != null) {
            print('Relationships: ${(relationships as Map).keys.join(", ")}');
          }
        } else {
          print('Error: ${response.body}');
        }
      }
    }, timeout: const Timeout(Duration(seconds: 60)));

    test('views パラメータでのテスト', () async {
      final query = Uri.encodeComponent('YOASOBI');
      final searchResponse = await http.get(
        Uri.parse('https://api.music.apple.com/v1/catalog/jp/search?term=$query&types=songs&limit=1'),
        headers: {'Authorization': 'Bearer $developerToken'},
      );

      final searchData = json.decode(searchResponse.body);
      final trackId = searchData['results']['songs']['data'][0]['id'] as String;

      // viewsパラメータを試す（ドキュメント化されていない可能性のあるパラメータ）
      final viewsParams = [
        'lyrics',
        'song-lyrics',
        'appears-on',
        'other-versions',
        'featured-albums',
      ];

      for (final view in viewsParams) {
        final response = await http.get(
          Uri.parse('https://api.music.apple.com/v1/catalog/jp/songs/$trackId/$view'),
          headers: {'Authorization': 'Bearer $developerToken'},
        );

        print('\n--- /songs/$trackId/$view ---');
        print('Status: ${response.statusCode}');

        if (response.statusCode == 200) {
          print('✅ Success!');
          final prettyJson = const JsonEncoder.withIndent('  ').convert(json.decode(response.body));
          print(prettyJson);
        } else if (response.statusCode == 404) {
          print('⚠️  Not Found');
        } else {
          print('❌ Error: ${response.statusCode}');
        }
      }
    }, timeout: const Timeout(Duration(seconds: 60)));
  });
}

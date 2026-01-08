import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_dotenv/flutter_dotenv.dart';

/// `with` パラメータを使って歌詞を取得できるかテスト
void main() {
  setUpAll(() async {
    await dotenv.load(fileName: '.env');
  });

  group('Apple Music API - with parameter tests', () {
    late String developerToken;

    setUp(() {
      developerToken = dotenv.env['APPLE_MUSIC_DEVELOPER_TOKEN'] ?? '';
    });

    test('検索APIでwith=lyricsパラメータをテスト', () async {
      final query = Uri.encodeComponent('YOASOBI 夜に駆ける');

      // withパラメータに lyrics を指定
      final searchUrl = 'https://api.music.apple.com/v1/catalog/jp/search'
          '?term=$query'
          '&types=songs'
          '&limit=1'
          '&with=lyrics';

      print('🔍 URL: $searchUrl\n');

      final response = await http.get(
        Uri.parse(searchUrl),
        headers: {'Authorization': 'Bearer $developerToken'},
      );

      print('Status: ${response.statusCode}');

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final prettyJson = const JsonEncoder.withIndent('  ').convert(data);
        print('Response:\n$prettyJson\n');

        // 歌詞フィールドを探す
        final songs = data['results']['songs']['data'] as List;
        if (songs.isNotEmpty) {
          final song = songs[0];
          print('=== Checking for lyrics fields ===');

          if (song['attributes']['lyrics'] != null) {
            print('✅ lyrics フィールド発見!');
            print('内容: ${song['attributes']['lyrics']}');
          } else {
            print('⚠️  lyrics フィールドなし');
          }

          if (song['relationships'] != null && song['relationships']['lyrics'] != null) {
            print('✅ relationships/lyrics フィールド発見!');
            print('内容: ${song['relationships']['lyrics']}');
          } else {
            print('⚠️  relationships/lyrics フィールドなし');
          }
        }
      } else {
        print('❌ Error: ${response.body}');
      }
    }, timeout: const Timeout(Duration(seconds: 30)));

    test('Song詳細APIでextend=lyricsパラメータをテスト', () async {
      // まず楽曲IDを取得
      final query = Uri.encodeComponent('YOASOBI');
      final searchResponse = await http.get(
        Uri.parse('https://api.music.apple.com/v1/catalog/jp/search?term=$query&types=songs&limit=1'),
        headers: {'Authorization': 'Bearer $developerToken'},
      );

      final searchData = json.decode(searchResponse.body);
      final trackId = searchData['results']['songs']['data'][0]['id'] as String;

      print('Track ID: $trackId\n');

      // extendパラメータに lyrics を指定
      final songUrl = 'https://api.music.apple.com/v1/catalog/jp/songs/$trackId?extend=lyrics';

      print('🔍 URL: $songUrl\n');

      final response = await http.get(
        Uri.parse(songUrl),
        headers: {'Authorization': 'Bearer $developerToken'},
      );

      print('Status: ${response.statusCode}');

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final song = data['data'][0];

        print('=== Checking for lyrics fields ===');
        print('All attributes keys: ${(song['attributes'] as Map).keys.join(", ")}\n');

        if (song['attributes']['lyrics'] != null) {
          print('✅ lyrics フィールド発見!');
          print('内容: ${song['attributes']['lyrics']}');
        } else {
          print('⚠️  attributes/lyrics フィールドなし');
        }

        if (song['relationships'] != null && song['relationships']['lyrics'] != null) {
          print('✅ relationships/lyrics フィールド発見!');
          final prettyJson = const JsonEncoder.withIndent('  ').convert(song['relationships']['lyrics']);
          print('内容:\n$prettyJson');
        } else {
          print('⚠️  relationships/lyrics フィールドなし');
        }
      } else {
        print('❌ Error: ${response.body}');
      }
    }, timeout: const Timeout(Duration(seconds: 30)));

    test('includeパラメータでlyricsを指定', () async {
      final query = Uri.encodeComponent('YOASOBI');
      final searchResponse = await http.get(
        Uri.parse('https://api.music.apple.com/v1/catalog/jp/search?term=$query&types=songs&limit=1'),
        headers: {'Authorization': 'Bearer $developerToken'},
      );

      final searchData = json.decode(searchResponse.body);
      final trackId = searchData['results']['songs']['data'][0]['id'] as String;

      final songUrl = 'https://api.music.apple.com/v1/catalog/jp/songs/$trackId?include=lyrics';

      print('🔍 URL: $songUrl\n');

      final response = await http.get(
        Uri.parse(songUrl),
        headers: {'Authorization': 'Bearer $developerToken'},
      );

      print('Status: ${response.statusCode}');

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final prettyJson = const JsonEncoder.withIndent('  ').convert(data);
        print('Response:\n$prettyJson\n');
      } else {
        print('❌ Error: ${response.body}');
      }
    }, timeout: const Timeout(Duration(seconds: 30)));

    test('Songをfetchしてから別リクエストでlyricsを取得', () async {
      final query = Uri.encodeComponent('YOASOBI');
      final searchResponse = await http.get(
        Uri.parse('https://api.music.apple.com/v1/catalog/jp/search?term=$query&types=songs&limit=1'),
        headers: {'Authorization': 'Bearer $developerToken'},
      );

      final searchData = json.decode(searchResponse.body);
      final song = searchData['results']['songs']['data'][0];
      final trackId = song['id'] as String;

      print('Track ID: $trackId');
      print('hasLyrics: ${song['attributes']['hasLyrics']}\n');

      // relationshipsのlyricsエンドポイントがあるか確認
      if (song['relationships'] != null && song['relationships']['lyrics'] != null) {
        final lyricsHref = song['relationships']['lyrics']['href'] as String?;

        if (lyricsHref != null) {
          print('🎵 Lyrics endpoint found: $lyricsHref');

          final lyricsResponse = await http.get(
            Uri.parse('https://api.music.apple.com$lyricsHref'),
            headers: {'Authorization': 'Bearer $developerToken'},
          );

          print('Lyrics Status: ${lyricsResponse.statusCode}');

          if (lyricsResponse.statusCode == 200) {
            print('✅ Success!');
            final lyricsData = json.decode(lyricsResponse.body);
            final prettyJson = const JsonEncoder.withIndent('  ').convert(lyricsData);
            print('Lyrics data:\n$prettyJson');
          } else {
            print('❌ Error: ${lyricsResponse.body}');
          }
        } else {
          print('⚠️  lyrics href not found in relationships');
        }
      } else {
        print('⚠️  No lyrics relationship in song data');
      }
    }, timeout: const Timeout(Duration(seconds: 30)));
  });
}

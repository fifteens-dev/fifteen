import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_dotenv/flutter_dotenv.dart';

/// LRCLIB API の仕様を調査・テスト
void main() {
  setUpAll(() async {
    await dotenv.load(fileName: '.env');
  });

  group('LRCLIB API Tests', () {
    const baseUrl = 'https://lrclib.net/api';
    late String appleDevToken;

    setUp(() {
      appleDevToken = dotenv.env['APPLE_MUSIC_DEVELOPER_TOKEN'] ?? '';
    });

    test('Apple MusicからISRCを取得してLRCLIBで歌詞検索', () async {
      // 1. Apple Music APIから楽曲情報とISRCを取得
      print('=== Step 1: Apple Musicから楽曲情報を取得 ===');
      final query = Uri.encodeComponent('YOASOBI 夜に駆ける');
      final searchResponse = await http.get(
        Uri.parse('https://api.music.apple.com/v1/catalog/jp/search?term=$query&types=songs&limit=1'),
        headers: {'Authorization': 'Bearer $appleDevToken'},
      );

      expect(searchResponse.statusCode, 200);
      final searchData = json.decode(searchResponse.body);
      final song = searchData['results']['songs']['data'][0];

      final trackName = song['attributes']['name'] as String;
      final artistName = song['attributes']['artistName'] as String;
      final isrc = song['attributes']['isrc'] as String;
      final duration = song['attributes']['durationInMillis'] as int;
      final durationSeconds = (duration / 1000).round();

      print('曲名: $trackName');
      print('アーティスト: $artistName');
      print('ISRC: $isrc');
      print('再生時間: ${durationSeconds}秒\n');

      // 2. LRCLIB APIでISRCコード検索を試す
      print('=== Step 2: LRCLIB APIでISRC検索 ===');
      final lrclibUrl = '$baseUrl/get?isrc=$isrc';
      print('URL: $lrclibUrl');

      final lrclibResponse = await http.get(Uri.parse(lrclibUrl));
      print('Status: ${lrclibResponse.statusCode}\n');

      if (lrclibResponse.statusCode == 200) {
        final lyricsData = json.decode(lrclibResponse.body);
        final prettyJson = const JsonEncoder.withIndent('  ').convert(lyricsData);
        print('✅ ISRC検索成功！');
        print('レスポンス:\n$prettyJson\n');

        if (lyricsData['syncedLyrics'] != null) {
          final syncedLyrics = lyricsData['syncedLyrics'] as String;
          print('🎵 タイムスタンプ付き歌詞（最初の10行）:');
          final lines = syncedLyrics.split('\n').take(10);
          for (final line in lines) {
            print('  $line');
          }
          print('');
        }

        if (lyricsData['plainLyrics'] != null) {
          final plainLyrics = lyricsData['plainLyrics'] as String;
          print('📝 プレーン歌詞（最初の200文字）:');
          final preview = plainLyrics.length > 200
              ? plainLyrics.substring(0, 200)
              : plainLyrics;
          print('  $preview...\n');
        }
      } else if (lrclibResponse.statusCode == 404) {
        print('⚠️  この楽曲の歌詞はLRCLIBに登録されていません\n');

        // 3. ISRCで見つからない場合、トラック名+アーティスト名で検索
        print('=== Step 3: トラック名+アーティスト名で検索 ===');
        final fallbackUrl = '$baseUrl/search?'
            'track_name=${Uri.encodeComponent(trackName)}'
            '&artist_name=${Uri.encodeComponent(artistName)}';
        print('URL: $fallbackUrl');

        final fallbackResponse = await http.get(Uri.parse(fallbackUrl));
        print('Status: ${fallbackResponse.statusCode}\n');

        if (fallbackResponse.statusCode == 200) {
          final results = json.decode(fallbackResponse.body) as List;
          if (results.isNotEmpty) {
            print('✅ 検索結果: ${results.length}件');
            final prettyJson = const JsonEncoder.withIndent('  ').convert(results[0]);
            print('最初の結果:\n$prettyJson');
          } else {
            print('⚠️  検索結果なし');
          }
        } else {
          print('❌ 検索失敗: ${fallbackResponse.statusCode}');
        }
      } else {
        print('❌ エラー: ${lrclibResponse.statusCode}');
        print('レスポンス: ${lrclibResponse.body}');
      }
    }, timeout: const Timeout(Duration(seconds: 60)));

    test('複数の人気曲でLRCLIBの網羅性をテスト', () async {
      final testSongs = [
        'YOASOBI アイドル',
        '米津玄師 Lemon',
        'Official髭男dism Pretender',
      ];

      for (final songQuery in testSongs) {
        print('\n=== Testing: $songQuery ===');

        // Apple Musicから検索
        final query = Uri.encodeComponent(songQuery);
        final searchResponse = await http.get(
          Uri.parse('https://api.music.apple.com/v1/catalog/jp/search?term=$query&types=songs&limit=1'),
          headers: {'Authorization': 'Bearer $appleDevToken'},
        );

        if (searchResponse.statusCode != 200) {
          print('❌ Apple Music検索失敗');
          continue;
        }

        final searchData = json.decode(searchResponse.body);
        final songs = searchData['results']['songs']['data'] as List;

        if (songs.isEmpty) {
          print('⚠️  楽曲が見つかりません');
          continue;
        }

        final song = songs[0];
        final trackName = song['attributes']['name'] as String;
        final artistName = song['attributes']['artistName'] as String;
        final isrc = song['attributes']['isrc'] as String;

        print('曲: $trackName by $artistName');
        print('ISRC: $isrc');

        // LRCLIB検索
        final lrclibResponse = await http.get(
          Uri.parse('$baseUrl/get?isrc=$isrc'),
        );

        if (lrclibResponse.statusCode == 200) {
          final data = json.decode(lrclibResponse.body);
          final hasPlain = data['plainLyrics'] != null;
          final hasSynced = data['syncedLyrics'] != null;
          print('✅ LRCLIB: プレーン=${hasPlain ? "○" : "×"}, タイムスタンプ=${hasSynced ? "○" : "×"}');
        } else {
          print('⚠️  LRCLIB: 歌詞なし (${lrclibResponse.statusCode})');
        }
      }
    }, timeout: const Timeout(Duration(seconds: 90)));

    test('LRCLIBのレート制限を確認', () async {
      print('=== レート制限テスト ===');
      print('連続で5回リクエストを送信...\n');

      for (int i = 1; i <= 5; i++) {
        final start = DateTime.now();
        final response = await http.get(
          Uri.parse('$baseUrl/get?track_name=test&artist_name=test'),
        );
        final duration = DateTime.now().difference(start).inMilliseconds;

        print('リクエスト$i: ${response.statusCode} (${duration}ms)');

        if (response.statusCode == 429) {
          print('⚠️  レート制限に到達！');
          print('レスポンス: ${response.body}');
          break;
        }
      }
    }, timeout: const Timeout(Duration(seconds: 60)));

    test('LRCLIB APIのレスポンス構造を詳細調査', () async {
      // 確実に存在する楽曲でテスト
      final response = await http.get(
        Uri.parse('$baseUrl/search?track_name=Shape of You&artist_name=Ed Sheeran'),
      );

      print('Status: ${response.statusCode}');

      if (response.statusCode == 200) {
        final results = json.decode(response.body) as List;
        if (results.isNotEmpty) {
          print('\n=== LRCLIB レスポンスフィールド ===');
          final first = results[0] as Map<String, dynamic>;
          first.forEach((key, value) {
            final valueType = value.runtimeType;
            final preview = value.toString().length > 50
                ? '${value.toString().substring(0, 50)}...'
                : value.toString();
            print('$key ($valueType): $preview');
          });
        }
      }
    }, timeout: const Timeout(Duration(seconds: 30)));
  });
}

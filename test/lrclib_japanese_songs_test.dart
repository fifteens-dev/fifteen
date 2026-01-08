import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_dotenv/flutter_dotenv.dart';

/// 日本語楽曲でLRCLIB APIのカバー率をテスト
void main() {
  setUpAll(() async {
    await dotenv.load(fileName: '.env');
  });

  group('LRCLIB Japanese Songs Coverage Test', () {
    const lrclibBaseUrl = 'https://lrclib.net/api';
    late String appleDevToken;

    setUp(() {
      appleDevToken = dotenv.env['APPLE_MUSIC_DEVELOPER_TOKEN'] ?? '';
    });

    // 人気の日本語楽曲リスト
    final testSongs = [
      // YOASOBI
      {'query': 'YOASOBI 夜に駆ける'},
      {'query': 'YOASOBI アイドル'},
      {'query': 'YOASOBI 群青'},
      {'query': 'YOASOBI 怪物'},

      // 米津玄師
      {'query': '米津玄師 Lemon'},
      {'query': '米津玄師 パプリカ'},
      {'query': '米津玄師 打上花火'},

      // Official髭男dism
      {'query': 'Official髭男dism Pretender'},
      {'query': 'Official髭男dism 宿命'},

      // あいみょん
      {'query': 'あいみょん マリーゴールド'},
      {'query': 'あいみょん 裸の心'},

      // Ado
      {'query': 'Ado うっせぇわ'},
      {'query': 'Ado 唱'},

      // King Gnu
      {'query': 'King Gnu 白日'},

      // LiSA
      {'query': 'LiSA 紅蓮華'},

      // RADWIMPS
      {'query': 'RADWIMPS 前前前世'},
    ];

    test('日本語人気曲でLRCLIBの網羅性をテスト', () async {
      print('\n╔═══════════════════════════════════════════════════════╗');
      print('║    LRCLIB API 日本語楽曲カバー率テスト               ║');
      print('╚═══════════════════════════════════════════════════════╝\n');

      int totalSongs = 0;
      int foundWithPlainLyrics = 0;
      int foundWithSyncedLyrics = 0;
      int notFound = 0;

      final results = <Map<String, dynamic>>[];

      for (final songInfo in testSongs) {
        totalSongs++;
        final query = songInfo['query'] as String;

        try {
          // 1. Apple Music APIから楽曲情報を取得
          final encodedQuery = Uri.encodeComponent(query);
          final searchResponse = await http.get(
            Uri.parse('https://api.music.apple.com/v1/catalog/jp/search?term=$encodedQuery&types=songs&limit=1'),
            headers: {'Authorization': 'Bearer $appleDevToken'},
          );

          if (searchResponse.statusCode != 200) {
            print('❌ [$query] Apple Music検索失敗');
            notFound++;
            results.add({
              'query': query,
              'status': 'apple_music_error',
              'lyrics': false,
            });
            continue;
          }

          final searchData = json.decode(searchResponse.body);
          final songs = searchData['results']['songs']['data'] as List?;

          if (songs == null || songs.isEmpty) {
            print('⚠️  [$query] Apple Musicに見つかりません');
            notFound++;
            results.add({
              'query': query,
              'status': 'not_found_apple_music',
              'lyrics': false,
            });
            continue;
          }

          final song = songs[0];
          final trackName = song['attributes']['name'] as String;
          final artistName = song['attributes']['artistName'] as String;
          final durationMs = song['attributes']['durationInMillis'] as int;
          final durationSec = (durationMs / 1000).round();
          final hasLyricsAppleMusic = song['attributes']['hasLyrics'] as bool? ?? false;

          // 2. LRCLIBで歌詞を検索
          final lrclibUrl = '$lrclibBaseUrl/get?'
              'track_name=${Uri.encodeComponent(trackName)}&'
              'artist_name=${Uri.encodeComponent(artistName)}&'
              'duration=$durationSec';

          final lrclibResponse = await http.get(Uri.parse(lrclibUrl));

          String status;
          String displayName = '$trackName - $artistName';
          bool hasPlain = false;
          bool hasSynced = false;

          if (lrclibResponse.statusCode == 200) {
            final lyricsData = json.decode(lrclibResponse.body);
            hasPlain = lyricsData['plainLyrics'] != null && (lyricsData['plainLyrics'] as String).isNotEmpty;
            hasSynced = lyricsData['syncedLyrics'] != null && (lyricsData['syncedLyrics'] as String).isNotEmpty;

            if (hasPlain) foundWithPlainLyrics++;
            if (hasSynced) foundWithSyncedLyrics++;

            if (hasPlain && hasSynced) {
              status = '✅ 完全（プレーン＋タイムスタンプ）';
              print('✅ $displayName');
              print('   📝 プレーン歌詞: あり');
              print('   🎵 タイムスタンプ付き: あり');

              // 歌詞の最初の2行を表示
              final plainLyrics = lyricsData['plainLyrics'] as String;
              final lines = plainLyrics.split('\n').take(2).toList();
              print('   歌詞冒頭: ${lines.join(" / ")}');
            } else if (hasPlain) {
              status = '⚪ プレーンのみ';
              print('⚪ $displayName');
              print('   📝 プレーン歌詞: あり（タイムスタンプなし）');
            } else {
              status = '⚠️  データ不完全';
              print('⚠️  $displayName');
              print('   データ不完全（空の歌詞）');
            }
          } else if (lrclibResponse.statusCode == 404) {
            status = '❌ 見つからず';
            notFound++;
            print('❌ $displayName');
            print('   LRCLIBにデータなし（Apple Musicにはあり: ${hasLyricsAppleMusic ? "はい" : "いいえ"}）');
          } else {
            status = '❌ エラー';
            notFound++;
            print('❌ $displayName');
            print('   LRCLIB エラー: ${lrclibResponse.statusCode}');
          }

          results.add({
            'query': query,
            'trackName': trackName,
            'artistName': artistName,
            'status': status,
            'hasPlain': hasPlain,
            'hasSynced': hasSynced,
            'appleHasLyrics': hasLyricsAppleMusic,
          });

          print('');

          // レート制限を避けるため少し待機
          await Future.delayed(const Duration(milliseconds: 500));
        } catch (e) {
          print('❌ [$query] エラー: $e\n');
          notFound++;
          results.add({
            'query': query,
            'status': 'error',
            'error': e.toString(),
          });
        }
      }

      // サマリーを表示
      print('\n╔═══════════════════════════════════════════════════════╗');
      print('║                   テスト結果サマリー                   ║');
      print('╚═══════════════════════════════════════════════════════╝\n');
      print('📊 総テスト楽曲数: $totalSongs曲');
      print('✅ プレーン歌詞あり: $foundWithPlainLyrics曲 (${(foundWithPlainLyrics / totalSongs * 100).toStringAsFixed(1)}%)');
      print('🎵 タイムスタンプ付き: $foundWithSyncedLyrics曲 (${(foundWithSyncedLyrics / totalSongs * 100).toStringAsFixed(1)}%)');
      print('❌ 見つからず: $notFound曲 (${(notFound / totalSongs * 100).toStringAsFixed(1)}%)\n');

      // カバー率の判定
      final coverageRate = foundWithPlainLyrics / totalSongs * 100;
      print('【結論】');
      if (coverageRate >= 70) {
        print('✅ LRCLIB APIは日本語楽曲に十分対応しています（カバー率: ${coverageRate.toStringAsFixed(1)}%）');
        print('   投稿フローでの使用を推奨します。');
      } else if (coverageRate >= 40) {
        print('⚠️  LRCLIB APIの日本語楽曲カバー率は中程度です（カバー率: ${coverageRate.toStringAsFixed(1)}%）');
        print('   Apple Music User Token認証との併用を検討してください。');
      } else {
        print('❌ LRCLIB APIの日本語楽曲カバー率は低いです（カバー率: ${coverageRate.toStringAsFixed(1)}%）');
        print('   Apple Music User Token認証の実装を推奨します。');
      }

      print('\n詳細な結果はテスト出力を参照してください。\n');
    }, timeout: const Timeout(Duration(minutes: 5)));

    test('LRCLIB検索の精度をテスト（表記揺れ対応）', () async {
      print('\n=== 表記揺れ対応テスト ===\n');

      final variations = [
        {
          'original': 'YOASOBI',
          'variations': ['yoasobi', 'Yoasobi', 'YOASOBI'],
        },
        {
          'original': 'Official髭男dism',
          'variations': ['Official髭男dism', 'Official HIGE DANdism', 'ヒゲダン'],
        },
      ];

      for (final testCase in variations) {
        print('元の表記: ${testCase['original']}');

        for (final variation in testCase['variations'] as List<String>) {
          final response = await http.get(
            Uri.parse('$lrclibBaseUrl/search?artist_name=${Uri.encodeComponent(variation)}&track_name=test'),
          );

          print('  $variation: ${response.statusCode == 200 ? "検索可能" : "404"}');
        }
        print('');
      }
    }, timeout: const Timeout(Duration(seconds: 30)));
  });
}

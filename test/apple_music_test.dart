import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:fifteen/services/apple_music_service.dart';

/// Apple Music API テスト
void main() {
  setUpAll(() async {
    // .envファイルを読み込み
    await dotenv.load(fileName: '.env');
  });

  group('Apple Music Service Tests', () {
    late AppleMusicService service;

    setUp(() {
      service = AppleMusicService();
    });

    test('Developer Tokenが設定されているか確認', () async {
      final isAuth = await service.isAuthenticated();
      expect(isAuth, true, reason: 'Developer Tokenが設定されていません');
    });

    test('楽曲検索のテスト', () async {
      final tracks = await service.searchTracks('YOASOBI', limit: 5);

      expect(tracks, isNotEmpty, reason: '楽曲が見つかりませんでした');
      expect(tracks.length, lessThanOrEqualTo(5));

      if (tracks.isNotEmpty) {
        final firstTrack = tracks.first;
        expect(firstTrack.trackName, isNotEmpty);
        expect(firstTrack.artistName, isNotEmpty);
        expect(firstTrack.albumImageUrl, isNotEmpty);

        print('✅ 検索成功: ${firstTrack.trackName} by ${firstTrack.artistName}');
      }
    });

    test('歌詞取得のテスト（存在する場合）', () async {
      // まず楽曲を検索
      final tracks = await service.searchTracks('夜に駆ける YOASOBI', limit: 1);

      if (tracks.isNotEmpty) {
        final trackId = tracks.first.trackId;
        print('Track ID: $trackId');

        // 歌詞を取得
        final lyrics = await service.getLyrics(trackId);

        if (lyrics != null) {
          expect(lyrics, isNotEmpty);
          print('✅ 歌詞取得成功（${lyrics.length}文字）');
          print('歌詞の一部: ${lyrics.substring(0, lyrics.length > 100 ? 100 : lyrics.length)}...');
        } else {
          print('⚠️  この楽曲には歌詞データがありません');
        }
      }
    }, timeout: const Timeout(Duration(seconds: 30)));

    test('トップチャート取得のテスト', () async {
      final charts = await service.getTopCharts(limit: 10);

      expect(charts, isNotEmpty, reason: 'チャートが取得できませんでした');
      expect(charts.length, lessThanOrEqualTo(10));

      if (charts.isNotEmpty) {
        print('✅ トップチャート取得成功: ${charts.length}曲');
        print('1位: ${charts.first.trackName} by ${charts.first.artistName}');
      }
    }, timeout: const Timeout(Duration(seconds: 30)));
  });
}

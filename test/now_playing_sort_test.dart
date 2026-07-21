import 'package:flutter_test/flutter_test.dart';
import 'package:fifteen/models/track_model.dart';
import 'package:fifteen/services/now_playing_service.dart';

/// 投稿フローの曲並べ替えロジック（NowPlayingService.orderTracks）のローカル検証。
/// 実機不要。`flutter test test/now_playing_sort_test.dart` で実行できる。
void main() {
  TrackModel t(String name, String artist) => TrackModel(
        trackId: '$name|$artist',
        trackName: name,
        artistName: artist,
        albumImageUrl: '',
      );

  // ユーザーの実ログの並び（Web API 順）と lastPlayedDate。
  final tracks = [
    t('第六感', 'Reol'),
    t('若き血', '慶応義塾ワグネル・ソサィエティー'),
    t('僕は今日も', 'Vaundy'),
    t('偉生人', 'Vaundy'),
    t('タイムパラドックス', 'Vaundy'),
  ];
  final playedAt = <String, DateTime>{
    NowPlayingService.keyForTest('第六感', 'Reol'): DateTime(2022, 3, 28),
    NowPlayingService.keyForTest('若き血', '慶応義塾ワグネル・ソサィエティー'):
        DateTime(2026, 5, 28),
  };
  final now = DateTime(2026, 7, 22);

  test('再生していない時: 実際の最新(僕は今日も)が先頭、古い第六感は末尾', () {
    final ordered = NowPlayingService.orderTracks(
      tracks,
      npKey: null,
      npPlaying: false,
      playedAt: playedAt,
      now: now,
    );
    final names = ordered.map((e) => e.trackName).toList();
    // タイムスタンプ無し(僕は今日も/偉生人/タイムパラドックス)は now 扱いで上位・Web API順維持、
    // タイムスタンプ有りは新しい順(若き血 2026-05 → 第六感 2022)で後ろへ。
    expect(names, ['僕は今日も', '偉生人', 'タイムパラドックス', '若き血', '第六感']);
  });

  test('今聞いている曲がある時: その曲が最優先で先頭', () {
    final ordered = NowPlayingService.orderTracks(
      tracks,
      npKey: NowPlayingService.keyForTest('第六感', 'Reol'),
      npPlaying: true,
      playedAt: playedAt,
      now: now,
    );
    expect(ordered.first.trackName, '第六感');
    expect(ordered.first.isNowPlaying, true);
  });

  test('今聞いている曲がタイムスタンプ無しでも先頭に来る', () {
    final ordered = NowPlayingService.orderTracks(
      tracks,
      npKey: NowPlayingService.keyForTest('タイムパラドックス', 'Vaundy'),
      npPlaying: true,
      playedAt: playedAt,
      now: now,
    );
    expect(ordered.first.trackName, 'タイムパラドックス');
    expect(ordered.first.isNowPlaying, true);
  });
}

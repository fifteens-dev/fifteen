import 'package:flutter_test/flutter_test.dart';
import 'package:fifteen/services/music_memory_cycle_service.dart';

/// JST の壁時計で instant を作る。
DateTime jst(int y, int m, int d, int h, [int min = 0, int s = 0]) =>
    DateTime.utc(y, m, d, h, min, s).subtract(const Duration(hours: 9));

void main() {
  // 10/24 21:00 JST に始まった回。
  final start = jst(2026, 10, 24, 21);

  test('投稿は翌日 20:59:59 まで', () {
    expect(MusicMemoryCycleService.postDeadlineFor(start),
        jst(2026, 10, 25, 20, 59, 59));
  });

  test('写真は 28:00（翌 4:00）まで', () {
    expect(MusicMemoryCycleService.photoDeadlineFor(start), jst(2026, 10, 25, 4));
  });

  test('通知は 25:00（翌 1:00）で止める', () {
    expect(MusicMemoryCycleService.quietFromFor(start), jst(2026, 10, 25, 1));
  });

  test('月またぎでも暦日で数える', () {
    final s = jst(2026, 10, 31, 21, 3);
    expect(MusicMemoryCycleService.photoDeadlineFor(s), jst(2026, 11, 1, 4));
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:fifteen/services/music_memory_cycle_service.dart';

/// 持っている notifiedAt が古いかの判定。
///
/// アプリを開いたまま 21:00 をまたぐと前日のサイクルのまま判定してしまい、
/// 新しい日に投稿できなくなる。取り直す境目をここで押さえる。
///
/// 判定式は ensureFreshNotifiedAt と同じ:
///   次の通知 = その回の締切(JST 24:00) + 21 時間 = 翌日 21:00 JST
void main() {
  DateTime nextFireAfter(DateTime cycleStart) =>
      MusicMemoryCycleService.deadlineFor(cycleStart)
          .add(const Duration(hours: 21));

  bool isStale(DateTime cycleStart, DateTime now) =>
      !now.isBefore(nextFireAfter(cycleStart));

  // JST の時刻を UTC の DateTime で作る
  DateTime jst(int y, int m, int d, int h, [int min = 0]) =>
      DateTime.utc(y, m, d, h, min).subtract(const Duration(hours: 9));

  final cycle = jst(2026, 10, 10, 21); // 10/10 21:00 の通知

  test('次の通知は翌日 21:00', () {
    expect(nextFireAfter(cycle), jst(2026, 10, 11, 21));
  });

  test('同じ夜は古くない', () {
    expect(isStale(cycle, jst(2026, 10, 10, 23)), false);
  });

  test('日付をまたいだ直後も、まだ同じサイクル', () {
    // 24:00 を過ぎても次の通知までは同じサイクル（Late 投稿の時間帯）。
    expect(isStale(cycle, jst(2026, 10, 11, 1)), false);
    expect(isStale(cycle, jst(2026, 10, 11, 20, 59)), false);
  });

  test('翌日 21:00 ちょうどで古くなる', () {
    expect(isStale(cycle, jst(2026, 10, 11, 21)), true);
  });

  test('開いたまま 21:00 をまたいだら取り直す', () {
    expect(isStale(cycle, jst(2026, 10, 11, 21, 30)), true);
  });

  test('何日も開きっぱなしでも古いと分かる', () {
    expect(isStale(cycle, jst(2026, 10, 15, 10)), true);
  });
}

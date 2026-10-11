import 'package:flutter_test/flutter_test.dart';
import 'package:fifteen/services/music_memory_cycle_service.dart';

/// 連続投稿日数の数え方。自分と他人のプロフィールで同じ規則を使う。
void main() {
  // 21:00 を境界に 5 日ぶん。新しい順（days.first が今日）。
  final days = [
    for (var i = 0; i < 5; i++)
      MusicMemoryDayWindow(
        key: '2026-10-${(11 - i).toString().padLeft(2, '0')}',
        start: DateTime(2026, 10, 11 - i, 21),
        end: i == 0 ? null : DateTime(2026, 10, 12 - i, 21),
      ),
  ];

  /// その日のサイクル内（22:00）に投稿した時刻。
  DateTime postOn(int day) => DateTime(2026, 10, day, 22);

  int streak(List<DateTime> at) =>
      MusicMemoryCycleService.streakOf(days: days, postedAt: at);

  test('投稿が無ければ 0', () {
    expect(streak([]), 0);
  });

  test('今日だけ投稿していれば 1', () {
    expect(streak([postOn(11)]), 1);
  });

  test('今日から遡って続いていればその日数', () {
    expect(streak([postOn(11), postOn(10), postOn(9)]), 3);
  });

  test('途切れたらそこで止まる', () {
    // 11, 10 は投稿、9 は無し、8 はある → 2 で止まる
    expect(streak([postOn(11), postOn(10), postOn(8)]), 2);
  });

  test('今日まだ投稿していなくても、昨日までの連続は途切れない', () {
    // 21:00 を過ぎた直後は誰も投稿していない。そこで 0 にすると
    // 毎晩いったん記録が消えたように見える。
    expect(streak([postOn(10), postOn(9)]), 2);
  });

  test('今日も昨日も無ければ 0', () {
    expect(streak([postOn(9), postOn(8)]), 0);
  });

  test('同じ日に 2 回投稿しても 1 日ぶん', () {
    expect(
      streak([DateTime(2026, 10, 11, 21, 30), DateTime(2026, 10, 11, 23, 30)]),
      1,
    );
  });

  test('境界の一覧が無ければ 0', () {
    expect(
      MusicMemoryCycleService.streakOf(days: const [], postedAt: [postOn(11)]),
      0,
    );
  });

  test('21:00 より前の投稿は前日のサイクルに入る', () {
    // 10/11 20:00 は、まだ 10/10 のサイクル（10/10 21:00〜10/11 21:00）。
    expect(streak([DateTime(2026, 10, 11, 20)]), 1);
  });
}

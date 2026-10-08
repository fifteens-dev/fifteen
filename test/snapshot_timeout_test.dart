import 'package:flutter_test/flutter_test.dart';
import 'package:fifteen/models/profile_snapshot.dart';

/// 最終確認画面は、投稿ボタンを押した時点で裏面の集計を「少しだけ」待つ。
/// 回線が詰まって終わらないときに投稿が止まらないこと、そのとき空に落ちて
/// 後追いの集計に任せられることを押さえる。
void main() {
  const wait = Duration(seconds: 3);

  Future<ProfileSnapshot> awaited(Future<ProfileSnapshot>? f) async =>
      await f?.timeout(wait, onTimeout: () => ProfileSnapshot.empty) ??
      ProfileSnapshot.empty;

  test('間に合えば集計結果をそのまま使う', () async {
    final done = Future<ProfileSnapshot>.value(const ProfileSnapshot(
      topArtists: [SnapshotArtist(name: 'Southern All Stars')],
      recentTracks: [],
    ));
    final s = await awaited(done);
    expect(s.isEmpty, false);
    expect(s.topArtists.single.name, 'Southern All Stars');
  });

  test('終わらない集計でも投稿は止まらず、空に落ちる', () async {
    final never = Future<ProfileSnapshot>.delayed(
        const Duration(minutes: 1), () => ProfileSnapshot.empty);
    final sw = Stopwatch()..start();
    final s = await awaited(never);
    sw.stop();
    expect(s.isEmpty, true, reason: '空に落ちれば createPost が後追いで集計する');
    expect(sw.elapsed, lessThan(wait + const Duration(seconds: 1)));
  });

  test('空のスナップショットは「無し」として扱われる', () {
    // createPost は isEmpty を見て、書き込むか後追いに回すかを決める。
    expect(ProfileSnapshot.empty.isEmpty, true);
    expect(
      const ProfileSnapshot(
        topArtists: [],
        recentTracks: [SnapshotTrack(trackName: 'a', artistName: 'b', albumImageUrl: '')],
      ).isEmpty,
      false,
      reason: '投稿する曲が recent choice に入るので、通常は空にならない',
    );
  });
}

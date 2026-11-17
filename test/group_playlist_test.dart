import 'package:fifteen/models/group_model.dart';
import 'package:fifteen/models/group_playlist.dart';
import 'package:fifteen/services/group_playlist_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final group = GroupModel(
    groupId: 'g',
    name: 'サークル同期',
    ownerId: 'a',
    memberIds: const ['a'],
    createdAt: DateTime(2026, 10, 1),
  );
  // 10/19〜10/25 の週。10/26（月）21:00 に届く。
  final playlist = GroupPlaylist(
    groupId: 'g',
    weekKey: '2026-10-19',
    endKey: '2026-10-25',
    deliveredAt: DateTime(2026, 10, 26, 21),
    memberCount: 6,
    dayCount: 7,
    tracks: const [],
  );
  GroupPlaylistEntry entry(DateTime? viewedAt) =>
      GroupPlaylistEntry(group: group, playlist: playlist, viewedAt: viewedAt);

  test('見ていなければ次の月曜 21:00 まで出す', () {
    expect(entry(null).showOnHome(DateTime(2026, 11, 2, 20, 59)), isTrue);
    expect(entry(null).showOnHome(DateTime(2026, 11, 2, 21)), isFalse);
  });

  test('見たら見た日の翌日 21:00 まで出す', () {
    final e = entry(DateTime(2026, 10, 28, 8));
    expect(e.showOnHome(DateTime(2026, 10, 29, 20, 59)), isTrue);
    expect(e.showOnHome(DateTime(2026, 10, 29, 21)), isFalse);
  });

  test('期間の表記', () {
    expect(playlist.rangeLabel, '10/19-10/25');
  });
}

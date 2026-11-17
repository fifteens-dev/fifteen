import 'dart:async';

import 'package:flutter/material.dart';

import '../../models/group_model.dart';
import '../../screens/group_settings_sheet.dart' show GroupIconImage;
import '../../services/group_playlist_service.dart';

/// 自分の全グループの最新のプレイリストを購読しておく。
///
/// ホームの上のストーリーの列と、日付の文言（「先週のプレイリストが
/// 届いています」）に使う。グループが変わったら [update] で張り直す。
class HomePlaylists extends ChangeNotifier {
  final String uid;
  HomePlaylists(this.uid);

  final Map<String, StreamSubscription<GroupPlaylistEntry?>> _subs = {};
  final Map<String, GroupPlaylistEntry?> _entries = {};
  List<GroupModel> _groups = const [];

  /// この画面から開いたもの。見た印が Firestore から戻る前に輪をグレーにする。
  final Set<String> _openedHere = {};

  /// グループの一覧が変わったら呼ぶ。build の中から呼んでよい（その場では通知しない）。
  void update(List<GroupModel> groups) {
    _groups = groups;
    final ids = {for (final g in groups) g.groupId};
    for (final id in _subs.keys.toList()) {
      if (!ids.contains(id)) {
        _subs.remove(id)?.cancel();
        _entries.remove(id);
      }
    }
    for (final g in groups) {
      _subs.putIfAbsent(
        g.groupId,
        () => GroupPlaylistService.instance.watchEntry(g, uid).listen((e) {
          _entries[g.groupId] = e;
          notifyListeners();
        }),
      );
    }
  }

  /// ホームに出すもの（グループの並び順のまま）。
  List<GroupPlaylistEntry> visible(DateTime now) => [
        for (final g in _groups)
          if (_entries[g.groupId] case final e?)
            if (e.showOnHome(now))
              GroupPlaylistEntry(
                group: g,
                playlist: e.playlist,
                viewedAt: e.viewedAt ??
                    (_openedHere.contains(_key(e)) ? DateTime.now() : null),
              ),
      ];

  void markOpened(GroupPlaylistEntry e) {
    if (_openedHere.add(_key(e))) notifyListeners();
  }

  static String _key(GroupPlaylistEntry e) =>
      '${e.group.groupId}:${e.playlist.weekKey}';

  @override
  void dispose() {
    for (final s in _subs.values) {
      s.cancel();
    }
    super.dispose();
  }
}

/// ホームの上のストーリーの列（Figma 6712:12359 の y=158〜272、丸は y=161）。
///
/// 丸の中はグループのアイコン。まだ見ていなければ虹色の輪、見たらグレーの輪。
/// 下にグループ名と「先週の38曲」。
class PlaylistStoryRow extends StatelessWidget {
  final List<GroupPlaylistEntry> entries;
  final void Function(int index) onOpen;

  const PlaylistStoryRow({
    super.key,
    required this.entries,
    required this.onOpen,
  });

  /// 1 つ分の幅（丸の中心の間隔）。
  static const double _pitch = 76;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 114,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.only(left: 11, right: 11),
        itemCount: entries.length,
        itemBuilder: (context, i) => GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => onOpen(i),
          child: SizedBox(
            width: _pitch,
            child: _StoryItem(entry: entries[i]),
          ),
        ),
      ),
    );
  }
}

class _StoryItem extends StatelessWidget {
  final GroupPlaylistEntry entry;
  const _StoryItem({required this.entry});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const SizedBox(height: 3),
        PlaylistRing(
          size: 64,
          viewed: entry.viewed,
          child: GroupIconImage(
            iconIndex: entry.group.iconIndex,
            size: 50,
            radius: 25,
          ),
        ),
        const SizedBox(height: 5),
        Text(
          entry.group.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            fontSize: 11,
            height: 1.2,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          '先週の${entry.playlist.trackCount}曲',
          maxLines: 1,
          style: const TextStyle(
            fontSize: 9,
            height: 1.2,
            color: Color(0xFF9B94A0),
          ),
        ),
      ],
    );
  }
}

/// 虹色（見たらグレー）の輪で囲んだ丸。ホームのストーリーとグループ画面で使う。
class PlaylistRing extends StatelessWidget {
  final double size;
  final bool viewed;
  final Widget child;

  const PlaylistRing({
    super.key,
    required this.size,
    required this.viewed,
    required this.child,
  });

  /// FULL HOUSE の帯と同じ虹色。
  static const Gradient rainbow = SweepGradient(
    colors: [
      Color(0xFFEDB8FE),
      Color(0xFFB4B5F7),
      Color(0xFF7FB3EC),
      Color(0xFF8CC8BD),
      Color(0xFF99DE8F),
      Color(0xFFBED57E),
      Color(0xFFF1C56C),
      Color(0xFFEDB8FE),
    ],
  );

  @override
  Widget build(BuildContext context) {
    final ring = size * 3 / 64;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: viewed ? null : rainbow,
        color: viewed ? const Color(0xFF4A474D) : null,
      ),
      padding: EdgeInsets.all(ring),
      child: Container(
        decoration: const BoxDecoration(
          shape: BoxShape.circle,
          color: Color(0xFF121212),
        ),
        alignment: Alignment.center,
        child: child,
      ),
    );
  }
}

/// 日付の後ろに付ける文言。
String homeDeliveryText(bool hasNewPlaylist) =>
    hasNewPlaylist ? '今日の曲と先週のプレイリストが届いています。' : '今日の曲が届いています';

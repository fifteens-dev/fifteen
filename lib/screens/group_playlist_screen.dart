import 'dart:ui' show ImageFilter;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../models/group_playlist.dart';
import '../services/audio_player_service.dart';
import '../services/group_playlist_service.dart';
import '../services/post_photo_service.dart';
import '../widgets/common/glass_circle_button.dart';
import 'group_settings_sheet.dart' show GroupIconImage;

/// 週のプレイリストをストーリーの形で見せる画面。
///
/// 1 曲ずつ 15 秒のプレビューを流し、終わったら次の曲へ。最後の曲の次は
/// 次のグループのプレイリストへ進む。右側のタップで次、左側で前、
/// 長押しで一時停止、下へのスワイプか × で閉じる。
///
/// 開いたプレイリストには見た印を付ける（[GroupPlaylistService.markViewed]）。
///
/// 見た目は仮（11/17）。Figma 6515:11942 / 6541:11988 / 6718:12553（写真なし）が
/// 取れたら差し替える。
class GroupPlaylistScreen extends StatefulWidget {
  final List<GroupPlaylistEntry> entries;
  final int initialIndex;
  final String uid;

  /// プレイリストを開いたとき（ホームの輪をすぐグレーにする）。
  final void Function(GroupPlaylistEntry entry)? onOpened;

  const GroupPlaylistScreen({
    super.key,
    required this.entries,
    required this.initialIndex,
    required this.uid,
    this.onOpened,
  });

  static Future<void> open(
    BuildContext context, {
    required List<GroupPlaylistEntry> entries,
    required int initialIndex,
    required String uid,
    void Function(GroupPlaylistEntry entry)? onOpened,
  }) {
    if (entries.isEmpty) return Future.value();
    return Navigator.of(context).push(PageRouteBuilder(
      opaque: true,
      transitionDuration: const Duration(milliseconds: 220),
      reverseTransitionDuration: const Duration(milliseconds: 180),
      pageBuilder: (_, __, ___) => GroupPlaylistScreen(
        entries: entries,
        initialIndex: initialIndex,
        uid: uid,
        onOpened: onOpened,
      ),
      transitionsBuilder: (_, anim, __, child) => FadeTransition(
        opacity: anim,
        child: ScaleTransition(
          scale: Tween(begin: 0.96, end: 1.0).animate(anim),
          child: child,
        ),
      ),
    ));
  }

  @override
  State<GroupPlaylistScreen> createState() => _GroupPlaylistScreenState();
}

class _GroupPlaylistScreenState extends State<GroupPlaylistScreen>
    with SingleTickerProviderStateMixin {
  /// 1 曲を見せる長さ（プレビューと同じ 15 秒）。
  static const Duration _perTrack = Duration(seconds: 15);

  final AudioPlayerService _audio = AudioPlayerService();
  late final AnimationController _progress =
      AnimationController(vsync: this, duration: _perTrack)
        ..addStatusListener((s) {
          if (s == AnimationStatus.completed) _next();
        });

  late int _entryIndex =
      widget.initialIndex.clamp(0, widget.entries.length - 1);
  int _trackIndex = 0;

  /// 投稿の写真（postId → URL）。無い・見られないものは null。
  final Map<String, String?> _photos = {};

  GroupPlaylistEntry get _entry => widget.entries[_entryIndex];
  List<GroupPlaylistTrack> get _tracks => _entry.playlist.tracks;
  GroupPlaylistTrack? get _track => _tracks.isEmpty
      ? null
      : _tracks[_trackIndex.clamp(0, _tracks.length - 1)];

  @override
  void initState() {
    super.initState();
    _enterEntry();
  }

  @override
  void dispose() {
    _progress.dispose();
    _audio.stop();
    super.dispose();
  }

  void _enterEntry() {
    final e = _entry;
    GroupPlaylistService.instance
        .markViewed(e.group.groupId, e.playlist.weekKey, widget.uid);
    widget.onOpened?.call(e);
    _startTrack();
  }

  void _startTrack() {
    final t = _track;
    if (t == null) return;
    _progress.forward(from: 0);
    final url = t.track.previewUrl;
    if (url != null && url.isNotEmpty) {
      _audio.playPreview(url, durationSeconds: _perTrack.inSeconds);
    } else {
      _audio.stop();
    }
    _loadPhoto(t);
    // 次の曲の写真も先に引いておく。
    if (_trackIndex + 1 < _tracks.length) _loadPhoto(_tracks[_trackIndex + 1]);
  }

  void _loadPhoto(GroupPlaylistTrack t) {
    if (!t.hasPhoto || _photos.containsKey(t.postId)) return;
    _photos[t.postId] = null;
    PostPhotoService.instance.photoUrl(t.postId).then((url) {
      if (!mounted || url == null) return;
      setState(() => _photos[t.postId] = url);
    });
  }

  void _next() {
    if (_trackIndex + 1 < _tracks.length) {
      setState(() => _trackIndex++);
      _startTrack();
    } else if (_entryIndex + 1 < widget.entries.length) {
      setState(() {
        _entryIndex++;
        _trackIndex = 0;
      });
      _enterEntry();
    } else {
      Navigator.of(context).maybePop();
    }
  }

  void _previous() {
    if (_trackIndex > 0) {
      setState(() => _trackIndex--);
    } else if (_entryIndex > 0) {
      setState(() {
        _entryIndex--;
        _trackIndex = _tracks.length - 1;
      });
    }
    _startTrack();
  }

  void _pause() {
    _progress.stop();
    _audio.pause();
  }

  void _resume() {
    _progress.forward();
    _audio.resume();
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final track = _track;
    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapUp: (d) =>
            d.localPosition.dx < media.size.width / 3 ? _previous() : _next(),
        onLongPressStart: (_) => _pause(),
        onLongPressEnd: (_) => _resume(),
        onVerticalDragEnd: (d) {
          if ((d.primaryVelocity ?? 0) > 300) Navigator.of(context).maybePop();
        },
        child: Stack(
          children: [
            if (track != null) Positioned.fill(child: _background(track)),
            Positioned(
              left: 12,
              right: 12,
              top: media.padding.top + 8,
              child: _progressBars(),
            ),
            Positioned(
              left: 16,
              right: 16,
              top: media.padding.top + 24,
              child: _top(),
            ),
            if (track != null)
              Positioned(
                left: 24,
                right: 24,
                top: media.padding.top + 96,
                bottom: media.padding.bottom + 32,
                child: _trackBody(track),
              ),
          ],
        ),
      ),
    );
  }

  /// ジャケットを大きくぼかして敷く。
  Widget _background(GroupPlaylistTrack t) {
    return Stack(
      fit: StackFit.expand,
      children: [
        ImageFiltered(
          imageFilter: ImageFilter.blur(sigmaX: 40, sigmaY: 40),
          child: CachedNetworkImage(
            imageUrl: t.track.albumImageUrl,
            fit: BoxFit.cover,
            errorWidget: (_, __, ___) => const SizedBox.shrink(),
          ),
        ),
        const ColoredBox(color: Color(0x99000000)),
      ],
    );
  }

  /// 曲ごとの進み具合。曲が多いと細くなりすぎるので、40 曲を超えたら 1 本にする。
  Widget _progressBars() {
    final n = _tracks.length;
    return AnimatedBuilder(
      animation: _progress,
      builder: (context, _) {
        if (n > 40) {
          final v = (_trackIndex + _progress.value) / n;
          return _bar(v);
        }
        return Row(
          children: [
            for (var i = 0; i < n; i++) ...[
              if (i > 0) const SizedBox(width: 3),
              Expanded(
                child: _bar(i < _trackIndex
                    ? 1
                    : i == _trackIndex
                        ? _progress.value
                        : 0),
              ),
            ],
          ],
        );
      },
    );
  }

  Widget _bar(double value) => ClipRRect(
        borderRadius: BorderRadius.circular(2),
        child: LinearProgressIndicator(
          value: value,
          minHeight: 2.5,
          backgroundColor: const Color(0x4DFFFFFF),
          valueColor: const AlwaysStoppedAnimation(Colors.white),
        ),
      );

  Widget _top() {
    final e = _entry;
    return Row(
      children: [
        GroupIconImage(iconIndex: e.group.iconIndex, size: 36, radius: 18),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                e.group.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              Text(
                '先週のプレイリスト　${e.playlist.rangeLabel}　'
                '${_trackIndex + 1}/${_tracks.length}',
                style: const TextStyle(fontSize: 12, color: Color(0xB3FFFFFF)),
              ),
            ],
          ),
        ),
        GlassCircleButton(
          size: 40,
          onTap: () => Navigator.of(context).maybePop(),
          child:
              const Icon(CupertinoIcons.xmark, color: Colors.white, size: 18),
        ),
      ],
    );
  }

  Widget _trackBody(GroupPlaylistTrack t) {
    final photo = _photos[t.postId];
    return Column(
      children: [
        Expanded(
          child: Center(
            child: AspectRatio(
              aspectRatio: photo != null ? 3 / 4 : 1,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    CachedNetworkImage(
                      imageUrl: photo ?? t.track.albumImageUrl,
                      fit: BoxFit.cover,
                      errorWidget: (_, __, ___) =>
                          const ColoredBox(color: Color(0xFF28262B)),
                    ),
                    // 写真のときはジャケットを左下に小さく重ねる。
                    if (photo != null)
                      Positioned(
                        left: 12,
                        bottom: 12,
                        width: 72,
                        height: 72,
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: CachedNetworkImage(
                            imageUrl: t.track.albumImageUrl,
                            fit: BoxFit.cover,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 20),
        Text(
          t.track.trackName,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          t.track.artistName,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 15, color: Color(0xB3FFFFFF)),
        ),
        const SizedBox(height: 16),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircleAvatar(
              radius: 12,
              backgroundColor: const Color(0xFF3A383D),
              backgroundImage: (t.userIconUrl?.isNotEmpty ?? false)
                  ? CachedNetworkImageProvider(t.userIconUrl!)
                  : null,
            ),
            const SizedBox(width: 8),
            Text(
              '${t.username}・${_dayLabel(t.cycleKey)}',
              style: const TextStyle(fontSize: 13, color: Color(0xB3FFFFFF)),
            ),
          ],
        ),
      ],
    );
  }

  /// 'YYYY-MM-DD' → 「10/21（水）」。
  static String _dayLabel(String key) {
    final p = key.split('-').map(int.tryParse).toList();
    if (p.length != 3 || p.contains(null)) return '';
    final d = DateTime(p[0]!, p[1]!, p[2]!);
    const weekdays = ['月', '火', '水', '木', '金', '土', '日'];
    return '${d.month}/${d.day}（${weekdays[d.weekday - 1]}）';
  }
}

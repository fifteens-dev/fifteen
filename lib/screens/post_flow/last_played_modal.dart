import 'dart:ui';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../../constants/profile_fonts.dart';
import '../../models/track_model.dart';
import '../../services/music_service_manager.dart';
import '../vibe_story_preview_screen.dart';
import 'music_memory_modal.dart';

/// 投稿フロー入口の「最後に聴いた曲」モーダル。
///
/// Figma 4838:9890 / Component 136 (プロパティ1=Frame 729) 準拠。
///   - 中央 360×640 のガラスパネル (backdrop-blur 14 + bg #1B1B1B / 0.55)
///   - 角丸 20 / border rgba(255,255,255,0.10)
///   - フェードイン + スケールアップ (0.9→1.0) で表示
///   - ヘッダに「最後に聴いた曲」タイトル + 閉じる X
///   - 中央にカード(音楽サービスの最近再生履歴の先頭 1 件)
///   - **カードを左スワイプ / タップ → 「今日のMusic Memory」カード束モーダルへ遷移**
///   - 「この曲で続ける」ボタンで先頭曲を確定 → 投稿プレビューへ
class LastPlayedModal extends StatefulWidget {
  const LastPlayedModal({super.key});

  static Future<void> open(BuildContext context) {
    return Navigator.of(context).push(
      PageRouteBuilder(
        opaque: false,
        barrierDismissible: true,
        barrierColor: Colors.black.withValues(alpha: 0.45),
        transitionDuration: const Duration(milliseconds: 280),
        reverseTransitionDuration: const Duration(milliseconds: 200),
        pageBuilder: (_, __, ___) => const LastPlayedModal(),
        transitionsBuilder: (_, animation, __, child) {
          final curved = CurvedAnimation(
            parent: animation,
            curve: Curves.easeOutCubic,
            reverseCurve: Curves.easeInCubic,
          );
          return FadeTransition(
            opacity: curved,
            child: ScaleTransition(
              scale: Tween<double>(begin: 0.9, end: 1.0).animate(curved),
              child: child,
            ),
          );
        },
      ),
    );
  }

  @override
  State<LastPlayedModal> createState() => _LastPlayedModalState();
}

class _LastPlayedModalState extends State<LastPlayedModal> {
  final MusicServiceManager _music = MusicServiceManager();
  List<TrackModel> _tracks = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadTracks();
  }

  Future<void> _loadTracks() async {
    try {
      final tracks = await _music.getRecentlyPlayedTracks(limit: 20);
      if (!mounted) return;
      setState(() {
        _tracks = tracks;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  TrackModel? get _topTrack => _tracks.isEmpty ? null : _tracks.first;

  void _confirm() {
    final selected = _topTrack;
    if (selected == null) return;
    Navigator.of(context).pop();
    VibeStoryPreviewScreen.pushWithSlideUp<void>(
      context,
      track: selected,
      isMoodPost: true,
    );
  }

  /// カード左スワイプ or タップ → Music Memory カード束モーダルへ。
  void _goToMusicMemory() {
    if (_tracks.isEmpty) return;
    Navigator.of(context).pop();
    MusicMemoryModal.open(context, tracks: _tracks);
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      type: MaterialType.transparency,
      child: Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => Navigator.of(context).maybePop(),
            ),
          ),
          Center(
            child: SizedBox(
              width: 360,
              height: 640,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(20),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
                  child: _ModalBody(
                    track: _topTrack,
                    loading: _loading,
                    onClose: () => Navigator.of(context).maybePop(),
                    onConfirm: _confirm,
                    onGoToMemory: _goToMusicMemory,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ModalBody extends StatelessWidget {
  final TrackModel? track;
  final bool loading;
  final VoidCallback onClose;
  final VoidCallback onConfirm;
  final VoidCallback onGoToMemory;

  const _ModalBody({
    required this.track,
    required this.loading,
    required this.onClose,
    required this.onConfirm,
    required this.onGoToMemory,
  });

  @override
  Widget build(BuildContext context) {
    final hasTrack = track != null;
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1B1B1B).withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.10),
          width: 1,
        ),
      ),
      child: Stack(
        children: [
          // 左上: 閉じる X (Figma: (21, 30), 32×32)
          Positioned(
            left: 21,
            top: 30,
            width: 32,
            height: 32,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onClose,
              child: Container(
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: Color(0xFF2B2B2B),
                ),
                alignment: Alignment.center,
                child: const Icon(
                  CupertinoIcons.xmark,
                  color: Colors.white,
                  size: 16,
                ),
              ),
            ),
          ),
          // タイトル + 時刻
          const Positioned(
            left: 0,
            right: 0,
            top: 32,
            child: Column(
              children: [
                Text(
                  '最後に聴いた曲',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    fontFamily: kSfProRounded,
                  ),
                ),
                SizedBox(height: 2),
                Text(
                  '最近再生',
                  style: TextStyle(
                    color: Color(0xFFC0C0C0),
                    fontSize: 10,
                    fontFamily: kSfProRounded,
                    height: 2.0,
                  ),
                ),
              ],
            ),
          ),
          // 中央のカード (単一)
          //   タップ or 左スワイプ → Music Memory カード束モーダルへ
          Positioned(
            left: 0,
            right: 0,
            top: 86,
            height: 457,
            child: _SingleTrackCardArea(
              track: track,
              loading: loading,
              onTapOrSwipeLeft: onGoToMemory,
            ),
          ),
          // 「← 左スワイプで曲を変更」ヒント
          Positioned(
            left: 0,
            right: 0,
            top: 552,
            child: Center(
              child: Text(
                '← 左スワイプで曲を変更',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.95),
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  fontFamily: 'SF Pro',
                ),
              ),
            ),
          ),
          // 「この曲で続ける」ボタン
          Positioned(
            left: 50,
            right: 50,
            top: 582,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: hasTrack ? onConfirm : null,
              child: Container(
                height: 42,
                decoration: BoxDecoration(
                  color: hasTrack
                      ? Colors.white
                      : Colors.white.withValues(alpha: 0.55),
                  borderRadius: BorderRadius.circular(36),
                ),
                alignment: Alignment.center,
                child: const Text(
                  'この曲で続ける',
                  style: TextStyle(
                    color: Color(0xFF8D8D8D),
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                    fontFamily: kSfProRounded,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SingleTrackCardArea extends StatefulWidget {
  final TrackModel? track;
  final bool loading;

  /// タップ or 左スワイプで呼ばれる (Music Memory 束モーダルを開く)。
  final VoidCallback onTapOrSwipeLeft;

  const _SingleTrackCardArea({
    required this.track,
    required this.loading,
    required this.onTapOrSwipeLeft,
  });

  @override
  State<_SingleTrackCardArea> createState() => _SingleTrackCardAreaState();
}

class _SingleTrackCardAreaState extends State<_SingleTrackCardArea> {
  double _dragX = 0.0;

  void _onPanUpdate(DragUpdateDetails d) {
    setState(() {
      // 右方向のドラッグは無視(左スワイプのみ意味を持つ)
      _dragX = (_dragX + d.delta.dx).clamp(-200.0, 0.0);
    });
  }

  void _onPanEnd(DragEndDetails d) {
    final vx = d.velocity.pixelsPerSecond.dx;
    if (_dragX < -60 || vx < -600) {
      // 左スワイプ確定 → Music Memory へ
      widget.onTapOrSwipeLeft();
    } else {
      setState(() => _dragX = 0.0);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.loading) {
      return const Center(
        child: CupertinoActivityIndicator(color: Colors.white, radius: 12),
      );
    }
    final track = widget.track;
    if (track == null) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 24),
          child: Text(
            '最近再生した曲がありません',
            style: TextStyle(color: Colors.white70, fontSize: 13),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    // 左スワイプ量に応じた微回転で「めくれ感」を出す
    final rot = (_dragX / 200) * 0.18;
    return Center(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTapOrSwipeLeft,
        onPanUpdate: _onPanUpdate,
        onPanEnd: _onPanEnd,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          transform: Matrix4.identity()
            ..translateByDouble(_dragX, 0.0, 0.0, 1.0)
            ..rotateZ(rot),
          transformAlignment: Alignment.center,
          child: _TrackCard(track: track),
        ),
      ),
    );
  }
}

/// Figma のカード(257×457, radius 15) を近似的にレンダリング。
class _TrackCard extends StatelessWidget {
  final TrackModel track;

  const _TrackCard({required this.track});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 257,
      height: 457,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(15),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.12),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.24),
            blurRadius: 30,
            offset: const Offset(0, 20),
          ),
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.14),
            blurRadius: 80,
            offset: const Offset(0, 50),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (track.albumImageUrl.isNotEmpty)
            CachedNetworkImage(
              imageUrl: track.albumImageUrl,
              fit: BoxFit.cover,
              errorWidget: (_, __, ___) => _placeholder(),
            )
          else
            _placeholder(),
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.transparent,
                    Colors.black.withValues(alpha: 0.65),
                  ],
                  stops: const [0.55, 1.0],
                ),
              ),
            ),
          ),
          Positioned(
            left: 16,
            right: 16,
            bottom: 20,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  track.trackName,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    height: 1.15,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  track.artistName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFFCFCFCF),
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _placeholder() {
    return Container(
      color: const Color(0xFF2A2A2A),
      alignment: Alignment.center,
      child: const Icon(Icons.album, color: Colors.white24, size: 60),
    );
  }
}

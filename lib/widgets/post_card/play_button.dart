import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import '../../services/audio_player_service.dart';
import 'post_card_constants.dart';

/// 再生ボタンウィジェット（アニメーション付き）
class PlayButton extends StatelessWidget {
  final AudioPlayerService audioService;
  final String? previewUrl;
  final AnimationController animationController;
  final Animation<double> scaleAnimation;
  final Animation<double> opacityAnimation;
  final Future<void> Function(bool isPlaying, String? previewUrl) onTap;

  const PlayButton({
    super.key,
    required this.audioService,
    required this.previewUrl,
    required this.animationController,
    required this.scaleAnimation,
    required this.opacityAnimation,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<PlayerState>(
      stream: audioService.playerStateStream,
      builder: (context, snapshot) {
        final isThisTrackPlaying = previewUrl != null &&
            audioService.isPlayingUrl(previewUrl!);

        return GestureDetector(
          onTap: () => onTap(isThisTrackPlaying, previewUrl),
          behavior: HitTestBehavior.opaque,
          child: Container(
            width: PostCardConstants.playButtonSize,
            height: PostCardConstants.playButtonSize,
            color: Colors.transparent,
            child: AnimatedBuilder(
              animation: animationController,
              builder: (context, child) {
                return Opacity(
                  opacity: opacityAnimation.value,
                  child: Transform.scale(
                    scale: scaleAnimation.value,
                    child: Container(
                      width: PostCardConstants.playButtonSize,
                      height: PostCardConstants.playButtonSize,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.black.withValues(
                          alpha: PostCardConstants.playButtonBackgroundOpacity,
                        ),
                        border: Border.all(
                          color: Colors.white,
                          width: PostCardConstants.playButtonBorderWidth,
                        ),
                      ),
                      child: Icon(
                        isThisTrackPlaying ? Icons.pause : Icons.play_arrow,
                        color: Colors.white,
                        size: PostCardConstants.playButtonIconSize,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        );
      },
    );
  }
}

/// 再生ボタンアニメーションを管理するヘルパークラス
class PlayButtonAnimations {
  late final AnimationController controller;
  late final Animation<double> scaleAnimation;
  late final Animation<double> opacityAnimation;

  PlayButtonAnimations(TickerProvider vsync) {
    controller = AnimationController(
      duration: PostCardConstants.playButtonAnimationDuration,
      vsync: vsync,
    );

    // スケールアニメーション（0.5秒で拡大→0.5秒で縮小）
    scaleAnimation = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween<double>(begin: 0.0, end: 1.0)
            .chain(CurveTween(curve: Curves.easeOut)),
        weight: 50,
      ),
      TweenSequenceItem(
        tween: Tween<double>(begin: 1.0, end: 0.0)
            .chain(CurveTween(curve: Curves.easeIn)),
        weight: 50,
      ),
    ]).animate(controller);

    // 不透明度アニメーション（0.5秒で表示→0.5秒でフェードアウト）
    opacityAnimation = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween<double>(begin: 0.0, end: 1.0)
            .chain(CurveTween(curve: Curves.easeOut)),
        weight: 50,
      ),
      TweenSequenceItem(
        tween: Tween<double>(begin: 1.0, end: 0.0)
            .chain(CurveTween(curve: Curves.easeIn)),
        weight: 50,
      ),
    ]).animate(controller);
  }

  void dispose() {
    controller.dispose();
  }

  void play() {
    controller.forward(from: 0.0);
  }
}

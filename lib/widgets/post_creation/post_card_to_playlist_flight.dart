import 'package:flutter/material.dart';

/// 投稿完了時の「カード → プレイリストバー」飛行アニメーション。
///
/// ステージ:
/// - [stageReady]   (0.0-0.2): 投稿カードが中央に大きく表示
/// - [stagePosting] (0.2-0.4): 「投稿中」バナー表示
/// - [stageFlying]  (0.4-0.8): カードが縮小しながらプレイリストバーへ移動
/// - [stageDone]    (0.8-1.0): バーに着地、バナーフェードアウト
///
/// 子ウィジェットを次のように構築する:
/// - [bigCardBuilder]: 中央に表示する大きな投稿カード
/// - [thumbnailBuilder]: バーに着地する小サムネ
///
/// 親が [progress] を 0..1 で渡し、各ステージのアニメーションを進める。
/// 飛行先位置は [targetCenterFinder] が返す Offset（画面座標）。
class PostCardToPlaylistFlight extends StatelessWidget {
  /// 0..1 のアニメーション進捗
  final double progress;

  /// 開始時の中央カードのサイズと位置を返す（自動レイアウトの場合は LayoutBuilder で渡す）
  final Rect startRect;

  /// プレイリストバー上の着地位置（中心座標）
  final Offset targetCenter;
  final double targetSize;

  /// 大きな投稿カードを描画
  final Widget bigCardChild;

  /// サムネイル（バー着地時の小カード）
  final Widget thumbnailChild;

  const PostCardToPlaylistFlight({
    super.key,
    required this.progress,
    required this.startRect,
    required this.targetCenter,
    required this.targetSize,
    required this.bigCardChild,
    required this.thumbnailChild,
  });

  static const double stagePostingStart = 0.2;
  static const double stageFlyStart = 0.4;
  static const double stageDoneStart = 0.8;

  @override
  Widget build(BuildContext context) {
    final flyT = ((progress - stageFlyStart) /
            (stageDoneStart - stageFlyStart))
        .clamp(0.0, 1.0);
    final ease = Curves.easeInOutCubic.transform(flyT);

    // 補間: startRect → 着地位置（targetCenter, targetSize）
    final startCenter = startRect.center;
    final cx = startCenter.dx + (targetCenter.dx - startCenter.dx) * ease;
    final cy = startCenter.dy + (targetCenter.dy - startCenter.dy) * ease;
    final scale = 1.0 + ((targetSize / startRect.width) - 1.0) * ease;

    // bigCard と thumbnail のクロスフェード（後半でサムネに置き換え）
    final cardOpacity = 1.0 - (ease * 0.4); // ぼんやり残す
    final thumbOpacity = ease > 0.6 ? ((ease - 0.6) / 0.4).clamp(0.0, 1.0) : 0.0;

    return Stack(
      children: [
        Positioned(
          left: cx - startRect.width * scale / 2,
          top: cy - startRect.height * scale / 2,
          width: startRect.width * scale,
          height: startRect.height * scale,
          child: Stack(
            fit: StackFit.expand,
            children: [
              Opacity(opacity: cardOpacity, child: bigCardChild),
              Opacity(opacity: thumbOpacity, child: thumbnailChild),
            ],
          ),
        ),
      ],
    );
  }
}

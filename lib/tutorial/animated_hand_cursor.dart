import 'package:flutter/material.dart';

/// アニメーション付き「手指」カーソル。チュートリアル中のジェスチャー誘導に使う。
///
/// バリアント:
/// - [HandCursorVariant.wave]      左右に手を振る（注意喚起）
/// - [HandCursorVariant.tap]       タップを示す（指 + 波紋）
/// - [HandCursorVariant.swipeUp]   上方向スワイプ（指 + 上向き軌跡）
/// - [HandCursorVariant.swipeDown] 下方向スワイプ
///
/// すべてループ再生。サイズはデフォルト 56px、`size` で上書き可。
enum HandCursorVariant { wave, tap, swipeUp, swipeDown }

class AnimatedHandCursor extends StatefulWidget {
  final HandCursorVariant variant;
  final double size;
  final Color color;

  /// アニメーション開始までのディレイ（ループ毎ではなく初回のみ）
  final Duration startDelay;

  /// 1ループの長さ
  final Duration period;

  const AnimatedHandCursor({
    super.key,
    required this.variant,
    this.size = 56,
    this.color = Colors.white,
    this.startDelay = Duration.zero,
    this.period = const Duration(milliseconds: 1400),
  });

  @override
  State<AnimatedHandCursor> createState() => _AnimatedHandCursorState();
}

class _AnimatedHandCursorState extends State<AnimatedHandCursor>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: widget.period);
    if (widget.startDelay == Duration.zero) {
      _controller.repeat();
    } else {
      Future.delayed(widget.startDelay, () {
        if (mounted) _controller.repeat();
      });
    }
  }

  @override
  void didUpdateWidget(covariant AnimatedHandCursor old) {
    super.didUpdateWidget(old);
    if (widget.period != old.period) {
      _controller.duration = widget.period;
      if (_controller.isAnimating) _controller.repeat();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        switch (widget.variant) {
          case HandCursorVariant.wave:
            return _buildWave();
          case HandCursorVariant.tap:
            return _buildTap();
          case HandCursorVariant.swipeUp:
            return _buildSwipe(direction: -1);
          case HandCursorVariant.swipeDown:
            return _buildSwipe(direction: 1);
        }
      },
    );
  }

  /// 👋 を回転で揺らす
  Widget _buildWave() {
    final t = _controller.value;
    final angle = 0.35 * (t < 0.5 ? (t * 4 - 1) : (3 - t * 4));
    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: Transform.rotate(
        angle: angle,
        child: Center(
          child: Text(
            '👋',
            style: TextStyle(fontSize: widget.size * 0.85),
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );
  }

  /// タップ: 指の周りに波紋が広がる
  Widget _buildTap() {
    final t = _controller.value;
    // 0..0.5: 波紋拡大
    // 0.5..1.0: 指が縮む（タップ感）
    final ripple = (t * 2).clamp(0.0, 1.0);
    final fingerScale = t < 0.5 ? 1.0 : 0.85 + (t - 0.5) * 0.3;
    return SizedBox(
      width: widget.size * 1.6,
      height: widget.size * 1.6,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // 波紋
          Opacity(
            opacity: (1 - ripple) * 0.7,
            child: Container(
              width: widget.size * 1.6 * ripple,
              height: widget.size * 1.6 * ripple,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: widget.color, width: 2),
              ),
            ),
          ),
          // 指
          Transform.scale(
            scale: fingerScale,
            child: Text(
              '👆',
              style: TextStyle(fontSize: widget.size * 0.9),
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );
  }

  /// 上下スワイプ: 指が direction(±1) 方向に動く + 軌跡矢印
  Widget _buildSwipe({required int direction}) {
    final t = _controller.value;
    // 0..0.4: フェードイン + 移動開始
    // 0.4..0.7: 移動メイン
    // 0.7..1.0: フェードアウト
    final progress = Curves.easeInOut.transform(t.clamp(0.0, 1.0));
    final translateY = direction * (50 * progress - 10);
    double opacity;
    if (t < 0.2) {
      opacity = t / 0.2;
    } else if (t < 0.8) {
      opacity = 1.0;
    } else {
      opacity = (1.0 - t) / 0.2;
    }

    return SizedBox(
      width: widget.size * 1.4,
      height: widget.size * 2.2,
      child: Opacity(
        opacity: opacity.clamp(0.0, 1.0),
        child: Stack(
          alignment: Alignment.center,
          children: [
            // 軌跡矢印
            Positioned(
              top: direction < 0 ? widget.size * 0.2 : null,
              bottom: direction > 0 ? widget.size * 0.2 : null,
              child: Icon(
                direction < 0
                    ? Icons.keyboard_arrow_up_rounded
                    : Icons.keyboard_arrow_down_rounded,
                color: widget.color.withValues(alpha: 0.85),
                size: widget.size * 0.7,
              ),
            ),
            // 指
            Transform.translate(
              offset: Offset(0, translateY),
              child: Text(
                '👆',
                style: TextStyle(fontSize: widget.size * 0.9),
                textAlign: TextAlign.center,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

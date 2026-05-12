import 'package:flutter/material.dart';

import 'animated_hand_cursor.dart';

/// コーチマーク（チュートリアル誘導オーバーレイ）の表示形式。
enum CoachmarkPlacement {
  /// 画面中央
  center,

  /// 指定した [target] のすぐ上
  aboveTarget,

  /// 指定した [target] のすぐ下
  belowTarget,
}

/// アプリ画面の上に重ねる誘導オーバーレイ。
///
/// 用途:
/// - ホーム画面で「楽曲をVibeに追加」ボタンを案内
/// - Vibeプレイリスト画面で「上にスワイプしてください」を案内
///
/// 特徴:
/// - 半透明ディムでフォーカスを誘導しつつ、タップは下層にスルーする (`IgnorePointer`)
/// - [target] を指定すると、その widget の位置に手指アニメ + ヒントテキストを配置
/// - [target] が null の場合は画面中央
class TutorialCoachmark extends StatefulWidget {
  /// 表示の有効/無効
  final bool active;

  /// 誘導テキスト
  final String text;

  /// サブテキスト（小さめ、補足）
  final String? subText;

  /// 手指アニメのバリアント
  final HandCursorVariant handVariant;

  /// 誘導対象 widget の Key（位置取得用）。null なら画面中央。
  final GlobalKey? target;

  /// テキスト位置。target を基準に上下の位置を決める。
  final CoachmarkPlacement placement;

  /// 背景ディムの強さ（0.0..1.0）
  final double dimOpacity;

  /// 手指のサイズ
  final double handSize;

  /// テキスト色
  final Color textColor;

  const TutorialCoachmark({
    super.key,
    required this.active,
    required this.text,
    this.subText,
    this.handVariant = HandCursorVariant.tap,
    this.target,
    this.placement = CoachmarkPlacement.aboveTarget,
    this.dimOpacity = 0.55,
    this.handSize = 56,
    this.textColor = Colors.white,
  });

  @override
  State<TutorialCoachmark> createState() => _TutorialCoachmarkState();
}

class _TutorialCoachmarkState extends State<TutorialCoachmark>
    with SingleTickerProviderStateMixin {
  late final AnimationController _fade;

  Offset? _targetCenter;
  Size? _targetSize;

  @override
  void initState() {
    super.initState();
    _fade = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 350),
    );
    if (widget.active) _fade.forward();
    WidgetsBinding.instance.addPostFrameCallback((_) => _measure());
  }

  @override
  void didUpdateWidget(covariant TutorialCoachmark old) {
    super.didUpdateWidget(old);
    if (widget.active != old.active) {
      if (widget.active) {
        _fade.forward();
      } else {
        _fade.reverse();
      }
    }
    if (widget.target != old.target) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _measure());
    }
  }

  @override
  void dispose() {
    _fade.dispose();
    super.dispose();
  }

  void _measure() {
    if (!mounted || widget.target == null) return;
    final ctx = widget.target!.currentContext;
    if (ctx == null) return;
    final box = ctx.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return;
    final globalCenter = box.localToGlobal(
      Offset(box.size.width / 2, box.size.height / 2),
    );
    if (_targetCenter != globalCenter || _targetSize != box.size) {
      setState(() {
        _targetCenter = globalCenter;
        _targetSize = box.size;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.active && _fade.value == 0) return const SizedBox.shrink();

    return AnimatedBuilder(
      animation: _fade,
      builder: (context, _) {
        return IgnorePointer(
          child: Opacity(
            opacity: _fade.value,
            child: Stack(
              fit: StackFit.expand,
              children: [
                // 背景ディム
                ColoredBox(
                  color: Colors.black.withValues(alpha: widget.dimOpacity),
                ),
                // テキスト + 手指
                Positioned.fromRect(
                  rect: _calculateContentRect(context),
                  child: _buildContent(),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Rect _calculateContentRect(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;
    const contentH = 200.0;
    const horizontalMargin = 24.0;

    if (_targetCenter == null || _targetSize == null) {
      return Rect.fromCenter(
        center: Offset(screenSize.width / 2, screenSize.height / 2),
        width: screenSize.width - horizontalMargin * 2,
        height: contentH,
      );
    }

    final size = _targetSize!;
    double top;
    switch (widget.placement) {
      case CoachmarkPlacement.center:
        return Rect.fromCenter(
          center: Offset(screenSize.width / 2, screenSize.height / 2),
          width: screenSize.width - horizontalMargin * 2,
          height: contentH,
        );
      case CoachmarkPlacement.aboveTarget:
        top = (_targetCenter!.dy - size.height / 2) - contentH - 8;
        if (top < MediaQuery.of(context).padding.top + 16) {
          top = MediaQuery.of(context).padding.top + 16;
        }
        break;
      case CoachmarkPlacement.belowTarget:
        top = (_targetCenter!.dy + size.height / 2) + 8;
        if (top + contentH > screenSize.height - 32) {
          top = screenSize.height - contentH - 32;
        }
        break;
    }

    return Rect.fromLTWH(
      horizontalMargin,
      top,
      screenSize.width - horizontalMargin * 2,
      contentH,
    );
  }

  Widget _buildContent() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        AnimatedHandCursor(
          variant: widget.handVariant,
          size: widget.handSize,
          color: widget.textColor,
        ),
        const SizedBox(height: 12),
        Text(
          widget.text,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: widget.textColor,
            fontSize: 16,
            fontWeight: FontWeight.w700,
            shadows: const [
              Shadow(
                color: Colors.black87,
                blurRadius: 8,
                offset: Offset(0, 2),
              ),
            ],
          ),
        ),
        if (widget.subText != null) ...[
          const SizedBox(height: 6),
          Text(
            widget.subText!,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: widget.textColor.withValues(alpha: 0.85),
              fontSize: 12,
              fontWeight: FontWeight.w400,
              shadows: const [
                Shadow(
                  color: Colors.black87,
                  blurRadius: 6,
                  offset: Offset(0, 1),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

import 'package:flutter/material.dart';
import '../models/post_model.dart';

/// 投稿フロー末尾に表示される公開範囲トグル（全体 / フォロワーのみ）。
///
/// Campus Vibe トグルバーと同じパターン:
/// - 背景 PNG は固定
/// - 白いサムが左右をスライド（AnimationController で位置を Tween）
/// - 各サイドの icon/text は CrossFade で dark/light を切り替え
///
/// Figma 基準: 178×31。
class AudienceToggleBar extends StatelessWidget {
  /// 現在の選択（[PostAudience.public] / [PostAudience.followers]）
  final String audience;
  final ValueChanged<String> onChanged;

  const AudienceToggleBar({
    super.key,
    required this.audience,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return _AudienceToggle(
      isPublic: audience == PostAudience.public,
      onChanged: (isPublic) =>
          onChanged(isPublic ? PostAudience.public : PostAudience.followers),
    );
  }
}

class _AudienceToggle extends StatefulWidget {
  final bool isPublic;
  final ValueChanged<bool> onChanged;

  const _AudienceToggle({
    required this.isPublic,
    required this.onChanged,
  });

  @override
  State<_AudienceToggle> createState() => _AudienceToggleState();
}

class _AudienceToggleState extends State<_AudienceToggle>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _thumbPosition;
  late final Animation<double> _thumbWidth;

  // 素材実寸（4×→1×）: 背景 564×124 → 141×31
  static const double _w = 141;
  static const double _h = 31;

  // サムは状態ごとに幅が違う（ラベル幅に合わせて、Campus Vibe と同パターン）。
  // 左（全体）: 240×116 → 60×29  / 右（フォロワー）: 316×116 → 79×29
  static const double _leftW = 60 / _w;
  static const double _rightW = 79 / _w;
  static const double _thumbH = 29 / _h;
  static const double _thumbY = 1 / _h;
  // 両端から 1px 余白を取って配置
  static const double _leftX = 1 / _w;
  static const double _rightX = 1.0 - _rightW - (1 / _w);

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 250),
      value: widget.isPublic ? 0.0 : 1.0,
    );
    _thumbPosition = Tween<double>(begin: _leftX, end: _rightX)
        .animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));
    _thumbWidth = Tween<double>(begin: _leftW, end: _rightW)
        .animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));
  }

  @override
  void didUpdateWidget(covariant _AudienceToggle oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.isPublic != widget.isPublic) {
      if (widget.isPublic) {
        _controller.reverse();
      } else {
        _controller.forward();
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: _w,
      height: _h,
      child: GestureDetector(
        onTap: () => widget.onChanged(!widget.isPublic),
        child: Stack(
          children: [
            // 背景
            Positioned.fill(
              child: Image.asset(
                'assets/icons/audience_toggle_bg.png',
                fit: BoxFit.fill,
              ),
            ),
            // スライドする白いサム（左右で幅が違うので Tween で補間 + 画像も CrossFade で差し替え）
            AnimatedBuilder(
              animation: _controller,
              builder: (context, _) {
                return Positioned(
                  left: _w * _thumbPosition.value,
                  top: _h * _thumbY,
                  width: _w * _thumbWidth.value,
                  height: _h * _thumbH,
                  child: AnimatedCrossFade(
                    duration: const Duration(milliseconds: 200),
                    crossFadeState: widget.isPublic
                        ? CrossFadeState.showFirst
                        : CrossFadeState.showSecond,
                    firstChild: Image.asset(
                      'assets/icons/audience_toggle_thumb_left.png',
                      fit: BoxFit.fill,
                    ),
                    secondChild: Image.asset(
                      'assets/icons/audience_toggle_thumb_right.png',
                      fit: BoxFit.fill,
                    ),
                  ),
                );
              },
            ),
            // 左セクション（地球 + "全体"）— 左サムの幅 60px に揃えてセンタリング
            Positioned(
              left: 0,
              top: 0,
              bottom: 0,
              width: 1 + (_w * _leftW),
              child: Center(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    AnimatedCrossFade(
                      duration: const Duration(milliseconds: 200),
                      crossFadeState: widget.isPublic
                          ? CrossFadeState.showFirst
                          : CrossFadeState.showSecond,
                      firstChild: Image.asset(
                        'assets/icons/audience_globe_dark.png',
                        width: 16,
                        height: 16,
                      ),
                      secondChild: Image.asset(
                        'assets/icons/audience_globe_light.png',
                        width: 16,
                        height: 16,
                      ),
                    ),
                    const SizedBox(width: 4),
                    AnimatedDefaultTextStyle(
                      duration: const Duration(milliseconds: 200),
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        color: widget.isPublic
                            ? const Color(0xFF1F1F1F)
                            : Colors.white,
                        decoration: TextDecoration.none,
                      ),
                      child: const Text('全体'),
                    ),
                  ],
                ),
              ),
            ),
            // 右セクション（鍵 + "フォロワー"）— 右サムの幅 79px に揃えてセンタリング
            Positioned(
              right: 0,
              top: 0,
              bottom: 0,
              width: 1 + (_w * _rightW),
              child: Center(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    AnimatedCrossFade(
                      duration: const Duration(milliseconds: 200),
                      crossFadeState: widget.isPublic
                          ? CrossFadeState.showFirst
                          : CrossFadeState.showSecond,
                      firstChild: Image.asset(
                        'assets/icons/audience_lock_light.png',
                        width: 12,
                        height: 16,
                      ),
                      secondChild: Image.asset(
                        'assets/icons/audience_lock_dark.png',
                        width: 12,
                        height: 16,
                      ),
                    ),
                    const SizedBox(width: 4),
                    AnimatedDefaultTextStyle(
                      duration: const Duration(milliseconds: 200),
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        color: widget.isPublic
                            ? Colors.white
                            : const Color(0xFF1F1F1F),
                        decoration: TextDecoration.none,
                      ),
                      child: const Text('フォロワー'),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

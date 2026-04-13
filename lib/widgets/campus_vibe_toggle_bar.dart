import 'package:flutter/material.dart';

/// 投稿フロー末尾に表示される Campus Vibe 参加トグルバー。
/// PNG画像素材を使用したアニメーション付きカスタムトグル。
///
/// Figma基準サイズ: 178×31 px（PNGアセットは4×解像度）
/// [participating] が true = 左（Campus Vibeに公開）/ false = 右（フォロワー）
class CampusVibeToggleBar extends StatelessWidget {
  final String university;
  final bool participating;
  final ValueChanged<bool> onChanged;

  const CampusVibeToggleBar({
    super.key,
    required this.university,
    required this.participating,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return _CampusVibeToggle(
      isCampusVibe: participating,
      onChanged: onChanged,
    );
  }
}

class _CampusVibeToggle extends StatefulWidget {
  final bool isCampusVibe;
  final ValueChanged<bool> onChanged;

  const _CampusVibeToggle({
    required this.isCampusVibe,
    required this.onChanged,
  });

  @override
  State<_CampusVibeToggle> createState() => _CampusVibeToggleState();
}

class _CampusVibeToggleState extends State<_CampusVibeToggle>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _thumbPosition;
  late final Animation<double> _thumbWidth;

  // Figma基準 178×31、PNGは4倍（712×124）
  static const double _w = 178;
  static const double _h = 31;

  // サム位置・幅（Figma基準）
  // 左サム: x=1, w=107 / 右サム: x=108, w=69
  static const double _leftX = 1 / _w;
  static const double _leftW = 107 / _w;
  static const double _rightW = 69 / _w;
  static const double _rightX = 1.0 - _rightW - (1 / _w);
  static const double _thumbY = 1 / _h;
  static const double _thumbH = 29 / _h;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 250),
      value: widget.isCampusVibe ? 0.0 : 1.0,
    );
    _thumbPosition = Tween<double>(begin: _leftX, end: _rightX)
        .animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));
    _thumbWidth = Tween<double>(begin: _leftW, end: _rightW)
        .animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));
  }

  @override
  void didUpdateWidget(covariant _CampusVibeToggle oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.isCampusVibe != widget.isCampusVibe) {
      if (widget.isCampusVibe) {
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
        onTap: () => widget.onChanged(!widget.isCampusVibe),
        child: Stack(
          children: [
            // 背景
            Positioned.fill(
              child: Image.asset(
                'assets/icons/cv_toggle_bg.png',
                fit: BoxFit.fill,
              ),
            ),
            // アニメーションするサム（白いピル）
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
                    crossFadeState: widget.isCampusVibe
                        ? CrossFadeState.showFirst
                        : CrossFadeState.showSecond,
                    firstChild: Image.asset(
                      'assets/icons/cv_toggle_thumb_left.png',
                      fit: BoxFit.fill,
                    ),
                    secondChild: Image.asset(
                      'assets/icons/cv_toggle_thumb_right.png',
                      fit: BoxFit.fill,
                    ),
                  ),
                );
              },
            ),
            // 左側コンテンツ（地球アイコン + テキスト）
            Positioned(
              left: 7,
              top: 0,
              bottom: 0,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  AnimatedCrossFade(
                    duration: const Duration(milliseconds: 200),
                    crossFadeState: widget.isCampusVibe
                        ? CrossFadeState.showFirst
                        : CrossFadeState.showSecond,
                    firstChild: Image.asset(
                      'assets/icons/cv_globe_dark.png',
                      width: 16,
                      height: 16,
                    ),
                    secondChild: Image.asset(
                      'assets/icons/cv_globe_light.png',
                      width: 16,
                      height: 16,
                    ),
                  ),
                  const SizedBox(width: 3),
                  AnimatedDefaultTextStyle(
                    duration: const Duration(milliseconds: 200),
                    style: TextStyle(
                      fontSize: 8,
                      fontWeight: FontWeight.w600,
                      color: widget.isCampusVibe
                          ? const Color(0xFF1F1F1F)
                          : Colors.white,
                      decoration: TextDecoration.none,
                    ),
                    child: const Text('Campus Vibeに公開'),
                  ),
                ],
              ),
            ),
            // 右側コンテンツ（鍵アイコン + テキスト）
            Positioned(
              right: 8,
              top: 0,
              bottom: 0,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  AnimatedCrossFade(
                    duration: const Duration(milliseconds: 200),
                    crossFadeState: widget.isCampusVibe
                        ? CrossFadeState.showFirst
                        : CrossFadeState.showSecond,
                    firstChild: Image.asset(
                      'assets/icons/cv_lock_light.png',
                      width: 12,
                      height: 16,
                    ),
                    secondChild: Image.asset(
                      'assets/icons/cv_lock_dark.png',
                      width: 12,
                      height: 16,
                    ),
                  ),
                  const SizedBox(width: 3),
                  AnimatedDefaultTextStyle(
                    duration: const Duration(milliseconds: 200),
                    style: TextStyle(
                      fontSize: 8,
                      fontWeight: FontWeight.w600,
                      color: widget.isCampusVibe
                          ? Colors.white
                          : const Color(0xFF1F1F1F),
                      decoration: TextDecoration.none,
                    ),
                    child: const Text('フォロワー'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

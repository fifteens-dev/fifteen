import 'package:flutter/material.dart';

/// 「写真を追加する」バー（Figma 5858-11628）。
///
/// 自分の投稿カードに出す。写真は 24:00 までしか足せないので、それを過ぎたら
/// 呼び出し側でこのバーごと消す。
class AddPhotoBar extends StatelessWidget {
  final VoidCallback? onTap;

  /// バーの色。カードのテーマに合わせて呼び出し側が渡す。
  final Color background;

  /// 文字色。
  final Color foreground;

  /// 文言。null なら「写真を追加する」。
  /// 既に選んだあとは「写真を変更する」などに差し替える。
  final String? label;

  const AddPhotoBar({
    super.key,
    required this.onTap,
    this.background = const Color(0xFFB0C266),
    this.foreground = Colors.black,
    this.label,
  });

  /// カード本体の色からバーの色を作る。
  ///
  /// Figma ではカードが #C9DD77、バーが #B0C266。同じ色相のまま明度を
  /// 0.087 下げ、彩度を 0.72 倍したものにあたる（計算すると一致する）。
  /// カードの色はアルバムごとに変わるので、色を直に持たずこの関係で作る。
  static Color backgroundFor(Color cardColor) {
    final hsl = HSLColor.fromColor(cardColor);
    return hsl
        .withLightness((hsl.lightness - 0.087).clamp(0.0, 1.0))
        .withSaturation((hsl.saturation * 0.72).clamp(0.0, 1.0))
        .toColor();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        height: 43,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(29),
        ),
        child: Text(
          label ?? '写真を追加する',
          style: TextStyle(
            color: foreground,
            fontSize: 15,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';

/// コピーアイコン（2 枚の紙が重なった形）。
///
/// 奥の 1 枚を左上に、手前の 1 枚を右下にずらして重ねている。手前の塗りは
/// 置く場所の背景と同じ色にする必要がある。透明にすると奥の枠線が透けて
/// 「重なっている」ように見えないため。
class CopyIcon extends StatelessWidget {
  /// 手前の紙の塗り。**置く場所の背景色**を渡す。
  final Color background;

  /// 枠線の色。
  final Color color;

  /// 全体の大きさ。中の紙はこれに比例する。
  final double size;

  const CopyIcon({
    super.key,
    required this.background,
    this.color = Colors.white,
    this.size = 20,
  });

  @override
  Widget build(BuildContext context) {
    // 20 のときに 14×16 だった比率をそのまま保つ。
    final w = size * 0.7;
    final h = size * 0.8;
    final border = size * 0.075;

    Widget sheet({required bool filled}) => Container(
          width: w,
          height: h,
          decoration: BoxDecoration(
            color: filled ? background : null,
            border: Border.all(color: color, width: border),
            borderRadius: BorderRadius.circular(size * 0.1),
          ),
        );

    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        children: [
          Positioned(left: 0, top: 0, child: sheet(filled: false)),
          Positioned(right: 0, bottom: 0, child: sheet(filled: true)),
        ],
      ),
    );
  }
}

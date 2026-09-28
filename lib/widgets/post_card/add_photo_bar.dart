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

  const AddPhotoBar({
    super.key,
    required this.onTap,
    this.background = const Color(0xFFB0C266),
    this.foreground = Colors.black,
  });

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
          '写真を追加する',
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

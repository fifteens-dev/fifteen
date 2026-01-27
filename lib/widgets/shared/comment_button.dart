import 'package:flutter/material.dart';
import '../../constants/post_card_constants.dart';
import '../../models/post_theme.dart';

/// 共有コメントボタンウィジェット
/// 投稿カードの下部に表示されるコメント入力ボタン
class CommentButton extends StatelessWidget {
  /// ボタンの背景色（テーマから取得）
  final Color? backgroundColor;

  /// テキストの色
  final Color textColor;

  /// アイコンの色
  final Color iconColor;

  /// タップ時のコールバック
  final VoidCallback? onTap;

  /// ボタンのテキスト
  final String text;

  /// PostThemeを使用する場合のコンストラクタ
  const CommentButton({
    super.key,
    this.backgroundColor,
    this.textColor = Colors.white,
    this.iconColor = Colors.white,
    this.onTap,
    this.text = 'コメントする',
  });

  /// PostThemeから生成するファクトリコンストラクタ
  factory CommentButton.fromTheme({
    Key? key,
    required PostTheme theme,
    VoidCallback? onTap,
    String text = 'コメントする',
  }) {
    return CommentButton(
      key: key,
      backgroundColor: theme.commentButtonColor,
      textColor: theme.textColor,
      iconColor: theme.textColor,
      onTap: onTap,
      text: text,
    );
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: PostCardDimensions.commentButtonHeight,
        decoration: BoxDecoration(
          color: backgroundColor ?? const Color(0xFF313131),
          borderRadius: BorderRadius.circular(PostCardDimensions.commentButtonRadius),
        ),
        child: Row(
          children: [
            const SizedBox(width: 12),
            Text(
              text,
              style: TextStyle(
                fontSize: PostCardFontSizes.commentButton,
                fontWeight: FontWeight.w500,
                color: textColor,
              ),
            ),
            const Spacer(),
            Icon(
              Icons.send,
              size: IconSizes.medium,
              color: iconColor.withValues(alpha: 0.7),
            ),
            const SizedBox(width: 12),
          ],
        ),
      ),
    );
  }
}

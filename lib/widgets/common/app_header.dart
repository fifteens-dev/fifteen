import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

/// 統一ヘッダーウィジェット
/// 画面上部のヘッダーを統一するためのウィジェット
class AppHeader extends StatelessWidget implements PreferredSizeWidget {
  final String? title;
  final Widget? titleWidget;
  final VoidCallback? onBack;
  final List<Widget>? actions;
  final bool showBackButton;
  final Color backgroundColor;
  final Color iconColor;
  final Color titleColor;
  final double height;

  const AppHeader({
    super.key,
    this.title,
    this.titleWidget,
    this.onBack,
    this.actions,
    this.showBackButton = true,
    this.backgroundColor = const Color(0xFF121212),
    this.iconColor = Colors.white,
    this.titleColor = Colors.white,
    this.height = 45,
  });

  @override
  Size get preferredSize => Size.fromHeight(height);

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      color: backgroundColor,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        children: [
          // 戻るボタン
          if (showBackButton)
            IconButton(
              icon: Icon(Icons.chevron_left, color: iconColor, size: 28),
              onPressed: onBack ?? () => Navigator.pop(context),
            )
          else
            const SizedBox(width: 48),

          // タイトル
          Expanded(
            child: titleWidget ??
                Text(
                  title ?? '',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: titleColor,
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                  ),
                ),
          ),

          // アクションボタン
          if (actions != null)
            Row(
              mainAxisSize: MainAxisSize.min,
              children: actions!,
            )
          else
            const SizedBox(width: 48),
        ],
      ),
    );
  }
}

/// 投稿作成ヘッダー
/// 投稿作成画面用の特化したヘッダー
class PostCreationHeader extends StatelessWidget {
  final String title;
  final VoidCallback onClose;
  final VoidCallback? onSubmit;
  final String submitText;
  final bool isSubmitting;
  final bool canSubmit;

  const PostCreationHeader({
    super.key,
    this.title = '新規投稿',
    required this.onClose,
    this.onSubmit,
    this.submitText = '投稿する',
    this.isSubmitting = false,
    this.canSubmit = true,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 62,
      padding: const EdgeInsets.symmetric(horizontal: 19),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // 閉じるボタン
          GestureDetector(
            onTap: isSubmitting ? null : onClose,
            child: Icon(
              Icons.close,
              color: isSubmitting ? Colors.grey : Colors.white,
              size: 20,
            ),
          ),

          // タイトル
          Text(
            title,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: Colors.white,
            ),
          ),

          // 投稿ボタン
          if (isSubmitting)
            const CupertinoActivityIndicator(
              color: Color(0xFF5D8FFF),
              radius: 8,
            )
          else
            GestureDetector(
              onTap: canSubmit && onSubmit != null ? onSubmit : null,
              child: Text(
                submitText,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: canSubmit
                      ? const Color(0xFF5D8FFF)
                      : Colors.grey,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// 設定画面ヘッダー
/// 設定関連画面用のヘッダー
class SettingsHeader extends StatelessWidget {
  final String title;
  final VoidCallback? onBack;
  final Widget? trailing;

  const SettingsHeader({
    super.key,
    required this.title,
    this.onBack,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 45,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        children: [
          // 戻るボタン
          IconButton(
            icon: const Icon(Icons.chevron_left, color: Colors.white, size: 28),
            onPressed: onBack ?? () => Navigator.pop(context),
          ),
          // タイトル
          Expanded(
            child: Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 15,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          // トレイリングウィジェット
          if (trailing != null)
            trailing!
          else
            const SizedBox(width: 48),
        ],
      ),
    );
  }
}

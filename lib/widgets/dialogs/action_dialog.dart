import 'package:flutter/material.dart';

/// アクションダイアログ
/// 複数のアクションボタンを持つカスタムデザインのダイアログ
class ActionDialog extends StatelessWidget {
  final String? title;
  final String? message;
  final IconData? icon;
  final List<DialogAction> actions;

  const ActionDialog({
    super.key,
    this.title,
    this.message,
    this.icon,
    required this.actions,
  });

  /// ダイアログアクション
  static DialogAction action({
    required String label,
    required VoidCallback onTap,
    bool isDestructive = false,
    bool isPrimary = false,
  }) {
    return DialogAction(
      label: label,
      onTap: onTap,
      isDestructive: isDestructive,
      isPrimary: isPrimary,
    );
  }

  /// アクションダイアログを表示するヘルパーメソッド
  static Future<String?> show(
    BuildContext context, {
    String? title,
    String? message,
    IconData? icon,
    required List<DialogAction> actions,
  }) async {
    return await showDialog<String>(
      context: context,
      barrierColor: Colors.black54,
      builder: (context) => ActionDialog(
        title: title,
        message: message,
        icon: icon,
        actions: actions,
      ),
    );
  }

  /// キャンセル確認ダイアログを表示（投稿キャンセル用）
  static Future<bool> showCancelConfirm(
    BuildContext context, {
    String? title,
    required String cancelActionLabel,
    required String continueActionLabel,
  }) async {
    final result = await show(
      context,
      title: title ?? 'どうしますか？',
      icon: Icons.help_outline_rounded,
      actions: [
        DialogAction(
          label: cancelActionLabel,
          isDestructive: true,
          onTap: () => Navigator.pop(context, 'cancel'),
        ),
        DialogAction(
          label: continueActionLabel,
          onTap: () => Navigator.pop(context, null),
        ),
      ],
    );
    return result == 'cancel';
  }

  /// 投稿確認ダイアログを表示
  static Future<bool> showPostConfirm(
    BuildContext context, {
    String title = '投稿しますか？',
    String message = 'この内容で投稿します',
    String cancelLabel = 'キャンセル',
    String confirmLabel = '投稿する',
  }) async {
    final result = await show(
      context,
      title: title,
      message: message,
      icon: Icons.send_rounded,
      actions: [
        DialogAction(
          label: cancelLabel,
          onTap: () => Navigator.pop(context, 'cancel'),
        ),
        DialogAction(
          label: confirmLabel,
          isPrimary: true,
          onTap: () => Navigator.pop(context, 'confirm'),
        ),
      ],
    );
    return result == 'confirm';
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      child: Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color(0xFF2A2A2A),
              Color(0xFF1A1A1A),
            ],
          ),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: Colors.white.withOpacity(0.1),
            width: 1,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.3),
              blurRadius: 20,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // アイコン
            if (icon != null)
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(
                  icon,
                  color: Colors.white70,
                  size: 28,
                ),
              ),
            if (icon != null) const SizedBox(height: 20),

            // タイトル
            if (title != null)
              Text(
                title!,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
            if (title != null && message != null) const SizedBox(height: 8),

            // メッセージ
            if (message != null)
              Text(
                message!,
                style: TextStyle(
                  color: Colors.white.withOpacity(0.6),
                  fontSize: 14,
                ),
              ),
            const SizedBox(height: 28),

            // アクションボタン
            _buildActions(context),
          ],
        ),
      ),
    );
  }

  Widget _buildActions(BuildContext context) {
    // 2つのアクションは横並び、それ以外は縦並び
    if (actions.length == 2 && !actions.any((a) => a.isDestructive)) {
      return Row(
        children: [
          Expanded(child: _buildActionButton(context, actions[0])),
          const SizedBox(width: 12),
          Expanded(child: _buildActionButton(context, actions[1])),
        ],
      );
    }

    return Column(
      children: actions.asMap().entries.map((entry) {
        final index = entry.key;
        final action = entry.value;
        return Padding(
          padding: EdgeInsets.only(bottom: index < actions.length - 1 ? 12 : 0),
          child: _buildActionButton(context, action, fullWidth: true),
        );
      }).toList(),
    );
  }

  Widget _buildActionButton(
    BuildContext context,
    DialogAction action, {
    bool fullWidth = false,
  }) {
    final BoxDecoration decoration;
    final TextStyle textStyle;

    if (action.isPrimary) {
      decoration = BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFF5D8FFF),
            Color(0xFF7B68EE),
          ],
        ),
        borderRadius: BorderRadius.circular(12),
      );
      textStyle = const TextStyle(
        color: Colors.white,
        fontSize: 15,
        fontWeight: FontWeight.w600,
      );
    } else if (action.isDestructive) {
      decoration = BoxDecoration(
        color: const Color(0xFFE53935).withOpacity(0.2),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: const Color(0xFFE53935).withOpacity(0.5),
          width: 1,
        ),
      );
      textStyle = const TextStyle(
        color: Color(0xFFE53935),
        fontSize: 15,
        fontWeight: FontWeight.w600,
      );
    } else {
      decoration = BoxDecoration(
        color: Colors.white.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
      );
      textStyle = const TextStyle(
        color: Colors.white70,
        fontSize: 15,
        fontWeight: FontWeight.w500,
      );
    }

    return GestureDetector(
      onTap: action.onTap,
      child: Container(
        width: fullWidth ? double.infinity : null,
        height: 48,
        decoration: decoration,
        child: Center(
          child: Text(
            action.label,
            style: textStyle,
          ),
        ),
      ),
    );
  }
}

/// ダイアログアクション
class DialogAction {
  final String label;
  final VoidCallback onTap;
  final bool isDestructive;
  final bool isPrimary;

  const DialogAction({
    required this.label,
    required this.onTap,
    this.isDestructive = false,
    this.isPrimary = false,
  });
}

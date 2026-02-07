import 'package:flutter/material.dart';

/// 確認ダイアログ
/// シンプルな確認・キャンセルのダイアログを表示するための共通ウィジェット
class ConfirmDialog extends StatelessWidget {
  final String title;
  final String? message;
  final String cancelText;
  final String confirmText;
  final Color? confirmColor;
  final VoidCallback? onConfirm;
  final VoidCallback? onCancel;

  const ConfirmDialog({
    super.key,
    required this.title,
    this.message,
    this.cancelText = 'キャンセル',
    this.confirmText = '確認',
    this.confirmColor,
    this.onConfirm,
    this.onCancel,
  });

  /// 確認ダイアログを表示するヘルパーメソッド
  static Future<bool> show(
    BuildContext context, {
    required String title,
    String? message,
    String cancelText = 'キャンセル',
    String confirmText = '確認',
    Color? confirmColor,
  }) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => ConfirmDialog(
        title: title,
        message: message,
        cancelText: cancelText,
        confirmText: confirmText,
        confirmColor: confirmColor,
      ),
    );
    return result ?? false;
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: Colors.grey[900],
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      title: Text(
        title,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 18,
          fontWeight: FontWeight.bold,
        ),
      ),
      content: message != null
          ? Text(
              message!,
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 14,
              ),
            )
          : null,
      actions: [
        TextButton(
          onPressed: () {
            onCancel?.call();
            Navigator.pop(context, false);
          },
          child: Text(
            cancelText,
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 14,
            ),
          ),
        ),
        TextButton(
          onPressed: () {
            onConfirm?.call();
            Navigator.pop(context, true);
          },
          child: Text(
            confirmText,
            style: TextStyle(
              color: confirmColor ?? const Color(0xFF5D8FFF),
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }
}

/// 削除確認ダイアログ
/// 削除操作の確認に特化したダイアログ
class DeleteConfirmDialog extends StatelessWidget {
  final String title;
  final String message;
  final String cancelText;
  final String deleteText;

  const DeleteConfirmDialog({
    super.key,
    required this.title,
    required this.message,
    this.cancelText = 'キャンセル',
    this.deleteText = '削除',
  });

  /// 削除確認ダイアログを表示するヘルパーメソッド
  static Future<bool> show(
    BuildContext context, {
    required String title,
    required String message,
    String cancelText = 'キャンセル',
    String deleteText = '削除',
  }) async {
    return await ConfirmDialog.show(
      context,
      title: title,
      message: message,
      cancelText: cancelText,
      confirmText: deleteText,
      confirmColor: Colors.red,
    );
  }

  @override
  Widget build(BuildContext context) {
    return ConfirmDialog(
      title: title,
      message: message,
      cancelText: cancelText,
      confirmText: deleteText,
      confirmColor: Colors.red,
    );
  }
}

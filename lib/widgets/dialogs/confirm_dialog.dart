import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

/// iOS スタイルの確認ダイアログ
class ConfirmDialog {
  static Future<bool> show(
    BuildContext context, {
    required String title,
    String? message,
    String cancelText = 'キャンセル',
    String confirmText = '確認',
    bool isDestructive = false,
    Color? confirmColor,
  }) async {
    final destructive = isDestructive || confirmColor == Colors.red;
    final result = await showCupertinoDialog<bool>(
      context: context,
      barrierDismissible: true,
      builder: (context) => CupertinoAlertDialog(
        title: Text(title),
        content: message != null
            ? Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(message),
              )
            : null,
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.pop(context, false),
            child: Text(cancelText),
          ),
          CupertinoDialogAction(
            isDestructiveAction: destructive,
            isDefaultAction: !destructive,
            onPressed: () => Navigator.pop(context, true),
            child: Text(confirmText),
          ),
        ],
      ),
    );
    return result ?? false;
  }
}

/// 削除確認ダイアログ
class DeleteConfirmDialog {
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
      isDestructive: true,
    );
  }
}

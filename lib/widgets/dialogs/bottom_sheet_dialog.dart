import 'package:flutter/material.dart';

/// ボトムシートダイアログ
/// モーダルボトムシート形式のダイアログを表示するための共通ウィジェット
class BottomSheetDialog extends StatelessWidget {
  final String? title;
  final String? message;
  final List<BottomSheetAction> actions;
  final Widget? content;

  const BottomSheetDialog({
    super.key,
    this.title,
    this.message,
    this.actions = const [],
    this.content,
  });

  /// ボトムシートダイアログを表示するヘルパーメソッド
  static Future<String?> show(
    BuildContext context, {
    String? title,
    String? message,
    List<BottomSheetAction> actions = const [],
    Widget? content,
  }) async {
    return await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: content != null,
      builder: (context) => BottomSheetDialog(
        title: title,
        message: message,
        actions: actions,
        content: content,
      ),
    );
  }

  /// 確認ダイアログを表示（2ボタン）
  static Future<bool> showConfirm(
    BuildContext context, {
    required String title,
    String? message,
    String cancelLabel = 'キャンセル',
    String confirmLabel = '確認',
    bool isConfirmDestructive = false,
  }) async {
    final result = await show(
      context,
      title: title,
      message: message,
      actions: [
        BottomSheetAction(
          label: cancelLabel,
          onTap: () => Navigator.pop(context, 'cancel'),
        ),
        BottomSheetAction(
          label: confirmLabel,
          isDestructive: isConfirmDestructive,
          onTap: () => Navigator.pop(context, 'confirm'),
        ),
      ],
    );
    return result == 'confirm';
  }

  /// 接続解除確認ダイアログを表示
  static Future<bool> showDisconnect(
    BuildContext context, {
    required String serviceName,
  }) async {
    return await showConfirm(
      context,
      title: '$serviceNameとの接続を解除',
      message: '本当に接続を解除しますか？',
      cancelLabel: 'キャンセル',
      confirmLabel: '解除',
      isConfirmDestructive: true,
    );
  }

  /// サービス切り替え確認ダイアログを表示
  static Future<bool> showSwitchService(
    BuildContext context, {
    required String newService,
    required String currentService,
  }) async {
    return await showConfirm(
      context,
      title: '$newServiceと接続',
      message: '${currentService}との接続を解除して${newService}と接続しますか？',
      cancelLabel: 'キャンセル',
      confirmLabel: '接続',
      isConfirmDestructive: true,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey[800],
        borderRadius: BorderRadius.circular(36),
      ),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
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
            if (title != null && message != null) const SizedBox(height: 12),

            // メッセージ
            if (message != null)
              Text(
                message!,
                style: TextStyle(
                  color: Colors.grey[400],
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                ),
              ),

            // カスタムコンテンツ
            if (content != null) content!,

            if (actions.isNotEmpty) ...[
              const SizedBox(height: 24),
              // アクションボタン
              Row(
                children: actions.asMap().entries.map((entry) {
                  final index = entry.key;
                  final action = entry.value;
                  return Expanded(
                    child: Padding(
                      padding: EdgeInsets.only(
                        left: index > 0 ? 12 : 0,
                      ),
                      child: _buildActionButton(context, action),
                    ),
                  );
                }).toList(),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildActionButton(BuildContext context, BottomSheetAction action) {
    return GestureDetector(
      onTap: action.onTap,
      child: Container(
        height: 45,
        decoration: BoxDecoration(
          color: action.isPrimary
              ? const Color(0xFF5D8FFF)
              : Colors.grey[700],
          borderRadius: BorderRadius.circular(13),
        ),
        child: Center(
          child: Text(
            action.label,
            style: TextStyle(
              color: action.isDestructive
                  ? Colors.red
                  : Colors.white,
              fontSize: 15,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ),
    );
  }
}

/// ボトムシートアクション
class BottomSheetAction {
  final String label;
  final VoidCallback onTap;
  final bool isPrimary;
  final bool isDestructive;

  const BottomSheetAction({
    required this.label,
    required this.onTap,
    this.isPrimary = false,
    this.isDestructive = false,
  });
}

/// サービス情報ボトムシートダイアログ
/// 音楽サービス連携時の機能説明を表示
class ServiceInfoBottomSheet extends StatelessWidget {
  final String title;
  final String icon;
  final List<String> features;
  final VoidCallback onConnect;
  final VoidCallback onCancel;

  const ServiceInfoBottomSheet({
    super.key,
    required this.title,
    required this.icon,
    required this.features,
    required this.onConnect,
    required this.onCancel,
  });

  /// サービス情報ボトムシートを表示
  static Future<bool> show(
    BuildContext context, {
    required String title,
    required String icon,
    required List<String> features,
  }) async {
    final result = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => ServiceInfoBottomSheet(
        title: title,
        icon: icon,
        features: features,
        onConnect: () => Navigator.pop(context, true),
        onCancel: () => Navigator.pop(context, false),
      ),
    );
    return result ?? false;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey[800],
        borderRadius: BorderRadius.circular(36),
      ),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // アイコンとタイトル
            Row(
              children: [
                Text(
                  icon,
                  style: const TextStyle(fontSize: 32),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),

            // できること
            Text(
              'できること',
              style: TextStyle(
                color: Colors.grey[400],
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 12),

            // 機能リスト
            ...features.map((feature) => Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        '✓',
                        style: TextStyle(
                          color: Color(0xFF4CAF50),
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          feature,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            height: 1.4,
                          ),
                        ),
                      ),
                    ],
                  ),
                )),
            const SizedBox(height: 24),

            // ボタン
            Row(
              children: [
                // キャンセルボタン
                Expanded(
                  child: GestureDetector(
                    onTap: onCancel,
                    child: Container(
                      height: 45,
                      decoration: BoxDecoration(
                        color: Colors.grey[700],
                        borderRadius: BorderRadius.circular(13),
                      ),
                      child: const Center(
                        child: Text(
                          'キャンセル',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                // 接続ボタン
                Expanded(
                  child: GestureDetector(
                    onTap: onConnect,
                    child: Container(
                      height: 45,
                      decoration: BoxDecoration(
                        color: const Color(0xFF5D8FFF),
                        borderRadius: BorderRadius.circular(13),
                      ),
                      child: const Center(
                        child: Text(
                          '接続する',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

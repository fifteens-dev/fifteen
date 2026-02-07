import 'package:flutter/material.dart';

/// エラー状態ウィジェット
/// エラー表示を統一するためのウィジェット
class ErrorState extends StatelessWidget {
  final String message;
  final String? retryText;
  final VoidCallback? onRetry;
  final IconData icon;
  final Color iconColor;

  const ErrorState({
    super.key,
    required this.message,
    this.retryText,
    this.onRetry,
    this.icon = Icons.error_outline,
    this.iconColor = const Color(0xFFE53935),
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 48,
              color: iconColor,
            ),
            const SizedBox(height: 16),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 14,
              ),
            ),
            if (onRetry != null) ...[
              const SizedBox(height: 24),
              _buildRetryButton(),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildRetryButton() {
    return GestureDetector(
      onTap: onRetry,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
        decoration: BoxDecoration(
          color: const Color(0xFF5D8FFF),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          retryText ?? '再試行',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

/// ネットワークエラー状態
class NetworkErrorState extends StatelessWidget {
  final VoidCallback? onRetry;

  const NetworkErrorState({
    super.key,
    this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    return ErrorState(
      icon: Icons.wifi_off,
      message: 'ネットワークに接続できません\nインターネット接続を確認してください',
      onRetry: onRetry,
    );
  }
}

/// データ取得エラー状態
class DataErrorState extends StatelessWidget {
  final String? message;
  final VoidCallback? onRetry;

  const DataErrorState({
    super.key,
    this.message,
    this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    return ErrorState(
      message: message ?? 'データの取得に失敗しました',
      onRetry: onRetry,
    );
  }
}

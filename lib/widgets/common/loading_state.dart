import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

/// ローディング状態ウィジェット
class LoadingState extends StatelessWidget {
  final String? message;
  final Color? color;
  final double size;

  const LoadingState({
    super.key,
    this.message,
    this.color,
    this.size = 24.0,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CupertinoActivityIndicator(
            color: color ?? Colors.white,
            radius: size / 2,
          ),
          if (message != null) ...[
            const SizedBox(height: 16),
            Text(
              message!,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.7),
                fontSize: 14,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// フルスクリーンローディング
class FullScreenLoading extends StatelessWidget {
  final String? message;
  final Color backgroundColor;
  final Color? indicatorColor;

  const FullScreenLoading({
    super.key,
    this.message,
    this.backgroundColor = const Color(0xFF121212),
    this.indicatorColor,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: backgroundColor,
      body: LoadingState(
        message: message,
        color: indicatorColor,
      ),
    );
  }
}

/// インラインローディング（ボタン等の中に使う小さめ）
class InlineLoading extends StatelessWidget {
  final double size;
  final Color? color;

  const InlineLoading({
    super.key,
    this.size = 16.0,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    return CupertinoActivityIndicator(
      color: color ?? Colors.white,
      radius: size / 2,
    );
  }
}

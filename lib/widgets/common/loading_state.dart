import 'package:flutter/material.dart';

/// ローディング状態ウィジェット
/// 読み込み中の表示を統一するためのウィジェット
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
          SizedBox(
            width: size,
            height: size,
            child: CircularProgressIndicator(
              strokeWidth: 2.5,
              valueColor: AlwaysStoppedAnimation<Color>(
                color ?? const Color(0xFF5D8FFF),
              ),
            ),
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
/// 画面全体を覆うローディング表示
class FullScreenLoading extends StatelessWidget {
  final String? message;
  final Color backgroundColor;
  final Color indicatorColor;

  const FullScreenLoading({
    super.key,
    this.message,
    this.backgroundColor = const Color(0xFF121212),
    this.indicatorColor = const Color(0xFF5D8FFF),
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

/// インラインローディング
/// ボタンやテキスト横に表示する小さなローディング
class InlineLoading extends StatelessWidget {
  final double size;
  final Color? color;
  final double strokeWidth;

  const InlineLoading({
    super.key,
    this.size = 16.0,
    this.color,
    this.strokeWidth = 2.0,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CircularProgressIndicator(
        strokeWidth: strokeWidth,
        valueColor: AlwaysStoppedAnimation<Color>(
          color ?? const Color(0xFF5D8FFF),
        ),
      ),
    );
  }
}

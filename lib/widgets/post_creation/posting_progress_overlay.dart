import 'package:flutter/material.dart';

/// 「Vibeに楽曲を追加しています...」のような投稿プログレス文をヘッダー領域に
/// フェードイン/アウトで表示するオーバーレイ。
///
/// 用途:
/// - チュートリアル中（楽曲追加アニメーション）
/// - 実際の投稿処理中（ホーム画面のヘッダー位置に重ねて表示）
///
/// アクティブ判定は [active] で行い、状態遷移時に opacity がアニメーション。
class PostingProgressOverlay extends StatelessWidget {
  final bool active;
  final String text;

  /// オーバーレイの上端からのオフセット（status bar + ヘッダー高さ ぐらい）
  final double topOffset;

  const PostingProgressOverlay({
    super.key,
    required this.active,
    this.text = 'Vibeに楽曲を追加しています...',
    this.topOffset = 0,
  });

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 300),
        opacity: active ? 1.0 : 0.0,
        child: Padding(
          padding: EdgeInsets.only(top: topOffset),
          child: SizedBox(
            height: 44,
            width: double.infinity,
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.55),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      text,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

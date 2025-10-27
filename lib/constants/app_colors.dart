import 'package:flutter/material.dart';

/// アプリケーション全体で使用する色定義
class AppColors {
  // プライマリカラー
  static const Color background = Color(0xFF000000); // 黒背景
  static const Color surface = Color(0xFF1A1A1A); // 入力フィールドなどの表面色

  // テキストカラー
  static const Color textPrimary = Color(0xFFFFFFFF); // 白
  static const Color textSecondary = Color(0xFF9E9E9E); // グレー
  static const Color textPlaceholder = Color(0xFF666666); // プレースホルダー用グレー

  // ボタンカラー
  static const Color buttonPrimary = Color(0xFFFFFFFF); // 白ボタン
  static const Color buttonText = Color(0xFF000000); // ボタンテキスト（黒）

  // ボーダー・区切り線
  static const Color border = Color(0xFF333333); // ダークグレー
  static const Color divider = Color(0xFF2A2A2A);

  // アクセントカラー（必要に応じて）
  static const Color accent = Color(0xFF4A90E2);
  static const Color error = Color(0xFFE74C3C);
  static const Color success = Color(0xFF2ECC71);
}

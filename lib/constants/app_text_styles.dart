import 'package:flutter/material.dart';
import 'app_colors.dart';

/// アプリケーション全体で使用するテキストスタイル定義
class AppTextStyles {
  // アプリ名スタイル
  static const TextStyle appTitle = TextStyle(
    fontSize: 48,
    fontWeight: FontWeight.bold,
    color: AppColors.textPrimary,
    letterSpacing: 2.0,
  );

  // 見出しスタイル
  static const TextStyle heading = TextStyle(
    fontSize: 18,
    fontWeight: FontWeight.w500,
    color: AppColors.textPrimary,
  );

  // ボディテキスト
  static const TextStyle body = TextStyle(
    fontSize: 16,
    fontWeight: FontWeight.normal,
    color: AppColors.textPrimary,
  );

  // ボタンテキスト
  static const TextStyle button = TextStyle(
    fontSize: 16,
    fontWeight: FontWeight.w600,
    color: AppColors.buttonText,
  );

  // 小さいテキスト（利用規約など）
  static const TextStyle caption = TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.normal,
    color: AppColors.textSecondary,
    height: 1.5,
  );

  // 入力フィールドテキスト
  static const TextStyle input = TextStyle(
    fontSize: 16,
    fontWeight: FontWeight.normal,
    color: AppColors.textPrimary,
  );

  // プレースホルダーテキスト
  static const TextStyle placeholder = TextStyle(
    fontSize: 16,
    fontWeight: FontWeight.normal,
    color: AppColors.textPlaceholder,
  );
}

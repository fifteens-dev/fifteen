import 'package:flutter/foundation.dart';

/// デバッグログ用のユーティリティクラス
/// kDebugModeでのみログを出力する
class DebugLogger {
  DebugLogger._();

  /// 情報ログ
  static void info(String message) {
    if (kDebugMode) {
      debugPrint('ℹ️ $message');
    }
  }

  /// 成功ログ
  static void success(String message) {
    if (kDebugMode) {
      debugPrint('✅ $message');
    }
  }

  /// 警告ログ
  static void warning(String message) {
    if (kDebugMode) {
      debugPrint('⚠️ $message');
    }
  }

  /// エラーログ
  static void error(String message, [Object? error]) {
    if (kDebugMode) {
      debugPrint('❌ $message');
      if (error != null) {
        debugPrint('   Error: $error');
      }
    }
  }

  /// デバッグログ（汎用）
  static void log(String message) {
    if (kDebugMode) {
      debugPrint(message);
    }
  }

  /// 画面遷移ログ
  static void navigation(String message) {
    if (kDebugMode) {
      debugPrint('🔀 $message');
    }
  }

  /// 音楽関連ログ
  static void music(String message) {
    if (kDebugMode) {
      debugPrint('🎵 $message');
    }
  }

  /// 画像関連ログ
  static void image(String message) {
    if (kDebugMode) {
      debugPrint('📷 $message');
    }
  }

  /// API関連ログ
  static void api(String message) {
    if (kDebugMode) {
      debugPrint('🌐 $message');
    }
  }

  /// 開発中の詳細ログ（詳細なデバッグ情報）
  static void verbose(String message) {
    if (kDebugMode) {
      debugPrint('   $message');
    }
  }
}

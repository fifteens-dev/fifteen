import 'package:flutter/foundation.dart';

/// 開発中だけ出すログ。
///
/// `print` はリリースビルドでも実行され、端末のシステムログに残る。
/// 以前はアプリ全体で生の `print` を使っており、ユーザー ID や OAuth の
/// レスポンスボディまで製品版の端末に出ていた。
///
/// 中身は [kDebugMode] で落とすので、リリースでは呼び出しごと何も起きない
/// （文字列の組み立てだけは走るので、重い値を渡す場所では呼び出し側で
/// 囲うこと）。
///
/// `print` ではなく [debugPrint] を使うのは、iOS のログが 1 行 1024 文字で
/// 切られるため。長い JSON を出したときに途中で欠けるのを防ぐ。
class AppLog {
  AppLog._();

  /// 開発中だけ出す。本番では何も起きない。
  static void debug(Object? message) {
    if (kDebugMode) debugPrint('$message');
  }
}

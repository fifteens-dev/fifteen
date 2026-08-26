import 'dart:io';
import 'dart:ui';
import 'package:flutter/services.dart';

/// ネイティブ（iOS）の絵文字リアクションピッカー（すりガラスの吹き出し）を表示する。
///
/// iOS では UIVisualEffectView によるネイティブのすりガラスで描画するため、
/// Flutter の BackdropFilter のような描画不具合や、2列拡大時の FittedBox
/// スケールによる見切れが起きない。
/// iOS 以外では null を返す（呼び出し元が Flutter 版にフォールバック）。
class ReactionPickerService {
  static const _channel = MethodChannel('com.fifteen.reactionpicker');

  /// [emojis] を横並びで表示し、選ばれた絵文字を返す。
  /// [anchorRect] はスマイルボタンのグローバル座標（論理pt）。
  /// キャンセル/外側タップ時は null。
  static Future<String?> show({
    required List<String> emojis,
    required Rect anchorRect,
  }) async {
    if (!Platform.isIOS) return null;
    try {
      return await _channel.invokeMethod<String>('show', {
        'emojis': emojis,
        'anchorX': anchorRect.left,
        'anchorY': anchorRect.top,
        'anchorW': anchorRect.width,
        'anchorH': anchorRect.height,
      });
    } on PlatformException {
      return null;
    }
  }
}

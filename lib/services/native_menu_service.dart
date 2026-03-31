import 'dart:io';
import 'package:flutter/services.dart';

/// iOS ネイティブ UIMenu を表示するサービス
///
/// iOS 14+ では Method Channel 経由でネイティブ UIMenu を表示。
/// iOS 14 未満 / Android では null を返す（呼び出し元でフォールバック）。
class NativeMenuService {
  static const _channel = MethodChannel('com.fifteen.nativemenu');

  /// UIMenu を表示する。
  /// [items]      表示するメニュー項目
  /// [anchorRect] ボタンのグローバル座標（Rect）
  ///
  /// 戻り値: 選択されたアイテムの [id]。キャンセル時は null。
  static Future<String?> showMenu({
    required List<NativeMenuItem> items,
    required Rect anchorRect,
  }) async {
    if (!Platform.isIOS) return null;
    try {
      final result = await _channel.invokeMethod<String>('showMenu', {
        'items': items.map((e) => e.toMap()).toList(),
        'anchorX': anchorRect.left,
        'anchorY': anchorRect.top,
        'anchorW': anchorRect.width,
        'anchorH': anchorRect.height,
      });
      return result;
    } on PlatformException {
      return null;
    }
  }
}

/// UIMenu の各アイテム定義
class NativeMenuItem {
  /// 選択時に返される識別子
  final String id;

  /// 表示ラベル
  final String title;

  /// 'default' または 'destructive'（赤色表示）
  final String type;

  /// SF Symbols のアイコン名（省略可）
  final String? icon;

  const NativeMenuItem({
    required this.id,
    required this.title,
    this.type = 'default',
    this.icon,
  });

  Map<String, dynamic> toMap() => {
        'id': id,
        'title': title,
        'type': type,
        if (icon != null) 'icon': icon,
      };
}

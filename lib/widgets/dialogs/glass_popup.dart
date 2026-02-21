import 'dart:ui';
import 'package:flutter/material.dart';

/// iOSスタイルのフロストガラスポップアップメニュー
class GlassPopup {
  /// ガラス風ポップアップメニューを表示
  /// [context] BuildContext
  /// [position] 表示位置（グローバル座標）
  /// [items] メニュー項目リスト
  /// 戻り値: 選択された値（キャンセル時はnull）
  static Future<T?> show<T>({
    required BuildContext context,
    required Offset position,
    required List<GlassPopupItem<T>> items,
    double width = 200,
  }) {
    return showDialog<T>(
      context: context,
      barrierColor: Colors.transparent,
      builder: (dialogContext) {
        return _GlassPopupOverlay<T>(
          position: position,
          items: items,
          width: width,
        );
      },
    );
  }
}

/// ポップアップメニューのアイテム
class GlassPopupItem<T> {
  final T value;
  final String label;
  final Color? textColor;
  final IconData? icon;
  final Widget? trailing;

  const GlassPopupItem({
    required this.value,
    required this.label,
    this.textColor,
    this.icon,
    this.trailing,
  });
}

class _GlassPopupOverlay<T> extends StatelessWidget {
  final Offset position;
  final List<GlassPopupItem<T>> items;
  final double width;

  const _GlassPopupOverlay({
    required this.position,
    required this.items,
    required this.width,
  });

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;

    // 画面からはみ出さないよう位置を調整
    double left = position.dx;
    double top = position.dy;

    if (left + width > screenSize.width - 16) {
      left = screenSize.width - width - 16;
    }
    if (left < 16) left = 16;

    final itemHeight = 44.0;
    final menuHeight = items.length * itemHeight;
    if (top + menuHeight > screenSize.height - 16) {
      top = position.dy - menuHeight;
    }

    return Stack(
      children: [
        // タップで閉じる透明レイヤー
        GestureDetector(
          onTap: () => Navigator.pop(context),
          child: Container(color: Colors.transparent),
        ),
        Positioned(
          left: left,
          top: top,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 25, sigmaY: 25),
              child: Container(
                width: width,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.2),
                    width: 0.5,
                  ),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: items.asMap().entries.map((entry) {
                    final index = entry.key;
                    final item = entry.value;
                    return Column(
                      children: [
                        if (index > 0)
                          Container(
                            height: 0.5,
                            color: Colors.white.withValues(alpha: 0.15),
                          ),
                        Material(
                          color: Colors.transparent,
                          child: InkWell(
                            onTap: () => Navigator.pop(context, item.value),
                            child: Container(
                              height: itemHeight,
                              padding: const EdgeInsets.symmetric(horizontal: 16),
                              child: Row(
                                children: [
                                  if (item.icon != null) ...[
                                    Icon(
                                      item.icon,
                                      size: 20,
                                      color: item.textColor ?? Colors.white,
                                    ),
                                    const SizedBox(width: 12),
                                  ],
                                  Expanded(
                                    child: Text(
                                      item.label,
                                      style: TextStyle(
                                        fontSize: 16,
                                        color: item.textColor ?? Colors.white,
                                      ),
                                    ),
                                  ),
                                  if (item.trailing != null) item.trailing!,
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    );
                  }).toList(),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pull_down_button/pull_down_button.dart';
import '../services/native_menu_service.dart';

export '../services/native_menu_service.dart' show NativeMenuItem;

/// iOS / Android 共通のメニューボタンウィジェット。
///
/// iOS: 透明な UIButton (UiKitView) を Flutter の child の上に重ね、
///      実際のタッチを UIButton が受け取ることで iOS ネイティブ UIMenu を表示する。
/// Android: pull_down_button パッケージで iOS UIMenu スタイルのメニューを表示する。
class NativePullDownButton extends StatefulWidget {
  final List<NativeMenuItem> items;
  final Future<void> Function(String id) onSelected;
  final Widget child;

  const NativePullDownButton({
    super.key,
    required this.items,
    required this.onSelected,
    required this.child,
  });

  @override
  State<NativePullDownButton> createState() => _NativePullDownButtonState();
}

class _NativePullDownButtonState extends State<NativePullDownButton> {
  MethodChannel? _channel;

  @override
  Widget build(BuildContext context) {
    if (Platform.isIOS) {
      return Stack(
        children: [
          widget.child,
          Positioned.fill(
            child: UiKitView(
              viewType: 'com.fifteen.nativemenu/button',
              creationParams: {
                'items': widget.items.map((e) => e.toMap()).toList(),
              },
              creationParamsCodec: const StandardMessageCodec(),
              onPlatformViewCreated: (viewId) {
                _channel = MethodChannel(
                    'com.fifteen.nativemenu/button_$viewId');
                _channel!.setMethodCallHandler((call) async {
                  if (call.method == 'onItemSelected') {
                    await widget.onSelected(call.arguments as String);
                  }
                });
              },
            ),
          ),
        ],
      );
    }

    // Android: pull_down_button で iOS スタイルのメニューを表示
    return PullDownButton(
      itemBuilder: (context) => widget.items
          .map((item) => PullDownMenuItem(
                title: item.title,
                icon: _iconData(item.icon),
                isDestructive: item.type == 'destructive',
                onTap: () => widget.onSelected(item.id),
              ))
          .toList(),
      buttonBuilder: (context, showMenu) => GestureDetector(
        onTap: showMenu,
        child: widget.child,
      ),
    );
  }

  /// SF Symbols 名 → Flutter IconData への変換（主要アイコンのみ）
  IconData? _iconData(String? sfSymbol) {
    switch (sfSymbol) {
      case 'trash':
        return Icons.delete_outline;
      case 'exclamationmark.triangle':
        return Icons.warning_amber_rounded;
      default:
        return null;
    }
  }
}

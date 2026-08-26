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

  // ── ネイティブ(UiKitView)描画の一時抑制 ───────────────────────
  // iOS では UiKitView が BackdropFilter/ImageFiltered の背後で黒く描画される。
  // 全画面ぼかしモーダル（例: 楽曲選択の MusicMemoryModal）を表示する間は
  // suppress() でネイティブ描画を止め、Flutter 版メニューにフォールバックさせて
  // 背後の黒い矩形を防ぐ。閉じたら release() で元に戻す。
  static final ValueNotifier<int> _suppressCount = ValueNotifier<int>(0);
  static void suppressNative() => _suppressCount.value++;
  static void releaseNative() =>
      _suppressCount.value = (_suppressCount.value - 1).clamp(0, 1 << 30);

  @override
  State<NativePullDownButton> createState() => _NativePullDownButtonState();
}

class _NativePullDownButtonState extends State<NativePullDownButton> {
  MethodChannel? _channel;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: NativePullDownButton._suppressCount,
      builder: (context, suppress, _) {
        // iOS かつ抑制されていない時のみネイティブ UIMenu(UiKitView) を使う。
        if (Platform.isIOS && suppress == 0) {
          return _buildNative();
        }
        return _buildFlutterFallback();
      },
    );
  }

  Widget _buildNative() {
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

  Widget _buildFlutterFallback() {
    // Android / ネイティブ抑制中: pull_down_button で iOS スタイルのメニューを表示
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
      case 'pencil':
        return Icons.edit_outlined;
      default:
        return null;
    }
  }
}

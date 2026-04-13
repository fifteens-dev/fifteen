import 'package:flutter/material.dart';

/// 画面中央にPNG背景付きのトーストメッセージを表示するユーティリティ。
/// 瞬時に表示され、しばらく待ってからフェードアウトする。
class AppToast {
  static OverlayEntry? _currentEntry;

  /// [context] のオーバーレイに [message] を表示する。
  static void show(BuildContext context, String message) {
    final overlay = Overlay.maybeOf(context, rootOverlay: true);
    if (overlay == null) return;

    _currentEntry?.remove();
    _currentEntry = null;

    late OverlayEntry entry;
    entry = OverlayEntry(
      builder: (context) => _ToastOverlay(
        message: message,
        onDismiss: () {
          if (_currentEntry == entry) {
            _currentEntry = null;
          }
          entry.remove();
        },
      ),
    );
    _currentEntry = entry;
    overlay.insert(entry);
  }
}

class _ToastOverlay extends StatefulWidget {
  final String message;
  final VoidCallback onDismiss;

  const _ToastOverlay({required this.message, required this.onDismiss});

  @override
  State<_ToastOverlay> createState() => _ToastOverlayState();
}

class _ToastOverlayState extends State<_ToastOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 350),
      value: 1.0,
    );
    // 表示は瞬時、一定時間後にフェードアウト
    Future.delayed(const Duration(milliseconds: 1400), () {
      if (!mounted) return;
      _controller.reverse().then((_) {
        if (mounted) widget.onDismiss();
      });
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: IgnorePointer(
        child: Material(
          type: MaterialType.transparency,
          child: Center(
            child: FadeTransition(
              opacity: _controller,
              child: SizedBox(
                width: 280,
                height: 58,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    Positioned.fill(
                      child: Image.asset(
                        'assets/icons/toast_bg.png',
                        fit: BoxFit.fill,
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: Text(
                        widget.message,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          decoration: TextDecoration.none,
                        ),
                        textAlign: TextAlign.center,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
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

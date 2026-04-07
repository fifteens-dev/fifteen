import 'package:flutter/material.dart';

/// コピー完了時に画面上部からスライドインするバナー
///
/// 使用例:
/// ```dart
/// showCopyBanner(context, copiedText: code, subtitle: '残り: 2人');
/// ```
class CopyBanner extends StatefulWidget {
  final VoidCallback onDismiss;

  const CopyBanner({super.key, required this.onDismiss});

  @override
  State<CopyBanner> createState() => _CopyBannerState();
}

class _CopyBannerState extends State<CopyBanner>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;
  bool _dismissed = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOut),
    );
    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, -1),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOut));

    _controller.forward();

    Future.delayed(const Duration(milliseconds: 2000), () {
      _dismiss();
    });
  }

  void _dismiss() {
    if (_dismissed || !mounted) return;
    _dismissed = true;
    _controller.reverse().then((_) => widget.onDismiss());
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final safeTop = MediaQuery.of(context).padding.top;
    return Positioned(
      top: safeTop + 8,
      left: 16,
      right: 16,
      child: GestureDetector(
        onVerticalDragUpdate: (details) {
          if (details.delta.dy < -4) _dismiss();
        },
        child: SlideTransition(
        position: _slideAnimation,
        child: FadeTransition(
          opacity: _fadeAnimation,
          child: Material(
            color: Colors.transparent,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                color: const Color(0xFF1E1E1E),
                borderRadius: BorderRadius.circular(14),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.3),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  // チェックマーク + "コピーしました"
                  Row(
                    children: [
                      Container(
                        width: 20,
                        height: 20,
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          color: Color(0xFF5D8FFF),
                        ),
                        child: const Icon(
                          Icons.check,
                          color: Colors.white,
                          size: 13,
                        ),
                      ),
                      const SizedBox(width: 8),
                      const Text(
                        'コピーしました',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
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

/// コピーバナーを表示するユーティリティ関数
void showCopyBanner(BuildContext context) {
  final overlay = Overlay.of(context);
  late OverlayEntry entry;
  entry = OverlayEntry(
    builder: (_) => CopyBanner(onDismiss: () => entry.remove()),
  );
  overlay.insert(entry);
}

import 'package:flutter/material.dart';

/// 制限操作の通知オーバーレイトースト
/// - IgnorePointer で包み、表示中も他の操作をブロックしない
/// - 自動で消える（約1.8秒）
class RestrictionNotification {
  static void show(
    BuildContext context, {
    String message = 'この操作はできません',
    IconData icon = Icons.lock_outline_rounded,
  }) {
    late OverlayEntry entry;
    entry = OverlayEntry(
      builder: (_) => _RestrictionToast(
        message: message,
        icon: icon,
        onDismiss: () {
          if (entry.mounted) entry.remove();
        },
      ),
    );
    Overlay.of(context).insert(entry);
  }
}

class _RestrictionToast extends StatefulWidget {
  final String message;
  final IconData icon;
  final VoidCallback onDismiss;

  const _RestrictionToast({
    required this.message,
    required this.icon,
    required this.onDismiss,
  });

  @override
  State<_RestrictionToast> createState() => _RestrictionToastState();
}

class _RestrictionToastState extends State<_RestrictionToast>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _opacity;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      duration: const Duration(milliseconds: 220),
      vsync: this,
    );
    _opacity = CurvedAnimation(parent: _ctrl, curve: Curves.easeOut);
    _ctrl.forward();

    // 1.4秒後にフェードアウト開始 → 合計約1.8秒で消える
    Future.delayed(const Duration(milliseconds: 1400), () {
      if (mounted) {
        _ctrl.reverse().then((_) => widget.onDismiss());
      }
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // IgnorePointer: 通知表示中も背後の操作を通過させる
    return IgnorePointer(
      child: Material(
        color: Colors.transparent,
        child: SafeArea(
          child: Center(
            child: FadeTransition(
              opacity: _opacity,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 18, vertical: 11),
                decoration: BoxDecoration(
                  color: const Color(0xFF282828),
                  borderRadius: BorderRadius.circular(10),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.4),
                      blurRadius: 16,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(widget.icon, color: Colors.white38, size: 18),
                    const SizedBox(height: 8),
                    Text(
                      widget.message,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.white54,
                        fontSize: 13,
                        fontWeight: FontWeight.w400,
                        decoration: TextDecoration.none,
                        height: 1.6,
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

import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// iOS の Liquid Glass（Regular / Small / Dark）の代わり。
///
/// Flutter から本物のガラスは描けないので、背景をぼかして薄い白を重ね、
/// 縁に細い光を入れて近づけている。
class GlassCircleButton extends StatelessWidget {
  final double size;
  final VoidCallback onTap;
  final Widget child;

  const GlassCircleButton({
    super.key,
    required this.size,
    required this.onTap,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: ClipOval(
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: 12, sigmaY: 12),
          child: Container(
            width: size,
            height: size,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white.withValues(alpha: 0.12),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.14),
                width: 0.8,
              ),
            ),
            child: child,
          ),
        ),
      ),
    );
  }
}

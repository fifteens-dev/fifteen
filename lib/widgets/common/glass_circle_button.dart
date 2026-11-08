import 'package:flutter/material.dart';

import 'liquid_glass.dart';

/// iOS の Liquid Glass の丸ボタン（Figma: Regular / Small / Dark）。
/// ガラスは iOS 本来のもの（[LiquidGlass]）。
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
      child: LiquidGlass(
        child: SizedBox(
          width: size,
          height: size,
          child: Center(child: child),
        ),
      ),
    );
  }
}

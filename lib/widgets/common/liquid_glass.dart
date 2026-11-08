import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// iOS 本来の Liquid Glass を背景に敷く（iOS 26 の UIGlassEffect）。
///
/// iOS ではネイティブのガラス（[LiquidGlassFactory]）を [child] の下に置く。
/// iOS 26 未満はネイティブ側で同じ形のぼかしに落ちる。iOS 以外は Flutter で
/// ぼかしと薄い色を重ねて近づける。
///
/// 注意: 同じ画面に Flutter の BackdropFilter があると、ネイティブのガラスが
/// 描かれなくなることがある。ガラスを置く画面では BackdropFilter を使わない。
class LiquidGlass extends StatelessWidget {
  /// 角の丸み。null なら丸（短い辺の半分）。
  final double? radius;

  /// clear は透けの強いガラス（写真の上など）。
  final bool clear;

  /// ガラスに混ぜる色。
  final Color? tint;

  final Widget child;

  const LiquidGlass({
    super.key,
    this.radius,
    this.clear = false,
    this.tint,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    if (!Platform.isIOS) return _fallback();
    return Stack(
      fit: StackFit.passthrough,
      children: [
        Positioned.fill(
          child: IgnorePointer(
            child: UiKitView(
              viewType: 'com.fifteen/liquid_glass',
              creationParams: {
                'cornerRadius': radius ?? -1.0,
                'style': clear ? 'clear' : 'regular',
                if (tint != null) 'tint': tint!.toARGB32(),
              },
              creationParamsCodec: const StandardMessageCodec(),
            ),
          ),
        ),
        child,
      ],
    );
  }

  Widget _fallback() {
    final shape = radius == null
        ? const StadiumBorder()
        : RoundedRectangleBorder(borderRadius: BorderRadius.circular(radius!));
    return ClipPath(
      clipper: ShapeBorderClipper(shape: shape),
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 16, sigmaY: 16),
        child: DecoratedBox(
          decoration: ShapeDecoration(
            shape: shape.copyWith(
              side: BorderSide(
                  color: Colors.white.withValues(alpha: 0.14), width: 0.8),
            ),
            color: tint ?? Colors.white.withValues(alpha: 0.12),
          ),
          child: child,
        ),
      ),
    );
  }
}

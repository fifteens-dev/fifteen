import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// 上→下に連続的にフェードする「ぼかし」オーバーレイ（iOS ネイティブ）。
///
/// iOS では `UIVisualEffectView` + `CAGradientLayer` マスクの PlatformView
/// （[VariableBlurFactory]）を使い、GPU 合成で軽量に連続ぼかしを描く。
/// タッチはネイティブ側で常に背後へ通すので、下の一覧はそのまま操作できる。
/// iOS 以外では何も描かない（[SizedBox.shrink]）。
class VariableBlur extends StatelessWidget {
  /// 上からこの割合(0..1)まではフルにぼかす。
  final double fullUntil;

  /// この割合(0..1)でぼかしが 0 になる。
  final double fadeEnd;

  /// ぼかしの重ね枚数（1〜3）。多いほど全体的に強くぼける。
  final int passes;

  const VariableBlur({
    super.key,
    this.fullUntil = 0.4,
    this.fadeEnd = 1.0,
    this.passes = 1,
  });

  @override
  Widget build(BuildContext context) {
    if (!Platform.isIOS) return const SizedBox.shrink();
    return IgnorePointer(
      child: UiKitView(
        viewType: 'com.fifteen/variable_blur',
        creationParams: {
          'fullUntil': fullUntil,
          'fadeEnd': fadeEnd,
          'passes': passes,
        },
        creationParamsCodec: const StandardMessageCodec(),
      ),
    );
  }
}

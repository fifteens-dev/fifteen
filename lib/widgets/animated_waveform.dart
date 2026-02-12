import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import '../services/audio_player_service.dart';

/// 再生中にバーがランダムにアニメーションする波形ウィジェット
/// tempoが指定されている場合、BPMに合わせてアニメーション速度を調整
class AnimatedWaveform extends StatefulWidget {
  final String postId;
  final Color barColor;
  final AudioPlayerService audioService;
  final String? previewUrl;
  final double? tempo; // BPM（例: 120.0）

  const AnimatedWaveform({
    super.key,
    required this.postId,
    required this.barColor,
    required this.audioService,
    this.previewUrl,
    this.tempo,
  });

  @override
  State<AnimatedWaveform> createState() => _AnimatedWaveformState();
}

class _AnimatedWaveformState extends State<AnimatedWaveform>
    with SingleTickerProviderStateMixin {
  late AnimationController _ticker;
  late List<double> _baseHeights;
  late List<double> _displayHeights;
  late List<_BarAnimation> _barAnimations;
  late Random _random;
  StreamSubscription? _playerStateSubscription;
  bool _isAnimating = false;

  static const cardWidth = 363.0;
  static const contentHeight = 294.0;
  static const availableWidth = cardWidth - 24;
  static const barWidth = 2.5;
  static const barMargin = 1.2 * 2;
  static const totalBarWidth = barWidth + barMargin;

  /// デフォルトBPM（tempoが不明な場合）
  static const defaultBpm = 120.0;

  late int barCount;
  late double horizontalMargin;

  /// 現在のBPMからビート間隔（ミリ秒）を計算
  double get _beatMs {
    final bpm = widget.tempo ?? defaultBpm;
    // BPMが極端な値にならないようにクランプ
    final clampedBpm = bpm.clamp(60.0, 240.0);
    return 60000.0 / clampedBpm;
  }

  @override
  void initState() {
    super.initState();
    _random = Random(widget.postId.hashCode);

    final maxBarCount = (availableWidth / totalBarWidth).floor();
    barCount = (maxBarCount * 2 / 3).floor();
    final totalBarWidthOnly = barCount * barWidth;
    final remainingWidth = availableWidth - totalBarWidthOnly;
    horizontalMargin = (remainingWidth / barCount) / 2;

    _baseHeights = List.generate(barCount, (index) {
      final normalizedIndex = index / (barCount - 1).toDouble();
      final angle = -pi / 4 + normalizedIndex * 1.5 * pi;
      final waveValue = sin(angle).abs();
      final baseHeight = 0.3 + waveValue * 0.7;
      final randomVariation = (_random.nextDouble() - 0.5) * 6;
      return (5.0 + (baseHeight * 28.0) + randomVariation).clamp(10.0, 48.0);
    });

    _displayHeights = List.from(_baseHeights);

    // 各バーに独立したアニメーションパラメータを割り当て
    _barAnimations = List.generate(barCount, (i) {
      return _BarAnimation(
        from: _baseHeights[i],
        to: _baseHeights[i],
        duration: _randomDuration(),
        elapsed: Duration.zero,
      );
    });

    // 60fpsで駆動するティッカー
    _ticker = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
    )
      ..addListener(_onTick)
      ..repeat();

    _playerStateSubscription =
        widget.audioService.playerStateStream.listen((_) {
      if (!mounted) return;
      _updateAnimationState();
    });

    _updateAnimationState();
  }

  @override
  void didUpdateWidget(AnimatedWaveform oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.previewUrl != widget.previewUrl) {
      _updateAnimationState();
    }
  }

  void _updateAnimationState() {
    final url = widget.previewUrl;
    final shouldAnimate =
        url != null && widget.audioService.isPlayingUrl(url);

    if (shouldAnimate && !_isAnimating) {
      _isAnimating = true;
      // 各バーに新しいターゲットをばらばらのタイミングで設定
      for (int i = 0; i < barCount; i++) {
        _assignNewTarget(i);
      }
    } else if (!shouldAnimate && _isAnimating) {
      _isAnimating = false;
      // ベース高さに戻すアニメーション
      for (int i = 0; i < barCount; i++) {
        _barAnimations[i] = _BarAnimation(
          from: _displayHeights[i],
          to: _baseHeights[i],
          duration: const Duration(milliseconds: 200),
          elapsed: Duration.zero,
        );
      }
    }
  }

  /// BPMに基づいたランダムな遷移時間
  /// 1ビート〜2ビートの間でランダムに設定
  Duration _randomDuration() {
    final beat = _beatMs;
    // 0.5ビート〜1.5ビートの範囲
    final minMs = (beat * 0.5).round();
    final rangeMs = beat.round();
    return Duration(milliseconds: minMs + _random.nextInt(rangeMs.clamp(1, 1000)));
  }

  /// BPMに基づく変動幅の倍率（0.0〜1.0）
  /// テンポが速いほど大きく動く
  double get _variationScale {
    final bpm = (widget.tempo ?? defaultBpm).clamp(60.0, 240.0);
    // 60BPM → 0.3, 120BPM → 0.6, 180BPM → 0.9, 240BPM → 1.0
    return ((bpm - 60.0) / 180.0 * 0.7 + 0.3).clamp(0.3, 1.0);
  }

  /// バーに新しいターゲット高さを割り当て
  void _assignNewTarget(int i) {
    // 変動幅: BPMに応じてスケール
    // 低BPM: 5%〜25%, 高BPM: 10%〜60%
    final scale = _variationScale;
    final minRatio = 0.05 + scale * 0.05;
    final maxRatio = 0.25 + scale * 0.35;
    final maxVariationRatio = minRatio + _random.nextDouble() * (maxRatio - minRatio);
    final variation = _baseHeights[i] * maxVariationRatio;
    final target = (_baseHeights[i] +
            (_random.nextDouble() - 0.5) * 2 * variation)
        .clamp(3.0, 52.0);

    _barAnimations[i] = _BarAnimation(
      from: _displayHeights[i],
      to: target,
      duration: _randomDuration(),
      elapsed: Duration.zero,
    );
  }

  DateTime _lastTick = DateTime.now();

  void _onTick() {
    final now = DateTime.now();
    final dt = now.difference(_lastTick);
    _lastTick = now;

    bool needsRebuild = false;

    for (int i = 0; i < barCount; i++) {
      final anim = _barAnimations[i];
      anim.elapsed += dt;

      // 0.0〜1.0の進行度（ease-in-out）
      final rawT =
          (anim.elapsed.inMicroseconds / anim.duration.inMicroseconds)
              .clamp(0.0, 1.0);
      final t = _easeInOut(rawT);

      final newHeight = anim.from + (anim.to - anim.from) * t;
      if (newHeight != _displayHeights[i]) {
        _displayHeights[i] = newHeight;
        needsRebuild = true;
      }

      // このバーのアニメーションが完了
      if (rawT >= 1.0 && _isAnimating) {
        _assignNewTarget(i);
      }
    }

    if (needsRebuild) {
      setState(() {});
    }
  }

  /// ease-in-out カーブ
  double _easeInOut(double t) {
    return t < 0.5 ? 2 * t * t : -1 + (4 - 2 * t) * t;
  }

  @override
  void dispose() {
    _playerStateSubscription?.cancel();
    _ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: contentHeight * (32 / 294),
      child: Row(
        children: List.generate(barCount, (index) {
          return Container(
            width: barWidth,
            height: _displayHeights[index],
            margin: EdgeInsets.symmetric(horizontal: horizontalMargin),
            decoration: BoxDecoration(
              color: widget.barColor,
              borderRadius: BorderRadius.circular(2),
            ),
          );
        }),
      ),
    );
  }
}

/// 各バーの独立したアニメーション状態
class _BarAnimation {
  double from;
  double to;
  Duration duration;
  Duration elapsed;

  _BarAnimation({
    required this.from,
    required this.to,
    required this.duration,
    required this.elapsed,
  });
}

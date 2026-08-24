import 'dart:math' as math;
import 'dart:ui';
import 'package:flutter/material.dart';

/// リアクションで使う絵文字（Figma 5111:10598 準拠）。左→右。
const List<String> kReactionEmojis = ['😍', '😭', '🔥', '😮', '🫶'];

const Color _kBubbleColor = Color(0x8C2A2A2E); // rgba(42,42,46,0.55)

// ── Figma 5111:10598 準拠の実寸（363幅カード座標）────────────────
// 吹き出し枠は 331×51、尻尾は 42×20（left 20, top 47）で合計高さ 67。
const double _kBubbleW = 331; // 吹き出し幅
const double _kBubbleH = 51; // 吹き出し高さ
const double _kFrameH = 67; // 枠全体（吹き出し+尻尾）の高さ
const double _kEmojiSize = 32; // 絵文字サイズ
const double _kEmojiTop = 9; // 絵文字の上端
const List<double> _kEmojiCenters = [35, 101, 166, 232, 298]; // 各絵文字の中心X
const double _kBubbleRadius = 25; // 角丸

/// 絵文字ピッカーの吹き出し（下向きの尻尾つき・すりガラス）。Figma の実寸を
/// [scale]（カードの表示倍率 = cardWidth/363）で拡縮して 1:1 で再現する。
class ReactionPickerBubble extends StatelessWidget {
  final ValueChanged<String> onSelected;
  final double scale;

  /// 吹き出し左端から尻尾の先端（左下の頂点）までの距離（拡大後の実px）。
  /// スマイル中心を指すよう呼び出し側から渡す。null のとき Figma 既定(20×scale)。
  final double? tailTipX;

  const ReactionPickerBubble({
    super.key,
    required this.onSelected,
    this.scale = 1.0,
    this.tailTipX,
  });

  double get width => _kBubbleW * scale;
  double get height => _kFrameH * scale;

  @override
  Widget build(BuildContext context) {
    final s = scale;
    return SizedBox(
      width: width,
      height: height,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // 吹き出し本体（すりガラス + 角丸）
          Positioned(
            left: 0,
            top: 0,
            width: _kBubbleW * s,
            height: _kBubbleH * s,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(_kBubbleRadius * s),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                child: Container(
                  decoration: BoxDecoration(
                    color: _kBubbleColor,
                    borderRadius: BorderRadius.circular(_kBubbleRadius * s),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.25),
                        blurRadius: 24 * s,
                        offset: Offset(0, 6 * s),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          // 尻尾（三角）は非表示。
          // 絵文字（中心Xを Figma 値に合わせて配置）。高さ/幅を固定枠で縛ると
          // グリフが枠からはみ出て overflow になるため、サイズ制約は付けない。
          for (int i = 0; i < kReactionEmojis.length; i++)
            Positioned(
              left: (_kEmojiCenters[i] - _kEmojiSize / 2) * s,
              top: _kEmojiTop * s,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => onSelected(kReactionEmojis[i]),
                child: Text(
                  kReactionEmojis[i],
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: _kEmojiSize * s, height: 1.0),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// タップした絵文字が上へふわっと上がって消えるアニメーション。
/// 5〜8個・上昇・0.8〜1.0秒で消える。全画面 [IgnorePointer] の Overlay として使う。
class ReactionBurstOverlay extends StatefulWidget {
  final Offset origin; // スマイルボタンのグローバル中心
  final String emoji;
  final VoidCallback onDone;
  const ReactionBurstOverlay({
    super.key,
    required this.origin,
    required this.emoji,
    required this.onDone,
  });

  @override
  State<ReactionBurstOverlay> createState() => _ReactionBurstOverlayState();
}

class _ReactionBurstOverlayState extends State<ReactionBurstOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;
  late final List<_Particle> _particles;

  @override
  void initState() {
    super.initState();
    final rnd = math.Random();
    final count = 12 + rnd.nextInt(5); // 12〜16個で画面を埋める
    _particles = List.generate(count, (_) {
      return _Particle(
        fx: 0.04 + rnd.nextDouble() * 0.92, // 画面幅いっぱいに散らす(0..1)
        startYFrac: 0.78 + rnd.nextDouble() * 0.30, // 画面下部から出る(0..1)
        riseFrac: 0.6 + rnd.nextDouble() * 0.5, // 画面高の60〜110%上昇
        size: 40 + rnd.nextDouble() * 36, // 40〜76（大きめ）
        delay: rnd.nextDouble() * 0.30, // 出だしのばらつき
        sway: (rnd.nextDouble() * 2 - 1) * 28, // 左右の揺れ
        rot: (rnd.nextDouble() * 2 - 1) * 0.5, // わずかな回転
      );
    });
    _c = AnimationController(
      vsync: this,
      // ゆっくり長めに（画面を横断してふわっと消える）。
      duration: const Duration(milliseconds: 1500),
    )..addStatusListener((s) {
        if (s == AnimationStatus.completed) widget.onDone();
      });
    _c.forward();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    return IgnorePointer(
      // Overlay 直下は Material が無く Text（絵文字）に黄色い二重下線が付くため、
      // 透明 Material で包んで DefaultTextStyle を供給する。
      child: Material(
        type: MaterialType.transparency,
        child: AnimatedBuilder(
          animation: _c,
          builder: (context, _) {
            final t = _c.value;
            return Stack(
              children: [
                for (final p in _particles) _buildParticle(p, t, size),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildParticle(_Particle p, double t, Size size) {
    final local =
        p.delay >= 1 ? 0.0 : ((t - p.delay) / (1 - p.delay)).clamp(0.0, 1.0);
    if (local <= 0) return const SizedBox.shrink();
    final eased = Curves.easeOut.transform(local);
    // 画面下部から出て、画面高いっぱいに上昇。X は全幅に散らして揺らす。
    final startY = p.startYFrac * size.height;
    final y = startY - p.riseFrac * size.height * eased;
    final x = p.fx * size.width + p.sway * math.sin(local * math.pi);
    // 立ち上がりで拡大 → しばらく維持 → 後半でゆっくりフェードアウト（長めに残す）。
    final scale = 0.5 + 0.5 * math.min(local * 3, 1.0);
    final double opacity;
    if (local < 0.1) {
      opacity = local / 0.1; // フェードイン
    } else if (local < 0.6) {
      opacity = 1.0; // しばらく維持
    } else {
      opacity = 1.0 - (local - 0.6) / 0.4; // 後半でフェードアウト
    }
    return Positioned(
      left: x - p.size / 2,
      top: y - p.size / 2,
      child: Opacity(
        opacity: opacity.clamp(0.0, 1.0),
        child: Transform.rotate(
          angle: p.rot * eased,
          child: Transform.scale(
            scale: scale,
            child: Text(widget.emoji, style: TextStyle(fontSize: p.size)),
          ),
        ),
      ),
    );
  }
}

class _Particle {
  final double fx; // 開始Xの画面幅に対する割合(0..1)
  final double startYFrac; // 開始Yの画面高に対する割合(0..1)
  final double riseFrac; // 上昇量の画面高に対する割合
  final double size; // 絵文字サイズ
  final double delay; // 出だしの遅延(0..1)
  final double sway; // 左右の揺れ(px)
  final double rot; // 回転(rad)
  const _Particle({
    required this.fx,
    required this.startYFrac,
    required this.riseFrac,
    required this.size,
    required this.delay,
    required this.sway,
    required this.rot,
  });
}

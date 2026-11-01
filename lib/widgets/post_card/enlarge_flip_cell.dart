import 'package:flutter/material.dart';

import '../post_card.dart';

/// グリッドの 1 マス。タップでその場から拡大し、0.2 秒後に裏へ反転する。
///
/// ホームの旧 2 列グリッド（home_grid_cell.dart の _GridPostCell）と同じ動き。
/// 違いはマスに出すものを [cell] で別に描けること。グループ画面では省略した
/// 表面（Figma 6308:12346）をマスに置き、拡大したら本物の [PostCard] を出す。
///
/// 拡大中のカードはルートのオーバーレイに別インスタンスで作る。もう一度
/// タップするか、カードの外をタップすると表へ戻して縮める。
class EnlargeFlipCell extends StatefulWidget {
  /// マスに出す中身。
  final Widget cell;

  /// 拡大したときのカード。key は必ず [PostCard] に付ける（反転に使う）。
  /// onTap はカードのタップ（閉じる）、requestClose はシートを開く前に即閉じる。
  final Widget Function(GlobalKey<PostCardState> key, VoidCallback onTap,
      VoidCallback requestClose) cardBuilder;

  const EnlargeFlipCell({
    super.key,
    required this.cell,
    required this.cardBuilder,
  });

  @override
  State<EnlargeFlipCell> createState() => _EnlargeFlipCellState();
}

class _EnlargeFlipCellState extends State<EnlargeFlipCell>
    with SingleTickerProviderStateMixin {
  final GlobalKey _cellKey = GlobalKey();
  final GlobalKey<PostCardState> _cardKey = GlobalKey<PostCardState>();
  late final AnimationController _anim;
  OverlayEntry? _entry;
  Rect _startRect = Rect.zero;
  bool _active = false;

  static const double _sidePadding = 15.0;
  // PostCard の縦横比（363:645）。
  static const double _cardAspect = 363 / 645;

  @override
  void initState() {
    super.initState();
    _anim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 220),
    )..addListener(() => _entry?.markNeedsBuild());
  }

  @override
  void dispose() {
    _removeEntry();
    _anim.dispose();
    super.dispose();
  }

  void _onTap() => _active ? _close() : _open();

  void _open() {
    final box = _cellKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return;
    // マスと縦横比が違うので、マスの幅に合わせたカードの矩形から広げる。
    final origin = box.localToGlobal(Offset.zero);
    final w = box.size.width;
    final h = w / _cardAspect;
    _startRect = Rect.fromLTWH(
        origin.dx, origin.dy + (box.size.height - h) / 2, w, h);
    _active = true;
    setState(() {});
    _entry = OverlayEntry(builder: _buildOverlay);
    Overlay.of(context, rootOverlay: true).insert(_entry!);
    _anim.forward(from: 0);
    Future.delayed(const Duration(milliseconds: 200), () {
      if (!_active) return;
      _cardKey.currentState?.flipToBack(playAudio: true);
    });
  }

  Future<void> _close() async {
    _cardKey.currentState?.flipToFront();
    try {
      await _anim.reverse();
    } catch (_) {}
    _removeEntry();
    if (mounted) setState(() {});
  }

  void _closeNow() {
    if (!_active) return;
    _anim.stop();
    _cardKey.currentState?.flipToFront();
    _removeEntry();
    if (mounted) setState(() {});
  }

  void _removeEntry() {
    _entry?.remove();
    _entry = null;
    _active = false;
  }

  Rect _targetRect(Size media) {
    double w = media.width - _sidePadding * 2;
    double h = w / _cardAspect;
    final maxH = media.height - 120;
    if (h > maxH) {
      h = maxH;
      w = h * _cardAspect;
    }
    return Rect.fromLTWH((media.width - w) / 2, (media.height - h) / 2, w, h);
  }

  Widget _buildOverlay(BuildContext ctx) {
    final media = MediaQuery.of(ctx).size;
    final t = Curves.easeOut.transform(_anim.value);
    final rect = Rect.lerp(_startRect, _targetRect(media), t)!;
    return Stack(
      children: [
        // 暗転はしない。カードの外をタップで閉じる。
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _close,
            child: const SizedBox.expand(),
          ),
        ),
        Positioned.fromRect(
          rect: rect,
          child: Opacity(
            // 広がり始めはマスの省略表示と重なるので、少し遅れて出す。
            opacity: (t * 3).clamp(0.0, 1.0),
            child: Material(
              type: MaterialType.transparency,
              child: FittedBox(
                fit: BoxFit.contain,
                child: widget.cardBuilder(_cardKey, _onTap, _closeNow),
              ),
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      key: _cellKey,
      behavior: HitTestBehavior.opaque,
      onTap: _onTap,
      // 拡大中はマスを空ける（二重に見えないように）。
      child: Opacity(opacity: _active ? 0 : 1, child: widget.cell),
    );
  }
}

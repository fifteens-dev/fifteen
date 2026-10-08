part of '../home_screen.dart';

/// ホーム2列グリッドの1セル。
/// タップすると、その投稿カードが元の位置から**拡大**し（オーバーレイで前面に浮かせて
/// 中央・1列幅へ）、0.2秒後に自動で裏面へ反転する。もう一度タップ（またはカード外
/// タップ）で表面へ戻し縮小。
///
/// 拡大表示はオーバーレイに**別インスタンスの PostCard**（[_overlayCardKey]）を生成して
/// 行う。セル内カードを移動させないため、従来通りの裏返しアニメーションが確実に動く。
/// 拡大中はセル側を空プレースホルダにして二重描画・二重再生を防ぐ。
class _GridPostCell extends StatefulWidget {
  final GlobalKey<PostCardState> cardKey;
  /// builder(key, onTap, requestClose): key=カードに付与する GlobalKey、
  /// onTap=カードタップ処理、requestClose=拡大を即キャンセル。
  final Widget Function(GlobalKey<PostCardState> key, VoidCallback onTap,
      VoidCallback requestClose) builder;
  /// 拡大オーバーレイの表示/非表示が変わったとき（true=表示中）に通知。
  final ValueChanged<bool>? onEnlargedChanged;

  const _GridPostCell({
    super.key,
    required this.cardKey,
    required this.builder,
    this.onEnlargedChanged,
  });

  @override
  State<_GridPostCell> createState() => _GridPostCellState();
}

class _GridPostCellState extends State<_GridPostCell>
    with SingleTickerProviderStateMixin {
  final GlobalKey _cellKey = GlobalKey();
  // オーバーレイの拡大カード用（セル内カードとは別インスタンス）。
  final GlobalKey<PostCardState> _overlayCardKey = GlobalKey<PostCardState>();
  late final AnimationController _anim; // 0=セル内, 1=拡大
  OverlayEntry? _entry;
  Rect _startRect = Rect.zero;
  bool _active = false;

  // 1列タイムラインと同じ左右padding（15px）。拡大時はこの幅の中央配置にする。
  static const double _oneColPadding = 15.0;
  // PostCard 前面の縦横比（363:645）。
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

  void _onTap() {
    if (!_active) {
      _open();
    } else {
      _close();
    }
  }

  void _open() {
    final box = _cellKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return;
    _startRect = box.localToGlobal(Offset.zero) & box.size;
    _active = true;
    widget.onEnlargedChanged?.call(true);
    setState(() {}); // セル → プレースホルダ（拡大カードはオーバーレイに別途生成）
    _entry = OverlayEntry(builder: _buildOverlay);
    Overlay.of(context, rootOverlay: true).insert(_entry!);
    _anim.forward(from: 0);
    // 拡大後 0.2秒で反転＋音楽再生。
    // 「投稿しないと裏返せない」制限は廃止したので、常に反転してよい。
    Future.delayed(const Duration(milliseconds: 200), () {
      if (!_active) return;
      _overlayCardKey.currentState?.flipToBack(playAudio: true);
    });
  }

  Future<void> _close() async {
    _overlayCardKey.currentState?.flipToFront();
    try {
      await _anim.reverse();
    } catch (_) {}
    _removeEntry();
    if (mounted) setState(() {}); // カードをセルへ戻す
  }

  /// アニメーションなしで即座に拡大をキャンセルする。
  /// 共有/コメント/削除など別シートを開く直前に呼び、シートの上に残らないようにする。
  void _closeNow() {
    if (!_active) return;
    _anim.stop();
    _overlayCardKey.currentState?.flipToFront();
    _removeEntry();
    if (mounted) setState(() {});
  }

  void _removeEntry() {
    _entry?.remove();
    _entry = null;
    _active = false;
    widget.onEnlargedChanged?.call(false);
  }

  /// 拡大の目標矩形 = 1列配置と同じ「中央・1列カード幅」。
  Rect _targetRect(Size media) {
    // 1列カード幅（左右15pxマージン）。ただし高さが画面に収まらない場合は高さ基準に。
    double w = media.width - _oneColPadding * 2;
    double h = w / _cardAspect;
    final maxH = media.height - 120; // 上下マージン
    if (h > maxH) {
      h = maxH;
      w = h * _cardAspect;
    }
    final left = (media.width - w) / 2;
    final top = (media.height - h) / 2;
    return Rect.fromLTWH(left, top, w, h);
  }

  Widget _buildOverlay(BuildContext ctx) {
    final media = MediaQuery.of(ctx).size;
    final t = Curves.easeOut.transform(_anim.value);
    // セル位置 → 中央1列位置へ補間（縦横比は一定なので歪みなし）。
    final rect = Rect.lerp(_startRect, _targetRect(media), t)!;
    return Stack(
      children: [
        // 透明バリア（暗転なし）。カード外タップで閉じる。スクロールも遮る。
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _close,
            child: const SizedBox.expand(),
          ),
        ),
        Positioned(
          left: rect.left,
          top: rect.top,
          width: rect.width,
          height: rect.height,
          // Material の祖先を与えないと Text に黄色い二重下線が出るため透明 Material で包む。
          child: Material(
            type: MaterialType.transparency,
            child: FittedBox(
              fit: BoxFit.contain,
              // 拡大カードは別インスタンス（_overlayCardKey）。従来通り反転可能。
              child: widget.builder(_overlayCardKey, _onTap, _closeNow),
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox.expand(
      key: _cellKey,
      child: _active
          ? const SizedBox.expand() // 拡大中はセル内カードを退避（空表示）
          : RepaintBoundary(
              child: FittedBox(
                fit: BoxFit.contain,
                child: widget.builder(widget.cardKey, _onTap, _closeNow),
              ),
            ),
    );
  }
}

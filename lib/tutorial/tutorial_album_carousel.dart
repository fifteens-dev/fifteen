import 'dart:async';
import 'package:flutter/material.dart';

/// Figma node `65:4203` (Component 114) のFlutter実装。
///
/// 仕様:
/// - 横幅 402、高さ 270 のコンテナ
/// - 3 種類のアルバムカード（250×250）が無限ループするカルーセル
/// - 中央のアクティブカードは 270×270（縦に拡張）に拡大
/// - viewportFraction で左右に隣接カードのピーク表示
/// - 自動スクロール（4秒ごと）+ 手動スワイプ両対応
/// - スクロール中はアクティブ度に応じてスケールが滑らかに補間
class TutorialAlbumCarousel extends StatefulWidget {
  /// 自動再生の有無
  final bool autoplay;

  /// 自動再生の間隔（デフォルト 6 秒）
  final Duration autoplayInterval;

  /// アクティブカードが切り替わったときに呼ばれる
  final ValueChanged<int>? onActiveChanged;

  /// 表示するアルバム群（指定しなければデフォルト3曲）
  final List<TutorialAlbumItem>? items;

  const TutorialAlbumCarousel({
    super.key,
    this.autoplay = true,
    this.autoplayInterval = const Duration(seconds: 6),
    this.onActiveChanged,
    this.items,
  });

  /// Figma に登場する 3 アルバム
  static const List<TutorialAlbumItem> defaultItems = [
    TutorialAlbumItem(
      assetPath: 'assets/images/tutorial/album_sukisugite.png',
      title: '好きすぎて滅!',
      artist: 'MiLK',
    ),
    TutorialAlbumItem(
      assetPath: 'assets/images/tutorial/album_bakuretsu.png',
      title: '爆裂愛してる',
      artist: 'MiLK',
    ),
    TutorialAlbumItem(
      assetPath: 'assets/images/tutorial/album_blueamber.png',
      title: 'ブルーアンバー',
      artist: 'back number',
    ),
  ];

  /// 無限スクロール用の初期ページ番号（_CarouselSection でも参照する）
  static const int initialPage = 10000;

  @override
  State<TutorialAlbumCarousel> createState() => _TutorialAlbumCarouselState();
}

class _TutorialAlbumCarouselState extends State<TutorialAlbumCarousel> {
  late final PageController _pageController;
  Timer? _autoplayTimer;
  int _lastReportedActive = -1;

  List<TutorialAlbumItem> get _items =>
      widget.items ?? TutorialAlbumCarousel.defaultItems;

  @override
  void initState() {
    super.initState();
    // viewportFraction = 250 / 402 で隣接カードがピーク表示
    _pageController = PageController(
      initialPage: TutorialAlbumCarousel.initialPage,
      viewportFraction: 270.0 / 402.0,
    );
    _pageController.addListener(_onPageChange);
    _scheduleAutoplay();
  }

  @override
  void dispose() {
    _autoplayTimer?.cancel();
    _pageController.removeListener(_onPageChange);
    _pageController.dispose();
    super.dispose();
  }

  void _onPageChange() {
    if (!_pageController.hasClients) return;
    final raw = _pageController.page ?? TutorialAlbumCarousel.initialPage.toDouble();
    final activeIndex = raw.round() % _items.length;
    if (activeIndex != _lastReportedActive) {
      _lastReportedActive = activeIndex;
      widget.onActiveChanged?.call(activeIndex);
    }
  }

  void _scheduleAutoplay() {
    if (!widget.autoplay) return;
    _autoplayTimer?.cancel();
    _autoplayTimer = Timer.periodic(widget.autoplayInterval, (_) {
      if (!mounted || !_pageController.hasClients) return;
      _pageController.nextPage(
        duration: const Duration(milliseconds: 700),
        curve: Curves.easeInOut,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 402,
      height: 270,
      child: NotificationListener<ScrollNotification>(
        onNotification: (notification) {
          // ユーザー操作中は自動再生を止め、操作後に再開
          if (notification is ScrollStartNotification) {
            _autoplayTimer?.cancel();
          } else if (notification is ScrollEndNotification) {
            _scheduleAutoplay();
          }
          return false;
        },
        child: PageView.builder(
          controller: _pageController,
          // 無限スクロール
          itemBuilder: (context, index) => _buildItem(index),
        ),
      ),
    );
  }

  Widget _buildItem(int index) {
    final item = _items[index % _items.length];
    return GestureDetector(
      // サイドカード（左右にはみ出た部分）をタップしてもそのカードへ移動
      onTap: () {
        _pageController.animateToPage(
          index,
          duration: const Duration(milliseconds: 400),
          curve: Curves.easeInOut,
        );
      },
      child: AnimatedBuilder(
        animation: _pageController,
        builder: (context, child) {
          double pageOffset = 0;
          if (_pageController.position.hasContentDimensions) {
            pageOffset = (_pageController.page ?? TutorialAlbumCarousel.initialPage.toDouble()) - index;
          }
          final t = (1.0 - pageOffset.abs()).clamp(0.0, 1.0);
          // スケール: ピーク 250/270 ≈ 0.926, 中央 1.0
          const minScale = 250.0 / 270.0;
          final scale = minScale + (1.0 - minScale) * t;
          return Center(
            child: Transform.scale(
              scale: scale,
              child: child,
            ),
          );
        },
        child: _AlbumCard(item: item),
      ),
    );
  }
}

/// カルーセルに表示する1枚分のアルバム情報
class TutorialAlbumItem {
  final String assetPath;
  final String title;
  final String artist;

  const TutorialAlbumItem({
    required this.assetPath,
    required this.title,
    required this.artist,
  });
}

/// 1枚分のカード描画
class _AlbumCard extends StatelessWidget {
  final TutorialAlbumItem item;
  const _AlbumCard({required this.item});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 270,
      height: 270,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.4),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Image.asset(
          item.assetPath,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => Container(color: Colors.grey[800]),
        ),
      ),
    );
  }
}

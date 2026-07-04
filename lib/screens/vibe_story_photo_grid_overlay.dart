import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:photo_manager/photo_manager.dart';

/// Vibe ストーリー投稿プレビュー画面の左下「投稿者アイコン」をタップして開く
/// 写真グリッドのオーバーレイ。
///
/// チュートリアル `tutorial_camera_overlay.dart` の写真グリッドと同じ構造:
///   - 3列、aspect 9/16、間隔 1px
///   - 写真は端末ライブラリから photo_manager で取得
///   - 上端は丸角 (15px)
///   - 下からフェードイン + 軽くスライドアップで上に被せる
class VibeStoryPhotoGridOverlay extends StatefulWidget {
  /// 写真選択時のコールバック（バイト列を返す）
  final ValueChanged<Uint8List> onPhotoSelected;

  const VibeStoryPhotoGridOverlay({
    super.key,
    required this.onPhotoSelected,
  });

  /// 下からフェードイン + スライドアップで開く便利メソッド。
  /// 既存ルートの上に被せる形（[opaque: false]）。
  static Future<T?> show<T>(
    BuildContext context, {
    required ValueChanged<Uint8List> onPhotoSelected,
  }) {
    return Navigator.of(context).push<T>(
      PageRouteBuilder<T>(
        opaque: false,
        barrierColor: Colors.black.withValues(alpha: 0.45),
        barrierDismissible: true,
        transitionDuration: const Duration(milliseconds: 260),
        reverseTransitionDuration: const Duration(milliseconds: 200),
        pageBuilder: (_, __, ___) => VibeStoryPhotoGridOverlay(
          onPhotoSelected: onPhotoSelected,
        ),
        transitionsBuilder: (_, anim, __, child) {
          final curved = CurvedAnimation(
            parent: anim,
            curve: Curves.easeOutCubic,
            reverseCurve: Curves.easeIn,
          );
          return FadeTransition(
            opacity: curved,
            child: SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(0, 0.15),
                end: Offset.zero,
              ).animate(curved),
              child: child,
            ),
          );
        },
      ),
    );
  }

  @override
  State<VibeStoryPhotoGridOverlay> createState() =>
      _VibeStoryPhotoGridOverlayState();
}

class _VibeStoryPhotoGridOverlayState extends State<VibeStoryPhotoGridOverlay>
    with SingleTickerProviderStateMixin {
  final ScrollController _gridScrollController = ScrollController();
  AssetPathEntity? _selectedAlbum;
  List<AssetEntity> _galleryAssets = [];
  bool _hasPermission = false;
  bool _isLoading = true;
  bool _isLoadingMore = false;
  bool _hasMorePhotos = false;
  int _currentGalleryPage = 0;

  static const int _initialLoad = 60;
  static const int _pageSize = 60;

  // ── ドラッグでシート閉じ ──────────────────────────
  // シートの追加下方向オフセット（0 = 通常位置、正の値 = 下に流れている）。
  double _dragOffset = 0.0;
  double _sheetHeight = 0.0; // 現在のシート高（レイアウトごとに更新）
  bool _dismissing = false;
  Animation<double>? _snapAnim;
  late final AnimationController _snapCtrl;

  @override
  void initState() {
    super.initState();
    _snapCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 220),
    );
    _loadGalleryImages();
    _gridScrollController.addListener(_onGridScroll);
  }

  @override
  void dispose() {
    _snapCtrl.dispose();
    _gridScrollController.dispose();
    super.dispose();
  }

  // ドラッグ開始: 進行中のスプリング戻しを止める
  void _onSheetDragStart(DragStartDetails _) {
    _snapCtrl.stop();
  }

  void _onSheetDragUpdate(DragUpdateDetails d) {
    if (_dismissing) return;
    setState(() {
      _dragOffset = math.max(0.0, _dragOffset + d.delta.dy);
    });
  }

  void _onSheetDragEnd(DragEndDetails d) {
    if (_dismissing) return;
    final velocityY = d.velocity.pixelsPerSecond.dy;
    // シート高の 22% 超え、または下方向 900px/s 超のフリックで閉じる
    final shouldDismiss =
        _dragOffset > _sheetHeight * 0.22 || velocityY > 900;
    if (shouldDismiss) {
      _animateDismiss();
    } else {
      _animateSnapBack();
    }
  }

  void _animateSnapBack() {
    _snapCtrl.stop();
    _snapCtrl.duration = const Duration(milliseconds: 220);
    _snapAnim = Tween<double>(begin: _dragOffset, end: 0.0)
        .animate(CurvedAnimation(parent: _snapCtrl, curve: Curves.easeOutCubic))
      ..addListener(_onSnapTick);
    _snapCtrl.reset();
    _snapCtrl.forward();
  }

  void _animateDismiss() {
    _dismissing = true;
    _snapCtrl.stop();
    _snapCtrl.duration = const Duration(milliseconds: 180);
    _snapAnim = Tween<double>(begin: _dragOffset, end: _sheetHeight)
        .animate(CurvedAnimation(parent: _snapCtrl, curve: Curves.easeOut))
      ..addListener(_onSnapTick);
    _snapCtrl.reset();
    _snapCtrl.forward().then((_) {
      if (mounted) Navigator.of(context).maybePop();
    });
  }

  void _onSnapTick() {
    if (!mounted) return;
    setState(() => _dragOffset = _snapAnim!.value);
  }

  // グリッド最上部でさらに下に引いた場合もシートドラッグとして扱う
  bool _onGridScrollNotification(ScrollNotification n) {
    if (_dismissing) return false;
    if (n is OverscrollNotification && n.overscroll < 0) {
      // 上端で下方向へのオーバースクロール（overscroll は負値）
      setState(() {
        _dragOffset = math.max(0.0, _dragOffset + (-n.overscroll));
      });
      return true;
    }
    if (n is ScrollEndNotification && _dragOffset > 0) {
      final vy = n.dragDetails?.velocity.pixelsPerSecond.dy ?? 0.0;
      _onSheetDragEnd(DragEndDetails(
        velocity: Velocity(pixelsPerSecond: Offset(0, vy)),
      ));
      return true;
    }
    return false;
  }

  Future<void> _loadGalleryImages() async {
    final permission = await PhotoManager.requestPermissionExtend();
    if (!permission.isAuth && !permission.hasAccess) {
      if (mounted) {
        setState(() {
          _hasPermission = false;
          _isLoading = false;
        });
      }
      return;
    }
    if (mounted) setState(() => _hasPermission = true);

    final albums = await PhotoManager.getAssetPathList(
      type: RequestType.image,
      filterOption: FilterOptionGroup(
        imageOption: const FilterOption(
            sizeConstraint: SizeConstraint(ignoreSize: true)),
        orders: [
          const OrderOption(type: OrderOptionType.createDate, asc: false)
        ],
      ),
    );
    if (albums.isEmpty) {
      if (mounted) setState(() => _isLoading = false);
      return;
    }
    _selectedAlbum = albums.first;
    await _loadAlbumAssets(_selectedAlbum!);
  }

  Future<void> _loadAlbumAssets(AssetPathEntity album) async {
    final assets = await album.getAssetListRange(start: 0, end: _initialLoad);
    final totalCount = await album.assetCountAsync;
    if (!mounted) return;
    setState(() {
      _galleryAssets = assets;
      _currentGalleryPage = _initialLoad;
      _hasMorePhotos = _initialLoad < totalCount;
      _isLoading = false;
    });
  }

  void _onGridScroll() {
    if (!_gridScrollController.hasClients) return;
    if (_gridScrollController.position.pixels >=
        _gridScrollController.position.maxScrollExtent - 800) {
      _loadMorePhotos();
    }
  }

  Future<void> _loadMorePhotos() async {
    if (_isLoadingMore || !_hasMorePhotos || _selectedAlbum == null) return;
    _isLoadingMore = true;
    final totalCount = await _selectedAlbum!.assetCountAsync;
    final end = (_currentGalleryPage + _pageSize).clamp(0, totalCount);
    final assets = await _selectedAlbum!
        .getAssetListRange(start: _currentGalleryPage, end: end);
    if (mounted) {
      setState(() {
        _galleryAssets.addAll(assets);
        _currentGalleryPage = end;
        _hasMorePhotos = end < totalCount;
      });
    }
    _isLoadingMore = false;
  }

  Future<void> _onThumbnailTap(int assetIndex) async {
    final asset = _galleryAssets[assetIndex];
    final data = await asset.originBytes;
    if (data == null) return;
    if (!mounted) return;
    widget.onPhotoSelected(data);
    Navigator.of(context).maybePop();
  }

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    // 画面下端から高さ70%ぐらいで開く（チュートリアル写真グリッドと同様の見え方）
    final gridTop = mq.size.height * 0.22;
    // シート高（下端から gridTop まで）— ドラッグ閾値・閉じアニメで参照する。
    _sheetHeight = mq.size.height - gridTop;

    return Material(
      type: MaterialType.transparency,
      child: Stack(
        children: [
          // 背景タップで閉じる
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => Navigator.of(context).maybePop(),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            top: gridTop,
            bottom: 0,
            child: Transform.translate(
              offset: Offset(0, _dragOffset),
              child: ClipRRect(
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(15),
                  topRight: Radius.circular(15),
                ),
                child: ColoredBox(
                  color: const Color(0xFF121212),
                  child: Column(
                    children: [
                      // ハンドル（つまみ）— ここを掴んで下にスワイプするとシートが流れる
                      GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onVerticalDragStart: _onSheetDragStart,
                        onVerticalDragUpdate: _onSheetDragUpdate,
                        onVerticalDragEnd: _onSheetDragEnd,
                        child: SizedBox(
                          height: 28,
                          child: Center(
                            child: Container(
                              width: 40,
                              height: 4,
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.4),
                                borderRadius: BorderRadius.circular(2),
                              ),
                            ),
                          ),
                        ),
                      ),
                      Expanded(
                        child: _isLoading
                            ? const Center(
                                child: CircularProgressIndicator(
                                  color: Colors.white70,
                                  strokeWidth: 2,
                                ),
                              )
                            : !_hasPermission
                                ? _buildPermissionPrompt()
                                : NotificationListener<ScrollNotification>(
                                    onNotification: _onGridScrollNotification,
                                    child: _buildGrid(),
                                  ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGrid() {
    if (_galleryAssets.isEmpty) {
      return const Center(
        child: Text('写真がありません',
            style: TextStyle(color: Colors.white54, fontSize: 13)),
      );
    }
    // GridView は親 MediaQuery の padding.top（ステータスバー/ノッチ分）を
    // 暗黙のトップパディングとして拾ってしまうので、明示的に除去。
    return MediaQuery.removePadding(
      context: context,
      removeTop: true,
      removeBottom: true,
      child: GridView.builder(
        controller: _gridScrollController,
        padding: EdgeInsets.zero,
        physics: const BouncingScrollPhysics(),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3,
          mainAxisSpacing: 1,
          crossAxisSpacing: 1,
          childAspectRatio: 9 / 16,
        ),
        itemCount: _galleryAssets.length,
        itemBuilder: (context, index) {
          return GestureDetector(
            onTap: () => _onThumbnailTap(index),
            child: _ThumbnailImage(
              key: ValueKey(_galleryAssets[index].id),
              asset: _galleryAssets[index],
            ),
          );
        },
      ),
    );
  }

  Widget _buildPermissionPrompt() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.photo_library,
                color: Colors.white54, size: 40),
            const SizedBox(height: 12),
            const Text(
              '写真へのアクセスを許可してください',
              style: TextStyle(color: Colors.white70, fontSize: 13),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            TextButton(
              onPressed: PhotoManager.openSetting,
              child: const Text('設定を開く',
                  style: TextStyle(color: Color(0xFF5D8FFF))),
            ),
          ],
        ),
      ),
    );
  }
}

class _ThumbnailImage extends StatefulWidget {
  final AssetEntity asset;
  const _ThumbnailImage({super.key, required this.asset});

  @override
  State<_ThumbnailImage> createState() => _ThumbnailImageState();
}

class _ThumbnailImageState extends State<_ThumbnailImage> {
  Uint8List? _thumbData;
  String? _loadedId;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(_ThumbnailImage old) {
    super.didUpdateWidget(old);
    if (old.asset.id != widget.asset.id) _load();
  }

  Future<void> _load() async {
    final id = widget.asset.id;
    _loadedId = id;
    final data = await widget.asset
        .thumbnailDataWithSize(const ThumbnailSize(300, 533));
    if (mounted && data != null && _loadedId == id) {
      setState(() => _thumbData = data);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_thumbData != null) {
      return Image.memory(
        _thumbData!,
        fit: BoxFit.cover,
        width: double.infinity,
        height: double.infinity,
        gaplessPlayback: true,
      );
    }
    return Container(color: Colors.grey[800]);
  }
}

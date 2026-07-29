import 'dart:typed_data';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:photo_manager/photo_manager.dart';
import '../models/track_model.dart';
import '../services/audio_player_service.dart';
import '../services/itunes_search_service.dart';
import '../services/lyrics_service.dart';
import '../utils/color_extractor.dart';
import 'post_card_edit_screen.dart';
import 'post_flow/mood_post_final_preview_screen.dart';

/// 投稿フローの写真選択画面（通常フロー専用）
///
/// 上下 2 ページの垂直 PageView 構造:
///   - Page 0: アプリ内カメラプレビュー。シャッターで即撮影→PostCardEditScreen。
///   - Page 1: 3列写真グリッド。写真タップで拡大アニメーション→PostCardEditScreen。
class PostPhotoSelectionScreen extends StatefulWidget {
  final TrackModel track;
  final LyricsData? lyricsData;
  final Future<LyricsData?>? lyricsFuture;
  final bool isVibe;
  final String? vibeTopicId;
  final String? vibeTopicTitle;
  final bool fromVibePlaylist;
  /// 気分投稿フロー (Music Memory 起点) では PostCardEditScreen / 歌詞カード選択を
  /// 経由せず、写真確定でそのまま [MoodPostFinalPreviewScreen] へ飛ばす。
  final bool isMoodPost;

  const PostPhotoSelectionScreen({
    super.key,
    required this.track,
    this.lyricsData,
    this.lyricsFuture,
    this.isVibe = false,
    this.vibeTopicId,
    this.vibeTopicTitle,
    this.fromVibePlaylist = false,
    this.isMoodPost = false,
  });

  @override
  State<PostPhotoSelectionScreen> createState() =>
      _PostPhotoSelectionScreenState();
}

class _PostPhotoSelectionScreenState extends State<PostPhotoSelectionScreen>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  // ---- カメラ ----
  CameraController? _cameraController;
  bool _isCameraInitialized = false;
  bool _isTakingPhoto = false;
  bool _isFrontCamera = false;

  // ---- PageView ----
  final PageController _pageController = PageController();

  // ---- photo_manager ----
  List<AssetEntity> _galleryAssets = [];
  bool _hasPermission = false;
  bool _isLoadingMore = false;
  bool _hasMorePhotos = true;
  int _currentGalleryPage = 0;
  AssetPathEntity? _selectedAlbum;
  final ScrollController _gridScrollController = ScrollController();
  final Map<int, GlobalKey> _thumbKeys = {};
  static const int _initialLoad = 100;
  static const int _pageSize = 70;
  Uint8List? _latestThumbData;

  // ---- ナビゲーション ----
  bool _isNavigating = false;

  // ---- 事前キャッシュ ----
  String? _cachedPreviewUrl;
  Color? _cachedGradientStart;
  Color? _cachedGradientEnd;

  // ---- フラッシュアニメーション ----
  late final AnimationController _flashController;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    AudioPlayerService().stop();
    _flashController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 280),
    );
    _initCamera();
    _loadGalleryImages();
    _gridScrollController.addListener(_onGridScroll);
    _prefetchTrackData();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _cameraController?.dispose();
    _pageController.dispose();
    _gridScrollController.dispose();
    _flashController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_cameraController == null || !_isCameraInitialized) return;
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused) {
      _cameraController!.dispose();
      setState(() => _isCameraInitialized = false);
    } else if (state == AppLifecycleState.resumed) {
      _initCamera();
    }
  }

  // ---- カメラ初期化 ----

  Future<void> _initCamera() async {
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty || !mounted) return;

      final direction = _isFrontCamera
          ? CameraLensDirection.front
          : CameraLensDirection.back;
      final camera = cameras.firstWhere(
        (c) => c.lensDirection == direction,
        orElse: () => cameras.first,
      );

      final controller = CameraController(
        camera,
        ResolutionPreset.high,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.jpeg,
      );

      await controller.initialize();
      if (!mounted) {
        controller.dispose();
        return;
      }

      _cameraController = controller;
      setState(() => _isCameraInitialized = true);
    } catch (_) {}
  }

  // ---- track 事前キャッシュ ----

  Future<void> _prefetchTrackData() async {
    final track = widget.track;
    if (track.trackId.isEmpty) return;
    String? url = track.previewUrl;
    if (url == null || url.isEmpty) {
      url = await ITunesSearchService().getPreviewUrl(
        trackName: track.trackName,
        artistName: track.artistName,
      );
    }
    if (mounted) _cachedPreviewUrl = url;
    if (track.albumImageUrl.isNotEmpty) {
      try {
        final colors =
            await ColorExtractor.extractGradientColors(track.albumImageUrl);
        if (mounted) {
          _cachedGradientStart = colors.$1;
          _cachedGradientEnd = colors.$2;
        }
      } catch (_) {}
    }
  }

  // ---- ギャラリー読み込み ----

  Future<void> _loadGalleryImages() async {
    final permission = await PhotoManager.requestPermissionExtend();
    if (!permission.isAuth && !permission.hasAccess) {
      if (mounted) setState(() => _hasPermission = false);
      return;
    }
    if (mounted) setState(() => _hasPermission = true);

    final albums = await PhotoManager.getAssetPathList(
      type: RequestType.image,
      filterOption: FilterOptionGroup(
        imageOption: const FilterOption(
          sizeConstraint: SizeConstraint(ignoreSize: true),
        ),
        orders: [
          const OrderOption(type: OrderOptionType.createDate, asc: false),
        ],
      ),
    );
    if (albums.isEmpty) return;

    _selectedAlbum = albums.first;
    await _loadAlbumAssets(_selectedAlbum!);
  }

  Future<void> _loadAlbumAssets(AssetPathEntity album) async {
    final assets = await album.getAssetListRange(start: 0, end: _initialLoad);
    final totalCount = await album.assetCountAsync;
    if (mounted) {
      setState(() {
        _galleryAssets = assets;
        _currentGalleryPage = _initialLoad;
        _hasMorePhotos = _initialLoad < totalCount;
        _thumbKeys.clear();
      });
    }
    if (assets.isNotEmpty) {
      final thumb = await assets.first
          .thumbnailDataWithSize(const ThumbnailSize(120, 120));
      if (mounted && thumb != null) {
        setState(() => _latestThumbData = thumb);
      }
    }
  }

  void _onGridScroll() {
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

  // ---- ページ切り替え ----

  void _scrollToGallery() {
    _pageController.animateToPage(
      1,
      duration: const Duration(milliseconds: 480),
      curve: Curves.easeInOutCubic,
    );
  }

  void _scrollToCamera() {
    _pageController.animateToPage(
      0,
      duration: const Duration(milliseconds: 480),
      curve: Curves.easeInOutCubic,
    );
  }

  // ---- カメラ反転 ----

  Future<void> _flipCamera() async {
    final oldController = _cameraController;
    setState(() {
      _isFrontCamera = !_isFrontCamera;
      _isCameraInitialized = false;
      _cameraController = null;
    });
    await oldController?.dispose();
    await _initCamera();
  }

  // ---- 撮影 ----

  Future<void> _onShutter() async {
    if (_isTakingPhoto || _cameraController == null || !_isCameraInitialized) {
      return;
    }
    _isTakingPhoto = true;

    _flashController.reset();
    _flashController.forward();

    try {
      final photo = await _cameraController!.takePicture();
      if (!mounted) return;
      _navigateToEdit(photo);
    } catch (_) {
      if (mounted) _isTakingPhoto = false;
    }
  }

  void _navigateToEdit(XFile photo) {
    if (widget.isMoodPost) {
      // 気分投稿: 歌詞カード編集をスキップ、カメラ/モーダルまでスタックを畳んで
      // ホーム route の上に **透明 route** として MoodPostFinalPreviewScreen を載せる。
      // これで背景にホームが透けて見える。
      Navigator.of(context).pushAndRemoveUntil(
        PageRouteBuilder(
          opaque: false,
          barrierDismissible: false,
          transitionDuration: const Duration(milliseconds: 400),
          pageBuilder: (_, __, ___) => MoodPostFinalPreviewScreen(
            track: widget.track,
            selectedImage: photo,
          ),
          transitionsBuilder: (_, animation, __, child) => FadeTransition(
            opacity: CurvedAnimation(parent: animation, curve: Curves.easeOut),
            child: child,
          ),
        ),
        // ホーム画面は AuthGate が pushReplacement で載せた「名前なし」route。
        // Navigator.pushReplacementNamed('/home') で載っているわけではないので
        // ModalRoute.withName('/home') は誰にもマッチせず、指定するとスタック
        // が完全に空になり pop 先が無くなる。stack 最下部 (= HomeScreen) を
        // 保持するために isFirst で predicate する。
        (route) => route.isFirst,
      );
      return;
    }

    Navigator.pushReplacement(
      context,
      PageRouteBuilder(
        pageBuilder: (_, __, ___) => PostCardEditScreen(
          track: widget.track,
          lyricsData: widget.lyricsData,
          lyricsFuture: widget.lyricsFuture,
          selectedImage: photo,
          isVibe: widget.isVibe,
          vibeTopicId: widget.vibeTopicId,
          vibeTopicTitle: widget.vibeTopicTitle,
          fromVibePlaylist: widget.fromVibePlaylist,
          cachedPreviewUrl: _cachedPreviewUrl,
          cachedGradientStart: _cachedGradientStart,
          cachedGradientEnd: _cachedGradientEnd,
        ),
        transitionDuration: const Duration(milliseconds: 400),
        transitionsBuilder: (_, animation, __, child) => FadeTransition(
          opacity: CurvedAnimation(parent: animation, curve: Curves.easeOut),
          child: child,
        ),
      ),
    );
  }

  // ---- グリッド写真タップ ----

  Future<void> _onThumbnailTap(int assetIndex) async {
    if (_isNavigating) return;
    _isNavigating = true;

    final asset = _galleryAssets[assetIndex];
    final file = await asset.file;
    if (file == null || !mounted) {
      _isNavigating = false;
      return;
    }

    Rect? thumbRect;
    final key = _thumbKeys[assetIndex];
    final renderBox = key?.currentContext?.findRenderObject() as RenderBox?;
    if (renderBox != null && renderBox.attached) {
      final pos = renderBox.localToGlobal(Offset.zero);
      thumbRect = Rect.fromLTWH(
          pos.dx, pos.dy, renderBox.size.width, renderBox.size.height);
    }
    final size = MediaQuery.of(context).size;
    final sourceRect = thumbRect ??
        Rect.fromCenter(
            center: Offset(size.width / 2, size.height / 2),
            width: 60,
            height: 107);
    final naturalSize =
        Size(asset.width.toDouble(), asset.height.toDouble());

    await _cameraController?.pausePreview();
    if (!mounted) return;

    if (widget.isMoodPost) {
      // 気分投稿: グリッド → 拡大アニメーションを省略し、
      // ホーム route まで畳んで透明 route として MoodPostFinalPreviewScreen を載せる。
      Navigator.of(context).pushAndRemoveUntil(
        PageRouteBuilder(
          opaque: false,
          barrierDismissible: false,
          transitionDuration: const Duration(milliseconds: 400),
          pageBuilder: (_, __, ___) => MoodPostFinalPreviewScreen(
            track: widget.track,
            selectedImage: XFile(file.path),
          ),
          transitionsBuilder: (_, animation, __, child) => FadeTransition(
            opacity: CurvedAnimation(parent: animation, curve: Curves.easeOut),
            child: child,
          ),
        ),
        // ホーム画面は AuthGate が pushReplacement で載せた「名前なし」route。
        // Navigator.pushReplacementNamed('/home') で載っているわけではないので
        // ModalRoute.withName('/home') は誰にもマッチせず、指定するとスタック
        // が完全に空になり pop 先が無くなる。stack 最下部 (= HomeScreen) を
        // 保持するために isFirst で predicate する。
        (route) => route.isFirst,
      );
      return;
    }

    await Navigator.push(
      context,
      _PhotoExpandRoute(
        sourceRect: sourceRect,
        child: PostCardEditScreen(
          track: widget.track,
          lyricsData: widget.lyricsData,
          lyricsFuture: widget.lyricsFuture,
          selectedImage: XFile(file.path),
          imageNaturalSize: naturalSize,
          isVibe: widget.isVibe,
          vibeTopicId: widget.vibeTopicId,
          vibeTopicTitle: widget.vibeTopicTitle,
          fromVibePlaylist: widget.fromVibePlaylist,
          cachedPreviewUrl: _cachedPreviewUrl,
          cachedGradientStart: _cachedGradientStart,
          cachedGradientEnd: _cachedGradientEnd,
        ),
      ),
    );

    if (mounted) {
      _isNavigating = false;
      await _cameraController?.resumePreview();
    }
  }

  // ---- Build ----

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          PageView(
            controller: _pageController,
            scrollDirection: Axis.vertical,
            children: [
              _buildCameraPage(),
              _buildPhotoGridPage(),
            ],
          ),
          // シャッターフラッシュ
          IgnorePointer(
            child: AnimatedBuilder(
              animation: _flashController,
              builder: (_, __) {
                final t = _flashController.value;
                final opacity =
                    t < 0.4 ? (t / 0.4) : (1 - (t - 0.4) / 0.6);
                return Opacity(
                  opacity: opacity.clamp(0.0, 0.85),
                  child: const ColoredBox(color: Colors.white),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  // ---- Page 0: カメラビュー ----

  Widget _buildCameraPage() {
    final mq = MediaQuery.of(context);
    final topPad = mq.padding.top;
    final bottomPad = mq.padding.bottom;
    final screenH = mq.size.height;

    return Container(
      color: Colors.black,
      height: screenH,
      child: Stack(
        children: [
          Column(
            children: [
              SizedBox(height: topPad),
              // カメラビューファインダー（9:16）
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: AspectRatio(
                  aspectRatio: 9 / 16,
                  child: Stack(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(20),
                        child: _isCameraInitialized && _cameraController != null
                            ? SizedBox.expand(
                                child: FittedBox(
                                  fit: BoxFit.cover,
                                  child: SizedBox(
                                    width: _cameraController!
                                        .value.previewSize!.height,
                                    height: _cameraController!
                                        .value.previewSize!.width,
                                    child: CameraPreview(_cameraController!),
                                  ),
                                ),
                              )
                            : Container(color: const Color(0xFF0A0A0A)),
                      ),
                      // 上部: フラッシュアイコン + Vibeハッシュタグ
                      Positioned(
                        top: 16,
                        left: 0,
                        right: 0,
                        child: Column(
                          children: [
                            const Icon(Icons.flash_off,
                                color: Colors.white, size: 24),
                            if (widget.vibeTopicTitle != null) ...[
                              const SizedBox(height: 6),
                              Text(
                                '#${widget.vibeTopicTitle}',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w500,
                                  letterSpacing: 0.2,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      // シャッターボタン
                      Positioned(
                        left: 0,
                        right: 0,
                        bottom: 28,
                        child: Center(
                          child: GestureDetector(
                            onTap: _onShutter,
                            child: const _ShutterButton(),
                          ),
                        ),
                      ),
                      // 白枠（最前面）
                      Positioned.fill(
                        child: IgnorePointer(
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              border:
                                  Border.all(color: Colors.white, width: 2),
                              borderRadius: BorderRadius.circular(20),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              // 下部: ギャラリーボタン（左）＋カメラ反転ボタン（右）
              Expanded(
                child: Padding(
                  padding: EdgeInsets.only(
                    left: 28,
                    right: 28,
                    bottom: bottomPad + 16,
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      // ギャラリーボタン（左下・カメラロールへの入口）は非表示。
                      // カメラ反転ボタンを右端に保つためサイズは維持する。
                      // 将来再表示する場合は Visibility を外すだけでよい。
                      Visibility(
                        visible: false,
                        maintainSize: true,
                        maintainAnimation: true,
                        maintainState: true,
                        child: GestureDetector(
                          onTap: _scrollToGallery,
                          child: Container(
                            width: 48,
                            height: 48,
                            decoration: BoxDecoration(
                              color: const Color(0xFF2B2B2B),
                              borderRadius: BorderRadius.circular(8),
                              border:
                                  Border.all(color: Colors.white38, width: 1.5),
                            ),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(6.5),
                              child: _latestThumbData != null
                                  ? Image.memory(
                                      _latestThumbData!,
                                      fit: BoxFit.cover,
                                      width: double.infinity,
                                      height: double.infinity,
                                      gaplessPlayback: true,
                                    )
                                  : const Icon(
                                      Icons.photo_library_outlined,
                                      color: Colors.white,
                                      size: 22,
                                    ),
                            ),
                          ),
                        ),
                      ),
                      // カメラ反転ボタン（右下）
                      GestureDetector(
                        onTap: _flipCamera,
                        child: Container(
                          width: 44,
                          height: 44,
                          decoration: const BoxDecoration(
                            color: Color(0xFF363B3F),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.cameraswitch,
                            color: Colors.white,
                            size: 22,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          // 左上: 戻るボタン
          Positioned(
            left: 16,
            top: topPad + 4,
            child: GestureDetector(
              onTap: () => Navigator.pop(context),
              child: Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.5),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.chevron_left,
                  color: Colors.white,
                  size: 26,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ---- Page 1: 写真グリッド ----

  Widget _buildPhotoGridPage() {
    final mq = MediaQuery.of(context);
    final topPad = mq.padding.top;

    return Container(
      color: Colors.black,
      child: Stack(
        children: [
          Column(
            children: [
              SizedBox(height: topPad),
              const SizedBox(
                height: 50,
                child: Center(
                  child: Text(
                    '写真を選択',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
              Expanded(
                child: _hasPermission ? _buildGrid() : _buildPermissionPrompt(),
              ),
            ],
          ),
          // 左上: 閉じるボタン
          Positioned(
            left: 16,
            top: topPad + 4,
            child: GestureDetector(
              onTap: () => Navigator.pop(context),
              child: Container(
                width: 36,
                height: 36,
                decoration: const BoxDecoration(
                  color: Color(0xFF363B3F),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.chevron_left,
                  color: Colors.white,
                  size: 26,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGrid() {
    return NotificationListener<OverscrollNotification>(
      onNotification: (n) {
        if (n.overscroll < 0) _scrollToCamera();
        return false;
      },
      child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 1),
      child: GridView.builder(
        controller: _gridScrollController,
        physics: const AlwaysScrollableScrollPhysics(),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3,
          mainAxisSpacing: 1,
          crossAxisSpacing: 1,
          childAspectRatio: 9 / 16,
        ),
        itemCount: 1 + _galleryAssets.length,
        itemBuilder: (context, index) {
          if (index == 0) return _buildCameraCell();
          final assetIndex = index - 1;
          _thumbKeys.putIfAbsent(assetIndex, () => GlobalKey());
          return _buildPhotoCell(assetIndex);
        },
      ),
    ),
    );
  }

  Widget _buildCameraCell() {
    return GestureDetector(
      onTap: _scrollToCamera,
      child: Container(
        color: const Color(0xFF2B2B2B),
        child: const Icon(Icons.camera_alt, size: 40, color: Colors.white54),
      ),
    );
  }

  Widget _buildPhotoCell(int assetIndex) {
    return GestureDetector(
      onTap: () => _onThumbnailTap(assetIndex),
      child: SizedBox.expand(
        child: _ThumbnailImage(
          key: _thumbKeys[assetIndex],
          asset: _galleryAssets[assetIndex],
        ),
      ),
    );
  }

  Widget _buildPermissionPrompt() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.photo_library_outlined,
              color: Colors.white38, size: 56),
          const SizedBox(height: 12),
          const Text(
            '写真へのアクセスを許可してください',
            style: TextStyle(color: Colors.white54, fontSize: 14),
          ),
          const SizedBox(height: 20),
          TextButton(
            onPressed: PhotoManager.openSetting,
            child: const Text(
              '設定を開く',
              style: TextStyle(color: Color(0xFF5D8FFF), fontSize: 15),
            ),
          ),
        ],
      ),
    );
  }
}

// ---- シャッターボタン ----

class _ShutterButton extends StatelessWidget {
  const _ShutterButton();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 76,
      height: 76,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 4),
      ),
      padding: const EdgeInsets.all(6),
      child: Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          shape: BoxShape.circle,
        ),
      ),
    );
  }
}

// ---- サムネイル画像 ----

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
  void didUpdateWidget(_ThumbnailImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.asset.id != widget.asset.id) _load();
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
      return Image.memory(_thumbData!,
          fit: BoxFit.cover,
          width: double.infinity,
          height: double.infinity,
          gaplessPlayback: true);
    }
    return Container(color: Colors.grey[800]);
  }
}

// ---- 拡大アニメーション付きルート ----

class _PhotoExpandRoute extends PageRouteBuilder {
  final Rect sourceRect;
  _PhotoExpandRoute({required this.sourceRect, required Widget child})
      : super(
          pageBuilder: (_, __, ___) => child,
          transitionDuration: const Duration(milliseconds: 500),
          reverseTransitionDuration: const Duration(milliseconds: 300),
        );

  @override
  Widget buildTransitions(BuildContext context, Animation<double> animation,
      Animation<double> secondaryAnimation, Widget child) {
    final curved =
        CurvedAnimation(parent: animation, curve: Curves.easeOutQuart);
    final size = MediaQuery.of(context).size;
    final screenCenter = Offset(size.width / 2, size.height / 2);
    final thumbCenter = sourceRect.center;
    final startScale =
        ((sourceRect.width / size.width) + (sourceRect.height / size.height)) /
            2;
    final dx = thumbCenter.dx - screenCenter.dx;
    final dy = thumbCenter.dy - screenCenter.dy;
    return FadeTransition(
      opacity: Tween(begin: 0.4, end: 1.0).animate(curved),
      child: Transform.translate(
        offset: Offset(dx * (1 - curved.value), dy * (1 - curved.value)),
        child: Transform.scale(
          scale: startScale + (1.0 - startScale) * curved.value,
          child: child,
        ),
      ),
    );
  }
}

import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:photo_manager/photo_manager.dart';
import '../models/track_model.dart';
import '../services/audio_player_service.dart';
import '../services/itunes_search_service.dart';
import '../services/lyrics_service.dart';
import '../utils/color_extractor.dart';
import '../widgets/dialogs/glass_popup.dart';
import 'post_card_edit_screen.dart';

/// 投稿フローの起点となる写真選択画面
/// ・プレビューなし
/// ・3列 × 9:16 サムネイルグリッド
/// ・写真タップで拡大アニメーション付き PostCardEditScreen へ遷移
class PostPhotoSelectionScreen extends StatefulWidget {
  final TrackModel track;
  final LyricsData? lyricsData;
  final Future<LyricsData?>? lyricsFuture;
  final bool isVibe;
  final String? vibeTopicId;
  final String? vibeTopicTitle;
  final bool fromVibePlaylist;

  const PostPhotoSelectionScreen({
    super.key,
    required this.track,
    this.lyricsData,
    this.lyricsFuture,
    this.isVibe = false,
    this.vibeTopicId,
    this.vibeTopicTitle,
    this.fromVibePlaylist = false,
  });

  @override
  State<PostPhotoSelectionScreen> createState() =>
      _PostPhotoSelectionScreenState();
}

class _PostPhotoSelectionScreenState extends State<PostPhotoSelectionScreen> {
  final ImagePicker _picker = ImagePicker();

  // photo_manager
  List<AssetEntity> _galleryAssets = [];
  bool _hasPermission = false;
  List<AssetPathEntity> _albums = [];
  List<AssetPathEntity> _allAlbums = [];
  AssetPathEntity? _selectedAlbum;
  int _currentPage = 0;
  bool _isLoadingMore = false;
  bool _hasMorePhotos = true;
  static const int _initialLoad = 100;
  static const int _pageSize = 70;
  final ScrollController _scrollController = ScrollController();

  // 各サムネイルの GlobalKey（拡大アニメーション用）
  final Map<int, GlobalKey> _thumbKeys = {};

  // ナビゲーション中フラグ（二重タップ防止）
  bool _isNavigating = false;

  // アニメーション前に事前取得しておくカード情報
  String? _cachedPreviewUrl;
  Color? _cachedGradientStart;
  Color? _cachedGradientEnd;

  @override
  void initState() {
    super.initState();
    AudioPlayerService().stop();
    _loadGalleryImages();
    _scrollController.addListener(_onScroll);
    _prefetchTrackData();
  }

  /// アニメーション開始前にカード描画に必要なデータを裏で取得
  Future<void> _prefetchTrackData() async {
    final track = widget.track;
    if (track.trackId.isEmpty) return;

    // プレビューURL（トラックに既存なら即使用、なければ iTunes から取得）
    String? url = track.previewUrl;
    if (url == null || url.isEmpty) {
      url = await ITunesSearchService().getPreviewUrl(
        trackName: track.trackName,
        artistName: track.artistName,
      );
    }
    if (mounted) _cachedPreviewUrl = url;

    // アルバムアートからグラデーション色を抽出
    if (track.albumImageUrl.isNotEmpty) {
      try {
        final colors = await ColorExtractor.extractGradientColors(track.albumImageUrl);
        if (mounted) {
          _cachedGradientStart = colors.$1;
          _cachedGradientEnd = colors.$2;
        }
      } catch (_) {}
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 1000) {
      _loadMorePhotos();
    }
  }

  Future<void> _loadGalleryImages() async {
    if (kIsWeb) return;

    final permission = await PhotoManager.requestPermissionExtend();
    if (!permission.isAuth && !permission.hasAccess) {
      setState(() => _hasPermission = false);
      return;
    }
    setState(() => _hasPermission = true);

    final albums = await PhotoManager.getAssetPathList(
      type: RequestType.image,
      filterOption: FilterOptionGroup(
        imageOption: const FilterOption(
          sizeConstraint: SizeConstraint(ignoreSize: true),
        ),
        orders: [const OrderOption(type: OrderOptionType.createDate, asc: false)],
      ),
    );
    if (albums.isEmpty) return;

    _allAlbums = albums;
    final targetNames = {'recents', 'recent photos', 'favorites', 'videos', 'camera roll'};
    _albums = albums.where((a) => targetNames.contains(a.name.toLowerCase())).toList();
    if (_albums.isEmpty) _albums = [albums.first];
    _selectedAlbum = _albums.first;
    await _loadAlbumAssets(_selectedAlbum!);
  }

  Future<void> _loadAlbumAssets(AssetPathEntity album) async {
    final assets = await album.getAssetListRange(start: 0, end: _initialLoad);
    final totalCount = await album.assetCountAsync;
    if (mounted) {
      setState(() {
        _galleryAssets = assets;
        _currentPage = _initialLoad;
        _hasMorePhotos = _initialLoad < totalCount;
        _thumbKeys.clear();
      });
    }
  }

  Future<void> _switchAlbum(AssetPathEntity album) async {
    if (album.id == _selectedAlbum?.id) return;
    setState(() {
      _selectedAlbum = album;
      _galleryAssets = [];
      _thumbKeys.clear();
    });
    if (_scrollController.hasClients) _scrollController.jumpTo(0);
    await _loadAlbumAssets(album);
  }

  Future<void> _loadMorePhotos() async {
    if (_isLoadingMore || !_hasMorePhotos || _selectedAlbum == null) return;
    _isLoadingMore = true;
    final totalCount = await _selectedAlbum!.assetCountAsync;
    final end = (_currentPage + _pageSize).clamp(0, totalCount);
    final assets = await _selectedAlbum!.getAssetListRange(start: _currentPage, end: end);
    if (mounted) {
      setState(() {
        _galleryAssets.addAll(assets);
        _currentPage = end;
        _hasMorePhotos = end < totalCount;
      });
    }
    _isLoadingMore = false;
  }

  /// 写真グリッドのアイテムをタップ → 拡大アニメーション → PostCardEditScreen
  Future<void> _onThumbnailTap(int assetIndex) async {
    if (_isNavigating) return;
    _isNavigating = true;

    final asset = _galleryAssets[assetIndex];
    final file = await asset.file;
    if (file == null || !mounted) {
      _isNavigating = false;
      return;
    }

    // サムネイルの画面上 Rect を取得
    Rect? thumbRect;
    final key = _thumbKeys[assetIndex];
    final renderBox = key?.currentContext?.findRenderObject() as RenderBox?;
    if (renderBox != null && renderBox.attached) {
      final pos = renderBox.localToGlobal(Offset.zero);
      thumbRect = Rect.fromLTWH(pos.dx, pos.dy, renderBox.size.width, renderBox.size.height);
    }

    final size = MediaQuery.of(context).size;
    final sourceRect = thumbRect ??
        Rect.fromCenter(center: Offset(size.width / 2, size.height / 2), width: 60, height: 107);

    final naturalSize = Size(asset.width.toDouble(), asset.height.toDouble());

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

    if (mounted) _isNavigating = false;
  }

  /// カメラで写真を撮影
  Future<void> _takePhoto() async {
    try {
      final XFile? photo = await _picker.pickImage(source: ImageSource.camera);
      if (photo == null || !mounted) return;

      final size = MediaQuery.of(context).size;
      final sourceRect = Rect.fromCenter(
        center: Offset(size.width / 2, size.height / 2),
        width: 60,
        height: 107,
      );

      await Navigator.push(
        context,
        _PhotoExpandRoute(
          sourceRect: sourceRect,
          child: PostCardEditScreen(
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
        ),
      );
    } catch (_) {}
  }

  // ---- Album selector ----

  String _albumDisplayName(String name) {
    switch (name.toLowerCase()) {
      case 'recents':
      case 'recent photos':
      case 'camera roll':
        return '最近';
      case 'favorites':
        return 'お気に入り';
      case 'videos':
        return '動画';
      case 'all photos':
        return 'すべての写真';
      default:
        return name;
    }
  }

  void _showAlbumPicker() {
    if (_albums.isEmpty) return;
    final renderBox = context.findRenderObject() as RenderBox;
    final position = renderBox.localToGlobal(Offset(16, renderBox.size.height * 0.5));

    final items = _albums.map((album) {
      final isSelected = album.id == _selectedAlbum?.id;
      return GlassPopupItem<String>(
        value: 'album_${album.id}',
        label: _albumDisplayName(album.name),
        trailing: isSelected
            ? const Icon(Icons.check, color: Colors.white, size: 20)
            : null,
      );
    }).toList();
    items.add(const GlassPopupItem<String>(
      value: 'all_albums',
      label: 'すべてのアルバム',
      icon: Icons.photo_library_outlined,
    ));

    GlassPopup.show<String>(
      context: context,
      position: position,
      width: renderBox.size.width - 32,
      items: items,
    ).then((selected) {
      if (selected == 'all_albums') {
        _showAllAlbumsBottomSheet();
      } else if (selected != null) {
        final albumId = selected.replaceFirst('album_', '');
        final album = _albums.firstWhere((a) => a.id == albumId);
        _switchAlbum(album);
      }
    });
  }

  void _showAllAlbumsBottomSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => _AllAlbumsBottomSheet(
        albums: _allAlbums,
        selectedAlbumId: _selectedAlbum?.id,
        onAlbumSelected: (album) {
          Navigator.pop(context);
          _switchAlbum(album);
        },
      ),
    );
  }

  // ---- Build ----

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            _buildHeader(),
            Expanded(child: _buildPhotoGrid()),
          ],
        ),
      ),
    );
  }

  /// 固定ヘッダー（戻る / タイトル）
  Widget _buildHeader() {
    return Hero(
      tag: 'post_flow_header',
      flightShuttleBuilder: (_, __, ___, ____, _____) => _postFlowHeaderShuttle,
      child: Material(
        color: Colors.transparent,
        child: SizedBox(
          height: 50,
          width: double.infinity,
          child: Stack(
            alignment: Alignment.center,
            children: [
              // タイトル（画面中央に絶対固定）
              const Text(
                '新規投稿',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
              // 戻るボタン（画面左端から19px）
              Positioned(
                left: 19,
                top: 0,
                bottom: 0,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => Navigator.pop(context),
                  child: const Icon(Icons.arrow_back_ios, color: Colors.white, size: 22),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Hero遷移中に表示するシャトルウィジェット（タイトルのみ）
  static const Widget _postFlowHeaderShuttle = Material(
    color: Colors.transparent,
    child: SizedBox(
      height: 50,
      child: Center(
        child: Text(
          '新規投稿',
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            color: Colors.white,
          ),
        ),
      ),
    ),
  );

  /// 3列 × 9:16 写真グリッド
  Widget _buildPhotoGrid() {
    if (!_hasPermission || kIsWeb) {
      return _buildFallbackGrid();
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 1),
      child: GridView.builder(
        controller: _scrollController,
        physics: const AlwaysScrollableScrollPhysics(),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3,
          mainAxisSpacing: 1,
          crossAxisSpacing: 1,
          childAspectRatio: 9 / 16,
        ),
        itemCount: 1 + _galleryAssets.length, // カメラ + 写真
        itemBuilder: (context, index) {
          if (index == 0) return _buildCameraButton();
          _thumbKeys.putIfAbsent(index - 1, () => GlobalKey());
          return _buildPhotoGridItem(index - 1);
        },
      ),
    );
  }

  Widget _buildFallbackGrid() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 1),
      child: GridView.builder(
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3,
          mainAxisSpacing: 1,
          crossAxisSpacing: 1,
          childAspectRatio: 9 / 16,
        ),
        itemCount: 2,
        itemBuilder: (context, index) {
          if (index == 0) return _buildCameraButton();
          return GestureDetector(
            onTap: () async {
              final XFile? image =
                  await _picker.pickImage(source: ImageSource.gallery);
              if (image != null && mounted) {
                final size = MediaQuery.of(context).size;
                Navigator.push(
                  context,
                  _PhotoExpandRoute(
                    sourceRect: Rect.fromCenter(
                      center: Offset(size.width / 2, size.height / 2),
                      width: 60,
                      height: 107,
                    ),
                    child: PostCardEditScreen(
                      track: widget.track,
                      lyricsData: widget.lyricsData,
                      lyricsFuture: widget.lyricsFuture,
                      selectedImage: image,
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
              }
            },
            child: Container(
              color: const Color(0xFF2B2B2B),
              child: const Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.photo_library, size: 36, color: Colors.white54),
                  SizedBox(height: 4),
                  Text('写真を選択',
                      style: TextStyle(fontSize: 10, color: Colors.white54)),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildCameraButton() {
    return GestureDetector(
      onTap: _takePhoto,
      child: Container(
        color: const Color(0xFF2B2B2B),
        child: const Icon(Icons.camera_alt, size: 40, color: Colors.white54),
      ),
    );
  }

  Widget _buildPhotoGridItem(int assetIndex) {
    final asset = _galleryAssets[assetIndex];
    return GestureDetector(
      onTap: () => _onThumbnailTap(assetIndex),
      child: SizedBox.expand(
        child: _ThumbnailImage(
          key: _thumbKeys[assetIndex],
          asset: asset,
        ),
      ),
    );
  }
}

// ============================================================
//  拡大アニメーション付きカスタムルート
// ============================================================

class _PhotoExpandRoute extends PageRouteBuilder {
  final Rect sourceRect;

  _PhotoExpandRoute({required this.sourceRect, required Widget child})
      : super(
          pageBuilder: (_, __, ___) => child,
          transitionDuration: const Duration(milliseconds: 500),
          reverseTransitionDuration: const Duration(milliseconds: 300),
        );

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    final curved = CurvedAnimation(parent: animation, curve: Curves.easeOutQuart);
    final size = MediaQuery.of(context).size;
    final screenCenter = Offset(size.width / 2, size.height / 2);
    final thumbCenter = sourceRect.center;

    // サムネイルの相対スケール（短辺基準）
    final startScale =
        ((sourceRect.width / size.width) + (sourceRect.height / size.height)) / 2;

    // サムネイル中心 → 画面中心へ移動
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

// ============================================================
//  サムネイル画像ウィジェット（非同期読み込み）
// ============================================================

class _ThumbnailImage extends StatefulWidget {
  final AssetEntity asset;

  const _ThumbnailImage({super.key, required this.asset});

  @override
  State<_ThumbnailImage> createState() => _ThumbnailImageState();
}

class _ThumbnailImageState extends State<_ThumbnailImage> {
  Uint8List? _thumbData;
  String? _loadedAssetId;

  @override
  void initState() {
    super.initState();
    _loadThumbnail();
  }

  @override
  void didUpdateWidget(_ThumbnailImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.asset.id != widget.asset.id) _loadThumbnail();
  }

  Future<void> _loadThumbnail() async {
    final assetId = widget.asset.id;
    _loadedAssetId = assetId;
    final data = await widget.asset.thumbnailDataWithSize(
      const ThumbnailSize(300, 533), // 9:16 相当
    );
    if (mounted && data != null && _loadedAssetId == assetId) {
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

// ============================================================
//  すべてのアルバム ボトムシート
// ============================================================

class _AllAlbumsBottomSheet extends StatefulWidget {
  final List<AssetPathEntity> albums;
  final String? selectedAlbumId;
  final void Function(AssetPathEntity album) onAlbumSelected;

  const _AllAlbumsBottomSheet({
    required this.albums,
    required this.selectedAlbumId,
    required this.onAlbumSelected,
  });

  @override
  State<_AllAlbumsBottomSheet> createState() => _AllAlbumsBottomSheetState();
}

class _AllAlbumsBottomSheetState extends State<_AllAlbumsBottomSheet> {
  final Map<String, Uint8List?> _albumThumbnails = {};
  final Map<String, int> _albumCounts = {};

  @override
  void initState() {
    super.initState();
    _loadAlbumInfo();
  }

  Future<void> _loadAlbumInfo() async {
    for (final album in widget.albums) {
      final count = await album.assetCountAsync;
      if (!mounted) return;
      Uint8List? thumb;
      if (count > 0) {
        final assets = await album.getAssetListRange(start: 0, end: 1);
        if (assets.isNotEmpty) {
          thumb = await assets.first
              .thumbnailDataWithSize(const ThumbnailSize(200, 200));
        }
      }
      if (mounted) {
        setState(() {
          _albumCounts[album.id] = count;
          _albumThumbnails[album.id] = thumb;
        });
      }
    }
  }

  String _albumNameJa(String name) {
    switch (name.toLowerCase()) {
      case 'recents':
      case 'recent photos':
      case 'camera roll':
        return '最近の項目';
      case 'favorites':
        return 'お気に入り';
      case 'videos':
        return 'ビデオ';
      case 'selfies':
        return 'セルフィー';
      case 'screenshots':
        return 'スクリーンショット';
      case 'live photos':
        return 'Live Photos';
      case 'panoramas':
        return 'パノラマ';
      case 'bursts':
        return 'バースト';
      case 'hidden':
        return '非表示';
      case 'recently deleted':
        return '最近削除した項目';
      case 'all photos':
        return 'すべての写真';
      default:
        return name;
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.of(context).size.height;
    return Container(
      height: screenHeight * 0.75,
      decoration: const BoxDecoration(
        color: Color(0xFF1C1C1E),
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      child: Column(
        children: [
          Container(
            margin: const EdgeInsets.only(top: 8),
            width: 36,
            height: 5,
            decoration: BoxDecoration(
              color: Colors.grey[600],
              borderRadius: BorderRadius.circular(3),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                GestureDetector(
                  onTap: () => Navigator.pop(context),
                  child: const Text(
                    'キャンセル',
                    style: TextStyle(color: Color(0xFF5D8FFF), fontSize: 15),
                  ),
                ),
                const Expanded(
                  child: Text(
                    'アルバムを選択',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w600),
                  ),
                ),
                const SizedBox(width: 72),
              ],
            ),
          ),
          Container(height: 0.5, color: Colors.grey[800]),
          Expanded(
            child: GridView.builder(
              padding: const EdgeInsets.all(16),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                mainAxisSpacing: 20,
                crossAxisSpacing: 12,
                childAspectRatio: 0.85,
              ),
              itemCount: widget.albums.length,
              itemBuilder: (context, index) {
                final album = widget.albums[index];
                final thumb = _albumThumbnails[album.id];
                final count = _albumCounts[album.id];
                final isSelected = album.id == widget.selectedAlbumId;
                return GestureDetector(
                  onTap: () => widget.onAlbumSelected(album),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Container(
                          decoration: BoxDecoration(
                            color: Colors.grey[800],
                            borderRadius: BorderRadius.circular(8),
                            border: isSelected
                                ? Border.all(
                                    color: const Color(0xFF5D8FFF), width: 2)
                                : null,
                          ),
                          child: ClipRRect(
                            borderRadius:
                                BorderRadius.circular(isSelected ? 6 : 8),
                            child: thumb != null
                                ? Image.memory(thumb,
                                    fit: BoxFit.cover,
                                    width: double.infinity,
                                    height: double.infinity,
                                    gaplessPlayback: true)
                                : const Center(
                                    child: Icon(
                                      Icons.photo_library_outlined,
                                      color: Colors.white38,
                                      size: 40,
                                    ),
                                  ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        _albumNameJa(album.name),
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.w500),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (count != null)
                        Text(
                          '$count',
                          style:
                              TextStyle(color: Colors.grey[500], fontSize: 12),
                        ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

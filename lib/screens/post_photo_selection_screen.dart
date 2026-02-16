import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:photo_manager/photo_manager.dart';
import '../models/track_model.dart';
import '../services/audio_player_service.dart';
import '../services/lyrics_service.dart';
import 'lyrics_card_selection_screen.dart';

/// 投稿用写真選択画面
class PostPhotoSelectionScreen extends StatefulWidget {
  final TrackModel track;
  final LyricsData? lyricsData;
  final Future<LyricsData?>? lyricsFuture; // バックグラウンド取得用
  final bool isVibe;
  final String? vibeTopicId;
  final String? vibeTopicTitle;

  const PostPhotoSelectionScreen({
    super.key,
    required this.track,
    this.lyricsData,
    this.lyricsFuture,
    this.isVibe = false,
    this.vibeTopicId,
    this.vibeTopicTitle,
  });

  @override
  State<PostPhotoSelectionScreen> createState() =>
      _PostPhotoSelectionScreenState();
}

class _PostPhotoSelectionScreenState extends State<PostPhotoSelectionScreen> {
  final ImagePicker _picker = ImagePicker();
  XFile? _selectedImage;
  LyricsData? _lyricsData;

  // photo_manager 用
  List<AssetEntity> _galleryAssets = [];
  int? _selectedAssetIndex;
  bool _hasPermission = false;
  AssetPathEntity? _recentAlbum;
  int _currentPage = 0;
  bool _isLoadingMore = false;
  bool _hasMorePhotos = true;
  static const int _initialLoad = 100;
  static const int _pageSize = 70;
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    AudioPlayerService().stop();
    _loadGalleryImages();
    _scrollController.addListener(_onScroll);

    _lyricsData = widget.lyricsData;

    if (widget.lyricsFuture != null) {
      widget.lyricsFuture!.then((lyricsData) {
        if (mounted) {
          setState(() {
            _lyricsData = lyricsData;
          });
        }
      });
    } else if (_lyricsData == null) {
      _fetchLyricsInBackground();
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  /// スクロール末尾検知
  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 1000) {
      _loadMorePhotos();
    }
  }

  /// 歌詞をバックグラウンドで取得
  Future<void> _fetchLyricsInBackground() async {
    try {
      final lyricsService = LyricsService();
      final appleDevToken = dotenv.env['APPLE_MUSIC_DEVELOPER_TOKEN'] ?? '';

      final lyricsData = await lyricsService.getLyrics(
        trackName: widget.track.trackName,
        artistName: widget.track.artistName,
        durationSeconds: null,
        appleDevToken: appleDevToken,
      );

      if (mounted) {
        setState(() {
          _lyricsData = lyricsData;
        });
      }
    } catch (e) {
      print('⚠️ 写真選択画面: 歌詞取得エラー - $e');
    }
  }

  /// ギャラリーから画像リストを読み込む（初回）
  Future<void> _loadGalleryImages() async {
    if (kIsWeb) return;

    final permission = await PhotoManager.requestPermissionExtend();
    if (!permission.isAuth) {
      if (!permission.hasAccess) {
        setState(() => _hasPermission = false);
        return;
      }
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

    _recentAlbum = albums.first;
    final assets = await _recentAlbum!.getAssetListRange(
      start: 0,
      end: _initialLoad,
    );

    final totalCount = await _recentAlbum!.assetCountAsync;

    if (mounted) {
      setState(() {
        _galleryAssets = assets;
        _currentPage = _initialLoad;
        _hasMorePhotos = _initialLoad < totalCount;
      });
    }
  }

  /// 追加の写真を読み込む（スクロール時）
  Future<void> _loadMorePhotos() async {
    if (_isLoadingMore || !_hasMorePhotos || _recentAlbum == null) return;

    _isLoadingMore = true;

    final totalCount = await _recentAlbum!.assetCountAsync;
    final end = (_currentPage + _pageSize).clamp(0, totalCount);
    final assets = await _recentAlbum!.getAssetListRange(
      start: _currentPage,
      end: end,
    );

    if (mounted) {
      setState(() {
        _galleryAssets.addAll(assets);
        _currentPage = end;
        _hasMorePhotos = end < totalCount;
      });
    }

    _isLoadingMore = false;
  }

  /// グリッドの写真をタップして選択
  Future<void> _selectAsset(int assetIndex) async {
    final asset = _galleryAssets[assetIndex];
    final file = await asset.file;
    if (file == null) return;

    if (mounted) {
      setState(() {
        _selectedImage = XFile(file.path);
        _selectedAssetIndex = assetIndex;
      });
    }
  }

  /// カメラで写真を撮影
  Future<void> _takePhoto() async {
    try {
      final XFile? photo = await _picker.pickImage(
        source: ImageSource.camera,
      );
      if (photo != null) {
        setState(() {
          _selectedImage = photo;
          _selectedAssetIndex = null;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('カメラの起動に失敗しました: $e'),
            backgroundColor: const Color(0xFFE53935),
          ),
        );
      }
    }
  }

  /// ギャラリーから写真を選択（システムピッカー - フォールバック用）
  Future<void> _pickFromGallery() async {
    try {
      final XFile? image = await _picker.pickImage(
        source: ImageSource.gallery,
      );
      if (image != null) {
        setState(() {
          _selectedImage = image;
          _selectedAssetIndex = null;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('画像の選択に失敗しました: $e'),
            backgroundColor: const Color(0xFFE53935),
          ),
        );
      }
    }
  }

  /// 次へボタン押下
  Future<void> _onNext() async {
    if (_selectedImage == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('写真を選択してください'),
          backgroundColor: Color(0xFFE53935),
        ),
      );
      return;
    }

    final result = await Navigator.push<Map<String, dynamic>>(
      context,
      MaterialPageRoute(
        builder: (context) => LyricsCardSelectionScreen(
          track: widget.track,
          lyricsData: _lyricsData,
          selectedImage: _selectedImage,
          isVibe: widget.isVibe,
          vibeTopicId: widget.vibeTopicId,
          vibeTopicTitle: widget.vibeTopicTitle,
        ),
      ),
    );

    if (result != null && mounted) {
      Navigator.pop(context, result);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(),
            Expanded(
              child: SingleChildScrollView(
                controller: _scrollController,
                child: Column(
                  children: [
                    const SizedBox(height: 16),
                    _buildPreviewImage(),
                    const SizedBox(height: 7),
                    _buildPhotoGrid(),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// ヘッダー
  Widget _buildHeader() {
    return Container(
      height: 62,
      padding: const EdgeInsets.symmetric(horizontal: 19),
      child: Row(
        children: [
          Expanded(
            child: Align(
              alignment: Alignment.centerLeft,
              child: GestureDetector(
                onTap: () => Navigator.pop(context),
                child: const Icon(
                  Icons.arrow_back_ios,
                  color: Colors.white,
                  size: 27,
                ),
              ),
            ),
          ),
          const Text(
            '新規投稿',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: Colors.white,
            ),
          ),
          Expanded(
            child: Align(
              alignment: Alignment.centerRight,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: _onNext,
                child: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  child: Text(
                    '次へ',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF5D8FFF),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// プレビュー画像
  Widget _buildPreviewImage() {
    return Container(
      width: 363,
      height: 484,
      margin: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        border: Border.all(
          color: Colors.white,
          width: 0.5,
        ),
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(18),
          topRight: Radius.circular(18),
        ),
      ),
      child: ClipRRect(
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(18),
          topRight: Radius.circular(18),
        ),
        child: _selectedImage != null
            ? kIsWeb
                ? Image.network(
                    _selectedImage!.path,
                    fit: BoxFit.cover,
                  )
                : Image.file(
                    File(_selectedImage!.path),
                    fit: BoxFit.cover,
                  )
            : Container(
                color: const Color(0xFF2B2B2B),
                child: const Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.add_photo_alternate,
                        size: 80,
                        color: Colors.white38,
                      ),
                      SizedBox(height: 16),
                      Text(
                        '写真を選択してください',
                        style: TextStyle(
                          fontSize: 16,
                          color: Colors.white54,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
      ),
    );
  }

  /// 写真グリッド
  Widget _buildPhotoGrid() {
    // 権限なし or Web → システムピッカーへのフォールバック
    if (!_hasPermission || kIsWeb) {
      return _buildFallbackGrid();
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 1),
      child: GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3,
          mainAxisSpacing: 1,
          crossAxisSpacing: 1,
        ),
        itemCount: 1 + _galleryAssets.length, // カメラボタン + 写真
        itemBuilder: (context, index) {
          if (index == 0) {
            return _buildCameraButton();
          }
          return _buildPhotoGridItem(index - 1);
        },
      ),
    );
  }

  /// 権限がない場合のフォールバックグリッド
  Widget _buildFallbackGrid() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 1),
      child: GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3,
          mainAxisSpacing: 1,
          crossAxisSpacing: 1,
        ),
        itemCount: 2,
        itemBuilder: (context, index) {
          if (index == 0) {
            return _buildCameraButton();
          }
          // ギャラリーピッカーボタン
          return GestureDetector(
            onTap: _pickFromGallery,
            child: Container(
              color: const Color(0xFF2B2B2B),
              child: const Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.photo_library, size: 36, color: Colors.white54),
                  SizedBox(height: 4),
                  Text(
                    '写真を選択',
                    style: TextStyle(fontSize: 10, color: Colors.white54),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  /// カメラボタン
  Widget _buildCameraButton() {
    return GestureDetector(
      onTap: _takePhoto,
      child: Container(
        color: const Color(0xFF2B2B2B),
        child: const Icon(
          Icons.camera_alt,
          size: 48,
          color: Colors.white54,
        ),
      ),
    );
  }

  /// 写真グリッドアイテム
  Widget _buildPhotoGridItem(int assetIndex) {
    final asset = _galleryAssets[assetIndex];
    final bool isSelected = _selectedAssetIndex == assetIndex;

    return GestureDetector(
      onTap: () => _selectAsset(assetIndex),
      child: Stack(
        fit: StackFit.expand,
        children: [
          _ThumbnailImage(asset: asset),

          // 選択状態のオーバーレイ
          if (isSelected)
            Container(
              decoration: BoxDecoration(
                border: Border.all(color: Colors.white, width: 1),
              ),
              child: Stack(
                children: [
                  Container(
                    color: Colors.white.withValues(alpha: 0.5),
                  ),
                  Center(
                    child: Container(
                      width: 32,
                      height: 32,
                      decoration: const BoxDecoration(
                        color: Color(0xFF5D8FFF),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.check,
                        color: Colors.white,
                        size: 20,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// サムネイル画像を非同期で読み込む独立ウィジェット
/// 各セルが独立して読み込むのでUIをブロックしない
class _ThumbnailImage extends StatefulWidget {
  final AssetEntity asset;

  const _ThumbnailImage({required this.asset});

  @override
  State<_ThumbnailImage> createState() => _ThumbnailImageState();
}

class _ThumbnailImageState extends State<_ThumbnailImage> {
  Uint8List? _thumbData;

  @override
  void initState() {
    super.initState();
    _loadThumbnail();
  }

  Future<void> _loadThumbnail() async {
    final data = await widget.asset.thumbnailDataWithSize(
      const ThumbnailSize(200, 200),
    );
    if (mounted && data != null) {
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

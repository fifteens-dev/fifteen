import 'dart:io';
import 'dart:math';
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:photo_manager/photo_manager.dart';
import '../models/track_model.dart';
import '../services/audio_player_service.dart';
import '../services/lyrics_service.dart';
import '../widgets/dialogs/glass_popup.dart';
import 'lyrics_card_selection_screen.dart';
import 'music_trim_screen.dart';

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

class _PostPhotoSelectionScreenState extends State<PostPhotoSelectionScreen>
    with SingleTickerProviderStateMixin {
  final ImagePicker _picker = ImagePicker();
  XFile? _selectedImage;
  LyricsData? _lyricsData;

  // photo_manager 用
  List<AssetEntity> _galleryAssets = [];
  int? _selectedAssetIndex;
  bool _hasPermission = false;
  List<AssetPathEntity> _albums = [];
  List<AssetPathEntity> _allAlbums = []; // フィルタなしの全アルバム
  AssetPathEntity? _selectedAlbum;
  int _currentPage = 0;
  bool _isLoadingMore = false;
  bool _hasMorePhotos = true;
  static const int _initialLoad = 100;
  static const int _pageSize = 70;
  final ScrollController _scrollController = ScrollController();

  // 画像編集（移動・拡大）— ValueNotifier でジェスチャー中のリビルドを最小化
  Offset _imageOffset = Offset.zero;
  double _imageScale = 1.0;
  double _startImageScale = 1.0;
  bool _showGridLines = false;
  final ValueNotifier<int> _transformNotifier = ValueNotifier<int>(0);
  static const double _previewW = 363.0;
  static const double _previewH = 484.0;
  Size? _imageNaturalSize; // 選択画像の元サイズ
  File? _previewImageFile; // キャッシュ済みプレビュー画像

  // プレビュー表示/非表示アニメーション
  bool _showPreview = false;
  static const double _albumBarHeight = 44.0;
  static const double _previewHeight = 484.0 + 16.0 + 7.0 + _albumBarHeight;
  late final AnimationController _previewAnimController;
  late final Animation<double> _previewShowAnim; // 表示用（ゆるバウンス）
  late final Animation<double> _previewHideAnim; // 非表示用（easeIn）

  @override
  void initState() {
    super.initState();

    _previewAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
      value: 1.0, // 初期状態は表示
    );
    // 表示時: ゆっくり降りてきて、最後に軽くバウンド
    // 0→0.65: 0.0→1.0 (easeOut で降りる)
    // 0.65→0.82: 1.0→0.97 (少し戻る)
    // 0.82→1.0: 0.97→1.0 (定位置に収まる)
    _previewShowAnim = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween(begin: 0.0, end: 1.0)
            .chain(CurveTween(curve: Curves.easeOut)),
        weight: 65,
      ),
      TweenSequenceItem(
        tween: Tween(begin: 1.0, end: 0.97)
            .chain(CurveTween(curve: Curves.easeInOut)),
        weight: 17,
      ),
      TweenSequenceItem(
        tween: Tween(begin: 0.97, end: 1.0)
            .chain(CurveTween(curve: Curves.easeInOut)),
        weight: 18,
      ),
    ]).animate(_previewAnimController);
    // 非表示時: easeInカーブ
    _previewHideAnim = CurvedAnimation(
      parent: _previewAnimController,
      curve: Curves.easeIn,
    );

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
    _previewAnimController.dispose();
    _scrollController.dispose();
    _transformNotifier.dispose();
    super.dispose();
  }

  /// プレビューを表示（バウンスアニメーション）
  void _showPreviewAnimated() {
    if (_showPreview) return;
    _showPreview = true;
    _previewAnimController.forward(from: 0.0);
  }

  /// プレビューを非表示（easeInアニメーション）
  void _hidePreviewAnimated() {
    if (!_showPreview) return;
    _showPreview = false;
    _overscrollUpCount = 0;
    _isOverscrolling = false;
    _previewAnimController.reverse(from: 1.0);
    // スクロール位置が黒い空白内にある場合はグリッド最上部へスナップ
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && !_showPreview && _scrollController.hasClients &&
          _scrollController.position.pixels < _previewHeight) {
        _scrollController.animateTo(
          _previewHeight,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  /// スクロール検知（追加読み込み用）
  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 1000) {
      _loadMorePhotos();
    }
  }

  // 下方向スクロールがあったかのフラグ
  bool _scrolledDown = false;
  // 上方向overscrollの回数カウント
  int _overscrollUpCount = 0;
  bool _isOverscrolling = false;

  /// グリッドのスクロール通知検知
  bool _handleScrollNotification(ScrollNotification notification) {
    if (notification is ScrollUpdateNotification) {
      final delta = notification.scrollDelta ?? 0;
      final pixels = notification.metrics.pixels;

      // 下方向スクロールを検知したらフラグを立てる
      if (delta > 0 && _showPreview && pixels > 0) {
        _scrolledDown = true;
      }

      // 黒い空白を除いたグリッド最上部で上方向スクロールを検知
      if (delta < 0 && !_showPreview && pixels <= _previewHeight) {
        if (!_isOverscrolling) {
          _isOverscrolling = true;
          _overscrollUpCount++;
        }
        if (_overscrollUpCount >= 2) {
          _showPreviewAnimated();
          _overscrollUpCount = 0;
        }
      }
    }

    // 指が離れたらoverscroll中フラグをリセット
    if (notification is ScrollEndNotification) {
      _isOverscrolling = false;
      // プレビュー非表示時、黒い空白が見えていたらグリッド最上部へスナップ
      if (!_showPreview && notification.metrics.pixels < _previewHeight) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && !_showPreview && _scrollController.hasClients) {
            _scrollController.animateTo(
              _previewHeight,
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOut,
            );
          }
        });
      }
    }

    // Android: ClampingScrollPhysicsではOverscrollNotificationが発生
    if (notification is OverscrollNotification &&
        notification.overscroll < 0 &&
        !_showPreview) {
      if (!_isOverscrolling) {
        _isOverscrolling = true;
        _overscrollUpCount++;
      }
      if (_overscrollUpCount >= 2) {
        _showPreviewAnimated();
        _overscrollUpCount = 0;
      }
    }
    return false;
  }

  /// 指が離れたタイミングでプレビューを隠す
  void _handlePointerUp(PointerUpEvent event) {
    if (_scrolledDown && _showPreview) {
      _scrolledDown = false;
      _hidePreviewAnimated();
    }
  }

  /// プレビュー画像のジェスチャー: 開始
  void _onImageScaleStart(ScaleStartDetails details) {
    _startImageScale = _imageScale;
    _showGridLines = true;
    _transformNotifier.value++;
  }

  /// プレビュー画像のジェスチャー: 更新（setState不使用 → プレビューのみ再描画）
  void _onImageScaleUpdate(ScaleUpdateDetails details) {
    // 1本指: 移動
    var newOffset = Offset(
      _imageOffset.dx + details.focalPointDelta.dx,
      _imageOffset.dy + details.focalPointDelta.dy,
    );

    // 2本指: 焦点を中心に拡大
    if (details.pointerCount >= 2) {
      final newScale = (_startImageScale * details.scale).clamp(1.0, 5.0);
      if (newScale != _imageScale) {
        final focal = details.localFocalPoint;
        final ratio = newScale / _imageScale;
        newOffset = Offset(
          focal.dx - (focal.dx - newOffset.dx) * ratio,
          focal.dy - (focal.dy - newOffset.dy) * ratio,
        );
        _imageScale = newScale;
      }
    }

    _imageOffset = newOffset;
    _transformNotifier.value++;
  }

  /// プレビュー画像のジェスチャー: 終了
  void _onImageScaleEnd(ScaleEndDetails details) {
    _showGridLines = false;
    _correctImagePosition();
  }

  /// 画像ファイルから元のサイズを取得
  Future<Size> _getImageSize(String path) async {
    final data = await File(path).readAsBytes();
    final codec = await ui.instantiateImageCodec(data);
    final frame = await codec.getNextFrame();
    final size = Size(
      frame.image.width.toDouble(),
      frame.image.height.toDouble(),
    );
    frame.image.dispose();
    return size;
  }

  /// 画像の表示用baseScaleを計算（枠を埋める最小スケール）
  double _calcBaseScale(Size naturalSize) {
    return max(_previewW / naturalSize.width, _previewH / naturalSize.height);
  }

  /// 画像の位置を補正（黒い部分が出ないようにする）
  void _correctImagePosition() {
    if (_imageNaturalSize == null) return;
    final baseScale = _calcBaseScale(_imageNaturalSize!);
    final dw = _imageNaturalSize!.width * baseScale * _imageScale;
    final dh = _imageNaturalSize!.height * baseScale * _imageScale;

    // 左上基準: offset は 0（左寄せ）〜 -(overflow) の範囲
    final minX = -(dw - _previewW).clamp(0.0, double.infinity);
    final minY = -(dh - _previewH).clamp(0.0, double.infinity);

    final clampedX = _imageOffset.dx.clamp(minX, 0.0);
    final clampedY = _imageOffset.dy.clamp(minY, 0.0);

    if (clampedX != _imageOffset.dx || clampedY != _imageOffset.dy) {
      _imageOffset = Offset(clampedX, clampedY);
    }
    _transformNotifier.value++;
  }

  /// 画像編集状態をリセット
  void _resetImageTransform() {
    _imageOffset = Offset.zero;
    _imageScale = 1.0;
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

    // 全アルバムを保持（すべてのアルバムボトムシート用）
    _allAlbums = albums;

    // メインピッカーは「最近」「動画」「お気に入り」に絞る
    final targetNames = {'recents', 'recent photos', 'favorites', 'videos', 'camera roll'};
    _albums = albums.where((a) => targetNames.contains(a.name.toLowerCase())).toList();
    if (_albums.isEmpty) _albums = [albums.first]; // フォールバック
    _selectedAlbum = _albums.first;
    await _loadAlbumAssets(_selectedAlbum!);

    // 最新写真（インデックス0）を自動選択
    if (mounted && _galleryAssets.isNotEmpty) {
      await _selectAsset(0);
    }
  }

  /// アルバムの写真を読み込む
  Future<void> _loadAlbumAssets(AssetPathEntity album) async {
    final assets = await album.getAssetListRange(
      start: 0,
      end: _initialLoad,
    );
    final totalCount = await album.assetCountAsync;

    if (mounted) {
      setState(() {
        _galleryAssets = assets;
        _currentPage = _initialLoad;
        _hasMorePhotos = _initialLoad < totalCount;
      });
    }
  }

  /// アルバムを切り替え
  Future<void> _switchAlbum(AssetPathEntity album) async {
    if (album.id == _selectedAlbum?.id) return;
    setState(() {
      _selectedAlbum = album;
      _galleryAssets = [];
      _selectedAssetIndex = null;
    });
    if (_scrollController.hasClients) {
      _scrollController.jumpTo(0);
    }
    await _loadAlbumAssets(album);
  }

  /// 追加の写真を読み込む（スクロール時）
  Future<void> _loadMorePhotos() async {
    if (_isLoadingMore || !_hasMorePhotos || _selectedAlbum == null) return;

    _isLoadingMore = true;

    final totalCount = await _selectedAlbum!.assetCountAsync;
    final end = (_currentPage + _pageSize).clamp(0, totalCount);
    final assets = await _selectedAlbum!.getAssetListRange(
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

    // 画像の元サイズを取得
    Size naturalSize = Size(asset.width.toDouble(), asset.height.toDouble());
    if (naturalSize.width <= 0 || naturalSize.height <= 0) {
      naturalSize = await _getImageSize(file.path);
    }

    if (mounted) {
      _resetImageTransform();
      setState(() {
        _selectedImage = XFile(file.path);
        _previewImageFile = file;
        _selectedAssetIndex = assetIndex;
        _imageNaturalSize = naturalSize;
      });
      _showPreviewAnimated();
      _scrollToRevealSelected(assetIndex);
    }
  }

  /// 選択した写真がプレビューに隠れる場合、グリッドをスクロールして見えるようにする
  void _scrollToRevealSelected(int assetIndex) {
    if (!_scrollController.hasClients) return;

    // グリッド内のインデックス（カメラボタン分+1）
    final gridIndex = assetIndex + 1;
    final row = gridIndex ~/ 3;

    // グリッドの利用可能幅からアイテムサイズを計算
    // Container padding: horizontal 1 each side = 2
    final gridWidth = MediaQuery.of(context).size.width - 2;
    final itemSize = (gridWidth - 3) / 4; // crossAxisSpacing: 1 × 3箇所
    // GridViewのtopPadding(_previewHeight)を加算した実際のスクロール座標
    final itemTop = _previewHeight + row * (itemSize + 1); // mainAxisSpacing: 1

    final currentOffset = _scrollController.offset;

    // アイテムの上端がプレビューに隠れるか判定
    final visibleTop = currentOffset + _previewHeight;
    if (itemTop < visibleTop) {
      // アイテムがプレビューの直下に来るようスクロール
      final targetOffset = (itemTop - _previewHeight).clamp(
        0.0,
        _scrollController.position.maxScrollExtent,
      );
      _scrollController.animateTo(
        targetOffset,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
  }

  /// カメラで写真を撮影
  Future<void> _takePhoto() async {
    try {
      final XFile? photo = await _picker.pickImage(
        source: ImageSource.camera,
      );
      if (photo != null) {
        final naturalSize = await _getImageSize(photo.path);
        _resetImageTransform();
        setState(() {
          _selectedImage = photo;
          _previewImageFile = File(photo.path);
          _selectedAssetIndex = null;
          _imageNaturalSize = naturalSize;
        });
        _showPreviewAnimated();
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
        final naturalSize = await _getImageSize(image.path);
        _resetImageTransform();
        setState(() {
          _selectedImage = image;
          _previewImageFile = File(image.path);
          _selectedAssetIndex = null;
          _imageNaturalSize = naturalSize;
        });
        _showPreviewAnimated();
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

    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => MusicTrimScreen(
          track: widget.track,
          lyricsData: _lyricsData,
          selectedImage: _selectedImage,
          imageOffset: _imageOffset,
          imageScale: _imageScale,
          imageNaturalSize: _imageNaturalSize,
          isVibe: widget.isVibe,
          vibeTopicId: widget.vibeTopicId,
          vibeTopicTitle: widget.vibeTopicTitle,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            _buildHeader(),
            // グリッドとプレビューをStackで重ねる（グリッド位置固定）
            Expanded(
              child: Stack(
                children: [
                  // 写真グリッド（常に全面を占有）
                  Positioned.fill(
                    child: RepaintBoundary(
                      child: Listener(
                        onPointerUp: _handlePointerUp,
                        child: NotificationListener<ScrollNotification>(
                          onNotification: _handleScrollNotification,
                          child: _buildPhotoGrid(),
                        ),
                      ),
                    ),
                  ),
                  // プレビュー（上から覆い被さる）
                  AnimatedBuilder(
                    animation: _previewAnimController,
                    builder: (context, child) {
                      final t = _showPreview
                          ? _previewShowAnim.value
                          : _previewHideAnim.value;
                      return Positioned(
                        left: 0,
                        right: 0,
                        top: -_previewHeight * (1 - t),
                        child: child!,
                      );
                    },
                    child: Container(
                      color: const Color(0xFF121212),
                      child: Column(
                        children: [
                          const SizedBox(height: 16),
                          _buildPreviewImage(),
                          const SizedBox(height: 7),
                          _buildAlbumSelector(),
                        ],
                      ),
                    ),
                  ),
                ],
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
              fontSize: 15,
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
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: Text(
                    '次へ',
                    style: TextStyle(
                      fontSize: 15,
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
      width: _previewW,
      height: _previewH,
      margin: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        border: Border.all(
          color: Colors.white,
          width: 0.5,
        ),
        borderRadius: BorderRadius.circular(18),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: _selectedImage != null && _imageNaturalSize != null
            ? GestureDetector(
                onScaleStart: _onImageScaleStart,
                onScaleUpdate: _onImageScaleUpdate,
                onScaleEnd: _onImageScaleEnd,
                behavior: HitTestBehavior.opaque,
                // ValueListenableBuilder: ジェスチャー中はこのサブツリーだけ再描画
                child: ValueListenableBuilder<int>(
                  valueListenable: _transformNotifier,
                  builder: (context, _, __) {
                    final baseScale = _calcBaseScale(_imageNaturalSize!);
                    final displayW = _imageNaturalSize!.width * baseScale;
                    final displayH = _imageNaturalSize!.height * baseScale;
                    return Stack(
                      clipBehavior: Clip.hardEdge,
                      children: [
                        Positioned.fill(
                          child: Container(color: Colors.black),
                        ),
                        Positioned(
                          left: _imageOffset.dx,
                          top: _imageOffset.dy,
                          child: Transform.scale(
                            scale: _imageScale,
                            alignment: Alignment.topLeft,
                            child: SizedBox(
                              width: displayW,
                              height: displayH,
                              child: kIsWeb
                                  ? Image.network(
                                      _selectedImage!.path,
                                      fit: BoxFit.fill,
                                    )
                                  : Image.file(
                                      _previewImageFile!,
                                      fit: BoxFit.fill,
                                      gaplessPlayback: true,
                                    ),
                            ),
                          ),
                        ),
                        if (_showGridLines)
                          Positioned.fill(
                            child: IgnorePointer(
                              child: CustomPaint(
                                painter: _GridLinesPainter(),
                              ),
                            ),
                          ),
                      ],
                    );
                  },
                ),
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

  /// アルバム選択バー
  Widget _buildAlbumSelector() {
    final albumName = _selectedAlbum != null ? _albumDisplayName(_selectedAlbum!.name) : '最近';
    return SizedBox(
      height: _albumBarHeight,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(
          children: [
            GestureDetector(
              onTap: _showAlbumPicker,
              behavior: HitTestBehavior.opaque,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    albumName,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(width: 4),
                  const Icon(
                    Icons.chevron_right,
                    color: Colors.white,
                    size: 20,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// アルバム名を日本語に変換
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
        return 'すべてのアルバム';
      default:
        return name;
    }
  }

  /// アルバム選択ポップアップ
  void _showAlbumPicker() {
    if (_albums.isEmpty) return;

    final renderBox = context.findRenderObject() as RenderBox;
    final position = renderBox.localToGlobal(
      Offset(16, renderBox.size.height * 0.5),
    );

    // 通常アルバム + 「すべてのアルバム」
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

  /// すべてのアルバムボトムシート
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

  /// 写真グリッド
  Widget _buildPhotoGrid() {
    // 権限なし or Web → システムピッカーへのフォールバック
    if (!_hasPermission || kIsWeb) {
      return _buildFallbackGrid();
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 1),
      child: GridView.builder(
        controller: _scrollController,
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.only(top: _previewHeight),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 4,
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
        controller: _scrollController,
        physics: const AlwaysScrollableScrollPhysics(),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 4,
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

/// 3×3 グリッド補助線
class _GridLinesPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0x80FFFFFF)
      ..strokeWidth = 0.5;

    // 縦線2本
    for (int i = 1; i < 3; i++) {
      final x = size.width * i / 3;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    // 横線2本
    for (int i = 1; i < 3; i++) {
      final y = size.height * i / 3;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
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
  String? _loadedAssetId;

  @override
  void initState() {
    super.initState();
    _loadThumbnail();
  }

  @override
  void didUpdateWidget(_ThumbnailImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    // GridViewのリサイクルでアセットが変わった場合に再読み込み
    if (oldWidget.asset.id != widget.asset.id) {
      _loadThumbnail();
    }
  }

  Future<void> _loadThumbnail() async {
    final assetId = widget.asset.id;
    _loadedAssetId = assetId;
    final data = await widget.asset.thumbnailDataWithSize(
      const ThumbnailSize(200, 200),
    );
    // リクエスト中にアセットが変わっていたら無視
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

/// すべてのアルバム表示用ボトムシート
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
  // アルバムごとのサムネイルとカウント
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
          thumb = await assets.first.thumbnailDataWithSize(
            const ThumbnailSize(200, 200),
          );
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
          // ドラッグハンドル
          Container(
            margin: const EdgeInsets.only(top: 8),
            width: 36,
            height: 5,
            decoration: BoxDecoration(
              color: Colors.grey[600],
              borderRadius: BorderRadius.circular(3),
            ),
          ),
          // ヘッダー
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                GestureDetector(
                  onTap: () => Navigator.pop(context),
                  child: const Text(
                    'キャンセル',
                    style: TextStyle(
                      color: Color(0xFF5D8FFF),
                      fontSize: 16,
                    ),
                  ),
                ),
                const Expanded(
                  child: Text(
                    'アルバムを選択',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(width: 72), // キャンセルとバランス
              ],
            ),
          ),
          Container(height: 0.5, color: Colors.grey[800]),
          // アルバムグリッド
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
                      // サムネイル
                      Expanded(
                        child: Container(
                          decoration: BoxDecoration(
                            color: Colors.grey[800],
                            borderRadius: BorderRadius.circular(8),
                            border: isSelected
                                ? Border.all(color: const Color(0xFF5D8FFF), width: 2)
                                : null,
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(isSelected ? 6 : 8),
                            child: thumb != null
                                ? Image.memory(
                                    thumb,
                                    fit: BoxFit.cover,
                                    width: double.infinity,
                                    height: double.infinity,
                                    gaplessPlayback: true,
                                  )
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
                      // アルバム名
                      Text(
                        _albumNameJa(album.name),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      // 写真数
                      if (count != null)
                        Text(
                          '$count',
                          style: TextStyle(
                            color: Colors.grey[500],
                            fontSize: 12,
                          ),
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
}

import 'dart:async';
import 'dart:math';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:image_picker/image_picker.dart';
import 'package:photo_manager/photo_manager.dart';
import '../models/track_model.dart';
import '../models/post_theme.dart';
import '../services/audio_player_service.dart';
import '../services/itunes_search_service.dart';
import '../services/lyrics_service.dart';
import '../services/post_service.dart';
import '../services/storage_service.dart';
import '../utils/color_extractor.dart';
import '../utils/current_user_helper.dart';
import '../utils/photo_helper.dart';
import '../widgets/dialogs/dialogs.dart';
import '../widgets/shared/user_info_badge.dart';

enum _Phase { flipping, front, photoModal, editingOverlay, preview, posting }

/// 投稿作成シート（音楽選択後に下からスライドインする全画面シート）
/// フリップ → 写真選択 → 編集 → プレビュー → 投稿 の一連のフローを管理
class PostCreationSheet extends StatefulWidget {
  final TrackModel track;
  final LyricsData? lyricsData;
  final Future<LyricsData?>? lyricsFuture;
  final bool isVibe;
  final String? vibeTopicId;
  final String? vibeTopicTitle;
  final Color? preExtractedGradientStart;
  final Color? preExtractedGradientEnd;

  const PostCreationSheet({
    super.key,
    required this.track,
    this.lyricsData,
    this.lyricsFuture,
    this.isVibe = false,
    this.vibeTopicId,
    this.vibeTopicTitle,
    this.preExtractedGradientStart,
    this.preExtractedGradientEnd,
  });

  @override
  State<PostCreationSheet> createState() => _PostCreationSheetState();
}

class _PostCreationSheetState extends State<PostCreationSheet>
    with TickerProviderStateMixin {
  // ---- Phase ----
  _Phase _phase = _Phase.flipping;

  // ---- Card flip ----
  late AnimationController _flipController; // 0=front, 1=back
  late Animation<double> _flipAnimation;

  // ---- Photo fit animation ----
  late AnimationController _photoFitController;
  late Animation<double> _photoFitAnimation;

  // ---- Audio ----
  final AudioPlayerService _audioService = AudioPlayerService();
  final ITunesSearchService _itunesService = ITunesSearchService();
  String? _previewUrl;
  bool _isPlaying = false;
  bool _isDragging = false;
  double _playbackProgress = 0.0;
  double _pausedProgress = 0.0;
  StreamSubscription<Duration>? _positionSub;
  StreamSubscription? _playerStateSub;
  final int _durationSeconds = 15;
  double _startPosition = 0.0;
  final Duration _totalDuration = const Duration(seconds: 30);
  late List<double> _waveformData;

  // ---- Selected photo ----
  AssetEntity? _selectedAsset;
  Uint8List? _cachedThumbBytes;
  AssetEntity? _cachedThumbAsset;
  Size? _imageNaturalSize;
  Offset _imageOffset = Offset.zero;
  double _imageScale = 1.0;
  double _startImageScale = 1.0;
  final ValueNotifier<int> _imageTransformNotifier = ValueNotifier(0);

  // ---- Gallery ----
  List<AssetEntity> _galleryAssets = [];
  bool _hasPermission = false;
  bool _galleryLoaded = false;
  late AnimationController _modalController;

  // ---- Jacket (layout card) ----
  int _selectedLayoutIndex = 1;
  Offset _cardCenter = Offset.zero;
  bool _cardCenterInitialized = false;
  double _cardScale = 1.0;
  double _cardRotation = 0.0;
  bool _isTwoFingerGesture = false;
  double _startCardScale = 1.0;
  double _startCardRotation = 0.0;
  static const List<double> _snapDegrees = [45, 135, 225, 315];
  static const double _snapThreshold = 3.0;
  Set<double> _activeSnapAngles = {};
  Set<double> _prevSnapAngles = {};
  bool _isTwoFingerAccepted = false;
  final ValueNotifier<int> _gestureNotifier = ValueNotifier<int>(0);
  double _effectiveCardW = 363.0;
  double _effectiveCardH = 484.0;
  static const double _controlsH = 158.0;

  // ---- User info / lyrics / colors ----
  String _currentUsername = '';
  String? _currentUserIconUrl;
  LyricsData? _lyricsData;
  Color? _gradientStart;
  Color? _gradientEnd;

  // ---- Posting ----
  final PostService _postService = PostService();
  final StorageService _storageService = StorageService();
  final FirebaseAuth _auth = FirebaseAuth.instance;
  bool _isPosting = false;

  @override
  void initState() {
    super.initState();

    _lyricsData = widget.lyricsData;
    if (widget.lyricsFuture != null) {
      widget.lyricsFuture!.then((data) {
        if (mounted) setState(() => _lyricsData = data);
      });
    } else if (_lyricsData == null) {
      _fetchLyricsInBackground();
    }

    // Flip: start at back (value=1.0), auto-flip to front after 300ms
    _flipController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 450),
      value: 1.0,
    );
    _flipAnimation = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _flipController, curve: Curves.easeInOut),
    );
    _flipController.addStatusListener((status) {
      if (status == AnimationStatus.dismissed && _phase == _Phase.flipping) {
        setState(() => _phase = _Phase.front);
      }
    });
    Future.delayed(const Duration(milliseconds: 300), () {
      if (mounted) _flipController.reverse(); // 1→0 (back→front)
    });

    // Photo fit animation
    _photoFitController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 350),
    );
    _photoFitAnimation = CurvedAnimation(
      parent: _photoFitController,
      curve: Curves.easeOutCubic,
    );

    // Modal animation
    _modalController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 350),
    );

    // Colors
    if (widget.preExtractedGradientStart != null &&
        widget.preExtractedGradientEnd != null) {
      _gradientStart = widget.preExtractedGradientStart;
      _gradientEnd = widget.preExtractedGradientEnd;
    } else {
      _extractColors();
    }

    // Waveform data
    final rng = Random(widget.track.trackName.hashCode);
    _waveformData =
        List.generate(60, (_) => 0.15 + rng.nextDouble() * 0.85);
    int peakIndex = 0;
    double peak = 0;
    for (int i = 0; i < _waveformData.length; i++) {
      if (_waveformData[i] > peak) {
        peak = _waveformData[i];
        peakIndex = i;
      }
    }
    final maxStart = 1.0 - _durationSeconds / _totalDuration.inSeconds;
    _startPosition = (peakIndex / _waveformData.length).clamp(0.0, maxStart);

    _loadUserInfo();
    _loadPreviewUrl();

    _positionSub = _audioService.positionStream.listen((pos) {
      if (!mounted || !_isPlaying || _isDragging) return;
      final remainMs =
          _durationSeconds * 1000 - (_pausedProgress * _durationSeconds * 1000);
      if (remainMs <= 0) return;
      final prog = _pausedProgress +
          (pos.inMilliseconds / remainMs) * (1.0 - _pausedProgress);
      setState(() => _playbackProgress = prog.clamp(0.0, 1.0));
    });
    _playerStateSub = _audioService.playerStateStream.listen((s) {
      if (!mounted || _isDragging) return;
      if (s.playing != _isPlaying) setState(() => _isPlaying = s.playing);
    });
  }

  @override
  void dispose() {
    _flipController.dispose();
    _photoFitController.dispose();
    _modalController.dispose();
    _positionSub?.cancel();
    _playerStateSub?.cancel();
    _audioService.stop();
    _gestureNotifier.dispose();
    _imageTransformNotifier.dispose();
    super.dispose();
  }

  // ---- Data loading ----

  Future<void> _loadUserInfo() async {
    final info = await CurrentUserHelper.load();
    if (mounted) {
      setState(() {
        _currentUsername = info.username;
        _currentUserIconUrl = info.iconUrl;
      });
    }
  }

  Future<void> _fetchLyricsInBackground() async {
    try {
      final ls = LyricsService();
      final token = dotenv.env['APPLE_MUSIC_DEVELOPER_TOKEN'] ?? '';
      final data = await ls.getLyrics(
        trackName: widget.track.trackName,
        artistName: widget.track.artistName,
        durationSeconds: null,
        appleDevToken: token,
      );
      if (mounted) setState(() => _lyricsData = data);
    } catch (_) {}
  }

  Future<void> _extractColors() async {
    try {
      final url = widget.track.albumImageUrl;
      if (url.isNotEmpty) {
        final colors = await ColorExtractor.extractGradientColors(url);
        if (mounted) {
          setState(() {
            _gradientStart = colors.$1;
            _gradientEnd = colors.$2;
          });
        }
      }
    } catch (_) {}
  }

  Future<void> _loadPreviewUrl() async {
    String? url = widget.track.previewUrl;
    if (url == null || url.isEmpty) {
      url = await _itunesService.getPreviewUrl(
        trackName: widget.track.trackName,
        artistName: widget.track.artistName,
      );
    }
    if (mounted) setState(() => _previewUrl = url);
  }

  // ---- Audio ----

  void _playFromCurrentPosition() async {
    if (_previewUrl == null) return;
    final resumeMs =
        (_pausedProgress * _durationSeconds * 1000).round();
    final startMs =
        (_startPosition * _totalDuration.inMilliseconds).round() + resumeMs;
    final remSec =
        _durationSeconds - (resumeMs / 1000).round();
    setState(() => _isPlaying = true);
    await _audioService.playPreview(
      _previewUrl!,
      startFrom: Duration(milliseconds: startMs),
      durationSeconds: remSec > 0 ? remSec : _durationSeconds,
    );
  }

  void _stopPlayback() async {
    setState(() {
      _isPlaying = false;
      _pausedProgress = _playbackProgress;
    });
    await _audioService.stop();
  }

  // ---- Gallery / Photo modal ----

  Future<void> _openPhotoModal() async {
    if (!_galleryLoaded) await _loadGallery();
    if (!mounted) return;
    setState(() => _phase = _Phase.photoModal);
    _modalController.forward(from: 0.0);
  }

  Future<void> _closePhotoModal() async {
    await _modalController.reverse();
    if (mounted) {
      setState(() => _phase = _selectedAsset != null ? _Phase.preview : _Phase.front);
    }
  }

  Future<void> _loadGallery() async {
    final result = await PhotoManager.requestPermissionExtend();
    if (!mounted) return;
    if (!result.isAuth) {
      setState(() {
        _hasPermission = false;
        _galleryLoaded = true;
      });
      return;
    }
    setState(() => _hasPermission = true);
    try {
      final albums = await PhotoManager.getAssetPathList(
        type: RequestType.image,
        filterOption: FilterOptionGroup(
          imageOption: const FilterOption(
            sizeConstraint: SizeConstraint(ignoreSize: true),
          ),
          orders: [
            const OrderOption(type: OrderOptionType.createDate, asc: false)
          ],
        ),
      );
      if (!mounted) return;
      if (albums.isEmpty) {
        setState(() => _galleryLoaded = true);
        return;
      }
      final recent =
          albums.firstWhere((a) => a.isAll, orElse: () => albums.first);
      final assets = await recent.getAssetListRange(start: 0, end: 100);
      if (mounted) {
        setState(() {
          _galleryAssets = assets;
          _galleryLoaded = true;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _galleryLoaded = true);
    }
  }

  Future<void> _selectAsset(AssetEntity asset) async {
    // Close modal first
    await _modalController.reverse();
    if (!mounted) return;

    final natW = asset.width.toDouble();
    final natH = asset.height.toDouble();

    // Calculate offset to center image within card (cover fill)
    double initOffX = 0, initOffY = 0;
    if (natW > 0 && natH > 0) {
      final baseScale = max(_effectiveCardW / natW, _effectiveCardH / natH);
      final dispW = natW * baseScale;
      final dispH = natH * baseScale;
      initOffX = (_effectiveCardW - dispW) / 2;
      initOffY = (_effectiveCardH - dispH) / 2;
    }

    // Clear cached thumb so it reloads for new asset
    _cachedThumbBytes = null;
    _cachedThumbAsset = null;

    setState(() {
      _selectedAsset = asset;
      _imageNaturalSize = Size(natW, natH);
      _imageOffset = Offset(initOffX, initOffY);
      _imageScale = 1.0;
      _phase = _Phase.editingOverlay;
    });

    // Animate photo fitting into card
    _photoFitController.forward(from: 0.0);

    // Start audio
    _pausedProgress = 0.0;
    _playbackProgress = 0.0;
    _playFromCurrentPosition();
  }

  void _onDoneEditing() {
    _stopPlayback();
    setState(() => _phase = _Phase.preview);
  }

  // ---- Thumbnail loading (cached) ----

  Future<Uint8List?> _getThumbBytes() async {
    if (_selectedAsset == null) return null;
    if (_cachedThumbAsset == _selectedAsset && _cachedThumbBytes != null) {
      return _cachedThumbBytes;
    }
    final bytes = await _selectedAsset!.thumbnailDataWithSize(
      ThumbnailSize(
        (_effectiveCardW * 2).round(),
        (_effectiveCardH * 2).round(),
      ),
      quality: 90,
    );
    _cachedThumbBytes = bytes;
    _cachedThumbAsset = _selectedAsset;
    return bytes;
  }

  // ---- Image gesture (adjusting photo inside card in editingOverlay) ----

  void _onImageScaleStart(ScaleStartDetails d) {
    _startImageScale = _imageScale;
    _imageTransformNotifier.value++;
  }

  void _onImageScaleUpdate(ScaleUpdateDetails d) {
    var newOffset = Offset(
      _imageOffset.dx + d.focalPointDelta.dx,
      _imageOffset.dy + d.focalPointDelta.dy,
    );
    if (d.pointerCount >= 2) {
      final newScale = (_startImageScale * d.scale).clamp(1.0, 5.0);
      if (newScale != _imageScale) {
        final focal = d.localFocalPoint;
        final ratio = newScale / _imageScale;
        newOffset = Offset(
          focal.dx - (focal.dx - newOffset.dx) * ratio,
          focal.dy - (focal.dy - newOffset.dy) * ratio,
        );
        _imageScale = newScale;
      }
    }
    // Clamp offset to prevent showing too much background
    if (_imageNaturalSize != null) {
      final natW = _imageNaturalSize!.width;
      final natH = _imageNaturalSize!.height;
      if (natW > 0 && natH > 0) {
        final baseScale = max(_effectiveCardW / natW, _effectiveCardH / natH);
        final dispW = natW * baseScale * _imageScale;
        final dispH = natH * baseScale * _imageScale;
        final minX = _effectiveCardW - dispW;
        final minY = _effectiveCardH - dispH;
        newOffset = Offset(
          newOffset.dx.clamp(minX, 0.0),
          newOffset.dy.clamp(minY, 0.0),
        );
      }
    }
    _imageOffset = newOffset;
    _imageTransformNotifier.value++;
  }

  void _onImageScaleEnd(ScaleEndDetails d) {
    _imageTransformNotifier.value++;
  }

  // ---- Jacket gesture (preview phase) ----

  Size _getCardSize() {
    switch (_selectedLayoutIndex) {
      case 0:
        return const Size(196, 126);
      case 1:
        return const Size(105, 147);
      case 2:
        return const Size(172, 42);
      case 3:
        return const Size(140, 152);
      case 4:
        return const Size(130, 61);
      default:
        return const Size(196, 126);
    }
  }

  bool _isInTwoFingerHitArea(Offset pt) {
    final center = Offset(_effectiveCardW / 2, _effectiveCardH * 0.45);
    final radius = min(_effectiveCardW, _effectiveCardH) * 0.6 / 2;
    return (pt - center).distance <= radius;
  }

  void _onJacketScaleStart(ScaleStartDetails d) {
    _startCardScale = _cardScale;
    _startCardRotation = _cardRotation;
    _isTwoFingerAccepted = false;
    if (d.pointerCount >= 2 && _isInTwoFingerHitArea(d.localFocalPoint)) {
      _isTwoFingerAccepted = true;
      _isTwoFingerGesture = true;
      _gestureNotifier.value++;
    }
  }

  void _onJacketScaleUpdate(ScaleUpdateDetails d) {
    if (d.pointerCount >= 2) {
      if (!_isTwoFingerAccepted &&
          _isInTwoFingerHitArea(d.localFocalPoint)) {
        _isTwoFingerAccepted = true;
        _startCardScale = _cardScale;
        _startCardRotation = _cardRotation;
      }
      if (_isTwoFingerAccepted) {
        _isTwoFingerGesture = true;
        _cardScale =
            (_startCardScale * (1.0 + (d.scale - 1.0) * 0.6)).clamp(0.3, 3.0);
        _cardRotation = _startCardRotation + d.rotation * 0.6;

        double deg = (_cardRotation * 180 / pi) % 360;
        if (deg < 0) deg += 360;
        final newSnaps = <double>{};
        for (final sd in _snapDegrees) {
          double diff = (deg - sd).abs();
          if (diff > 180) diff = 360 - diff;
          if (diff <= _snapThreshold) newSnaps.add(sd);
        }
        if (newSnaps.isNotEmpty &&
            !newSnaps.every((a) => _prevSnapAngles.contains(a))) {
          HapticFeedback.lightImpact();
        }
        _prevSnapAngles = newSnaps;
        _activeSnapAngles = newSnaps;
      }
    }
    _cardCenter = Offset(
      _cardCenter.dx + d.focalPointDelta.dx * 0.7,
      _cardCenter.dy + d.focalPointDelta.dy * 0.7,
    );
    _gestureNotifier.value++;
  }

  void _onJacketScaleEnd(ScaleEndDetails d) {
    _isTwoFingerGesture = false;
    _isTwoFingerAccepted = false;
    _activeSnapAngles = {};
    _prevSnapAngles = {};
    final center = Offset(_effectiveCardW / 2, _effectiveCardH * 0.45);
    if ((_cardCenter - center).distance <= 40.0) {
      _cardCenter = center;
      HapticFeedback.lightImpact();
    }
    _gestureNotifier.value++;
  }

  // ---- Posting ----

  Future<void> _onPost() async {
    if (_isPosting) return;
    final confirmed = await ActionDialog.showPostConfirm(context);
    if (!confirmed) return;

    setState(() {
      _isPosting = true;
      _phase = _Phase.posting;
    });
    _audioService.stop();

    try {
      final currentUser = _auth.currentUser;
      final userId = currentUser?.uid ?? 'test_user';
      final username = _currentUsername.isNotEmpty
          ? _currentUsername
          : currentUser?.displayName ?? 'ユーザー';

      String? photoUrl;
      if (_selectedAsset != null) {
        final file = await _selectedAsset!.file;
        if (file != null) {
          final xfile = XFile(file.path);
          try {
            photoUrl = await PhotoHelper.processPhoto(
              image: xfile,
              userId: userId,
              storageService: _storageService,
            );
          } catch (e) {
            debugPrint('⚠️ Photo upload error: $e');
          }
        }
      }

      PostTheme? theme;
      try {
        theme = await ColorExtractor.extractThemeFromAlbumArt(
            widget.track.albumImageUrl);
      } catch (_) {}

      String? lyricsText;
      if (_lyricsData != null) {
        final ls = LyricsService();
        lyricsText =
            ls.truncateLyrics(_lyricsData!.plainLyrics, maxLines: 4);
      }

      final audioStartMs =
          (_startPosition * _totalDuration.inMilliseconds).round();
      final cardSize = _getCardSize();
      final cardPosition = Offset(
        _cardCenter.dx - cardSize.width * _cardScale / 2,
        _cardCenter.dy - cardSize.height * _cardScale / 2,
      );

      await _postService.createPost(
        userId: userId,
        username: username,
        userIconUrl: _currentUserIconUrl,
        trackData: widget.track.toMap(),
        photoUrl: photoUrl,
        imageOffsetX: _imageOffset.dx,
        imageOffsetY: _imageOffset.dy,
        imageScale: _imageScale,
        imageNaturalWidth: _imageNaturalSize?.width ?? 0,
        imageNaturalHeight: _imageNaturalSize?.height ?? 0,
        selectedLayoutIndex: _selectedLayoutIndex,
        cardPositionX: cardPosition.dx,
        cardPositionY: cardPosition.dy,
        cardScale: _cardScale,
        cardRotation: _cardRotation,
        isVibe: widget.isVibe,
        vibeTopicId: widget.vibeTopicId,
        vibeTopicTitle: widget.vibeTopicTitle,
        theme: theme,
        lyricsText: lyricsText,
        audioStartMs: audioStartMs,
        audioDurationSec: _durationSeconds,
      );

      if (mounted) {
        Navigator.of(context)
            .pushNamedAndRemoveUntil('/home', (route) => false);
      }
    } catch (e) {
      debugPrint('投稿エラー: $e');
      if (mounted) {
        setState(() {
          _isPosting = false;
          _phase = _Phase.preview;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('投稿の作成に失敗しました'),
            backgroundColor: Color(0xFFE53935),
          ),
        );
      }
    }
  }

  // ---- Build ----

  @override
  Widget build(BuildContext context) {
    final screenW = MediaQuery.of(context).size.width;
    final cardW = screenW - 32.0;
    final cardH = cardW * (484.0 / 363.0);

    if (!_cardCenterInitialized) {
      _cardCenter = Offset(cardW / 2, cardH * 0.45);
      _cardCenterInitialized = true;
    }
    _effectiveCardW = cardW;
    _effectiveCardH = cardH;

    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      body: SafeArea(
        bottom: false,
        child: Stack(
          children: [
            Column(
              children: [
                _buildHeader(),
                Expanded(
                  child: SingleChildScrollView(
                    physics: (_phase == _Phase.flipping ||
                            _phase == _Phase.photoModal)
                        ? const NeverScrollableScrollPhysics()
                        : null,
                    child: Column(
                      children: [
                        const SizedBox(height: 12),
                        Padding(
                          padding:
                              const EdgeInsets.symmetric(horizontal: 16),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(18),
                            child: SizedBox(
                              width: cardW,
                              height: cardH,
                              child: _buildCardArea(cardW, cardH),
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        _buildTrackInfoSection(),
                        SizedBox(
                            height:
                                MediaQuery.of(context).padding.bottom + 24),
                      ],
                    ),
                  ),
                ),
              ],
            ),

            // Photo modal overlay
            if (_phase == _Phase.photoModal) _buildPhotoModalLayer(),

            // Posting indicator overlay
            if (_phase == _Phase.posting)
              const Positioned.fill(
                child: ColoredBox(
                  color: Color(0x66000000),
                  child: Center(
                    child: CircularProgressIndicator(color: Colors.white),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    final bool canGoBack = _phase != _Phase.posting;
    final bool showPost = _phase == _Phase.preview;
    final bool showDone = _phase == _Phase.editingOverlay;

    return SizedBox(
      height: 50,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Stack(
          alignment: Alignment.center,
          children: [
            const Text(
              '新規投稿',
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.w600),
            ),
            Positioned.fill(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  GestureDetector(
                    onTap: canGoBack
                        ? () {
                            _audioService.stop();
                            Navigator.pop(context);
                          }
                        : null,
                    child: Icon(
                      Icons.arrow_back_ios,
                      color: canGoBack ? Colors.white : Colors.transparent,
                      size: 22,
                    ),
                  ),
                  if (showPost)
                    GestureDetector(
                      onTap: _isPosting ? null : _onPost,
                      child: const Text(
                        '投稿',
                        style: TextStyle(
                            color: Color(0xFF5D8FFF),
                            fontSize: 15,
                            fontWeight: FontWeight.w600),
                      ),
                    )
                  else if (showDone)
                    GestureDetector(
                      onTap: _onDoneEditing,
                      child: const Text(
                        '完了',
                        style: TextStyle(
                            color: Color(0xFF5D8FFF),
                            fontSize: 15,
                            fontWeight: FontWeight.w600),
                      ),
                    )
                  else
                    const SizedBox(width: 40),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ---- Card area (flip animation) ----

  Widget _buildCardArea(double cardW, double cardH) {
    return AnimatedBuilder(
      animation: _flipAnimation,
      builder: (context, child) {
        final angle = _flipAnimation.value * pi;
        final isFront = angle < pi / 2;
        return Transform(
          alignment: Alignment.center,
          transform: Matrix4.identity()
            ..setEntry(3, 2, 0.001)
            ..rotateY(angle),
          child: isFront
              ? Transform(
                  alignment: Alignment.center,
                  transform: Matrix4.rotationY(pi),
                  child: _buildFrontCard(cardW, cardH),
                )
              : _buildBackCard(cardW, cardH),
        );
      },
    );
  }

  Widget _buildBackCard(double cardW, double cardH) {
    final c1 = _gradientStart ?? const Color(0xFF1a1a2e);
    final c2 = _gradientEnd ?? const Color(0xFF16213e);
    return Container(
      width: cardW,
      height: cardH,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [c1, c2],
        ),
      ),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (widget.track.albumImageUrl.isNotEmpty)
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: CachedNetworkImage(
                  imageUrl: widget.track.albumImageUrl,
                  width: 130,
                  height: 130,
                  fit: BoxFit.cover,
                ),
              ),
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Text(
                widget.track.trackName,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w700),
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              widget.track.artistName,
              style:
                  const TextStyle(color: Colors.white70, fontSize: 14),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFrontCard(double cardW, double cardH) {
    return Stack(
      clipBehavior: Clip.hardEdge,
      children: [
        // Photo background
        Positioned.fill(
          child: _buildPhotoBackground(cardW, cardH),
        ),

        // Dark overlay in editingOverlay phase
        if (_phase == _Phase.editingOverlay)
          Positioned.fill(
            child: Container(
                color: Colors.black.withValues(alpha: 0.35)),
          ),

        // Image adjustment gesture (editingOverlay phase)
        if (_phase == _Phase.editingOverlay && _selectedAsset != null)
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            bottom: _controlsH,
            child: GestureDetector(
              onScaleStart: _onImageScaleStart,
              onScaleUpdate: _onImageScaleUpdate,
              onScaleEnd: _onImageScaleEnd,
              behavior: HitTestBehavior.translucent,
            ),
          ),

        // "写真を追加" button (front phase, no photo)
        if (_phase == _Phase.front && _selectedAsset == null)
          Center(
            child: GestureDetector(
              onTap: _openPhotoModal,
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 24, vertical: 14),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(28),
                  border: Border.all(color: Colors.white38),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.add_photo_alternate_outlined,
                        color: Colors.white, size: 20),
                    SizedBox(width: 8),
                    Text('写真を追加',
                        style: TextStyle(
                            color: Colors.white, fontSize: 15)),
                  ],
                ),
              ),
            ),
          ),

        // "写真を変更" button in preview phase
        if (_phase == _Phase.preview)
          Positioned(
            top: 15,
            right: 15,
            child: GestureDetector(
              onTap: _openPhotoModal,
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Text('変更',
                    style: TextStyle(color: Colors.white, fontSize: 12)),
              ),
            ),
          ),

        // Jacket gesture layer (preview phase only)
        if (_phase == _Phase.preview)
          Positioned.fill(
            child: GestureDetector(
              onScaleStart: _onJacketScaleStart,
              onScaleUpdate: _onJacketScaleUpdate,
              onScaleEnd: _onJacketScaleEnd,
              behavior: HitTestBehavior.translucent,
            ),
          ),

        // Jacket overlay
        if (_phase != _Phase.front ||
            _selectedAsset != null)
          _buildJacketOverlay(),

        // User info badge
        Positioned(
          top: 15,
          left: 15,
          child: UserInfoBadge(
            username: _currentUsername.isNotEmpty
                ? _currentUsername
                : 'ユーザー',
            iconUrl: _currentUserIconUrl,
            hashtagText:
                widget.isVibe && widget.vibeTopicTitle != null
                    ? '#${widget.vibeTopicTitle}'
                    : null,
            showBackground: false,
          ),
        ),

        // Bottom gradient + controls (editingOverlay only)
        if (_phase == _Phase.editingOverlay) ...[
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            height: _controlsH + 40,
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.transparent,
                    Colors.black.withValues(alpha: 0.8),
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: _buildControlsOverlay(),
          ),
        ],
      ],
    );
  }

  Widget _buildPhotoBackground(double cardW, double cardH) {
    if (_selectedAsset == null) {
      return Container(color: const Color(0xFF2B2B2B));
    }

    return FutureBuilder<Uint8List?>(
      future: _getThumbBytes(),
      builder: (ctx, snapshot) {
        if (!snapshot.hasData || snapshot.data == null) {
          return Container(color: const Color(0xFF1C1C1C));
        }

        final natW = _imageNaturalSize?.width ?? cardW;
        final natH = _imageNaturalSize?.height ?? cardH;
        final baseScale = max(cardW / natW, cardH / natH);
        final dispW = natW * baseScale;
        final dispH = natH * baseScale;

        return ValueListenableBuilder<int>(
          valueListenable: _imageTransformNotifier,
          builder: (ctx, _, __) {
            return AnimatedBuilder(
              animation: _photoFitAnimation,
              builder: (ctx, child) {
                final t = _photoFitAnimation.value;
                return Stack(
                  children: [
                    Container(color: Colors.black),
                    Positioned(
                      left: _imageOffset.dx,
                      top: _imageOffset.dy,
                      child: Transform.scale(
                        scale: _imageScale * (0.8 + 0.2 * t),
                        alignment: Alignment.center,
                        child: Opacity(
                          opacity: t.clamp(0.0, 1.0),
                          child: SizedBox(
                            width: dispW,
                            height: dispH,
                            child: Image.memory(
                              snapshot.data!,
                              fit: BoxFit.fill,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                );
              },
            );
          },
        );
      },
    );
  }

  Widget _buildJacketOverlay() {
    return Positioned.fill(
      child: ValueListenableBuilder<int>(
        valueListenable: _gestureNotifier,
        builder: (ctx, _, child) {
          final cardSize = _getCardSize();
          return Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned(
                left: _cardCenter.dx - cardSize.width * _cardScale / 2,
                top: _cardCenter.dy - cardSize.height * _cardScale / 2,
                child: Transform.scale(
                  scale: _cardScale,
                  alignment: Alignment.topLeft,
                  child: Transform.rotate(
                    angle: _cardRotation,
                    child: child!,
                  ),
                ),
              ),
              if (_isTwoFingerGesture)
                Positioned.fill(
                  child: RepaintBoundary(
                    child: CustomPaint(
                      painter: _GuideLinePainter(
                          activeSnapAngles: _activeSnapAngles),
                    ),
                  ),
                ),
            ],
          );
        },
        child: _buildCurrentLayout(),
      ),
    );
  }

  // ---- Controls overlay (editingOverlay phase) ----

  Widget _buildControlsOverlay() {
    return Container(
      color: Colors.black.withValues(alpha: 0.4),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 10),
          _buildLayoutOptions(),
          const SizedBox(height: 6),
          _buildTrimControls(),
          const SizedBox(height: 6),
          _buildWaveform(),
          const SizedBox(height: 10),
        ],
      ),
    );
  }

  Widget _buildLayoutOptions() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: List.generate(4, (i) {
          final index = i + 1;
          final isSelected = _selectedLayoutIndex == index;
          return GestureDetector(
            onTap: () => setState(() {
              _selectedLayoutIndex = index;
              _cardScale = 1.0;
            }),
            child: SizedBox(
              width: 33,
              height: 33,
              child: SvgPicture.asset(
                'assets/icons/lyrics/layout_${index + 1}_${isSelected ? 'selected' : 'unselected'}.svg',
                width: 33,
                height: 33,
              ),
            ),
          );
        }),
      ),
    );
  }

  Widget _buildTrimControls() {
    final maxStart = 1.0 - (_durationSeconds / _totalDuration.inSeconds);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white54, width: 1.5),
            ),
            child: Center(
              child: Text(
                '$_durationSeconds',
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w600),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: LayoutBuilder(builder: (ctx, constraints) {
              final barW = constraints.maxWidth;
              final selW =
                  barW * (_durationSeconds / _totalDuration.inSeconds);
              return GestureDetector(
                onHorizontalDragStart: (_) {
                  if (_isPlaying) _audioService.stop();
                  setState(() {
                    _isPlaying = false;
                    _isDragging = true;
                    _playbackProgress = 0.0;
                    _pausedProgress = 0.0;
                  });
                },
                onHorizontalDragUpdate: (d) {
                  setState(() {
                    _startPosition = (_startPosition + d.delta.dx / barW)
                        .clamp(0.0, maxStart.clamp(0.0, 1.0));
                  });
                },
                onHorizontalDragEnd: (_) {
                  setState(() => _isDragging = false);
                  _playFromCurrentPosition();
                },
                child: SizedBox(
                  height: 32,
                  child: CustomPaint(
                    size: Size(barW, 32),
                    painter: _SeekBarPainter(
                      startPosition: _startPosition,
                      selectionWidth: selW,
                      barWidth: barW,
                      playbackProgress:
                          _isPlaying ? _playbackProgress : _pausedProgress,
                    ),
                  ),
                ),
              );
            }),
          ),
          const SizedBox(width: 10),
          GestureDetector(
            onTap: _isPlaying ? _stopPlayback : _playFromCurrentPosition,
            child: Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white54, width: 1.5),
              ),
              child: Icon(
                _isPlaying ? Icons.stop : Icons.play_arrow,
                color: Colors.white,
                size: 20,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWaveform() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: SizedBox(
        height: 42,
        child: LayoutBuilder(builder: (ctx, constraints) {
          final barW = constraints.maxWidth;
          return CustomPaint(
            size: Size(barW, 42),
            painter: _WaveformPainter(
              waveformData: _waveformData,
              selectionStart: _startPosition * barW,
              selectionWidth:
                  (_durationSeconds / _totalDuration.inSeconds) * barW,
              totalWidth: barW,
            ),
          );
        }),
      ),
    );
  }

  // ---- Track info section ----

  Widget _buildTrackInfoSection() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.track.trackName,
            style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 2),
          Text(
            widget.track.artistName,
            style: TextStyle(color: Colors.grey[400], fontSize: 14),
          ),
          const SizedBox(height: 12),
          const Row(
            children: [
              Icon(Icons.favorite_border, color: Colors.white, size: 26),
              SizedBox(width: 18),
              Icon(Icons.chat_bubble_outline,
                  color: Colors.white, size: 24),
              SizedBox(width: 18),
              Icon(Icons.add_circle_outline,
                  color: Colors.white, size: 24),
            ],
          ),
        ],
      ),
    );
  }

  // ---- Photo modal ----

  Widget _buildPhotoModalLayer() {
    return AnimatedBuilder(
      animation: _modalController,
      builder: (ctx, child) {
        final t = _modalController.value;
        return Stack(
          children: [
            // Scrim
            Positioned.fill(
              child: GestureDetector(
                onTap: _closePhotoModal,
                child: Container(
                    color:
                        Colors.black.withValues(alpha: 0.55 * t)),
              ),
            ),
            // Sheet
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: Transform.translate(
                offset: Offset(0, (1 - t) * 700),
                child: child!,
              ),
            ),
          ],
        );
      },
      child: _buildPhotoModalContent(),
    );
  }

  Widget _buildPhotoModalContent() {
    final screenH = MediaQuery.of(context).size.height;
    final modalH = screenH * 0.75;

    return Container(
      height: modalH,
      decoration: const BoxDecoration(
        color: Color(0xFF1C1C1C),
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      child: Column(
        children: [
          // Handle bar
          Container(
            margin: const EdgeInsets.only(top: 10),
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.white30,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          // Header
          Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'ライブラリ',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w600),
                ),
                GestureDetector(
                  onTap: _closePhotoModal,
                  child: const Icon(Icons.close,
                      color: Colors.white54, size: 22),
                ),
              ],
            ),
          ),
          // Grid
          Expanded(
            child: _hasPermission
                ? _buildPhotoGrid()
                : Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.photo_library_outlined,
                            color: Colors.white38, size: 48),
                        const SizedBox(height: 12),
                        const Text(
                          '写真へのアクセスを許可してください',
                          style: TextStyle(color: Colors.white54),
                        ),
                        const SizedBox(height: 16),
                        TextButton(
                          onPressed: () => PhotoManager.openSetting(),
                          child: const Text('設定を開く',
                              style:
                                  TextStyle(color: Color(0xFF5D8FFF))),
                        ),
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildPhotoGrid() {
    if (!_galleryLoaded) {
      return const Center(
          child: CircularProgressIndicator(color: Colors.white));
    }
    if (_galleryAssets.isEmpty) {
      return const Center(
        child: Text('写真が見つかりませんでした',
            style: TextStyle(color: Colors.white54)),
      );
    }
    return GridView.builder(
      padding: const EdgeInsets.all(2),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 2,
        mainAxisSpacing: 2,
      ),
      itemCount: _galleryAssets.length,
      itemBuilder: (ctx, i) {
        final asset = _galleryAssets[i];
        final isSelected = _selectedAsset?.id == asset.id;
        return GestureDetector(
          onTap: () => _selectAsset(asset),
          child: Stack(
            fit: StackFit.expand,
            children: [
              _GridThumbCell(asset: asset),
              if (isSelected)
                Container(
                  decoration: BoxDecoration(
                    border: Border.all(
                        color: const Color(0xFF5D8FFF), width: 3),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  // ---- Card layouts ----

  String get _displayLyrics {
    if (_lyricsData != null) return _lyricsData!.plainLyrics;
    return '';
  }

  Widget _buildCurrentLayout() {
    switch (_selectedLayoutIndex) {
      case 0:
        return _buildLayout1();
      case 1:
        return _buildLayout2();
      case 2:
        return _buildLayout3();
      case 3:
        return _buildLayout4();
      case 4:
        return _buildLayout5();
      default:
        return _buildLayout1();
    }
  }

  Widget _buildLayout1() {
    return Container(
      width: 196,
      height: 126,
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.52),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        children: [
          Expanded(
            flex: 60,
            child: Container(
              decoration: const BoxDecoration(
                color: Color.fromRGBO(0, 0, 0, 0.29),
                borderRadius: BorderRadius.only(
                    topLeft: Radius.circular(10),
                    topRight: Radius.circular(10)),
              ),
              padding: const EdgeInsets.all(11),
              child: Center(
                child: Text(
                  _displayLyrics,
                  style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                      height: 1.2),
                  textAlign: TextAlign.left,
                ),
              ),
            ),
          ),
          Expanded(
            flex: 40,
            child: Container(
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.52),
                borderRadius: const BorderRadius.only(
                    bottomLeft: Radius.circular(10),
                    bottomRight: Radius.circular(10)),
              ),
              padding:
                  const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
              child: Row(
                children: [
                  Container(
                    width: 36,
                    height: 40,
                    decoration: BoxDecoration(
                        color: const Color(0xFF9F9F9F),
                        borderRadius: BorderRadius.circular(3)),
                    child: widget.track.albumImageUrl.isNotEmpty
                        ? ClipRRect(
                            borderRadius: BorderRadius.circular(3),
                            child: CachedNetworkImage(
                                imageUrl: widget.track.albumImageUrl,
                                fit: BoxFit.cover))
                        : null,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(widget.track.trackName,
                            style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: Colors.white),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis),
                        const SizedBox(height: 2),
                        Text(widget.track.artistName,
                            style: const TextStyle(
                                fontSize: 7, color: Colors.white),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLayout2() {
    return SizedBox(
      width: 105,
      height: 147,
      child: Column(
        children: [
          Container(
            width: 105,
            height: 115,
            decoration: BoxDecoration(
                color: const Color(0xFF9F9F9F),
                borderRadius: BorderRadius.circular(3)),
            child: widget.track.albumImageUrl.isNotEmpty
                ? ClipRRect(
                    borderRadius: BorderRadius.circular(3),
                    child: CachedNetworkImage(
                        imageUrl: widget.track.albumImageUrl,
                        fit: BoxFit.cover))
                : null,
          ),
          const SizedBox(height: 7),
          Text(widget.track.trackName,
              style: const TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                  height: 1.388),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center),
          Text(widget.track.artistName,
              style:
                  const TextStyle(fontSize: 7, color: Colors.white, height: 1.5),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center),
        ],
      ),
    );
  }

  Widget _buildLayout3() {
    return Container(
      width: 172,
      height: 42,
      decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.52),
          borderRadius: BorderRadius.circular(7)),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      child: Row(
        children: [
          Container(
            width: 33,
            height: 35,
            decoration: BoxDecoration(
                color: const Color(0xFF9F9F9F),
                borderRadius: BorderRadius.circular(3)),
            child: widget.track.albumImageUrl.isNotEmpty
                ? ClipRRect(
                    borderRadius: BorderRadius.circular(3),
                    child: CachedNetworkImage(
                        imageUrl: widget.track.albumImageUrl,
                        fit: BoxFit.cover))
                : null,
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(widget.track.trackName,
                    style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Colors.white),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
                const SizedBox(height: 2),
                Text(widget.track.artistName,
                    style:
                        const TextStyle(fontSize: 7, color: Colors.white),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLayout4() {
    return Container(
      width: 140,
      height: 152,
      decoration: BoxDecoration(
          color: const Color(0xFF9F9F9F),
          borderRadius: BorderRadius.circular(2)),
      child: widget.track.albumImageUrl.isNotEmpty
          ? ClipRRect(
              borderRadius: BorderRadius.circular(2),
              child: CachedNetworkImage(
                  imageUrl: widget.track.albumImageUrl, fit: BoxFit.cover))
          : null,
    );
  }

  Widget _buildLayout5() {
    return Container(
      width: 130,
      height: 61,
      decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(12)),
      child: Stack(
        children: [
          Positioned(
            left: 11,
            top: 8,
            child: Container(
              width: 41,
              height: 45,
              decoration: BoxDecoration(
                  color: const Color(0xFF9F9F9F),
                  borderRadius: BorderRadius.circular(3)),
              child: widget.track.albumImageUrl.isNotEmpty
                  ? ClipRRect(
                      borderRadius: BorderRadius.circular(3),
                      child: CachedNetworkImage(
                          imageUrl: widget.track.albumImageUrl,
                          fit: BoxFit.cover))
                  : null,
            ),
          ),
          Positioned(
            left: 60,
            top: 6,
            right: 6,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(widget.track.trackName,
                    style: const TextStyle(
                        fontSize: 6, color: Colors.white),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
                const SizedBox(height: 2),
                Text(widget.track.artistName,
                    style: const TextStyle(
                        fontSize: 5,
                        color: Color(0xFF999999),
                        height: 0.957),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
          Positioned(
            left: 66,
            top: 28,
            child: Row(
              children: [
                Transform.rotate(
                    angle: 3.14159,
                    child: const Icon(Icons.skip_next,
                        color: Colors.white, size: 10)),
                const SizedBox(width: 7),
                Container(
                    width: 2.948,
                    height: 9.579,
                    decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(0.4))),
                const SizedBox(width: 1),
                Container(
                    width: 2.948,
                    height: 9.579,
                    decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(0.4))),
                const SizedBox(width: 13),
                const Icon(Icons.skip_next,
                    color: Colors.white, size: 10),
              ],
            ),
          ),
          Positioned(
            left: 61,
            bottom: 14,
            child: Stack(
              children: [
                Container(
                    width: 63,
                    height: 3,
                    decoration: BoxDecoration(
                        color:
                            const Color(0xFF474747).withValues(alpha: 0.8),
                        borderRadius: BorderRadius.circular(3))),
                Container(
                    width: 42.195,
                    height: 3,
                    decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.8),
                        borderRadius: const BorderRadius.only(
                            topLeft: Radius.circular(3),
                            bottomLeft: Radius.circular(3)))),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ---- Grid thumbnail cell ----

class _GridThumbCell extends StatefulWidget {
  final AssetEntity asset;
  const _GridThumbCell({required this.asset});

  @override
  State<_GridThumbCell> createState() => _GridThumbCellState();
}

class _GridThumbCellState extends State<_GridThumbCell> {
  Uint8List? _bytes;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final bytes = await widget.asset.thumbnailDataWithSize(
      const ThumbnailSize.square(200),
    );
    if (mounted) setState(() => _bytes = bytes);
  }

  @override
  Widget build(BuildContext context) {
    if (_bytes == null) {
      return Container(color: const Color(0xFF2A2A2A));
    }
    return Image.memory(_bytes!, fit: BoxFit.cover);
  }
}

// ---- Painters (reused from PostCardEditScreen) ----

class _SeekBarPainter extends CustomPainter {
  final double startPosition;
  final double selectionWidth;
  final double barWidth;
  final double playbackProgress;

  _SeekBarPainter({
    required this.startPosition,
    required this.selectionWidth,
    required this.barWidth,
    required this.playbackProgress,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final cy = size.height / 2;
    canvas.drawLine(
      Offset(0, cy),
      Offset(size.width, cy),
      Paint()
        ..color = const Color(0xFF3C3C3C)
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round,
    );

    final selL = startPosition * barWidth;
    final selR = selL + selectionWidth;
    canvas.drawLine(
      Offset(selL, cy),
      Offset(selR, cy),
      Paint()
        ..color = const Color(0xFF666666)
        ..strokeWidth = 4
        ..strokeCap = StrokeCap.round,
    );

    if (playbackProgress > 0) {
      final progressEnd = selL + selectionWidth * playbackProgress;
      canvas.drawLine(
        Offset(selL, cy),
        Offset(progressEnd, cy),
        Paint()
          ..shader = const LinearGradient(
            colors: [Color(0xFFFF6B35), Color(0xFFFF3D9A)],
          ).createShader(Rect.fromLTRB(selL, 0, selR, 0))
          ..strokeWidth = 4
          ..strokeCap = StrokeCap.round,
      );
    }

    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(
            center: Offset(selL + selectionWidth / 2, cy),
            width: 28,
            height: 12),
        const Radius.circular(6),
      ),
      Paint()..color = Colors.white,
    );

    final dotPaint = Paint()..color = const Color(0xFFFF6B9D);
    canvas.drawCircle(Offset(selL, cy), 4, dotPaint);
    canvas.drawCircle(Offset(selR, cy), 4, dotPaint);
  }

  @override
  bool shouldRepaint(covariant _SeekBarPainter old) =>
      old.startPosition != startPosition ||
      old.selectionWidth != selectionWidth ||
      old.playbackProgress != playbackProgress;
}

class _WaveformPainter extends CustomPainter {
  final List<double> waveformData;
  final double selectionStart;
  final double selectionWidth;
  final double totalWidth;

  _WaveformPainter({
    required this.waveformData,
    required this.selectionStart,
    required this.selectionWidth,
    required this.totalWidth,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final barCount = waveformData.length;
    final barSpacing = totalWidth / barCount;
    final barW = barSpacing * 0.6;
    final maxH = size.height * 0.9;
    final cy = size.height / 2;
    final selEnd = selectionStart + selectionWidth;

    for (int i = 0; i < barCount; i++) {
      final x = i * barSpacing + barSpacing / 2;
      final h = waveformData[i] * maxH;
      final isInSel = x >= selectionStart && x <= selEnd;
      final paint = Paint()
        ..color = isInSel
            ? Color.lerp(
                const Color(0xFFFF6B35),
                const Color(0xFFFF3D9A),
                (x - selectionStart) / selectionWidth,
              )!
            : const Color(0xFF4A4A4A);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(x - barW / 2, cy - h / 2, barW, h),
          const Radius.circular(2),
        ),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _WaveformPainter old) =>
      old.selectionStart != selectionStart ||
      old.selectionWidth != selectionWidth;
}

class _GuideLinePainter extends CustomPainter {
  final Set<double> activeSnapAngles;
  _GuideLinePainter({required this.activeSnapAngles});

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;
    final len = sqrt(size.width * size.width + size.height * size.height);
    final base = Paint()
      ..color = Colors.white.withValues(alpha: 0.3)
      ..strokeWidth = 1.0;

    for (final deg in [0.0, 90.0]) {
      final rad = deg * pi / 180;
      canvas.drawLine(
        Offset(cx - cos(rad) * len, cy - sin(rad) * len),
        Offset(cx + cos(rad) * len, cy + sin(rad) * len),
        base,
      );
    }

    if (activeSnapAngles.isNotEmpty) {
      final snap = Paint()
        ..color = Colors.orange.withValues(alpha: 0.5)
        ..strokeWidth = 1.0;
      final drawn = <double>{};
      for (final deg in activeSnapAngles) {
        final norm = deg % 180;
        if (drawn.contains(norm)) continue;
        drawn.add(norm);
        final rad = deg * pi / 180;
        canvas.drawLine(
          Offset(cx - cos(rad) * len, cy - sin(rad) * len),
          Offset(cx + cos(rad) * len, cy + sin(rad) * len),
          snap,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant _GuideLinePainter old) =>
      old.activeSnapAngles.length != activeSnapAngles.length ||
      !old.activeSnapAngles.containsAll(activeSnapAngles);
}

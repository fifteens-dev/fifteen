import 'dart:io';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:just_audio/just_audio.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/track_model.dart';
import '../models/post_model.dart';
import '../models/post_theme.dart';
import '../models/post_edit_state.dart';
import '../widgets/post_card.dart';
import '../widgets/post_card/post_card_constants.dart';
import '../widgets/post_card_back_info.dart';
import '../widgets/post_creation/lyrics_card_layouts.dart';
import '../widgets/post_creation/post_card_back_view.dart';
import '../widgets/dialogs/dialogs.dart';
import '../services/audio_player_service.dart';
import '../services/itunes_search_service.dart';
import '../services/post_service.dart';
import '../services/storage_service.dart';
import '../services/lyrics_service.dart';
import '../utils/campus_vibe_utils.dart';
import '../utils/color_extractor.dart';
import '../utils/current_user_helper.dart';
import '../utils/photo_helper.dart';
import '../widgets/campus_vibe_toggle_bar.dart';
import '../widgets/shared/user_info_badge.dart';

/// 投稿カード最終プレビュー画面
/// PostPreviewScreenと同じカード仕様（フリップ・音楽再生）で表示する
class PostFinalPreviewScreen extends StatefulWidget {
  final TrackModel track;
  final XFile? selectedImage;
  final Offset imageOffset;
  final double imageScale;
  final Size? imageNaturalSize;
  final int selectedLayoutIndex;
  final Offset cardPosition;
  final double cardScale;
  final double cardRotation;
  final bool isVibe;
  final String? vibeTopicId;
  final String? vibeTopicTitle;
  final LyricsData? lyricsData;
  final int audioStartMs;
  final int audioDurationSec;
  final Color? preExtractedGradientStart;
  final Color? preExtractedGradientEnd;
  final String? initialUsername;
  final String? initialUserIconUrl;
  final String? initialUniversity;
  final double albumArtOpacity;

  const PostFinalPreviewScreen({
    super.key,
    required this.track,
    this.selectedImage,
    this.imageOffset = Offset.zero,
    this.imageScale = 1.0,
    this.imageNaturalSize,
    required this.selectedLayoutIndex,
    this.cardPosition = Offset.zero,
    this.cardScale = 1.0,
    this.cardRotation = 0.0,
    this.isVibe = false,
    this.vibeTopicId,
    this.vibeTopicTitle,
    this.lyricsData,
    this.audioStartMs = 0,
    this.audioDurationSec = 15,
    this.preExtractedGradientStart,
    this.preExtractedGradientEnd,
    this.initialUsername,
    this.initialUserIconUrl,
    this.initialUniversity,
    this.albumArtOpacity = 1.0,
  });

  @override
  State<PostFinalPreviewScreen> createState() =>
      _PostFinalPreviewScreenState();
}

class _PostFinalPreviewScreenState extends State<PostFinalPreviewScreen>
    with TickerProviderStateMixin {
  // 音楽再生サービス
  final AudioPlayerService _audioService = AudioPlayerService();
  String? _cachedPreviewUrl;

  // 投稿関連
  final PostService _postService = PostService();
  final StorageService _storageService = StorageService();
  final FirebaseAuth _auth = FirebaseAuth.instance;
  bool _isPosting = false;

  // 反転アニメーション用（最終プレビューは常に裏面から開始）
  late AnimationController _flipController;
  late Animation<double> _flipAnimation;
  bool _showFront = false;

  // 背景フェードイン用（フリップ開始時に下画面を隠す）
  late AnimationController _bgFadeController;
  late Animation<double> _bgFadeAnimation;

  // 再生ボタンアニメーション用
  late AnimationController _playButtonAnimController;
  late Animation<double> _playButtonScaleAnim;
  late Animation<double> _playButtonOpacityAnim;

  // アルバムアートから抽出した色（裏面のテーマ用）
  Color? _extractedGradientStart;
  Color? _extractedGradientEnd;
  bool _isColorExtracting = false;

  // 歌詞カード編集状態
  late PostEditState _editState;

  // ジェスチャー途中の状態
  bool _isTwoFingerGesture = false;
  double _startScale = 1.0;
  double _startRotation = 0.0;
  static const List<double> _snapDegrees = [45, 135, 225, 315];
  static const double _snapThreshold = 3.0;
  Set<double> _activeSnapAngles = {};
  Set<double> _prevSnapAngles = {};
  bool _isTwoFingerAccepted = false;
  bool _rotationLocked = true;

  // 写真パン・ズーム
  late Offset _imageOffset;
  late double _imageScale;
  bool _isPhotoGestureMode = false;
  Offset _photoStartOffset = Offset.zero;
  double _photoStartScale = 1.0;
  Offset _photoStartFocalPoint = Offset.zero;

  // 現在のユーザー情報
  String _currentUsername = '';
  String? _currentUserIconUrl;
  String? _currentUniversity;

  // Campus Vibe 参加フラグ（デフォルトON）
  bool _campusVibeParticipating = true;

  @override
  void initState() {
    super.initState();
    _currentUniversity = widget.initialUniversity;
    if (widget.initialUsername != null && widget.initialUsername!.isNotEmpty) {
      _currentUsername = widget.initialUsername!;
      _currentUserIconUrl = widget.initialUserIconUrl;
    } else {
      _loadCurrentUserInfo();
    }

    _imageOffset = widget.imageOffset;
    _imageScale = widget.imageScale;

    // widget の cardPosition（左上座標）から cardCenter を復元
    final cardSize = PostCardBackView.cardSizeForLayout(widget.selectedLayoutIndex);
    final initialCenter = Offset(
      widget.cardPosition.dx + cardSize.width * widget.cardScale / 2,
      widget.cardPosition.dy + cardSize.height * widget.cardScale / 2,
    );
    _editState = PostEditState(
      selectedLayoutIndex: widget.selectedLayoutIndex,
      cardCenter: initialCenter,
      cardScale: widget.cardScale,
      cardRotation: widget.cardRotation,
    );

    // 最初から裏面を表示するため value: 1.0 で初期化
    _flipController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
      value: 1.0,
    );
    _flipAnimation = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _flipController, curve: Curves.easeInOut),
    );

    // 背景（下画面を隠す暗背景）- 画面表示と同時に不透明
    _bgFadeController = AnimationController(
      duration: const Duration(milliseconds: 1),
      vsync: this,
      value: 1.0, // 最初から不透明
    );
    _bgFadeAnimation = _bgFadeController;

    // 再生ボタンアニメーション（PostCardと同一仕様）
    _playButtonAnimController = AnimationController(
      duration: PostCardConstants.playButtonAnimationDuration,
      vsync: this,
    );
    _playButtonScaleAnim = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween<double>(begin: 0.0, end: 1.0)
            .chain(CurveTween(curve: Curves.easeOut)),
        weight: 50,
      ),
      TweenSequenceItem(
        tween: Tween<double>(begin: 1.0, end: 0.0)
            .chain(CurveTween(curve: Curves.easeIn)),
        weight: 50,
      ),
    ]).animate(_playButtonAnimController);
    _playButtonOpacityAnim = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween<double>(begin: 0.0, end: 1.0)
            .chain(CurveTween(curve: Curves.easeOut)),
        weight: 50,
      ),
      TweenSequenceItem(
        tween: Tween<double>(begin: 1.0, end: 0.0)
            .chain(CurveTween(curve: Curves.easeIn)),
        weight: 50,
      ),
    ]).animate(_playButtonAnimController);

    // 事前抽出された色があれば使用、なければ色抽出を実行
    if (widget.preExtractedGradientStart != null &&
        widget.preExtractedGradientEnd != null) {
      _extractedGradientStart = widget.preExtractedGradientStart;
      _extractedGradientEnd = widget.preExtractedGradientEnd;
    } else {
      _extractColorsFromAlbumArt();
    }

    // 最初から裏面表示なので、ビルド後すぐに音楽を再生
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _playMusicPreview();
        _playButtonAnimController.forward(from: 0.0);
      }
    });
  }

  Future<void> _loadCurrentUserInfo() async {
    final userInfo = await CurrentUserHelper.load();
    if (mounted) {
      setState(() {
        _currentUsername = userInfo.username;
        _currentUserIconUrl = userInfo.iconUrl;
      });
    }
  }

  /// アルバムアートから色を抽出
  Future<void> _extractColorsFromAlbumArt() async {
    if (_isColorExtracting) return;
    setState(() => _isColorExtracting = true);
    try {
      final imageUrl = widget.track.albumImageUrl;
      if (imageUrl.isNotEmpty) {
        final extractedColors =
            await ColorExtractor.extractGradientColors(imageUrl);
        if (mounted) {
          setState(() {
            _extractedGradientStart = extractedColors.$1;
            _extractedGradientEnd = extractedColors.$2;
          });
        }
      }
    } catch (e) {
      debugPrint('Color extraction error: $e');
    } finally {
      if (mounted) setState(() => _isColorExtracting = false);
    }
  }

  @override
  void dispose() {
    _flipController.dispose();
    _bgFadeController.dispose();
    _playButtonAnimController.dispose();
    _audioService.stop();
    _editState.dispose();
    super.dispose();
  }

  /// カードを反転
  void _flipCard() {
    if (_showFront) {
      _flipController.forward().then((_) {
        if (mounted && !_showFront) {
          _playButtonAnimController.forward(from: 0.0);
        }
      });
      _playMusicPreview();
    } else {
      _flipController.reverse();
    }
    setState(() {
      _showFront = !_showFront;
    });
  }

  /// 音楽のプレビューを再生
  Future<void> _playMusicPreview() async {
    var previewUrl = widget.track.previewUrl;

    if (previewUrl == null || previewUrl.isEmpty) {
      previewUrl = await _getPreviewUrlFromItunes();
    }

    if (previewUrl != null && previewUrl.isNotEmpty) {
      _cachedPreviewUrl = previewUrl;
      try {
        await _audioService.playPreview(
          previewUrl,
          startFrom: Duration(milliseconds: widget.audioStartMs),
          durationSeconds: widget.audioDurationSec,
        );
      } catch (e) {
        print('❌ 音楽プレビュー再生エラー: $e');
      }
    }
  }

  /// iTunesからプレビューURLを取得
  Future<String?> _getPreviewUrlFromItunes() async {
    try {
      final itunesService = ITunesSearchService();
      final tracks = await itunesService.searchTracks(
        '${widget.track.trackName} ${widget.track.artistName}',
        limit: 1,
      );
      if (tracks.isNotEmpty && tracks.first.previewUrl != null) {
        return tracks.first.previewUrl;
      }
    } catch (e) {
      print('❌ iTunes API取得エラー: $e');
    }
    return null;
  }

  /// 裏面用の動的テーマを生成
  PostTheme _getDynamicThemeForBack() {
    if (_extractedGradientStart != null && _extractedGradientEnd != null) {
      return ColorExtractor.createThemeFromColors(
        _extractedGradientStart!,
        _extractedGradientEnd!,
      );
    }
    return PostTheme.defaultTheme;
  }

  /// ダミーのPostModelを作成（表面プレビュー用）
  PostModel _createDummyPost() {
    final now = DateTime.now();
    return PostModel(
      postId: 'preview_post',
      userId: 'preview_user',
      username: _currentUsername.isNotEmpty ? _currentUsername : 'ユーザー',
      userIconUrl: _currentUserIconUrl,
      track: widget.track,
      likeCount: 3,
      commentCount: 3,
      likedUserIds: [],
      createdAt: now,
      updatedAt: now,
      theme: PostTheme.defaultTheme,
    );
  }

  /// 再生ボタンタップ時の処理
  Future<void> _handlePlayButtonTap() async {
    _playButtonAnimController.forward(from: 0.0);

    final isPlaying = _cachedPreviewUrl != null &&
        _audioService.isPlayingUrl(_cachedPreviewUrl!);

    if (isPlaying) {
      _audioService.pause();
    } else if (_audioService.isPaused && _cachedPreviewUrl != null) {
      _audioService.resume();
    } else {
      await _playMusicPreview();
    }
  }

  // ---- ジェスチャー共通 ----

  /// 歌詞カードの外側（写真ゾーン）かどうかを判定
  /// trueなら写真パン・ズームゾーン、falseなら歌詞カードゾーン
  bool _isInPhotoZone(Offset localPoint) {
    const photoW = 363.0;
    const photoH = 484.0;
    if (localPoint.dy < 0 || localPoint.dy > photoH) return false;
    if (localPoint.dx < 0 || localPoint.dx > photoW) return false;

    // 歌詞カードの実際の位置・スケール・回転に基づいて判定
    final cardSize = PostCardBackView.cardSizeForLayout(_editState.selectedLayoutIndex);
    final halfW = cardSize.width * _editState.cardScale / 2;
    final halfH = cardSize.height * _editState.cardScale / 2;
    final center = _editState.cardCenter;

    // カード中心からの相対座標を求め、カードの回転を逆に適用
    final dx = localPoint.dx - center.dx;
    final dy = localPoint.dy - center.dy;
    final angle = -_editState.cardRotation;
    final rx = dx * cos(angle) - dy * sin(angle);
    final ry = dx * sin(angle) + dy * cos(angle);

    // カード矩形内ならfalse（歌詞カードゾーン）、外ならtrue（写真ゾーン）
    return !(rx.abs() <= halfW && ry.abs() <= halfH);
  }

  bool _isInCardHitArea(Offset localFocalPoint) {
    const frameW = 363.0;
    const frameH = 484.0;
    return localFocalPoint.dx >= 0 &&
        localFocalPoint.dx <= frameW &&
        localFocalPoint.dy >= 0 &&
        localFocalPoint.dy <= frameH;
  }

  void _onGestureScaleStart(ScaleStartDetails details) {
    if (_isInPhotoZone(details.localFocalPoint)) {
      _isPhotoGestureMode = true;
      _photoStartOffset = _imageOffset;
      _photoStartScale = _imageScale;
      _photoStartFocalPoint = details.localFocalPoint;
      return;
    }
    _isPhotoGestureMode = false;
    _startScale = _editState.cardScale;
    _startRotation = _editState.cardRotation;
    _isTwoFingerAccepted = false;
    _rotationLocked = true;
    if (details.pointerCount >= 2 &&
        _isInCardHitArea(details.localFocalPoint)) {
      _isTwoFingerAccepted = true;
      setState(() => _isTwoFingerGesture = true);
    }
  }

  void _onGestureScaleUpdate(ScaleUpdateDetails details) {
    if (_isPhotoGestureMode) {
      final scaleRatio = details.scale;
      final newScale = (_photoStartScale * scaleRatio).clamp(0.5, 5.0);
      final panDelta = details.localFocalPoint - _photoStartFocalPoint;
      final newOffset = Offset(
        _photoStartFocalPoint.dx -
            (_photoStartFocalPoint.dx - _photoStartOffset.dx) *
                (newScale / _photoStartScale) +
            panDelta.dx,
        _photoStartFocalPoint.dy -
            (_photoStartFocalPoint.dy - _photoStartOffset.dy) *
                (newScale / _photoStartScale) +
            panDelta.dy,
      );
      setState(() {
        _imageOffset = newOffset;
        _imageScale = newScale;
      });
      return;
    }

    double newScale = _editState.cardScale;
    double newRotation = _editState.cardRotation;

    if (details.pointerCount >= 2) {
      if (!_isTwoFingerAccepted &&
          _isInCardHitArea(details.localFocalPoint)) {
        _isTwoFingerAccepted = true;
        _startScale = _editState.cardScale;
        _startRotation = _editState.cardRotation;
      }
      if (_isTwoFingerAccepted) {
        newScale =
            (_startScale * (1.0 + (details.scale - 1.0) * 0.6)).clamp(0.3, 3.0);
        // 10度未満は回転をロック（拡縮優先）
        const rotationThreshold = 10.0 * pi / 180.0;
        if (_rotationLocked && details.rotation.abs() < rotationThreshold) {
          newRotation = _startRotation;
        } else {
          _rotationLocked = false;
          newRotation = _startRotation + details.rotation * 0.6;
        }

        double deg = (newRotation * 180 / pi) % 360;
        if (deg < 0) deg += 360;
        final newSnaps = <double>{};
        for (final snapDeg in _snapDegrees) {
          double diff = (deg - snapDeg).abs();
          if (diff > 180) diff = 360 - diff;
          if (diff <= _snapThreshold) newSnaps.add(snapDeg);
        }
        if (newSnaps.isNotEmpty &&
            !newSnaps.every((a) => _prevSnapAngles.contains(a))) {
          HapticFeedback.lightImpact();
        }
        _prevSnapAngles = newSnaps;
        _activeSnapAngles = newSnaps;
      }
    }

    final newCenter = Offset(
      _editState.cardCenter.dx + details.focalPointDelta.dx * 0.7,
      _editState.cardCenter.dy + details.focalPointDelta.dy * 0.7,
    );

    setState(() {
      _editState.updateCardSilent(
        center: newCenter,
        scale: newScale,
        rotation: newRotation,
      );
      _editState.notify();
    });
  }

  void _onGestureScaleEnd(ScaleEndDetails details) {
    if (_isPhotoGestureMode) {
      setState(() => _isPhotoGestureMode = false);
      return;
    }
    const snapCenter = Offset(363.0 / 2, 484.0 * 0.45);
    setState(() {
      _isTwoFingerGesture = false;
      _isTwoFingerAccepted = false;
      _activeSnapAngles = {};
      _prevSnapAngles = {};

      if ((_editState.cardCenter - snapCenter).distance <= 40.0) {
        _editState.updateCardSilent(
          center: snapCenter,
          scale: _editState.cardScale,
          rotation: _editState.cardRotation,
        );
        HapticFeedback.lightImpact();
      }
      _editState.notify();
    });
  }

  /// 投稿を完了
  Future<void> _onPost() async {
    if (_isPosting) return;

    final confirmed = await ActionDialog.showPostConfirm(context);
    if (!confirmed) return;

    setState(() => _isPosting = true);

    try {
      final currentUser = _auth.currentUser;
      final userId = currentUser?.uid ?? 'test_user_temp';
      final username = _currentUsername.isNotEmpty
          ? _currentUsername
          : currentUser?.displayName ?? 'ユーザー';
      final userIconUrl = _currentUserIconUrl;

      // 写真を処理
      String? photoUrl;
      if (widget.selectedImage != null) {
        try {
          photoUrl = await PhotoHelper.processPhoto(
            image: widget.selectedImage!,
            userId: userId,
            storageService: _storageService,
          );
        } catch (e) {
          print('⚠️ 写真の処理に失敗: $e');
          photoUrl = null;
        }
      }

      // アルバムアートから色を抽出してテーマを生成
      PostTheme? extractedTheme;
      try {
        extractedTheme = await ColorExtractor.extractThemeFromAlbumArt(
          widget.track.albumImageUrl,
        );
      } catch (e) {
        extractedTheme = null;
      }

      // 歌詞テキストを取得
      String? lyricsText;
      if (widget.lyricsData != null) {
        final lyricsService = LyricsService();
        lyricsText = lyricsService.truncateLyrics(
          widget.lyricsData!.plainLyrics,
          maxLines: 4,
        );
      }

      // _editState から最終カード位置を計算
      final cardSize = PostCardBackView.cardSizeForLayout(_editState.selectedLayoutIndex);
      final cardPos = _editState.cardPositionForSize(cardSize);

      // 投稿を作成
      final postId = await _postService.createPost(
        userId: userId,
        username: username,
        userIconUrl: userIconUrl,
        trackData: widget.track.toMap(),
        photoUrl: photoUrl,
        imageOffsetX: _imageOffset.dx,
        imageOffsetY: _imageOffset.dy,
        imageScale: _imageScale,
        imageNaturalWidth: widget.imageNaturalSize?.width ?? 0,
        imageNaturalHeight: widget.imageNaturalSize?.height ?? 0,
        selectedLayoutIndex: _editState.selectedLayoutIndex,
        cardPositionX: cardPos.dx,
        cardPositionY: cardPos.dy,
        cardScale: _editState.cardScale,
        cardRotation: _editState.cardRotation,
        isVibe: widget.isVibe,
        vibeTopicId: widget.vibeTopicId,
        vibeTopicTitle: widget.vibeTopicTitle,
        theme: extractedTheme,
        lyricsText: lyricsText,
        audioStartMs: widget.audioStartMs,
        audioDurationSec: widget.audioDurationSec,
        university: _currentUniversity,
        campusVibeParticipating: _campusVibeParticipating,
      );

      print('✅ 投稿を作成しました: $postId');

      if (mounted) {
        Navigator.of(context).pushNamedAndRemoveUntil(
          '/home',
          (route) => false,
        );
      }
    } catch (e) {
      print('投稿作成エラー: $e');
      if (mounted) {
        setState(() => _isPosting = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('投稿の作成に失敗しました'),
            backgroundColor: Color(0xFFE53935),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        children: [
          // フリップ開始時に下画面（PostCardEditScreen）を隠す暗背景
          FadeTransition(
            opacity: _bgFadeAnimation,
            child: const ColoredBox(
              color: Color(0xFF121212),
              child: SizedBox.expand(),
            ),
          ),
          SafeArea(
        bottom: false,
        child: Column(
          children: [
            _buildHeader(),
            Expanded(
              child: SingleChildScrollView(
                child: Builder(
                  builder: (context) {
                    final cardW = MediaQuery.of(context).size.width - 2;
                    final cardH = cardW * (644.0 / 363.0);
                    return Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 1),
                      child: SizedBox(
                        width: cardW,
                        height: cardH,
                        child: FittedBox(
                          fit: BoxFit.fill,
                          child: SizedBox(
                            width: 363.0,
                            height: 644.0,
                            child: AnimatedBuilder(
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
                                      ? PostCard(
                                          post: _createDummyPost(),
                                          audioService: _audioService,
                                          showFrontOnly: true,
                                          hideReactionCounts: true,
                                          onCardTap: _flipCard,
                                          preExtractedGradientStart: _extractedGradientStart,
                                          preExtractedGradientEnd: _extractedGradientEnd,
                                          externalPreviewUrl: _cachedPreviewUrl,
                                        )
                                      : _buildBackCard(),
                                );
                              },
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
            if (CampusVibeUtils.shouldShow(_currentUniversity))
              CampusVibeToggleBar(
                university: _currentUniversity!,
                participating: _campusVibeParticipating,
                onChanged: (v) => setState(() => _campusVibeParticipating = v),
              ),
          ],
        ),
      ),
        ],
      ),
    );
  }

/// ヘッダー
  Widget _buildHeader() {
    return Hero(
      tag: 'post_flow_header',
      flightShuttleBuilder: (_, __, ___, ____, _____) => const Material(
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
      ),
      child: Material(
        color: Colors.transparent,
        child: Container(
          height: 50,
          padding: const EdgeInsets.symmetric(horizontal: 19),
          child: Row(
            children: [
              // 戻るボタン（くの字）- ダイアログなし
              Expanded(
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: GestureDetector(
                    onTap: _isPosting ? null : () => Navigator.pop(context),
                    child: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.5),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.arrow_back_ios_new,
                        color: _isPosting ? Colors.grey : Colors.white,
                        size: 20,
                      ),
                    ),
                  ),
                ),
              ),

              // タイトル
              const Text(
                '新規投稿',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                ),
              ),

              // 投稿するボタン
              Expanded(
                child: Align(
                  alignment: Alignment.centerRight,
                  child: _isPosting
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(
                              Color(0xFF5D8FFF),
                            ),
                          ),
                        )
                      : GestureDetector(
                          onTap: _onPost,
                          child: const Text(
                            '投稿する',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF5D8FFF),
                            ),
                          ),
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 投稿カード（裏面）
  Widget _buildBackCard() {
    const cardHeight = 644.0;
    const photoHeight = 484.0;

    return Transform(
      alignment: Alignment.center,
      transform: Matrix4.identity()..rotateY(pi),
      child: GestureDetector(
        onTap: _flipCard,
        onScaleStart: _onGestureScaleStart,
        onScaleUpdate: _onGestureScaleUpdate,
        onScaleEnd: _onGestureScaleEnd,
        behavior: HitTestBehavior.opaque,
        child: Container(
          width: 363,
          height: cardHeight,
          decoration: BoxDecoration(
            color: const Color(0xFF121212),
            borderRadius: BorderRadius.circular(18),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(18),
            child: Stack(
              children: [
                // 上部エリア（写真部分）
                Positioned(
                  left: 0,
                  top: 0,
                  width: 363,
                  height: photoHeight,
                  child: _buildPhotoSectionBack(),
                ),

                // 下部エリア（楽曲情報）
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: _buildInfoSectionBack(),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// 写真セクション（裏面）
  Widget _buildPhotoSectionBack() {
    const frameW = 363.0;
    const frameH = 484.0;

    // 画像表示サイズを事前計算
    double? displayW, displayH;
    if (widget.imageNaturalSize != null) {
      final natW = widget.imageNaturalSize!.width;
      final natH = widget.imageNaturalSize!.height;
      if (natW > 0 && natH > 0) {
        final baseScale = max(frameW / natW, frameH / natH);
        displayW = natW * baseScale;
        displayH = natH * baseScale;
      }
    }

    return Stack(
      children: [
        // 白い枠
        Positioned(
          left: 0,
          top: 0,
          width: frameW,
          height: frameH,
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
            ),
            child: ClipRRect(
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(18.0),
                topRight: Radius.circular(18.0),
              ),
              child: Stack(
                clipBehavior: Clip.hardEdge,
                children: [
                  // 選択された写真
                  if (widget.selectedImage != null && displayW != null)
                    Positioned(
                      left: _imageOffset.dx,
                      top: _imageOffset.dy,
                      child: Transform.scale(
                        scale: _imageScale,
                        alignment: Alignment.topLeft,
                        child: SizedBox(
                          width: displayW,
                          height: displayH!,
                          child: kIsWeb
                              ? Image.network(
                                  widget.selectedImage!.path,
                                  fit: BoxFit.fill,
                                )
                              : Image.file(
                                  File(widget.selectedImage!.path),
                                  fit: BoxFit.fill,
                                ),
                        ),
                      ),
                    )
                  else if (widget.selectedImage != null)
                    Positioned.fill(
                      child: kIsWeb
                          ? Image.network(widget.selectedImage!.path,
                              fit: BoxFit.cover)
                          : Image.file(File(widget.selectedImage!.path),
                              fit: BoxFit.cover),
                    )
                  else
                    Positioned.fill(
                      child: Container(color: const Color(0xFF121212)),
                    ),

                  // 歌詞カード
                  _buildLyricsCardBack(),

                  // スナップガイドライン（2本指ジェスチャー中のみ）
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
              ),
            ),
          ),
        ),

        // 再生ボタン（写真エリア中央）
        Positioned(
          left: (frameW - PostCardConstants.playButtonSize) / 2,
          top: (frameH - PostCardConstants.playButtonSize) / 2,
          child: _buildPlayButton(),
        ),

        // ユーザー情報（左上）
        Positioned(
          left: 15,
          top: 15,
          child: _buildUserInfoBack(),
        ),
      ],
    );
  }

  /// 再生ボタン
  Widget _buildPlayButton() {
    return StreamBuilder<PlayerState>(
      stream: _audioService.playerStateStream,
      builder: (context, snapshot) {
        final isPlaying = _cachedPreviewUrl != null &&
            _audioService.isPlayingUrl(_cachedPreviewUrl!);

        return GestureDetector(
          onTap: _handlePlayButtonTap,
          behavior: HitTestBehavior.opaque,
          child: Container(
            width: PostCardConstants.playButtonSize,
            height: PostCardConstants.playButtonSize,
            color: Colors.transparent,
            child: AnimatedBuilder(
              animation: _playButtonAnimController,
              builder: (context, child) {
                return Opacity(
                  opacity: _playButtonOpacityAnim.value,
                  child: Transform.scale(
                    scale: _playButtonScaleAnim.value,
                    child: Container(
                      width: PostCardConstants.playButtonSize,
                      height: PostCardConstants.playButtonSize,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.black.withOpacity(
                            PostCardConstants.playButtonBackgroundOpacity),
                        border: Border.all(
                          color: Colors.white,
                          width: PostCardConstants.playButtonBorderWidth,
                        ),
                      ),
                      child: Icon(
                        isPlaying ? Icons.pause : Icons.play_arrow,
                        color: Colors.white,
                        size: PostCardConstants.playButtonIconSize,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        );
      },
    );
  }

  /// 歌詞カード（裏面・ジェスチャーで移動・拡縮・回転可能）
  Widget _buildLyricsCardBack() {
    final layoutType =
        LyricsCardLayout.getLayoutType(_editState.selectedLayoutIndex);

    // 歌詞テキストを取得
    String? lyricsText;
    if (widget.lyricsData != null) {
      final lyricsService = LyricsService();
      lyricsText = lyricsService.truncateLyrics(
        widget.lyricsData!.plainLyrics,
        maxLines: 4,
      );
    }

    final cardSize = PostCardBackView.cardSizeForLayout(_editState.selectedLayoutIndex);
    final cardPos = _editState.cardPositionForSize(cardSize);

    return Positioned(
      left: cardPos.dx,
      top: cardPos.dy,
      child: Transform.scale(
        scale: _editState.cardScale,
        alignment: Alignment.topLeft,
        child: Transform.rotate(
          angle: _editState.cardRotation,
          alignment: Alignment.center,
          child: LyricsCardLayout(
            layoutType: layoutType,
            track: widget.track,
            lyricsText: lyricsText,
            albumArtOpacity: widget.albumArtOpacity,
          ),
        ),
      ),
    );
  }

  /// ユーザー情報（裏面）
  Widget _buildUserInfoBack() {
    return UserInfoBadge(
      username: _currentUsername.isNotEmpty ? _currentUsername : 'ユーザー',
      iconUrl: _currentUserIconUrl,
      hashtagText: widget.isVibe && widget.vibeTopicTitle != null
          ? '#${widget.vibeTopicTitle}'
          : null,
      showBackground: false,
    );
  }

  /// 情報セクション（裏面）
  Widget _buildInfoSectionBack() {
    final theme = _getDynamicThemeForBack();

    return PostCardBackInfo(
      track: widget.track,
      theme: theme,
      likeCount: 3,
      commentCount: 3,
      isLiked: false,
      showCounts: false,
      onLike: () {},
      onComment: () {},
      onAdd: () {},
    );
  }
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
          base);
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
            snap);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _GuideLinePainter old) =>
      old.activeSnapAngles.length != activeSnapAngles.length ||
      !old.activeSnapAngles.containsAll(activeSnapAngles);
}


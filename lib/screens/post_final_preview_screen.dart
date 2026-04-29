import 'dart:io';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:just_audio/just_audio.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
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
import '../services/vibe_topic_service.dart';
import '../widgets/common/app_toast.dart';
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
  // 水平スナップ（0°/180°）フラグ
  bool _isHorizontalSnap = false;
  // 水平スナップ時の回転ロック
  bool _horizontalSnapLockActive = false;
  double _snapStartGestureRotation = 0.0; // スナップした瞬間の details.rotation
  double _snapLockedAngle = 0.0;          // スナップ先の角度（0 or π）

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

  // Vibe/感情 選択状態（最終プレビューで選択可能に）
  late bool _isVibe;
  String? _vibeTopicId;
  String? _vibeTopicTitle;

  @override
  void initState() {
    super.initState();
    _isVibe = widget.isVibe;
    _vibeTopicId = widget.vibeTopicId;
    _vibeTopicTitle = widget.vibeTopicTitle;
    _loadTodaysTopic();

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

  /// 今日のVibeお題を読み込み
  Future<void> _loadTodaysTopic() async {
    try {
      final topic = await VibeTopicService().getTodaysTopic();
      if (mounted) {
        setState(() {
          if (topic != null) {
            _vibeTopicId = topic.topicId;
            _vibeTopicTitle = topic.title;
          }
        });
      }
    } catch (e) {
      debugPrint('Error loading today\'s topic: $e');
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
    const photoH = 645.0;
    if (localPoint.dy < 0 || localPoint.dy > photoH) return false;
    if (localPoint.dx < 0 || localPoint.dx > photoW) return false;

    // 歌詞カードの実際の位置・スケール・回転に基づいて判定
    final cardSize = PostCardBackView.cardSizeForLayout(_editState.selectedLayoutIndex);
    final hitMultiplier = _editState.selectedLayoutIndex == 2 ? 3.0 : 1.5;
    final halfW = cardSize.width * _editState.cardScale / 2 * hitMultiplier;
    final halfH = cardSize.height * _editState.cardScale / 2 * hitMultiplier;
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
    const frameH = 645.0;
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
    _horizontalSnapLockActive = false;
    _isHorizontalSnap = false;
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

        const rotationThreshold = 10.0 * pi / 180.0;

        // ── 回転計算 ────────────────────────────────────────────────
        // ① ジェスチャー開始ロック（最初の10度は回転しない）
        double intendedRotation;
        if (_rotationLocked && details.rotation.abs() < rotationThreshold) {
          intendedRotation = _startRotation;
        } else {
          _rotationLocked = false;
          intendedRotation = _startRotation + details.rotation * 0.6;
        }

        // ② 水平スナップロック（平行になった瞬間も再ロック）
        if (_horizontalSnapLockActive) {
          final cardDelta =
              (details.rotation - _snapStartGestureRotation) * 0.6;
          if (cardDelta.abs() < rotationThreshold) {
            // ロック範囲内 → スナップ角に固定
            newRotation = _snapLockedAngle;
          } else {
            // 10度以上動かした → ロック解除して継続
            _horizontalSnapLockActive = false;
            _isHorizontalSnap = false;
            newRotation = _snapLockedAngle + cardDelta;
          }
        } else {
          newRotation = intendedRotation;
        }

        // ── 斜めスナップ検出 ─────────────────────────────────────
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

        // ── 水平スナップ検出（ロック中は再検出しない）────────────
        if (!_horizontalSnapLockActive) {
          bool isHoriz = false;
          for (final h in [0.0, 180.0]) {
            double diff = (deg - h).abs();
            if (diff > 180) diff = 360 - diff;
            if (diff <= _snapThreshold) { isHoriz = true; break; }
          }
          if (isHoriz && !_isHorizontalSnap) {
            // 平行になった瞬間：振動 + ロック発動
            HapticFeedback.lightImpact();
            _snapStartGestureRotation = details.rotation;
            _snapLockedAngle = _nearestHorizontalRad(newRotation);
            _horizontalSnapLockActive = true;
            newRotation = _snapLockedAngle;
          }
          _isHorizontalSnap = isHoriz;
        }
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
    const snapCenter = Offset(363.0 / 2, 645.0 * 0.45);
    setState(() {
      _isTwoFingerGesture = false;
      _isTwoFingerAccepted = false;
      _activeSnapAngles = {};
      _prevSnapAngles = {};
      _isHorizontalSnap = false;
      _horizontalSnapLockActive = false;

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

  /// 0° と 180° のうち、rotation に近い方をラジアンで返す
  double _nearestHorizontalRad(double rotation) {
    double deg = (rotation * 180 / pi) % 360;
    if (deg < 0) deg += 360;
    final diff0 = deg <= 180 ? deg : 360 - deg;
    final diff180 = (deg - 180).abs();
    return diff0 <= diff180 ? 0.0 : pi;
  }

  /// 投稿を完了（isVibeを引数で指定）
  Future<void> _onPost({required bool asVibe}) async {
    if (_isPosting) return;

    setState(() => _isVibe = asVibe);
    setState(() => _isPosting = true);

    try {
      final currentUser = _auth.currentUser;
      final userId = currentUser?.uid ?? 'test_user_temp';
      final username = _currentUsername.isNotEmpty
          ? _currentUsername
          : currentUser?.displayName ?? 'ユーザー';
      final userIconUrl = _currentUserIconUrl;

      final String? previewUrlBase = _cachedPreviewUrl ?? widget.track.previewUrl;

      // Phase 1: アップロード(URL取得前)・テーマ抽出・プレビューURL を並列実行
      // モバイル: putDataのみ実行→Reference返却（getDownloadURLはPhase2で並列化）
      // Web: Base64変換→immediateUrlに格納
      final Future<({String? immediateUrl, Reference? storageRef})> photoSplitFuture =
          widget.selectedImage != null
              ? PhotoHelper.processPhotoSplit(
                  image: widget.selectedImage!,
                  userId: userId,
                  storageService: _storageService,
                ).catchError((dynamic e) {
                  print('⚠️ 写真のアップロードに失敗: $e');
                  return (
                    immediateUrl: null as String?,
                    storageRef: null as Reference?,
                  );
                })
              : Future.value((
                  immediateUrl: null as String?,
                  storageRef: null as Reference?,
                ));

      final Future<PostTheme?> themeFuture =
          ColorExtractor.extractThemeFromAlbumArt(widget.track.albumImageUrl)
              .catchError((dynamic _) => null as PostTheme?);

      final Future<String?> previewFuture =
          (previewUrlBase == null || previewUrlBase.isEmpty)
              ? _getPreviewUrlFromItunes()
              : Future.value(previewUrlBase);

      final results1 = await Future.wait<dynamic>([
        photoSplitFuture,
        themeFuture,
        previewFuture,
      ]);

      final photoResult =
          results1[0] as ({String? immediateUrl, Reference? storageRef});
      final PostTheme? extractedTheme = results1[1] as PostTheme?;
      final String? previewUrl = results1[2] as String?;

      // ローカル処理（高速）
      String? lyricsText;
      if (widget.lyricsData != null) {
        final lyricsService = LyricsService();
        lyricsText = lyricsService.truncateLyrics(
          widget.lyricsData!.plainLyrics,
          maxLines: 4,
        );
      }

      final cardSize =
          PostCardBackView.cardSizeForLayout(_editState.selectedLayoutIndex);
      final cardPos = _editState.cardPositionForSize(cardSize);
      final trackData = widget.track.toMap()..['previewUrl'] = previewUrl;

      // Phase 2: getDownloadURL と createPost を並列実行
      // モバイル: putData完了済みのRefからURLを取得しつつ、同時にFirestore書き込み
      // Web: immediateUrl をそのまま使うので並列化は createPost のみ
      final Future<String?> urlFuture = photoResult.storageRef != null
          ? photoResult.storageRef!
              .getDownloadURL()
              .then((url) => url as String?)
              .catchError((dynamic _) => null as String?)
          : Future.value(photoResult.immediateUrl);

      final Future<String> postIdFuture = _postService.createPost(
        userId: userId,
        username: username,
        userIconUrl: userIconUrl,
        trackData: trackData,
        // モバイル: photoUrlは後でupdatePostPhotoUrlで反映 / Web: 即時URL
        photoUrl: photoResult.immediateUrl,
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
        isVibe: _isVibe,
        vibeTopicId: _isVibe ? _vibeTopicId : null,
        vibeTopicTitle: _isVibe ? _vibeTopicTitle : null,
        theme: extractedTheme,
        lyricsText: lyricsText,
        audioStartMs: widget.audioStartMs,
        audioDurationSec: widget.audioDurationSec,
        university: _currentUniversity,
        campusVibeParticipating: _campusVibeParticipating,
      );

      final results2 = await Future.wait<dynamic>([urlFuture, postIdFuture]);
      final String? photoUrl = results2[0] as String?;
      final String postId = results2[1] as String;

      // モバイルのみ: getDownloadURLで取得したURLをバックグラウンドで反映
      if (photoResult.storageRef != null && photoUrl != null) {
        _postService
            .updatePostPhotoUrl(postId: postId, photoUrl: photoUrl)
            .ignore();
      }

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
        AppToast.show(context, '投稿の作成に失敗しました');
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
            Expanded(
              child: SingleChildScrollView(
                physics: const NeverScrollableScrollPhysics(),
                child: Builder(
                  builder: (context) {
                    final cardW = MediaQuery.of(context).size.width - 2;
                    final cardH = cardW * (645.0 / 363.0);
                    // 裏面の写真領域は 484/645、情報領域は残り
                    final infoH = cardH * (160.0 / 645.0);
                    // トグル下端 = 情報領域上端から18px上
                    final toggleBottom = infoH + 18;
                    return Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 1),
                      child: SizedBox(
                        width: cardW,
                        height: cardH,
                        child: Stack(
                          children: [
                            Positioned.fill(
                              child: FittedBox(
                                fit: BoxFit.fill,
                                child: SizedBox(
                                  width: 363.0,
                                  height: 645.0,
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
                            // Campus Vibe トグル（写真領域の右下、情報領域から18px上）
                            if (CampusVibeUtils.canPost(_currentUniversity))
                              Positioned(
                                right: 9,
                                bottom: toggleBottom,
                                child: CampusVibeToggleBar(
                                  university: CampusVibeUtils.targetUniversity,
                                  participating: _campusVibeParticipating,
                                  onChanged: (v) => setState(() => _campusVibeParticipating = v),
                                ),
                              ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
            // Vibe / 今の気分 切り替えバー
            _buildPostTypeBar(),
          ],
        ),
      ),
          // ボタンオーバーレイ（カードの上に重ねる）
          Positioned(
            top: 0, left: 0, right: 0,
            child: SafeArea(
              bottom: false,
              child: _buildButtonsOverlay(),
            ),
          ),
        ],
      ),
    );
  }

  /// Vibe / 今の気分 投稿タイプバー
  Widget _buildPostTypeBar() {
    final topicLabel = _vibeTopicTitle != null ? '\n【#$_vibeTopicTitle】' : '';
    return Container(
      padding: const EdgeInsets.only(left: 12, right: 12, top: 6, bottom: 6),
      color: const Color(0xFF121212),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            // Vibeで投稿ボタン
            Expanded(
              child: GestureDetector(
                onTap: _isPosting ? null : () => _onPost(asVibe: true),
                child: Container(
                  height: 50,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(25),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      Image.asset(
                        'assets/icons/vibe_post_bg.png',
                        fit: BoxFit.cover,
                      ),
                      Padding(
                        padding: const EdgeInsets.only(left: 34, right: 8),
                        child: Align(
                          alignment: Alignment.center,
                          child: Text.rich(
                            TextSpan(
                              children: [
                                const TextSpan(
                                  text: 'Vibeで投稿',
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w700,
                                    color: Colors.white,
                                  ),
                                ),
                                if (topicLabel.isNotEmpty)
                                  TextSpan(
                                    text: topicLabel,
                                    style: const TextStyle(
                                      fontSize: 8,
                                      fontWeight: FontWeight.w500,
                                      color: Colors.white,
                                    ),
                                  ),
                              ],
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(width: 6),
            // 今の気分で投稿ボタン
            Expanded(
              child: GestureDetector(
                onTap: _isPosting ? null : () => _onPost(asVibe: false),
                child: Container(
                  height: 50,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(25),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      Image.asset(
                        'assets/icons/emotion_post_bg.png',
                        fit: BoxFit.cover,
                      ),
                      Padding(
                        padding: const EdgeInsets.only(left: 34, right: 8),
                        child: const Align(
                          alignment: Alignment.center,
                          child: Text(
                            '今の気分で投稿',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildButtonsOverlay() {
    return Container(
      height: 50,
      padding: const EdgeInsets.symmetric(horizontal: 19),
      child: Row(
        children: [
          GestureDetector(
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
          const Spacer(),
          if (_isPosting)
            const CupertinoActivityIndicator(
              color: Color(0xFF5D8FFF),
              radius: 8,
            ),
        ],
      ),
    );
  }

  /// 投稿カード（裏面）
  Widget _buildBackCard() {
    const cardHeight = 645.0;
    const cardWidth = 363.0;

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
          width: cardWidth,
          height: cardHeight,
          decoration: BoxDecoration(
            color: const Color(0xFF121212),
            borderRadius: BorderRadius.circular(18),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(18),
            child: Stack(
              children: [
                // 写真（カード全体）
                Positioned.fill(
                  child: _buildPhotoSectionBack(),
                ),

                // 楽曲情報オーバーレイ（下部174px）
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: _buildInfoSectionBack(),
                ),

                // 再生ボタン（写真エリア中央）
                Positioned(
                  left: (cardWidth - PostCardConstants.playButtonSize) / 2,
                  top: (cardHeight - 174 - PostCardConstants.playButtonSize) / 2,
                  child: _buildPlayButton(),
                ),

                // ユーザー情報（左上）
                Positioned(
                  left: 23,
                  top: 18,
                  child: UserInfoBadge(
                    username: _currentUsername.isNotEmpty ? _currentUsername : 'ユーザー',
                    iconUrl: _currentUserIconUrl,
                    hashtagText: widget.isVibe && widget.vibeTopicTitle != null
                        ? '#${widget.vibeTopicTitle}'
                        : null,
                    showBackground: false,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// 写真セクション（裏面・カード全体を覆う）
  Widget _buildPhotoSectionBack() {
    // 高さ基準でフィット: 縦幅=645になるまで等比拡大し横幅は363でクリップ
    const frameH = 645.0;

    double? displayW, displayH;
    if (widget.imageNaturalSize != null) {
      final natW = widget.imageNaturalSize!.width;
      final natH = widget.imageNaturalSize!.height;
      if (natW > 0 && natH > 0) {
        final baseScale = frameH / natH;
        displayW = natW * baseScale;
        displayH = natH * baseScale;
      }
    }

    return Stack(
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
                    ? Image.network(widget.selectedImage!.path, fit: BoxFit.fill)
                    : Image.file(File(widget.selectedImage!.path), fit: BoxFit.fill),
              ),
            ),
          )
        else if (widget.selectedImage != null)
          Positioned.fill(
            child: kIsWeb
                ? Image.network(widget.selectedImage!.path, fit: BoxFit.cover)
                : Image.file(File(widget.selectedImage!.path), fit: BoxFit.cover),
          )
        else
          const Positioned.fill(
            child: ColoredBox(color: Color(0xFF121212)),
          ),

        // 水平スナップ時の横点線（歌詞カードの後ろ）
        if (_isTwoFingerGesture && _isHorizontalSnap)
          Positioned.fill(
            child: RepaintBoundary(
              child: CustomPaint(
                painter: _HorizontalDottedLinePainter(
                  y: _editState.cardCenter.dy,
                ),
              ),
            ),
          ),

        // 歌詞カード
        _buildLyricsCardBack(),

        // スナップガイドライン（2本指ジェスチャー中のみ）
        if (_isTwoFingerGesture)
          Positioned.fill(
            child: RepaintBoundary(
              child: CustomPaint(
                painter: _GuideLinePainter(activeSnapAngles: _activeSnapAngles),
              ),
            ),
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

class _HorizontalDottedLinePainter extends CustomPainter {
  final double y;

  const _HorizontalDottedLinePainter({required this.y});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.7)
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;

    const dashWidth = 8.0;
    const dashSpace = 6.0;
    double x = 0;
    while (x < size.width) {
      canvas.drawLine(
        Offset(x, y),
        Offset((x + dashWidth).clamp(0.0, size.width), y),
        paint,
      );
      x += dashWidth + dashSpace;
    }
  }

  @override
  bool shouldRepaint(_HorizontalDottedLinePainter old) => old.y != y;
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


import 'dart:io';
import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../models/track_model.dart';
import '../models/post_model.dart';
import '../models/post_theme.dart';
import 'package:just_audio/just_audio.dart';
import '../widgets/post_card.dart';
import '../widgets/post_card/post_card_constants.dart';
import '../widgets/post_card_back_info.dart';
import '../widgets/post_creation/lyrics_card_layouts.dart';
import '../services/audio_player_service.dart';
import '../services/lyrics_service.dart';
import '../services/itunes_search_service.dart';
import '../utils/color_extractor.dart';
import '../utils/current_user_helper.dart';
import '../widgets/shared/user_info_badge.dart';
import 'post_photo_selection_screen.dart';

/// 投稿プレビュー画面
class PostPreviewScreen extends StatefulWidget {
  final TrackModel track;
  final LyricsData? lyricsData;
  final Future<LyricsData?>? lyricsFuture; // バックグラウンド取得用
  final bool isVibe;
  final String? vibeTopicId;
  final String? vibeTopicTitle; // Vibeお題のタイトル
  final Color? preExtractedGradientStart;
  final Color? preExtractedGradientEnd;

  const PostPreviewScreen({
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
  State<PostPreviewScreen> createState() => _PostPreviewScreenState();
}

class _PostPreviewScreenState extends State<PostPreviewScreen> with TickerProviderStateMixin {
  XFile? _selectedImage;
  Offset _imageOffset = Offset.zero;
  double _imageScale = 1.0;
  Size? _imageNaturalSize;

  // 音楽再生サービス
  final AudioPlayerService _audioService = AudioPlayerService();
  String? _cachedPreviewUrl; // 再生ボタン用にキャッシュ

  // 歌詞カード関連
  int _selectedLayoutIndex = 0; // 選択されたレイアウト (0-4)
  Rect _rect = const Rect.fromLTWH(0, 0, 196, 126); // 歌詞カードの位置とサイズ
  double _cardRotation = 0.0; // 回転角度（ラジアン）
  int _audioStartMs = 0; // 音楽再生開始位置（ミリ秒）
  int _audioDurationSec = 15; // 音楽再生時間（秒）
  LyricsData? _lyricsData; // 取得した歌詞データ
  Future<LyricsData?>? _lyricsFuture; // バックグラウンド取得用Future

  // 反転アニメーション用
  late AnimationController _flipController;
  late Animation<double> _flipAnimation;
  bool _showFront = true; // 初期状態は表面
  Timer? _autoFlipTimer; // 自動反転用タイマー

  // 再生ボタンアニメーション用
  late AnimationController _playButtonAnimController;
  late Animation<double> _playButtonScaleAnim;
  late Animation<double> _playButtonOpacityAnim;

  // アルバムアートから抽出した色（裏面のテーマ用）
  Color? _extractedGradientStart;
  Color? _extractedGradientEnd;
  bool _isColorExtracting = false;

  // 現在のユーザー情報
  String _currentUsername = '';
  String? _currentUserIconUrl;

  @override
  void initState() {
    super.initState();
    print('🎬 PostPreviewScreen initState()');
    print('  - track: ${widget.track.trackName} by ${widget.track.artistName}');

    // 現在のユーザー情報を取得
    _loadCurrentUserInfo();

    // 歌詞データの初期化
    _lyricsData = widget.lyricsData;
    _lyricsFuture = widget.lyricsFuture;

    // バックグラウンドで取得中の歌詞があれば、それを待つ
    if (_lyricsFuture != null) {
      print('🎵 バックグラウンドで歌詞取得中... 完了を待機します');
      _lyricsFuture!.then((lyricsData) {
        if (mounted) {
          setState(() {
            _lyricsData = lyricsData;
          });
          if (lyricsData != null) {
            print('✅ バックグラウンド歌詞取得完了: ${lyricsData.source}');
          }
        }
      });
    }

    _flipController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    _flipAnimation = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _flipController, curve: Curves.easeInOut),
    );

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
    if (widget.preExtractedGradientStart != null && widget.preExtractedGradientEnd != null) {
      print('✅ 事前抽出された色を使用します');
      _extractedGradientStart = widget.preExtractedGradientStart;
      _extractedGradientEnd = widget.preExtractedGradientEnd;
    } else {
      print('⚠️ 色が未抽出のため、バックグラウンドで抽出を開始します');
      _extractColorsFromAlbumArt();
    }

    // 1秒後に自動的にカードを裏返す（裏面で音楽再生開始）
    _autoFlipTimer = Timer(const Duration(seconds: 1), () {
      if (mounted && _showFront) {
        print('⏰ 1秒経過：カードを自動的に裏返します');
        _flipCard();
      }
    });
  }

  /// 現在のユーザー情報を取得
  Future<void> _loadCurrentUserInfo() async {
    final userInfo = await CurrentUserHelper.load();
    if (mounted) {
      setState(() {
        _currentUsername = userInfo.username;
        _currentUserIconUrl = userInfo.iconUrl;
      });
    }
  }

  /// BPMを非同期で取得
  /// 音楽のプレビューを再生
  Future<void> _playMusicPreview() async {
    var previewUrl = widget.track.previewUrl;

    // previewURLが空の場合、iTunesから取得
    if (previewUrl == null || previewUrl.isEmpty) {
      print('⚠️ Spotify previewURLが空のため、iTunesから取得します');
      previewUrl = await _getPreviewUrlFromItunes();
    }

    if (previewUrl != null && previewUrl.isNotEmpty) {
      _cachedPreviewUrl = previewUrl; // 再生ボタン用にキャッシュ
      try {
        print('🎵 音楽プレビューを再生開始: ${widget.track.trackName}');
        await _audioService.playPreview(
          previewUrl,
          startFrom: Duration(milliseconds: _audioStartMs),
          durationSeconds: _audioDurationSec,
        );
      } catch (e) {
        print('❌ 音楽プレビュー再生エラー: $e');
      }
    } else {
      print('⚠️ プレビューURLが取得できませんでした');
    }
  }

  /// iTunesからプレビューURLを取得（スコアリングで最適なバージョンを選択）
  Future<String?> _getPreviewUrlFromItunes() async {
    try {
      final itunesService = ITunesSearchService();
      final trackName = widget.track.trackName;
      final artistName = widget.track.artistName;

      print('🍎 iTunes APIからプレビューURL取得: $trackName - $artistName');

      final result = await itunesService.getPreviewUrlWithArt(
        trackName: trackName,
        artistName: artistName,
      );

      if (result?['previewUrl'] != null) {
        print('✅ iTunes APIからプレビューURL取得成功');
        return result!['previewUrl'];
      } else {
        print('❌ iTunes APIでプレビューURLが見つかりませんでした');
        return null;
      }
    } catch (e) {
      print('❌ iTunes API取得エラー: $e');
      return null;
    }
  }

  /// アルバムアートから色を抽出
  Future<void> _extractColorsFromAlbumArt() async {
    if (_isColorExtracting) return;

    setState(() {
      _isColorExtracting = true;
    });

    try {
      final imageUrl = widget.track.albumImageUrl;
      if (imageUrl.isNotEmpty) {
        // ColorExtractor を使用して色を抽出
        final extractedColors = await ColorExtractor.extractGradientColors(imageUrl);

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
      if (mounted) {
        setState(() {
          _isColorExtracting = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _autoFlipTimer?.cancel();
    _flipController.dispose();
    _playButtonAnimController.dispose();
    // 音楽再生を停止
    _audioService.stop();
    super.dispose();
  }

  /// カードを反転
  void _flipCard() {
    if (_showFront) {
      _flipController.forward().then((_) {
        // フリップ完了後に再生ボタンアニメーションを表示
        if (mounted && !_showFront) {
          _playButtonAnimController.forward(from: 0.0);
        }
      });
      // 裏面に切り替え → 音楽を再生
      _playMusicPreview();
    } else {
      _flipController.reverse();
      // 表面に切り替え（音楽は停止しない）
    }
    setState(() {
      _showFront = !_showFront;
    });
  }

  /// TrackModelからダミーのPostModelを作成（プレビュー用）
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
      theme: PostTheme.defaultTheme, // デフォルトテーマを使用（色抽出は PostCard 内で実行される）
    );
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

  /// 写真を追加
  Future<void> _pickImage() async {
    print('📷 写真選択画面へ遷移');

    // 写真選択フロー（PostPhotoSelectionScreen → MusicTrimScreen → LyricsCardSelectionScreen → PostFinalPreviewScreen）
    await Navigator.push(
      context,
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (context) => PostPhotoSelectionScreen(
          track: widget.track,
          lyricsData: _lyricsData,
          lyricsFuture: _lyricsFuture,
          isVibe: widget.isVibe,
          vibeTopicId: widget.vibeTopicId,
          vibeTopicTitle: widget.vibeTopicTitle,
        ),
      ),
    );

    // フローから戻ったら音楽を再開
    if (mounted) _playMusicPreview();
  }


  @override
  Widget build(BuildContext context) {
    print('🎨 PostPreviewScreen build()呼び出し');

    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            // ヘッダー
            _buildHeader(),

            // 投稿カードプレビュー（スクロールなし・画面に収まるようサイズ調整）
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  const aspectRatio = 644.0 / 363.0;
                  final screenW = MediaQuery.of(context).size.width - 2;
                  final byWidth = screenW;
                  final byHeight = constraints.maxHeight / aspectRatio;
                  final cardW = byWidth < byHeight ? byWidth : byHeight;
                  final cardH = cardW * aspectRatio;
                  return Center(
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
          ],
        ),
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
              // 戻るボタン
              Expanded(
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: GestureDetector(
                    onTap: () => Navigator.of(context).pop(),
                    child: const Icon(
                      Icons.arrow_back_ios_new,
                      color: Colors.white,
                      size: 22,
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

              // 右側スペーサー
              const Expanded(child: SizedBox.shrink()),
            ],
          ),
        ),
      ),
    );
  }

  /// 投稿カード（裏面） - Figmaデザインに基づく
  Widget _buildBackCard() {
    const cardHeight = 644.0;
    const photoHeight = 484.0; // 写真エリアの高さ

    return Transform(
      alignment: Alignment.center,
      transform: Matrix4.identity()..rotateY(pi), // 裏面なので反転
      child: GestureDetector(
        onTap: _flipCard, // タップで表面に戻る
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
                // 上部エリア（写真選択部分）
                Positioned(
                  left: 0,
                  top: 0,
                  width: 363,
                  height: photoHeight,
                  child: _buildPhotoSectionBack(),
                ),

                // 下部エリア（楽曲情報）- bottomから配置してグラデーションが写真エリアと重なるようにする
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

  /// 再生ボタンタップ時の処理
  Future<void> _handlePlayButtonTap() async {
    // アニメーションを開始
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

  /// 再生ボタン（裏面の写真エリア中央）
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

  /// 写真セクション（裏面）
  Widget _buildPhotoSectionBack() {
    // 画像表示サイズを事前計算
    const frameW = 363.0;
    const frameH = 484.0;
    double? displayW, displayH;
    if (_imageNaturalSize != null) {
      final natW = _imageNaturalSize!.width;
      final natH = _imageNaturalSize!.height;
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
              border: Border.all(color: Colors.white, width: 0.5),
              borderRadius: BorderRadius.circular(18),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(18),
              child: Stack(
                clipBehavior: Clip.hardEdge,
                children: [
                  // 選択された写真または写真追加ボタン
                  if (_selectedImage != null && displayW != null)
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
                                  _selectedImage!.path,
                                  fit: BoxFit.fill,
                                )
                              : Image.file(
                                  File(_selectedImage!.path),
                                  fit: BoxFit.fill,
                                ),
                        ),
                      ),
                    )
                  else if (_selectedImage != null)
                    Positioned.fill(
                      child: kIsWeb
                          ? Image.network(_selectedImage!.path, fit: BoxFit.cover)
                          : Image.file(File(_selectedImage!.path), fit: BoxFit.cover),
                    )
                  else
                    _buildAddPhotoButtonBack(),

                  // 歌詞カードプレビュー（写真選択後）
                  if (_selectedImage != null) _buildLyricsCardBack(),
                ],
              ),
            ),
          ),
        ),

        // 再生ボタン（写真エリアの中央）
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

  /// 写真追加ボタン（裏面）
  Widget _buildAddPhotoButtonBack() {
    return Container(
      color: const Color(0xFF121212),
      child: Align(
        alignment: const Alignment(0.0, 0.35),
        child: GestureDetector(
          onTap: _pickImage,
          child: Container(
            width: 120,
            height: 40,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // +アイコン
                Container(
                  width: 25,
                  height: 25,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.black,
                  ),
                  child: const Icon(
                    Icons.add,
                    color: Colors.white,
                    size: 16,
                  ),
                ),
                const SizedBox(width: 8),
                // テキスト
                const Text(
                  '写真を追加',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: Colors.black,
                  ),
                ),
              ],
            ),
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

  /// 情報セクション（裏面）- ホーム画面のPostCardと同じデザインを引き継ぐ
  Widget _buildInfoSectionBack() {
    final theme = _getDynamicThemeForBack();

    return PostCardBackInfo(
      track: widget.track,
      theme: theme,
      likeCount: 3,
      commentCount: 3,
      isLiked: false,
      showCounts: false, // プレビュー画面ではカウント非表示
      onLike: () {
        // プレビュー画面ではアクションなし
      },
      onComment: () {
        // プレビュー画面ではアクションなし
      },
      onAdd: () {
        // プレビュー画面ではアクションなし
      },
    );
  }



  /// 歌詞カードプレビュー（裏面）
  /// 歌詞カード（裏面・固定表示）
  Widget _buildLyricsCardBack() {
    // 共通ウィジェットを使用してレイアウトを表示
    final layoutType = LyricsCardLayout.getLayoutType(_selectedLayoutIndex);

    // rectから位置とスケールを取得
    final baseSize = _getCardSizeBack();
    final cardScale = _rect.width / baseSize.width;

    // 歌詞テキストを取得
    String? lyricsText;
    if (_lyricsData != null) {
      final lyricsService = LyricsService();
      lyricsText = lyricsService.truncateLyrics(
        _lyricsData!.plainLyrics,
        maxLines: 4,
      );
    }

    // 固定表示（操作不可）
    return Positioned(
      left: _rect.left,
      top: _rect.top,
      child: Transform.scale(
        scale: cardScale,
        alignment: Alignment.topLeft,
        child: Transform.rotate(
          angle: _cardRotation,
          alignment: Alignment.center,
          child: LyricsCardLayout(
            layoutType: layoutType,
            track: widget.track,
            lyricsText: lyricsText,
          ),
        ),
      ),
    );
  }

  /// カードサイズを取得（裏面用）
  Size _getCardSizeBack() {
    switch (_selectedLayoutIndex) {
      case 0:
        return const Size(196, 126); // レイアウト1
      case 1:
        return const Size(105, 147); // レイアウト2
      case 2:
        return const Size(172, 42); // レイアウト3
      case 3:
        return const Size(140, 152); // レイアウト4
      case 4:
        return const Size(130, 61); // レイアウト5
      default:
        return const Size(196, 126);
    }
  }


  // === 以下のレイアウトメソッド（_buildLayout1Back ~ _buildLayout5Back）は ===
  // === LyricsCardLayout 共通ウィジェットに移行済み ===
  // === lib/widgets/post_creation/lyrics_card_layouts.dart を参照 ===
}

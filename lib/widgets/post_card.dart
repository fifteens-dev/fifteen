import 'dart:convert';
import 'dart:math';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:just_audio/just_audio.dart';
import '../models/post_model.dart';
import '../models/post_theme.dart';
import '../screens/other_user_profile_screen.dart';
import '../services/audio_player_service.dart';
import '../services/itunes_search_service.dart';
import '../services/lyrics_service.dart';
import '../services/post_service.dart';
import '../utils/color_extractor.dart';
import '../utils/photo_helper.dart';
import 'profile_widgets.dart';
import 'post_creation/lyrics_card_layouts.dart';
import 'post_card/post_card_constants.dart';
import 'post_card/marquee_text.dart';

/// 投稿カードウィジェット（表裏反転アニメーション付き）
class PostCard extends StatefulWidget {
  final PostModel post;
  final VoidCallback? onLike;
  final VoidCallback? onComment;
  final VoidCallback? onAdd;
  final String? currentUserId;
  final String? currentUserIconUrl; // 現在のユーザーのアイコンURL（楽観的UI用）
  final AudioPlayerService audioService; // 音楽再生サービス（外部から注入）
  final bool showFrontOnly; // trueの場合、表面のみ表示（反転なし）
  final VoidCallback? onCardTap; // showFrontOnly時の外部タップハンドラ
  final bool isSaved; // 保存済みかどうか
  final bool hideReactionCounts; // trueの場合、リアクション数を非表示（プレビュー用）
  final Color? preExtractedGradientStart; // 事前抽出されたグラデーション開始色
  final Color? preExtractedGradientEnd; // 事前抽出されたグラデーション終了色
  final bool autoFlipAfterDelay; // trueの場合、0.5秒後に自動で裏返す

  const PostCard({
    super.key,
    required this.post,
    this.onLike,
    this.onComment,
    this.onAdd,
    this.currentUserId,
    this.currentUserIconUrl,
    required this.audioService, // 必須パラメータ
    this.showFrontOnly = false, // デフォルトは両面表示
    this.onCardTap, // 外部タップハンドラ（オプション）
    this.isSaved = false, // デフォルトは未保存
    this.hideReactionCounts = false, // デフォルトはカウント表示
    this.preExtractedGradientStart, // 事前抽出された色（オプション）
    this.preExtractedGradientEnd, // 事前抽出された色（オプション）
    this.autoFlipAfterDelay = false, // デフォルトは自動反転なし
  });

  @override
  State<PostCard> createState() => _PostCardState();
}

class _PostCardState extends State<PostCard>
    with TickerProviderStateMixin, AutomaticKeepAliveClientMixin {
  late AnimationController _flipController;
  late Animation<double> _flipAnimation;
  bool _showFront = true;

  // 再生ボタンアニメーション用
  late AnimationController _playButtonAnimationController;
  late Animation<double> _playButtonScaleAnimation;
  late Animation<double> _playButtonOpacityAnimation;

  // 楽観的UI更新用のローカル状態
  bool? _isLikedOptimistic;
  int? _likeCountOptimistic;
  List<String>? _likedByUserIconUrlsOptimistic;

  // iTunes検索サービス
  final ITunesSearchService _itunesService = ITunesSearchService();

  // 動的に取得したpreview URLをキャッシュ
  String? _cachedPreviewUrl;

  /// 表示するアルバムアートURL（Spotifyから取得したものを使用）
  String get _displayAlbumArtUrl => widget.post.track.albumImageUrl;

  /// 裏面に写真が設定されているかチェック
  bool get _hasBackPhoto {
    return widget.post.photoUrl != null && widget.post.photoUrl!.isNotEmpty;
  }

  /// photoUrlがネットワークURL（https://）かどうかをチェック
  bool get _isPhotoUrlNetwork {
    if (!_hasBackPhoto) return false;
    return PhotoHelper.isNetworkUrl(widget.post.photoUrl!);
  }

  /// photoUrlがData URL（Base64）かどうかをチェック
  bool get _isPhotoUrlDataUrl {
    if (!_hasBackPhoto) return false;
    return PhotoHelper.isDataUrl(widget.post.photoUrl!);
  }

  // アルバムアートから抽出した色
  Color? _extractedGradientStart;
  Color? _extractedGradientEnd;
  bool _isColorExtracting = false;

  // 動的に取得した歌詞
  String? _fetchedLyricsText;
  bool _isLyricsFetching = false;
  bool _lyricsFetchAttempted = false;

  // スクロール時にウィジェットの状態を保持
  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();

    _initializeAnimations();
    _initializeColors();

    // 自動反転が有効な場合、0.5秒後に裏返す
    if (widget.autoFlipAfterDelay) {
      Future.delayed(PostCardConstants.autoFlipDelay, () {
        if (mounted && _showFront) {
          _flipCard();
        }
      });
    }
  }

  /// アニメーションの初期化
  void _initializeAnimations() {
    // カード反転アニメーション
    _flipController = AnimationController(
      duration: PostCardConstants.flipAnimationDuration,
      vsync: this,
    );
    _flipAnimation = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _flipController, curve: Curves.easeInOut),
    );

    // 再生ボタンアニメーション
    _playButtonAnimationController = AnimationController(
      duration: PostCardConstants.playButtonAnimationDuration,
      vsync: this,
    );

    // スケールアニメーション（0.5秒で拡大→0.5秒で縮小）
    _playButtonScaleAnimation = TweenSequence<double>([
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
    ]).animate(_playButtonAnimationController);

    // 不透明度アニメーション（0.5秒で表示→0.5秒でフェードアウト）
    _playButtonOpacityAnimation = TweenSequence<double>([
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
    ]).animate(_playButtonAnimationController);
  }

  /// 色テーマの初期化
  void _initializeColors() {
    // 色の優先順位:
    // 1. 事前抽出パラメータ
    // 2. Firestoreに保存されたテーマ（デフォルトテーマでない場合）
    // 3. リアルタイム抽出
    if (widget.preExtractedGradientStart != null && widget.preExtractedGradientEnd != null) {
      debugPrint('✅ PostCard: 事前抽出された色を使用します');
      _extractedGradientStart = widget.preExtractedGradientStart;
      _extractedGradientEnd = widget.preExtractedGradientEnd;
    } else if (widget.post.theme != PostTheme.defaultTheme) {
      debugPrint('✅ PostCard: Firestoreのテーマを使用します');
      _extractedGradientStart = widget.post.theme.gradientStart;
      _extractedGradientEnd = widget.post.theme.gradientEnd;
    } else {
      debugPrint('⚠️ PostCard: 色が未抽出のため、抽出を開始します');
      _extractColorsFromAlbumArt();
    }
  }

  /// アルバムアートから色を抽出
  Future<void> _extractColorsFromAlbumArt() async {
    if (_isColorExtracting) return;

    setState(() {
      _isColorExtracting = true;
    });

    try {
      final imageUrl = _displayAlbumArtUrl;
      debugPrint('🎨 Extracting colors from: $imageUrl');

      if (imageUrl.isNotEmpty) {
        // グラデーション用の色ペアを抽出
        final (gradientStart, gradientEnd) =
            await ColorExtractor.extractGradientColors(imageUrl);

        debugPrint('✅ Color extraction successful!');
        debugPrint('  Gradient Start: $gradientStart');
        debugPrint('  Gradient End: $gradientEnd');

        if (mounted) {
          setState(() {
            _extractedGradientStart = gradientStart;
            _extractedGradientEnd = gradientEnd;
          });
        }
      }
    } catch (e) {
      debugPrint('❌ Color extraction error: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isColorExtracting = false;
        });
      }
    }
  }

  /// 歌詞を動的に取得（lyricsTextがない場合のフォールバック）
  Future<void> _fetchLyricsIfNeeded() async {
    // 既に歌詞がある場合、または取得中/取得済みの場合はスキップ
    if (widget.post.lyricsText != null || _isLyricsFetching || _lyricsFetchAttempted) {
      return;
    }

    setState(() {
      _isLyricsFetching = true;
    });

    try {
      final lyricsService = LyricsService();
      final lyricsData = await lyricsService.getLyrics(
        trackName: widget.post.track.trackName,
        artistName: widget.post.track.artistName,
      );

      if (mounted && lyricsData != null) {
        final truncatedLyrics = lyricsService.truncateLyrics(
          lyricsData.plainLyrics,
          maxLines: 4,
        );
        setState(() {
          _fetchedLyricsText = truncatedLyrics;
        });
        debugPrint('✅ PostCard: 歌詞を動的に取得しました');

        // Firebaseに保存（テスト投稿以外の場合）
        final postId = widget.post.postId;
        if (!postId.startsWith('test_post_') && !postId.startsWith('preview_')) {
          final postService = PostService();
          await postService.updateLyricsText(
            postId: postId,
            lyricsText: truncatedLyrics,
          );
        }
      }
    } catch (e) {
      debugPrint('❌ PostCard: 歌詞取得エラー: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isLyricsFetching = false;
          _lyricsFetchAttempted = true;
        });
      }
    }
  }

  @override
  void dispose() {
    _flipController.dispose();
    _playButtonAnimationController.dispose();
    super.dispose();
  }

  /// カードをタップして裏返す
  void _flipCard() async {
    // 表面のみ表示モードの場合は外部ハンドラを呼ぶ
    if (widget.showFrontOnly) {
      widget.onCardTap?.call();
      return;
    }

    // 状態を先に更新してUIを即座に反映
    setState(() {
      _showFront = !_showFront;
    });

    if (!_showFront) {
      // 裏面に反転
      _flipController.forward().then((_) {
        // フリップアニメーション完了後、再生ボタンのアニメーションを表示
        if (mounted && !_showFront) {
          _playButtonAnimationController.forward(from: 0.0);
        }
      });
      if (kDebugMode) {
        print('=== Flipping to back ===');
        print('Track: ${widget.post.track.trackName} - ${widget.post.track.artistName}');
      }

      // 音楽再生は非同期で実行（UIブロックしない）
      _playAudioAsync();
    } else {
      // 表面に反転
      _flipController.reverse();
      if (kDebugMode) {
        print('=== Flipping to front - stopping playback ===');
      }
      widget.audioService.stop();
    }
  }

  /// 音楽を非同期で再生（UIをブロックしない）
  Future<void> _playAudioAsync() async {
    // キャッシュまたは動的に取得したpreview URLを使用
    String? previewUrl = _cachedPreviewUrl;

    // キャッシュがない場合、iTunes APIから取得
    if (previewUrl == null) {
      if (kDebugMode) {
        print('🍎 Fetching preview URL from iTunes (keeping Spotify album art)...');
      }
      final result = await _itunesService.getPreviewUrlWithArt(
        trackName: widget.post.track.trackName,
        artistName: widget.post.track.artistName,
      );

      if (result != null) {
        previewUrl = result['previewUrl'];

        // キャッシュに保存（preview URLのみ、アルバムアートはSpotifyのものを維持）
        _cachedPreviewUrl = previewUrl;

        if (kDebugMode) {
          print('✅ iTunes preview URL obtained and cached');
        }
      } else {
        if (kDebugMode) {
          print('❌ No preview URL found from iTunes');
        }
      }
    } else {
      if (kDebugMode) {
        print('📦 Using cached preview URL');
      }
    }

    // プレビューURLがあれば再生
    if (previewUrl != null && previewUrl.isNotEmpty) {
      if (kDebugMode) {
        print('▶️  Starting playback...');
      }
      try {
        await widget.audioService.playPreview(previewUrl);
      } catch (e) {
        if (kDebugMode) {
          print('❌ Playback error: $e');
        }
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('音楽の再生に失敗しました: ${e.toString()}'),
              backgroundColor: Colors.red,
              duration: const Duration(seconds: 3),
            ),
          );
        }
      }
    } else {
      if (kDebugMode) {
        print('⚠️  No preview URL available');
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('この曲のプレビューURLが見つかりません'),
            duration: Duration(seconds: 2),
          ),
        );
      }
    }
  }

  /// いいねボタンが押された時の処理（楽観的UI更新）
  void _handleLikeTap() {
    if (widget.onLike != null) {
      setState(() {
        final currentIsLiked = _isLikedOptimistic ??
            (widget.currentUserId != null &&
                widget.post.isLikedBy(widget.currentUserId!));
        final currentLikeCount = _likeCountOptimistic ?? widget.post.likeCount;
        final currentIconUrls = _likedByUserIconUrlsOptimistic ??
            List<String>.from(widget.post.likedByUserIconUrls);

        _isLikedOptimistic = !currentIsLiked;
        _likeCountOptimistic =
            currentIsLiked ? currentLikeCount - 1 : currentLikeCount + 1;

        // アイコンURLリストも楽観的に更新
        if (currentIsLiked) {
          // いいね解除：自分のアイコンを削除
          if (widget.currentUserIconUrl != null) {
            currentIconUrls.remove(widget.currentUserIconUrl);
          } else if (currentIconUrls.isNotEmpty) {
            // アイコンURLがない場合は最後の要素を削除
            currentIconUrls.removeLast();
          }
        } else {
          // いいね追加：自分のアイコンを追加
          final iconUrl = widget.currentUserIconUrl ?? '';
          currentIconUrls.add(iconUrl);
        }
        _likedByUserIconUrlsOptimistic = currentIconUrls;
      });

      widget.onLike!();
    }
  }

  @override
  void didUpdateWidget(PostCard oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.post.postId != widget.post.postId) {
      _isLikedOptimistic = null;
      _likeCountOptimistic = null;
      _likedByUserIconUrlsOptimistic = null;
    } else if (_isLikedOptimistic != null || _likeCountOptimistic != null || _likedByUserIconUrlsOptimistic != null) {
      final actualIsLiked = widget.currentUserId != null &&
          widget.post.isLikedBy(widget.currentUserId!);
      final actualLikeCount = widget.post.likeCount;

      if (_isLikedOptimistic == actualIsLiked &&
          _likeCountOptimistic == actualLikeCount) {
        _isLikedOptimistic = null;
        _likeCountOptimistic = null;
        _likedByUserIconUrlsOptimistic = null;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context); // AutomaticKeepAliveClientMixinのために必要

    return Center(
      child: SizedBox(
        width: 363.0,
        height: 644.0,
        child: widget.showFrontOnly
            ? _buildFront() // 表面のみ表示（反転アニメーションなし）
            : AnimatedBuilder(
                animation: _flipAnimation,
                builder: (context, child) {
                  final angle = _flipAnimation.value * pi;
                  final isFront = angle < pi / 2;

                  return Transform(
                    alignment: Alignment.center,
                    transform: Matrix4.identity()
                      ..setEntry(3, 2, 0.001)
                      ..rotateY(angle),
                    child: isFront ? _buildFront() : _buildBack(),
                  );
                },
              ),
      ),
    );
  }

  /// 動的にテーマを生成（抽出された色を優先、なければデフォルトテーマ）
  PostTheme _getDynamicTheme() {
    // 抽出された色がある場合は動的にテーマを生成
    if (_extractedGradientStart != null && _extractedGradientEnd != null) {
      return ColorExtractor.createThemeFromColors(
        _extractedGradientStart!,
        _extractedGradientEnd!,
      );
    }
    // デフォルトのテーマを使用
    return widget.post.theme;
  }

  /// カード表面（アルバムカバー全表示）
  Widget _buildFront() {
    final theme = _getDynamicTheme();

    return GestureDetector(
      onTap: _flipCard,
      child: LayoutBuilder(
        builder: (context, constraints) {
          // 実際のレンダリングサイズを使用（制約を受けた場合でも正確）
          final cardWidth = constraints.maxWidth > 0 ? constraints.maxWidth : 363.0;
          final cardHeight = constraints.maxHeight > 0 ? constraints.maxHeight : 644.0;
          final albumSize = cardWidth; // アルバムカバーは正方形（カード幅と同じ）
          final contentHeight = cardHeight * (294.0 / 644.0); // タイトルエリア

          return Container(
            width: cardWidth,
            height: cardHeight,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(PostCardConstants.cardBorderRadius),
              color: theme.gradientEnd,
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(PostCardConstants.cardBorderRadius),
              child: Stack(
            children: [
              // アルバムカバー（全表示）
              Positioned(
                left: 0,
                top: 0,
                child: Container(
                  width: albumSize,
                  height: albumSize,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(3),
                  ),
                  child: _displayAlbumArtUrl.isNotEmpty
                      ? Image.network(
                          _displayAlbumArtUrl,
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) {
                            return _buildAlbumPlaceholder();
                          },
                        )
                      : _buildAlbumPlaceholder(),
                ),
              ),

              // グラデーションオーバーレイ（下部3/7）
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                height: contentHeight,
                child: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        theme.gradientStart
                            .withOpacity(0.0), // 上端は透明（アルバムと重なる部分）
                        theme.gradientEnd, // 13px以降は不透明
                      ],
                      stops: const [
                        0.0,
                        0.0442
                      ], // 上部4.42% (13px/294px) でグラデーション完了
                    ),
                  ),
                ),
              ),

              // コンテンツ（下部）- Figmaに合わせて絶対配置
              // Figmaは下から計測（Y軸反転）なので、294px基準で変換
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                height: contentHeight,
                child: Stack(
                  children: [
                    // ユーザー情報 - Figma: bottom: 238px → top: 56px (294-238), left: 12px
                    Positioned(
                      left: cardWidth * (12 / 363),
                      top: contentHeight * (24 / 294),
                      child: _buildUserInfo(theme),
                    ),

                    // 曲名とアーティスト名 - Figma: bottom: 185px → top: 109px (294-185), left: 11px, right: 66px
                    Positioned(
                      left: cardWidth * (11 / 363),
                      top: contentHeight * (63 / 294),
                      right: cardWidth * (66 / 363),
                      child: _buildTrackInfo(theme),
                    ),

                    // シェアボタン - Figma: bottom: 195px → top: 99px (294-195), left: 314px
                    Positioned(
                      left: cardWidth * (314 / 363),
                      top: contentHeight * (63 / 294),
                      child: _buildShareButton(theme),
                    ),

                    // リアクション - Figma: bottom: 141px → top: 153px (294-141), left: 12px, right: 12px
                    Positioned(
                      left: cardWidth * (12 / 363),
                      right: cardWidth * (12 / 363),
                      top: contentHeight * (128 / 294),
                      child: _buildReactions(theme),
                    ),

                    // 音楽波形 - Figma: bottom: 96px → top: 198px (294-96), left: 4px, right: 5px
                    Positioned(
                      left: cardWidth * (12 / 363),
                      top: contentHeight * (166 / 294),
                      child: _buildWaveform(theme),
                    ),

                    // コメント入力欄 - Figma: bottom: 40px → top: 254px (294-40), left: 12px, right: 12px
                    Positioned(
                      left: cardWidth * (12 / 363),
                      right: cardWidth * (12 / 363),
                      top: contentHeight * (211 / 294),
                      child: _buildCommentButton(theme),
                    ),

                    // "Provided courtesy of Apple Music" - Figma: bottom: 12px → top: 282px (294-12), left: 17px
                    Positioned(
                      left: cardWidth * (17 / 363),
                      top: contentHeight * (268 / 294),
                      child: Text(
                        'Provided courtesy of Apple Music',
                        style: TextStyle(
                          fontSize: 10,
                          color: theme.secondaryTextColor.withOpacity(0.7),
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
        },
      ),
    );
  }

  /// カード裏面（写真+アルバムカード+下部セクション）
  Widget _buildBack() {
    final theme = _getDynamicTheme();

    return Transform(
      alignment: Alignment.center,
      transform: Matrix4.identity()..rotateY(pi),
      child: GestureDetector(
        onTap: _flipCard,
        child: LayoutBuilder(
          builder: (context, constraints) {
            // 実際のレンダリングサイズを使用（制約を受けた場合でも正確）
            final cardWidth = constraints.maxWidth > 0 ? constraints.maxWidth : 363.0;
            final cardHeight = constraints.maxHeight > 0 ? constraints.maxHeight : 644.0;
            final photoHeight = cardHeight * (484.0 / 644.0); // 写真エリア
            final contentHeight = cardHeight * (174.0 / 644.0); // タイトルエリア

            return Container(
              width: cardWidth,
              height: cardHeight,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(PostCardConstants.cardBorderRadius),
                color: theme.gradientEnd,
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(PostCardConstants.cardBorderRadius),
                child: Stack(
              children: [
                // 写真エリア（上部）- 投稿の写真またはアルバムアート
                Positioned(
                  left: 0,
                  top: 0,
                  child: Container(
                    width: cardWidth,
                    height: photoHeight,
                    child: _hasBackPhoto
                        ? (_isPhotoUrlDataUrl
                            // Web版: Base64 Data URL
                            ? Builder(
                                builder: (context) {
                                  try {
                                    // data:image/jpeg;base64,... の形式から base64 部分を抽出
                                    final String base64String = widget.post.photoUrl!.split(',')[1];
                                    final Uint8List bytes = base64Decode(base64String);
                                    return Image.memory(
                                      bytes,
                                      fit: BoxFit.cover,
                                      errorBuilder: (context, error, stackTrace) {
                                        if (kDebugMode) {
                                          print('❌ Failed to decode Base64 photo: $error');
                                        }
                                        // デコード失敗時はアルバムアートにフォールバック
                                        return _displayAlbumArtUrl.isNotEmpty
                                            ? Image.network(
                                                _displayAlbumArtUrl,
                                                fit: BoxFit.cover,
                                                errorBuilder: (context, error, stackTrace) {
                                                  return _buildPhotoPlaceholder();
                                                },
                                              )
                                            : _buildPhotoPlaceholder();
                                      },
                                    );
                                  } catch (e) {
                                    if (kDebugMode) {
                                      print('❌ Error parsing Base64: $e');
                                    }
                                    return _buildPhotoPlaceholder();
                                  }
                                },
                              )
                            : _isPhotoUrlNetwork
                                // モバイル版: Firebase StorageなどのネットワークURL
                                ? Builder(
                                    builder: (context) {
                                      return Image.network(
                                        widget.post.photoUrl!,
                                        fit: BoxFit.cover,
                                        loadingBuilder: (context, child, loadingProgress) {
                                          if (loadingProgress == null) return child;
                                          return Center(
                                            child: CircularProgressIndicator(
                                              value: loadingProgress.expectedTotalBytes != null
                                                  ? loadingProgress.cumulativeBytesLoaded /
                                                      loadingProgress.expectedTotalBytes!
                                                  : null,
                                              color: Colors.white,
                                            ),
                                          );
                                        },
                                        errorBuilder: (context, error, stackTrace) {
                                          if (kDebugMode) {
                                            print('❌ Failed to load photo: $error');
                                            print('   URL: ${PhotoHelper.formatPhotoUrlForLog(widget.post.photoUrl)}');
                                          }
                                          // ネットワーク読み込み失敗時はアルバムアートにフォールバック
                                          return _displayAlbumArtUrl.isNotEmpty
                                              ? Image.network(
                                                  _displayAlbumArtUrl,
                                                  fit: BoxFit.cover,
                                                  errorBuilder: (context, error, stackTrace) {
                                                    return _buildPhotoPlaceholder();
                                                  },
                                                )
                                              : _buildPhotoPlaceholder();
                                        },
                                      );
                                    },
                                  )
                                // ローカルアセット（ダミー写真など）
                                : Image.asset(
                                    widget.post.photoUrl!,
                                    fit: BoxFit.cover,
                                    errorBuilder: (context, error, stackTrace) {
                                      // アセット読み込み失敗時はアルバムアートにフォールバック
                                      return _displayAlbumArtUrl.isNotEmpty
                                          ? Image.network(
                                              _displayAlbumArtUrl,
                                              fit: BoxFit.cover,
                                              errorBuilder: (context, error, stackTrace) {
                                                return _buildPhotoPlaceholder();
                                              },
                                            )
                                          : _buildPhotoPlaceholder();
                                    },
                                  ))
                        : _displayAlbumArtUrl.isNotEmpty
                            ? Image.network(
                                _displayAlbumArtUrl,
                                fit: BoxFit.cover,
                                errorBuilder: (context, error, stackTrace) {
                                  return _buildPhotoPlaceholder();
                                },
                              )
                            : _buildPhotoPlaceholder(),
                  ),
                ),

                // ユーザー情報（左上）
                Positioned(
                  left: 15,
                  top: 15,
                  child: _buildUserInfoTopLeft(theme),
                ),

                // 歌詞カード（投稿時の位置・レイアウトを再現）
                _buildLyricsCardOverlay(),

                // 再生ボタン（写真エリアの中央）
                Positioned(
                  left: (cardWidth - PostCardConstants.playButtonSize) / 2,
                  top: (photoHeight - PostCardConstants.playButtonSize) / 2,
                  child: _buildPlayButton(),
                ),

                // 下部コンテンツセクション（グラデーション背景）
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  height: contentHeight,
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          theme.gradientStart
                              .withOpacity(0.0), // 上端は透明（写真と重なる部分）
                          theme.gradientEnd, // 14px以降は不透明
                        ],
                        stops: const [
                          0.0,
                          0.0805
                        ], // 上部8.05% (14px/174px) でグラデーション完了
                      ),
                    ),
                  ),
                ),

                // 曲名とアーティスト名 - Figma: bottom area
                Positioned(
                  left: cardWidth * (12 / 363),
                  right: cardWidth * (66 / 363),
                  bottom: cardHeight * (110 / 644), //
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // タイトル（長い場合は自動スクロール）
                      MarqueeText(
                        text: widget.post.track.trackName,
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          color: theme.textColor,
                        ),
                        width: cardWidth * (285 / 363), // 利用可能な幅
                      ),
                      const SizedBox(height: 1.198),
                      Text(
                        widget.post.track.artistName,
                        style: TextStyle(
                          fontSize: 13,
                          color: theme.secondaryTextColor,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),

                // リアクション（いいね、コメント、追加）- Figma: bottom: 141px
                Positioned(
                  left: cardWidth * (12 / 363),
                  bottom: cardHeight * (80 / 644),
                  child: Row(
                    children: [
                      // いいね
                      _buildReactionButton(
                        icon: _isLikedOptimistic ??
                                (widget.currentUserId != null &&
                                    widget.post
                                        .isLikedBy(widget.currentUserId!))
                            ? Icons.favorite
                            : Icons.favorite_border,
                        color: _isLikedOptimistic ??
                                (widget.currentUserId != null &&
                                    widget.post
                                        .isLikedBy(widget.currentUserId!))
                            ? Colors.red
                            : theme.iconColor,
                        count: widget.hideReactionCounts ? null : (_likeCountOptimistic ?? widget.post.likeCount),
                        onTap: _handleLikeTap,
                        textColor: theme.iconColor,
                      ),
                      SizedBox(width: cardWidth * (15 / 363)),
                      // コメント
                      _buildCommentReactionBack(
                        count: widget.post.commentCount,
                        onTap: widget.onComment,
                        theme: theme,
                      ),
                      SizedBox(width: cardWidth * (15 / 363)),
                      // 追加（保存ボタン）
                      _buildSaveButton(theme: theme),
                    ],
                  ),
                ),

                // ユーザーアバター（右側）- Figma: right side
                Positioned(
                  right: cardWidth * (12 / 363),
                  bottom: cardHeight * (80 / 644),
                  child: _buildLikedUsersIconsFront(cardWidth, cardHeight),
                ),

                // コメントボタン - Figma: bottom: 40px
                Positioned(
                  left: cardWidth * (12 / 363),
                  right: cardWidth * (12 / 363),
                  bottom: cardHeight * (28 / 644), // 底部から28px
                  child: _buildCommentButton(theme),
                ),

                // "Provided courtesy of Apple Music" - Figma: bottom: 12px
                Positioned(
                  left: cardWidth * (17 / 363),
                  bottom: cardHeight * (9 / 644), // 底部から9px
                  child: Text(
                    'Provided courtesy of Apple Music',
                    style: TextStyle(
                      fontSize: 10,
                      color: theme.secondaryTextColor.withOpacity(0.7),
                    ),
                  ),
                ),

                // 共有ボタン（右下）- Figma: left: 314px, bottom area
                // Stackの最後に配置して最前面に表示
                Positioned(
                  right: cardWidth *
                      (13 / 363), // 363 - 314 - 36 = 13px from right
                  bottom: cardHeight * (120 / 644), // 底部からの位置
                  child: _buildShareButtonBack(theme),
                ),
              ],
            ),
          ),
        );
          },
        ),
      ),
    );
  }

  /// アルバムプレースホルダー
  Widget _buildAlbumPlaceholder() {
    return Container(
      color: Colors.grey[800],
      child: const Center(
        child: Icon(
          Icons.album,
          size: 120,
          color: Colors.white54,
        ),
      ),
    );
  }

  /// 写真プレースホルダー
  Widget _buildPhotoPlaceholder() {
    return Container(
      color: Colors.grey[900],
      child: const Center(
        child: Icon(
          Icons.photo,
          size: 120,
          color: Colors.white54,
        ),
      ),
    );
  }

  /// ユーザー情報（裏面の左上）
  Widget _buildUserInfoTopLeft(PostTheme theme) {
    // Vibeの場合は「Vibe【お題名】」または「Vibe」、それ以外は感情タグを表示
    String? displayText;

    if (widget.post.isVibe) {
      // Vibe投稿の場合
      if (widget.post.vibeTopicTitle != null && widget.post.vibeTopicTitle!.isNotEmpty) {
        displayText = '#${widget.post.vibeTopicTitle!}';
      } else {
        // vibeTopicTitleがない古い投稿の場合はVibeのみ表示
        displayText = 'Vibe';
      }
    } else if (widget.post.emotionTag != null) {
      displayText = widget.post.emotionTag;
    }
    // Vibeでも感情タグでもない場合は2行目を表示しない

    return GestureDetector(
      onTap: () {
        // ユーザープロフィール画面へ遷移
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => OtherUserProfileScreen(
              userId: widget.post.userId,
            ),
          ),
        );
      },
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.5),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // プロフィールアイコン
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.grey[400],
              ),
              child: ClipOval(
                child: ProfileImage(
                  imageUrl: widget.post.userIconUrl,
                  size: 32,
                ),
              ),
            ),
            const SizedBox(width: 8),

            // ユーザー名とハッシュタグ
            Flexible(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  // ユーザー名
                  Text(
                    widget.post.username,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                  ),

                  // ハッシュタグ/質問テキスト（感情タグの場合は非表示）
                  if (displayText != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      displayText,
                      style: const TextStyle(
                        fontSize: 8,
                        color: Colors.white,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 歌詞カードオーバーレイ（裏面の写真上）
  Widget _buildLyricsCardOverlay() {
    // 投稿時に保存されたレイアウト情報を取得
    final layoutIndex = widget.post.selectedLayoutIndex;
    final positionX = widget.post.cardPositionX;
    final positionY = widget.post.cardPositionY;
    final scale = widget.post.cardScale;
    final rotation = widget.post.cardRotation;

    // レイアウトタイプを取得
    final layoutType = LyricsCardLayout.getLayoutType(layoutIndex);

    // 歌詞テキストを決定（保存済み > 動的取得 > null）
    final lyricsText = widget.post.lyricsText ?? _fetchedLyricsText;

    // 歌詞がない場合は動的に取得を試みる
    if (lyricsText == null && !_lyricsFetchAttempted) {
      // 非同期で歌詞を取得（UIはブロックしない）
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _fetchLyricsIfNeeded();
      });
    }

    return Positioned(
      left: positionX,
      top: positionY,
      child: Transform.scale(
        scale: scale,
        alignment: Alignment.topLeft,
        child: Transform.rotate(
          angle: rotation,
          alignment: Alignment.center,
          child: LyricsCardLayout(
            layoutType: layoutType,
            track: widget.post.track,
            lyricsText: _isLyricsFetching ? '歌詞を取得中...' : lyricsText,
          ),
        ),
      ),
    );
  }

  /// プレビューURLを取得（キャッシュまたはiTunes APIから）
  Future<String?> _fetchPreviewUrl() async {
    if (_cachedPreviewUrl != null) {
      return _cachedPreviewUrl;
    }

    final result = await _itunesService.getPreviewUrlWithArt(
      trackName: widget.post.track.trackName,
      artistName: widget.post.track.artistName,
    );

    if (result != null) {
      final url = result['previewUrl'];
      setState(() {
        _cachedPreviewUrl = url;
      });
      return url;
    }

    return null;
  }

  /// 再生ボタンタップ時の処理
  Future<void> _handlePlayButtonTap(bool isPlaying, String? previewUrl) async {
    // アニメーションを開始
    _playButtonAnimationController.forward(from: 0.0);

    // 再生/一時停止処理
    if (isPlaying) {
      widget.audioService.pause();
    } else if (widget.audioService.isPaused && previewUrl != null) {
      widget.audioService.resume();
    } else {
      final urlToPlay = await _fetchPreviewUrl();
      if (urlToPlay != null && urlToPlay.isNotEmpty) {
        widget.audioService.playPreview(urlToPlay);
      }
    }
  }

  /// 再生ボタン（裏面用 - タップ時のみ表示）
  Widget _buildPlayButton() {
    return StreamBuilder<PlayerState>(
      stream: widget.audioService.playerStateStream,
      builder: (context, snapshot) {
        final previewUrl = _cachedPreviewUrl;
        final isThisTrackPlaying = previewUrl != null &&
            widget.audioService.isPlayingUrl(previewUrl);

        return GestureDetector(
          onTap: () => _handlePlayButtonTap(isThisTrackPlaying, previewUrl),
          behavior: HitTestBehavior.opaque,
          child: Container(
            width: PostCardConstants.playButtonSize,
            height: PostCardConstants.playButtonSize,
            color: Colors.transparent,
            child: AnimatedBuilder(
              animation: _playButtonAnimationController,
              builder: (context, child) {
                return Opacity(
                  opacity: _playButtonOpacityAnimation.value,
                  child: Transform.scale(
                    scale: _playButtonScaleAnimation.value,
                    child: Container(
                      width: PostCardConstants.playButtonSize,
                      height: PostCardConstants.playButtonSize,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.black.withOpacity(PostCardConstants.playButtonBackgroundOpacity),
                        border: Border.all(
                          color: Colors.white,
                          width: PostCardConstants.playButtonBorderWidth,
                        ),
                      ),
                      child: Icon(
                        isThisTrackPlaying ? Icons.pause : Icons.play_arrow,
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

  /// リアクションボタン（いいね、コメント、追加）
  Widget _buildReactionButton({
    required IconData icon,
    required Color color,
    required int? count,
    required VoidCallback? onTap,
    required Color textColor,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 24,
            color: color,
          ),
          if (count != null) ...[
            const SizedBox(width: 4),
            Text(
              count.toString(),
              style: TextStyle(
                fontSize: 14,
                color: textColor,
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// コメントリアクションボタン（裏面用・SVGアイコン使用）
  Widget _buildCommentReactionBack({
    required int count,
    required VoidCallback? onTap,
    required PostTheme theme,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SvgPicture.asset(
            'assets/icons/message_circle.svg',
            width: 24,
            height: 24,
            colorFilter: ColorFilter.mode(
              theme.iconColor,
              BlendMode.srcIn,
            ),
          ),
          if (!widget.hideReactionCounts) ...[
            const SizedBox(width: 4),
            Text(
              count.toString(),
              style: TextStyle(
                fontSize: 14,
                color: theme.iconColor,
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// コメントボタン
  Widget _buildCommentButton(PostTheme theme) {
    return GestureDetector(
      onTap: widget.onComment,
      child: Container(
        height: 43,
        decoration: BoxDecoration(
          color: theme.commentButtonColor,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            const SizedBox(width: 12),
            Text(
              'コメントする',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: theme.textColor,
              ),
            ),
            const Spacer(),
            Icon(
              Icons.send,
              size: 20,
              color: theme.textColor.withOpacity(0.7),
            ),
            const SizedBox(width: 12),
          ],
        ),
      ),
    );
  }

  /// 音楽波形
  /// 大、小、大のパターン（各投稿でpostIdをシードとして微妙に異なるパターン）
  Widget _buildWaveform(PostTheme theme) {
    // postIdをシードとしてランダムな変動を追加
    final seed = widget.post.postId.hashCode;
    final random = Random(seed);

    // Figmaの基準サイズで固定（拡大縮小しない）
    const cardWidth = 363.0;
    const contentHeight = 294.0;
    const availableWidth = cardWidth - 24; // カード内のpadding（左右12pxずつ）を引く

    // バーの幅とマージンから必要なバーの数を計算
    const barWidth = 2.5;
    const barMargin = 1.2 * 2; // 左右のマージン
    const totalBarWidth = barWidth + barMargin;
    final maxBarCount = (availableWidth / totalBarWidth).floor();
    final barCount = (maxBarCount * 2 / 3).floor(); // 棒の数を3分の2に削減

    // 利用可能な幅全体を埋めるように間隔を調整
    final totalBarWidthOnly = barCount * barWidth;
    final remainingWidth = availableWidth - totalBarWidthOnly;
    final horizontalMargin = (remainingWidth / barCount) / 2; // 片側のマージン

    return Container(
      height: contentHeight * (32 / 294),
      child: Row(
        children: List.generate(barCount, (index) {
          // 大、小、大のパターン（-π/4〜5π/4の範囲）
          // 0〜(barCount-1)のインデックスを-π/4〜5π/4の範囲にマッピング
          final normalizedIndex = index / (barCount - 1).toDouble(); // 0〜1の範囲
          final angle =
              -pi / 4 + normalizedIndex * 1.5 * pi; // -π/4〜5π/4の範囲（1.5π）

          // sin(angle)で波形を作成（-1〜1の範囲）
          // 絶対値を取って、0〜1の範囲にする
          final waveValue = sin(angle).abs();

          // 0〜1の範囲を0.3〜1.0の範囲にマッピング
          final baseHeight = 0.3 + waveValue * 0.7;

          // 5〜32の範囲にスケーリング + ランダムな変動（±3px）
          final randomVariation = (random.nextDouble() - 0.5) * 6;
          final height = 5.0 + (baseHeight * 28.0) + randomVariation;

          return Container(
            width: barWidth,
            height: height.clamp(10.0, 48.0),
            margin: EdgeInsets.symmetric(horizontal: horizontalMargin),
            decoration: BoxDecoration(
              color: theme.iconColor,
              borderRadius: BorderRadius.circular(2),
            ),
          );
        }),
      ),
    );
  }

  /// 曲名とアーティスト名（表面）
  Widget _buildTrackInfo(PostTheme theme) {
    // Positionedで配置されているため、利用可能な幅を計算
    // left: 11px, right: 66px → 利用可能幅: 363 - 11 - 66 = 286px
    const availableWidth = 286.0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        MarqueeText(
          text: widget.post.track.trackName,
          style: TextStyle(
            fontSize: 25,
            fontWeight: FontWeight.bold,
            color: theme.textColor,
          ),
          width: availableWidth,
        ),
        const SizedBox(height: 4),
        Text(
          widget.post.track.artistName,
          style: TextStyle(
            fontSize: 13,
            color: theme.textColor,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }

  /// リアクション（いいね、コメント、追加）
  Widget _buildReactions(PostTheme theme) {
    final isLiked = _isLikedOptimistic ??
        (widget.currentUserId != null &&
            widget.post.isLikedBy(widget.currentUserId!));
    final likeCount = _likeCountOptimistic ?? widget.post.likeCount;

    return Row(
      children: [
        // いいね
        _buildReactionItem(
          icon: isLiked ? Icons.favorite : Icons.favorite_border,
          count: likeCount,
          onTap: _handleLikeTap,
          isActive: isLiked,
          theme: theme,
        ),
        SizedBox(width: 15 ),

        // コメント
        _buildCommentReaction(
          count: widget.post.commentCount,
          onTap: widget.onComment,
          theme: theme,
        ),
        SizedBox(width: 15 ),

        // 追加（保存ボタン）
        _buildSaveButton(theme: theme),

        const Spacer(),

        // いいねしたユーザーのアイコン（最大2人）
        _buildLikedUsersIcons(),
      ],
    );
  }

  /// リアクションアイテム
  Widget _buildReactionItem({
    required IconData icon,
    required int count,
    VoidCallback? onTap,
    bool isActive = false,
    required PostTheme theme,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Row(
        children: [
          Icon(
            icon,
            size: 25,
            color: isActive ? Colors.red : theme.iconColor,
          ),
          if (!widget.hideReactionCounts) ...[
            const SizedBox(width: 6),
            Text(
              '$count',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: isActive ? Colors.red : theme.textColor,
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// コメントリアクションアイテム（SVGアイコン使用）
  Widget _buildCommentReaction({
    required int count,
    VoidCallback? onTap,
    required PostTheme theme,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Row(
        children: [
          SvgPicture.asset(
            'assets/icons/message_circle.svg',
            width: 25,
            height: 25,
            colorFilter: ColorFilter.mode(
              theme.iconColor,
              BlendMode.srcIn,
            ),
          ),
          if (!widget.hideReactionCounts) ...[
            const SizedBox(width: 6),
            Text(
              '$count',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: theme.textColor,
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// いいねしたユーザーのアイコン（裏面用 - 固定サイズ）
  Widget _buildLikedUsersIcons() {
    return _buildLikedUsersIconsCommon(
      iconSize: PostCardConstants.likedUserIconSize,
      margin: PostCardConstants.likedUserIconMargin,
    );
  }

  /// いいねしたユーザーのアイコン（表面用 - 相対サイズ）
  Widget _buildLikedUsersIconsFront(double cardWidth, double cardHeight) {
    return _buildLikedUsersIconsCommon(
      iconSize: cardWidth * (PostCardConstants.likedUserIconSize / PostCardConstants.cardBaseWidth),
      margin: cardWidth * (PostCardConstants.likedUserIconMargin / PostCardConstants.cardBaseWidth),
    );
  }

  /// いいねしたユーザーのアイコン（共通ロジック）
  Widget _buildLikedUsersIconsCommon({
    required double iconSize,
    required double margin,
  }) {
    // 楽観的UIを使用するか、実際のデータを使用
    final iconUrls = _likedByUserIconUrlsOptimistic ?? widget.post.likedByUserIconUrls;
    final displayCount = iconUrls.length > PostCardConstants.maxLikedUsersToShow
        ? PostCardConstants.maxLikedUsersToShow
        : iconUrls.length;

    if (displayCount == 0) {
      return const SizedBox.shrink();
    }

    return Row(
      children: List.generate(
        displayCount,
        (index) => GestureDetector(
          onTap: () {
            if (index < widget.post.likedUserIds.length) {
              _navigateToUserProfile(widget.post.likedUserIds[index]);
            }
          },
          child: Container(
            width: iconSize,
            height: iconSize,
            margin: EdgeInsets.only(left: index > 0 ? margin : 0),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.grey[400],
            ),
            child: ClipOval(
              child: ProfileImage(
                imageUrl: iconUrls[index],
                size: 25,
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// ユーザー情報（表面の下部）
  Widget _buildUserInfo(PostTheme theme) {
    return GestureDetector(
      onTap: () {
        // ユーザープロフィール画面へ遷移
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => OtherUserProfileScreen(
              userId: widget.post.userId,
            ),
          ),
        );
      },
      child: Row(
        children: [
          // ユーザーアイコン
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.grey[400],
            ),
            child: ClipOval(
              child: ProfileImage(
                imageUrl: widget.post.userIconUrl,
                size: 32,
              ),
            ),
          ),
          const SizedBox(width: 8),

          // ユーザー名
          Text(
            widget.post.username,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: theme.textColor,
            ),
          ),
        ],
      ),
    );
  }

  /// シェアボタン
  Widget _buildShareButton(PostTheme theme) {
    return Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        color: theme.iconColor.withOpacity(0.2),
        borderRadius: BorderRadius.circular(18),
      ),
      child: IconButton(
        icon: Icon(
          Icons.ios_share,
          color: theme.iconColor,
          size: 20,
        ),
        onPressed: () {
          // TODO: シェア機能の実装
          if (kDebugMode) {
            print('Share post: ${widget.post.track.trackName}');
          }
        },
        padding: EdgeInsets.zero,
      ),
    );
  }

  /// シェアボタン（裏面用）
  Widget _buildShareButtonBack(PostTheme theme) {
    return Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        color: theme.iconColor.withOpacity(0.2),
        borderRadius: BorderRadius.circular(18),
      ),
      child: IconButton(
        icon: Icon(
          Icons.ios_share,
          color: theme.iconColor,
          size: 20,
        ),
        onPressed: () {
          // TODO: シェア機能の実装
          if (kDebugMode) {
            print('Share post (back): ${widget.post.track.trackName}');
          }
        },
        padding: EdgeInsets.zero,
      ),
    );
  }

  /// 保存ボタン（表面用）
  Widget _buildSaveButton({required PostTheme theme}) {
    return GestureDetector(
      onTap: widget.onAdd,
      child: widget.isSaved
          ? _buildSavedIcon()
          : Icon(
              Icons.add_circle_outline,
              size: 24,
              color: theme.iconColor,
            ),
    );
  }

  /// 保存済みアイコン（緑色の円 + 灰色のチェックマーク）
  Widget _buildSavedIcon() {
    return Stack(
      alignment: Alignment.center,
      children: [
        // 背景：明るい緑色の塗りつぶし円
        Container(
          width: 24,
          height: 24,
          decoration: BoxDecoration(
            color: Colors.lightGreen,
            shape: BoxShape.circle,
          ),
        ),
        // 前景：灰色のチェックマーク
        Icon(
          Icons.check,
          size: 18,
          color: Colors.grey[700],
        ),
      ],
    );
  }

  /// ユーザープロフィール画面へ遷移
  void _navigateToUserProfile(String userId) {
    final currentUserId = FirebaseAuth.instance.currentUser?.uid;

    // 自分自身の場合はProfileScreenへ
    if (currentUserId == userId) {
      Navigator.pushNamed(context, '/profile');
      return;
    }

    // 他のユーザーの場合はOtherUserProfileScreenへ
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => OtherUserProfileScreen(
          userId: userId,
        ),
      ),
    );
  }
}


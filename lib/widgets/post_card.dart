import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:just_audio/just_audio.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/post_model.dart';
import '../models/post_theme.dart';
import '../screens/other_user_profile_screen.dart';
import '../services/audio_player_service.dart';
import '../services/itunes_search_service.dart';
import '../utils/color_extractor.dart';

/// 投稿カードウィジェット（表裏反転アニメーション付き）
class PostCard extends StatefulWidget {
  final PostModel post;
  final VoidCallback? onLike;
  final VoidCallback? onComment;
  final VoidCallback? onAdd;
  final String? currentUserId;
  final AudioPlayerService audioService; // 音楽再生サービス（外部から注入）
  final bool showFrontOnly; // trueの場合、表面のみ表示（反転なし）
  final VoidCallback? onCardTap; // showFrontOnly時の外部タップハンドラ
  final bool isSaved; // 保存済みかどうか

  const PostCard({
    super.key,
    required this.post,
    this.onLike,
    this.onComment,
    this.onAdd,
    this.currentUserId,
    required this.audioService, // 必須パラメータ
    this.showFrontOnly = false, // デフォルトは両面表示
    this.onCardTap, // 外部タップハンドラ（オプション）
    this.isSaved = false, // デフォルトは未保存
  });

  @override
  State<PostCard> createState() => _PostCardState();
}

class _PostCardState extends State<PostCard>
    with SingleTickerProviderStateMixin, AutomaticKeepAliveClientMixin {
  late AnimationController _flipController;
  late Animation<double> _flipAnimation;
  bool _showFront = true;

  // 楽観的UI更新用のローカル状態
  bool? _isLikedOptimistic;
  int? _likeCountOptimistic;

  // iTunes検索サービス
  final ITunesSearchService _itunesService = ITunesSearchService();

  // 動的に取得したpreview URLをキャッシュ
  String? _cachedPreviewUrl;

  // アルバムアートから抽出した色
  Color? _extractedBackgroundColor;
  Color? _extractedGradientStart;
  Color? _extractedGradientEnd;
  bool _isColorExtracting = false;

  // スクロール時にウィジェットの状態を保持
  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _flipController = AnimationController(
      duration: const Duration(milliseconds: 600),
      vsync: this,
    );
    _flipAnimation = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _flipController, curve: Curves.easeInOut),
    );

    // アルバムアートから色を抽出
    _extractColorsFromAlbumArt();
  }

  /// アルバムアートから色を抽出
  Future<void> _extractColorsFromAlbumArt() async {
    if (_isColorExtracting) return;

    setState(() {
      _isColorExtracting = true;
    });

    try {
      final imageUrl = widget.post.track.albumImageUrl;
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
            _extractedBackgroundColor = gradientEnd;
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

  @override
  void dispose() {
    _flipController.dispose();
    super.dispose();
  }

  /// Spotifyで楽曲を開く
  Future<void> _openInSpotify() async {
    final trackId = widget.post.track.trackId;
    final spotifyUrl = Uri.parse('https://open.spotify.com/track/$trackId');

    try {
      print('Opening Spotify: $spotifyUrl');
      if (await canLaunchUrl(spotifyUrl)) {
        await launchUrl(spotifyUrl, mode: LaunchMode.externalApplication);
      } else {
        print('Could not launch $spotifyUrl');
      }
    } catch (e) {
      print('Error opening Spotify: $e');
    }
  }

  /// カードをタップして裏返す
  void _flipCard() async {
    // 表面のみ表示モードの場合は外部ハンドラを呼ぶ
    if (widget.showFrontOnly) {
      widget.onCardTap?.call();
      return;
    }

    if (_showFront) {
      _flipController.forward();
      print('=== Flipping to back ===');
      print(
          'Track: ${widget.post.track.trackName} - ${widget.post.track.artistName}');

      // キャッシュまたは動的に取得したpreview URLを使用
      String? previewUrl = _cachedPreviewUrl;

      // キャッシュがない場合、iTunes APIから取得
      if (previewUrl == null) {
        print('🍎 Fetching preview URL from iTunes...');
        previewUrl = await _itunesService.getPreviewUrl(
          trackName: widget.post.track.trackName,
          artistName: widget.post.track.artistName,
        );

        if (previewUrl != null) {
          _cachedPreviewUrl = previewUrl; // キャッシュに保存
          print('✅ iTunes preview URL obtained and cached');
        } else {
          print('❌ No preview URL found from iTunes');
        }
      } else {
        print('📦 Using cached preview URL');
      }

      // プレビューURLがあれば再生
      if (previewUrl != null && previewUrl.isNotEmpty) {
        print('▶️  Starting playback...');
        widget.audioService.playPreview(previewUrl);
      } else {
        print('⚠️  No preview URL available');
      }
    } else {
      _flipController.reverse();
      print('=== Flipping to front - stopping playback ===');
      widget.audioService.stop();
    }
    setState(() {
      _showFront = !_showFront;
    });
  }

  /// いいねボタンが押された時の処理（楽観的UI更新）
  void _handleLikeTap() {
    if (widget.onLike != null) {
      setState(() {
        final currentIsLiked = _isLikedOptimistic ??
            (widget.currentUserId != null &&
                widget.post.isLikedBy(widget.currentUserId!));
        final currentLikeCount = _likeCountOptimistic ?? widget.post.likeCount;

        _isLikedOptimistic = !currentIsLiked;
        _likeCountOptimistic =
            currentIsLiked ? currentLikeCount - 1 : currentLikeCount + 1;
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
    } else if (_isLikedOptimistic != null || _likeCountOptimistic != null) {
      final actualIsLiked = widget.currentUserId != null &&
          widget.post.isLikedBy(widget.currentUserId!);
      final actualLikeCount = widget.post.likeCount;

      if (_isLikedOptimistic == actualIsLiked &&
          _likeCountOptimistic == actualLikeCount) {
        _isLikedOptimistic = null;
        _likeCountOptimistic = null;
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
      // 背景色の明度に応じてアイコンとテキストの色を決定
      final HSLColor hsl = HSLColor.fromColor(_extractedGradientEnd!);
      final bool isDark = hsl.lightness < 0.5;

      // コメントボタンの色は10%明るくする
      final Color commentButtonColor = hsl
          .withLightness(
            (hsl.lightness * 1.1).clamp(0.0, 1.0),
          )
          .toColor();

      return PostTheme(
        gradientStart: _extractedGradientStart!,
        gradientEnd: _extractedGradientEnd!,
        commentButtonColor: commentButtonColor,
        textColor: isDark ? Colors.white : Colors.black,
        iconColor: isDark ? Colors.white : Colors.black,
        secondaryTextColor: isDark
            ? Colors.white.withOpacity(0.8)
            : Colors.black.withOpacity(0.8),
      );
    }
    // デフォルトのテーマを使用
    return widget.post.theme;
  }

  /// カード表面（アルバムカバー全表示）
  Widget _buildFront() {
    final theme = _getDynamicTheme();
    // Figmaの基準サイズで固定（拡大縮小しない）
    const cardWidth = 363.0;
    const albumSize = 363.0; // アルバムカバーは正方形
    const contentHeight = 294.0; // タイトルエリア
    const cardHeight = 644.0; // 全体の高さ（13pxのオーバーラップ込み）

    return GestureDetector(
      onTap: _flipCard,
      child: Container(
        width: cardWidth,
        height: cardHeight,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          color: theme.gradientEnd,
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(18),
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
                  child: widget.post.track.albumImageUrl.isNotEmpty
                      ? Image.network(
                          widget.post.track.albumImageUrl,
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
                      child: _buildShareButton(),
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
      ),
    );
  }

  /// カード裏面（写真+アルバムカード+下部セクション）
  Widget _buildBack() {
    final theme = _getDynamicTheme();
    // Figmaの基準サイズで固定（拡大縮小しない）
    const cardWidth = 363.0;
    const photoHeight = 484.0; // 写真エリア
    const contentHeight = 174.0; // タイトルエリア
    const cardHeight = 644.0; // 全体の高さ（14pxのオーバーラップ込み）

    return Transform(
      alignment: Alignment.center,
      transform: Matrix4.identity()..rotateY(pi),
      child: GestureDetector(
        onTap: _flipCard,
        child: Container(
          width: cardWidth,
          height: cardHeight,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            color: theme.gradientEnd,
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(18),
            child: Stack(
              children: [
                // 写真エリア（上部）
                Positioned(
                  left: 0,
                  top: 0,
                  child: Container(
                    width: cardWidth,
                    height: photoHeight,
                    child: widget.post.track.albumImageUrl.isNotEmpty
                        ? Image.network(
                            widget.post.track.albumImageUrl,
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

                // 小さなアルバムカード（写真の上部中央）
                Positioned(
                  left: cardWidth * 0.25,
                  top: 20,
                  child: _buildMiniAlbumCard(),
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
                        count: _likeCountOptimistic ?? widget.post.likeCount,
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
                  child: Row(
                    children: [
                      // いいねした人のアバター（3人分）
                      Container(
                        width: cardWidth * (25 / 363),
                        height: cardHeight * (25 / 644),
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.grey,
                        ),
                      ),
                      SizedBox(width: cardWidth * (1 / 363)),
                      Container(
                        width: cardWidth * (25 / 363),
                        height: cardHeight * (25 / 644),
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.grey,
                        ),
                      ),
                      SizedBox(width: cardWidth * (1 / 363)),
                      Container(
                        width: cardWidth * (25 / 363),
                        height: cardHeight * (25 / 644),
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.grey,
                        ),
                      ),
                    ],
                  ),
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
                  child: _buildShareButtonBack(),
                ),
              ],
            ),
          ),
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

  /// 歌詞カード（裏面の中央オーバーレイ）
  Widget _buildLyricsCard() {
    return Column(
      children: [
        // 歌詞情報
        Container(
          width: 240.153,
          height: 73.893,
          decoration: BoxDecoration(
            color: const Color(0x4A000000), // rgba(0,0,0,0.29)
          ),
          child: const Padding(
            padding: EdgeInsets.symmetric(horizontal: 14, vertical: 18),
            child: Text(
              '笑ってもっとbaby\nむじゃきにon my mind',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.white,
                height: 1.39,
              ),
            ),
          ),
        ),
        // トラック情報
        Container(
          width: 240.153,
          height: 64.656,
          decoration: BoxDecoration(
            color: const Color(0x85000000), // rgba(0,0,0,0.52) opacity:80
          ),
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Row(
              children: [
                // ミニアルバムカバー
                Container(
                  width: 50,
                  height: 50,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(3),
                    color: Colors.grey[800],
                  ),
                  child: widget.post.track.albumImageUrl.isNotEmpty
                      ? ClipRRect(
                          borderRadius: BorderRadius.circular(3),
                          child: Image.network(
                            widget.post.track.albumImageUrl,
                            fit: BoxFit.cover,
                            errorBuilder: (context, error, stackTrace) {
                              return const Icon(Icons.album,
                                  color: Colors.white54, size: 30);
                            },
                          ),
                        )
                      : const Icon(Icons.album,
                          color: Colors.white54, size: 30),
                ),
                const SizedBox(width: 7),
                // トラック名とアーティスト名
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        widget.post.track.trackName,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        widget.post.track.artistName,
                        style: const TextStyle(
                          fontSize: 9,
                          color: Colors.white,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  /// ユーザー情報（裏面の左上）
  Widget _buildUserInfoTopLeft(PostTheme theme) {
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // ユーザー名
          Text(
            widget.post.username,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: Colors.white,
              shadows: [
                Shadow(
                  offset: Offset(0, 1),
                  blurRadius: 3,
                  color: Colors.black54,
                ),
              ],
            ),
          ),
          const SizedBox(height: 2),

          // ハッシュタグ/質問テキスト
          const Text(
            '#ドライブの時に聴きたい曲は？',
            style: TextStyle(
              fontSize: 12,
              color: Colors.white,
              shadows: [
                Shadow(
                  offset: Offset(0, 1),
                  blurRadius: 3,
                  color: Colors.black54,
                ),
              ],
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  /// 小さなアルバムカード（裏面の写真上部）
  Widget _buildMiniAlbumCard() {
    return Container(
      width: 200,
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: const Color(0xB3000000), // 半透明の黒背景
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          // アルバムカバー
          Container(
            width: 50,
            height: 50,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(6),
              color: Colors.grey[800],
            ),
            child: widget.post.track.albumImageUrl.isNotEmpty
                ? ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: Image.network(
                      widget.post.track.albumImageUrl,
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) {
                        return const Icon(Icons.album,
                            color: Colors.white54, size: 30);
                      },
                    ),
                  )
                : const Icon(Icons.album, color: Colors.white54, size: 30),
          ),
          const SizedBox(width: 10),

          // トラック情報
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  widget.post.track.trackName,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  widget.post.track.artistName,
                  style: const TextStyle(
                    fontSize: 11,
                    color: Colors.white70,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),

          // 再生/一時停止ボタン
          StreamBuilder<PlayerState>(
            stream: widget.audioService.playerStateStream,
            builder: (context, snapshot) {
              // キャッシュされたpreview URLを使用
              final previewUrl = _cachedPreviewUrl;
              final isThisTrackPlaying = previewUrl != null &&
                  widget.audioService.isPlayingUrl(previewUrl);
              final isPaused = widget.audioService.isPaused;

              return IconButton(
                icon: Icon(
                  isThisTrackPlaying
                      ? Icons.pause_circle_filled
                      : Icons.play_circle_filled,
                  color: isThisTrackPlaying ? Colors.greenAccent : Colors.white,
                  size: 32,
                ),
                onPressed: () async {
                  if (isThisTrackPlaying) {
                    // 再生中の場合は一時停止
                    widget.audioService.pause();
                  } else if (isPaused && previewUrl != null) {
                    // 一時停止中の場合は再開
                    widget.audioService.resume();
                  } else {
                    // 停止中の場合は再生開始
                    String? urlToPlay = previewUrl;

                    // preview URLがまだ取得されていない場合は取得
                    if (urlToPlay == null) {
                      print('🍎 Fetching preview URL for playback...');
                      urlToPlay = await _itunesService.getPreviewUrl(
                        trackName: widget.post.track.trackName,
                        artistName: widget.post.track.artistName,
                      );

                      if (urlToPlay != null) {
                        setState(() {
                          _cachedPreviewUrl = urlToPlay;
                        });
                        print('✅ Preview URL obtained and cached');
                      } else {
                        print('❌ Failed to obtain preview URL');
                        return;
                      }
                    }

                    widget.audioService.playPreview(urlToPlay);
                  }
                },
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              );
            },
          ),
        ],
      ),
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
          const SizedBox(width: 4),
          Text(
            count.toString(),
            style: TextStyle(
              fontSize: 14,
              color: theme.iconColor,
            ),
          ),
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
    const cardHeight = 644.0;
    const contentHeight = 294.0;
    const availableWidth = cardWidth - 24; // カード内のpadding（左右12pxずつ）を引く

    // バーの幅とマージンから必要なバーの数を計算
    const barWidth = 2.5;
    const barMargin = 1.2 * 2; // 左右のマージン
    const totalBarWidth = barWidth + barMargin;
    final barCount = (availableWidth / totalBarWidth).floor();

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
            margin: const EdgeInsets.symmetric(horizontal: 1.2),
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

  /// 曲名とアーティスト名（裏面・小さめ）
  Widget _buildTrackInfoBack(PostTheme theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          widget.post.track.trackName,
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.bold,
            color: theme.textColor,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: 2),
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
    // Figmaの基準サイズで固定（拡大縮小しない）
    const cardWidth = 363.0;
    const cardHeight = 644.0;
    const contentHeight = 294.0;

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
        SizedBox(width: cardWidth * (15 / 363)),

        // コメント
        _buildCommentReaction(
          count: widget.post.commentCount,
          onTap: widget.onComment,
          theme: theme,
        ),
        SizedBox(width: cardWidth * (15 / 363)),

        // 追加（保存ボタン）
        _buildSaveButtonBack(theme: theme),

        const Spacer(),

        // いいねした人のアイコン（最大3人）
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
      ),
    );
  }

  /// いいねした人のアイコン（最大3人表示）
  Widget _buildLikedUsersIcons() {
    return Row(
      children: List.generate(
        3,
        (index) => Container(
          width: 25,
          height: 25,
          margin: EdgeInsets.only(left: index > 0 ? 4 : 0),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.grey[400],
          ),
          child: const Icon(
            Icons.person,
            size: 14,
            color: Colors.white,
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
            child: widget.post.userIconUrl != null &&
                    widget.post.userIconUrl!.isNotEmpty
                ? ClipOval(
                    child: Image.network(
                      widget.post.userIconUrl!,
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) {
                        return const Icon(Icons.person,
                            size: 20, color: Colors.white);
                      },
                    ),
                  )
                : const Icon(Icons.person, size: 20, color: Colors.white),
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
  Widget _buildShareButton() {
    return Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.2),
        borderRadius: BorderRadius.circular(18),
      ),
      child: IconButton(
        icon: const Icon(
          Icons.ios_share,
          color: Colors.white,
          size: 20,
        ),
        onPressed: () {
          // TODO: シェア機能の実装
          print('Share post: ${widget.post.track.trackName}');
        },
        padding: EdgeInsets.zero,
      ),
    );
  }

  /// シェアボタン（裏面用）
  Widget _buildShareButtonBack() {
    return Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.2),
        borderRadius: BorderRadius.circular(18),
      ),
      child: IconButton(
        icon: const Icon(
          Icons.ios_share,
          color: Colors.white,
          size: 20,
        ),
        onPressed: () {
          // TODO: シェア機能の実装
          print('Share post (back): ${widget.post.track.trackName}');
        },
        padding: EdgeInsets.zero,
      ),
    );
  }

  /// ユーザー情報（裏面・下部左）
  Widget _buildUserInfoBottomLeft(PostTheme theme) {
    return Row(
      children: [
        // プロフィール画像
        Container(
          width: 32,
          height: 32,
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.grey,
          ),
          child: widget.post.userIconUrl != null &&
                  widget.post.userIconUrl!.isNotEmpty
              ? ClipOval(
                  child: Image.network(
                    widget.post.userIconUrl!,
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) {
                      return const Icon(Icons.person,
                          size: 20, color: Colors.white);
                    },
                  ),
                )
              : const Icon(Icons.person, size: 20, color: Colors.white),
        ),
        const SizedBox(width: 8),
        // ユーザー名とハッシュタグ
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // ハッシュタグ
            Text(
              '#盛り上がる一曲は？',
              style: const TextStyle(
                fontSize: 8,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 2),
            // ユーザー名
            Text(
              widget.post.username,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Colors.white,
              ),
            ),
          ],
        ),
      ],
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

  /// 保存ボタン（裏面用）
  Widget _buildSaveButtonBack({required PostTheme theme}) {
    final cardWidth = MediaQuery.of(context).size.width - 30;
    final contentHeight = cardWidth * (294 / 363);

    return GestureDetector(
      onTap: widget.onAdd,
      child: SizedBox(
        width: cardWidth * (25 / 363),
        height: contentHeight * (25 / 294),
        child: widget.isSaved
            ? _buildSavedIcon()
            : Icon(
                Icons.add_circle_outline,
                size: 23,
                color: theme.iconColor,
              ),
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
}

/// テキストが長い場合に横スクロールするマーキーウィジェット
class MarqueeText extends StatefulWidget {
  final String text;
  final TextStyle? style;
  final double width;

  const MarqueeText({
    super.key,
    required this.text,
    this.style,
    required this.width,
  });

  @override
  State<MarqueeText> createState() => _MarqueeTextState();
}

class _MarqueeTextState extends State<MarqueeText> {
  late ScrollController _scrollController;
  bool _needsScrolling = false;
  double _textWidth = 0;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkAndStartScrolling();
    });
  }

  void _checkAndStartScrolling() async {
    // テキストの幅を計算
    final textPainter = TextPainter(
      text: TextSpan(text: widget.text, style: widget.style),
      maxLines: 1,
      textDirection: TextDirection.ltr,
    )..layout();

    _textWidth = textPainter.width;

    if (_textWidth > widget.width) {
      setState(() {
        _needsScrolling = true;
      });

      // スクロールアニメーションを開始
      await Future.delayed(const Duration(seconds: 1));
      if (!mounted) return;

      while (mounted) {
        // 右から左へスクロール
        await _scrollController.animateTo(
          _textWidth - widget.width + 20,
          duration: const Duration(seconds: 5),
          curve: Curves.linear,
        );

        // 少し待つ
        await Future.delayed(const Duration(seconds: 1));
        if (!mounted) return;

        // 左端に戻る
        await _scrollController.animateTo(
          0,
          duration: const Duration(seconds: 5),
          curve: Curves.linear,
        );

        // 少し待つ
        await Future.delayed(const Duration(seconds: 1));
        if (!mounted) return;
      }
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_needsScrolling) {
      return SizedBox(
        width: widget.width,
        child: Text(
          widget.text,
          style: widget.style,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      );
    }

    return SizedBox(
      width: widget.width,
      child: SingleChildScrollView(
        controller: _scrollController,
        scrollDirection: Axis.horizontal,
        physics: const NeverScrollableScrollPhysics(),
        child: Text(
          widget.text,
          style: widget.style,
          maxLines: 1,
        ),
      ),
    );
  }
}

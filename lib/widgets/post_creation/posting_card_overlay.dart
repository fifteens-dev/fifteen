import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../../models/post_model.dart';
import '../../models/post_theme.dart';
import '../../services/audio_player_service.dart';
import '../../services/lyrics_service.dart';
import '../../services/posting_state.dart';
import '../../utils/color_extractor.dart';
import '../../widgets/post_card.dart';
import '../../widgets/post_card_back_info.dart';
import '../../widgets/post_creation/lyrics_card_layouts.dart';
import '../../widgets/post_creation/post_card_back_view.dart';
import '../../widgets/shared/user_info_badge.dart';

/// 投稿アップロード中にホーム画面の上に表示するオーバーレイ。
///
/// - 半透明黒（70%）の全画面ディム
/// - 上部：「Vibeに楽曲を追加しています...」バナー
/// - 中央：最終プレビュー画面と同じカード（324×576）が2秒ごとに表裏を繰り返す
class PostingCardOverlay extends StatefulWidget {
  const PostingCardOverlay({super.key});

  @override
  State<PostingCardOverlay> createState() => _PostingCardOverlayState();
}

class _PostingCardOverlayState extends State<PostingCardOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _flipController;
  late final Animation<double> _flipAnimation;
  Timer? _flipTimer;
  bool _showFront = false; // false = 裏面から開始（プレビュー画面と同じ）

  final AudioPlayerService _audioService = AudioPlayerService();

  @override
  void initState() {
    super.initState();

    // プレビュー画面と同じく裏面から開始（value: 1.0 = 裏面）
    _flipController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
      value: 1.0,
    );
    _flipAnimation = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _flipController, curve: Curves.easeInOut),
    );

    // 2秒ごとに自動フリップ
    _flipTimer = Timer.periodic(const Duration(seconds: 2), (_) => _flip());

    // 裏面に音楽を自動再生
    WidgetsBinding.instance.addPostFrameCallback((_) => _playMusic());
  }

  void _flip() {
    if (!mounted) return;
    setState(() => _showFront = !_showFront);
    if (_showFront) {
      _flipController.reverse();
    } else {
      _flipController.forward();
      _playMusic();
    }
  }

  Future<void> _playMusic() async {
    final data = PostingState.instance.cardData;
    if (data == null) return;
    final url = data.previewUrl ?? data.track.previewUrl;
    if (url == null || url.isEmpty) return;
    try {
      await _audioService.playPreview(
        url,
        startFrom: Duration(milliseconds: data.audioStartMs),
        durationSeconds: data.audioDurationSec,
      );
    } catch (_) {}
  }

  @override
  void dispose() {
    _flipTimer?.cancel();
    _flipController.dispose();
    _audioService.stopIfOwner(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final data = PostingState.instance.cardData;
    if (data == null) return const SizedBox.shrink();

    final topPadding = MediaQuery.of(context).padding.top;

    return Stack(
      fit: StackFit.expand,
      children: [
        // 半透明黒ディム（タップ吸収）
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () {},
          child: const ColoredBox(color: Color(0xB3000000)),
        ),

        // 上部テキスト（Vibe / 通常で文言を切り替え）
        Positioned(
          top: topPadding + 48,
          left: 0,
          right: 0,
          child: Text(
            data.isVibe ? 'Vibeに楽曲を追加しています...' : '楽曲を追加しています...',
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Color(0xFFFFFFFF),
              fontSize: 16,
              fontWeight: FontWeight.w600,
              decoration: TextDecoration.none,
            ),
          ),
        ),

        // 中央カード（324×576にスケールダウン）
        Center(
          child: SizedBox(
            width: 324,
            height: 576,
            child: FittedBox(
              fit: BoxFit.fill,
              child: SizedBox(
                width: 363,
                height: 645,
                child: AnimatedBuilder(
                  animation: _flipAnimation,
                  builder: (context, _) {
                    final angle = _flipAnimation.value * pi;
                    final isFront = angle < pi / 2;
                    return Transform(
                      alignment: Alignment.center,
                      transform: Matrix4.identity()
                        ..setEntry(3, 2, 0.001)
                        ..rotateY(angle),
                      child: isFront
                          ? _buildFrontCard(data)
                          : _buildBackCard(data),
                    );
                  },
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// 表面：PostCard（プレビュー画面の表面と同じ）
  Widget _buildFrontCard(PostingCardData data) {
    final now = DateTime.now();
    final post = PostModel(
      postId: '__posting_preview__',
      userId: '__preview__',
      username: data.username.isNotEmpty ? data.username : 'ユーザー',
      userIconUrl: data.userIconUrl,
      track: data.track,
      likeCount: 3,
      commentCount: 3,
      createdAt: now,
      updatedAt: now,
      adlTeamId: data.adlTeamId,
    );
    return PostCard(
      post: post,
      audioService: _audioService,
      showFrontOnly: true,
      hideReactionCounts: true,
      preExtractedGradientStart: data.gradientStart,
      preExtractedGradientEnd: data.gradientEnd,
      externalPreviewUrl: data.previewUrl,
    );
  }

  /// 裏面：プレビュー画面の _buildBackCard() と同じ構造
  Widget _buildBackCard(PostingCardData data) {
    return Transform(
      alignment: Alignment.center,
      transform: Matrix4.identity()..rotateY(pi),
      child: Container(
        width: 363,
        height: 645,
        decoration: BoxDecoration(
          color: const Color(0xFF121212),
          borderRadius: BorderRadius.circular(18),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(18),
          child: Stack(
            children: [
              // 写真レイヤー + 歌詞カード
              Positioned.fill(child: _buildPhotoSection(data)),

              // 楽曲情報（下部）
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: _buildInfoSection(data),
              ),

              // ユーザー情報（左上）
              Positioned(
                left: 23,
                top: 18,
                child: UserInfoBadge(
                  username: data.username.isNotEmpty ? data.username : 'ユーザー',
                  iconUrl: data.userIconUrl,
                  hashtagText: data.isVibe && data.vibeTopicTitle != null
                      ? '#${data.vibeTopicTitle}'
                      : null,
                  showBackground: false,
                  teamId: data.adlTeamId,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 写真エリア（歌詞カード込み）
  Widget _buildPhotoSection(PostingCardData data) {
    const frameH = 645.0;

    double? displayW, displayH;
    if (data.imageNaturalSize != null) {
      final natW = data.imageNaturalSize!.width;
      final natH = data.imageNaturalSize!.height;
      if (natW > 0 && natH > 0) {
        final baseScale = frameH / natH;
        displayW = natW * baseScale;
        displayH = natH * baseScale;
      }
    }

    return Stack(
      clipBehavior: Clip.hardEdge,
      children: [
        if (data.selectedImage != null && displayW != null)
          Positioned(
            left: data.imageOffset.dx,
            top: data.imageOffset.dy,
            child: Transform.scale(
              scale: data.imageScale,
              alignment: Alignment.topLeft,
              child: SizedBox(
                width: displayW,
                height: displayH!,
                child: kIsWeb
                    ? Image.network(data.selectedImage!.path, fit: BoxFit.fill)
                    : Image.file(File(data.selectedImage!.path), fit: BoxFit.fill),
              ),
            ),
          )
        else if (data.selectedImage != null)
          Positioned.fill(
            child: kIsWeb
                ? Image.network(data.selectedImage!.path, fit: BoxFit.cover)
                : Image.file(File(data.selectedImage!.path), fit: BoxFit.cover),
          )
        else
          const Positioned.fill(
            child: ColoredBox(color: Color(0xFF121212)),
          ),

        // 歌詞カード
        _buildLyricsCard(data),
      ],
    );
  }

  /// 歌詞カード（位置・スケール・回転はプレビュー時の値をそのまま使用）
  Widget _buildLyricsCard(PostingCardData data) {
    final layoutType = LyricsCardLayout.getLayoutType(data.selectedLayoutIndex);
    final cardSize = PostCardBackView.cardSizeForLayout(data.selectedLayoutIndex);
    // center → top-left（PostEditState.cardPositionForSize と同じ計算）
    final cardPos = Offset(
      data.cardCenter.dx - cardSize.width * data.cardScale / 2,
      data.cardCenter.dy - cardSize.height * data.cardScale / 2,
    );

    String? lyricsText;
    if (data.lyricsData != null) {
      lyricsText = LyricsService().truncateLyrics(
        data.lyricsData!.plainLyrics,
        maxLines: 4,
      );
    }

    return Positioned(
      left: cardPos.dx,
      top: cardPos.dy,
      child: Transform.scale(
        scale: data.cardScale,
        alignment: Alignment.topLeft,
        child: Transform.rotate(
          angle: data.cardRotation,
          alignment: Alignment.center,
          child: LyricsCardLayout(
            layoutType: layoutType,
            track: data.track,
            lyricsText: lyricsText,
            albumArtOpacity: data.albumArtOpacity,
          ),
        ),
      ),
    );
  }

  /// 楽曲情報セクション（下部・プレビュー画面と同じ）
  Widget _buildInfoSection(PostingCardData data) {
    PostTheme theme = PostTheme.defaultTheme;
    if (data.gradientStart != null && data.gradientEnd != null) {
      theme = ColorExtractor.createThemeFromColors(
        data.gradientStart!,
        data.gradientEnd!,
      );
    }
    return PostCardBackInfo(
      track: data.track,
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

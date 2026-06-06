import 'dart:io';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../../models/track_model.dart';
import '../../models/post_edit_state.dart';
import '../../services/lyrics_service.dart';
import '../../utils/color_extractor.dart';
import '../../models/post_theme.dart';
import '../post_card_back_info.dart';
import '../post_creation/lyrics_card_layouts.dart';
import '../shared/user_info_badge.dart';

/// 投稿カード裏面の共通ウィジェット
/// PostCardEditScreen（編集中）と PostFinalPreviewScreen（最終確認）で共用する。
///
/// カード寸法（固定）:
///   全体: 363 × 645（写真がカード全体を覆う）
class PostCardBackView extends StatefulWidget {
  static const double cardWidth = 363.0;
  static const double photoHeight = 645.0; // 写真はカード全体の高さ
  static const double cardHeight = 645.0;

  final TrackModel track;
  final XFile? selectedImage;
  final Offset imageOffset;
  final double imageScale;
  final Size? imageNaturalSize;
  final PostEditState editState;
  final LyricsData? lyricsData;
  final String username;
  final String? userIconUrl;
  final bool isVibe;
  final String? vibeTopicTitle;
  final String? adlTeamId;

  /// 事前抽出済みのグラデーション色（提供されていれば再抽出しない）
  final Color? preExtractedGradientStart;
  final Color? preExtractedGradientEnd;

  /// false のとき歌詞カードを非表示にする（アニメーション中など）
  final bool showLyricsCard;

  /// false のときユーザー情報バッジを非表示にする
  final bool showUserBadge;

  /// 写真エリア内で歌詞カードの「下」に置くウィジェット群
  /// ジェスチャー検出レイヤー（PostCardEditScreen）はここに渡す
  final List<Widget> photoOverlaysBefore;

  /// 写真エリア内で歌詞カードの「上」に置くウィジェット群
  /// 再生ボタン（PostFinalPreviewScreen）やガイドライン（PostCardEditScreen）はここに渡す
  final List<Widget> photoOverlaysAfter;

  const PostCardBackView({
    super.key,
    required this.track,
    this.selectedImage,
    this.imageOffset = Offset.zero,
    this.imageScale = 1.0,
    this.imageNaturalSize,
    required this.editState,
    this.lyricsData,
    required this.username,
    this.userIconUrl,
    this.isVibe = false,
    this.vibeTopicTitle,
    this.adlTeamId,
    this.preExtractedGradientStart,
    this.preExtractedGradientEnd,
    this.showLyricsCard = true,
    this.showUserBadge = true,
    this.photoOverlaysBefore = const [],
    this.photoOverlaysAfter = const [],
  });

  /// レイアウトインデックスに対応するカードサイズ
  static Size cardSizeForLayout(int layoutIndex) {
    switch (layoutIndex) {
      case 0: return const Size(196, 126);
      case 1: return const Size(105, 147);
      case 2: return const Size(172, 42);
      case 3: return const Size(140, 152);
      case 4: return const Size(130, 61);
      default: return const Size(196, 126);
    }
  }

  @override
  State<PostCardBackView> createState() => _PostCardBackViewState();
}

class _PostCardBackViewState extends State<PostCardBackView> {
  Color? _gradientStart;
  Color? _gradientEnd;

  @override
  void initState() {
    super.initState();
    if (widget.preExtractedGradientStart != null &&
        widget.preExtractedGradientEnd != null) {
      _gradientStart = widget.preExtractedGradientStart;
      _gradientEnd = widget.preExtractedGradientEnd;
    } else {
      _extractColors();
    }
  }

  @override
  void didUpdateWidget(PostCardBackView old) {
    super.didUpdateWidget(old);
    // 事前抽出色が新たに渡された場合は反映する
    if (widget.preExtractedGradientStart != null &&
        widget.preExtractedGradientStart != old.preExtractedGradientStart) {
      setState(() {
        _gradientStart = widget.preExtractedGradientStart;
        _gradientEnd = widget.preExtractedGradientEnd;
      });
    }
  }

  Future<void> _extractColors() async {
    try {
      final imageUrl = widget.track.albumImageUrl;
      if (imageUrl.isNotEmpty) {
        final colors = await ColorExtractor.extractGradientColors(imageUrl);
        if (mounted) {
          setState(() {
            _gradientStart = colors.$1;
            _gradientEnd = colors.$2;
          });
        }
      }
    } catch (_) {}
  }

  PostTheme get _theme {
    if (_gradientStart != null && _gradientEnd != null) {
      return ColorExtractor.createThemeFromColors(_gradientStart!, _gradientEnd!);
    }
    return PostTheme.defaultTheme;
  }

  @override
  Widget build(BuildContext context) {
    const cardW = PostCardBackView.cardWidth;
    const cardH = PostCardBackView.cardHeight;

    // 写真の表示サイズを事前計算（高さ基準でフィット）
    double? displayW, displayH;
    if (widget.imageNaturalSize != null) {
      final natW = widget.imageNaturalSize!.width;
      final natH = widget.imageNaturalSize!.height;
      if (natW > 0 && natH > 0) {
        final baseScale = cardH / natH;
        displayW = natW * baseScale;
        displayH = natH * baseScale;
      }
    }

    return SizedBox(
      width: cardW,
      height: cardH,
      child: Container(
        decoration: const BoxDecoration(
          color: Color(0xFF121212),
          borderRadius: BorderRadius.all(Radius.circular(18)),
        ),
        child: ClipRRect(
          borderRadius: const BorderRadius.all(Radius.circular(18)),
          child: Stack(
            children: [
              // 写真（カード全体）
              Positioned.fill(
                child: _buildPhotoArea(displayW, displayH),
              ),
              // 情報オーバーレイ（下部174px）
              Positioned(
                left: 0, right: 0, bottom: 0,
                child: PostCardBackInfo(
                  track: widget.track,
                  theme: _theme,
                  showCounts: false,
                  onLike: () {},
                  onComment: () {},
                  onAdd: () {},
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPhotoArea(double? displayW, double? displayH) {
    String? lyricsText;
    if (widget.lyricsData != null) {
      final lyricsService = LyricsService();
      lyricsText = lyricsService.truncateLyrics(
        widget.lyricsData!.plainLyrics,
        maxLines: 4,
      );
    }

    return Stack(
        clipBehavior: Clip.hardEdge,
        children: [
          // ① 写真背景
          if (widget.selectedImage != null && displayW != null)
            Positioned(
              left: widget.imageOffset.dx,
              top: widget.imageOffset.dy,
              child: Transform.scale(
                scale: widget.imageScale,
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
            Positioned.fill(child: Container(color: const Color(0xFF121212))),

          // ② 歌詞カードより下のオーバーレイ（ジェスチャー検出レイヤー等）
          ...widget.photoOverlaysBefore,

          // ③ 歌詞カード（editState をリッスンして位置/レイアウトを反映）
          if (widget.showLyricsCard) ListenableBuilder(
            listenable: widget.editState,
            builder: (context, _) {
              final layoutType = LyricsCardLayout.getLayoutType(
                  widget.editState.selectedLayoutIndex);
              final cardSize = PostCardBackView.cardSizeForLayout(
                  widget.editState.selectedLayoutIndex);
              final cardPos = widget.editState.cardPositionForSize(cardSize);

              return Stack(
                clipBehavior: Clip.none,
                children: [
                  Positioned(
                    left: cardPos.dx,
                    top: cardPos.dy,
                    child: Transform.scale(
                      scale: widget.editState.cardScale,
                      alignment: Alignment.topLeft,
                      child: Transform.rotate(
                        angle: widget.editState.cardRotation,
                        alignment: Alignment.center,
                        child: LyricsCardLayout(
                          layoutType: layoutType,
                          track: widget.track,
                          lyricsText: lyricsText,
                        ),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),

          // ④ 歌詞カードより上のオーバーレイ（再生ボタン、スナップガイドライン等）
          ...widget.photoOverlaysAfter,

          // ⑤ ユーザー情報バッジ（常に最前面）
          if (widget.showUserBadge)
            Positioned(
              top: 18,
              left: 23,
              child: UserInfoBadge(
                username: widget.username.isNotEmpty ? widget.username : 'ユーザー',
                iconUrl: widget.userIconUrl,
                hashtagText: widget.isVibe && widget.vibeTopicTitle != null
                    ? '#${widget.vibeTopicTitle}'
                    : null,
                showBackground: false,
                teamId: widget.adlTeamId,
              ),
            ),
        ],
    );
  }
}

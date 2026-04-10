import 'dart:convert';
import 'dart:math';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import '../../models/post_model.dart';
import '../../models/post_theme.dart';
import '../../models/track_model.dart';
import '../../utils/photo_helper.dart';
import '../post_creation/lyrics_card_layouts.dart';

/// メディア表示関連のウィジェット群

/// アルバムアート表示
class AlbumArtImage extends StatelessWidget {
  final String imageUrl;
  final double size;

  const AlbumArtImage({
    super.key,
    required this.imageUrl,
    required this.size,
  });

  @override
  Widget build(BuildContext context) {
    if (imageUrl.isEmpty) {
      return _buildPlaceholder();
    }

    return CachedNetworkImage(
      imageUrl: imageUrl,
      width: size,
      height: size,
      fit: BoxFit.cover,
      errorWidget: (context, url, error) => _buildPlaceholder(),
    );
  }

  Widget _buildPlaceholder() {
    return Container(
      width: size,
      height: size,
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
}

/// 投稿写真表示（ネットワーク、Base64、ローカルアセット対応）
class PostPhotoImage extends StatelessWidget {
  final String? photoUrl;
  final String fallbackAlbumArtUrl;
  final double width;
  final double height;

  const PostPhotoImage({
    super.key,
    required this.photoUrl,
    required this.fallbackAlbumArtUrl,
    required this.width,
    required this.height,
  });

  bool get _hasPhoto => photoUrl != null && photoUrl!.isNotEmpty;
  bool get _isDataUrl => _hasPhoto && PhotoHelper.isDataUrl(photoUrl!);
  bool get _isNetworkUrl => _hasPhoto && PhotoHelper.isNetworkUrl(photoUrl!);

  @override
  Widget build(BuildContext context) {
    if (!_hasPhoto) {
      return _buildFallbackImage();
    }

    if (_isDataUrl) {
      return _buildBase64Image();
    }

    if (_isNetworkUrl) {
      return _buildNetworkImage();
    }

    // ローカルアセット
    return _buildAssetImage();
  }

  Widget _buildBase64Image() {
    return Builder(
      builder: (context) {
        try {
          final String base64String = photoUrl!.split(',')[1];
          final Uint8List bytes = base64Decode(base64String);
          return Image.memory(
            bytes,
            width: width,
            height: height,
            fit: BoxFit.cover,
            errorBuilder: (context, error, stackTrace) {
              if (kDebugMode) {
                print('❌ Failed to decode Base64 photo: $error');
              }
              return _buildFallbackImage();
            },
          );
        } catch (e) {
          if (kDebugMode) {
            print('❌ Error parsing Base64: $e');
          }
          return _buildPhotoPlaceholder();
        }
      },
    );
  }

  Widget _buildNetworkImage() {
    return CachedNetworkImage(
      imageUrl: photoUrl!,
      width: width,
      height: height,
      fit: BoxFit.cover,
      progressIndicatorBuilder: (context, url, progress) {
        return Center(
          child: CupertinoActivityIndicator(
            color: Colors.white,
            radius: 14,
          ),
        );
      },
      errorWidget: (context, url, error) {
        if (kDebugMode) {
          print('❌ Failed to load photo: $error');
          print('   URL: ${PhotoHelper.formatPhotoUrlForLog(photoUrl)}');
        }
        return _buildFallbackImage();
      },
    );
  }

  Widget _buildAssetImage() {
    return Image.asset(
      photoUrl!,
      width: width,
      height: height,
      fit: BoxFit.cover,
      errorBuilder: (context, error, stackTrace) => _buildFallbackImage(),
    );
  }

  Widget _buildFallbackImage() {
    if (fallbackAlbumArtUrl.isNotEmpty) {
      return CachedNetworkImage(
        imageUrl: fallbackAlbumArtUrl,
        width: width,
        height: height,
        fit: BoxFit.cover,
        errorWidget: (context, url, error) => _buildPhotoPlaceholder(),
      );
    }
    return _buildPhotoPlaceholder();
  }

  Widget _buildPhotoPlaceholder() {
    return Container(
      width: width,
      height: height,
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
}

/// 歌詞カードオーバーレイ
class LyricsCardOverlay extends StatelessWidget {
  final PostModel post;

  const LyricsCardOverlay({
    super.key,
    required this.post,
  });

  @override
  Widget build(BuildContext context) {
    final layoutIndex = post.selectedLayoutIndex;
    final positionX = post.cardPositionX;
    final positionY = post.cardPositionY;
    final scale = post.cardScale;
    final rotation = post.cardRotation;
    final layoutType = LyricsCardLayout.getLayoutType(layoutIndex);

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
            track: post.track,
            lyricsText: null,
          ),
        ),
      ),
    );
  }
}

/// 音楽波形ウィジェット
class WaveformDisplay extends StatelessWidget {
  final PostTheme theme;
  final String postId;

  const WaveformDisplay({
    super.key,
    required this.theme,
    required this.postId,
  });

  @override
  Widget build(BuildContext context) {
    final seed = postId.hashCode;
    final random = Random(seed);

    const cardWidth = 363.0;
    const contentHeight = 294.0;
    const availableWidth = cardWidth - 24;

    const barWidth = 2.5;
    const barMargin = 1.2 * 2;
    const totalBarWidth = barWidth + barMargin;
    final maxBarCount = (availableWidth / totalBarWidth).floor();
    final barCount = (maxBarCount * 2 / 3).floor();

    final totalBarWidthOnly = barCount * barWidth;
    final remainingWidth = availableWidth - totalBarWidthOnly;
    final horizontalMargin = (remainingWidth / barCount) / 2;

    return SizedBox(
      height: contentHeight * (32 / 294),
      child: Row(
        children: List.generate(barCount, (index) {
          final normalizedIndex = index / (barCount - 1).toDouble();
          final angle = -pi / 4 + normalizedIndex * 1.5 * pi;
          final waveValue = sin(angle).abs();
          final baseHeight = 0.3 + waveValue * 0.7;
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
}

/// トラック情報表示（タイトル + アーティスト）
class TrackInfoDisplay extends StatelessWidget {
  final TrackModel track;
  final PostTheme theme;
  final double? availableWidth;
  final double titleFontSize;
  final double artistFontSize;

  const TrackInfoDisplay({
    super.key,
    required this.track,
    required this.theme,
    this.availableWidth,
    this.titleFontSize = 25,
    this.artistFontSize = 13,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (availableWidth != null)
          _MarqueeText(
            text: track.trackName,
            style: TextStyle(
              fontSize: titleFontSize,
              fontWeight: FontWeight.bold,
              color: theme.textColor,
            ),
            width: availableWidth!,
          )
        else
          Text(
            track.trackName,
            style: TextStyle(
              fontSize: titleFontSize,
              fontWeight: FontWeight.bold,
              color: theme.textColor,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        const SizedBox(height: 4),
        Text(
          track.artistName,
          style: TextStyle(
            fontSize: artistFontSize,
            color: theme.secondaryTextColor,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }
}

/// シンプルなマーキーテキスト（post_card_media内で使用）
class _MarqueeText extends StatelessWidget {
  final String text;
  final TextStyle style;
  final double width;

  const _MarqueeText({
    required this.text,
    required this.style,
    required this.width,
  });

  @override
  Widget build(BuildContext context) {
    // 完全なマーキー機能が必要な場合はmarquee_text.dartのMarqueeTextを使用
    return SizedBox(
      width: width,
      child: Text(
        text,
        style: style,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}

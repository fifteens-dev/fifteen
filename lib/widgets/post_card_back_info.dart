import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../models/post_theme.dart';
import '../models/track_model.dart';
import '../screens/artist_profile_screen.dart';
import 'post_card/marquee_text.dart';

/// 投稿カード裏面の情報セクション（写真フルブリード上のオーバーレイ）
/// PostCardとpost_preview_screenの両方で使用される共通ウィジェット
class PostCardBackInfo extends StatelessWidget {
  final TrackModel track;
  // theme は互換性のため残すが、色はすべて白系で固定
  final PostTheme theme;
  final int likeCount;
  final int commentCount;
  final bool isLiked;
  final VoidCallback? onLike;
  final VoidCallback? onComment;
  final VoidCallback? onAdd;
  final VoidCallback? onShare;
  final bool showCounts;

  const PostCardBackInfo({
    super.key,
    required this.track,
    required this.theme,
    this.likeCount = 0,
    this.commentCount = 0,
    this.isLiked = false,
    this.onLike,
    this.onComment,
    this.onAdd,
    this.onShare,
    this.showCounts = true,
  });

  @override
  Widget build(BuildContext context) {
    const cardWidth = 363.0;
    const cardHeight = 645.0;
    const contentHeight = 174.0;

    return SizedBox(
      width: cardWidth,
      height: contentHeight,
      child: Stack(
        children: [
          // 暗いグラデーション（写真の上に重ねてテキストを読みやすくする）
          Positioned.fill(
            child: Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.transparent, Color(0x80000000)],
                ),
              ),
            ),
          ),

          // 曲名とアーティスト名
          Positioned(
            left: cardWidth * (12 / 363),
            right: cardWidth * (66 / 363),
            bottom: cardHeight * (110 / 645),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                MarqueeText(
                  text: track.trackName,
                  style: const TextStyle(
                    fontSize: 21,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                  width: cardWidth * (285 / 363),
                ),
                const SizedBox(height: 1.198),
                GestureDetector(
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => ArtistProfileScreen(
                        artistName: track.artistName,
                        spotifyArtistId: track.spotifyArtistId,
                      ),
                    ),
                  ),
                  child: Text(
                    track.artistName,
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.white.withValues(alpha: 0.8),
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),

          // リアクション（いいね、コメント、追加）
          Positioned(
            left: cardWidth * (12 / 363),
            bottom: cardHeight * (80 / 645),
            child: Row(
              children: [
                _buildReactionButton(
                  icon: isLiked ? Icons.favorite : Icons.favorite_border,
                  color: isLiked ? Colors.red : Colors.white,
                  count: showCounts ? likeCount : null,
                  onTap: onLike,
                  textColor: isLiked ? Colors.red : Colors.white,
                ),
                SizedBox(width: cardWidth * (15 / 363)),
                _buildCommentReaction(
                  count: showCounts ? commentCount : null,
                  onTap: onComment,
                ),
                SizedBox(width: cardWidth * (15 / 363)),
                _buildReactionButton(
                  icon: Icons.add_circle_outline,
                  color: Colors.white,
                  count: null,
                  onTap: onAdd,
                  textColor: Colors.white,
                ),
              ],
            ),
          ),

          // ユーザーアバター（右側）- プレビューモードでは非表示
          if (showCounts)
            Positioned(
              right: cardWidth * (12 / 363),
              bottom: cardHeight * (80 / 645),
              child: Row(
                children: [
                  _buildAvatar(),
                  SizedBox(width: cardWidth * (1 / 363)),
                  _buildAvatar(),
                  SizedBox(width: cardWidth * (1 / 363)),
                  _buildAvatar(),
                ],
              ),
            ),

          // コメントボタン
          Positioned(
            left: cardWidth * (12 / 363),
            right: cardWidth * (12 / 363),
            bottom: cardHeight * (28 / 645),
            child: _buildCommentButton(),
          ),

          // "Provided courtesy of Apple Music"
          Positioned(
            left: cardWidth * (17 / 363),
            bottom: cardHeight * (9 / 645),
            child: const Text(
              'Provided courtesy of Apple Music',
              style: TextStyle(
                fontSize: 10,
                color: Color(0xFFB0B0B0),
              ),
            ),
          ),

          // 共有ボタン（右下）
          if (onShare != null)
            Positioned(
              right: cardWidth * (13 / 363),
              bottom: cardHeight * (120 / 645),
              child: _buildShareButton(),
            ),
        ],
      ),
    );
  }

  Widget _buildReactionButton({
    required IconData icon,
    required Color color,
    required int? count,
    VoidCallback? onTap,
    required Color textColor,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Row(
        children: [
          Icon(icon, size: 23, color: color),
          if (count != null) ...[
            const SizedBox(width: 6),
            Text(
              '$count',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: textColor,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildCommentReaction({required int? count, VoidCallback? onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Row(
        children: [
          SvgPicture.asset(
            'assets/icons/message_circle.svg',
            width: 23,
            height: 23,
            colorFilter: const ColorFilter.mode(Colors.white, BlendMode.srcIn),
          ),
          if (count != null) ...[
            const SizedBox(width: 6),
            Text(
              '$count',
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: Colors.white,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildAvatar() {
    return Container(
      width: 25.0,
      height: 25.0,
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.grey,
      ),
    );
  }

  Widget _buildCommentButton() {
    return GestureDetector(
      onTap: onComment,
      child: Container(
        height: 43,
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            const SizedBox(width: 12),
            const Text(
              'コメントする',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: Colors.white,
              ),
            ),
            const Spacer(),
            Image.asset(
              'assets/icons/comment_send_button.png',
              width: 20,
              height: 20,
              color: Colors.white.withValues(alpha: 0.6),
            ),
            const SizedBox(width: 12),
          ],
        ),
      ),
    );
  }

  Widget _buildShareButton() {
    return GestureDetector(
      onTap: onShare,
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.5),
          shape: BoxShape.circle,
        ),
        child: Center(
          child: Image.asset(
            'assets/icons/share_button.png',
            width: 36,
            height: 36,
            color: Colors.white,
            colorBlendMode: BlendMode.srcIn,
          ),
        ),
      ),
    );
  }
}

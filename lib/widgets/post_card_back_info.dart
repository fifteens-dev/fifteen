import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../models/post_theme.dart';
import '../models/track_model.dart';
import 'post_card.dart'; // MarqueeText用

/// 投稿カード裏面の情報セクション（タイトルエリア）
/// PostCardとpost_preview_screenの両方で使用される共通ウィジェット
class PostCardBackInfo extends StatelessWidget {
  final TrackModel track;
  final PostTheme theme;
  final int likeCount;
  final int commentCount;
  final bool isLiked;
  final VoidCallback? onLike;
  final VoidCallback? onComment;
  final VoidCallback? onAdd;
  final VoidCallback? onShare;

  const PostCardBackInfo({
    super.key,
    required this.track,
    required this.theme,
    this.likeCount = 3,
    this.commentCount = 3,
    this.isLiked = false,
    this.onLike,
    this.onComment,
    this.onAdd,
    this.onShare,
  });

  @override
  Widget build(BuildContext context) {
    const cardWidth = 363.0;
    const cardHeight = 644.0;
    const contentHeight = 174.0;

    return SizedBox(
      width: cardWidth,
      height: contentHeight,
      child: Stack(
        children: [
          // グラデーション背景
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    theme.gradientStart.withOpacity(0.0), // 上端は透明
                    theme.gradientEnd, // 14px以降は不透明
                  ],
                  stops: const [0.0, 0.0805], // 上部8.05% (14px/174px)
                ),
              ),
            ),
          ),

          // 曲名とアーティスト名
          Positioned(
            left: cardWidth * (12 / 363),
            right: cardWidth * (66 / 363),
            bottom: cardHeight * (110 / 644),  // top: 64px相当
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                // タイトル（長い場合は自動スクロール）
                MarqueeText(
                  text: track.trackName,
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: theme.textColor,
                  ),
                  width: cardWidth * (285 / 363),
                ),
                const SizedBox(height: 1.198),
                Text(
                  track.artistName,
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

          // リアクション（いいね、コメント、追加）
          Positioned(
            left: cardWidth * (12 / 363),
            bottom: cardHeight * (80 / 644),
            child: Row(
              children: [
                // いいね
                _buildReactionButton(
                  icon: isLiked ? Icons.favorite : Icons.favorite_border,
                  color: isLiked ? Colors.red : theme.iconColor,
                  count: likeCount,
                  onTap: onLike,
                  textColor: isLiked ? Colors.red : theme.textColor,
                ),
                SizedBox(width: cardWidth * (15 / 363)),
                // コメント
                _buildCommentReaction(
                  count: commentCount,
                  onTap: onComment,
                  theme: theme,
                ),
                SizedBox(width: cardWidth * (15 / 363)),
                // 追加
                _buildReactionButton(
                  icon: Icons.add_circle_outline,
                  color: theme.iconColor,
                  count: null,
                  onTap: onAdd,
                  textColor: theme.iconColor,
                ),
              ],
            ),
          ),

          // ユーザーアバター（右側）
          Positioned(
            right: cardWidth * (12 / 363),
            bottom: cardHeight * (80 / 644),
            child: Row(
              children: [
                // いいねした人のアバター（3人分）
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
            bottom: cardHeight * (28 / 644),
            child: _buildCommentButton(theme),
          ),

          // "Provided courtesy of Apple Music"
          Positioned(
            left: cardWidth * (17 / 363),
            bottom: cardHeight * (9 / 644),
            child: Text(
              'Provided courtesy of Apple Music',
              style: TextStyle(
                fontSize: 10,
                color: theme.secondaryTextColor.withOpacity(0.7),
              ),
            ),
          ),

          // 共有ボタン（右下）
          if (onShare != null)
            Positioned(
              right: cardWidth * (13 / 363),
              bottom: cardHeight * (120 / 644),
              child: _buildShareButton(),
            ),
        ],
      ),
    );
  }

  /// リアクションボタン
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
          Icon(
            icon,
            size: 23,
            color: color,
          ),
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

  /// コメントリアクション（SVGアイコン使用）
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
            width: 23,
            height: 23,
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

  /// アバター
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

  /// コメントボタン
  Widget _buildCommentButton(PostTheme theme) {
    const cardWidth = 363.0;

    return GestureDetector(
      onTap: onComment,
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
              color: theme.iconColor.withOpacity(0.7),
            ),
            const SizedBox(width: 12),
          ],
        ),
      ),
    );
  }

  /// 共有ボタン
  Widget _buildShareButton() {
    return GestureDetector(
      onTap: onShare,
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.6),
          shape: BoxShape.circle,
        ),
        child: const Icon(
          Icons.share,
          color: Colors.white,
          size: 20,
        ),
      ),
    );
  }
}

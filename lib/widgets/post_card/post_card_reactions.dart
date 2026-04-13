import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../../models/post_theme.dart';
import '../../screens/other_user_profile_screen.dart';
import '../profile_widgets.dart';
import 'post_card_constants.dart';

/// リアクションボタン（いいね、コメント、保存）を提供するウィジェット群

/// いいねボタン
class LikeButton extends StatelessWidget {
  final bool isLiked;
  final int? count;
  final VoidCallback? onTap;
  final PostTheme theme;
  final bool hideCount;

  const LikeButton({
    super.key,
    required this.isLiked,
    this.count,
    this.onTap,
    required this.theme,
    this.hideCount = false,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isLiked ? Icons.favorite : Icons.favorite_border,
            size: 25,
            color: isLiked ? Colors.red : theme.iconColor,
          ),
          if (!hideCount && count != null) ...[
            const SizedBox(width: 6),
            Text(
              '$count',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: isLiked ? Colors.red : theme.textColor,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// コメントボタン（SVGアイコン使用）
class CommentButton extends StatelessWidget {
  final int count;
  final VoidCallback? onTap;
  final PostTheme theme;
  final bool hideCount;
  final double iconSize;

  const CommentButton({
    super.key,
    required this.count,
    this.onTap,
    required this.theme,
    this.hideCount = false,
    this.iconSize = 25,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SvgPicture.asset(
            'assets/icons/message_circle.svg',
            width: iconSize,
            height: iconSize,
            colorFilter: ColorFilter.mode(
              theme.iconColor,
              BlendMode.srcIn,
            ),
          ),
          if (!hideCount) ...[
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
}

/// 保存ボタン
class SaveButton extends StatelessWidget {
  final bool isSaved;
  final VoidCallback? onTap;
  final PostTheme theme;

  const SaveButton({
    super.key,
    required this.isSaved,
    this.onTap,
    required this.theme,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: isSaved ? _buildSavedIcon() : _buildUnsavedIcon(),
    );
  }

  Widget _buildSavedIcon() {
    return Stack(
      alignment: Alignment.center,
      children: [
        Container(
          width: 24,
          height: 24,
          decoration: const BoxDecoration(
            color: Colors.lightGreen,
            shape: BoxShape.circle,
          ),
        ),
        Icon(
          Icons.check,
          size: 18,
          color: Colors.grey[700],
        ),
      ],
    );
  }

  Widget _buildUnsavedIcon() {
    return Icon(
      Icons.add_circle_outline,
      size: 24,
      color: theme.iconColor,
    );
  }
}

/// シェアボタン
class ShareButton extends StatelessWidget {
  final VoidCallback? onTap;
  final PostTheme theme;
  final double size;

  const ShareButton({
    super.key,
    this.onTap,
    required this.theme,
    this.size = 36,
  });

  @override
  Widget build(BuildContext context) {
    final hsl = HSLColor.fromColor(theme.gradientEnd);
    final newLightness = hsl.lightness > 0.5
        ? (hsl.lightness - 0.1).clamp(0.0, 1.0)
        : (hsl.lightness + 0.1).clamp(0.0, 1.0);
    final bgColor = hsl.withLightness(newLightness).toColor();
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: bgColor,
          shape: BoxShape.circle,
        ),
        child: Center(
          child: Image.asset(
            'assets/icons/share_button.png',
            width: size,
            height: size,
            color: theme.textColor,
            colorBlendMode: BlendMode.srcIn,
          ),
        ),
      ),
    );
  }
}

/// いいねしたユーザーのアイコン一覧
class LikedUsersIcons extends StatelessWidget {
  final List<String> iconUrls;
  final List<String> userIds;
  final double iconSize;
  final double margin;
  final int maxDisplay;

  const LikedUsersIcons({
    super.key,
    required this.iconUrls,
    required this.userIds,
    this.iconSize = PostCardConstants.likedUserIconSize,
    this.margin = PostCardConstants.likedUserIconMargin,
    this.maxDisplay = PostCardConstants.maxLikedUsersToShow,
  });

  @override
  Widget build(BuildContext context) {
    final displayCount = iconUrls.length > maxDisplay ? maxDisplay : iconUrls.length;

    if (displayCount == 0) {
      return const SizedBox.shrink();
    }

    return Row(
      children: List.generate(
        displayCount,
        (index) => GestureDetector(
          onTap: () => _navigateToUserProfile(context, index),
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
                size: iconSize,
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _navigateToUserProfile(BuildContext context, int index) {
    if (index >= userIds.length) return;

    final userId = userIds[index];
    final currentUserId = FirebaseAuth.instance.currentUser?.uid;

    if (currentUserId == userId) {
      Navigator.pushNamed(context, '/profile');
    } else {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => OtherUserProfileScreen(userId: userId),
        ),
      );
    }
  }
}

/// コメント入力ボタン（タップでコメント画面を開く）
class CommentInputButton extends StatelessWidget {
  final VoidCallback? onTap;
  final PostTheme theme;

  const CommentInputButton({
    super.key,
    this.onTap,
    required this.theme,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
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
            Image.asset(
              'assets/icons/comment_send_button.png',
              width: 20,
              height: 20,
            ),
            const SizedBox(width: 12),
          ],
        ),
      ),
    );
  }
}

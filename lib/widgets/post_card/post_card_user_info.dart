import 'package:flutter/material.dart';
import '../../models/post_model.dart';
import '../../models/post_theme.dart';
import '../../screens/other_user_profile_screen.dart';
import '../profile_widgets.dart';

/// ユーザー情報表示関連のウィジェット群

/// 表面用ユーザー情報（アイコン + ユーザー名）
class UserInfoBadge extends StatelessWidget {
  final PostModel post;
  final PostTheme theme;

  const UserInfoBadge({
    super.key,
    required this.post,
    required this.theme,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => _navigateToProfile(context),
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
                imageUrl: post.userIconUrl,
                size: 32,
              ),
            ),
          ),
          const SizedBox(width: 11),

          // ユーザー名
          Text(
            post.username,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: theme.textColor,
            ),
          ),
        ],
      ),
    );
  }

  void _navigateToProfile(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => OtherUserProfileScreen(
          userId: post.userId,
        ),
      ),
    );
  }
}

/// 裏面用ユーザー情報（左上に表示、背景付き）
class UserInfoOverlay extends StatelessWidget {
  final PostModel post;

  const UserInfoOverlay({
    super.key,
    required this.post,
  });

  @override
  Widget build(BuildContext context) {
    // Vibeの場合は「Vibe【お題名】」または「Vibe」、それ以外は感情タグを表示
    String? displayText;

    if (post.isVibe) {
      if (post.vibeTopicTitle != null && post.vibeTopicTitle!.isNotEmpty) {
        displayText = '#${post.vibeTopicTitle!}';
      } else {
        displayText = 'Vibe';
      }
    } else if (post.emotionTag != null) {
      displayText = post.emotionTag;
    }

    return GestureDetector(
      onTap: () => _navigateToProfile(context),
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.5),
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
                  imageUrl: post.userIconUrl,
                  size: 32,
                ),
              ),
            ),
            const SizedBox(width: 11),

            // ユーザー名とハッシュタグ
            Flexible(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    post.username,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                  ),
                  if (displayText != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      displayText,
                      style: const TextStyle(
                        fontSize: 9,
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

  void _navigateToProfile(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => OtherUserProfileScreen(
          userId: post.userId,
        ),
      ),
    );
  }
}

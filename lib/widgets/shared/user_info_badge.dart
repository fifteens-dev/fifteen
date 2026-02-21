import 'package:flutter/material.dart';
import 'user_avatar.dart';

/// 投稿カード左上に表示するユーザー情報バッジ
/// アバター + ユーザー名 + オプションのハッシュタグを半透明背景で表示
class UserInfoBadge extends StatelessWidget {
  final String username;
  final String? iconUrl;
  final String? hashtagText;

  const UserInfoBadge({
    super.key,
    required this.username,
    this.iconUrl,
    this.hashtagText,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.5),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          UserAvatar(
            imageUrl: iconUrl,
            size: UserAvatarSize.medium,
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                username,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                ),
              ),
              if (hashtagText != null) ...[
                const SizedBox(height: 2),
                Text(
                  hashtagText!,
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
        ],
      ),
    );
  }
}

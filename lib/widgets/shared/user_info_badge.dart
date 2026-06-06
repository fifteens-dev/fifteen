import 'package:flutter/material.dart';
import '../../constants/adl_teams.dart';
import 'user_avatar.dart';

/// 投稿カード左上に表示するユーザー情報バッジ
/// アバター + ユーザー名 + オプションのハッシュタグを半透明背景で表示
class UserInfoBadge extends StatelessWidget {
  final String username;
  final String? iconUrl;
  final String? hashtagText;
  final bool showBackground;

  /// ADL班ID。設定されていればユーザー名の右に「@◯◯班」を表示する。
  /// プレビュー段階では navigation は伴わず、表示のみ。
  final String? teamId;

  const UserInfoBadge({
    super.key,
    required this.username,
    this.iconUrl,
    this.hashtagText,
    this.showBackground = true,
    this.teamId,
  });

  @override
  Widget build(BuildContext context) {
    final hasTeam = teamId != null && teamId!.isNotEmpty;
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: showBackground ? Colors.black.withOpacity(0.5) : null,
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
              Row(
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
                  if (hasTeam) ...[
                    const SizedBox(width: 6),
                    Text(
                      '@${AdlTeamDefinitions.displayNameOf(teamId!)}班',
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFFD9D9D9),
                      ),
                    ),
                  ],
                ],
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

import 'package:flutter/material.dart';

/// 空状態ウィジェット
/// データがない場合の表示を統一するためのウィジェット
class EmptyState extends StatelessWidget {
  final String message;
  final String? subMessage;
  final IconData? icon;
  final Widget? action;

  const EmptyState({
    super.key,
    required this.message,
    this.subMessage,
    this.icon,
    this.action,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (icon != null) ...[
              Icon(
                icon,
                size: 64,
                color: Colors.grey[600],
              ),
              const SizedBox(height: 16),
            ],
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
            if (subMessage != null) ...[
              const SizedBox(height: 8),
              Text(
                subMessage!,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.grey[500],
                  fontSize: 14,
                ),
              ),
            ],
            if (action != null) ...[
              const SizedBox(height: 24),
              action!,
            ],
          ],
        ),
      ),
    );
  }
}

/// 投稿がない状態
class NoPostsState extends StatelessWidget {
  final VoidCallback? onCreatePost;

  const NoPostsState({
    super.key,
    this.onCreatePost,
  });

  @override
  Widget build(BuildContext context) {
    return EmptyState(
      icon: Icons.music_note,
      message: 'まだ投稿がありません',
      subMessage: '音楽を選んで投稿してみましょう',
      action: onCreatePost != null
          ? _buildCreateButton(onCreatePost!)
          : null,
    );
  }

  Widget _buildCreateButton(VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFF5D8FFF), Color(0xFF7B68EE)],
          ),
          borderRadius: BorderRadius.circular(24),
        ),
        child: const Text(
          '投稿を作成',
          style: TextStyle(
            color: Colors.white,
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

/// コメントがない状態
class NoCommentsState extends StatelessWidget {
  final Color? textColor;

  const NoCommentsState({
    super.key,
    this.textColor,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(
        'まだコメントがありません\n最初のコメントを投稿しましょう',
        textAlign: TextAlign.center,
        style: TextStyle(
          color: textColor ?? Colors.grey[500],
          fontSize: 14,
        ),
      ),
    );
  }
}

/// 検索結果がない状態
class NoSearchResultsState extends StatelessWidget {
  final String? query;

  const NoSearchResultsState({
    super.key,
    this.query,
  });

  @override
  Widget build(BuildContext context) {
    return EmptyState(
      icon: Icons.search_off,
      message: query != null
          ? '「$query」の検索結果がありません'
          : '検索結果がありません',
      subMessage: '別のキーワードで検索してみてください',
    );
  }
}

/// フォロワーがいない状態
class NoFollowersState extends StatelessWidget {
  const NoFollowersState({super.key});

  @override
  Widget build(BuildContext context) {
    return const EmptyState(
      icon: Icons.people_outline,
      message: 'フォロワーがいません',
    );
  }
}

/// フォロー中がいない状態
class NoFollowingState extends StatelessWidget {
  const NoFollowingState({super.key});

  @override
  Widget build(BuildContext context) {
    return const EmptyState(
      icon: Icons.person_add_outlined,
      message: 'まだ誰もフォローしていません',
      subMessage: '気になるユーザーをフォローしてみましょう',
    );
  }
}

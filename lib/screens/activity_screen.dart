import 'package:flutter/material.dart';

/// アクティビティ画面（通知画面）
class ActivityScreen extends StatefulWidget {
  const ActivityScreen({super.key});

  @override
  State<ActivityScreen> createState() => _ActivityScreenState();
}

class _ActivityScreenState extends State<ActivityScreen> {
  // TODO: 実際のデータはFirestoreから取得
  final List<ActivityItem> _activities = [
    ActivityItem(
      type: ActivityType.follow,
      username: '0lhx9',
      timestamp: '1d',
      userIconUrl: 'https://picsum.photos/seed/user1/200',
      isFollowing: false,
    ),
    ActivityItem(
      type: ActivityType.like,
      username: '0lhx9',
      timestamp: '1d',
      userIconUrl: 'https://picsum.photos/seed/user1/200',
      albumArtUrl: 'https://picsum.photos/seed/album1/200',
    ),
    ActivityItem(
      type: ActivityType.comment,
      username: '0lhx9',
      timestamp: '4d',
      userIconUrl: 'https://picsum.photos/seed/user1/200',
      albumArtUrl: 'https://picsum.photos/seed/album1/200',
      commentText: 'いい曲',
    ),
    ActivityItem(
      type: ActivityType.save,
      username: '0lhx9',
      timestamp: '1d',
      userIconUrl: 'https://picsum.photos/seed/user1/200',
      albumArtUrl: 'https://picsum.photos/seed/album1/200',
    ),
    ActivityItem(
      type: ActivityType.follow,
      username: '0lhx9',
      timestamp: '1d',
      userIconUrl: 'https://picsum.photos/seed/user1/200',
      isFollowing: true,
    ),
    ActivityItem(
      type: ActivityType.like,
      username: '0lhx9',
      timestamp: '1d',
      userIconUrl: 'https://picsum.photos/seed/user1/200',
      albumArtUrl: 'https://picsum.photos/seed/album1/200',
    ),
    ActivityItem(
      type: ActivityType.comment,
      username: 'shadowlynx',
      timestamp: '4d',
      userIconUrl: 'https://picsum.photos/seed/user2/200',
      albumArtUrl: 'https://picsum.photos/seed/album1/200',
      commentText: 'いい曲',
    ),
    ActivityItem(
      type: ActivityType.save,
      username: '0lhx9',
      timestamp: '1d',
      userIconUrl: 'https://picsum.photos/seed/user1/200',
      albumArtUrl: 'https://picsum.photos/seed/album1/200',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(),
            Expanded(
              child: _buildActivityList(),
            ),
          ],
        ),
      ),
    );
  }

  /// ヘッダー
  Widget _buildHeader() {
    return Container(
      height: 45,
      padding: const EdgeInsets.only(left: 0),
      child: Row(
        children: [
          // 戻るボタン
          IconButton(
            icon: const Icon(Icons.chevron_left, color: Colors.white, size: 32),
            onPressed: () => Navigator.pop(context),
          ),
          const SizedBox(width: 8),
          // ユーザー名
          const Text(
            'taroooooda',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w600,
              color: Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  /// アクティビティリスト
  Widget _buildActivityList() {
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 18),
      itemCount: _activities.length,
      itemBuilder: (context, index) {
        return _buildActivityCell(_activities[index]);
      },
    );
  }

  /// アクティビティセル
  Widget _buildActivityCell(ActivityItem activity) {
    switch (activity.type) {
      case ActivityType.follow:
        return _buildFollowCell(activity);
      case ActivityType.like:
        return _buildLikeCell(activity);
      case ActivityType.comment:
        return _buildCommentCell(activity);
      case ActivityType.save:
        return _buildSaveCell(activity);
    }
  }

  /// フォロー通知セル
  Widget _buildFollowCell(ActivityItem activity) {
    return Container(
      height: 59,
      margin: const EdgeInsets.only(bottom: 0),
      child: Row(
        children: [
          // ユーザーアイコン
          _buildUserIcon(activity.userIconUrl),
          const SizedBox(width: 20),
          // コンテンツ
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Row(
                  children: [
                    Text(
                      activity.username,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      activity.timestamp,
                      style: const TextStyle(
                        fontSize: 14,
                        color: Color(0x80FFFFFF),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                const Text(
                  'あなたをフォローしました',
                  style: TextStyle(
                    fontSize: 14,
                    color: Color(0x80FFFFFF),
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          // フォローボタン
          _buildFollowButton(activity.isFollowing),
        ],
      ),
    );
  }

  /// いいね通知セル
  Widget _buildLikeCell(ActivityItem activity) {
    return Container(
      height: 59,
      margin: const EdgeInsets.only(bottom: 0),
      child: Row(
        children: [
          // ユーザーアイコン
          _buildUserIcon(activity.userIconUrl),
          const SizedBox(width: 20),
          // コンテンツ
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Row(
                  children: [
                    Text(
                      activity.username,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      activity.timestamp,
                      style: const TextStyle(
                        fontSize: 14,
                        color: Color(0x80FFFFFF),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                const Text(
                  'あなたの投稿にいいねしました',
                  style: TextStyle(
                    fontSize: 14,
                    color: Color(0x80FFFFFF),
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          // アルバムアート
          _buildAlbumArt(activity.albumArtUrl),
        ],
      ),
    );
  }

  /// 保存通知セル
  Widget _buildSaveCell(ActivityItem activity) {
    return Container(
      height: 59,
      margin: const EdgeInsets.only(bottom: 0),
      child: Row(
        children: [
          // ユーザーアイコン
          _buildUserIcon(activity.userIconUrl),
          const SizedBox(width: 20),
          // コンテンツ
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Row(
                  children: [
                    Text(
                      activity.username,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      activity.timestamp,
                      style: const TextStyle(
                        fontSize: 14,
                        color: Color(0x80FFFFFF),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                const Text(
                  'あなたの投稿したが楽曲を保存しました',
                  style: TextStyle(
                    fontSize: 14,
                    color: Color(0x80FFFFFF),
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          // アルバムアート
          _buildAlbumArt(activity.albumArtUrl),
        ],
      ),
    );
  }

  /// コメント通知セル
  Widget _buildCommentCell(ActivityItem activity) {
    return Container(
      height: 81,
      margin: const EdgeInsets.only(bottom: 0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ユーザーアイコン
          Padding(
            padding: const EdgeInsets.only(top: 9),
            child: _buildUserIcon(activity.userIconUrl),
          ),
          const SizedBox(width: 20),
          // コンテンツ
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: 9),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        activity.username,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        activity.timestamp,
                        style: const TextStyle(
                          fontSize: 14,
                          color: Color(0x80FFFFFF),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  const Text(
                    'あなたの投稿にコメントしました',
                    style: TextStyle(
                      fontSize: 14,
                      color: Color(0x80FFFFFF),
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  // コメント引用
                  Row(
                    children: [
                      Container(
                        width: 3,
                        height: 20,
                        decoration: BoxDecoration(
                          color: const Color(0xFFD9D9D9),
                          borderRadius: BorderRadius.circular(3),
                        ),
                      ),
                      const SizedBox(width: 7),
                      Expanded(
                        child: Text(
                          activity.commentText ?? '',
                          style: const TextStyle(
                            fontSize: 14,
                            color: Colors.white,
                          ),
                          overflow: TextOverflow.ellipsis,
                          maxLines: 1,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 16),
          // アルバムアート
          Padding(
            padding: const EdgeInsets.only(top: 9),
            child: _buildAlbumArt(activity.albumArtUrl),
          ),
        ],
      ),
    );
  }

  /// ユーザーアイコン
  Widget _buildUserIcon(String? imageUrl) {
    return Container(
      width: 42,
      height: 42,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: const Color(0xFF2D2D2D),
        image: imageUrl != null
            ? DecorationImage(
                image: NetworkImage(imageUrl),
                fit: BoxFit.cover,
              )
            : null,
      ),
    );
  }

  /// アルバムアート
  Widget _buildAlbumArt(String? imageUrl) {
    return Container(
      width: 42,
      height: 42,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        color: const Color(0xFF2D2D2D),
        image: imageUrl != null
            ? DecorationImage(
                image: NetworkImage(imageUrl),
                fit: BoxFit.cover,
              )
            : null,
      ),
    );
  }

  /// フォローボタン
  Widget _buildFollowButton(bool isFollowing) {
    return Container(
      height: 32,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Center(
        child: Text(
          isFollowing ? 'フォロー中' : 'フォロー',
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w500,
            color: Colors.black,
          ),
        ),
      ),
    );
  }
}

/// アクティビティタイプ
enum ActivityType {
  follow,   // フォロー
  like,     // いいね
  comment,  // コメント
  save,     // 保存
}

/// アクティビティアイテム
class ActivityItem {
  final ActivityType type;
  final String username;
  final String timestamp;
  final String? userIconUrl;
  final String? albumArtUrl;
  final String? commentText;
  final bool isFollowing;

  ActivityItem({
    required this.type,
    required this.username,
    required this.timestamp,
    this.userIconUrl,
    this.albumArtUrl,
    this.commentText,
    this.isFollowing = false,
  });
}

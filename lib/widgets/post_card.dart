import 'package:flutter/material.dart';
import '../models/post_model.dart';
import '../constants/app_colors.dart';

/// 投稿カードウィジェット
class PostCard extends StatefulWidget {
  final PostModel post;
  final VoidCallback? onLike;
  final VoidCallback? onComment;
  final VoidCallback? onAdd;
  final String? currentUserId; // 現在のユーザーID（いいね状態の判定用）

  const PostCard({
    super.key,
    required this.post,
    this.onLike,
    this.onComment,
    this.onAdd,
    this.currentUserId,
  });

  @override
  State<PostCard> createState() => _PostCardState();
}

class _PostCardState extends State<PostCard> {
  // 楽観的UI更新（Optimistic Update）用のローカル状態
  //
  // ユーザーがいいねボタンをクリックした時、Firestoreへの更新を待たずに
  // 即座にUIを更新するための一時的な状態です。
  //
  // Firestoreから正しい更新データが返ってきたら、この楽観的状態はリセットされ、
  // 実際のFirestoreデータが表示されます。
  //
  // これにより、他のユーザーがいいねを押した場合も、リアルタイムで
  // すべてのクライアントに反映されます。
  bool? _isLikedOptimistic;
  int? _likeCountOptimistic;

  /// いいねボタンが押された時の処理（楽観的UI更新）
  void _handleLikeTap() {
    if (widget.onLike != null) {
      setState(() {
        // 現在のいいね状態を取得
        final currentIsLiked = _isLikedOptimistic ??
            (widget.currentUserId != null && widget.post.isLikedBy(widget.currentUserId!));
        final currentLikeCount = _likeCountOptimistic ?? widget.post.likeCount;

        // 楽観的に状態を反転
        _isLikedOptimistic = !currentIsLiked;
        _likeCountOptimistic = currentIsLiked ? currentLikeCount - 1 : currentLikeCount + 1;
      });

      // 実際のFirestore更新を実行
      widget.onLike!();
    }
  }

  @override
  void didUpdateWidget(PostCard oldWidget) {
    super.didUpdateWidget(oldWidget);

    // Firestoreから新しいデータが来た場合、楽観的状態と一致するかチェック
    if (oldWidget.post.postId != widget.post.postId) {
      // 異なる投稿に変わった場合はリセット
      _isLikedOptimistic = null;
      _likeCountOptimistic = null;
    } else if (_isLikedOptimistic != null || _likeCountOptimistic != null) {
      // 楽観的状態が設定されている場合、Firestoreの状態と比較
      final actualIsLiked = widget.currentUserId != null &&
          widget.post.isLikedBy(widget.currentUserId!);
      final actualLikeCount = widget.post.likeCount;

      // 楽観的状態とFirestoreの状態が一致した場合のみリセット
      if (_isLikedOptimistic == actualIsLiked &&
          _likeCountOptimistic == actualLikeCount) {
        _isLikedOptimistic = null;
        _likeCountOptimistic = null;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 644,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color(0xFFC9DD77), // Figmaデザインのグラデーション開始色
            Color(0xFFCADD72),
          ],
        ),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: Stack(
          children: [
            // アルバムジャケット（背景）
            Positioned.fill(
              child: _buildAlbumCover(),
            ),

            // グラデーションオーバーレイ（下部）
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              height: 294,
              child: Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Color(0x00CADD72),
                      Color(0xFFC9DD77),
                    ],
                    stops: [0.0377, 1.0],
                  ),
                ),
              ),
            ),

            // コンテンツ
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              height: 294,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // "Provided courtesy of Apple Music"
                    const Text(
                      'Provided courtesy of Apple Music',
                      style: TextStyle(
                        fontSize: 10,
                        color: Color(0xFFB0B0B0),
                      ),
                    ),
                    const SizedBox(height: 12),

                    // コメントボタン
                    _buildCommentButton(),
                    const SizedBox(height: 16),

                    // 音楽波形プレースホルダー
                    _buildWaveform(),
                    const SizedBox(height: 16),

                    // 曲名とアーティスト名
                    _buildTrackInfo(),
                    const SizedBox(height: 10),

                    // リアクション（いいね、コメント、追加）といいねした人のアイコン
                    _buildReactions(),
                    const SizedBox(height: 16),

                    // ユーザー情報
                    _buildUserInfo(),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// アルバムカバー
  Widget _buildAlbumCover() {
    return widget.post.track.albumImageUrl.isNotEmpty
        ? Image.network(
            widget.post.track.albumImageUrl,
            fit: BoxFit.cover,
            errorBuilder: (context, error, stackTrace) {
              return _buildAlbumPlaceholder();
            },
          )
        : _buildAlbumPlaceholder();
  }

  /// アルバムプレースホルダー
  Widget _buildAlbumPlaceholder() {
    return Container(
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

  /// コメントボタン
  Widget _buildCommentButton() {
    return GestureDetector(
      onTap: widget.onComment,
      child: Container(
        height: 43,
        decoration: BoxDecoration(
          color: const Color(0xFFB0C266),
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
                color: Colors.black,
              ),
            ),
            const Spacer(),
            Icon(
              Icons.send,
              size: 20,
              color: Colors.black.withOpacity(0.7),
            ),
            const SizedBox(width: 12),
          ],
        ),
      ),
    );
  }

  /// 音楽波形プレースホルダー
  Widget _buildWaveform() {
    return Container(
      height: 32,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        children: List.generate(40, (index) {
          // ランダムな高さの波形バーを生成
          final heights = [8.0, 12.0, 16.0, 20.0, 24.0, 16.0, 12.0];
          final height = heights[index % heights.length];
          return Container(
            width: 3,
            height: height,
            margin: const EdgeInsets.symmetric(horizontal: 1),
            decoration: BoxDecoration(
              color: Colors.black,
              borderRadius: BorderRadius.circular(2),
            ),
          );
        }),
      ),
    );
  }

  /// 曲名とアーティスト名
  Widget _buildTrackInfo() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          widget.post.track.trackName,
          style: const TextStyle(
            fontSize: 25,
            fontWeight: FontWeight.bold,
            color: Colors.black,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: 4),
        Text(
          widget.post.track.artistName,
          style: const TextStyle(
            fontSize: 13,
            color: Colors.black,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }

  /// リアクション（いいね、コメント、追加）
  Widget _buildReactions() {
    // 楽観的UI更新を優先、なければ実際の状態を使用
    final isLiked = _isLikedOptimistic ??
        (widget.currentUserId != null && widget.post.isLikedBy(widget.currentUserId!));
    final likeCount = _likeCountOptimistic ?? widget.post.likeCount;

    return Row(
      children: [
        // いいね
        _buildReactionItem(
          icon: isLiked ? Icons.favorite : Icons.favorite_border,
          count: likeCount,
          onTap: _handleLikeTap,
          isActive: isLiked,
        ),
        const SizedBox(width: 12),

        // コメント
        _buildReactionItem(
          icon: Icons.chat_bubble_outline,
          count: widget.post.commentCount,
          onTap: widget.onComment,
        ),
        const SizedBox(width: 12),

        // 追加
        GestureDetector(
          onTap: widget.onAdd,
          child: Container(
            width: 23,
            height: 23,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.add_circle_outline,
              size: 23,
              color: Colors.black,
            ),
          ),
        ),

        const Spacer(),

        // いいねした人のアイコン（最大3人）
        _buildLikedUsersIcons(),
      ],
    );
  }

  /// リアクションアイテム
  Widget _buildReactionItem({
    required IconData icon,
    required int count,
    VoidCallback? onTap,
    bool isActive = false,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Row(
        children: [
          Icon(
            icon,
            size: 25,
            color: isActive ? Colors.red : Colors.black,
          ),
          const SizedBox(width: 6),
          Text(
            '$count',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: isActive ? Colors.red : Colors.black,
            ),
          ),
        ],
      ),
    );
  }

  /// いいねした人のアイコン（最大3人表示）
  Widget _buildLikedUsersIcons() {
    // TODO: 実際のいいねしたユーザーのアイコンを表示
    // 今はダミーのプレースホルダーを3つ表示
    return Row(
      children: List.generate(
        3,
        (index) => Container(
          width: 25,
          height: 25,
          margin: EdgeInsets.only(left: index > 0 ? 4 : 0),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.grey[400],
          ),
          child: const Icon(
            Icons.person,
            size: 14,
            color: Colors.white,
          ),
        ),
      ),
    );
  }

  /// ユーザー情報
  Widget _buildUserInfo() {
    return Row(
      children: [
        // ユーザーアイコン
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.grey[400],
          ),
          child: widget.post.userIconUrl != null && widget.post.userIconUrl!.isNotEmpty
              ? ClipOval(
                  child: Image.network(
                    widget.post.userIconUrl!,
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) {
                      return const Icon(Icons.person, size: 20, color: Colors.white);
                    },
                  ),
                )
              : const Icon(Icons.person, size: 20, color: Colors.white),
        ),
        const SizedBox(width: 8),

        // ユーザー名
        Text(
          widget.post.username,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: Colors.black,
          ),
        ),
      ],
    );
  }
}

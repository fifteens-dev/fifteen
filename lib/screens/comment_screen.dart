import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/post_model.dart';
import '../models/comment_model.dart';
import '../services/comment_service.dart';
import '../constants/app_colors.dart';
import '../utils/test_data.dart';

/// コメント画面
class CommentScreen extends StatefulWidget {
  final PostModel post;
  final Function(int)? onCommentCountChanged;

  const CommentScreen({
    super.key,
    required this.post,
    this.onCommentCountChanged,
  });

  @override
  State<CommentScreen> createState() => _CommentScreenState();
}

class _CommentScreenState extends State<CommentScreen> {
  final TextEditingController _commentController = TextEditingController();
  final CommentService _commentService = CommentService();
  final ScrollController _scrollController = ScrollController();
  bool _isPosting = false;

  @override
  void dispose() {
    _commentController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  /// コメントを投稿
  Future<void> _postComment() async {
    final content = _commentController.text.trim();
    if (content.isEmpty) return;

    setState(() {
      _isPosting = true;
    });

    try {
      final currentUser = FirebaseAuth.instance.currentUser;
      final userId = currentUser?.uid ?? 'test_user_temp';
      final username = currentUser?.displayName ?? 'test_user';

      // 新しいコメントを作成
      final newComment = CommentModel(
        commentId: 'local_comment_${DateTime.now().millisecondsSinceEpoch}',
        postId: widget.post.postId,
        userId: userId,
        username: username,
        userIconUrl: currentUser?.photoURL,
        content: content,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      // テスト投稿の場合はローカルストレージに追加
      if (widget.post.postId.startsWith('test_post_')) {
        await TestData.addLocalComment(widget.post.postId, newComment);

        // コメント数を更新（親画面に通知）
        if (widget.onCommentCountChanged != null) {
          final newCommentCount = await TestData.getCommentCount(widget.post.postId);
          widget.onCommentCountChanged!(newCommentCount);
        }

        setState(() {}); // 画面を更新
      } else {
        // 通常の投稿の場合はFirestoreに保存
        await _commentService.createComment(
          postId: widget.post.postId,
          userId: userId,
          username: username,
          userIconUrl: currentUser?.photoURL,
          content: content,
        );

        // コメント数を更新（親画面に通知）
        if (widget.onCommentCountChanged != null) {
          final newCommentCount = widget.post.commentCount + 1;
          widget.onCommentCountChanged!(newCommentCount);
        }
      }

      _commentController.clear();

      // スクロールを最下部に移動
      Future.delayed(const Duration(milliseconds: 100), () {
        if (_scrollController.hasClients && mounted) {
          _scrollController.animateTo(
            _scrollController.position.maxScrollExtent,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut,
          );
        }
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('コメントの投稿に失敗しました: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isPosting = false;
        });
      }
    }
  }

  /// コメント数を取得
  Future<int> _getTotalCommentCount() async {
    if (widget.post.postId.startsWith('test_post_')) {
      return await TestData.getCommentCount(widget.post.postId);
    }
    return widget.post.commentCount;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: AppColors.textPrimary),
          onPressed: () => Navigator.pop(context),
        ),
        title: FutureBuilder<int>(
          future: _getTotalCommentCount(),
          builder: (context, snapshot) {
            final count = snapshot.data ?? widget.post.commentCount;
            return Text(
              'コメント ($count)',
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 18,
                fontWeight: FontWeight.w600,
              ),
            );
          },
        ),
        centerTitle: true,
      ),
      body: Column(
        children: [
          // 投稿情報
          _buildPostHeader(),
          const Divider(color: AppColors.border, height: 1),

          // コメント一覧
          Expanded(
            child: _buildCommentList(),
          ),

          const Divider(color: AppColors.border, height: 1),

          // コメント入力欄
          _buildCommentInput(),
        ],
      ),
    );
  }

  /// コメント一覧
  Widget _buildCommentList() {
    // テスト投稿の場合はダミーコメント + ローカルコメントを表示
    if (widget.post.postId.startsWith('test_post_')) {
      return FutureBuilder<List<CommentModel>>(
        future: TestData.getLocalComments(widget.post.postId),
        builder: (context, snapshot) {
          final dummyComments = TestData.generateTestComments(widget.post.postId);
          final localComments = snapshot.data ?? [];
          final allComments = [...dummyComments, ...localComments];

          if (allComments.isEmpty) {
            return Center(
              child: Text(
                'まだコメントがありません\n最初のコメントを投稿しましょう',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 14,
                ),
              ),
            );
          }

          return ListView.builder(
            controller: _scrollController,
            padding: const EdgeInsets.symmetric(vertical: 8),
            itemCount: allComments.length,
            itemBuilder: (context, index) {
              return _buildCommentItem(allComments[index]);
            },
          );
        },
      );
    }

    // 通常の投稿の場合はFirestoreからコメントを取得
    return StreamBuilder<List<CommentModel>>(
      stream: _commentService.getCommentsStream(widget.post.postId),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(
            child: CircularProgressIndicator(
              color: AppColors.textPrimary,
            ),
          );
        }

        if (snapshot.hasError) {
          return Center(
            child: Text(
              'エラーが発生しました',
              style: TextStyle(color: AppColors.textSecondary),
            ),
          );
        }

        final comments = snapshot.data ?? [];

        if (comments.isEmpty) {
          return Center(
            child: Text(
              'まだコメントがありません\n最初のコメントを投稿しましょう',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: AppColors.textSecondary,
                fontSize: 14,
              ),
            ),
          );
        }

        return ListView.builder(
          controller: _scrollController,
          padding: const EdgeInsets.symmetric(vertical: 8),
          itemCount: comments.length,
          itemBuilder: (context, index) {
            return _buildCommentItem(comments[index]);
          },
        );
      },
    );
  }

  /// 投稿ヘッダー
  Widget _buildPostHeader() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ユーザーアイコン
          Container(
            width: 40,
            height: 40,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.grey,
            ),
            child: widget.post.userIconUrl != null &&
                    widget.post.userIconUrl!.isNotEmpty
                ? ClipOval(
                    child: Image.network(
                      widget.post.userIconUrl!,
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) {
                        return const Icon(Icons.person,
                            size: 24, color: Colors.white);
                      },
                    ),
                  )
                : const Icon(Icons.person, size: 24, color: Colors.white),
          ),
          const SizedBox(width: 12),

          // 投稿情報
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.post.username,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${widget.post.track.trackName} - ${widget.post.track.artistName}',
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 14,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// コメントアイテム
  Widget _buildCommentItem(CommentModel comment) {
    final currentUser = FirebaseAuth.instance.currentUser;
    final isMyComment = currentUser != null && comment.userId == currentUser.uid;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ユーザーアイコン
          Container(
            width: 32,
            height: 32,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.grey,
            ),
            child: comment.userIconUrl != null && comment.userIconUrl!.isNotEmpty
                ? ClipOval(
                    child: Image.network(
                      comment.userIconUrl!,
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) {
                        return const Icon(Icons.person,
                            size: 20, color: Colors.white);
                      },
                    ),
                  )
                : const Icon(Icons.person, size: 20, color: Colors.white),
          ),
          const SizedBox(width: 12),

          // コメント内容
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      comment.username,
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      _formatTimestamp(comment.createdAt),
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  comment.content,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          ),

          // 削除ボタン（自分のコメントの場合のみ）
          if (isMyComment)
            IconButton(
              icon: const Icon(Icons.delete_outline, color: AppColors.textSecondary, size: 20),
              onPressed: () => _deleteComment(comment),
            ),
        ],
      ),
    );
  }

  /// コメント入力欄
  Widget _buildCommentInput() {
    return Container(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 8,
        bottom: MediaQuery.of(context).viewInsets.bottom + 8,
      ),
      color: AppColors.background,
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _commentController,
              style: const TextStyle(color: AppColors.textPrimary),
              decoration: InputDecoration(
                hintText: 'コメントを入力...',
                hintStyle: const TextStyle(color: AppColors.textSecondary),
                filled: true,
                fillColor: AppColors.surface,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(24),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 10,
                ),
              ),
              maxLines: null,
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => _postComment(),
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            onPressed: _isPosting ? null : _postComment,
            icon: _isPosting
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: AppColors.textPrimary,
                    ),
                  )
                : const Icon(Icons.send, color: AppColors.textPrimary),
          ),
        ],
      ),
    );
  }

  /// タイムスタンプをフォーマット
  String _formatTimestamp(DateTime timestamp) {
    final now = DateTime.now();
    final difference = now.difference(timestamp);

    if (difference.inMinutes < 1) {
      return '今';
    } else if (difference.inHours < 1) {
      return '${difference.inMinutes}分前';
    } else if (difference.inDays < 1) {
      return '${difference.inHours}時間前';
    } else if (difference.inDays < 7) {
      return '${difference.inDays}日前';
    } else {
      return '${timestamp.year}/${timestamp.month}/${timestamp.day}';
    }
  }

  /// コメントを削除
  Future<void> _deleteComment(CommentModel comment) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text('コメントを削除', style: TextStyle(color: AppColors.textPrimary)),
        content: const Text('このコメントを削除しますか？', style: TextStyle(color: AppColors.textSecondary)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('キャンセル', style: TextStyle(color: AppColors.textSecondary)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('削除', style: TextStyle(color: AppColors.error)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        // ローカルコメントかFirestoreコメントかを判定
        if (comment.commentId.startsWith('local_comment_')) {
          await TestData.removeLocalComment(comment.postId, comment.commentId);

          // コメント数を更新（親画面に通知）
          if (widget.onCommentCountChanged != null) {
            final newCommentCount = await TestData.getCommentCount(comment.postId);
            widget.onCommentCountChanged!(newCommentCount);
          }

          setState(() {}); // 画面を更新
        } else {
          await _commentService.deleteComment(comment.commentId, comment.postId);

          // コメント数を更新（親画面に通知）
          if (widget.onCommentCountChanged != null) {
            final newCommentCount = widget.post.commentCount - 1;
            widget.onCommentCountChanged!(newCommentCount);
          }
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('コメントの削除に失敗しました: $e'),
              backgroundColor: AppColors.error,
            ),
          );
        }
      }
    }
  }
}

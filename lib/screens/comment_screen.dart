import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/post_model.dart';
import '../models/post_theme.dart';
import '../models/comment_model.dart';
import '../services/comment_service.dart';
import '../constants/app_colors.dart';
import '../utils/current_user_helper.dart';
import '../widgets/dialogs/dialogs.dart';
import '../services/report_service.dart';

/// コメント画面（ボトムシート）
class CommentScreen extends StatefulWidget {
  final PostModel post;
  final Function(int)? onCommentCountChanged;

  const CommentScreen({
    super.key,
    required this.post,
    this.onCommentCountChanged,
  });

  /// ボトムシートとして表示するヘルパーメソッド
  static Future<void> show(
    BuildContext context, {
    required PostModel post,
    Function(int)? onCommentCountChanged,
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        minChildSize: 0.4,
        maxChildSize: 0.9,
        builder: (context, scrollController) => CommentScreen(
          post: post,
          onCommentCountChanged: onCommentCountChanged,
        ),
      ),
    );
  }

  @override
  State<CommentScreen> createState() => _CommentScreenState();
}

class _CommentScreenState extends State<CommentScreen> {
  final TextEditingController _commentController = TextEditingController();
  final CommentService _commentService = CommentService();
  final ReportService _reportService = ReportService();
  final ScrollController _scrollController = ScrollController();
  bool _isPosting = false;
  String _currentUsername = '';
  String? _currentUserIconUrl;

  PostTheme get _theme => widget.post.theme;

  @override
  void initState() {
    super.initState();
    _loadCurrentUserInfo();
  }

  Future<void> _loadCurrentUserInfo() async {
    final userInfo = await CurrentUserHelper.load();
    if (mounted) {
      setState(() {
        _currentUsername = userInfo.username;
        _currentUserIconUrl = userInfo.iconUrl;
      });
    }
  }

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
      final username = _currentUsername.isNotEmpty ? _currentUsername : 'ユーザー';

      await _commentService.createComment(
        postId: widget.post.postId,
        userId: userId,
        username: username,
        userIconUrl: _currentUserIconUrl,
        content: content,
      );

      if (widget.onCommentCountChanged != null) {
        // commentCountフィールドはcreateComment内で既にインクリメント済み
        // 投稿ドキュメントから直接読み取る
        final postDoc = await FirebaseFirestore.instance
            .collection('posts')
            .doc(widget.post.postId)
            .get();
        final count = postDoc.data()?['commentCount'] ?? 0;
        widget.onCommentCountChanged!(count as int);
      }

      _commentController.clear();

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

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: _theme.gradientEnd,
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(20),
          topRight: Radius.circular(20),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // ドラッグハンドル
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Container(
              width: 50,
              height: 3,
              decoration: BoxDecoration(
                color: const Color(0xFF404040),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),

          // タイトル「コメント」
          Padding(
            padding: const EdgeInsets.only(top: 14, bottom: 16),
            child: Text(
              'コメント',
              style: TextStyle(
                color: _theme.textColor,
                fontSize: 14,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),

          // 区切り線
          Divider(
            color: _theme.textColor.withOpacity(0.15),
            height: 1,
          ),

          // コメント一覧
          Expanded(
            child: _buildCommentList(),
          ),

          // コメント入力欄
          _buildCommentInput(),
        ],
      ),
    );
  }

  /// コメント一覧
  Widget _buildCommentList() {
    return StreamBuilder<List<CommentModel>>(
      stream: _commentService.getCommentsStream(widget.post.postId),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Center(
            child: CircularProgressIndicator(
              color: _theme.textColor,
            ),
          );
        }

        if (snapshot.hasError) {
          return Center(
            child: Text(
              'エラーが発生しました',
              style: TextStyle(color: _theme.secondaryTextColor),
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
                color: _theme.secondaryTextColor,
                fontSize: 14,
              ),
            ),
          );
        }

        return ListView.builder(
          controller: _scrollController,
          padding: const EdgeInsets.only(top: 16),
          itemCount: comments.length,
          itemBuilder: (context, index) {
            return _buildCommentItem(comments[index]);
          },
        );
      },
    );
  }

  /// コメントアイテム（Figma準拠）
  Widget _buildCommentItem(CommentModel comment) {
    final currentUser = FirebaseAuth.instance.currentUser;
    final isMyComment =
        currentUser != null && comment.userId == currentUser.uid;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ユーザーアイコン（32x32）
          Container(
            width: 32,
            height: 32,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.grey,
            ),
            child:
                comment.userIconUrl != null && comment.userIconUrl!.isNotEmpty
                    ? ClipOval(
                        child: _buildUserIcon(comment.userIconUrl!, 32),
                      )
                    : Icon(Icons.person, size: 20, color: _theme.textColor),
          ),
          const SizedBox(width: 8),

          // コメント内容
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ユーザー名 + タイムスタンプ
                Row(
                  children: [
                    Text(
                      comment.username,
                      style: TextStyle(
                        color: _theme.textColor,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      _formatTimestamp(comment.createdAt),
                      style: const TextStyle(
                        color: Color(0xFF68717B),
                        fontSize: 10,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                // コメント本文
                Text(
                  comment.content,
                  style: TextStyle(
                    color: _theme.textColor,
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          ),

          // 3点メニュー（自分→削除、他人→通報）
          SizedBox(
            width: 28,
            height: 28,
            child: PopupMenuButton<String>(
              padding: EdgeInsets.zero,
              icon: Icon(Icons.more_horiz,
                  color: _theme.secondaryTextColor, size: 18),
              color: const Color(0xFF2D2D2D),
              onSelected: (value) async {
                if (value == 'delete') {
                  _deleteComment(comment);
                } else if (value == 'report') {
                  await _reportComment(comment);
                }
              },
              itemBuilder: (context) => [
                if (isMyComment)
                  const PopupMenuItem(
                    value: 'delete',
                    child: Row(
                      children: [
                        Icon(Icons.delete_outline,
                            color: Color(0xFFE53935), size: 18),
                        SizedBox(width: 8),
                        Text('削除',
                            style: TextStyle(color: Color(0xFFE53935))),
                      ],
                    ),
                  ),
                if (!isMyComment)
                  const PopupMenuItem(
                    value: 'report',
                    child: Row(
                      children: [
                        Icon(Icons.flag_outlined,
                            color: Color(0xFFE53935), size: 18),
                        SizedBox(width: 8),
                        Text('通報',
                            style: TextStyle(color: Color(0xFFE53935))),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// コメント入力欄（Figma準拠）
  Widget _buildCommentInput() {
    return Container(
      padding: EdgeInsets.only(
        left: 19,
        right: 19,
        top: 10,
        bottom: MediaQuery.of(context).viewInsets.bottom + 16,
      ),
      child: Row(
        children: [
          // 現在のユーザーアイコン（40x40）
          Container(
            width: 40,
            height: 40,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.grey,
            ),
            child: _currentUserIconUrl != null &&
                    _currentUserIconUrl!.isNotEmpty
                ? ClipOval(
                    child: _buildUserIcon(_currentUserIconUrl!, 40),
                  )
                : Icon(Icons.person, size: 24, color: _theme.textColor),
          ),
          const SizedBox(width: 10),

          // 入力フィールド（commentButtonColor背景、角丸12px）
          Expanded(
            child: Container(
              height: 40,
              decoration: BoxDecoration(
                color: _theme.commentButtonColor,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _commentController,
                      style: TextStyle(
                        color: _theme.textColor,
                        fontSize: 13,
                      ),
                      decoration: InputDecoration(
                        hintText: 'コメントする',
                        hintStyle: TextStyle(
                          color: _theme.textColor.withOpacity(0.6),
                          fontSize: 13,
                        ),
                        border: InputBorder.none,
                        contentPadding: const EdgeInsets.only(
                          left: 13,
                          bottom: 10,
                        ),
                        isCollapsed: true,
                      ),
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => _postComment(),
                      contextMenuBuilder: (ctx, editableTextState) {
                        return AdaptiveTextSelectionToolbar.buttonItems(
                          anchors: editableTextState.contextMenuAnchors,
                          buttonItems: editableTextState.contextMenuButtonItems,
                        );
                      },
                    ),
                  ),
                  // 送信ボタン
                  GestureDetector(
                    onTap: _isPosting ? null : _postComment,
                    child: Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: _isPosting
                          ? SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: _theme.textColor,
                              ),
                            )
                          : Icon(
                              Icons.send,
                              color: _theme.textColor.withOpacity(0.7),
                              size: 24,
                            ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// ユーザーアイコンを表示（アセットパスとネットワークURLの両方に対応）
  Widget _buildUserIcon(String url, double size) {
    if (url.startsWith('http://') || url.startsWith('https://')) {
      return CachedNetworkImage(
        imageUrl: url,
        width: size,
        height: size,
        fit: BoxFit.cover,
        errorWidget: (context, imageUrl, error) {
          return Icon(Icons.person, size: size * 0.6, color: _theme.textColor);
        },
      );
    } else {
      return Image.asset(
        url,
        width: size,
        height: size,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) {
          return Icon(Icons.person, size: size * 0.6, color: _theme.textColor);
        },
      );
    }
  }

  /// タイムスタンプをフォーマット（Figma準拠: 短縮表記）
  String _formatTimestamp(DateTime timestamp) {
    final now = DateTime.now();
    final difference = now.difference(timestamp);

    if (difference.inMinutes < 1) {
      return '今';
    } else if (difference.inHours < 1) {
      return '${difference.inMinutes}分';
    } else if (difference.inDays < 1) {
      return '${difference.inHours}時間';
    } else if (difference.inDays < 7) {
      return '${difference.inDays}日';
    } else {
      return '${timestamp.year}/${timestamp.month}/${timestamp.day}';
    }
  }

  /// コメントを通報
  Future<void> _reportComment(CommentModel comment) async {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) return;

    const reasons = [
      'スパム',
      '不適切なコンテンツ',
      'ハラスメント・いじめ',
      '著作権侵害',
      'その他',
    ];

    final reason = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 32),
        decoration: BoxDecoration(
          color: const Color(0xFF2D2D2D),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Container(
                width: 40,
                height: 3,
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const Padding(
              padding: EdgeInsets.fromLTRB(24, 16, 24, 4),
              child: Text(
                '通報する理由を選択してください',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.bold),
              ),
            ),
            const Divider(color: Colors.white12, height: 24),
            ...reasons.map((r) => InkWell(
                  onTap: () => Navigator.pop(context, r),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 24, vertical: 14),
                    child: Text(r,
                        style: const TextStyle(
                            color: Colors.white, fontSize: 15)),
                  ),
                )),
            const Divider(color: Colors.white12, height: 1),
            InkWell(
              onTap: () => Navigator.pop(context),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 16),
                alignment: Alignment.center,
                child: const Text('キャンセル',
                    style: TextStyle(
                        color: Colors.white54,
                        fontSize: 15,
                        fontWeight: FontWeight.w500)),
              ),
            ),
          ],
        ),
      ),
    );

    if (reason == null || !mounted) return;

    try {
      await _reportService.reportComment(
        commentId: comment.commentId,
        postId: comment.postId,
        reporterId: currentUser.uid,
        reportedUserId: comment.userId,
        reason: reason,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('通報しました。ご報告ありがとうございます。'),
            duration: Duration(seconds: 3),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('通報に失敗しました。もう一度お試しください。')),
        );
      }
    }
  }

  /// コメントを削除
  Future<void> _deleteComment(CommentModel comment) async {
    final confirmed = await DeleteConfirmDialog.show(
      context,
      title: 'コメントを削除',
      message: 'このコメントを削除しますか？',
    );

    if (confirmed) {
      try {
        await _commentService.deleteComment(
            comment.commentId, comment.postId);

        if (widget.onCommentCountChanged != null) {
          final postDoc = await FirebaseFirestore.instance
              .collection('posts')
              .doc(comment.postId)
              .get();
          final count = postDoc.data()?['commentCount'] ?? 0;
          widget.onCommentCountChanged!(count as int);
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

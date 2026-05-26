import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:provider/provider.dart';
import '../models/post_model.dart';
import '../models/post_theme.dart';
import '../models/comment_model.dart';
import '../models/user_model.dart';
import '../providers/current_user_provider.dart';
import '../services/comment_service.dart';
import '../services/user_service.dart';
import '../utils/context_menu_builder.dart';
import '../widgets/dialogs/dialogs.dart';
import '../services/report_service.dart';
import '../widgets/native_pull_down_button.dart';
import '../widgets/common/app_toast.dart';
import 'other_user_profile_screen.dart';

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
  final UserService _userService = UserService();
  final ReportService _reportService = ReportService();
  final ScrollController _scrollController = ScrollController();
  bool _isPosting = false;

  // @メンション サジェスト用
  List<UserModel> _mentionSuggestions = [];
  bool _showMentionSuggestions = false;

  // メンション候補プール（セッション中キャッシュ）。
  // 初回の @ 入力時に1回だけフォロー/フォロワーを取得して保持する。
  List<UserModel>? _mentionCandidatePool;
  bool _isLoadingMentionPool = false;

  PostTheme get _theme => widget.post.theme;

  String get _currentUsername => context.read<CurrentUserProvider>().username;
  String? get _currentUserIconUrl => context.read<CurrentUserProvider>().iconUrl;
  String? get _currentUserId => context.read<CurrentUserProvider>().uid;

  // onChanged 内での同期 setState は iOS の IME 変換を壊すため、
  // フレーム後に setState をスケジュールするヘルパーを使う
  void _scheduledHideSuggestions() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _showMentionSuggestions) {
        setState(() => _showMentionSuggestions = false);
      }
    });
  }

  /// テキスト変更時に@メンションを検出してサジェストを更新
  void _onCommentChanged(String text) {
    final cursorPos = _commentController.selection.baseOffset;
    if (cursorPos < 0) return;
    final beforeCursor = text.substring(0, cursorPos.clamp(0, text.length));
    final atIndex = beforeCursor.lastIndexOf('@');
    if (atIndex == -1) {
      _scheduledHideSuggestions();
      return;
    }
    // @ の直前がスペースまたは行頭か確認
    if (atIndex > 0 && beforeCursor[atIndex - 1] != ' ') {
      _scheduledHideSuggestions();
      return;
    }
    final query = beforeCursor.substring(atIndex + 1);
    // スペースが入ったらメンション終了
    if (query.contains(' ')) {
      _scheduledHideSuggestions();
      return;
    }
    _fetchMentionSuggestions(query);
  }

  /// メンション候補プールを初回のみ取得してキャッシュする。
  /// セッション中の @ 入力ごとに Firestore を再読しない。
  Future<List<UserModel>> _ensureMentionPool() async {
    if (_mentionCandidatePool != null) return _mentionCandidatePool!;
    if (_isLoadingMentionPool) {
      // ロード中なら完了を待ってから再評価
      while (_isLoadingMentionPool) {
        await Future.delayed(const Duration(milliseconds: 50));
      }
      return _mentionCandidatePool ?? <UserModel>[];
    }
    final uid = _currentUserId;
    if (uid == null) return <UserModel>[];
    _isLoadingMentionPool = true;
    try {
      final results = await Future.wait([
        _userService.getFollowingUsers(uid),
        _userService.getFollowerUsers(uid),
      ]);
      final seen = <String>{};
      final combined = [
        ...results[0],
        ...results[1],
      ].where((u) => u.uid.isNotEmpty && seen.add(u.uid)).toList();
      _mentionCandidatePool = combined;
      return combined;
    } catch (_) {
      return _mentionCandidatePool ?? <UserModel>[];
    } finally {
      _isLoadingMentionPool = false;
    }
  }

  Future<void> _fetchMentionSuggestions(String query) async {
    final uid = _currentUserId;
    if (uid == null) return;
    final pool = await _ensureMentionPool();
    if (!mounted) return;

    final filtered = pool.where((u) {
      final username = (u.username ?? '').toLowerCase();
      return query.isEmpty || username.startsWith(query.toLowerCase());
    }).take(6).toList();

    setState(() {
      _mentionSuggestions = filtered;
      _showMentionSuggestions = filtered.isNotEmpty;
    });
  }

  /// サジェストからユーザーを選択して挿入
  void _selectMentionUser(UserModel user) {
    final text = _commentController.text;
    final cursorPos = _commentController.selection.baseOffset.clamp(0, text.length);
    final beforeCursor = text.substring(0, cursorPos);
    final atIndex = beforeCursor.lastIndexOf('@');
    if (atIndex == -1) return;
    final afterCursor = text.substring(cursorPos);
    final newText = '${text.substring(0, atIndex)}@${user.username} $afterCursor';
    _commentController.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: atIndex + (user.username?.length ?? 0) + 2),
    );
    setState(() {
      _showMentionSuggestions = false;
      _mentionSuggestions = [];
    });
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
        AppToast.show(context, 'コメントの投稿に失敗しました: $e');
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
    // 入力エリアの高さ: topPad(10) + Row(40) + bottomPad(viewInsets.bottom + 26)
    final keyboardHeight = MediaQuery.of(context).viewInsets.bottom;
    final inputAreaHeight = 76.0 + keyboardHeight;

    return Container(
      decoration: BoxDecoration(
        color: _theme.gradientEnd,
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(20),
          topRight: Radius.circular(20),
        ),
      ),
      child: Stack(
        children: [
          // メインレイアウト（サジェストによるレイアウト変化なし）
          Column(
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

              // コメント入力欄（サジェストなし）
              _buildCommentInput(),
            ],
          ),

          // @メンションサジェスト（オーバーレイ、レイアウト非影響）
          if (_showMentionSuggestions && _mentionSuggestions.isNotEmpty)
            Positioned(
              left: 0,
              right: 0,
              bottom: inputAreaHeight,
              child: Container(
                constraints: const BoxConstraints(maxHeight: 200),
                decoration: BoxDecoration(
                  color: _theme.commentButtonColor,
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
                ),
                child: ListView.builder(
                  shrinkWrap: true,
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  itemCount: _mentionSuggestions.length,
                  itemBuilder: (context, index) {
                    final user = _mentionSuggestions[index];
                    return InkWell(
                      onTap: () => _selectMentionUser(user),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        child: Row(
                          children: [
                            Container(
                              width: 32,
                              height: 32,
                              decoration: const BoxDecoration(shape: BoxShape.circle, color: Colors.grey),
                              child: user.profileImageUrl != null && user.profileImageUrl!.isNotEmpty
                                  ? ClipOval(child: _buildUserIcon(user.profileImageUrl!, 32))
                                  : Icon(Icons.person, size: 18, color: _theme.textColor),
                            ),
                            const SizedBox(width: 10),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '@${user.username ?? ''}',
                                  style: TextStyle(
                                    color: _theme.textColor,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                if (user.name != null && user.name!.isNotEmpty)
                                  Text(
                                    user.name!,
                                    style: TextStyle(
                                      color: _theme.textColor.withOpacity(0.6),
                                      fontSize: 11,
                                    ),
                                  ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
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
            child: CupertinoActivityIndicator(
              color: _theme.textColor,
              radius: 14,
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
                // コメント本文（@メンションをハイライト）
                _buildCommentText(comment.content),
              ],
            ),
          ),

          // 3点メニュー（自分→削除、他人→通報）
          NativePullDownButton(
            items: [
              if (isMyComment)
                const NativeMenuItem(id: 'delete', title: '削除', type: 'destructive', icon: 'trash')
              else
                const NativeMenuItem(id: 'report', title: '通報', type: 'destructive', icon: 'exclamationmark.triangle'),
            ],
            onSelected: (id) async {
              if (id == 'delete') _deleteComment(comment);
              if (id == 'report') _reportComment(comment);
            },
            child: SizedBox(
              width: 28,
              height: 28,
              child: Icon(Icons.more_horiz,
                  color: _theme.secondaryTextColor, size: 18),
            ),
          ),
        ],
      ),
    );
  }

  /// コメント入力欄
  Widget _buildCommentInput() {
    // 入力エリア（キーボード分だけ押し上げ、シート本体は動かない）
    return Container(
      padding: EdgeInsets.only(
        left: 19,
        right: 19,
        top: 10,
        bottom: MediaQuery.of(context).viewInsets.bottom + 26,
      ),
      child: Row(
            children: [
              // 現在のユーザーアイコン
              Container(
                width: 40,
                height: 40,
                decoration: const BoxDecoration(shape: BoxShape.circle, color: Colors.grey),
                child: _currentUserIconUrl != null && _currentUserIconUrl!.isNotEmpty
                    ? ClipOval(child: _buildUserIcon(_currentUserIconUrl!, 40))
                    : Icon(Icons.person, size: 24, color: _theme.textColor),
              ),
              const SizedBox(width: 10),

              // 入力フィールド
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
                          cursorColor: Colors.black,
                          style: TextStyle(color: _theme.textColor, fontSize: 13),
                          decoration: InputDecoration(
                            hintText: 'コメントする',
                            hintStyle: TextStyle(
                              color: _theme.textColor.withOpacity(0.6),
                              fontSize: 13,
                            ),
                            border: InputBorder.none,
                            contentPadding: const EdgeInsets.symmetric(horizontal: 13, vertical: 0),
                            isCollapsed: true,
                          ),
                          textInputAction: TextInputAction.send,
                          onSubmitted: (_) => _postComment(),
                          onChanged: _onCommentChanged,
                          contextMenuBuilder: buildTextContextMenu,
                        ),
                      ),
                      // 送信ボタン
                      GestureDetector(
                        onTap: _isPosting ? null : _postComment,
                        child: Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: _isPosting
                              ? CupertinoActivityIndicator(color: _theme.textColor, radius: 10)
                              : Image.asset(
                                  'assets/icons/comment_send_button.png',
                                  width: 24,
                                  height: 24,
                                  color: _theme.textColor.withOpacity(0.6),
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

  /// @メンションをハイライトしたコメント本文
  Widget _buildCommentText(String content) {
    final mentionRegex = RegExp(r'@([a-zA-Z0-9_][a-zA-Z0-9_.]*[a-zA-Z0-9_]|[a-zA-Z0-9_])');
    final spans = <InlineSpan>[];
    int lastEnd = 0;
    for (final match in mentionRegex.allMatches(content)) {
      if (match.start > lastEnd) {
        spans.add(TextSpan(
          text: content.substring(lastEnd, match.start),
          style: TextStyle(color: _theme.textColor, fontSize: 14),
        ));
      }
      final username = match.group(1)!;
      spans.add(WidgetSpan(
        child: GestureDetector(
          onTap: () async {
            try {
              final users = await _userService.searchUsers(query: username, limit: 5);
              final target = users.where((u) => u.username == username).firstOrNull;
              if (target != null && mounted) {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => OtherUserProfileScreen(userId: target.uid),
                  ),
                );
              }
            } catch (_) {}
          },
          child: Text(
            '@$username',
            style: TextStyle(
              color: _theme.textColor,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ));
      lastEnd = match.end;
    }
    if (lastEnd < content.length) {
      spans.add(TextSpan(
        text: content.substring(lastEnd),
        style: TextStyle(color: _theme.textColor, fontSize: 14),
      ));
    }
    return RichText(text: TextSpan(children: spans));
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
        AppToast.show(context, '通報しました。ご報告ありがとうございます。');
      }
    } catch (e) {
      if (mounted) {
        AppToast.show(context, '通報に失敗しました。もう一度お試しください。');
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
          AppToast.show(context, 'コメントの削除に失敗しました: $e');
        }
      }
    }
  }
}

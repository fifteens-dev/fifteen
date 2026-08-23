import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:provider/provider.dart';
import '../models/post_model.dart';
import '../providers/current_user_provider.dart';
import '../providers/post_ui_state.dart';
import '../providers/saved_items_provider.dart';
import '../widgets/post_card.dart';
import '../services/audio_player_service.dart';
import '../services/itunes_search_service.dart';
import '../services/post_service.dart';
import 'card_share_screen.dart';
import '../widgets/common/app_toast.dart';
import '../widgets/dialogs/delete_post_dialog.dart';

/// プロフィールからの投稿一覧画面（インスタ式縦スクロール）
/// 音楽制御はこの画面が一括管理（PostCardのフリップに依存しない）
class ProfilePostsListScreen extends StatefulWidget {
  final List<PostModel> posts;
  final int initialIndex;
  final bool showBackFirst; // true: 裏面から表示
  final bool disableInteractions; // いいね/コメント無効化

  const ProfilePostsListScreen({
    super.key,
    required this.posts,
    required this.initialIndex,
    this.showBackFirst = true,
    this.disableInteractions = false,
  });

  @override
  State<ProfilePostsListScreen> createState() => _ProfilePostsListScreenState();
}

class _ProfilePostsListScreenState extends State<ProfilePostsListScreen> {
  final AudioPlayerService _audioService = AudioPlayerService();
  final ITunesSearchService _itunesService = ITunesSearchService();
  final PostService _postService = PostService();
  final ScrollController _scrollController = ScrollController();
  String? _currentUserId;
  int? _playingIndex;

  String? get _currentUserIconUrl =>
      context.read<CurrentUserProvider>().iconUrl;

  // 各PostCardのGlobalKey（flipToBack呼び出し用）
  final Map<int, GlobalKey<PostCardState>> _cardKeys = {};


  // 投稿リスト（削除対応）
  late List<PostModel> _posts;

  // プレビューURLキャッシュ（インデックス → URL）
  final Map<int, String?> _previewUrlCache = {};
  int? _requestedPageIndex;

  static const double _cardItemHeight = 669.0; // 645 card + 24 bottom padding

  @override
  void initState() {
    super.initState();
    _posts = List.from(widget.posts);
    _currentUserId = FirebaseAuth.instance.currentUser?.uid;

    _scrollController.addListener(_checkCardVisibility);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      // PostUIState に投稿リストをマージ（他画面の楽観的更新は保持される）
      if (mounted && _currentUserId != null) {
        context.read<PostUIState>().mergePosts(
              posts: _posts,
              currentUserId: _currentUserId!,
            );
      }
      // 初期インデックスへスクロール
      if (_scrollController.hasClients && widget.initialIndex > 0) {
        _scrollController.jumpTo(widget.initialIndex * _cardItemHeight);
      }
      // 初期カードの音楽を再生
      _playingIndex = widget.initialIndex;
      _playMusicForPage(widget.initialIndex);
    });
  }

  /// いいねトグル（PostUIState の楽観的更新 + Firestore 書き込み + 失敗時ロールバック）。
  /// HomeScreen._handleLike と同じパターン。
  Future<void> _handleLike(PostModel post) async {
    if (widget.disableInteractions) return;
    final userId = _currentUserId;
    if (userId == null) return;

    final postUIState = context.read<PostUIState>();
    final currentLikeCount =
        postUIState.getLikeCount(post.postId) ?? post.likeCount;
    final wasLiked = postUIState.isLiked(post.postId);

    postUIState.toggleLike(post.postId, currentLikeCount: currentLikeCount);

    try {
      await _postService.toggleLike(postId: post.postId, userId: userId);
    } catch (_) {
      if (mounted) {
        postUIState.revertLikeToggle(
          post.postId,
          originalLikeCount: currentLikeCount,
          wasLiked: wasLiked,
        );
      }
    }
  }

  /// 指定インデックスの音楽を再生する（画面側が音楽を一括管理）
  Future<void> _playMusicForPage(int index) async {
    if (index < 0 || index >= _posts.length) return;
    _requestedPageIndex = index;
    final post = _posts[index];

    String? url = _previewUrlCache[index];

    if (url == null) {
      final result = await _itunesService.getPreviewUrlWithArt(
        trackName: post.track.trackName,
        artistName: post.track.artistName,
      );
      if (!mounted) return;
      if (_requestedPageIndex != index) return;

      if (result != null) {
        url = result['previewUrl'];
        if (url != null) {
          setState(() { _previewUrlCache[index] = url; });
        }
      }
    }

    if (!mounted) return;
    if (_requestedPageIndex != index) return;

    if (url != null && url.isNotEmpty) {
      try {
        await _audioService.playPreview(
          url,
          startFrom: Duration(milliseconds: post.audioStartMs),
          durationSeconds: post.audioDurationSec,
        );
      } catch (_) {}
    }
  }

  /// スクロール時に各カードの可視性を確認し、
  /// 半分以上見えているカードの音楽を再生・画面外に出たら裏面に戻す
  void _checkCardVisibility() {
    if (!mounted) return;
    final screenHeight = MediaQuery.of(context).size.height;

    int? newPlayingIndex;
    double bestVisibleFraction = 0;

    for (final entry in _cardKeys.entries) {
      final index = entry.key;
      final key = entry.value;
      final renderBox = key.currentContext?.findRenderObject() as RenderBox?;
      if (renderBox == null || !renderBox.attached) continue;

      final position = renderBox.localToGlobal(Offset.zero);
      final cardHeight = renderBox.size.height;
      final cardTop = position.dy;
      final cardBottom = cardTop + cardHeight;

      final isOffScreen = cardBottom <= 0 || cardTop >= screenHeight;
      if (isOffScreen) {
        key.currentState?.flipToBack();
        if (_playingIndex == index) {
          _audioService.stop();
          setState(() => _playingIndex = null);
        }
        continue;
      }

      // 画面内に見えている割合を計算
      final visibleTop = cardTop.clamp(0.0, screenHeight.toDouble());
      final visibleBottom = cardBottom.clamp(0.0, screenHeight.toDouble());
      final visibleFraction = (visibleBottom - visibleTop) / cardHeight;

      // 半分以上見えているカードのうち最も多く見えているものを再生候補にする
      if (visibleFraction > 0.5 && visibleFraction > bestVisibleFraction) {
        bestVisibleFraction = visibleFraction;
        newPlayingIndex = index;
      }
    }

    // 再生すべきカードが変わった場合のみ切り替え
    if (newPlayingIndex != null && newPlayingIndex != _playingIndex) {
      // 前のカードを裏面に戻す
      if (_playingIndex != null) {
        _cardKeys[_playingIndex!]?.currentState?.flipToBack();
      }
      _audioService.stop();
      setState(() => _playingIndex = newPlayingIndex);
      _playMusicForPage(newPlayingIndex);
    }
  }

  Future<void> _handleSave(PostModel post) async {
    await SavedItemsProvider.togglePostWithToast(context, post);
  }


  Future<void> _handleDelete(PostModel post) async {
    final confirmed = await showDeletePostConfirmDialog(context);

    if (!confirmed || !mounted) return;

    try {
      await _postService.deletePost(post.postId);
      if (mounted) {
        setState(() {
          _posts.removeWhere((p) => p.postId == post.postId);
        });
        if (_posts.isEmpty) {
          Navigator.pop(context);
        }
      }
    } catch (e) {
      if (mounted) {
        AppToast.show(context, '削除に失敗しました');
      }
    }
  }

  @override
  void dispose() {
    _audioService.stopIfOwner(this);
    _scrollController.removeListener(_checkCardVisibility);
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final topPadding = MediaQuery.of(context).padding.top;
    final headerAreaHeight = topPadding + 16.0 + 40.0 + 8.0; // status + top + button + gap

    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      body: Stack(
        children: [
          // インスタ式ListView
          NotificationListener<ScrollNotification>(
            onNotification: (notification) {
              _checkCardVisibility();
              return false;
            },
            child: Consumer<PostUIState>(
              builder: (context, postUIState, _) => ListView.builder(
                controller: _scrollController,
                padding: EdgeInsets.only(top: headerAreaHeight, bottom: 80),
                itemCount: _posts.length,
                itemBuilder: (context, index) {
                  final basePost = _posts[index];
                  // PostUIState の楽観的更新を反映した PostModel を取得
                  final post = postUIState.getDisplayPost(
                    basePost,
                    currentUserId: _currentUserId,
                    currentUserIconUrl: _currentUserIconUrl,
                  );
                  _cardKeys.putIfAbsent(index, () => GlobalKey<PostCardState>());
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 24),
                    child: Center(
                      child: PostCard(
                        key: _cardKeys[index],
                        post: post,
                        currentUserId: _currentUserId,
                        currentUserIconUrl: _currentUserIconUrl,
                        audioService: _audioService,
                        startFromBack: true, // 常に裏面スタート
                        audioManagedExternally: true,
                        externalPreviewUrl: _previewUrlCache[index],
                        disableInteractions: widget.disableInteractions,
                        onPlayStarted: () => setState(() { _playingIndex = index; }),
                        isSaved: context.watch<SavedItemsProvider>().isPostOrTrackSaved(post),
                        onLike: () => _handleLike(basePost),
                        onReaction: _currentUserId == null
                            ? null
                            : (emoji) => PostUIState.handleReaction(
                                  postId: basePost.postId,
                                  emoji: emoji,
                                  userId: _currentUserId!,
                                  postService: _postService,
                                ),
                        onAdd: () => _handleSave(basePost),
                        onDelete: (_currentUserId != null && post.userId == _currentUserId)
                            ? () => _handleDelete(basePost)
                            : null,
                        onShare: () => showCardShareSheet(
                          context,
                          post: post,
                          currentUserId: _currentUserId,
                          currentUserIconUrl: _currentUserIconUrl,
                          isSaved: context.watch<SavedItemsProvider>().isPostOrTrackSaved(post),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
          // 投稿タイトル（中央上部）
          Positioned(
            top: topPadding + 16,
            left: 0,
            right: 0,
            child: const SizedBox(
              height: 40,
              child: Center(
                child: Text(
                  '投稿',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          ),
          // 閉じるボタン（左上）
          Positioned(
            top: topPadding + 16,
            left: 16,
            child: GestureDetector(
              onTap: () {
                _audioService.stop();
                Navigator.pop(context);
              },
              child: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.5),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.arrow_back_ios_new,
                  color: Colors.white,
                  size: 20,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

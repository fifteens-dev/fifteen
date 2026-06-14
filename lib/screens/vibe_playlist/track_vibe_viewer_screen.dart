import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../constants/app_colors.dart';
import '../../models/post_model.dart';
import '../../models/track_model.dart';
import '../../models/vibe_ranking_item.dart';
import '../../providers/post_ui_state.dart';
import '../../services/audio_player_service.dart';
import '../../services/itunes_search_service.dart';
import '../../services/post_service.dart';
import '../../providers/saved_items_provider.dart';
import '../comment_screen.dart';
import '../post_preview_screen.dart';
import 'widgets/vibe_post_card.dart';

/// 1楽曲の投稿だけをVibeプレイリスト形式（VibePostCard全画面PageView）で閲覧する画面。
///
/// VibePlaylistScreen の「投稿タブ」のレイアウト・操作・音楽再生ロジックを抽出。
/// - 縦スワイプで全画面PageView
/// - 各ページで自動的に楽曲を再生（プリロード対応）
/// - いいね・コメント・保存
/// - カーソルバータップで閉じる、音符ボタンでこの楽曲で投稿フローへ
class TrackVibeViewerScreen extends StatefulWidget {
  final TrackModel track;
  final List<PostModel> posts;
  final String currentUserId;
  final int initialIndex;

  /// Vibeトピック紐付け（あれば投稿作成時にVibe投稿として記録）
  final String? vibeTopicId;
  final String? vibeTopicTitle;

  const TrackVibeViewerScreen({
    super.key,
    required this.track,
    required this.posts,
    required this.currentUserId,
    this.initialIndex = 0,
    this.vibeTopicId,
    this.vibeTopicTitle,
  });

  @override
  State<TrackVibeViewerScreen> createState() => _TrackVibeViewerScreenState();
}

class _TrackVibeViewerScreenState extends State<TrackVibeViewerScreen> {
  // Figma: card 814px + gap 8px = page 822px
  // 画面高さに対する比率で viewportFraction を計算し、機種問わずカード高さを揃え、
  // 次の投稿が下にちょっと見える状態を作る。
  // build() で MediaQuery にアクセスしてから遅延初期化する。
  PageController? _pageController;
  final AudioPlayerService _audioService = AudioPlayerService();
  final ITunesSearchService _itunesService = ITunesSearchService();
  final PostService _postService = PostService();

  late int _currentPage;
  final Map<int, String?> _previewUrlCache = {};
  // いいね状態は PostUIState に集約（旧 _likeCountCache / _isLikedCache は撤去）

  @override
  void initState() {
    super.initState();
    final maxIndex = widget.posts.isEmpty ? 0 : widget.posts.length - 1;
    _currentPage = widget.initialIndex.clamp(0, maxIndex);
    if (widget.posts.isNotEmpty) {
      _playMusicForPage(_currentPage);
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // PostUIState にマージ（他画面の楽観的更新は保持される）
      if (mounted) {
        context.read<PostUIState>().mergePosts(
              posts: widget.posts,
              currentUserId: widget.currentUserId,
            );
      }
    });
  }

  @override
  void dispose() {
    _audioService.stopIfOwner(this);
    _pageController?.dispose();
    super.dispose();
  }

  Future<void> _playMusicForPage(int index) async {
    if (index < 0 || index >= widget.posts.length) return;
    final post = widget.posts[index];

    if (!_previewUrlCache.containsKey(index)) {
      final url = await _itunesService.getPreviewUrl(
        trackName: post.track.trackName,
        artistName: post.track.artistName,
      );
      _previewUrlCache[index] = url;
    }

    final url = _previewUrlCache[index];
    if (url != null && mounted) {
      await _audioService.stop();
      if (!mounted) return;
      await _audioService.playPreview(
        url,
        startFrom: Duration(milliseconds: post.audioStartMs),
      );
    }
    _preloadNeighborAudio(index);
  }

  void _preloadNeighborAudio(int currentIndex) {
    final next = currentIndex + 1;
    if (next >= widget.posts.length) return;
    final url = _previewUrlCache[next];
    if (url == null || url.isEmpty) {
      final nextPost = widget.posts[next];
      unawaited(_itunesService
          .getPreviewUrl(
        trackName: nextPost.track.trackName,
        artistName: nextPost.track.artistName,
      )
          .then((u) {
        if (!mounted) return;
        _previewUrlCache[next] = u;
        if (u != null && u.isNotEmpty) {
          _audioService.preload(u);
        }
      }));
      return;
    }
    _audioService.preload(url);
  }

  void _onPageChanged(int index) {
    setState(() => _currentPage = index);
    _playMusicForPage(index);
  }

  Future<void> _handleLike(PostModel post) async {
    HapticFeedback.lightImpact();
    final postUIState = context.read<PostUIState>();
    final currentLikeCount =
        postUIState.getLikeCount(post.postId) ?? post.likeCount;
    final wasLiked = postUIState.isLiked(post.postId);
    postUIState.toggleLike(post.postId, currentLikeCount: currentLikeCount);
    try {
      await _postService.toggleLike(
        postId: post.postId,
        userId: widget.currentUserId,
      );
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

  Future<void> _handleSave(PostModel post) async {
    HapticFeedback.lightImpact();
    await SavedItemsProvider.togglePostWithToast(context, post);
  }

  Future<void> _handleComment(PostModel post) async {
    _audioService.stop();
    await CommentScreen.show(context, post: post);
  }

  /// この楽曲で投稿フローへ。Vibeトピックが渡されていればVibe投稿として記録される。
  Future<void> _navigateToPostPreview() async {
    _audioService.stop();
    if (!mounted) return;
    await Navigator.push(
      context,
      PageRouteBuilder(
        pageBuilder: (_, __, ___) => PostPreviewScreen(
          track: widget.track,
          isVibe: widget.vibeTopicId != null,
          vibeTopicId: widget.vibeTopicId,
          vibeTopicTitle: widget.vibeTopicTitle,
          fromVibePlaylist: widget.vibeTopicId != null,
        ),
        transitionsBuilder: (context, animation, _, child) {
          final tween = Tween(begin: const Offset(0, 1), end: Offset.zero)
              .chain(CurveTween(curve: Curves.easeOutCubic));
          return SlideTransition(
              position: animation.drive(tween), child: child);
        },
        transitionDuration: const Duration(milliseconds: 350),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final topPadding = MediaQuery.of(context).padding.top;
    final screenH = MediaQuery.of(context).size.height;
    // PageView の viewportFraction は 0..1 の範囲が安全。
    // 小型端末（screenH < 822）では 1.0 にクランプして崩れを防ぐ。
    final fraction =
        screenH > 0 ? (822.0 / screenH).clamp(0.5, 1.0) : 1.0;
    _pageController ??= PageController(
      initialPage: _currentPage,
      viewportFraction: fraction,
    );

    return Scaffold(
      backgroundColor: AppColors.background,
      body: Stack(
        children: [
          if (widget.posts.isEmpty)
            const Center(
              child: Text(
                'まだこの曲で投稿された写真はありません',
                style: TextStyle(color: Colors.white, fontSize: 14),
              ),
            )
          else
            PageView.builder(
              scrollDirection: Axis.vertical,
              controller: _pageController!,
              pageSnapping: true,
              padEnds: false,
              physics: const FastSnapPageScrollPhysics(),
              itemCount: widget.posts.length,
              onPageChanged: _onPageChanged,
              itemBuilder: (context, index) {
                final post = widget.posts[index];
                return _buildVibePostCard(post);
              },
            ),

          // フローティングヘッダー
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: SizedBox(
                  height: 40,
                  child: Row(
                    children: [
                      GestureDetector(
                        onTap: () => Navigator.of(context).pop(),
                        behavior: HitTestBehavior.opaque,
                        child: const SizedBox(
                          width: 44,
                          height: 44,
                          child: Icon(
                            Icons.chevron_left,
                            color: Colors.white,
                            size: 28,
                          ),
                        ),
                      ),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Text(
                              widget.track.trackName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            Text(
                              widget.track.artistName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Color(0xFFB7BCC0),
                                fontSize: 10,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 44),
                    ],
                  ),
                ),
              ),
            ),
          ),
          // 上部の暗いグラデーション（テキスト可読性のため）
          IgnorePointer(
            child: Container(
              height: topPadding + 80,
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0x66000000), Colors.transparent],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildVibePostCard(PostModel post) {
    final postUIState = context.watch<PostUIState>();
    final isLiked = postUIState.isLiked(post.postId) ||
        (postUIState.getLikeCount(post.postId) == null &&
            post.isLikedBy(widget.currentUserId));
    final likeCount = postUIState.getLikeCount(post.postId) ?? post.likeCount;
    final isSaved =
        context.watch<SavedItemsProvider>().isPostOrTrackSaved(post);
    // 単一曲表示なのでランキング情報は空のものを渡す
    final rankingItem =
        VibeRankingItem(rank: 0, track: post.track, postCount: 0);
    return VibePostCard(
      post: post,
      rankingItem: rankingItem,
      isLiked: isLiked,
      likeCount: likeCount,
      isSaved: isSaved,
      onLikeTap: () => _handleLike(post),
      onCommentTap: () => _handleComment(post),
      onSaveTap: () => _handleSave(post),
      onCuratorBarTap: () => Navigator.of(context).pop(),
      onPostNoteTap: _navigateToPostPreview,
    );
  }
}

/// VibePlaylistScreen と同じスナップ速度のページスクロール physics。
/// 既定: mass=0.5, stiffness=100, ratio=1.1 → stiffness=400 に引き上げ。
class FastSnapPageScrollPhysics extends PageScrollPhysics {
  const FastSnapPageScrollPhysics({super.parent});

  @override
  FastSnapPageScrollPhysics applyTo(ScrollPhysics? ancestor) {
    return FastSnapPageScrollPhysics(parent: buildParent(ancestor));
  }

  @override
  SpringDescription get spring => SpringDescription.withDampingRatio(
        mass: 0.5,
        stiffness: 400,
        ratio: 1.1,
      );
}

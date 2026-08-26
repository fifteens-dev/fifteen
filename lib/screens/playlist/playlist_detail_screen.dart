import 'dart:async';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../models/post_model.dart';
import '../../models/playlist_model.dart';
import '../../services/post_service.dart';
import '../../services/playlist_service.dart';
import '../../services/audio_player_service.dart';
import '../../services/itunes_search_service.dart';
import '../../providers/post_ui_state.dart';
import '../../providers/saved_items_provider.dart';
import '../../utils/album_image.dart';
import '../comment_screen.dart';
import '../vibe_playlist/widgets/vibe_post_card.dart';
import '../../widgets/native_pull_down_button.dart';

/// My Playlist を開く画面。Vibe プレイリストのカード表示（縦フルスクリーンの
/// ページャー + VibePostCard）を流用しつつ、個人プレイリスト向けに簡略化。
/// 右上の 3点メニューから「編集」（後日）/「削除」が可能。
class PlaylistDetailScreen extends StatefulWidget {
  final PlaylistModel playlist;
  final String currentUserId;

  const PlaylistDetailScreen({
    super.key,
    required this.playlist,
    required this.currentUserId,
  });

  /// 戻り値: 削除された場合 true（呼び出し側で一覧を更新する）。
  static Future<bool?> push(
    BuildContext context, {
    required PlaylistModel playlist,
    required String currentUserId,
  }) {
    return Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => PlaylistDetailScreen(
          playlist: playlist,
          currentUserId: currentUserId,
        ),
      ),
    );
  }

  @override
  State<PlaylistDetailScreen> createState() => _PlaylistDetailScreenState();
}

class _PlaylistDetailScreenState extends State<PlaylistDetailScreen> {
  final PostService _postService = PostService();
  final PlaylistService _playlistService = PlaylistService();
  final AudioPlayerService _audioService = AudioPlayerService();
  final ITunesSearchService _itunesService = ITunesSearchService();

  PageController? _pageController;
  // 横タブ（0=投稿の縦カード / 1=曲リスト）。Vibe プレイリストと同じ右スライド構成。
  final PageController _tabPageController = PageController();
  int _selectedTab = 0;
  List<PostModel>? _posts;
  bool _isLoading = true;
  int _currentPage = 0;

  // 再生レース対策（Vibe 画面と同じ世代カウンタ方式）。
  final Map<int, String?> _previewUrlCache = {};
  int _playGeneration = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _audioService.stopIfOwner(this);
    _pageController?.dispose();
    _tabPageController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final posts = await _postService.getPostsByIds(widget.playlist.postIds);
    if (!mounted) return;
    setState(() {
      _posts = posts;
      _isLoading = false;
    });
    if (posts.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _playMusicForPage(0));
    }
  }

  Future<void> _playMusicForPage(int index) async {
    final posts = _posts;
    if (posts == null || index >= posts.length) return;
    final myGen = ++_playGeneration;
    final post = posts[index];
    if (!_previewUrlCache.containsKey(index)) {
      final url = await _itunesService.getPreviewUrl(
        trackName: post.track.trackName,
        artistName: post.track.artistName,
      );
      if (myGen != _playGeneration || !mounted) return;
      _previewUrlCache[index] = url;
    }
    final url = _previewUrlCache[index];
    if (url != null && url.isNotEmpty && mounted) {
      await _audioService.stop();
      if (myGen != _playGeneration || !mounted) return;
      await _audioService.playPreview(
        url,
        startFrom: Duration(milliseconds: post.audioStartMs),
        owner: this,
      );
    }
  }

  void _onPageChanged(int index) {
    _currentPage = index;
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
          postId: post.postId, userId: widget.currentUserId);
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

  Future<void> _handleComment(PostModel post) async {
    _audioService.stop();
    await CommentScreen.show(context, post: post);
  }

  Future<void> _handleSave(PostModel post) async {
    HapticFeedback.lightImpact();
    await SavedItemsProvider.togglePostWithToast(context, post);
  }

  Future<void> _confirmDelete() async {
    final ok = await showCupertinoDialog<bool>(
      context: context,
      builder: (ctx) => CupertinoAlertDialog(
        title: const Text('プレイリストを削除'),
        content: Text('「${widget.playlist.name}」を削除しますか？'),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('キャンセル'),
          ),
          CupertinoDialogAction(
            isDestructiveAction: true,
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('削除'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await _playlistService.deletePlaylist(widget.playlist.id);
      if (mounted) Navigator.pop(context, true); // 削除完了を呼び出し側へ
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('削除に失敗しました')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final posts = _posts;
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          Positioned.fill(
            child: _isLoading
                ? const Center(
                    child: CupertinoActivityIndicator(
                        color: Colors.white, radius: 14))
                : (posts == null || posts.isEmpty)
                    ? const Center(
                        child: Text('このプレイリストには曲がありません',
                            style: TextStyle(
                                color: Colors.white54, fontSize: 14)))
                    // 横スライドで「投稿(縦カード)」⇔「曲リスト」を切り替え（Vibe と同じ）。
                    : PageView(
                        controller: _tabPageController,
                        onPageChanged: (index) {
                          if (index == 1) {
                            _audioService.stop();
                          } else {
                            _playMusicForPage(_currentPage);
                          }
                          setState(() => _selectedTab = index);
                        },
                        children: [
                          _buildPostsPager(posts),
                          _buildTracksTab(posts),
                        ],
                      ),
          ),
          // ヘッダー（戻る + プレイリスト名 + 3点 + タブ）
          Positioned(top: 0, left: 0, right: 0, child: _buildHeader()),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    final topPad = MediaQuery.of(context).padding.top;
    return Container(
      padding: EdgeInsets.only(top: topPad + 6, left: 8, right: 8, bottom: 6),
      color: _selectedTab == 1 ? Colors.black : Colors.transparent,
      child: Column(
        children: [
          Row(
            children: [
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => Navigator.pop(context),
                child: const SizedBox(
                  width: 44,
                  height: 44,
                  child: Icon(CupertinoIcons.chevron_left,
                      color: Colors.white, size: 24),
                ),
              ),
              Expanded(
                child: Text(
                  widget.playlist.name,
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              // 3点メニュー（iOS ネイティブ UIMenu = ガラスの吹き出し）
              NativePullDownButton(
                items: const [
                  NativeMenuItem(id: 'edit', title: '編集', icon: 'pencil'),
                  NativeMenuItem(
                      id: 'delete',
                      title: '削除',
                      type: 'destructive',
                      icon: 'trash'),
                ],
                onSelected: (id) async {
                  if (id == 'edit') {
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('編集機能は準備中です')),
                      );
                    }
                  } else if (id == 'delete') {
                    await _confirmDelete();
                  }
                },
                child: const SizedBox(
                  width: 44,
                  height: 44,
                  child: Icon(Icons.more_horiz, color: Colors.white, size: 26),
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          // タブ（投稿 / 曲リスト）
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _tabLabel('投稿', 0),
              const SizedBox(width: 28),
              _tabLabel('曲リスト', 1),
            ],
          ),
        ],
      ),
    );
  }

  Widget _tabLabel(String text, int index) {
    final active = _selectedTab == index;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => _tabPageController.animateToPage(
        index,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            text,
            style: TextStyle(
              color: active ? Colors.white : Colors.white54,
              fontSize: 14,
              fontWeight: active ? FontWeight.w700 : FontWeight.w500,
            ),
          ),
          const SizedBox(height: 4),
          Container(
            width: 22,
            height: 2,
            decoration: BoxDecoration(
              color: active ? Colors.white : Colors.transparent,
              borderRadius: BorderRadius.circular(1),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPostsPager(List<PostModel> posts) {
    // 1 ページにカード 1 枚 + 上下に隣カードが少し覗く（Vibe 画面と同じ）。
    final screenH = MediaQuery.of(context).size.height;
    const pitch = 814.0 + 8.0;
    final fraction = (pitch / screenH).clamp(0.1, 1.0);
    _pageController ??= PageController(viewportFraction: fraction);

    return PageView.builder(
      scrollDirection: Axis.vertical,
      controller: _pageController!,
      pageSnapping: true,
      padEnds: false,
      itemCount: posts.length,
      onPageChanged: _onPageChanged,
      itemBuilder: (context, index) => _buildCard(posts[index]),
    );
  }

  /// 曲リストタブ（右スライド）。プレイリスト向けに調整:
  /// 2×2 サマリー画像 + プレイリスト名 + 「n曲」 + 曲リスト（ジャケット/曲名/保存）。
  Widget _buildTracksTab(List<PostModel> posts) {
    final topPad = MediaQuery.of(context).padding.top;
    final summary = posts
        .map((p) => (p.photoUrl?.isNotEmpty ?? false)
            ? p.photoUrl!
            : p.track.albumImageUrl)
        .where((u) => u.isNotEmpty)
        .take(4)
        .toList();
    return ListView(
      padding: EdgeInsets.only(top: topPad + 88, left: 16, right: 16, bottom: 40),
      children: [
        // 2×2 サマリー
        Center(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: SizedBox(
              width: 220,
              height: 146,
              child: _summaryGrid(summary),
            ),
          ),
        ),
        const SizedBox(height: 16),
        Text(
          widget.playlist.name,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 20,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          '${posts.length}曲',
          textAlign: TextAlign.center,
          style: const TextStyle(color: Color(0xFFA8A8A8), fontSize: 12),
        ),
        const SizedBox(height: 18),
        for (int i = 0; i < posts.length; i++) _buildSongRow(posts[i], i),
      ],
    );
  }

  Widget _buildSongRow(PostModel post, int index) {
    final isSaved =
        context.watch<SavedItemsProvider>().isPostOrTrackSaved(post);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        // その曲の投稿へジャンプ（投稿タブへ切替 + 該当ページへ）。
        _tabPageController.animateToPage(0,
            duration: const Duration(milliseconds: 300), curve: Curves.easeInOut);
        _pageController?.jumpToPage(index);
      },
      child: Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: SizedBox(
                width: 48,
                height: 48,
                child: post.track.albumImageUrl.isNotEmpty
                    ? Image(
                        image: albumImageProvider(post.track.albumImageUrl),
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) =>
                            Container(color: const Color(0xFF2A2A2A)),
                      )
                    : Container(color: const Color(0xFF2A2A2A)),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    post.track.trackName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    post.track.artistName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        color: Color(0xFF9E9E9E), fontSize: 12),
                  ),
                ],
              ),
            ),
            // 保存マーク（既存の VibeSongListItem と同じ: 未保存=円に＋、保存済み=薄緑丸＋チェック）
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => _handleSave(post),
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: isSaved
                    ? Stack(
                        alignment: Alignment.center,
                        children: [
                          Container(
                            width: 22,
                            height: 22,
                            decoration: const BoxDecoration(
                              color: Colors.lightGreen,
                              shape: BoxShape.circle,
                            ),
                          ),
                          Icon(Icons.check, size: 15, color: Colors.grey[700]),
                        ],
                      )
                    : const Icon(
                        Icons.add_circle_outline,
                        color: Colors.white,
                        size: 22,
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 2×2 サマリー画像（不足分はダークで埋める）。
  Widget _summaryGrid(List<String> urls) {
    Widget cell(int i) {
      if (i >= urls.length) {
        return const ColoredBox(color: Color(0xFF1E1E1E));
      }
      return Image(
        image: albumImageProvider(urls[i]),
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) =>
            const ColoredBox(color: Color(0xFF2A2A2A)),
      );
    }

    return Column(
      children: [
        Expanded(
          child: Row(children: [
            Expanded(child: cell(0)),
            const SizedBox(width: 2),
            Expanded(child: cell(1)),
          ]),
        ),
        const SizedBox(height: 2),
        Expanded(
          child: Row(children: [
            Expanded(child: cell(2)),
            const SizedBox(width: 2),
            Expanded(child: cell(3)),
          ]),
        ),
      ],
    );
  }

  Widget _buildCard(PostModel post) {
    final postUIState = context.watch<PostUIState>();
    final isLiked = postUIState.isLiked(post.postId) ||
        (postUIState.getLikeCount(post.postId) == null &&
            post.isLikedBy(widget.currentUserId));
    final likeCount = postUIState.getLikeCount(post.postId) ?? post.likeCount;
    final isSaved =
        context.watch<SavedItemsProvider>().isPostOrTrackSaved(post);
    const cardWidth = 402.0;
    const cardHeight = 814.0;
    return Center(
      child: ClipRect(
        child: OverflowBox(
          alignment: Alignment.center,
          minWidth: cardWidth,
          maxWidth: cardWidth,
          minHeight: cardHeight,
          maxHeight: cardHeight,
          child: VibePostCard(
            post: post,
            rankingItem: null, // 個人プレイリストはランキングなし
            isLiked: isLiked,
            likeCount: likeCount,
            isSaved: isSaved,
            onLikeTap: () => _handleLike(post),
            onCommentTap: () => _handleComment(post),
            onSaveTap: () => _handleSave(post),
            onCuratorBarTap: () {},
            onPostNoteTap: () {},
          ),
        ),
      ),
    );
  }
}

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
import '../comment_screen.dart';
import '../vibe_playlist/widgets/vibe_post_card.dart';

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

  // ── 3点メニュー（編集 / 削除）─────────────────────────────
  Future<void> _showMenu() async {
    final action = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: const Color(0xFF1C1C1E),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _menuItem(ctx, '編集', Icons.edit_outlined, 'edit'),
            const Divider(height: 1, color: Color(0xFF2C2C2E)),
            _menuItem(ctx, '削除', Icons.delete_outline, 'delete',
                danger: true),
          ],
        ),
      ),
    );
    if (action == 'edit') {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('編集機能は準備中です')),
        );
      }
    } else if (action == 'delete') {
      await _confirmDelete();
    }
  }

  Widget _menuItem(BuildContext ctx, String label, IconData icon, String value,
      {bool danger = false}) {
    final color = danger ? const Color(0xFFFF453A) : Colors.white;
    return ListTile(
      leading: Icon(icon, color: color),
      title: Text(label, style: TextStyle(color: color, fontSize: 16)),
      onTap: () => Navigator.pop(ctx, value),
    );
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
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          Positioned.fill(child: _buildBody()),
          // ヘッダー（戻る + プレイリスト名 + 3点）
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: _buildHeader(),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    final topPad = MediaQuery.of(context).padding.top;
    return Container(
      padding: EdgeInsets.only(top: topPad + 6, left: 8, right: 8, bottom: 6),
      child: Row(
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
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _showMenu,
            child: const SizedBox(
              width: 44,
              height: 44,
              child: Icon(Icons.more_horiz, color: Colors.white, size: 26),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(
        child: CupertinoActivityIndicator(color: Colors.white, radius: 14),
      );
    }
    final posts = _posts;
    if (posts == null || posts.isEmpty) {
      return const Center(
        child: Text('このプレイリストには曲がありません',
            style: TextStyle(color: Colors.white54, fontSize: 14)),
      );
    }

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

import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../models/post_model.dart';
import '../../../models/vibe_ranking_item.dart';
import '../../../providers/saved_items_provider.dart';
import '../../../services/post_service.dart';
import '../../artist_profile_screen.dart';
import '../../post_detail_screen.dart';

/// 曲行タップで表示されるアクションシート（Figma 3870:6805）
/// - 上部: 曲情報バー（アルバム / 曲名 / アーティスト / Vibe追加カウント / +保存）
/// - 中段: アクションボタン2つ
/// - 下部: その楽曲を使った投稿写真の3列グリッド（スクロール・ページネーション）
class SongActionSheet extends StatefulWidget {
  final VibeRankingItem item;
  final VoidCallback onPlayFull;
  final VoidCallback onAddToVibe;
  final VoidCallback onSave;

  const SongActionSheet({
    super.key,
    required this.item,
    required this.onPlayFull,
    required this.onAddToVibe,
    required this.onSave,
  });

  @override
  State<SongActionSheet> createState() => _SongActionSheetState();
}

class _SongActionSheetState extends State<SongActionSheet> {
  final PostService _postService = PostService();
  final ScrollController _scrollController = ScrollController();

  List<PostModel> _posts = [];
  DocumentSnapshot? _lastDoc;
  bool _hasMore = true;
  bool _isLoading = true;
  bool _isLoadingMore = false;

  static const int _initialLimit = 12;
  static const int _moreLimit = 12;
  static const double _scrollThreshold = 300;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _loadInitial();
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final pos = _scrollController.position;
    if (pos.pixels >= pos.maxScrollExtent - _scrollThreshold) {
      _loadMore();
    }
  }

  Future<void> _loadInitial() async {
    final trackId = widget.item.track.trackId;
    if (trackId.isEmpty) {
      if (mounted) setState(() => _isLoading = false);
      return;
    }
    final result = await _postService.getPostsByTrackIdPaged(
      trackId,
      limit: _initialLimit,
    );
    if (!mounted) return;
    setState(() {
      _posts = result.posts
          .where((p) => (p.photoUrl ?? '').startsWith('http'))
          .toList();
      _lastDoc = result.lastDoc;
      _hasMore = result.hasMore;
      _isLoading = false;
    });
  }

  Future<void> _loadMore() async {
    if (_isLoadingMore || !_hasMore || _lastDoc == null) return;
    final trackId = widget.item.track.trackId;
    if (trackId.isEmpty) return;

    setState(() => _isLoadingMore = true);
    final result = await _postService.getPostsByTrackIdPaged(
      trackId,
      limit: _moreLimit,
      startAfter: _lastDoc,
    );
    if (!mounted) return;
    setState(() {
      _posts.addAll(
        result.posts.where((p) => (p.photoUrl ?? '').startsWith('http')),
      );
      _lastDoc = result.lastDoc;
      _hasMore = result.hasMore;
      _isLoadingMore = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final bottomPadding = MediaQuery.of(context).padding.bottom;
    final screenH = MediaQuery.of(context).size.height;
    final modalHeight = screenH * 0.85;

    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF313131),
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(11),
          topRight: Radius.circular(11),
        ),
      ),
      child: SizedBox(
        height: modalHeight,
        child: Column(
          children: [
            SizedBox(
              height: 153,
              child: _buildHeader(),
            ),
            Expanded(
              child: _buildPhotoGrid(bottomPadding),
            ),
          ],
        ),
      ),
    );
  }

  void _openPost(PostModel post) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => PostDetailScreen(
        post: post,
        currentUserId: uid,
        alwaysShowBack: true,
      ),
    ));
  }

  Widget _buildPhotoGrid(double bottomPadding) {
    if (_isLoading) {
      return const Center(
        child: CupertinoActivityIndicator(color: Colors.white, radius: 12),
      );
    }
    if (_posts.isEmpty) {
      return Padding(
        padding: EdgeInsets.only(bottom: bottomPadding),
        child: const Center(
          child: Text(
            'まだこの曲で投稿された写真はありません',
            style: TextStyle(color: Color(0xFF858585), fontSize: 12),
          ),
        ),
      );
    }
    return GridView.builder(
      controller: _scrollController,
      padding: EdgeInsets.only(bottom: bottomPadding + (_isLoadingMore ? 40 : 0)),
      physics: const ClampingScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        mainAxisSpacing: 1,
        crossAxisSpacing: 1,
        childAspectRatio: 133 / 178,
      ),
      itemCount: _posts.length + (_isLoadingMore ? 3 : 0),
      itemBuilder: (context, index) {
        if (index >= _posts.length) {
          return Container(color: const Color(0xFF1F1F1F));
        }
        final post = _posts[index];
        return GestureDetector(
          onTap: () => _openPost(post),
          child: CachedNetworkImage(
            imageUrl: post.photoUrl!,
            fit: BoxFit.cover,
            errorWidget: (_, __, ___) => Container(color: Colors.grey[900]),
          ),
        );
      },
    );
  }

  Widget _buildHeader() {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        // ドラッグハンドル
        Positioned(
          top: 9,
          left: 0,
          right: 0,
          child: Center(
            child: Container(
              width: 44,
              height: 4,
              decoration: BoxDecoration(
                color: const Color(0xFF6E6E6E),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
        ),
        // 曲情報バー
        Positioned(
          left: 14,
          top: 20,
          right: 14,
          height: 72,
          child: Container(
            decoration: BoxDecoration(
              color: const Color(0xFF1F1F1F),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Stack(
              children: [
                Positioned(
                  left: 8,
                  top: 8,
                  width: 56,
                  height: 56,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(7),
                    child: CachedNetworkImage(
                      imageUrl: widget.item.track.albumImageUrl,
                      fit: BoxFit.cover,
                      errorWidget: (_, __, ___) => Container(
                        color: Colors.grey[800],
                        child: const Icon(Icons.album, color: Colors.white54),
                      ),
                    ),
                  ),
                ),
                Positioned(
                  left: 72,
                  top: 13,
                  right: 60,
                  child: Text(
                    widget.item.track.trackName,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                      height: 1.0,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Positioned(
                  left: 72,
                  top: 29,
                  right: 60,
                  child: GestureDetector(
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => ArtistProfileScreen(
                          artistName: widget.item.track.artistName,
                          spotifyArtistId: widget.item.track.spotifyArtistId,
                        ),
                      ),
                    ),
                    child: Text(
                      widget.item.track.artistName,
                      style: const TextStyle(
                        fontSize: 11,
                        color: Colors.white,
                        height: 1.0,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
                Positioned(
                  left: 72,
                  top: 46,
                  right: 60,
                  child: Text(
                    '🔥${widget.item.postCount}人がVibeにこの曲を追加',
                    style: const TextStyle(
                      fontSize: 11,
                      color: Color(0xFF858585),
                      letterSpacing: -0.22,
                      height: 1.0,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Positioned(
                  right: 13,
                  top: 19,
                  width: 34,
                  height: 34,
                  child: GestureDetector(
                    onTap: widget.onSave,
                    behavior: HitTestBehavior.opaque,
                    child: context.watch<SavedItemsProvider>().isTrackSaved(widget.item.track.trackId)
                        ? Stack(
                            alignment: Alignment.center,
                            children: [
                              Container(
                                width: 30,
                                height: 30,
                                decoration: const BoxDecoration(
                                  color: Colors.lightGreen,
                                  shape: BoxShape.circle,
                                ),
                              ),
                              Icon(Icons.check,
                                  size: 18, color: Colors.grey[700]),
                            ],
                          )
                        : const Icon(
                            Icons.add_circle_outline,
                            color: Colors.white,
                            size: 30,
                          ),
                  ),
                ),
              ],
            ),
          ),
        ),
        // 「楽曲をフルで聴く」
        Positioned(
          left: 14,
          top: 102,
          width: 181,
          height: 40,
          child: GestureDetector(
            onTap: widget.onPlayFull,
            child: Container(
              decoration: BoxDecoration(
                color: const Color(0xFF454545),
                borderRadius: BorderRadius.circular(30),
              ),
              alignment: Alignment.center,
              child: const Text(
                '楽曲をフルで聴く',
                style: TextStyle(
                  fontSize: 13,
                  color: Colors.white,
                  letterSpacing: -0.26,
                  height: 1.0,
                ),
              ),
            ),
          ),
        ),
        // 「楽曲をVibeに追加」
        Positioned(
          left: 207,
          top: 103,
          width: 181,
          height: 40,
          child: GestureDetector(
            onTap: widget.onAddToVibe,
            child: Container(
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF1937EF), Color(0xFFFE1F56)],
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                ),
                borderRadius: BorderRadius.circular(30),
              ),
              child: Stack(
                children: [
                  Positioned(
                    left: 23,
                    top: 8,
                    width: 24,
                    height: 24,
                    child: Center(
                      child: Image.asset(
                        'assets/icons/Vibe.png',
                        width: 19,
                        height: 19,
                        fit: BoxFit.contain,
                        errorBuilder: (_, __, ___) => const Icon(
                            Icons.music_note,
                            color: Colors.white,
                            size: 19),
                      ),
                    ),
                  ),
                  const Positioned(
                    left: 54,
                    top: 12,
                    child: Text(
                      '楽曲をVibeに追加',
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.white,
                        letterSpacing: -0.26,
                        height: 1.0,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

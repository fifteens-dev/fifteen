import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../constants/app_colors.dart';
import '../../models/music_service_type.dart';
import '../../models/post_model.dart';
import '../../models/track_model.dart';
import '../../models/vibe_ranking_item.dart';
import '../../models/vibe_topic_model.dart';
import '../../services/audio_player_service.dart';
import '../../services/itunes_search_service.dart';
import '../../services/music_service_manager.dart';
import '../../services/post_service.dart';
import '../../services/user_service.dart';
import '../comment_screen.dart';
import '../music_selection_screen.dart';
import '../post_preview_screen.dart';
import 'vibe_playlist_header.dart';
import 'vibe_tracks_tab.dart';
import 'widgets/song_action_sheet.dart';
import 'widgets/vibe_post_card.dart';

/// Vibeプレイリスト画面
/// - 投稿タブ: TikTok形式でVibe投稿を全画面スクロール
/// - 曲リストタブ: ランキング曲一覧
class VibePlaylistScreen extends StatefulWidget {
  final VibeTopicModel topic;
  final List<VibeRankingItem> ranking;
  final String currentUserId;
  final bool hasPostedToday;

  const VibePlaylistScreen({
    super.key,
    required this.topic,
    required this.ranking,
    required this.currentUserId,
    this.hasPostedToday = false,
  });

  @override
  State<VibePlaylistScreen> createState() => _VibePlaylistScreenState();
}

class _VibePlaylistScreenState extends State<VibePlaylistScreen>
    with TickerProviderStateMixin {
  late TabController _tabController;
  late PageController _tabPageController;
  int _selectedTab = 0; // 0=投稿, 1=曲リスト
  List<PostModel>? _posts;
  bool _isLoading = true;

  // Figma: card 814px + gap 8px = page 822px
  // viewportFraction を実際の画面高さで割ることで、機種問わず常に814pxのカード高さを維持する
  PageController? _pageController;
  final AudioPlayerService _audioService = AudioPlayerService();
  final ITunesSearchService _itunesService = ITunesSearchService();
  final PostService _postService = PostService();
  final UserService _userService = UserService();

  int _currentPage = 0;
  final Map<int, String?> _previewUrlCache = {};
  final Map<String, int> _likeCountCache = {};
  final Map<String, bool> _isLikedCache = {};
  final Map<String, bool> _isSavedCache = {};

  // 各投稿のランキングアイテムをキャッシュ
  final Map<String, VibeRankingItem?> _rankingItemCache = {};

  // 並び替え済みランキング (postCount desc → trackName asc)
  late final List<VibeRankingItem> _sortedRanking;

  // サマリー画像の固定スロット（写真2 + ジャケット2、ランダム抽選を一度だけ）
  List<String> _summaryImages = const [];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabPageController = PageController();
    _tabController.addListener(_onTabControllerChanged);
    _sortedRanking = _sortRanking(widget.ranking);
    _loadPosts();
  }

  void _onTabControllerChanged() {
    if (_tabController.indexIsChanging) return;
    if (_tabPageController.hasClients) {
      _tabPageController.animateToPage(
        _tabController.index,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeInOut,
      );
    }
    if (_selectedTab != _tabController.index) {
      setState(() => _selectedTab = _tabController.index);
    }
  }

  List<VibeRankingItem> _sortRanking(List<VibeRankingItem> source) {
    final list = List<VibeRankingItem>.of(source);
    list.sort((a, b) {
      final byCount = b.postCount.compareTo(a.postCount);
      if (byCount != 0) return byCount;
      return a.track.trackName.compareTo(b.track.trackName);
    });
    return list;
  }

  /// _posts と ranking から「写真2 + ジャケット2」をランダム抽選してキャッシュ
  void _buildSummaryImages() {
    final rng = math.Random(widget.topic.topicId.hashCode);
    final photos = <String>[
      for (final p in (_posts ?? const <PostModel>[]))
        if (p.photoUrl != null && p.photoUrl!.startsWith('http')) p.photoUrl!,
    ]..shuffle(rng);
    final jackets = <String>[
      for (final r in _sortedRanking)
        if (r.track.albumImageUrl.isNotEmpty) r.track.albumImageUrl,
    ]..shuffle(rng);

    // 左・中央: 写真のみ、右上・右下: アルバムアートのみ（不足時は空文字）
    _summaryImages = [
      photos.isNotEmpty ? photos[0] : '',
      photos.length > 1 ? photos[1] : '',
      jackets.isNotEmpty ? jackets[0] : '',
      jackets.length > 1 ? jackets[1] : '',
    ];
  }

  @override
  void dispose() {
    _tabController.removeListener(_onTabControllerChanged);
    _tabController.dispose();
    _tabPageController.dispose();
    _pageController?.dispose();
    _audioService.dispose();
    super.dispose();
  }

  Future<void> _loadPosts() async {
    try {
      final posts = await _postService.getVibePostsByTopic(
        widget.topic.topicId,
        DateTime.now(),
      );
      if (!mounted) return;
      setState(() {
        _posts = posts;
        _isLoading = false;
        _buildSummaryImages();
      });
      if (posts.isNotEmpty) {
        _playMusicForPage(0);
      }
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _playMusicForPage(int index) async {
    if (_posts == null || index >= _posts!.length) return;
    final post = _posts![index];

    if (!_previewUrlCache.containsKey(index)) {
      final url = await _itunesService.getPreviewUrl(
        trackName: post.track.trackName,
        artistName: post.track.artistName,
      );
      _previewUrlCache[index] = url;
    }

    final url = _previewUrlCache[index];
    if (url != null && mounted) {
      await _audioService.playPreview(url);
    }
    // 隣接（次ページ）の音声をプリロードしておく
    _preloadNeighborAudio(index);
  }

  /// 次ページの楽曲を事前 setUrl してタップ→再生のネットワーク待ちを排除
  void _preloadNeighborAudio(int currentIndex) {
    final posts = _posts;
    if (posts == null) return;
    final next = currentIndex + 1;
    if (next >= posts.length) return;
    final url = _previewUrlCache[next];
    if (url == null || url.isEmpty) {
      // URL未取得の場合はバックグラウンドで取りに行く（次回 page change で間に合わせる）
      final nextPost = posts[next];
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

  VibeRankingItem? _rankingFor(PostModel post) {
    final key = post.postId;
    if (_rankingItemCache.containsKey(key)) return _rankingItemCache[key];

    final trackKey = post.track.trackId.isNotEmpty
        ? post.track.trackId
        : '${post.track.trackName}_${post.track.artistName}';

    final found = _sortedRanking.cast<VibeRankingItem?>().firstWhere(
      (r) {
        if (r == null) return false;
        final rKey = r.track.trackId.isNotEmpty
            ? r.track.trackId
            : '${r.track.trackName}_${r.track.artistName}';
        return rKey == trackKey;
      },
      orElse: () => null,
    );

    _rankingItemCache[key] = found;
    return found;
  }

  /// 楽曲未指定で投稿フローへ（楽曲選択から）
  Future<void> _navigateToVibePost() async {
    _audioService.stop();
    await Navigator.push<int>(
      context,
      PageRouteBuilder(
        pageBuilder: (_, __, ___) =>
            const MusicSelectionScreen(initialCategoryType: 'vibe', fromVibePlaylist: true),
        transitionDuration: Duration.zero,
        reverseTransitionDuration: Duration.zero,
      ),
    );
  }

  /// 指定の楽曲で投稿フロー（カード反転起点）へ直接遷移
  /// 音符ボタン・モーダルの「楽曲をVibeに追加」から呼び出し
  Future<void> _navigateToPostPreviewWithTrack(TrackModel track) async {
    _audioService.stop();
    if (!mounted) return;
    await Navigator.push(
      context,
      PageRouteBuilder(
        pageBuilder: (_, __, ___) => PostPreviewScreen(
          track: track,
          isVibe: true,
          vibeTopicId: widget.topic.topicId,
          vibeTopicTitle: widget.topic.title,
          fromVibePlaylist: true,
        ),
        transitionsBuilder: (context, animation, _, child) {
          final tween = Tween(begin: const Offset(0, 1), end: Offset.zero)
              .chain(CurveTween(curve: Curves.easeOutCubic));
          return SlideTransition(position: animation.drive(tween), child: child);
        },
        transitionDuration: const Duration(milliseconds: 350),
      ),
    );
  }

  /// 曲行タップで開くモーダル（Figma 3870:6805 仕様）
  Future<void> _showSongModal(VibeRankingItem item) async {
    // この楽曲を使った投稿の写真を抽出（trackId or trackName+artistNameでマッチ）
    final trackKey = item.track.trackId.isNotEmpty
        ? item.track.trackId
        : '${item.track.trackName}_${item.track.artistName}';
    final photos = <String>[
      for (final p in (_posts ?? const <PostModel>[]))
        if ((p.photoUrl ?? '').startsWith('http') &&
            (p.track.trackId.isNotEmpty
                    ? p.track.trackId
                    : '${p.track.trackName}_${p.track.artistName}') ==
                trackKey)
          p.photoUrl!,
    ];

    final matchingPost = (_posts ?? []).cast<PostModel?>().firstWhere(
      (p) => p != null && (
        p.track.trackId.isNotEmpty
          ? p.track.trackId == item.track.trackId
          : '${p.track.trackName}_${p.track.artistName}' == trackKey
      ),
      orElse: () => null,
    );
    final isSaved = matchingPost != null
        ? (_isSavedCache[matchingPost.postId] ??
            matchingPost.savedByUserIds.contains(widget.currentUserId))
        : false;

    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true, // 背の高いモーダル + 内部スクロール
      builder: (ctx) => SongActionSheet(
        item: item,
        photos: photos,
        isSaved: isSaved,
        onPlayFull: () {
          Navigator.of(ctx).pop();
          _openExternalMusicService(item.track);
        },
        onAddToVibe: () {
          Navigator.of(ctx).pop();
          _navigateToPostPreviewWithTrack(item.track);
        },
        onSave: () {
          if (matchingPost != null) _handleSave(matchingPost);
        },
      ),
    );
  }

  /// Apple Music / Spotify を外部で開く（ユーザーの優先サービスに従う）
  Future<void> _openExternalMusicService(TrackModel track) async {
    final manager = MusicServiceManager();
    final selected = await manager.getSelectedService();
    final service = selected == MusicServiceType.spotify
        ? MusicServiceType.spotify
        : MusicServiceType.appleMusic; // 未設定/none は Apple Music
    final query = Uri.encodeComponent('${track.trackName} ${track.artistName}');
    final url = service == MusicServiceType.spotify
        ? 'https://open.spotify.com/search/$query'
        : 'https://music.apple.com/jp/search?term=$query';
    final uri = Uri.parse(url);
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('音楽サービスを開けませんでした')),
        );
      }
    }
  }

  int get _totalUsers {
    final ids = <String>{};
    for (final r in _sortedRanking) {
      ids.addAll(r.userIds);
    }
    return ids.length;
  }

  // ────────────────────────────────────────────
  // BUILD
  // ────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final topPadding = MediaQuery.of(context).padding.top;
    final screenH = MediaQuery.of(context).size.height;
    // PageView の viewportFraction は 0..1 の範囲が安全。
    // 小型端末（screenH < 822）では 1.0 にクランプして崩れを防ぐ。
    final fraction = screenH > 0
        ? (822.0 / screenH).clamp(0.5, 1.0)
        : 1.0;
    _pageController ??= PageController(viewportFraction: fraction);

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: AppColors.background,
        body: Stack(
          children: [
            // ── コンテンツ（横スワイプで投稿⇔曲リスト） ──
            Positioned.fill(
              child: PageView(
                controller: _tabPageController,
                onPageChanged: (index) {
                  _tabController.animateTo(index);
                  setState(() => _selectedTab = index);
                },
                children: [
                  _buildPostsTab(),
                  Padding(
                    padding: EdgeInsets.only(top: topPadding + 35 + 32),
                    child: _buildTracksTab(),
                  ),
                ],
              ),
            ),

            // ── 上部グラデーション（投稿タブ用・テキスト可読性） ──
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              height: topPadding + 35 + 31 + 20,
              child: AnimatedBuilder(
                animation: _tabPageController,
                builder: (context, _) {
                  final t = _tabPageController.hasClients
                      ? (_tabPageController.page ?? _tabController.index.toDouble()).clamp(0.0, 1.0)
                      : _tabController.index.toDouble();
                  // 投稿タブ(t=0)で不透明、曲リストタブ(t=1)で透明
                  final opacity = (1.0 - t).clamp(0.0, 1.0);
                  if (opacity == 0.0) return const SizedBox.shrink();
                  return Opacity(
                    opacity: opacity,
                    child: const DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [Color(0xCC000000), Colors.transparent],
                        ),
                      ),
                      child: SizedBox.expand(),
                    ),
                  );
                },
              ),
            ),

            // ── ヘッダー＋タブバー（常に前面） ──
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: AnimatedBuilder(
                animation: _tabPageController,
                builder: (context, child) {
                  final t = _tabPageController.hasClients
                      ? (_tabPageController.page ?? _tabController.index.toDouble()).clamp(0.0, 1.0)
                      : _tabController.index.toDouble();
                  return Container(
                    color: AppColors.background.withValues(alpha: t),
                    child: child,
                  );
                },
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(height: topPadding),
                    VibePlaylistHeader(
                      topicTitle: widget.topic.title,
                      totalUsers: _totalUsers,
                      trackCount: _sortedRanking.length,
                      onBack: () {
                        _audioService.stop();
                        Navigator.of(context).pop();
                      },
                    ),
                    VibePlaylistTabBar(
                      tabController: _tabController,
                      tabPageController: _tabPageController,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }


  // ────────────────────────────────────────────
  // 投稿タブ（全画面 PageView）
  // ────────────────────────────────────────────

  Widget _buildPostsTab() {
    if (_isLoading) {
      return const Center(
        child: CupertinoActivityIndicator(color: Colors.white, radius: 14),
      );
    }
    if (_posts == null || _posts!.isEmpty) {
      return const Center(
        child: Text('まだ投稿がありません',
            style: TextStyle(color: Colors.white, fontSize: 14)),
      );
    }
    // padEnds:false で先頭ページが上端に揃い、各ページ下に次カードがピーク
    return PageView.builder(
      scrollDirection: Axis.vertical,
      controller: _pageController!,
      pageSnapping: true,
      padEnds: false,
      itemCount: _posts!.length,
      onPageChanged: _onPageChanged,
      itemBuilder: (context, index) {
        final post = _posts![index];
        return _buildVibePostCard(post, _rankingFor(post));
      },
    );
  }

  Widget _buildVibePostCard(PostModel post, VibeRankingItem? rankingItem) {
    final modalItem = rankingItem ??
        VibeRankingItem(rank: 0, track: post.track, postCount: 0);
    final isLiked =
        _isLikedCache[post.postId] ?? post.isLikedBy(widget.currentUserId);
    final likeCount = _likeCountCache[post.postId] ?? post.likeCount;
    final isSaved = _isSavedCache[post.postId] ??
        post.savedByUserIds.contains(widget.currentUserId);
    return VibePostCard(
      post: post,
      rankingItem: rankingItem,
      isLiked: isLiked,
      likeCount: likeCount,
      isSaved: isSaved,
      onLikeTap: () => _handleLike(post),
      onCommentTap: () => _handleComment(post),
      onSaveTap: () => _handleSave(post),
      onCuratorBarTap: () => _showSongModal(modalItem),
      onPostNoteTap: () => _navigateToPostPreviewWithTrack(post.track),
    );
  }


  Future<void> _handleLike(PostModel post) async {
    HapticFeedback.lightImpact();
    final postId = post.postId;
    final wasLiked = _isLikedCache[postId] ?? post.isLikedBy(widget.currentUserId);
    final count = _likeCountCache[postId] ?? post.likeCount;
    setState(() {
      _isLikedCache[postId] = !wasLiked;
      _likeCountCache[postId] = wasLiked ? (count - 1).clamp(0, 999999) : count + 1;
    });
    try {
      await _postService.toggleLike(
        postId: postId,
        userId: widget.currentUserId,
      );
    } catch (_) {
      if (mounted) {
        setState(() {
          _isLikedCache[postId] = wasLiked;
          _likeCountCache[postId] = count;
        });
      }
    }
  }

  Future<void> _handleSave(PostModel post) async {
    HapticFeedback.lightImpact();
    final postId = post.postId;
    final wasSaved = _isSavedCache[postId] ??
        post.savedByUserIds.contains(widget.currentUserId);
    setState(() {
      _isSavedCache[postId] = !wasSaved;
    });
    try {
      await _userService.toggleSavePost(
        userId: widget.currentUserId,
        postId: postId,
      );
    } catch (_) {
      if (mounted) {
        setState(() {
          _isSavedCache[postId] = wasSaved;
        });
      }
    }
  }

  Future<void> _handleComment(PostModel post) async {
    _audioService.stop();
    await CommentScreen.show(context, post: post);
  }

  // ────────────────────────────────────────────
  // 曲リストタブ
  // ────────────────────────────────────────────

  Widget _buildTracksTab() {
    final posts = _posts;
    final currentPost = (posts != null && posts.isNotEmpty)
        ? posts[_currentPage.clamp(0, posts.length - 1)]
        : null;
    return VibeTracksTab(
      topic: widget.topic,
      sortedRanking: _sortedRanking,
      summaryImages: _summaryImages,
      totalUsers: _totalUsers,
      currentPost: currentPost,
      onJumpToPostsTab: () {
        _tabController.animateTo(0);
        _tabPageController.animateToPage(
          0,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeInOut,
        );
      },
      onAddVibeTap: _navigateToVibePost,
      onSongTap: _showSongModal,
      onSongPostTap: (item) => _navigateToPostPreviewWithTrack(item.track),
      onSongSaveTap: (item) {
        final matching = _matchingPostFor(item);
        return matching != null ? () => _handleSave(matching) : null;
      },
      isSongSaved: (item) {
        final matching = _matchingPostFor(item);
        if (matching == null) return false;
        return _isSavedCache[matching.postId] ??
            matching.savedByUserIds.contains(widget.currentUserId);
      },
    );
  }

  /// 曲行に紐づく投稿（保存ボタンの楽観UI更新先）を探す
  PostModel? _matchingPostFor(VibeRankingItem item) {
    final trackKey = item.track.trackId.isNotEmpty
        ? item.track.trackId
        : '${item.track.trackName}_${item.track.artistName}';
    return (_posts ?? []).cast<PostModel?>().firstWhere(
      (p) =>
          p != null &&
          (p.track.trackId.isNotEmpty
              ? p.track.trackId == item.track.trackId
              : '${p.track.trackName}_${p.track.artistName}' == trackKey),
      orElse: () => null,
    );
  }
}

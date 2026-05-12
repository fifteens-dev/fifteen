import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../constants/app_colors.dart';
import '../models/post_model.dart';
import '../providers/current_user_provider.dart';
import '../widgets/post_card.dart';
import '../services/audio_player_service.dart';
import '../services/itunes_search_service.dart';
import '../services/post_service.dart';
import 'card_share_screen.dart';
import 'home/home_bottom_nav.dart';

/// Campus Vibe 投稿一覧画面（Vibe画面と同じTikTok式縦スクロール）
class CampusVibeScreen extends StatefulWidget {
  final String university;
  final String currentUserId;
  final void Function(int tabIndex)? onTabSwitch;

  const CampusVibeScreen({
    super.key,
    required this.university,
    required this.currentUserId,
    this.onTabSwitch,
  });

  @override
  State<CampusVibeScreen> createState() => _CampusVibeScreenState();
}

class _CampusVibeScreenState extends State<CampusVibeScreen> {
  final PageController _pageController = PageController();
  final AudioPlayerService _audioService = AudioPlayerService();
  final ITunesSearchService _itunesService = ITunesSearchService();
  final PostService _postService = PostService();

  List<PostModel> _posts = [];
  bool _isLoading = true;
  int _currentPage = 0;

  bool _hasPostedThisWeekend = false;
  bool _hasPostedThisWeekendLoaded = false;

  int? _playingPageIndex;
  final Map<int, GlobalKey<PostCardState>> _cardKeys = {};
  final Map<int, String?> _previewUrlCache = {};
  int? _requestedPageIndex;

  String? get _currentUserIconUrl =>
      context.read<CurrentUserProvider>().iconUrl;

  @override
  void initState() {
    super.initState();
    _loadPosts();
    _loadHasPostedThisWeekend();
    // 過去週の Campus Vibe 投稿をバックグラウンドでアーカイブ
    _postService.archiveOldCampusVibePosts(widget.university);
  }

  Future<void> _loadPosts() async {
    setState(() => _isLoading = true);
    final posts = await _postService.getCampusVibePosts(widget.university);
    if (mounted) {
      setState(() {
        _posts = posts;
        _isLoading = false;
      });
      if (posts.isNotEmpty) {
        _playingPageIndex = 0;
        _playMusicForPage(0);
      }
    }
  }

  Future<void> _loadHasPostedThisWeekend() async {
    final hasPosted =
        await _postService.hasUserPostedInCurrentWeekend(widget.currentUserId);
    if (mounted) {
      setState(() {
        _hasPostedThisWeekend = hasPosted;
        _hasPostedThisWeekendLoaded = true;
      });
    }
  }

  Future<void> _playMusicForPage(int index) async {
    if (index < 0 || index >= _posts.length) return;
    _requestedPageIndex = index;
    final post = _posts[index];

    // playPreview 内で fire-and-forget の stop と preload swap を行うため
    // ここでは事前 stop しない（不要な await を避ける）
    String? url = _previewUrlCache[index];

    if (url == null) {
      if (post.track.previewUrl != null && post.track.previewUrl!.isNotEmpty) {
        url = post.track.previewUrl;
        _previewUrlCache[index] = url;
      } else {
        final result = await _itunesService.getPreviewUrlWithArt(
          trackName: post.track.trackName,
          artistName: post.track.artistName,
        );
        if (!mounted) return;
        if (_requestedPageIndex != index) return;

        if (result != null) {
          url = result['previewUrl'];
          if (url != null) {
            setState(() => _previewUrlCache[index] = url);
          }
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

    // 隣接ページの音声を事前 setUrl してタップ→再生のレイテンシを排除
    _preloadNeighborAudio(index);
  }

  /// 次ページ音声の事前ロード
  void _preloadNeighborAudio(int currentIndex) {
    final next = currentIndex + 1;
    if (next >= _posts.length) return;
    final cached = _previewUrlCache[next];
    if (cached != null && cached.isNotEmpty) {
      _audioService.preload(
        cached,
        startFrom: Duration(milliseconds: _posts[next].audioStartMs),
        durationSeconds: _posts[next].audioDurationSec,
      );
      return;
    }
    final nextPost = _posts[next];
    if (nextPost.track.previewUrl != null &&
        nextPost.track.previewUrl!.isNotEmpty) {
      _previewUrlCache[next] = nextPost.track.previewUrl;
      _audioService.preload(
        nextPost.track.previewUrl!,
        startFrom: Duration(milliseconds: nextPost.audioStartMs),
        durationSeconds: nextPost.audioDurationSec,
      );
      return;
    }
    // URL未取得 → バックグラウンドで取得＋preloadまでつなげる
    unawaited(_itunesService
        .getPreviewUrlWithArt(
      trackName: nextPost.track.trackName,
      artistName: nextPost.track.artistName,
    )
        .then((result) {
      if (!mounted) return;
      final u = result?['previewUrl'];
      if (u == null || u.isEmpty) return;
      _previewUrlCache[next] = u;
      _audioService.preload(
        u,
        startFrom: Duration(milliseconds: nextPost.audioStartMs),
        durationSeconds: nextPost.audioDurationSec,
      );
    }));
  }

  void _onPageChanged(int index) {
    if (_playingPageIndex != null && _playingPageIndex != index) {
      if (_hasPostedThisWeekend) {
        _cardKeys[_playingPageIndex]?.currentState?.flipToBack();
      }
    }
    _playingPageIndex = index;
    setState(() => _currentPage = index);
    _playMusicForPage(index);
  }

  @override
  void dispose() {
    _audioService.stop();
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final topPadding = MediaQuery.of(context).padding.top;
    final headerAreaHeight = topPadding + 16.0 + 40.0 + 8.0;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: Stack(
        children: [
          // ── メインコンテンツ ──────────────────────────────
          if (_isLoading || !_hasPostedThisWeekendLoaded)
            const Center(
              child: CupertinoActivityIndicator(
                color: Colors.white54,
                radius: 12,
              ),
            )
          else if (_posts.isEmpty)
            Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('🏫', style: TextStyle(fontSize: 48)),
                  const SizedBox(height: 16),
                  Text(
                    'まだ投稿がありません',
                    style: TextStyle(
                      fontSize: 16,
                      color: Colors.white.withValues(alpha: 0.7),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '今週末の${widget.university}の\n投稿をお待ちください',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.white.withValues(alpha: 0.4),
                    ),
                  ),
                ],
              ),
            )
          else
            PageView.builder(
              controller: _pageController,
              scrollDirection: Axis.vertical,
              onPageChanged: _onPageChanged,
              itemCount: _posts.length,
              itemBuilder: (context, index) {
                final post = _posts[index];
                _cardKeys.putIfAbsent(
                    index, () => GlobalKey<PostCardState>());
                return Padding(
                  padding:
                      EdgeInsets.only(top: headerAreaHeight, bottom: 71),
                  child: Center(
                    child: SingleChildScrollView(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: PostCard(
                          key: _cardKeys[index],
                          post: post,
                          currentUserId: widget.currentUserId,
                          currentUserIconUrl: _currentUserIconUrl,
                          audioService: _audioService,
                          startFromBack: _hasPostedThisWeekend,
                          audioManagedExternally: true,
                          externalPreviewUrl: _previewUrlCache[index],
                          backSideEnabled: _hasPostedThisWeekend,
                          onLike: () {},
                          onComment: () {},
                          onAdd: () {},
                          onShare: () => showCardShareSheet(
                            context,
                            post: post,
                            currentUserId: widget.currentUserId,
                            currentUserIconUrl: _currentUserIconUrl,
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),

          // ── フローティングヘッダー ────────────────────────
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SizedBox(
              height: headerAreaHeight,
              child: Padding(
                padding: EdgeInsets.only(top: topPadding),
                child: Row(
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(left: 8),
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
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text('🔥', style: TextStyle(fontSize: 14)),
                              SizedBox(width: 4),
                              Text(
                                'Campus Vibe',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.white,
                                ),
                              ),
                            ],
                          ),
                          Text(
                            widget.university,
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.white.withValues(alpha: 0.7),
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(right: 16),
                      child: SizedBox(
                        width: 40,
                        child: _posts.isNotEmpty
                            ? Text(
                                '${_currentPage + 1}/${_posts.length}',
                                style: TextStyle(
                                  fontSize: 14,
                                  color:
                                      Colors.white.withValues(alpha: 0.7),
                                ),
                                textAlign: TextAlign.right,
                              )
                            : const SizedBox.shrink(),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // ── ボトムナビゲーション ──────────────────────────
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: HomeBottomNavigation(
              selectedIndex: 0,
              onItemTapped: (i) {
                _audioService.stop();
                if (i == 0) {
                  Navigator.pop(context);
                } else {
                  widget.onTabSwitch?.call(i);
                  final route = ModalRoute.of(context);
                  if (route != null) {
                    Navigator.of(context).removeRoute(route);
                  }
                }
              },
            ),
          ),
        ],
      ),
    );
  }
}

import 'package:flutter/material.dart';
import '../constants/app_colors.dart';
import '../models/post_model.dart';
import '../widgets/post_card.dart';
import '../services/audio_player_service.dart';
import '../services/itunes_search_service.dart';
import '../services/post_service.dart';
import '../utils/current_user_helper.dart';
import 'home/home_bottom_nav.dart';

/// Campus Vibe 投稿一覧画面（TikTok式縦スクロール）
class CampusVibeScreen extends StatefulWidget {
  final String university;
  final String currentUserId;

  const CampusVibeScreen({
    super.key,
    required this.university,
    required this.currentUserId,
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
  String? _currentUserIconUrl;

  int? _playingPageIndex;
  final Map<int, GlobalKey<PostCardState>> _cardKeys = {};
  final Map<int, String?> _previewUrlCache = {};
  int? _requestedPageIndex;

  @override
  void initState() {
    super.initState();
    _loadPosts();
    _loadCurrentUserIconUrl();
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

  Future<void> _loadCurrentUserIconUrl() async {
    final userInfo = await CurrentUserHelper.load();
    if (mounted) {
      setState(() => _currentUserIconUrl = userInfo.iconUrl);
    }
  }

  Future<void> _playMusicForPage(int index) async {
    if (index < 0 || index >= _posts.length) return;
    _requestedPageIndex = index;
    final post = _posts[index];

    await _audioService.stop();

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
  }

  void _onPageChanged(int index) {
    if (_playingPageIndex != null && _playingPageIndex != index) {
      _cardKeys[_playingPageIndex]?.currentState?.flipToBack();
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
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        forceMaterialTransparency: true,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, color: Colors.white),
          onPressed: () {
            _audioService.stop();
            Navigator.pop(context);
          },
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: const [
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
                color: Colors.white.withOpacity(0.7),
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
        centerTitle: true,
        actions: [
          if (!_isLoading && _posts.isNotEmpty)
            Center(
              child: Padding(
                padding: const EdgeInsets.only(right: 16),
                child: Text(
                  '${_currentPage + 1}/${_posts.length}',
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.white.withOpacity(0.7),
                  ),
                ),
              ),
            ),
        ],
      ),
      body: _isLoading
          ? const Center(
              child: SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(
                  color: Colors.white54,
                  strokeWidth: 2,
                ),
              ),
            )
          : _posts.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text('🏫',
                          style: TextStyle(fontSize: 48)),
                      const SizedBox(height: 16),
                      Text(
                        'まだ投稿がありません',
                        style: TextStyle(
                          fontSize: 16,
                          color: Colors.white.withOpacity(0.7),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '今週末の${widget.university}の\n投稿をお待ちください',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.white.withOpacity(0.4),
                        ),
                      ),
                    ],
                  ),
                )
              : Stack(
                  children: [
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
                          padding: const EdgeInsets.only(bottom: 71),
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
                                  startFromBack: false,
                                  audioManagedExternally: true,
                                  externalPreviewUrl: _previewUrlCache[index],
                                  backSideEnabled: false,
                                  onLike: () {},
                                  onComment: () {},
                                  onAdd: () {},
                                ),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
                      child: HomeBottomNavigation(
                        selectedIndex: 0,
                        onItemTapped: (i) {
                          if (i == 0) {
                            _audioService.stop();
                            Navigator.pop(context);
                          }
                        },
                      ),
                    ),
                  ],
                ),
    );
  }
}

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../constants/app_colors.dart';
import '../models/post_model.dart';
import '../widgets/post_card.dart';
import '../services/audio_player_service.dart';
import '../services/itunes_search_service.dart';
import '../services/user_service.dart';
import '../utils/current_user_helper.dart';
import 'card_share_screen.dart';

/// Vibe / CampusVibe 過去投稿一覧画面（TikTok式縦スクロール）
class VibePostsListScreen extends StatefulWidget {
  final String title;
  final Future<List<PostModel>> Function() fetchPosts;
  final String currentUserId;

  const VibePostsListScreen({
    super.key,
    required this.title,
    required this.fetchPosts,
    required this.currentUserId,
  });

  @override
  State<VibePostsListScreen> createState() => _VibePostsListScreenState();
}

class _VibePostsListScreenState extends State<VibePostsListScreen> {
  final PageController _pageController = PageController();
  final AudioPlayerService _audioService = AudioPlayerService();
  final ITunesSearchService _itunesService = ITunesSearchService();
  final UserService _userService = UserService();

  List<PostModel> _posts = [];
  bool _isLoading = true;
  int _currentPage = 0;
  String? _currentUserIconUrl;
  final Map<String, bool> _isSavedCache = {};

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
    final posts = await widget.fetchPosts();
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
    if (mounted) setState(() => _currentUserIconUrl = userInfo.iconUrl);
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
          if (url != null) setState(() => _previewUrlCache[index] = url);
        }
      }
    }

    if (!mounted || _requestedPageIndex != index) return;

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
    _playingPageIndex = index;
    setState(() => _currentPage = index);
    _playMusicForPage(index);
  }

  Future<void> _handleSave(PostModel post) async {
    HapticFeedback.lightImpact();
    final postId = post.postId;
    final wasSaved = _isSavedCache[postId] ??
        post.savedByUserIds.contains(widget.currentUserId);
    setState(() => _isSavedCache[postId] = !wasSaved);
    try {
      await _userService.toggleSavePost(
        userId: widget.currentUserId,
        postId: postId,
      );
    } catch (_) {
      if (mounted) setState(() => _isSavedCache[postId] = wasSaved);
    }
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
          if (_isLoading)
            const Center(
              child: CupertinoActivityIndicator(color: Colors.white54, radius: 12),
            )
          else if (_posts.isEmpty)
            Center(
              child: Text(
                '投稿が見つかりませんでした',
                style: TextStyle(fontSize: 16, color: Colors.white.withValues(alpha: 0.5)),
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
                _cardKeys.putIfAbsent(index, () => GlobalKey<PostCardState>());
                return Padding(
                  padding: EdgeInsets.only(top: headerAreaHeight, bottom: 71),
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
                          backSideEnabled: true,
                          onLike: () {},
                          onComment: () {},
                          isSaved: _isSavedCache[post.postId] ??
                              post.savedByUserIds.contains(widget.currentUserId),
                          onAdd: () => _handleSave(post),
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

          // フローティングヘッダー
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
                      child: Center(
                        child: Text(
                          widget.title,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: Colors.white.withValues(alpha: 0.9),
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: SizedBox(
                        width: 40,
                        child: _posts.isNotEmpty
                            ? Center(
                                child: Text(
                                  '${_currentPage + 1}/${_posts.length}',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.white.withValues(alpha: 0.6),
                                  ),
                                ),
                              )
                            : null,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

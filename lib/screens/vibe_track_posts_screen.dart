import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import '../constants/app_colors.dart';
import '../models/post_model.dart';
import '../models/track_model.dart';
import '../widgets/post_card.dart';
import 'package:flutter/services.dart';
import '../services/audio_player_service.dart';
import '../services/itunes_search_service.dart';
import '../services/post_service.dart';
import '../services/user_service.dart';
import '../utils/current_user_helper.dart';
import 'card_share_screen.dart';
import 'home/home_bottom_nav.dart';

/// 特定のトラックのVibe投稿一覧を表示する画面
class VibeTrackPostsScreen extends StatefulWidget {
  final TrackModel track;
  final List<PostModel> posts;
  final String currentUserId;
  final bool? initialHasPostedToday;
  final void Function(int tabIndex)? onTabSwitch;

  const VibeTrackPostsScreen({
    super.key,
    required this.track,
    required this.posts,
    required this.currentUserId,
    this.initialHasPostedToday,
    this.onTabSwitch,
  });

  @override
  State<VibeTrackPostsScreen> createState() => _VibeTrackPostsScreenState();
}

class _VibeTrackPostsScreenState extends State<VibeTrackPostsScreen> {
  final PageController _pageController = PageController();
  final AudioPlayerService _audioService = AudioPlayerService();
  final ITunesSearchService _itunesService = ITunesSearchService();
  final PostService _postService = PostService();
  final UserService _userService = UserService();
  final Map<String, bool> _isSavedCache = {};
  int _currentPage = 0;
  String? _currentUserIconUrl;

  // 今日投稿済みかどうか（裏面表示制御用）
  bool _hasPostedToday = false;
  bool _hasPostedTodayLoaded = false; // ロード完了前は PageView を表示しない

  // 音楽制御用（ProfilePostsListScreen と同じパターン）
  int? _playingPageIndex;
  final Map<int, GlobalKey<PostCardState>> _cardKeys = {};
  final Map<int, String?> _previewUrlCache = {};
  int? _requestedPageIndex;

  @override
  void initState() {
    super.initState();
    _loadCurrentUserIconUrl();
    // 呼び出し元から渡された値があればローディングをスキップ
    if (widget.initialHasPostedToday != null) {
      _hasPostedToday = widget.initialHasPostedToday!;
      _hasPostedTodayLoaded = true;
    } else {
      _loadHasPostedToday();
    }
    // 最初のカードの音楽を再生
    if (widget.posts.isNotEmpty) {
      _playingPageIndex = 0;
      _playMusicForPage(0);
    }
  }

  Future<void> _loadHasPostedToday() async {
    final hasPosted = await _postService.hasUserPostedToday(widget.currentUserId);
    if (mounted) {
      setState(() {
        _hasPostedToday = hasPosted;
        _hasPostedTodayLoaded = true;
      });
    }
  }

  Future<void> _loadCurrentUserIconUrl() async {
    final userInfo = await CurrentUserHelper.load();
    if (mounted) {
      setState(() {
        _currentUserIconUrl = userInfo.iconUrl;
      });
    }
  }

  /// 指定ページの音楽を再生（画面側が一括管理）
  Future<void> _playMusicForPage(int index) async {
    if (index < 0 || index >= widget.posts.length) return;
    _requestedPageIndex = index;
    final post = widget.posts[index];

    // 同じURLでも投稿ごとの再生位置から必ず再生し直すため、先に停止する
    await _audioService.stop();

    // キャッシュ済みURLがあればすぐ再生
    String? url = _previewUrlCache[index];

    if (url == null) {
      // まず post の previewUrl を試す
      if (post.track.previewUrl != null && post.track.previewUrl!.isNotEmpty) {
        url = post.track.previewUrl;
        _previewUrlCache[index] = url;
      } else {
        // iTunes API からプレビューURLを取得
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
      } catch (_) {
        // 再生エラーは無視
      }
    }
  }

  /// ページが変わったら音楽を新しいカードに切り替え、前のカードを裏面に戻す
  void _onPageChanged(int index) {
    if (_playingPageIndex != null && _playingPageIndex != index) {
      if (_hasPostedToday) {
        // 投稿済みユーザー: 前のカードを裏面に戻す（表面にいた場合のみ）
        _cardKeys[_playingPageIndex]?.currentState?.flipToBack();
      }
      // 未投稿ユーザー: カードは常に表面なので何もしない
    }
    _playingPageIndex = index;
    setState(() {
      _currentPage = index;
    });

    // 新しいページの音楽を再生
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
          !_hasPostedTodayLoaded
              ? const Center(
                  child: CupertinoActivityIndicator(
                    color: Colors.white54,
                    radius: 12,
                  ),
                )
              : PageView.builder(
                  controller: _pageController,
                  scrollDirection: Axis.vertical,
                  onPageChanged: _onPageChanged,
                  itemCount: widget.posts.length,
                  itemBuilder: (context, index) {
                    final post = widget.posts[index];
                    _cardKeys.putIfAbsent(index, () => GlobalKey<PostCardState>());
                    // ヘッダー分を上に、ナビバー分(71px)を下に padding してカードを中央に寄せる
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
                              startFromBack: _hasPostedToday,
                              audioManagedExternally: true,
                              externalPreviewUrl: _previewUrlCache[index],
                              backSideEnabled: _hasPostedToday,
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
          // フローティングヘッダー（透明背景・文字だけ浮かせる）
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
                    // 戻るボタン
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
                    // トラック名・アーティスト名（中央）
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            widget.track.trackName,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: Colors.white,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.center,
                          ),
                          Text(
                            widget.track.artistName,
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
                    // ページカウンター
                    Padding(
                      padding: const EdgeInsets.only(right: 16),
                      child: SizedBox(
                        width: 40,
                        child: Text(
                          '${_currentPage + 1}/${widget.posts.length}',
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.white.withValues(alpha: 0.7),
                          ),
                          textAlign: TextAlign.right,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          // ボトムナビゲーション（ホームアイコン白・タップで戻る）
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

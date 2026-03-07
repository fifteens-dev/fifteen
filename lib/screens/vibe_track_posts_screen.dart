import 'package:flutter/material.dart';
import '../constants/app_colors.dart';
import '../models/post_model.dart';
import '../models/track_model.dart';
import '../widgets/post_card.dart';
import '../services/audio_player_service.dart';
import '../services/itunes_search_service.dart';
import '../services/post_service.dart';
import '../utils/current_user_helper.dart';

/// 特定のトラックのVibe投稿一覧を表示する画面
class VibeTrackPostsScreen extends StatefulWidget {
  final TrackModel track;
  final List<PostModel> posts;
  final String currentUserId;

  const VibeTrackPostsScreen({
    super.key,
    required this.track,
    required this.posts,
    required this.currentUserId,
  });

  @override
  State<VibeTrackPostsScreen> createState() => _VibeTrackPostsScreenState();
}

class _VibeTrackPostsScreenState extends State<VibeTrackPostsScreen> {
  final PageController _pageController = PageController();
  final AudioPlayerService _audioService = AudioPlayerService();
  final ITunesSearchService _itunesService = ITunesSearchService();
  final PostService _postService = PostService();
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
    _loadHasPostedToday();
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
          url = result['previewUrl'] as String?;
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
        backgroundColor: AppColors.background,
        elevation: 0,
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
            Text(
              widget.track.trackName,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: Colors.white,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            Text(
              widget.track.artistName,
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
          Center(
            child: Padding(
              padding: const EdgeInsets.only(right: 16),
              child: Text(
                '${_currentPage + 1}/${widget.posts.length}',
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.white.withOpacity(0.7),
                ),
              ),
            ),
          ),
        ],
      ),
      body: !_hasPostedTodayLoaded
          // 投稿状態の確認が完了するまでローディング表示
          // （startFromBack の値が確定してから PostCard を生成するため）
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
          : PageView.builder(
              controller: _pageController,
              scrollDirection: Axis.vertical,
              onPageChanged: _onPageChanged,
              itemCount: widget.posts.length,
              itemBuilder: (context, index) {
                final post = widget.posts[index];
                _cardKeys.putIfAbsent(index, () => GlobalKey<PostCardState>());
                return Center(
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
                        onAdd: () {},
                      ),
                    ),
                  ),
                );
              },
            ),
    );
  }
}

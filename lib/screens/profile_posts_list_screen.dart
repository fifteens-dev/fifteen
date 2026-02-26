import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/post_model.dart';
import '../widgets/post_card.dart';
import '../services/audio_player_service.dart';
import '../services/itunes_search_service.dart';
import '../services/post_service.dart';
import '../services/user_service.dart';
import '../utils/current_user_helper.dart';

/// プロフィールからの投稿一覧画面（インスタ式縦スクロール）
/// 音楽制御はこの画面が一括管理（PostCardのフリップに依存しない）
class ProfilePostsListScreen extends StatefulWidget {
  final List<PostModel> posts;
  final int initialIndex;
  final bool showBackFirst; // true: 裏面から表示
  final bool disableInteractions; // いいね/コメント無効化

  const ProfilePostsListScreen({
    super.key,
    required this.posts,
    required this.initialIndex,
    this.showBackFirst = true,
    this.disableInteractions = false,
  });

  @override
  State<ProfilePostsListScreen> createState() => _ProfilePostsListScreenState();
}

class _ProfilePostsListScreenState extends State<ProfilePostsListScreen> {
  final AudioPlayerService _audioService = AudioPlayerService();
  final ITunesSearchService _itunesService = ITunesSearchService();
  final UserService _userService = UserService();
  final PostService _postService = PostService();
  late PageController _pageController;
  String? _currentUserIconUrl;
  String? _currentUserId;
  int? _playingPageIndex;

  // 各PostCardのGlobalKey（flipToFront呼び出し用）
  final Map<int, GlobalKey<PostCardState>> _cardKeys = {};

  // 保存状態
  final Set<String> _savedPostIds = {};

  // 投稿リスト（削除対応）
  late List<PostModel> _posts;

  // プレビューURLキャッシュ（インデックス → URL）
  final Map<int, String?> _previewUrlCache = {};

  // 最後にリクエストしたページ（スクロール連打対応）
  int? _requestedPageIndex;

  @override
  void initState() {
    super.initState();
    _posts = List.from(widget.posts);
    _currentUserId = FirebaseAuth.instance.currentUser?.uid;
    _pageController = PageController(initialPage: widget.initialIndex);
    _loadCurrentUserIconUrl();
    _loadSaveStates();

    // 裏面スタートの場合、最初のカードの音楽を再生（fire-and-forget）
    if (widget.showBackFirst) {
      _playingPageIndex = widget.initialIndex;
      _playMusicForPage(widget.initialIndex);
    }
  }

  /// 指定ページの音楽を再生する（画面側が音楽を一括管理）
  Future<void> _playMusicForPage(int index) async {
    if (index < 0 || index >= _posts.length) return;
    _requestedPageIndex = index;
    final post = _posts[index];

    // キャッシュ済みURLがあればすぐ再生
    String? url = _previewUrlCache[index];

    if (url == null) {
      // iTunes APIからプレビューURLを取得
      final result = await _itunesService.getPreviewUrlWithArt(
        trackName: post.track.trackName,
        artistName: post.track.artistName,
      );
      if (!mounted) return;
      // スクロールで別ページに移動済みなら中断
      if (_requestedPageIndex != index) return;

      if (result != null) {
        url = result['previewUrl'];
        if (url != null) {
          setState(() { _previewUrlCache[index] = url; });
        }
      }
    }

    if (!mounted) return;
    if (_requestedPageIndex != index) return;

    if (url != null && url.isNotEmpty) {
      try {
        // playPreview内部で別URLが再生中なら自動停止してから再生
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

  Future<void> _loadSaveStates() async {
    final userId = FirebaseAuth.instance.currentUser?.uid;
    if (userId == null) return;
    for (final post in _posts) {
      if (post.savedByUserIds.contains(userId)) {
        _savedPostIds.add(post.postId);
      }
    }
    if (mounted) setState(() {});
  }

  Future<void> _handleSave(PostModel post) async {
    final userId = FirebaseAuth.instance.currentUser?.uid;
    if (userId == null) return;

    setState(() {
      if (_savedPostIds.contains(post.postId)) {
        _savedPostIds.remove(post.postId);
      } else {
        _savedPostIds.add(post.postId);
      }
    });

    try {
      await _userService.toggleSavePost(userId: userId, postId: post.postId);
    } catch (e) {
      if (mounted) {
        setState(() {
          if (_savedPostIds.contains(post.postId)) {
            _savedPostIds.remove(post.postId);
          } else {
            _savedPostIds.add(post.postId);
          }
        });
      }
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

  Future<void> _handleDelete(PostModel post) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        title: const Text('投稿を削除', style: TextStyle(color: Colors.white)),
        content: const Text('この投稿を削除しますか？', style: TextStyle(color: Colors.white70)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('キャンセル', style: TextStyle(color: Colors.white54)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('削除', style: TextStyle(color: Color(0xFFE53935))),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    try {
      await _postService.deletePost(post.postId);
      if (mounted) {
        final idx = _posts.indexWhere((p) => p.postId == post.postId);
        setState(() {
          _posts.removeWhere((p) => p.postId == post.postId);
        });
        if (_posts.isEmpty) {
          Navigator.pop(context);
        } else if (idx >= _posts.length) {
          _pageController.jumpToPage(_posts.length - 1);
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('削除に失敗しました'), backgroundColor: Color(0xFFE53935)),
        );
      }
    }
  }

  @override
  void dispose() {
    _audioService.stop();
    _pageController.dispose();
    super.dispose();
  }

  /// ページが変わったら音楽を新しいカードに切り替え、前のカードを表面に戻す
  void _onPageChanged(int index) {
    // 前のカードを表面に戻す
    if (_playingPageIndex != null && _playingPageIndex != index) {
      _cardKeys[_playingPageIndex]?.currentState?.flipToFront();
    }
    _playingPageIndex = index;

    // 新しいページの音楽を再生（playPreview内部で前の音楽を自動停止）
    _playMusicForPage(index);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      body: Stack(
        children: [
          PageView.builder(
            controller: _pageController,
            scrollDirection: Axis.vertical,
            onPageChanged: _onPageChanged,
            itemCount: _posts.length,
            itemBuilder: (context, index) {
              final post = _posts[index];
              _cardKeys.putIfAbsent(index, () => GlobalKey<PostCardState>());
              return Center(
                child: PostCard(
                  key: _cardKeys[index],
                  post: post,
                  currentUserId: _currentUserId,
                  currentUserIconUrl: _currentUserIconUrl,
                  audioService: _audioService,
                  startFromBack: widget.showBackFirst,
                  audioManagedExternally: widget.showBackFirst, // 音楽制御をこの画面に委譲
                  externalPreviewUrl: _previewUrlCache[index], // 波形表示用のURL
                  disableInteractions: widget.disableInteractions,
                  isSaved: _savedPostIds.contains(post.postId),
                  onAdd: () => _handleSave(post),
                  onDelete: (_currentUserId != null && post.userId == _currentUserId)
                      ? () => _handleDelete(post)
                      : null,
                ),
              );
            },
          ),
          // 投稿ロゴ（中央上部・背景なし）
          Positioned(
            top: MediaQuery.of(context).padding.top + 8,
            left: 0,
            right: 0,
            child: const Center(
              child: Text(
                '投稿',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                ),
              ),
            ),
          ),
          // 閉じるボタン（左上）
          Positioned(
            top: MediaQuery.of(context).padding.top + 16,
            left: 16,
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
        ],
      ),
    );
  }
}

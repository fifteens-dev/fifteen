import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/post_model.dart';
import '../widgets/post_card.dart';
import '../services/audio_player_service.dart';
import '../services/itunes_search_service.dart';
import '../services/post_service.dart';
import '../services/user_service.dart';
import '../utils/current_user_helper.dart';
import 'card_share_screen.dart';

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
  final ScrollController _scrollController = ScrollController();
  String? _currentUserIconUrl;
  String? _currentUserId;
  int? _playingIndex;

  // 各PostCardのGlobalKey（flipToBack呼び出し用）
  final Map<int, GlobalKey<PostCardState>> _cardKeys = {};

  // 保存状態
  final Set<String> _savedPostIds = {};

  // 投稿リスト（削除対応）
  late List<PostModel> _posts;

  // プレビューURLキャッシュ（インデックス → URL）
  final Map<int, String?> _previewUrlCache = {};
  int? _requestedPageIndex;

  static const double _cardItemHeight = 668.0; // 644 card + 24 bottom padding

  @override
  void initState() {
    super.initState();
    _posts = List.from(widget.posts);
    _currentUserId = FirebaseAuth.instance.currentUser?.uid;
    _loadCurrentUserIconUrl();
    _loadSaveStates();

    _scrollController.addListener(_checkCardVisibility);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      // 初期インデックスへスクロール
      if (_scrollController.hasClients && widget.initialIndex > 0) {
        _scrollController.jumpTo(widget.initialIndex * _cardItemHeight);
      }
      // 初期カードの音楽を再生
      _playingIndex = widget.initialIndex;
      _playMusicForPage(widget.initialIndex);
    });
  }

  /// 指定インデックスの音楽を再生する（画面側が音楽を一括管理）
  Future<void> _playMusicForPage(int index) async {
    if (index < 0 || index >= _posts.length) return;
    _requestedPageIndex = index;
    final post = _posts[index];

    String? url = _previewUrlCache[index];

    if (url == null) {
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

  /// スクロール時に各カードの可視性を確認し、
  /// 半分以上見えているカードの音楽を再生・画面外に出たら裏面に戻す
  void _checkCardVisibility() {
    if (!mounted) return;
    final screenHeight = MediaQuery.of(context).size.height;

    int? newPlayingIndex;
    double bestVisibleFraction = 0;

    for (final entry in _cardKeys.entries) {
      final index = entry.key;
      final key = entry.value;
      final renderBox = key.currentContext?.findRenderObject() as RenderBox?;
      if (renderBox == null || !renderBox.attached) continue;

      final position = renderBox.localToGlobal(Offset.zero);
      final cardHeight = renderBox.size.height;
      final cardTop = position.dy;
      final cardBottom = cardTop + cardHeight;

      final isOffScreen = cardBottom <= 0 || cardTop >= screenHeight;
      if (isOffScreen) {
        key.currentState?.flipToBack();
        if (_playingIndex == index) {
          _audioService.stop();
          setState(() => _playingIndex = null);
        }
        continue;
      }

      // 画面内に見えている割合を計算
      final visibleTop = cardTop.clamp(0.0, screenHeight.toDouble());
      final visibleBottom = cardBottom.clamp(0.0, screenHeight.toDouble());
      final visibleFraction = (visibleBottom - visibleTop) / cardHeight;

      // 半分以上見えているカードのうち最も多く見えているものを再生候補にする
      if (visibleFraction > 0.5 && visibleFraction > bestVisibleFraction) {
        bestVisibleFraction = visibleFraction;
        newPlayingIndex = index;
      }
    }

    // 再生すべきカードが変わった場合のみ切り替え
    if (newPlayingIndex != null && newPlayingIndex != _playingIndex) {
      // 前のカードを裏面に戻す
      if (_playingIndex != null) {
        _cardKeys[_playingIndex!]?.currentState?.flipToBack();
      }
      _audioService.stop();
      setState(() => _playingIndex = newPlayingIndex);
      _playMusicForPage(newPlayingIndex!);
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
    final confirmed = await showCupertinoDialog<bool>(
      context: context,
      barrierDismissible: true,
      builder: (context) => CupertinoAlertDialog(
        title: const Text('投稿を削除'),
        content: const Padding(
          padding: EdgeInsets.only(top: 4),
          child: Text('この投稿を削除しますか？'),
        ),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('キャンセル'),
          ),
          CupertinoDialogAction(
            isDestructiveAction: true,
            onPressed: () => Navigator.pop(context, true),
            child: const Text('削除'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    try {
      await _postService.deletePost(post.postId);
      if (mounted) {
        setState(() {
          _posts.removeWhere((p) => p.postId == post.postId);
        });
        if (_posts.isEmpty) {
          Navigator.pop(context);
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
    _scrollController.removeListener(_checkCardVisibility);
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final topPadding = MediaQuery.of(context).padding.top;
    final headerAreaHeight = topPadding + 16.0 + 40.0 + 8.0; // status + top + button + gap

    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      body: Stack(
        children: [
          // インスタ式ListView
          NotificationListener<ScrollNotification>(
            onNotification: (notification) {
              _checkCardVisibility();
              return false;
            },
            child: ListView.builder(
              controller: _scrollController,
              padding: EdgeInsets.only(top: headerAreaHeight, bottom: 80),
              itemCount: _posts.length,
              itemBuilder: (context, index) {
                final post = _posts[index];
                _cardKeys.putIfAbsent(index, () => GlobalKey<PostCardState>());
                return Padding(
                  padding: const EdgeInsets.only(bottom: 24),
                  child: Center(
                    child: PostCard(
                      key: _cardKeys[index],
                      post: post,
                      currentUserId: _currentUserId,
                      currentUserIconUrl: _currentUserIconUrl,
                      audioService: _audioService,
                      startFromBack: true, // 常に裏面スタート
                      audioManagedExternally: true,
                      externalPreviewUrl: _previewUrlCache[index],
                      disableInteractions: widget.disableInteractions,
                      persistentPlayButton: false,
                      onPlayStarted: () => setState(() { _playingIndex = index; }),
                      isSaved: _savedPostIds.contains(post.postId),
                      onAdd: () => _handleSave(post),
                      onDelete: (_currentUserId != null && post.userId == _currentUserId)
                          ? () => _handleDelete(post)
                          : null,
                      onShare: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => CardShareScreen(
                            post: post,
                            currentUserId: _currentUserId,
                            currentUserIconUrl: _currentUserIconUrl,
                            isSaved: _savedPostIds.contains(post.postId),
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          // 投稿タイトル（中央上部）
          Positioned(
            top: topPadding + 16,
            left: 0,
            right: 0,
            child: const SizedBox(
              height: 40,
              child: Center(
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
          ),
          // 閉じるボタン（左上）
          Positioned(
            top: topPadding + 16,
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

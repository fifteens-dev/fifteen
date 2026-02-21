import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/post_model.dart';
import '../widgets/post_card.dart';
import '../services/audio_player_service.dart';
import '../services/user_service.dart';
import '../utils/current_user_helper.dart';

/// プロフィールからの投稿一覧画面（インスタ式縦スクロール）
/// タップした投稿にスクロール済みの状態で開く
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
  final UserService _userService = UserService();
  late ScrollController _scrollController;
  String? _currentUserIconUrl;

  // スクロール時の音楽停止用
  final Map<String, GlobalKey> _postCardKeys = {};
  String? _playingPostId;

  // 保存状態
  final Set<String> _savedPostIds = {};

  @override
  void initState() {
    super.initState();
    // 選択した投稿の位置までスクロール
    // PostCard高さ644 + 間隔25 = 669 per item
    final offset = widget.initialIndex * 669.0;
    _scrollController = ScrollController(
      initialScrollOffset: offset,
    );
    _loadCurrentUserIconUrl();
    _loadSaveStates();
  }

  Future<void> _loadSaveStates() async {
    final userId = FirebaseAuth.instance.currentUser?.uid;
    if (userId == null) return;
    for (final post in widget.posts) {
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

  @override
  void dispose() {
    _audioService.stop();
    _scrollController.dispose();
    super.dispose();
  }

  /// 再生中のカードが画面外にスクロールしたら音楽を停止
  void _checkPlayingCardVisibility() {
    if (!mounted) return;
    if (!_audioService.isPlaying && !_audioService.isPaused) return;
    if (_playingPostId == null) return;

    final key = _postCardKeys[_playingPostId];
    if (key == null) {
      _audioService.stop();
      _playingPostId = null;
      return;
    }

    final currentContext = key.currentContext;
    if (currentContext == null) {
      _audioService.stop();
      _playingPostId = null;
      return;
    }

    final renderBox = currentContext.findRenderObject() as RenderBox?;
    if (renderBox == null || !renderBox.attached) {
      _audioService.stop();
      _playingPostId = null;
      return;
    }

    final position = renderBox.localToGlobal(Offset.zero);
    final size = renderBox.size;
    final screenHeight = MediaQuery.of(context).size.height;

    // カードが完全に画面外に出たら停止
    if (position.dy + size.height <= 0 || position.dy >= screenHeight) {
      _audioService.stop();
      _playingPostId = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      body: Stack(
        children: [
          NotificationListener<ScrollNotification>(
            onNotification: (notification) {
              _checkPlayingCardVisibility();
              return false;
            },
            child: ListView.builder(
              controller: _scrollController,
              padding: EdgeInsets.only(
                top: MediaQuery.of(context).padding.top,
                bottom: MediaQuery.of(context).padding.bottom,
              ),
              itemCount: widget.posts.length,
              itemBuilder: (context, index) {
                final post = widget.posts[index];
                _postCardKeys.putIfAbsent(post.postId, () => GlobalKey());
                final cardKey = _postCardKeys[post.postId]!;
                return Padding(
                  key: cardKey,
                  padding: const EdgeInsets.only(bottom: 25),
                  child: PostCard(
                    post: post,
                    currentUserIconUrl: _currentUserIconUrl,
                    audioService: _audioService,
                    startFromBack: widget.showBackFirst,
                    disableInteractions: widget.disableInteractions,
                    isSaved: _savedPostIds.contains(post.postId),
                    onAdd: () => _handleSave(post),
                    onPlayStarted: () {
                      _playingPostId = post.postId;
                    },
                  ),
                );
              },
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
                  Icons.close,
                  color: Colors.white,
                  size: 24,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

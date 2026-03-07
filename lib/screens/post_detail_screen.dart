import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../constants/app_colors.dart';
import '../models/post_model.dart';
import '../widgets/post_card.dart';
import '../services/audio_player_service.dart';
import '../services/itunes_search_service.dart';
import '../services/post_service.dart';
import '../services/user_service.dart';
import '../utils/current_user_helper.dart';

/// 投稿カード単体表示画面（通知タップ時など）
class PostDetailScreen extends StatefulWidget {
  final PostModel post;
  final String? currentUserId;
  final bool autoFlipAfterDelay;
  final bool disableInteractions;

  const PostDetailScreen({
    super.key,
    required this.post,
    this.currentUserId,
    this.autoFlipAfterDelay = false,
    this.disableInteractions = false,
  });

  @override
  State<PostDetailScreen> createState() => _PostDetailScreenState();
}

class _PostDetailScreenState extends State<PostDetailScreen> {
  final AudioPlayerService _audioService = AudioPlayerService();
  final ITunesSearchService _itunesService = ITunesSearchService();
  final PostService _postService = PostService();
  final UserService _userService = UserService();

  String? _currentUserIconUrl;
  bool _isSaved = false;
  String? _previewUrl;

  // 今日投稿済みかどうか（裏面表示制御用）
  bool _hasPostedToday = false;
  bool _hasPostedTodayLoaded = false;

  String get _currentUserId =>
      widget.currentUserId ?? FirebaseAuth.instance.currentUser?.uid ?? '';

  @override
  void initState() {
    super.initState();
    _loadCurrentUserIconUrl();
    _checkSaveState();
    _fetchPreviewUrl();
    _loadHasPostedToday();
  }

  Future<void> _loadHasPostedToday() async {
    final userId = _currentUserId;
    if (userId.isEmpty) {
      setState(() {
        _hasPostedToday = false;
        _hasPostedTodayLoaded = true;
      });
      return;
    }

    // 自分の投稿は常に閲覧可能
    if (widget.post.userId == userId) {
      setState(() {
        _hasPostedToday = true;
        _hasPostedTodayLoaded = true;
      });
      return;
    }

    // 他人の投稿: その投稿日に自分も投稿していたか確認
    final hasPosted = await _postService.hasUserPostedOnDate(userId, widget.post.createdAt);
    if (mounted) {
      setState(() {
        _hasPostedToday = hasPosted;
        _hasPostedTodayLoaded = true;
      });
    }
  }

  Future<void> _checkSaveState() async {
    final userId = _currentUserId;
    if (userId.isNotEmpty) {
      setState(() {
        _isSaved = widget.post.savedByUserIds.contains(userId);
      });
    }
  }

  Future<void> _fetchPreviewUrl() async {
    final post = widget.post;
    String? url;

    if (post.track.previewUrl != null && post.track.previewUrl!.isNotEmpty) {
      url = post.track.previewUrl;
    } else {
      final result = await _itunesService.getPreviewUrlWithArt(
        trackName: post.track.trackName,
        artistName: post.track.artistName,
      );
      if (!mounted) return;
      url = result?['previewUrl'];
    }

    if (mounted && url != null) {
      setState(() {
        _previewUrl = url;
      });
    }
  }

  Future<void> _handleSave() async {
    final userId = _currentUserId;
    if (userId.isEmpty) return;

    setState(() {
      _isSaved = !_isSaved;
    });

    try {
      await _userService.toggleSavePost(userId: userId, postId: widget.post.postId);
    } catch (e) {
      if (mounted) {
        setState(() {
          _isSaved = !_isSaved;
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
              widget.post.track.trackName,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: Colors.white,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            Text(
              widget.post.track.artistName,
              style: TextStyle(
                fontSize: 12,
                color: Colors.white.withValues(alpha: 0.7),
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
        centerTitle: true,
      ),
      body: !_hasPostedTodayLoaded
          // 投稿状態の確認が完了するまでローディング表示
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
          : Center(
              child: SingleChildScrollView(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: PostCard(
                    post: widget.post,
                    currentUserId: _currentUserId,
                    currentUserIconUrl: _currentUserIconUrl,
                    audioService: _audioService,
                    autoFlipAfterDelay: widget.autoFlipAfterDelay,
                    disableInteractions: widget.disableInteractions,
                    isSaved: _isSaved,
                    externalPreviewUrl: _previewUrl,
                    startFromBack: _hasPostedToday,
                    backSideEnabled: _hasPostedToday,
                    onLike: () {},
                    onComment: () {},
                    onAdd: _handleSave,
                  ),
                ),
              ),
            ),
    );
  }
}

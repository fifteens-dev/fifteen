import 'package:flutter/material.dart';
import '../constants/app_colors.dart';
import '../models/post_model.dart';
import '../models/track_model.dart';
import '../widgets/post_card.dart';
import '../services/audio_player_service.dart';
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
  int _currentPage = 0;
  String? _currentUserIconUrl;

  @override
  void initState() {
    super.initState();
    _loadCurrentUserIconUrl();
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
    _pageController.dispose();
    _audioService.dispose();
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
          icon: const Icon(Icons.close, color: Colors.white),
          onPressed: () => Navigator.pop(context),
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
      body: PageView.builder(
        controller: _pageController,
        onPageChanged: (index) {
          setState(() {
            _currentPage = index;
          });
        },
        itemCount: widget.posts.length,
        itemBuilder: (context, index) {
          final post = widget.posts[index];
          return Center(
            child: SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: PostCard(
                  post: post,
                  currentUserId: widget.currentUserId,
                  currentUserIconUrl: _currentUserIconUrl,
                  audioService: _audioService,
                  autoFlipAfterDelay: true, // すぐに裏返す
                  onLike: () {
                    // いいね処理（必要に応じて実装）
                  },
                  onComment: () {
                    // コメント処理（必要に応じて実装）
                  },
                  onAdd: () {
                    // 保存処理（必要に応じて実装）
                  },
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

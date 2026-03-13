import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../constants/app_colors.dart';
import '../../models/post_model.dart';
import '../../services/user_service.dart';
import '../../services/vibe_topic_service.dart';

/// Vibe投稿データ閲覧タブ（管理者用）
class VibePostsViewerTab extends StatefulWidget {
  const VibePostsViewerTab({super.key});

  @override
  State<VibePostsViewerTab> createState() => _VibePostsViewerTabState();
}

class _VibePostsViewerTabState extends State<VibePostsViewerTab> {
  final UserService _userService = UserService();
  final VibeTopicService _vibeTopicService = VibeTopicService();

  DateTime _selectedDate = DateTime.now();
  List<PostModel> _vibePosts = [];
  Map<String, String?> _userIcons = {};
  String? _topicTitle;
  bool _isLoading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadVibePosts();
  }

  Future<void> _loadVibePosts() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      // 選択日のVibe投稿を取得
      final normalizedDate = DateTime(
        _selectedDate.year,
        _selectedDate.month,
        _selectedDate.day,
      );

      // isVibeがtrueの投稿を取得し、日付はクライアント側でフィルタ
      final snapshot = await FirebaseFirestore.instance
          .collection('posts')
          .where('isVibe', isEqualTo: true)
          .get();

      final posts = snapshot.docs
          .map((doc) => PostModel.fromFirestore(doc))
          .where((post) {
        final postDate = post.vibeDate ?? post.createdAt;
        return postDate.year == normalizedDate.year &&
            postDate.month == normalizedDate.month &&
            postDate.day == normalizedDate.day;
      }).toList();
      // createdAtで降順ソート
      posts.sort((a, b) => b.createdAt.compareTo(a.createdAt));

      // ユーザーアイコンを取得
      final Map<String, String?> icons = {};
      final userIds = posts.map((p) => p.userId).toSet();
      for (final uid in userIds) {
        final user = await _userService.getUser(uid);
        icons[uid] = user?.profileImageUrl;
      }

      // お題タイトルを取得
      String? topicTitle;
      if (posts.isNotEmpty && posts.first.vibeTopicTitle != null) {
        topicTitle = posts.first.vibeTopicTitle;
      } else {
        // vibeTopicServiceから今日のお題を取得
        final topic = await _vibeTopicService.getTodaysTopic();
        topicTitle = topic?.title;
      }

      if (mounted) {
        setState(() {
          _vibePosts = posts;
          _userIcons = icons;
          _topicTitle = topicTitle;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2024),
      lastDate: DateTime.now(),
      builder: (context, child) {
        return Theme(
          data: ThemeData.dark().copyWith(
            colorScheme: const ColorScheme.dark(
              primary: AppColors.accentBlue,
              surface: AppColors.surfaceLight,
            ),
          ),
          child: child!,
        );
      },
    );

    if (picked != null) {
      setState(() {
        _selectedDate = picked;
      });
      _loadVibePosts();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // 日付選択ヘッダー
        _buildDateHeader(),

        // お題タイトル
        if (_topicTitle != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.surfaceLighter,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  const Icon(Icons.music_note,
                      color: AppColors.accentBlue, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'お題: $_topicTitle',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

        // 投稿数
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(
              '${_vibePosts.length}件のVibe投稿',
              style: const TextStyle(color: Colors.grey, fontSize: 13),
            ),
          ),
        ),

        // 投稿リスト
        Expanded(
          child: _buildContent(),
        ),
      ],
    );
  }

  Widget _buildDateHeader() {
    final isToday = _selectedDate.year == DateTime.now().year &&
        _selectedDate.month == DateTime.now().month &&
        _selectedDate.day == DateTime.now().day;

    return Container(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          Expanded(
            child: GestureDetector(
              onTap: _pickDate,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: AppColors.surfaceLight,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.border),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.calendar_today,
                        color: Colors.white, size: 18),
                    const SizedBox(width: 12),
                    Text(
                      '${_selectedDate.year}/${_selectedDate.month.toString().padLeft(2, '0')}/${_selectedDate.day.toString().padLeft(2, '0')}'
                      '${isToday ? '（今日）' : ''}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const Spacer(),
                    const Icon(Icons.arrow_drop_down, color: Colors.grey),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          // リロードボタン
          IconButton(
            onPressed: _loadVibePosts,
            icon: const Icon(Icons.refresh, color: Colors.white),
          ),
        ],
      ),
    );
  }

  Widget _buildContent() {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(color: Colors.white),
      );
    }

    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, color: Colors.red, size: 48),
              const SizedBox(height: 12),
              Text(
                'エラー: $_error',
                style: const TextStyle(color: Colors.red, fontSize: 14),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: _loadVibePosts,
                child: const Text('再読み込み'),
              ),
            ],
          ),
        ),
      );
    }

    if (_vibePosts.isEmpty) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.inbox_outlined, color: Colors.grey, size: 48),
            SizedBox(height: 12),
            Text(
              'この日のVibe投稿はありません',
              style: TextStyle(color: Colors.grey, fontSize: 15),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      itemCount: _vibePosts.length,
      itemBuilder: (context, index) {
        return _buildPostCard(_vibePosts[index], index + 1);
      },
    );
  }

  Widget _buildPostCard(PostModel post, int number) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surfaceLight,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ヘッダー: 番号 + ユーザー名 + 投稿時刻
          Row(
            children: [
              // 番号
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: AppColors.accentBlue.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(6),
                ),
                alignment: Alignment.center,
                child: Text(
                  '$number',
                  style: const TextStyle(
                    color: AppColors.accentBlue,
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              // ユーザーアイコン
              Builder(builder: (_) {
                final iconUrl =
                    post.userIconUrl ?? _userIcons[post.userId];
                return Container(
                  width: 24,
                  height: 24,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.grey,
                  ),
                  child: iconUrl != null && iconUrl.isNotEmpty
                      ? ClipOval(
                          child: iconUrl.startsWith('http')
                              ? CachedNetworkImage(
                                  imageUrl: iconUrl,
                                  width: 24,
                                  height: 24,
                                  fit: BoxFit.cover,
                                  errorWidget: (_, __, ___) => const Icon(
                                      Icons.person,
                                      size: 16,
                                      color: Colors.white),
                                )
                              : Image.asset(
                                  iconUrl,
                                  width: 24,
                                  height: 24,
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, __, ___) => const Icon(
                                      Icons.person,
                                      size: 16,
                                      color: Colors.white),
                                ),
                      )
                    : const Icon(Icons.person, size: 16, color: Colors.white),
                );
              }),
              const SizedBox(width: 8),
              // ユーザー名
              Expanded(
                child: Text(
                  post.username,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              // 投稿時刻
              Text(
                _formatTime(post.createdAt),
                style: const TextStyle(color: Colors.grey, fontSize: 12),
              ),
            ],
          ),

          const SizedBox(height: 10),

          // 曲情報
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppColors.surfaceLighter,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                // アルバムアート
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: CachedNetworkImage(
                    imageUrl: post.track.albumImageUrl,
                    width: 44,
                    height: 44,
                    fit: BoxFit.cover,
                    errorWidget: (_, __, ___) => Container(
                      width: 44,
                      height: 44,
                      color: Colors.grey[800],
                      child: const Icon(Icons.music_note,
                          color: Colors.white, size: 20),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                // 曲名・アーティスト
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        post.track.trackName,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        post.track.artistName,
                        style: const TextStyle(
                            color: Colors.grey, fontSize: 12),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 8),

          // メタデータ行
          Row(
            children: [
              _buildMeta(Icons.favorite_border, '${post.likeCount}'),
              const SizedBox(width: 16),
              _buildMeta(Icons.chat_bubble_outline, '${post.commentCount}'),
              const Spacer(),
              // Post ID（タップでコピー）
              GestureDetector(
                onTap: () {
                  // クリップボードにコピー
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Post ID: ${post.postId}'),
                      duration: const Duration(seconds: 2),
                    ),
                  );
                },
                child: Text(
                  'ID: ${post.postId.substring(0, 8)}...',
                  style: const TextStyle(
                    color: Colors.grey,
                    fontSize: 10,
                    fontFamily: 'monospace',
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMeta(IconData icon, String text) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: Colors.grey, size: 16),
        const SizedBox(width: 4),
        Text(text, style: const TextStyle(color: Colors.grey, fontSize: 12)),
      ],
    );
  }

  String _formatTime(DateTime dt) {
    return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }
}

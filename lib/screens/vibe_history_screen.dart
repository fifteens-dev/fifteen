import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../services/post_service.dart';
import 'vibe_posts_list_screen.dart';

class VibeHistoryScreen extends StatefulWidget {
  const VibeHistoryScreen({super.key});

  @override
  State<VibeHistoryScreen> createState() => _VibeHistoryScreenState();
}

class _VibeHistoryScreenState extends State<VibeHistoryScreen> {
  final PostService _postService = PostService();
  List<({String topicTitle, String topicId, DateTime date, int count})> _topics = [];
  bool _isLoading = true;
  bool _isLoadingMore = false;
  // 現在どこまで遡ったか（日数）
  int _daysOffset = 0;
  static const int _windowDays = 7;

  @override
  void initState() {
    super.initState();
    _loadNext();
  }

  Future<void> _loadNext() async {
    if (_isLoadingMore) return;
    setState(() {
      if (_topics.isEmpty) _isLoading = true;
      _isLoadingMore = true;
    });

    final now = DateTime.now();
    final to = now.subtract(Duration(days: _daysOffset));
    final from = now.subtract(Duration(days: _daysOffset + _windowDays));

    final newTopics = await _postService.getVibeTopicsByDateRange(from, to);

    if (mounted) {
      setState(() {
        _topics = [..._topics, ...newTopics];
        _daysOffset += _windowDays;
        _isLoading = false;
        _isLoadingMore = false;
      });
    }
  }

  String _formatDate(DateTime date) => '${date.month}月${date.day}日';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      body: SafeArea(
        child: Column(
          children: [
            // ヘッダー
            Container(
              height: 45,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.chevron_left, color: Colors.white, size: 28),
                    onPressed: () => Navigator.pop(context),
                  ),
                  const Expanded(
                    child: Text(
                      '過去のVibe',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const SizedBox(width: 48),
                ],
              ),
            ),

            // コンテンツ
            Expanded(
              child: _isLoading
                  ? const Center(
                      child: CupertinoActivityIndicator(color: Colors.white, radius: 12),
                    )
                  : _topics.isEmpty
                      ? Center(
                          child: Text(
                            '過去のVibeはありません',
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.5),
                              fontSize: 15,
                            ),
                          ),
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          itemCount: _topics.length + 1,
                          separatorBuilder: (_, index) => index < _topics.length - 1
                              ? Divider(color: Colors.white.withValues(alpha: 0.08), height: 1)
                              : const SizedBox.shrink(),
                          itemBuilder: (context, index) {
                            if (index < _topics.length) {
                              return _buildTopicItem(_topics[index]);
                            }
                            // 末尾：「さらに過去7日間」ボタン
                            return Padding(
                              padding: const EdgeInsets.symmetric(vertical: 20),
                              child: _isLoadingMore
                                  ? const Center(
                                      child: CupertinoActivityIndicator(
                                        color: Colors.white,
                                        radius: 10,
                                      ),
                                    )
                                  : GestureDetector(
                                      onTap: _loadNext,
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(
                                            vertical: 14, horizontal: 20),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFF282828),
                                          borderRadius: BorderRadius.circular(12),
                                        ),
                                        child: const Row(
                                          mainAxisAlignment: MainAxisAlignment.center,
                                          children: [
                                            Icon(Icons.history, color: Colors.white70, size: 18),
                                            SizedBox(width: 8),
                                            Text(
                                              'さらに過去7日間のvibe投稿を見る',
                                              style: TextStyle(
                                                color: Colors.white,
                                                fontSize: 14,
                                                fontWeight: FontWeight.w500,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                            );
                          },
                        ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTopicItem(
      ({String topicTitle, String topicId, DateTime date, int count}) topic) {
    final currentUserId = FirebaseAuth.instance.currentUser?.uid ?? '';
    return InkWell(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => VibePostsListScreen(
              title: '${_formatDate(topic.date)} ${topic.topicTitle}',
              currentUserId: currentUserId,
              fetchPosts: () => _postService.getVibePostsByTopicAndDate(
                topic.topicId,
                topic.date,
              ),
            ),
          ),
        );
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 14),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    topic.topicTitle,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    '${_formatDate(topic.date)}　${topic.count}件の投稿',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.5),
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right, color: Colors.white.withValues(alpha: 0.3), size: 20),
          ],
        ),
      ),
    );
  }
}

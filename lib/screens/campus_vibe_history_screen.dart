import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../services/post_service.dart';
import 'vibe_posts_list_screen.dart';

/// 過去のCampusVibe一覧画面（大学 + 週末日付、新しい順）
class CampusVibeHistoryScreen extends StatefulWidget {
  const CampusVibeHistoryScreen({super.key});

  @override
  State<CampusVibeHistoryScreen> createState() => _CampusVibeHistoryScreenState();
}

class _CampusVibeHistoryScreenState extends State<CampusVibeHistoryScreen> {
  final PostService _postService = PostService();
  List<({String university, DateTime weekStart, int count})> _entries = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    final entries = await _postService.getPastCampusVibeEntries();
    if (mounted) {
      setState(() {
        _entries = entries;
        _isLoading = false;
      });
    }
  }

  /// "4月12日" 形式
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
                      '過去のCampusVibe',
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
                      child: CupertinoActivityIndicator(
                        color: Colors.white,
                        radius: 12,
                      ),
                    )
                  : _entries.isEmpty
                      ? Center(
                          child: Text(
                            '過去のCampusVibeはありません',
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.5),
                              fontSize: 15,
                            ),
                          ),
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          itemCount: _entries.length,
                          separatorBuilder: (_, __) => Divider(
                            color: Colors.white.withValues(alpha: 0.08),
                            height: 1,
                          ),
                          itemBuilder: (context, index) {
                            final entry = _entries[index];
                            return _buildEntryItem(entry);
                          },
                        ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEntryItem(({String university, DateTime weekStart, int count}) entry) {
    final currentUserId = FirebaseAuth.instance.currentUser?.uid ?? '';
    // 週末範囲（金〜日）
    final weekEnd = entry.weekStart.add(const Duration(days: 2));
    final dateLabel = '${_formatDate(entry.weekStart)}〜${_formatDate(weekEnd)}';

    return InkWell(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => VibePostsListScreen(
              title: '$dateLabel ${entry.university}',
              currentUserId: currentUserId,
              fetchPosts: () => _postService.getCampusVibePostsByWeekAndUniversity(
                entry.weekStart,
                entry.university,
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
                    entry.university,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    '$dateLabel　${entry.count}件の投稿',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.5),
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.chevron_right,
              color: Colors.white.withValues(alpha: 0.3),
              size: 20,
            ),
          ],
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import '../../constants/app_colors.dart';
import '../../models/vibe_topic_model.dart';
import '../../models/vibe_ranking_item.dart';

/// Vibeバーセクション
/// ホーム画面の上部に表示されるVibeランキングバー
class VibeBarSection extends StatelessWidget {
  final Future<Map<String, dynamic>> vibeDataFuture;
  final void Function(VibeRankingItem item) onRankingItemTap;

  const VibeBarSection({
    super.key,
    required this.vibeDataFuture,
    required this.onRankingItemTap,
  });

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Map<String, dynamic>>(
      future: vibeDataFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return _buildSkeleton();
        }

        if (!snapshot.hasData || snapshot.data!['topic'] == null) {
          return _buildEmpty();
        }

        final topic = snapshot.data!['topic'] as VibeTopicModel;
        final ranking = snapshot.data!['ranking'] as List<VibeRankingItem>;

        return Container(
          height: 190,
          color: AppColors.background,
          child: Column(
            children: [
              _buildHeader(topic),
              Expanded(
                child: ranking.isEmpty
                    ? _buildNoRankingMessage()
                    : ListView.builder(
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        itemCount: ranking.length,
                        itemBuilder: (context, index) {
                          return _buildRankingItem(ranking[index], index + 1);
                        },
                      ),
              ),
            ],
          ),
        );
      },
    );
  }

  /// ヘッダー（お題タイトル）
  Widget _buildHeader(VibeTopicModel topic) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          Image.asset(
            'assets/icons/Vibe.png',
            width: 40,
            height: 40,
            errorBuilder: (context, error, stackTrace) {
              return Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: Colors.purple,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.music_note, color: Colors.white),
              );
            },
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'Vibe【${topic.title}】',
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: Colors.white,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// ランキングアイテム
  Widget _buildRankingItem(VibeRankingItem item, int rank) {
    return GestureDetector(
      onTap: () => onRankingItemTap(item),
      child: Container(
        width: 80,
        margin: const EdgeInsets.symmetric(horizontal: 4),
        child: Column(
          children: [
            // ランク番号
            Container(
              width: 20,
              height: 20,
              decoration: BoxDecoration(
                color: _getRankColor(rank),
                shape: BoxShape.circle,
              ),
              child: Center(
                child: Text(
                  '$rank',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 4),

            // アルバムアートワーク
            Container(
              width: 70,
              height: 70,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(4),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: Image.network(
                  item.track.albumImageUrl,
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) {
                    return Container(
                      color: Colors.grey[800],
                      child: const Icon(Icons.album, color: Colors.white54),
                    );
                  },
                ),
              ),
            ),
            const SizedBox(height: 4),

            // 楽曲名
            Text(
              item.track.trackName,
              style: const TextStyle(
                fontSize: 9,
                fontWeight: FontWeight.w600,
                color: Colors.white,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
            ),
            // アーティスト名
            Text(
              item.track.artistName,
              style: TextStyle(
                fontSize: 7,
                color: Colors.white.withValues(alpha: 0.7),
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
            ),

            // 投稿数
            Text(
              '${item.postCount}投稿',
              style: const TextStyle(
                fontSize: 7,
                color: Color(0xFF5D8FFF),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// ランク別の色
  Color _getRankColor(int rank) {
    switch (rank) {
      case 1:
        return const Color(0xFFFFD700); // ゴールド
      case 2:
        return const Color(0xFFC0C0C0); // シルバー
      case 3:
        return const Color(0xFFCD7F32); // ブロンズ
      default:
        return const Color(0xFF5D8FFF);
    }
  }

  /// スケルトン（ローディング）
  Widget _buildSkeleton() {
    return Container(
      height: 190,
      color: AppColors.background,
      padding: const EdgeInsets.all(16),
      child: const Center(
        child: CircularProgressIndicator(),
      ),
    );
  }

  /// 空状態
  Widget _buildEmpty() {
    return Container(
      height: 190,
      color: AppColors.background,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                Image.asset(
                  'assets/icons/Vibe.png',
                  width: 40,
                  height: 40,
                  errorBuilder: (context, error, stackTrace) {
                    return Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: Colors.purple,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(Icons.music_note, color: Colors.white),
                    );
                  },
                ),
                const SizedBox(width: 12),
                const Text(
                  'Vibe',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: Center(
              child: Text(
                '今日のVibeお題はありません',
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.white.withValues(alpha: 0.6),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// ランキングがない場合
  Widget _buildNoRankingMessage() {
    return Center(
      child: Text(
        'まだ投稿がありません',
        style: TextStyle(
          fontSize: 12,
          color: Colors.white.withValues(alpha: 0.6),
        ),
      ),
    );
  }
}

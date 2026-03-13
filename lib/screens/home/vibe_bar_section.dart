import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../constants/app_colors.dart';
import '../../models/vibe_topic_model.dart';
import '../../models/vibe_ranking_item.dart';

/// Vibeバーセクション
/// ホーム画面の上部に表示されるVibeランキングバー
class VibeBarSection extends StatelessWidget {
  final Future<Map<String, dynamic>> vibeDataFuture;
  final void Function(VibeRankingItem item) onRankingItemTap;
  final VoidCallback? onPostTap;

  const VibeBarSection({
    super.key,
    required this.vibeDataFuture,
    required this.onRankingItemTap,
    this.onPostTap,
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
          color: AppColors.background,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildHeader(topic),
              SizedBox(
                height: ranking.isEmpty ? 40 : 100,
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
      padding: const EdgeInsets.only(left: 16, right: 16, top: 8, bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
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
            child: RichText(
              text: TextSpan(
                children: [
                  const TextSpan(
                    text: 'Vibe ',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                  TextSpan(
                    text: '【#${topic.title}】',
                    style: const TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (onPostTap != null)
            GestureDetector(
              onTap: onPostTap,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 17,
                      height: 17,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.black, width: 1.5),
                      ),
                      child: const Icon(
                        Icons.add,
                        size: 10.2,
                        color: Colors.black,
                      ),
                    ),
                    const SizedBox(width: 4),
                    const Text(
                      '投稿する',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: Colors.black,
                      ),
                    ),
                  ],
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
        width: 76,
        margin: const EdgeInsets.symmetric(horizontal: 2),
        child: Column(
          children: [
            // アルバムアートワーク
            Container(
              width: 70,
              height: 70,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(4),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: CachedNetworkImage(
                  imageUrl: item.track.albumImageUrl,
                  fit: BoxFit.cover,
                  memCacheWidth: 140,
                  memCacheHeight: 140,
                  errorWidget: (context, url, error) {
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
          ],
        ),
      ),
    );
  }

  /// スケルトン（ローディング）
  Widget _buildSkeleton() {
    return Container(
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
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
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

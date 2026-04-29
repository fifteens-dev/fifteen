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
          return const SizedBox.shrink();
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
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildHeader(topic),
              Padding(
                padding: const EdgeInsets.only(left: 10, top: 4, bottom: 4),
                child: SizedBox(
                  height: 78,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      // Vibeアイコン（円形バブル）
                      _buildVibeBubble(),
                      const SizedBox(width: 8),
                      // ランキングアルバムアート（正方形、横スクロール）
                      Expanded(
                        child: ListView.builder(
                          scrollDirection: Axis.horizontal,
                          padding: EdgeInsets.zero,
                          itemCount: ranking.length,
                          itemBuilder: (context, index) {
                            return _buildRankingItem(ranking[index]);
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              _buildBottomBar(ranking),
            ],
          ),
        );
      },
    );
  }

  /// ヘッダー（「Vibe」20px + 「【#お題】」13px を同一行、left=21）
  Widget _buildHeader(VibeTopicModel topic) {
    return Padding(
      padding: const EdgeInsets.only(left: 21, right: 16, top: 18, bottom: 0),
      child: RichText(
        text: TextSpan(
          children: [
            const TextSpan(
              text: 'Vibe',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w500,
                color: Colors.white,
              ),
            ),
            TextSpan(
              text: '【#${topic.title}】',
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Vibeアイコンバブル（78×78の円形、ラベルなし）
  Widget _buildVibeBubble() {
    return GestureDetector(
      onTap: onPostTap,
      child: Container(
        width: 78,
        height: 78,
        decoration: const BoxDecoration(
          shape: BoxShape.circle,
          gradient: LinearGradient(
            colors: [Color(0xFF8B2FC9), Color(0xFFE91E8C), Color(0xFFFF6B00)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        padding: const EdgeInsets.all(3),
        child: Container(
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            color: AppColors.background,
          ),
          padding: const EdgeInsets.all(7),
          child: Image.asset(
            'assets/icons/Vibe.png',
            fit: BoxFit.contain,
            errorBuilder: (_, __, ___) => const Icon(
              Icons.music_note,
              color: Colors.white,
              size: 30,
            ),
          ),
        ),
      ),
    );
  }

  /// ランキングアイテム（正方形アルバムアート形式）
  Widget _buildRankingItem(VibeRankingItem item) {
    return GestureDetector(
      onTap: () => onRankingItemTap(item),
      child: Container(
        width: 64,
        margin: const EdgeInsets.symmetric(horizontal: 2),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 60,
              height: 60,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(4),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: CachedNetworkImage(
                  imageUrl: item.track.albumImageUrl,
                  fit: BoxFit.cover,
                  memCacheWidth: 120,
                  memCacheHeight: 120,
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
            Text(
              '${item.track.artistName}/${item.track.trackName}',
              style: TextStyle(
                fontSize: 8,
                color: Colors.white.withValues(alpha: 0.8),
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

  /// ボトムバー（投稿者アイコン・投稿情報・投稿ボタン）
  Widget _buildBottomBar(List<VibeRankingItem> ranking) {
    if (onPostTap == null) return const SizedBox.shrink();

    // 投稿者アイコンURL（重複なし、最大3件）
    final iconUrls = ranking
        .expand((r) => r.userIconUrls)
        .toSet()
        .take(3)
        .toList();

    // ユーザー名（重複なし、最大2件）
    final names = ranking
        .expand((r) => r.usernames)
        .toSet()
        .take(2)
        .toList();

    // 合計ユーザー数（重複なし）
    final totalUsers = ranking.expand((r) => r.userIds).toSet().length;

    // 曲数
    final songCount = ranking.length;

    // 表示テキスト: 🔥name1、name2などX人が追加・Y曲
    final String infoText;
    if (totalUsers == 0) {
      infoText = '';
    } else if (names.isEmpty) {
      infoText = '🔥$totalUsers人が追加・$songCount曲';
    } else if (names.length == 1) {
      infoText = '🔥${names[0]}など$totalUsers人が追加・$songCount曲';
    } else {
      infoText = '🔥${names[0]}、${names[1]}など$totalUsers人が追加・$songCount曲';
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(9, 0, 9, 8),
      child: SizedBox(
        height: 25,
        child: Row(
          children: [
            if (iconUrls.isNotEmpty) _buildPosterAvatars(iconUrls),
            const SizedBox(width: 6),
            if (infoText.isNotEmpty)
              Expanded(
                child: Text(
                  infoText,
                  style: const TextStyle(
                    fontSize: 10,
                    color: Color(0xFFB7BCC0),
                    fontWeight: FontWeight.w400,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              )
            else
              const Spacer(),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: onPostTap,
              child: Container(
                width: 115,
                height: 25,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF1937EF), Color(0xFFFE1F56)],
                    begin: Alignment.centerLeft,
                    end: Alignment.centerRight,
                  ),
                  borderRadius: BorderRadius.circular(30),
                ),
                alignment: Alignment.centerLeft,
                padding: const EdgeInsets.only(left: 17),
                child: const Text(
                  '楽曲をVibeに追加',
                  style: TextStyle(
                    fontSize: 10,
                    color: Colors.white,
                    fontWeight: FontWeight.w400,
                    letterSpacing: -0.2,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 投稿者のアイコンを重ねて表示
  Widget _buildPosterAvatars(List<String> iconUrls) {
    const size = 25.0;
    const overlap = 5.5;
    final total = iconUrls.length;
    final width = size + (total - 1) * (size - overlap);

    return SizedBox(
      width: width,
      height: size,
      child: Stack(
        children: [
          for (int i = 0; i < total; i++)
            Positioned(
              left: i * (size - overlap),
              child: Container(
                width: size,
                height: size,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: AppColors.background, width: 1),
                ),
                child: ClipOval(
                  child: CachedNetworkImage(
                    imageUrl: iconUrls[i],
                    width: size,
                    height: size,
                    fit: BoxFit.cover,
                    errorWidget: (_, __, ___) => Container(
                      color: Colors.grey[700],
                      child: const Icon(Icons.person, color: Colors.white54, size: 12),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// 空状態
  Widget _buildEmpty() {
    return Container(
      color: AppColors.background,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Text(
              'Vibe',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: Colors.white.withValues(alpha: 0.6),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(
              '今日のVibeお題はありません',
              style: TextStyle(
                fontSize: 14,
                color: Colors.white.withValues(alpha: 0.6),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

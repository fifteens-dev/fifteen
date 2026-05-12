import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import '../../models/post_model.dart';
import '../../models/vibe_ranking_item.dart';
import '../../models/vibe_topic_model.dart';
import 'widgets/vibe_post_card.dart';
import 'widgets/vibe_song_list_item.dart';

/// Vibeプレイリスト画面の「曲リスト」タブ。
///
/// 表示専用の StatelessWidget。タップ系のアクションはすべてコールバックとして親に委譲する。
class VibeTracksTab extends StatelessWidget {
  final VibeTopicModel topic;
  final List<VibeRankingItem> sortedRanking;
  final List<String> summaryImages;
  final int totalUsers;
  final PostModel? currentPost;

  /// 「投稿」タブに切り替えるためのコールバック（青枠サムネタップ）
  final VoidCallback onJumpToPostsTab;

  /// 「楽曲をVibeに追加」グラデーションボタン／空状態CTAタップ
  final VoidCallback onAddVibeTap;

  /// 曲行タップ（楽曲モーダル表示）
  final void Function(VibeRankingItem item) onSongTap;

  /// 行内の投稿ボタンタップ（指定楽曲で投稿フローへ）
  final void Function(VibeRankingItem item) onSongPostTap;

  /// 行内の保存トグルタップ。対象 post がない場合は null
  final VoidCallback? Function(VibeRankingItem item) onSongSaveTap;

  /// 曲行に紐づく投稿の保存状態を判定するクロージャ
  final bool Function(VibeRankingItem item) isSongSaved;

  const VibeTracksTab({
    super.key,
    required this.topic,
    required this.sortedRanking,
    required this.summaryImages,
    required this.totalUsers,
    required this.currentPost,
    required this.onJumpToPostsTab,
    required this.onAddVibeTap,
    required this.onSongTap,
    required this.onSongPostTap,
    required this.onSongSaveTap,
    required this.isSongSaved,
  });

  String _fmt(int n) {
    if (n >= 10000) {
      return '${(n / 10000).toStringAsFixed(n % 10000 != 0 ? 1 : 0)}万';
    }
    if (n >= 1000) {
      return '${(n / 1000).toStringAsFixed(n % 1000 != 0 ? 1 : 0)}K';
    }
    return n.toString();
  }

  @override
  Widget build(BuildContext context) {
    final itemCount = sortedRanking.length;
    final songListHeight = itemCount > 0 ? itemCount * 64 - 16 : 200;
    final totalHeight = 318 + songListHeight + 32;

    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14),
        child: SizedBox(
          width: 374,
          height: totalHeight.toDouble(),
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              // サマリー画像 2×2
              Positioned(
                left: 47,
                top: 10,
                width: 280,
                height: 186,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: _SummaryGrid(urls: summaryImages),
                ),
              ),
              // タイトル
              Positioned(
                left: 0,
                top: 208,
                right: 0,
                child: Text(
                  '#${topic.title}',
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                    letterSpacing: -0.11,
                    height: 1.0,
                  ),
                ),
              ),
              // サブテキスト
              Positioned(
                left: 0,
                top: 235,
                right: 0,
                child: Text(
                  '🔥${_fmt(totalUsers)}人がこのVibeに追加',
                  style: const TextStyle(
                    fontSize: 10,
                    color: Color(0xFFA8A8A8),
                    height: 1.9,
                  ),
                ),
              ),
              // アクションボタン行
              Positioned(
                left: 0,
                top: 266,
                width: 374,
                height: 40,
                child: _ActionButtons(
                  currentPost: currentPost,
                  onJumpToPosts: onJumpToPostsTab,
                  onAddVibe: onAddVibeTap,
                ),
              ),
              // 曲リスト or 空状態
              Positioned(
                left: 0,
                top: 318,
                width: 374,
                child: itemCount > 0
                    ? _SongList(
                        items: sortedRanking,
                        onTap: onSongTap,
                        onPostTap: onSongPostTap,
                        onSaveTap: onSongSaveTap,
                        isSaved: isSongSaved,
                      )
                    : _EmptyState(onCtaTap: onAddVibeTap),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── サマリーグリッド ─────────────────────────

class _SummaryGrid extends StatelessWidget {
  final List<String> urls;
  const _SummaryGrid({required this.urls});

  bool _hasUrl(int i) => i < urls.length && urls[i].isNotEmpty;

  Widget _photoCell(int i) {
    if (!_hasUrl(i)) return Container(color: Colors.grey[850]);
    return ClipRect(
      child: SizedBox.expand(
        child: CachedNetworkImage(
          imageUrl: urls[i],
          fit: BoxFit.fitHeight,
          alignment: Alignment.center,
          width: double.infinity,
          height: double.infinity,
          errorWidget: (_, __, ___) => Container(color: Colors.grey[850]),
        ),
      ),
    );
  }

  Widget _jacketCell(int i) {
    if (!_hasUrl(i)) return Container(color: Colors.grey[850]);
    return SizedBox.expand(
      child: CachedNetworkImage(
        imageUrl: urls[i],
        fit: BoxFit.cover,
        width: double.infinity,
        height: double.infinity,
        errorWidget: (_, __, ___) => Container(color: Colors.grey[850]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Row(
        children: [
          Expanded(child: _photoCell(0)),
          const SizedBox(width: 1),
          Expanded(child: _photoCell(1)),
          const SizedBox(width: 1),
          Expanded(
            child: Column(
              children: [
                Expanded(child: _jacketCell(2)),
                const SizedBox(height: 1),
                Expanded(child: _jacketCell(3)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── アクションボタン行 ───────────────────────

class _ActionButtons extends StatelessWidget {
  final PostModel? currentPost;
  final VoidCallback onJumpToPosts;
  final VoidCallback onAddVibe;

  const _ActionButtons({
    required this.currentPost,
    required this.onJumpToPosts,
    required this.onAddVibe,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 40,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // 青枠サムネ
          Positioned(
            left: 0,
            top: 0,
            width: 24,
            height: 40,
            child: GestureDetector(
              onTap: onJumpToPosts,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Positioned(
                    left: 2.5,
                    top: 2.5,
                    right: 2.5,
                    bottom: 2.5,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: currentPost != null
                          ? VibePostCard.photoBackgroundOf(currentPost!)
                          : Container(color: Colors.grey[900]),
                    ),
                  ),
                  Positioned.fill(
                    child: IgnorePointer(
                      child: Image.asset(
                        'assets/images/vibe_song_frame.png',
                        fit: BoxFit.fill,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          // グラデーションボタン
          Positioned(
            left: 35,
            top: 0,
            width: 181,
            height: 40,
            child: GestureDetector(
              onTap: onAddVibe,
              child: Container(
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF1937EF), Color(0xFFFE1F56)],
                    begin: Alignment.centerLeft,
                    end: Alignment.centerRight,
                  ),
                  borderRadius: BorderRadius.circular(30),
                ),
                child: Stack(
                  children: [
                    Positioned(
                      left: 23,
                      top: 8,
                      width: 24,
                      height: 24,
                      child: Center(
                        child: Image.asset(
                          'assets/icons/Vibe.png',
                          width: 19,
                          height: 19,
                          fit: BoxFit.contain,
                          errorBuilder: (_, __, ___) => const Icon(
                              Icons.music_note,
                              color: Colors.white,
                              size: 19),
                        ),
                      ),
                    ),
                    const Positioned(
                      left: 54,
                      top: 12,
                      child: Text(
                        '楽曲をVibeに追加',
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.white,
                          letterSpacing: -0.26,
                          height: 1.0,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── 空状態 ─────────────────────────────────

class _EmptyState extends StatelessWidget {
  final VoidCallback onCtaTap;
  const _EmptyState({required this.onCtaTap});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          const SizedBox(height: 8),
          const Text(
            'まだ曲が追加されていません',
            style: TextStyle(
              fontSize: 14,
              color: Color(0xFFA8A8A8),
              height: 1.4,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          GestureDetector(
            onTap: onCtaTap,
            behavior: HitTestBehavior.opaque,
            child: Container(
              height: 44,
              padding: const EdgeInsets.symmetric(horizontal: 24),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF1937EF), Color(0xFFFE1F56)],
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                ),
                borderRadius: BorderRadius.circular(30),
              ),
              alignment: Alignment.center,
              child: const Text(
                '最初の曲をVibeに追加',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                  letterSpacing: -0.28,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── 曲リスト ───────────────────────────────

class _SongList extends StatelessWidget {
  final List<VibeRankingItem> items;
  final void Function(VibeRankingItem item) onTap;
  final void Function(VibeRankingItem item) onPostTap;
  final VoidCallback? Function(VibeRankingItem item) onSaveTap;
  final bool Function(VibeRankingItem item) isSaved;

  const _SongList({
    required this.items,
    required this.onTap,
    required this.onPostTap,
    required this.onSaveTap,
    required this.isSaved,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 374,
      height: items.length * 64 - 16,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          for (int i = 0; i < items.length; i++)
            Positioned(
              left: 0,
              top: (i * 64).toDouble(),
              width: 374,
              height: 48,
              child: VibeSongListItem(
                item: items[i],
                isSaved: isSaved(items[i]),
                onTap: () => onTap(items[i]),
                onPostTap: () => onPostTap(items[i]),
                onSaveTap: onSaveTap(items[i]),
              ),
            ),
        ],
      ),
    );
  }
}

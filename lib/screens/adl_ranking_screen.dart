import 'package:flutter/material.dart';
import '../constants/app_colors.dart';
import '../models/adl_team_model.dart';
import '../services/adl_service.dart';
import 'adl_team_playlist_screen.dart';

/// ADLチームランキング画面（ユーザー向け）
class AdlRankingScreen extends StatelessWidget {
  const AdlRankingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final adl = AdlService();

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            // ヘッダー
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: const Icon(Icons.close, color: Colors.white),
                  ),
                  const SizedBox(width: 16),
                  const Expanded(
                    child: Text(
                      'ランキング',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const Icon(Icons.emoji_events,
                      color: Color(0xFFFFD700), size: 22),
                ],
              ),
            ),
            const Divider(color: AppColors.divider, height: 1),

            // ランキングリスト
            Expanded(
              child: StreamBuilder<List<AdlTeamModel>>(
                stream: adl.watchFixedTeams(),
                builder: (ctx, snap) {
                  if (!snap.hasData) {
                    return const Center(
                      child: CircularProgressIndicator(color: Colors.white),
                    );
                  }
                  final teams = snap.data!;
                  if (teams.isEmpty) {
                    return const Center(
                      child: Text('班がまだありません',
                          style: TextStyle(color: Colors.grey)),
                    );
                  }
                  return ListView.separated(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 12),
                    itemCount: teams.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (_, i) => _RankCard(
                        rank: i + 1,
                        team: teams[i],
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => AdlTeamPlaylistScreen(
                                teamId: teams[i].teamId,
                              ),
                            ),
                          );
                        },
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
}

class _RankCard extends StatelessWidget {
  final int rank;
  final AdlTeamModel team;
  final VoidCallback onTap;
  const _RankCard({required this.rank, required this.team, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final rankMeta = switch (rank) {
      1 => (const Color(0xFFFFD700), '🥇'),
      2 => (const Color(0xFFC0C0C0), '🥈'),
      3 => (const Color(0xFFCD7F32), '🥉'),
      _ => (Colors.grey as Color, '$rank'),
    };

    return GestureDetector(
      onTap: onTap,
      child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: rank == 1
            ? const Color(0xFFFFD700).withValues(alpha: 0.12)
            : AppColors.surfaceLight,
        borderRadius: BorderRadius.circular(14),
        border: rank == 1
            ? Border.all(
                color: const Color(0xFFFFD700).withValues(alpha: 0.4),
                width: 1)
            : null,
      ),
      child: Row(
        children: [
          // 順位バッジ
          SizedBox(
            width: 40,
            child: rank <= 3
                ? Text(rankMeta.$2,
                    style: const TextStyle(fontSize: 24),
                    textAlign: TextAlign.center)
                : Text(
                    '${rankMeta.$2}',
                    style: TextStyle(
                        color: rankMeta.$1,
                        fontWeight: FontWeight.w800,
                        fontSize: 18),
                    textAlign: TextAlign.center,
                  ),
          ),
          const SizedBox(width: 12),
          // 班名・人数
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  team.name,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  '${team.memberCount}人参加',
                  style: const TextStyle(color: Colors.grey, fontSize: 12),
                ),
              ],
            ),
          ),
          // いいね数
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '${team.likeCount}',
                style: TextStyle(
                  color: rankMeta.$1,
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const Text('いいね',
                  style: TextStyle(color: Colors.grey, fontSize: 11)),
            ],
          ),
          const SizedBox(width: 8),
          const Icon(Icons.chevron_right, color: Colors.grey, size: 18),
        ],
      ),
      ),
    );
  }
}

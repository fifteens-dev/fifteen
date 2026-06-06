import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import '../constants/app_colors.dart';
import '../models/adl_team_model.dart';
import '../services/adl_service.dart';
import 'adl_team_playlist_screen.dart';
import 'other_user_profile_screen.dart';

/// ADLランキング画面（ユーザー向け）
///
/// 2タブ構成:
/// - チーム賞: 9班を likeCount 降順で表示
/// - 個人賞: invite_usages を集計し、招待人数の多いユーザーを表示
class AdlRankingScreen extends StatefulWidget {
  const AdlRankingScreen({super.key});

  @override
  State<AdlRankingScreen> createState() => _AdlRankingScreenState();
}

class _AdlRankingScreenState extends State<AdlRankingScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tab;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: StreamBuilder<bool>(
          stream: AdlService().watchResultFinalized(),
          builder: (ctx, snap) {
            final finalized = snap.data == true;
            return Column(
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 12),
                  child: Row(
                    children: [
                      GestureDetector(
                        onTap: () => Navigator.pop(context),
                        child: const Icon(Icons.close, color: Colors.white),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Text(
                          finalized ? '最終結果' : 'ランキング',
                          style: TextStyle(
                            color: finalized
                                ? const Color(0xFFFFD700)
                                : Colors.white,
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
                if (finalized) const _FinalizedBanner(),
                TabBar(
                  controller: _tab,
                  indicatorColor: AppColors.accentBlue,
                  labelColor: Colors.white,
                  unselectedLabelColor: Colors.grey,
                  labelStyle: const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w700),
                  tabs: const [
                    Tab(text: 'チーム賞'),
                    Tab(text: '個人賞'),
                  ],
                ),
                const Divider(color: AppColors.divider, height: 1),
                Expanded(
                  child: TabBarView(
                    controller: _tab,
                    children: [
                      _TeamRankingTab(finalized: finalized),
                      _InviteRankingTab(finalized: finalized),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// 確定モード時のヘッダーバナー
class _FinalizedBanner extends StatelessWidget {
  const _FinalizedBanner();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFFFD700), Color(0xFFFFAA00)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(12),
      ),
      child: const Row(
        children: [
          Icon(Icons.workspace_premium, color: Colors.black, size: 22),
          SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '結果が確定しました',
                  style: TextStyle(
                    color: Colors.black,
                    fontWeight: FontWeight.w800,
                    fontSize: 14,
                  ),
                ),
                SizedBox(height: 2),
                Text(
                  'チーム賞 上位3班 / 個人賞 上位3名 が受賞対象です',
                  style: TextStyle(color: Colors.black87, fontSize: 11),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ---- チーム賞タブ ----

class _TeamRankingTab extends StatelessWidget {
  final bool finalized;
  const _TeamRankingTab({this.finalized = false});

  @override
  Widget build(BuildContext context) {
    final adl = AdlService();
    return StreamBuilder<List<AdlTeamModel>>(
      stream: adl.watchFixedTeams(),
      builder: (ctx, snap) {
        if (!snap.hasData) {
          return const Center(
            child: CupertinoActivityIndicator(color: Colors.white, radius: 14),
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
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          itemCount: teams.length,
          separatorBuilder: (_, __) => const SizedBox(height: 8),
          itemBuilder: (_, i) => _TeamRankCard(
            rank: i + 1,
            team: teams[i],
            finalized: finalized,
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) =>
                      AdlTeamPlaylistScreen(teamId: teams[i].teamId),
                ),
              );
            },
          ),
        );
      },
    );
  }
}

class _TeamRankCard extends StatelessWidget {
  final int rank;
  final AdlTeamModel team;
  final VoidCallback onTap;
  final bool finalized;
  const _TeamRankCard({
    required this.rank,
    required this.team,
    required this.onTap,
    this.finalized = false,
  });

  @override
  Widget build(BuildContext context) {
    final rankMeta = switch (rank) {
      1 => (const Color(0xFFFFD700), '🥇'),
      2 => (const Color(0xFFC0C0C0), '🥈'),
      3 => (const Color(0xFFCD7F32), '🥉'),
      _ => (Colors.grey as Color, '$rank'),
    };
    final isWinner = finalized && rank <= 3;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: isWinner
              ? rankMeta.$1.withValues(alpha: 0.18)
              : (rank == 1
                  ? const Color(0xFFFFD700).withValues(alpha: 0.12)
                  : AppColors.surfaceLight),
          borderRadius: BorderRadius.circular(14),
          border: isWinner
              ? Border.all(color: rankMeta.$1, width: 1.5)
              : (rank == 1
                  ? Border.all(
                      color:
                          const Color(0xFFFFD700).withValues(alpha: 0.4),
                      width: 1)
                  : null),
        ),
        child: Row(
          children: [
            SizedBox(
              width: 40,
              child: rank <= 3
                  ? Text(rankMeta.$2,
                      style: const TextStyle(fontSize: 24),
                      textAlign: TextAlign.center)
                  : Text(
                      rankMeta.$2,
                      style: TextStyle(
                          color: rankMeta.$1,
                          fontWeight: FontWeight.w800,
                          fontSize: 18),
                      textAlign: TextAlign.center,
                    ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    team.name,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w700),
                  ),
                  Text(
                    '${team.memberCount}人参加',
                    style: const TextStyle(color: Colors.grey, fontSize: 12),
                  ),
                  if (isWinner) ...[
                    const SizedBox(height: 4),
                    _PrizeBadge(text: _teamPrizeText(rank), color: rankMeta.$1),
                  ],
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '${team.likeCount}',
                  style: TextStyle(
                      color: rankMeta.$1,
                      fontSize: 24,
                      fontWeight: FontWeight.w800),
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

  static String _teamPrizeText(int rank) {
    switch (rank) {
      case 1:
        return 'Amazonギフト 3万円';
      case 2:
        return 'Amazonギフト 2万円';
      case 3:
        return 'Amazonギフト 1万円';
      default:
        return '';
    }
  }
}

// ---- 個人賞タブ ----

class _InviteRankingTab extends StatefulWidget {
  final bool finalized;
  const _InviteRankingTab({this.finalized = false});

  @override
  State<_InviteRankingTab> createState() => _InviteRankingTabState();
}

class _InviteRankingTabState extends State<_InviteRankingTab> {
  late Future<List<InviteRankingEntry>> _future;

  @override
  void initState() {
    super.initState();
    _future = _fetch();
  }

  /// 個人賞期間（inviteRankingStart〜inviteRankingEnd）が設定されていれば
  /// その範囲のみで集計、未設定なら全期間累計を返す。
  Future<List<InviteRankingEntry>> _fetch() async {
    final adl = AdlService();
    final periods = await adl.getAdlPeriods();
    return adl.getInviteRanking(
      from: periods.inviteRankingStart,
      to: periods.inviteRankingEnd,
      limit: 20,
    );
  }

  Future<void> _refresh() async {
    setState(() {
      _future = _fetch();
    });
    await _future;
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<InviteRankingEntry>>(
      future: _future,
      builder: (ctx, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(
            child: CupertinoActivityIndicator(color: Colors.white, radius: 14),
          );
        }
        if (snap.hasError) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.error_outline, color: Colors.red, size: 36),
                const SizedBox(height: 8),
                Text('読み込みに失敗しました',
                    style: TextStyle(color: Colors.grey[400], fontSize: 13)),
                const SizedBox(height: 12),
                TextButton(
                    onPressed: _refresh,
                    child: const Text('再試行',
                        style: TextStyle(color: AppColors.accentBlue))),
              ],
            ),
          );
        }
        final entries = snap.data ?? const <InviteRankingEntry>[];
        if (entries.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.person_add_alt_1,
                      color: Colors.grey, size: 36),
                  const SizedBox(height: 12),
                  Text(
                    'まだ招待実績がありません\n友達を招待すると、ここに名前が並びます',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.grey[400], fontSize: 13),
                  ),
                ],
              ),
            ),
          );
        }
        return RefreshIndicator(
          color: Colors.white,
          backgroundColor: AppColors.surfaceLight,
          onRefresh: _refresh,
          child: ListView.separated(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            itemCount: entries.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (_, i) => _InviteRankCard(
              rank: i + 1,
              entry: entries[i],
              finalized: widget.finalized,
            ),
          ),
        );
      },
    );
  }
}

class _InviteRankCard extends StatelessWidget {
  final int rank;
  final InviteRankingEntry entry;
  final bool finalized;
  const _InviteRankCard({
    required this.rank,
    required this.entry,
    this.finalized = false,
  });

  @override
  Widget build(BuildContext context) {
    final rankMeta = switch (rank) {
      1 => (const Color(0xFFFFD700), '🥇'),
      2 => (const Color(0xFFC0C0C0), '🥈'),
      3 => (const Color(0xFFCD7F32), '🥉'),
      _ => (Colors.grey as Color, '$rank'),
    };
    final isWinner = finalized && rank <= 3;

    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => OtherUserProfileScreen(userId: entry.uid),
          ),
        );
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: isWinner
              ? rankMeta.$1.withValues(alpha: 0.18)
              : (rank == 1
                  ? const Color(0xFFFFD700).withValues(alpha: 0.12)
                  : AppColors.surfaceLight),
          borderRadius: BorderRadius.circular(14),
          border: isWinner
              ? Border.all(color: rankMeta.$1, width: 1.5)
              : (rank == 1
                  ? Border.all(
                      color:
                          const Color(0xFFFFD700).withValues(alpha: 0.4),
                      width: 1)
                  : null),
        ),
        child: Row(
          children: [
            SizedBox(
              width: 40,
              child: rank <= 3
                  ? Text(rankMeta.$2,
                      style: const TextStyle(fontSize: 24),
                      textAlign: TextAlign.center)
                  : Text(
                      rankMeta.$2,
                      style: TextStyle(
                          color: rankMeta.$1,
                          fontWeight: FontWeight.w800,
                          fontSize: 18),
                      textAlign: TextAlign.center,
                    ),
            ),
            const SizedBox(width: 12),
            _Avatar(
                profileImageUrl: entry.profileImageUrl,
                displayName: entry.displayName),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    entry.displayName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w700),
                  ),
                  if (entry.username.isNotEmpty)
                    Text(
                      '@${entry.username}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style:
                          const TextStyle(color: Colors.grey, fontSize: 12),
                    ),
                  if (isWinner) ...[
                    const SizedBox(height: 4),
                    _PrizeBadge(
                        text: 'Amazonギフト 1万円', color: rankMeta.$1),
                  ],
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '${entry.inviteCount}',
                  style: TextStyle(
                      color: rankMeta.$1,
                      fontSize: 22,
                      fontWeight: FontWeight.w800),
                ),
                const Text('招待',
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

/// 確定モード時に上位3位に表示する賞金バッジ
class _PrizeBadge extends StatelessWidget {
  final String text;
  final Color color;
  const _PrizeBadge({required this.text, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.6), width: 0.5),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.card_giftcard, color: color, size: 11),
          const SizedBox(width: 4),
          Text(
            text,
            style: TextStyle(
              color: color,
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  final String? profileImageUrl;
  final String displayName;
  const _Avatar({required this.profileImageUrl, required this.displayName});

  @override
  Widget build(BuildContext context) {
    final hasUrl = profileImageUrl != null && profileImageUrl!.isNotEmpty;
    return Container(
      width: 40,
      height: 40,
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        color: AppColors.surfaceLighter,
      ),
      clipBehavior: Clip.antiAlias,
      child: hasUrl
          ? CachedNetworkImage(
              imageUrl: profileImageUrl!,
              fit: BoxFit.cover,
              errorWidget: (_, __, ___) => _placeholder(),
            )
          : _placeholder(),
    );
  }

  Widget _placeholder() {
    final initial =
        displayName.isNotEmpty ? displayName[0].toUpperCase() : '?';
    return Center(
      child: Text(
        initial,
        style: const TextStyle(
            color: Colors.white,
            fontSize: 16,
            fontWeight: FontWeight.bold),
      ),
    );
  }
}

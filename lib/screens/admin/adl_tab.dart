import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../constants/app_colors.dart';
import '../../models/adl_team_model.dart';
import '../../services/adl_service.dart';
import '../../widgets/common/app_toast.dart';
import '../adl_team_playlist_screen.dart';

/// 管理パネル ADLイベントタブ
///
/// ADLイベントは1回限りの運用のため、ON/OFFトグルのみのシンプル構成にしてある。
/// 9つの固定班（adl_house ほか）は seed_adl_teams.js で事前作成済み。
class AdlTab extends StatefulWidget {
  const AdlTab({super.key});

  @override
  State<AdlTab> createState() => _AdlTabState();
}

class _AdlTabState extends State<AdlTab> {
  final _adl = AdlService();

  bool _adlActive = false;
  bool _loading = true;
  bool _toggleBusy = false;
  bool _recomputing = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final active = await _adl.isAdlModeActive();
    if (mounted) {
      setState(() {
        _adlActive = active;
        _loading = false;
      });
    }
  }

  Future<void> _toggleAdlMode(bool value) async {
    setState(() => _toggleBusy = true);
    await _adl.setAdlMode(value);
    if (!mounted) return;
    setState(() {
      _adlActive = value;
      _toggleBusy = false;
    });
    AppToast.show(context, value ? 'ADLモードをONにしました' : 'ADLモードをOFFにしました');
  }

  Future<void> _recompute() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surfaceLight,
        title: const Text('集計を再計算しますか？',
            style: TextStyle(color: Colors.white, fontSize: 16)),
        content: const Text(
          '全投稿を走査して各班の likeCount / postCount を再計算します。\n'
          'ドリフトしている場合の修正用です。',
          style: TextStyle(color: Colors.grey, fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('キャンセル',
                style: TextStyle(color: Colors.grey)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('実行',
                style: TextStyle(color: AppColors.accentBlue)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _recomputing = true);
    try {
      final totals = await _adl.recomputeLikeCounts();
      if (!mounted) return;
      final teamCount = totals.length;
      AppToast.show(context, '$teamCount班の集計を再計算しました');
    } catch (e) {
      if (!mounted) return;
      AppToast.show(context, '再集計に失敗しました: $e');
    } finally {
      if (mounted) setState(() => _recomputing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(
          child: CupertinoActivityIndicator(color: Colors.white));
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // ── ADLモードトグル ──
        _Section(
          title: 'ADLモード',
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _adlActive ? 'ON（開催中）' : 'OFF',
                    style: TextStyle(
                      color: _adlActive ? AppColors.success : Colors.grey,
                      fontWeight: FontWeight.w600,
                      fontSize: 15,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _adlActive
                        ? '参加者が設定画面から班に参加できます'
                        : 'ONにすると参加者が班コードで参加可能になります',
                    style: const TextStyle(color: Colors.grey, fontSize: 11),
                  ),
                ],
              ),
              _toggleBusy
                  ? const SizedBox(
                      width: 28,
                      height: 28,
                      child: CupertinoActivityIndicator(color: Colors.white),
                    )
                  : CupertinoSwitch(
                      value: _adlActive,
                      activeTrackColor: AppColors.success,
                      onChanged: _toggleAdlMode,
                    ),
            ],
          ),
        ),

        const SizedBox(height: 16),

        // ── 9班ストリーム（サマリと班一覧を共有） ──
        StreamBuilder<List<AdlTeamModel>>(
          stream: _adl.watchFixedTeams(),
          builder: (ctx, snap) {
            if (!snap.hasData) {
              return const _Section(
                title: '集計',
                child: Center(
                  child: CupertinoActivityIndicator(color: Colors.white),
                ),
              );
            }
            final teams = snap.data!;
            if (teams.isEmpty) {
              return const _Section(
                title: '集計',
                child: Text(
                  '班データがありません。scripts/seed_adl_teams.js を実行してください',
                  style: TextStyle(color: Colors.grey, fontSize: 13),
                ),
              );
            }
            return Column(
              children: [
                _SummaryCard(teams: teams),
                const SizedBox(height: 16),
                _Section(
                  title: '班一覧 / ランキング',
                  trailing: _recomputing
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CupertinoActivityIndicator(
                              color: Colors.white),
                        )
                      : TextButton.icon(
                          onPressed: _recompute,
                          icon: const Icon(Icons.refresh,
                              size: 16, color: AppColors.accentBlue),
                          label: const Text('再集計',
                              style: TextStyle(
                                  color: AppColors.accentBlue,
                                  fontSize: 12)),
                          style: TextButton.styleFrom(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 4),
                            minimumSize: const Size(0, 28),
                          ),
                        ),
                  child: Column(
                    children: teams.asMap().entries.map((entry) {
                      return _TeamTile(
                        rank: entry.key + 1,
                        team: entry.value,
                      );
                    }).toList(),
                  ),
                ),
              ],
            );
          },
        ),
      ],
    );
  }
}

// ---- サブウィジェット ----

class _Section extends StatelessWidget {
  final String title;
  final Widget child;
  final Widget? trailing;

  const _Section({required this.title, required this.child, this.trailing});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surfaceLight,
        borderRadius: BorderRadius.circular(12),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(title,
                  style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 14)),
              if (trailing != null) trailing!,
            ],
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  final List<AdlTeamModel> teams;

  const _SummaryCard({required this.teams});

  @override
  Widget build(BuildContext context) {
    int totalMembers = 0;
    int totalPosts = 0;
    int totalLikes = 0;
    for (final t in teams) {
      totalMembers += t.memberCount;
      totalPosts += t.postCount;
      totalLikes += t.likeCount;
    }

    return Container(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF1937EF), Color(0xFFFE1F56)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(12),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '全体サマリ',
            style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
                fontSize: 14),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _SummaryStat(label: '投稿', value: totalPosts),
              _SummaryStat(label: 'メンバー', value: totalMembers),
              _SummaryStat(label: 'いいね', value: totalLikes),
            ],
          ),
        ],
      ),
    );
  }
}

class _SummaryStat extends StatelessWidget {
  final String label;
  final int value;

  const _SummaryStat({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          '$value',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 24,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: const TextStyle(color: Colors.white70, fontSize: 11),
        ),
      ],
    );
  }
}

class _TeamTile extends StatelessWidget {
  final int rank;
  final AdlTeamModel team;

  const _TeamTile({required this.rank, required this.team});

  @override
  Widget build(BuildContext context) {
    final rankColors = [
      const Color(0xFFFFD700), // gold
      const Color(0xFFC0C0C0), // silver
      const Color(0xFFCD7F32), // bronze
    ];
    final rankColor = rank <= 3 ? rankColors[rank - 1] : Colors.grey;

    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => AdlTeamPlaylistScreen(teamId: team.teamId),
          ),
        );
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: AppColors.surfaceLighter,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            // 順位
            SizedBox(
              width: 28,
              child: Text(
                '$rank',
                style: TextStyle(
                    color: rankColor,
                    fontWeight: FontWeight.w800,
                    fontSize: 16),
              ),
            ),
            // 班名 + コード + 投稿数
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(team.name,
                      style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                          fontSize: 14)),
                  Row(
                    children: [
                      Text(
                        'コード: ${team.inviteCode}',
                        style: const TextStyle(
                            color: Colors.grey,
                            fontSize: 12,
                            fontFamily: 'monospace'),
                      ),
                      const SizedBox(width: 4),
                      GestureDetector(
                        onTap: () {
                          Clipboard.setData(
                              ClipboardData(text: team.inviteCode));
                          AppToast.show(context, 'コードをコピーしました');
                        },
                        child: const Icon(Icons.copy,
                            color: Colors.grey, size: 14),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      _MetaChip(
                          icon: Icons.people,
                          label: '${team.memberCount}人'),
                      const SizedBox(width: 8),
                      _MetaChip(
                          icon: Icons.photo_library_outlined,
                          label: '${team.postCount}件'),
                    ],
                  ),
                ],
              ),
            ),
            // いいね数
            Column(
              children: [
                Text(
                  '${team.likeCount}',
                  style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                      fontSize: 18),
                ),
                const Text('いいね',
                    style: TextStyle(color: Colors.grey, fontSize: 10)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _MetaChip extends StatelessWidget {
  final IconData icon;
  final String label;

  const _MetaChip({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: Colors.grey, size: 11),
        const SizedBox(width: 3),
        Text(label,
            style: const TextStyle(color: Colors.grey, fontSize: 11)),
      ],
    );
  }
}

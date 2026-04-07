import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'analytics_detail_screen.dart';

/// 集計データタブ（管理者パネル内）
class AnalyticsTab extends StatefulWidget {
  const AnalyticsTab({super.key});

  @override
  State<AnalyticsTab> createState() => _AnalyticsTabState();
}

class _AnalyticsTabState extends State<AnalyticsTab> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  bool _isLoading = false;
  _AnalyticsData? _data;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<int?> _countQuery(Query query) async {
    try {
      final snap = await query.count().get();
      return snap.count ?? 0;
    } catch (_) {
      return null;
    }
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);

    final now = DateTime.now();
    final todayStr =
        '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    final monthKey =
        '${now.year}-${now.month.toString().padLeft(2, '0')}';
    final todayTs = Timestamp.fromDate(DateTime(now.year, now.month, now.day));

    // 各クエリを独立実行（一部失敗しても他は表示）
    final results = await Future.wait([
      // 0: 累計DL数
      _countQuery(_firestore.collection('users')),
      // 1: 日次DL数
      _countQuery(_firestore.collection('users')
          .where('createdAt', isGreaterThanOrEqualTo: todayTs)),
      // 2: DAU — app_open_events で date == today（1ユーザー1日1件）
      _countQuery(_firestore.collection('app_open_events')
          .where('date', isEqualTo: todayStr)),
      // 3: MAU — app_open_events で monthKey == 今月、ユニークuserIdをメモリで集計
      _countDistinctUsersThisMonth(monthKey),
      // 4: 投稿者数
      _countQuery(_firestore.collection('users')
          .where('postsCount', isGreaterThan: 0)),
      // 5: 投稿完了数（累計）
      _countQuery(_firestore.collection('posts')),
      // 6: 投稿完了数（今日）
      _countQuery(_firestore.collection('posts')
          .where('createdAt', isGreaterThanOrEqualTo: todayTs)),
      // 7: 投稿開始数（今日）— createdAt のみで絞り、type をメモリフィルタ
      _countPostStartsToday(todayTs),
    ]);

    if (mounted) {
      setState(() {
        _data = _AnalyticsData(
          totalUsers: results[0],
          dailyNewUsers: results[1],
          dau: results[2],
          mau: results[3],
          totalPosters: results[4],
          totalPostCompletions: results[5],
          postCompletionsToday: results[6],
          postStartsToday: results[7],
        );
        _isLoading = false;
      });
    }
  }

  /// MAU: 今月の app_open_events から distinct userId を数える
  Future<int?> _countDistinctUsersThisMonth(String monthKey) async {
    try {
      final snap = await _firestore
          .collection('app_open_events')
          .where('monthKey', isEqualTo: monthKey)
          .get();
      return snap.docs
          .map((d) => d.data()['userId'] as String?)
          .whereType<String>()
          .toSet()
          .length;
    } catch (_) {
      return null;
    }
  }

  /// 投稿開始数: createdAt のみで絞り type をメモリフィルタ（複合インデックス不要）
  Future<int?> _countPostStartsToday(Timestamp todayTs) async {
    try {
      final snap = await _firestore
          .collection('analytics_events')
          .where('createdAt', isGreaterThanOrEqualTo: todayTs)
          .get();
      return snap.docs.where((d) => d.data()['type'] == 'post_start').length;
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    return CustomScrollView(
      physics: const BouncingScrollPhysics(
        parent: AlwaysScrollableScrollPhysics(),
      ),
      slivers: [
        CupertinoSliverRefreshControl(onRefresh: _load),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 40),
          sliver: SliverToBoxAdapter(
            child: _isLoading
                ? const Center(
                    child: Padding(
                      padding: EdgeInsets.only(top: 80),
                      child: CupertinoActivityIndicator(
                        color: Colors.white,
                        radius: 14,
                      ),
                    ),
                  )
                : _buildDashboard(context),
          ),
        ),
      ],
    );
  }

  Widget _buildDashboard(BuildContext context) {
    final d = _data;
    if (d == null) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionTitle('ユーザー', Icons.people_alt_outlined),
        const SizedBox(height: 12),
        _buildGrid([
          _MetricCard(
            label: '累計DL数',
            value: _fmt(d.totalUsers),
            subtitle: '全期間・登録者数',
            icon: Icons.download_outlined,
            color: const Color(0xFF5D8FFF),
            onTap: () => _openDetail(context, '累計DL数', const Color(0xFF5D8FFF), MetricSeriesType.cumulativeUsers),
          ),
          _MetricCard(
            label: '日次DL数',
            value: _fmt(d.dailyNewUsers),
            subtitle: '今日の新規登録',
            icon: Icons.person_add_outlined,
            color: const Color(0xFF4CAF82),
            onTap: () => _openDetail(context, '日次DL数', const Color(0xFF4CAF82), MetricSeriesType.dailyNewUsers),
          ),
          _MetricCard(
            label: 'DAU',
            value: _fmt(d.dau),
            subtitle: '今日のアクティブ',
            icon: Icons.today_outlined,
            color: const Color(0xFFFF8C42),
            onTap: () => _openDetail(context, 'DAU', const Color(0xFFFF8C42), MetricSeriesType.dau),
          ),
          _MetricCard(
            label: 'MAU',
            value: _fmt(d.mau),
            subtitle: '今月のアクティブ',
            icon: Icons.calendar_month_outlined,
            color: const Color(0xFFAB6FEB),
            onTap: () => _openDetail(context, 'MAU', const Color(0xFFAB6FEB), MetricSeriesType.mau),
          ),
        ]),

        const SizedBox(height: 28),

        _buildSectionTitle('投稿', Icons.music_note_outlined),
        const SizedBox(height: 12),
        _buildGrid([
          _MetricCard(
            label: '投稿者数',
            value: _fmt(d.totalPosters),
            subtitle: '日次ユニーク投稿者',
            icon: Icons.group_outlined,
            color: const Color(0xFF5D8FFF),
            onTap: () => _openDetail(context, '投稿者数（日次）', const Color(0xFF5D8FFF), MetricSeriesType.dailyPosters),
          ),
          _MetricCard(
            label: '投稿完了数',
            value: _fmt(d.totalPostCompletions),
            subtitle: '累計',
            icon: Icons.check_circle_outline,
            color: const Color(0xFF4CAF82),
            onTap: () => _openDetail(context, '投稿完了数（累計）', const Color(0xFF4CAF82), MetricSeriesType.cumulativePostCompletions),
          ),
          _MetricCard(
            label: '投稿開始数',
            value: _fmt(d.postStartsToday),
            subtitle: '今日',
            icon: Icons.play_circle_outline,
            color: const Color(0xFFFF8C42),
            onTap: () => _openDetail(context, '投稿開始数', const Color(0xFFFF8C42), MetricSeriesType.postStarts),
          ),
          _MetricCard(
            label: '投稿完了数',
            value: _fmt(d.postCompletionsToday),
            subtitle: '今日',
            icon: Icons.task_alt_outlined,
            color: const Color(0xFFAB6FEB),
            onTap: () => _openDetail(context, '投稿完了数（日次）', const Color(0xFFAB6FEB), MetricSeriesType.postCompletions),
          ),
        ]),

        // 投稿完了率（今日・開始数が1件以上のとき表示）
        if ((d.postStartsToday ?? 0) > 0) ...[
          const SizedBox(height: 16),
          _buildCompletionRateCard(d.postStartsToday!, d.postCompletionsToday ?? 0),
        ],
      ],
    );
  }

  void _openDetail(BuildContext context, String title, Color color, MetricSeriesType type) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => AnalyticsDetailScreen(
          title: title,
          color: color,
          seriesType: type,
        ),
      ),
    );
  }

  Widget _buildSectionTitle(String title, IconData icon) {
    return Row(
      children: [
        Icon(icon, color: Colors.white54, size: 16),
        const SizedBox(width: 6),
        Text(
          title,
          style: const TextStyle(
            color: Colors.white54,
            fontSize: 13,
            fontWeight: FontWeight.w600,
            letterSpacing: 1.0,
          ),
        ),
      ],
    );
  }

  Widget _buildGrid(List<_MetricCard> cards) {
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisSpacing: 10,
      mainAxisSpacing: 10,
      childAspectRatio: 1.5,
      children: cards,
    );
  }

  Widget _buildCompletionRateCard(int starts, int completions) {
    final rate = (completions / starts * 100).clamp(0.0, 100.0);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E2E),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white12),
      ),
      child: Row(
        children: [
          const Icon(Icons.percent, color: Colors.white38, size: 18),
          const SizedBox(width: 10),
          const Text(
            '今日の投稿完了率',
            style: TextStyle(color: Colors.white60, fontSize: 13),
          ),
          const Spacer(),
          Text(
            '${rate.toStringAsFixed(1)}%',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  String _fmt(int? n) {
    if (n == null) return '–';
    if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(1)}M';
    if (n >= 1000) return '${(n / 1000).toStringAsFixed(1)}K';
    return n.toString();
  }
}

class _AnalyticsData {
  final int? totalUsers;
  final int? dailyNewUsers;
  final int? dau;
  final int? mau;
  final int? totalPosters;
  final int? totalPostCompletions;
  final int? postCompletionsToday;
  final int? postStartsToday;

  const _AnalyticsData({
    this.totalUsers,
    this.dailyNewUsers,
    this.dau,
    this.mau,
    this.totalPosters,
    this.totalPostCompletions,
    this.postCompletionsToday,
    this.postStartsToday,
  });
}

class _MetricCard extends StatelessWidget {
  final String label;
  final String value;
  final String subtitle;
  final IconData icon;
  final Color color;
  final VoidCallback? onTap;

  const _MetricCard({
    required this.label,
    required this.value,
    required this.subtitle,
    required this.icon,
    required this.color,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isMissing = value == '–';
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
        decoration: BoxDecoration(
          color: const Color(0xFF1E1E2E),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isMissing ? Colors.white12 : color.withValues(alpha: 0.3),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                Icon(icon, color: isMissing ? Colors.white24 : color, size: 15),
                const SizedBox(width: 5),
                Expanded(
                  child: Text(
                    label,
                    style: TextStyle(
                      color: isMissing ? Colors.white24 : color,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (onTap != null && !isMissing)
                  Icon(Icons.chevron_right, color: color.withValues(alpha: 0.5), size: 14),
              ],
            ),
            Text(
              value,
              style: TextStyle(
                color: isMissing ? Colors.white24 : Colors.white,
                fontSize: 26,
                fontWeight: FontWeight.bold,
                height: 1.1,
              ),
            ),
            Text(
              subtitle,
              style: const TextStyle(color: Colors.white38, fontSize: 10),
            ),
          ],
        ),
      ),
    );
  }
}

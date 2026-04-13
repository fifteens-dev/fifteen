import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../widgets/common/app_toast.dart';

/// 集計メトリクスの時系列種別
enum MetricSeriesType {
  dailyNewUsers,            // 日次DL数
  cumulativeUsers,          // 累計DL数（累積）
  dau,                      // DAU（日次アクティブ）
  mau,                      // MAU（月次アクティブ）
  dailyPosters,             // 投稿者数（日次ユニーク投稿者）
  postStarts,               // 投稿開始数
  postCompletions,          // 投稿完了数（日次）
  cumulativePostCompletions,// 投稿完了数（累積）
}

class _DataPoint {
  final DateTime date;
  final int count;
  _DataPoint(this.date, this.count);
}

/// メトリクス詳細画面（折れ線グラフ + データ表）
class AnalyticsDetailScreen extends StatefulWidget {
  final String title;
  final Color color;
  final MetricSeriesType seriesType;

  const AnalyticsDetailScreen({
    super.key,
    required this.title,
    required this.color,
    required this.seriesType,
  });

  @override
  State<AnalyticsDetailScreen> createState() => _AnalyticsDetailScreenState();
}

class _AnalyticsDetailScreenState extends State<AnalyticsDetailScreen> {
  final _firestore = FirebaseFirestore.instance;
  bool _isLoading = true;
  List<_DataPoint> _points = [];
  String? _error;

  bool get _isMonthly => widget.seriesType == MetricSeriesType.mau;
  String get _periodLabel => _isMonthly ? '過去12ヶ月' : '過去30日間';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final points = await _fetchData();
      if (mounted) setState(() { _points = points; _isLoading = false; });
    } catch (e) {
      if (mounted) setState(() { _error = e.toString(); _isLoading = false; });
    }
  }

  // ──────────────────────────────────────────
  // データ取得
  // ──────────────────────────────────────────

  Future<List<_DataPoint>> _fetchData() async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    switch (widget.seriesType) {
      case MetricSeriesType.dailyNewUsers:
        return _fetchDailyFromCollection('users', 'createdAt', today);

      case MetricSeriesType.cumulativeUsers:
        return _fetchCumulative('users', 'createdAt', today);

      case MetricSeriesType.dau:
        return _fetchDauHistory(today);

      case MetricSeriesType.mau:
        return _fetchMauHistory(now);

      case MetricSeriesType.dailyPosters:
        return _fetchDailyDistinctPosters(today);

      case MetricSeriesType.postStarts:
        return _fetchPostStartsDaily(today);

      case MetricSeriesType.postCompletions:
        return _fetchDailyFromCollection('posts', 'createdAt', today);

      case MetricSeriesType.cumulativePostCompletions:
        return _fetchCumulative('posts', 'createdAt', today);
    }
  }

  /// 累計グラフ用：30日窓より前のベース件数 + 日次累積
  Future<List<_DataPoint>> _fetchCumulative(
    String collection,
    String dateField,
    DateTime today,
  ) async {
    final cutoff = today.subtract(const Duration(days: 29));

    // 窓より前の全件数をベースとして取得
    final baseSnap = await _firestore
        .collection(collection)
        .where(dateField, isLessThan: Timestamp.fromDate(cutoff))
        .count()
        .get();
    final base = baseSnap.count ?? 0;

    // 窓内の日次データを取得
    final daily = await _fetchDailyFromCollection(collection, dateField, today);

    // ベース＋累積和
    int running = base;
    return daily.map((p) {
      running += p.count;
      return _DataPoint(p.date, running);
    }).toList();
  }

  /// 単一コレクションを日付フィールドで過去30日分取得
  Future<List<_DataPoint>> _fetchDailyFromCollection(
    String collection,
    String dateField,
    DateTime today,
  ) async {
    final cutoff = today.subtract(const Duration(days: 29));
    final snap = await _firestore
        .collection(collection)
        .where(dateField, isGreaterThanOrEqualTo: Timestamp.fromDate(cutoff))
        .get();
    return _groupByDay(snap.docs, dateField, today);
  }

  /// analytics_events から post_start を日次集計（複合インデックス不要）
  Future<List<_DataPoint>> _fetchPostStartsDaily(DateTime today) async {
    final cutoff = today.subtract(const Duration(days: 29));
    final snap = await _firestore
        .collection('analytics_events')
        .where('createdAt', isGreaterThanOrEqualTo: Timestamp.fromDate(cutoff))
        .get();
    final filtered = snap.docs.where((d) {
      final data = d.data();
      return data['type'] == 'post_start';
    }).toList();
    return _groupByDay(filtered, 'createdAt', today);
  }

  /// posts から日ごとのユニーク投稿者数
  Future<List<_DataPoint>> _fetchDailyDistinctPosters(DateTime today) async {
    final cutoff = today.subtract(const Duration(days: 29));
    final snap = await _firestore
        .collection('posts')
        .where('createdAt', isGreaterThanOrEqualTo: Timestamp.fromDate(cutoff))
        .get();

    final Map<DateTime, Set<String>> usersByDay = {};
    for (final doc in snap.docs) {
      final data = doc.data();
      final ts = data['createdAt'] as Timestamp?;
      final userId = data['userId'] as String?;
      if (ts == null || userId == null) continue;
      final d = ts.toDate();
      final day = DateTime(d.year, d.month, d.day);
      usersByDay.putIfAbsent(day, () => {}).add(userId);
    }
    return List.generate(30, (i) {
      final date = today.subtract(Duration(days: 29 - i));
      return _DataPoint(date, usersByDay[date]?.length ?? 0);
    });
  }

  /// DAU 履歴：app_open_events の date フィールドで日別集計
  /// 1ユーザー1日1件のため count = distinct ユーザー数
  Future<List<_DataPoint>> _fetchDauHistory(DateTime today) async {
    final cutoff = today.subtract(const Duration(days: 29));
    final cutoffStr = _dateStr(cutoff);

    final snap = await _firestore
        .collection('app_open_events')
        .where('date', isGreaterThanOrEqualTo: cutoffStr)
        .get();

    final Map<String, int> countsByDate = {};
    for (final doc in snap.docs) {
      final date = doc.data()['date'] as String?;
      if (date == null) continue;
      countsByDate[date] = (countsByDate[date] ?? 0) + 1;
    }

    return List.generate(30, (i) {
      final date = today.subtract(Duration(days: 29 - i));
      return _DataPoint(date, countsByDate[_dateStr(date)] ?? 0);
    });
  }

  /// MAU 履歴：app_open_events の monthKey フィールドで月別集計
  /// 各月の distinct userId をメモリで集計
  Future<List<_DataPoint>> _fetchMauHistory(DateTime now) async {
    // 12ヶ月前の monthKey を計算
    int cutoffMonth = now.month - 11;
    int cutoffYear = now.year;
    while (cutoffMonth <= 0) { cutoffMonth += 12; cutoffYear--; }
    final cutoffKey =
        '$cutoffYear-${cutoffMonth.toString().padLeft(2, '0')}';

    final snap = await _firestore
        .collection('app_open_events')
        .where('monthKey', isGreaterThanOrEqualTo: cutoffKey)
        .get();

    // monthKey → distinct userIds
    final Map<String, Set<String>> usersByMonth = {};
    for (final doc in snap.docs) {
      final monthKey = doc.data()['monthKey'] as String?;
      final userId = doc.data()['userId'] as String?;
      if (monthKey == null || userId == null) continue;
      usersByMonth.putIfAbsent(monthKey, () => {}).add(userId);
    }

    return List.generate(12, (i) {
      int month = now.month - 11 + i;
      int year = now.year;
      while (month <= 0) { month += 12; year--; }
      while (month > 12) { month -= 12; year++; }
      final date = DateTime(year, month);
      final key = '$year-${month.toString().padLeft(2, '0')}';
      return _DataPoint(date, usersByMonth[key]?.length ?? 0);
    });
  }

  String _dateStr(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  /// docs を日付フィールドでグループ化して30日分の配列を返す
  List<_DataPoint> _groupByDay(
    List<QueryDocumentSnapshot> docs,
    String dateField,
    DateTime today,
  ) {
    final Map<DateTime, int> counts = {};
    for (final doc in docs) {
      final data = doc.data() as Map<String, dynamic>;
      final ts = data[dateField] as Timestamp?;
      if (ts == null) continue;
      final d = ts.toDate();
      final day = DateTime(d.year, d.month, d.day);
      counts[day] = (counts[day] ?? 0) + 1;
    }
    return List.generate(30, (i) {
      final date = today.subtract(Duration(days: 29 - i));
      return _DataPoint(date, counts[date] ?? 0);
    });
  }

  // ──────────────────────────────────────────
  // CSV
  // ──────────────────────────────────────────

  String _buildCsv() {
    final buf = StringBuffer();
    buf.writeln('日付,件数');
    for (final p in _points) {
      final dateStr = _isMonthly
          ? '${p.date.year}-${p.date.month.toString().padLeft(2, '0')}'
          : '${p.date.year}-${p.date.month.toString().padLeft(2, '0')}-${p.date.day.toString().padLeft(2, '0')}';
      buf.writeln('$dateStr,${p.count}');
    }
    return buf.toString();
  }

  void _copyAsCsv() {
    Clipboard.setData(ClipboardData(text: _buildCsv()));
    AppToast.show(context, 'CSVをクリップボードにコピーしました');
  }

  // ──────────────────────────────────────────
  // UI
  // ──────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1A1A2E),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.title,
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
            Text(_periodLabel,
                style: const TextStyle(color: Colors.white38, fontSize: 11)),
          ],
        ),
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          if (!_isLoading && _error == null)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: TextButton.icon(
                onPressed: _copyAsCsv,
                icon: const Icon(Icons.copy, color: Colors.white60, size: 16),
                label: const Text('CSVコピー',
                    style: TextStyle(color: Colors.white60, fontSize: 12)),
              ),
            ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CupertinoActivityIndicator(color: Colors.white, radius: 14))
          : _error != null
              ? _buildError()
              : _buildContent(),
    );
  }

  Widget _buildError() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, color: Colors.redAccent, size: 40),
            const SizedBox(height: 12),
            Text(_error!,
                style: const TextStyle(color: Colors.white38, fontSize: 12),
                textAlign: TextAlign.center),
            const SizedBox(height: 20),
            TextButton(
              onPressed: _load,
              child: const Text('再試行', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildContent() {
    final hasData = _points.any((p) => p.count > 0);
    final maxCount = hasData
        ? _points.map((p) => p.count).reduce((a, b) => a > b ? a : b)
        : 1;

    return CustomScrollView(
      physics: const BouncingScrollPhysics(
        parent: AlwaysScrollableScrollPhysics(),
      ),
      slivers: [
        CupertinoSliverRefreshControl(onRefresh: _load),
        SliverToBoxAdapter(
          child: ListView(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
        children: [
          // ── 折れ線グラフ ──
          Container(
            height: 230,
            padding: const EdgeInsets.fromLTRB(4, 16, 16, 8),
            decoration: BoxDecoration(
              color: const Color(0xFF1E1E2E),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.white10),
            ),
            child: hasData
                ? _buildChart(maxCount.toDouble())
                : const Center(
                    child: Text('データがありません',
                        style: TextStyle(color: Colors.white38, fontSize: 13)),
                  ),
          ),

          const SizedBox(height: 28),

          // ── テーブルヘッダー ──
          Row(
            children: [
              const Text('データ一覧',
                  style: TextStyle(
                      color: Colors.white70,
                      fontSize: 14,
                      fontWeight: FontWeight.w600)),
              const Spacer(),
              GestureDetector(
                onTap: _copyAsCsv,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.white24),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.copy, color: Colors.white54, size: 14),
                      SizedBox(width: 4),
                      Text('CSVコピー',
                          style: TextStyle(color: Colors.white54, fontSize: 12)),
                    ],
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 8),

          // ── データ表（新しい順） ──
          Container(
            decoration: BoxDecoration(
              color: const Color(0xFF1E1E2E),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.white10),
            ),
            child: Column(
              children: [
                _tableRow('日付', '件数', isHeader: true),
                const Divider(color: Colors.white10, height: 1),
                ...List.generate(_points.length, (i) {
                  final p = _points[_points.length - 1 - i]; // 新しい順
                  final dateStr = _isMonthly
                      ? '${p.date.year}年${p.date.month}月'
                      : '${p.date.year}/${p.date.month.toString().padLeft(2, '0')}/${p.date.day.toString().padLeft(2, '0')}';
                  return Column(
                    children: [
                      _tableRow(dateStr, p.count.toString()),
                      if (i < _points.length - 1)
                        const Divider(color: Colors.white10, height: 1),
                    ],
                  );
                }),
              ],
            ),
          ),
        ],
      ),
        ),
      ],
    );
  }

  Widget _buildChart(double maxY) {
    final spots = _points
        .asMap()
        .entries
        .map((e) => FlSpot(e.key.toDouble(), e.value.count.toDouble()))
        .toList();

    final labelStep = _isMonthly ? 2 : 7;
    final yInterval = (maxY / 4).ceilToDouble().clamp(1.0, double.infinity);

    return LineChart(
      LineChartData(
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          horizontalInterval: yInterval,
          getDrawingHorizontalLine: (_) =>
              const FlLine(color: Colors.white10, strokeWidth: 1),
        ),
        titlesData: FlTitlesData(
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 38,
              interval: yInterval,
              getTitlesWidget: (val, _) => Text(
                _fmtAxisVal(val.toInt()),
                style:
                    const TextStyle(color: Colors.white38, fontSize: 10),
              ),
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 26,
              getTitlesWidget: (val, _) {
                final idx = val.toInt();
                if (idx < 0 || idx >= _points.length) return const SizedBox();
                if (idx % labelStep != 0) return const SizedBox();
                final p = _points[idx];
                final label = _isMonthly
                    ? '${p.date.month}月'
                    : '${p.date.month}/${p.date.day}';
                return Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(label,
                      style: const TextStyle(
                          color: Colors.white38, fontSize: 10)),
                );
              },
            ),
          ),
          topTitles:
              const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles:
              const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        ),
        borderData: FlBorderData(show: false),
        minX: 0,
        maxX: (_points.length - 1).toDouble(),
        minY: 0,
        maxY: maxY * 1.25,
        lineBarsData: [
          LineChartBarData(
            spots: spots,
            isCurved: true,
            curveSmoothness: 0.3,
            color: widget.color,
            barWidth: 2.5,
            isStrokeCapRound: true,
            dotData: FlDotData(
              show: true,
              getDotPainter: (_, __, ___, ____) => FlDotCirclePainter(
                radius: 3,
                color: widget.color,
                strokeWidth: 0,
              ),
            ),
            belowBarData: BarAreaData(
              show: true,
              color: widget.color.withValues(alpha: 0.12),
            ),
          ),
        ],
        lineTouchData: LineTouchData(
          touchTooltipData: LineTouchTooltipData(
            getTooltipColor: (_) => const Color(0xFF2A2A3E),
            getTooltipItems: (touchedSpots) => touchedSpots.map((s) {
              final idx = s.x.toInt();
              if (idx < 0 || idx >= _points.length) return null;
              final p = _points[idx];
              final dateStr = _isMonthly
                  ? '${p.date.year}/${p.date.month}'
                  : '${p.date.month}/${p.date.day}';
              return LineTooltipItem(
                '$dateStr\n',
                const TextStyle(color: Colors.white54, fontSize: 11),
                children: [
                  TextSpan(
                    text: s.y.toInt().toString(),
                    style: TextStyle(
                      color: widget.color,
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              );
            }).toList(),
          ),
        ),
      ),
    );
  }

  Widget _tableRow(String dateLabel, String countLabel,
      {bool isHeader = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          Expanded(
            child: Text(
              dateLabel,
              style: isHeader
                  ? const TextStyle(
                      color: Colors.white38,
                      fontSize: 12,
                      fontWeight: FontWeight.w600)
                  : const TextStyle(color: Colors.white70, fontSize: 13),
            ),
          ),
          Text(
            countLabel,
            style: isHeader
                ? const TextStyle(
                    color: Colors.white38,
                    fontSize: 12,
                    fontWeight: FontWeight.w600)
                : TextStyle(
                    color: widget.color,
                    fontSize: 14,
                    fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }

  String _fmtAxisVal(int n) {
    if (n >= 1000) return '${(n / 1000).toStringAsFixed(1)}K';
    return n.toString();
  }
}

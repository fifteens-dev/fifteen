import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../services/music_memory_cycle_service.dart';
import '../../widgets/common/app_toast.dart';

/// 集計メトリクスの時系列種別
enum MetricSeriesType {
  dailyNewUsers,            // DL数（15s Day ごと）
  cumulativeUsers,          // 累計DL数（累積）
  dau,                      // DAU（15s Day ごとのアクティブ）
  mau,                      // MAU（月次アクティブ）
  dailyPosters,             // 投稿者数（15s Day ごとのユニーク投稿者）
  postCompletions,          // 投稿完了数（15s Day ごと）
  cumulativePostCompletions,// 投稿完了数（累積）
}

class _DataPoint {
  final DateTime date;
  final int count;
  _DataPoint(this.date, this.count);
}

/// メトリクス詳細画面（折れ線グラフ + データ表）
///
/// 時間軸は暦日ではなく「15s Day」＝通知が来てから次の通知が来るまで。
/// 境界は `music_memory_cycles` から読むため、履歴が無い期間は点が出ない。
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
  String get _periodLabel =>
      _isMonthly ? '過去12ヶ月' : '直近30 15s Day';

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

  /// 集計に使う「15s Day」窓を古い→新しい順で返す（最大 [limit] 件）。
  Future<List<MusicMemoryDayWindow>> _loadWindows({int limit = 30}) async {
    final days = await MusicMemoryCycleService().loadDays(limit: limit + 5);
    if (days.isEmpty) return const [];
    // loadDays は新しい→古い。古い→新しいに直し、必要な件数だけ残す。
    final asc = days.reversed.toList();
    return asc.length <= limit ? asc : asc.sublist(asc.length - limit);
  }

  /// [t] が属する窓の index。どこにも入らなければ -1。
  int _windowIndexFor(List<MusicMemoryDayWindow> asc, DateTime t) {
    for (var i = asc.length - 1; i >= 0; i--) {
      if (asc[i].contains(t)) return i;
    }
    return -1;
  }

  /// 窓の代表日付（グラフ・CSV のラベル用）。cycleKey の暦日を使う。
  DateTime _windowDate(MusicMemoryDayWindow w) {
    final parts = w.key.split('-');
    if (parts.length != 3) return w.start;
    return DateTime(
        int.parse(parts[0]), int.parse(parts[1]), int.parse(parts[2]));
  }

  Future<List<_DataPoint>> _fetchData() async {
    // ダミーユーザーは指標から除外する。
    // 集計タブと同じく dummy_config/users(+ bulkDummyUsers) を起点にする。
    final dummyUids = await _loadDummyUids();

    // MAU は月別なので、12ヶ月ぶんの窓が要る。
    final windows = await _loadWindows(limit: _isMonthly ? 370 : 30);
    if (windows.isEmpty) return const [];

    switch (widget.seriesType) {
      case MetricSeriesType.dailyNewUsers:
        return _countPerWindow('users', 'createdAt', windows,
            skipDoc: (doc) => dummyUids.contains(doc.id));

      case MetricSeriesType.cumulativeUsers:
        return _cumulativePerWindow('users', 'createdAt', windows,
            skipDoc: (doc) => dummyUids.contains(doc.id));

      case MetricSeriesType.dau:
        return _dauPerWindow(windows, dummyUids);

      case MetricSeriesType.mau:
        return _mauPerMonth(windows, dummyUids);

      case MetricSeriesType.dailyPosters:
        return _distinctPostersPerWindow(windows, dummyUids);

      case MetricSeriesType.postCompletions:
        return _countPerWindow('posts', 'createdAt', windows,
            skipDoc: (doc) =>
                (doc.data() as Map<String, dynamic>)['isDummyPost'] == true);

      case MetricSeriesType.cumulativePostCompletions:
        return _cumulativePerWindow('posts', 'createdAt', windows,
            skipDoc: (doc) =>
                (doc.data() as Map<String, dynamic>)['isDummyPost'] == true);
    }
  }

  /// ダミーユーザーのUID一覧を `dummy_config/users` + `bulkDummyUsers`（あれば）から取得。
  Future<Set<String>> _loadDummyUids() async {
    final ids = <String>{};
    try {
      final snap = await _firestore.doc('dummy_config/users').get();
      final list = (snap.data()?['userIds'] as List?) ?? const [];
      for (final v in list) {
        if (v is String) ids.add(v);
      }
    } catch (_) {}
    try {
      final snap = await _firestore.doc('dummy_config/bulkDummyUsers').get();
      final list = (snap.data()?['userIds'] as List?) ?? const [];
      for (final v in list) {
        if (v is String) ids.add(v);
      }
    } catch (_) {}
    return ids;
  }

  /// コレクションを [dateField] で取得し、15s Day ごとの件数にする。
  Future<List<_DataPoint>> _countPerWindow(
    String collection,
    String dateField,
    List<MusicMemoryDayWindow> windows, {
    bool Function(QueryDocumentSnapshot doc)? skipDoc,
  }) async {
    final snap = await _firestore
        .collection(collection)
        .where(dateField,
            isGreaterThanOrEqualTo: Timestamp.fromDate(windows.first.start))
        .get();

    final counts = List<int>.filled(windows.length, 0);
    for (final doc in snap.docs) {
      if (skipDoc != null && skipDoc(doc)) continue;
      final ts = doc.data()[dateField] as Timestamp?;
      if (ts == null) continue;
      final i = _windowIndexFor(windows, ts.toDate());
      if (i >= 0) counts[i]++;
    }
    return [
      for (var i = 0; i < windows.length; i++)
        _DataPoint(_windowDate(windows[i]), counts[i]),
    ];
  }

  /// 15s Day ごとの累積。窓の開始より前の件数をベースに積み上げる。
  Future<List<_DataPoint>> _cumulativePerWindow(
    String collection,
    String dateField,
    List<MusicMemoryDayWindow> windows, {
    bool Function(QueryDocumentSnapshot doc)? skipDoc,
  }) async {
    final cutoff = Timestamp.fromDate(windows.first.start);
    int base;
    if (skipDoc == null) {
      final baseSnap = await _firestore
          .collection(collection)
          .where(dateField, isLessThan: cutoff)
          .count()
          .get();
      base = baseSnap.count ?? 0;
    } else {
      // ダミー除外あり → 全件取得して skipDoc を弾く
      final baseSnap = await _firestore
          .collection(collection)
          .where(dateField, isLessThan: cutoff)
          .get();
      base = baseSnap.docs.where((d) => !skipDoc(d)).length;
    }

    final daily = await _countPerWindow(collection, dateField, windows,
        skipDoc: skipDoc);
    var running = base;
    return daily.map((p) {
      running += p.count;
      return _DataPoint(p.date, running);
    }).toList();
  }

  /// DAU 履歴：15s Day ごとのユニーク起動ユーザー数。
  ///
  /// `app_open_events` は 1 ユーザー 1 サイクル 1 件だが、旧スキーマ（暦日キー）の
  /// ドキュメントとも混在するため、日付キーではなく createdAt が
  /// どの窓に入るかで判定する（どちらの世代でも正しく数えられる）。
  Future<List<_DataPoint>> _dauPerWindow(
      List<MusicMemoryDayWindow> windows, Set<String> dummyUids) async {
    final snap = await _firestore
        .collection('app_open_events')
        .where('createdAt',
            isGreaterThanOrEqualTo: Timestamp.fromDate(windows.first.start))
        .get();

    final users = List.generate(windows.length, (_) => <String>{});
    for (final doc in snap.docs) {
      final data = doc.data();
      final ts = data['createdAt'] as Timestamp?;
      final uid = data['userId'] as String?;
      if (ts == null || uid == null || dummyUids.contains(uid)) continue;
      final i = _windowIndexFor(windows, ts.toDate());
      if (i >= 0) users[i].add(uid);
    }
    return [
      for (var i = 0; i < windows.length; i++)
        _DataPoint(_windowDate(windows[i]), users[i].length),
    ];
  }

  /// MAU 履歴：15s Day を月ごとにまとめ、月別のユニーク起動ユーザー数を返す。
  /// 月の切れ目も 15s Day で判断する（8/31 19:00 開始のサイクルは 8 月扱い）。
  Future<List<_DataPoint>> _mauPerMonth(
      List<MusicMemoryDayWindow> windows, Set<String> dummyUids) async {
    final snap = await _firestore
        .collection('app_open_events')
        .where('createdAt',
            isGreaterThanOrEqualTo: Timestamp.fromDate(windows.first.start))
        .get();

    final byMonth = <String, Set<String>>{};
    for (final doc in snap.docs) {
      final data = doc.data();
      final ts = data['createdAt'] as Timestamp?;
      final uid = data['userId'] as String?;
      if (ts == null || uid == null || dummyUids.contains(uid)) continue;
      final i = _windowIndexFor(windows, ts.toDate());
      if (i < 0) continue;
      final monthKey = windows[i].key.substring(0, 7);
      (byMonth[monthKey] ??= <String>{}).add(uid);
    }

    // 窓が存在する月だけを古い→新しい順に並べる。
    final months = <String>[];
    for (final w in windows) {
      final k = w.key.substring(0, 7);
      if (months.isEmpty || months.last != k) months.add(k);
    }
    return [
      for (final m in months)
        _DataPoint(
          DateTime(int.parse(m.split('-')[0]), int.parse(m.split('-')[1])),
          byMonth[m]?.length ?? 0,
        ),
    ];
  }

  /// posts から 15s Day ごとのユニーク投稿者数。
  /// ダミーユーザーの userId は集計対象から外す。
  Future<List<_DataPoint>> _distinctPostersPerWindow(
      List<MusicMemoryDayWindow> windows, Set<String> dummyUids) async {
    final snap = await _firestore
        .collection('posts')
        .where('createdAt',
            isGreaterThanOrEqualTo: Timestamp.fromDate(windows.first.start))
        .get();

    final users = List.generate(windows.length, (_) => <String>{});
    for (final doc in snap.docs) {
      final data = doc.data();
      final ts = data['createdAt'] as Timestamp?;
      final userId = data['userId'] as String?;
      if (ts == null || userId == null) continue;
      if (dummyUids.contains(userId)) continue;
      // isDummyPost 直接マーキングされている投稿も除外（保険）
      if (data['isDummyPost'] == true) continue;
      final i = _windowIndexFor(windows, ts.toDate());
      if (i >= 0) users[i].add(userId);
    }
    return [
      for (var i = 0; i < windows.length; i++)
        _DataPoint(_windowDate(windows[i]), users[i].length),
    ];
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

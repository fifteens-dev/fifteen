import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import '../../services/music_memory_cycle_service.dart';
import '../../widgets/common/app_toast.dart';
import 'analytics_detail_screen.dart';

/// 集計データタブ（管理者パネル内）
///
/// # 時間軸: 「15s Day」
/// すべての日次指標は暦日（0:00 区切り）ではなく **通知が来てから次の通知が
/// 来るまで**を 1 日と数える。例: 9/2 の 15s Day = 9/2 の通知(19:00) 〜 9/3 の通知。
/// 境界は `music_memory_cycles`（各日の発火時刻）から読む。
class AnalyticsTab extends StatefulWidget {
  const AnalyticsTab({super.key});

  @override
  State<AnalyticsTab> createState() => _AnalyticsTabState();
}

class _AnalyticsTabState extends State<AnalyticsTab> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  final MusicMemoryCycleService _cycle = MusicMemoryCycleService();

  bool _isLoading = false;
  bool _backfilling = false;
  bool _serviceBackfilling = false;
  _AnalyticsData? _data;

  Future<int?> _countQuery(Query query) async {
    try {
      final snap = await query.count().get();
      return snap.count ?? 0;
    } catch (_) {
      return null;
    }
  }

  /// ダミーユーザーのUID一覧を `dummy_config/users` + `bulkDummyUsers`（あれば）から取得。
  /// 集計から除外するために使う。
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

  /// 引き算後に 0 未満にしない（null の場合は null をそのまま返す）
  int? _sub(int? a, int b) => a == null ? null : (a - b).clamp(0, a);

  /// 「15s Day」の集計窓（未取得なら現サイクルのみのフォールバック）。
  Future<List<MusicMemoryDayWindow>> _loadDays() async {
    final days = await _cycle.loadDays(limit: 40);
    if (days.isNotEmpty) return days;
    // 履歴コレクションがまだ空（バックフィル未実行）のときは現サイクルだけ作る。
    final notifiedAt = await _cycle.fetchNotifiedAt();
    if (notifiedAt == null) return const [];
    String two(int v) => v.toString().padLeft(2, '0');
    return [
      MusicMemoryDayWindow(
        key: '${notifiedAt.year}-${two(notifiedAt.month)}-${two(notifiedAt.day)}',
        start: notifiedAt,
      ),
    ];
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);

    // 先にダミーUID・15s Day の境界を取得（集計から差し引く / 窓に使う）
    final dummyUids = await _loadDummyUids();
    final days = await _loadDays();

    if (days.isEmpty) {
      // 通知が一度も発火していない。日次指標は出せないので累計だけ出す。
      final totals = await Future.wait([
        _countQuery(_firestore.collection('users')),
        _countQuery(_firestore.collection('users').where('postsCount', isGreaterThan: 0)),
        _countQuery(_firestore.collection('posts')),
        _countQuery(_firestore.collection('posts').where('isDummyPost', isEqualTo: true)),
        _countDummyPosters(dummyUids),
      ]);
      final services = await _loadServiceBreakdown(dummyUids);
      final switches = await _loadServiceSwitches(dummyUids);
      final trackSources = await _loadTrackSourceStats(dummyUids);
      if (mounted) {
        setState(() {
          _data = _AnalyticsData(
            totalUsers: _sub(totals[0], dummyUids.length),
            totalPosters: _sub(totals[1], totals[4] ?? 0),
            totalPostCompletions: _sub(totals[2], totals[3] ?? 0),
            days: const [],
            services: services,
            switches: switches,
            trackSources: trackSources,
          );
          _isLoading = false;
        });
      }
      return;
    }

    final current = days.first;
    final monthStart = _monthStartFor(days, current);

    final baseFuture = Future.wait([
      // 0: 累計DL数
      _countQuery(_firestore.collection('users')),
      // 1: 新規登録数（現 15s Day）
      _countInWindow('users', 'createdAt', current),
      // 2: 投稿者数（累計）
      _countQuery(_firestore
          .collection('users')
          .where('postsCount', isGreaterThan: 0)),
      // 3: 投稿完了数（累計）
      _countQuery(_firestore.collection('posts')),
      // 4: ダミー投稿総数（累計）
      _countQuery(_firestore
          .collection('posts')
          .where('isDummyPost', isEqualTo: true)),
      // 5: 現 15s Day に登録されたダミーユーザー（通常0だが念のため）
      _countDummyUsersCreatedSince(
          dummyUids, Timestamp.fromDate(current.start)),
      // 6: postsCount > 0 のダミーユーザー数
      _countDummyPosters(dummyUids),
    ]);
    final dauFuture = _openersIn(current, dummyUids);
    final mauFuture = _distinctOpenersSince(monthStart, dummyUids);
    final cycleFuture = _loadCycleStats(current, dummyUids);
    final retentionFuture = _loadRetention(days, dummyUids);
    final servicesFuture = _loadServiceBreakdown(dummyUids);
    final switchesFuture = _loadServiceSwitches(dummyUids);
    final sourcesFuture = _loadTrackSourceStats(dummyUids);

    final results = await baseFuture;
    final dau = await dauFuture;
    final mau = await mauFuture;
    final cycle = await cycleFuture;
    final retention = await retentionFuture;
    final services = await servicesFuture;
    final switches = await switchesFuture;
    final trackSources = await sourcesFuture;

    if (mounted) {
      setState(() {
        // 全指標からダミー分を差し引く。
        // DAU/MAU は app_open_events ベースで、集計側で uid を除外済み。
        _data = _AnalyticsData(
          totalUsers: _sub(results[0], dummyUids.length),
          newUsersInDay: _sub(results[1], results[5] ?? 0),
          dau: dau.length,
          mau: mau,
          totalPosters: _sub(results[2], results[6] ?? 0),
          totalPostCompletions: _sub(results[3], results[4] ?? 0),
          days: days,
          dayPosters: cycle.posters,
          dayPostCompletions: cycle.completions,
          retention: retention,
          services: services,
          switches: switches,
          trackSources: trackSources,
        );
        _isLoading = false;
      });
    }
  }

  /// [current] と同じ月に属する 15s Day のうち最古のものの開始時刻。
  /// 月の切れ目も「15s Day」で判断する（8/31 19:00 開始のサイクルは 8 月扱い）。
  DateTime _monthStartFor(
      List<MusicMemoryDayWindow> days, MusicMemoryDayWindow current) {
    final monthKey = current.key.substring(0, 7);
    var start = current.start;
    for (final d in days) {
      if (d.key.startsWith(monthKey)) start = d.start;
    }
    return start;
  }

  /// コレクションの [field] が窓内にあるドキュメント数。
  Future<int?> _countInWindow(
      String collection, String field, MusicMemoryDayWindow window) async {
    try {
      Query q = _firestore.collection(collection).where(field,
          isGreaterThanOrEqualTo: Timestamp.fromDate(window.start));
      final end = window.end;
      if (end != null) {
        q = q.where(field, isLessThan: Timestamp.fromDate(end));
      }
      return _countQuery(q);
    } catch (_) {
      return null;
    }
  }

  /// 指定の 15s Day にアプリを開いたユーザー（ダミー除外）。
  ///
  /// `app_open_events` は 1 ユーザー 1 サイクル 1 件だが、旧スキーマの
  /// 暦日ベースのドキュメントとも混在するため、日付キーではなく
  /// **createdAt が窓内に入るか**で判定する（どちらの世代でも正しく数えられる）。
  Future<Set<String>> _openersIn(
      MusicMemoryDayWindow window, Set<String> dummyUids) async {
    try {
      Query<Map<String, dynamic>> q = _firestore
          .collection('app_open_events')
          .where('createdAt',
              isGreaterThanOrEqualTo: Timestamp.fromDate(window.start));
      final end = window.end;
      if (end != null) {
        q = q.where('createdAt', isLessThan: Timestamp.fromDate(end));
      }
      final snap = await q.get();
      return snap.docs
          .map((d) => d.data()['userId'] as String?)
          .whereType<String>()
          .where((uid) => !dummyUids.contains(uid))
          .toSet();
    } catch (_) {
      return const {};
    }
  }

  /// [since] 以降にアプリを開いたユニークユーザー数（MAU 用）。
  Future<int?> _distinctOpenersSince(
      DateTime since, Set<String> dummyUids) async {
    try {
      final snap = await _firestore
          .collection('app_open_events')
          .where('createdAt', isGreaterThanOrEqualTo: Timestamp.fromDate(since))
          .get();
      return snap.docs
          .map((d) => d.data()['userId'] as String?)
          .whereType<String>()
          .where((uid) => !dummyUids.contains(uid))
          .toSet()
          .length;
    } catch (_) {
      return null;
    }
  }

  /// 現 15s Day（通知 〜 次の通知）の投稿者数・投稿完了数。
  /// 1 サイクル分の posts を 1 クエリで取り、ダミーをメモリで除外する。
  Future<_CycleStats> _loadCycleStats(
      MusicMemoryDayWindow window, Set<String> dummyUids) async {
    try {
      Query<Map<String, dynamic>> q = _firestore.collection('posts').where(
          'createdAt',
          isGreaterThanOrEqualTo: Timestamp.fromDate(window.start));
      final end = window.end;
      if (end != null) {
        q = q.where('createdAt', isLessThan: Timestamp.fromDate(end));
      }
      final snap = await q.get();
      final posters = <String>{};
      var completions = 0;
      for (final d in snap.docs) {
        final data = d.data();
        if (data['isDummyPost'] == true) continue;
        final uid = data['userId'] as String?;
        if (uid == null || dummyUids.contains(uid)) continue;
        completions++;
        posters.add(uid);
      }
      return _CycleStats(posters: posters.length, completions: completions);
    } catch (_) {
      return const _CycleStats();
    }
  }

  /// D1 / D7 継続率。母集団も「15s Day」単位。
  ///
  /// D1 = 1つ前の 15s Day に開いた人のうち、今の 15s Day にも開いた人の割合。
  /// D7 = 7つ前の 15s Day に開いた人のうち、今の 15s Day にも開いた人の割合。
  Future<_Retention> _loadRetention(
      List<MusicMemoryDayWindow> days, Set<String> dummyUids) async {
    try {
      final current = days.first;
      final d1Day = days.length > 1 ? days[1] : null;
      final d7Day = days.length > 7 ? days[7] : null;
      if (d1Day == null && d7Day == null) return const _Retention();

      final today = await _openersIn(current, dummyUids);
      final d1Cohort =
          d1Day == null ? null : await _openersIn(d1Day, dummyUids);
      final d7Cohort =
          d7Day == null ? null : await _openersIn(d7Day, dummyUids);

      return _Retention(
        d1Label: d1Day?.label,
        d1Cohort: d1Cohort?.length,
        d1Retained: d1Cohort?.intersection(today).length,
        d7Label: d7Day?.label,
        d7Cohort: d7Cohort?.length,
        d7Retained: d7Cohort?.intersection(today).length,
      );
    } catch (_) {
      return const _Retention();
    }
  }

  /// 過去の 15s Day 境界を `notifications` から復元する（管理者のみ・冪等）。
  Future<void> _runBackfill() async {
    setState(() => _backfilling = true);
    try {
      final res = await FirebaseFunctions.instance
          .httpsCallable('backfillMusicMemoryCycles')
          .call({'days': 90});
      final d = (res.data as Map?)?.cast<String, dynamic>() ?? {};
      if (mounted) {
        AppToast.show(context,
            '境界を復元: 新規${d['created'] ?? 0} / 既存${d['skipped'] ?? 0} / 不明${d['missing'] ?? 0}');
      }
      await _load();
    } catch (e) {
      if (mounted) AppToast.show(context, '復元に失敗しました: $e');
    } finally {
      if (mounted) setState(() => _backfilling = false);
    }
  }

  /// 音楽サービス別のユーザー数・投稿数（累計）。
  ///
  /// 分類は **`musicService`（アプリが刻む連携スタンプ）だけ**を根拠にする。
  /// 投稿の楽曲メタデータからは連携先を判定できないため（未連携ユーザーの検索は
  /// Spotify に、おすすめは全員 Apple Music チャートにフォールバックする）、
  /// 推定値は分類には使わず [_loadTrackSourceStats] の参考値として別に出す。
  Future<List<_ServiceStat>> _loadServiceBreakdown(
      Set<String> dummyUids) async {
    try {
      final snap = await _firestore.collection('users').get();

      final uids = <String, List<String>>{
        'appleMusic': [],
        'spotify': [],
        'none': [],
        'unstamped': [],
      };

      for (final d in snap.docs) {
        if (dummyUids.contains(d.id)) continue;
        final v = d.data()['musicService'];
        final bucket =
            (v == 'spotify' || v == 'appleMusic' || v == 'none') ? v as String : 'unstamped';
        uids[bucket]!.add(d.id);
      }

      const defs = [
        ('appleMusic', 'Apple Music', Color(0xFFFC3C44)),
        ('spotify', 'Spotify', Color(0xFF1DB954)),
        ('none', '未連携', Color(0xFF8E8E93)),
        ('unstamped', '未取得', Color(0xFF5A5A5F)),
      ];

      // 4 バケット分の投稿数カウントは並列に流す。
      final counts = await Future.wait(
        defs.map((def) => _countPostsByUsers(uids[def.$1]!)),
      );
      return [
        for (var i = 0; i < defs.length; i++)
          _ServiceStat(
            key: defs[i].$1,
            label: defs[i].$2,
            color: defs[i].$3,
            users: uids[defs[i].$1]!.length,
            posts: counts[i],
          ),
      ];
    } catch (_) {
      return const [];
    }
  }

  /// サービスを乗り換えたユーザー一覧（`musicServicePrevious` が入っている人）。
  Future<List<_ServiceSwitch>> _loadServiceSwitches(
      Set<String> dummyUids) async {
    try {
      // orderBy はそのフィールドを持たないドキュメントを自動的に除外するため、
      // 「乗り換えたことがある人」だけが対象になる（不等式フィルタは不要。
      // 不等式＋別フィールドの並び替えは Firestore が許可しない）。
      final snap = await _firestore
          .collection('users')
          .orderBy('musicServiceChangedAt', descending: true)
          .limit(100)
          .get();
      return [
        for (final d in snap.docs)
          if (!dummyUids.contains(d.id) &&
              (d.data()['musicServicePrevious'] as String?)?.isNotEmpty == true)
            _ServiceSwitch(
              uid: d.id,
              displayName: (d.data()['name'] as String?)?.isNotEmpty == true
                  ? d.data()['name'] as String
                  : (d.data()['username'] as String?) ?? d.id,
              username: d.data()['username'] as String?,
              from: d.data()['musicServicePrevious'] as String? ?? '',
              to: d.data()['musicService'] as String? ?? '',
              changedAt:
                  (d.data()['musicServiceChangedAt'] as Timestamp?)?.toDate(),
              switchCount:
                  (d.data()['musicServiceSwitchCount'] as num?)?.toInt() ?? 1,
            ),
      ];
    } catch (_) {
      // 複合インデックス未作成などでは一覧を諦める（他の集計は止めない）。
      return const [];
    }
  }

  /// 参考値: 投稿の楽曲メタデータの取得元（Apple の mzstatic / Spotify の scdn）。
  /// **連携先とは一致しない**ので、あくまで参考として別枠で見せる。
  Future<Map<String, int>> _loadTrackSourceStats(Set<String> dummyUids) async {
    try {
      final snap = await _firestore.collection('users').get();
      final out = <String, int>{'appleMusic': 0, 'spotify': 0};
      for (final d in snap.docs) {
        if (dummyUids.contains(d.id)) continue;
        final v = d.data()['musicServiceInferred'];
        if (v == 'appleMusic' || v == 'spotify') {
          out[v as String] = (out[v] ?? 0) + 1;
        }
      }
      return out;
    } catch (_) {
      return const {};
    }
  }

  /// 参考値（楽曲取得元）を投稿から再計算する（管理者 callable）。
  Future<void> _runServiceBackfill() async {
    setState(() => _serviceBackfilling = true);
    try {
      final res = await FirebaseFunctions.instance
          .httpsCallable('backfillMusicServiceFromPosts')
          .call();
      final d = (res.data as Map?)?.cast<String, dynamic>() ?? {};
      if (mounted) {
        AppToast.show(context, '${d['users'] ?? 0} 人の楽曲取得元を再計算しました');
      }
      await _load();
    } catch (e) {
      if (mounted) AppToast.show(context, '再計算に失敗しました: $e');
    } finally {
      if (mounted) setState(() => _serviceBackfilling = false);
    }
  }

  /// 指定ユーザー群の投稿数（累計）。whereIn は 30 件上限なので分割して count する。
  Future<int?> _countPostsByUsers(List<String> uids) async {
    if (uids.isEmpty) return 0;
    try {
      final chunks = <List<String>>[
        for (var i = 0; i < uids.length; i += 30) uids.skip(i).take(30).toList(),
      ];
      final counts = await Future.wait(chunks.map((chunk) => _firestore
          .collection('posts')
          .where('userId', whereIn: chunk)
          .count()
          .get()));
      return counts.fold<int>(0, (a, s) => a + (s.count ?? 0));
    } catch (_) {
      return null;
    }
  }

  /// 指定 timestamp 以降に作成されたダミーユーザー数。
  Future<int?> _countDummyUsersCreatedSince(
      Set<String> dummyUids, Timestamp since) async {
    if (dummyUids.isEmpty) return 0;
    try {
      var matched = 0;
      // Firestore whereIn は 30 件上限
      for (var i = 0; i < dummyUids.length; i += 30) {
        final batch = dummyUids.skip(i).take(30).toList();
        final snap = await _firestore
            .collection('users')
            .where(FieldPath.documentId, whereIn: batch)
            .where('createdAt', isGreaterThanOrEqualTo: since)
            .count()
            .get();
        matched += snap.count ?? 0;
      }
      return matched;
    } catch (_) {
      return null;
    }
  }

  /// postsCount > 0 のダミーユーザー数。
  Future<int?> _countDummyPosters(Set<String> dummyUids) async {
    if (dummyUids.isEmpty) return 0;
    try {
      var matched = 0;
      for (final uid in dummyUids) {
        final doc = await _firestore.collection('users').doc(uid).get();
        final pc = (doc.data()?['postsCount'] as num?)?.toInt() ?? 0;
        if (pc > 0) matched++;
      }
      return matched;
    } catch (_) {
      return null;
    }
  }

  @override
  void initState() {
    super.initState();
    _load();
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

    if (d.days.isEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildNoticeCard(
            '通知がまだ一度も発火していないため、日次指標（15s Day）を出せません。'
            '累計のみ表示しています。',
            warning: true,
          ),
          const SizedBox(height: 20),
          _buildSectionTitle('累計', Icons.functions_outlined),
          const SizedBox(height: 12),
          _buildGrid([
            _MetricCard(
              label: '累計DL数',
              value: _fmt(d.totalUsers),
              subtitle: '全期間・登録者数',
              icon: Icons.download_outlined,
              color: const Color(0xFF5D8FFF),
            ),
            _MetricCard(
              label: '投稿完了数',
              value: _fmt(d.totalPostCompletions),
              subtitle: '累計',
              icon: Icons.check_circle_outline,
              color: const Color(0xFFFF8C42),
            ),
          ]),
          const SizedBox(height: 28),
          _buildSectionTitle('音楽サービス別', Icons.library_music_outlined),
          const SizedBox(height: 12),
          _buildServiceBreakdown(d),
        ],
      );
    }

    final current = d.days.first;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildDayHeader(current, d.days.length),
        const SizedBox(height: 20),

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
            label: 'DL数',
            value: _fmt(d.newUsersInDay),
            subtitle: '${current.label} の新規登録',
            icon: Icons.person_add_outlined,
            color: const Color(0xFF4CAF82),
            onTap: () => _openDetail(context, 'DL数（15s Day）', const Color(0xFF4CAF82), MetricSeriesType.dailyNewUsers),
          ),
          _MetricCard(
            label: 'DAU',
            value: _fmt(d.dau),
            subtitle: '${current.label} のアクティブ',
            icon: Icons.today_outlined,
            color: const Color(0xFFFF8C42),
            onTap: () => _openDetail(context, 'DAU（15s Day）', const Color(0xFFFF8C42), MetricSeriesType.dau),
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
            value: _fmt(d.dayPosters),
            subtitle: '${current.label} のユニーク',
            icon: Icons.group_outlined,
            color: const Color(0xFF5D8FFF),
            onTap: () => _openDetail(context, '投稿者数（15s Day）', const Color(0xFF5D8FFF), MetricSeriesType.dailyPosters),
          ),
          _MetricCard(
            label: '投稿完了数',
            value: _fmt(d.dayPostCompletions),
            subtitle: current.label,
            icon: Icons.task_alt_outlined,
            color: const Color(0xFFAB6FEB),
            onTap: () => _openDetail(context, '投稿完了数（15s Day）', const Color(0xFFAB6FEB), MetricSeriesType.postCompletions),
          ),
          _MetricCard(
            label: '投稿者数',
            value: _fmt(d.totalPosters),
            subtitle: '累計',
            icon: Icons.groups_outlined,
            color: const Color(0xFF4CAF82),
            onTap: () => _openDetail(context, '投稿者数（15s Day）', const Color(0xFF4CAF82), MetricSeriesType.dailyPosters),
          ),
          _MetricCard(
            label: '投稿完了数',
            value: _fmt(d.totalPostCompletions),
            subtitle: '累計',
            icon: Icons.check_circle_outline,
            color: const Color(0xFFFF8C42),
            onTap: () => _openDetail(context, '投稿完了数（累計）', const Color(0xFFFF8C42), MetricSeriesType.cumulativePostCompletions),
          ),
        ]),

        const SizedBox(height: 28),

        _buildSectionTitle('継続率', Icons.repeat_outlined),
        const SizedBox(height: 6),
        const Row(
          children: [
            Icon(Icons.info_outline, size: 13, color: Colors.white38),
            SizedBox(width: 5),
            Expanded(
              child: Text(
                'D1＝1つ前の 15s Day に開いた人のうち、今の 15s Day にも開いた割合。'
                'D7 は 7つ前が母集団。今の 15s Day は途中なので低めに出ます。',
                style: TextStyle(color: Colors.white38, fontSize: 11, height: 1.4),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        _buildGrid([
          _MetricCard(
            label: 'D1',
            value: _pct(d.retention.d1Retained, d.retention.d1Cohort),
            subtitle: d.retention.d1Cohort == null
                ? '1つ前の 15s Day が未取得'
                : '${d.retention.d1Label} の${d.retention.d1Cohort}人中 ${d.retention.d1Retained}人',
            icon: Icons.looks_one_outlined,
            color: const Color(0xFF4CAF82),
          ),
          _MetricCard(
            label: 'D7',
            value: _pct(d.retention.d7Retained, d.retention.d7Cohort),
            subtitle: d.retention.d7Cohort == null
                ? '7つ前の 15s Day が未取得'
                : '${d.retention.d7Label} の${d.retention.d7Cohort}人中 ${d.retention.d7Retained}人',
            icon: Icons.looks_two_outlined,
            color: const Color(0xFFAB6FEB),
          ),
        ]),

        const SizedBox(height: 28),

        _buildSectionTitle('音楽サービス別', Icons.library_music_outlined),
        const SizedBox(height: 12),
        _buildServiceBreakdown(d),
      ],
    );
  }

  /// 現在の 15s Day の窓と、境界履歴の充足状況を示すヘッダ。
  Widget _buildDayHeader(MusicMemoryDayWindow current, int historyCount) {
    String hm(DateTime t) => '${t.month}/${t.day} '
        '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          decoration: BoxDecoration(
            color: const Color(0xFF1E1E2E),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFF5D8FFF).withValues(alpha: 0.3)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.schedule, size: 14, color: Color(0xFF5D8FFF)),
                  const SizedBox(width: 6),
                  Text(
                    '15s Day  ${current.label}',
                    style: const TextStyle(
                      color: Color(0xFF5D8FFF),
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                '${hm(current.start)} の通知 〜 次の通知まで',
                style: const TextStyle(color: Colors.white, fontSize: 14),
              ),
              const SizedBox(height: 4),
              const Text(
                '日次の指標はすべてこの区切り（0:00 リセットではない）。',
                style: TextStyle(color: Colors.white38, fontSize: 10, height: 1.5),
              ),
            ],
          ),
        ),
        // D7 には 8 サイクル分の境界が要る。足りなければ復元を促す。
        if (historyCount < 8) ...[
          const SizedBox(height: 10),
          _buildNoticeCard(
            '15s Day の境界履歴が $historyCount 件しかありません。'
            'D1 / D7 と過去のグラフには過去の通知時刻が必要です。',
            warning: true,
            action: TextButton.icon(
              onPressed: _backfilling ? null : _runBackfill,
              icon: const Icon(Icons.history, size: 16),
              label: Text(_backfilling ? '復元中...' : '過去の境界を復元'),
              style: TextButton.styleFrom(foregroundColor: const Color(0xFFFFB74D)),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildNoticeCard(String text, {bool warning = false, Widget? action}) {
    final color = warning ? const Color(0xFFFFB74D) : Colors.white38;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E2E),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(warning ? Icons.warning_amber_outlined : Icons.info_outline,
                  size: 15, color: color),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  text,
                  style: TextStyle(color: color, fontSize: 11, height: 1.5),
                ),
              ),
            ],
          ),
          if (action != null)
            Align(alignment: Alignment.centerRight, child: action)
          else
            const SizedBox(height: 4),
        ],
      ),
    );
  }

  Widget _buildServiceBreakdown(_AnalyticsData d) {
    final services = d.services;
    if (services.isEmpty) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: const Color(0xFF1E1E2E),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white12),
        ),
        child: const Text('取得できませんでした',
            style: TextStyle(color: Colors.white38, fontSize: 12)),
      );
    }

    final totalUsers = services.fold<int>(0, (a, s) => a + s.users);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          decoration: BoxDecoration(
            color: const Color(0xFF1E1E2E),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.white12),
          ),
          child: Column(
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 12, 16, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Text('連携スタンプ',
                          style: TextStyle(color: Colors.white38, fontSize: 11)),
                    ),
                    SizedBox(
                      width: 92,
                      child: Text('ユーザー数',
                          textAlign: TextAlign.right,
                          style: TextStyle(color: Colors.white38, fontSize: 11)),
                    ),
                    SizedBox(
                      width: 64,
                      child: Text('投稿数',
                          textAlign: TextAlign.right,
                          style: TextStyle(color: Colors.white38, fontSize: 11)),
                    ),
                  ],
                ),
              ),
              for (final s in services) ...[
                const Divider(height: 1, color: Colors.white12),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 11, 16, 11),
                  child: Row(
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration:
                            BoxDecoration(color: s.color, shape: BoxShape.circle),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(s.label,
                            style: const TextStyle(
                                color: Colors.white, fontSize: 13)),
                      ),
                      SizedBox(
                        width: 92,
                        child: Text(
                          totalUsers > 0
                              ? '${s.users}  (${(s.users / totalUsers * 100).toStringAsFixed(0)}%)'
                              : '${s.users}',
                          textAlign: TextAlign.right,
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 13,
                              fontWeight: FontWeight.w600),
                        ),
                      ),
                      SizedBox(
                        width: 64,
                        child: Text(
                          _fmt(s.posts),
                          textAlign: TextAlign.right,
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 13,
                              fontWeight: FontWeight.w600),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 8),
        const Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.info_outline, size: 13, color: Colors.white38),
            SizedBox(width: 5),
            Expanded(
              child: Text(
                'アプリが記録した連携状態のみを根拠にしています。「未取得」は'
                'スタンプ対応前のバージョンのままのユーザーで、アップデート後に'
                '一度アプリを開けば分類されます。',
                style: TextStyle(color: Colors.white38, fontSize: 10, height: 1.5),
              ),
            ),
          ],
        ),

        // ── 乗り換え ──
        const SizedBox(height: 20),
        _buildSectionTitle('サービス乗り換え', Icons.swap_horiz),
        const SizedBox(height: 10),
        _buildSwitchList(d.switches),

        // ── 参考値 ──
        const SizedBox(height: 20),
        _buildTrackSourceReference(d.trackSources),
      ],
    );
  }

  Widget _buildSwitchList(List<_ServiceSwitch> switches) {
    if (switches.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: const Color(0xFF1E1E2E),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white12),
        ),
        child: const Text(
          '乗り換えたユーザーはまだいません。'
          '（スタンプが2回以上更新されて初めて記録されます）',
          style: TextStyle(color: Colors.white38, fontSize: 11, height: 1.5),
        ),
      );
    }

    String fmtDate(DateTime? d) {
      if (d == null) return '-';
      return '${d.month}/${d.day} '
          '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
    }

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E2E),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Text('${switches.length} 人（新しい順）',
                style: const TextStyle(color: Colors.white38, fontSize: 11)),
          ),
          for (final sw in switches) ...[
            const Divider(height: 1, color: Colors.white12),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          sw.username?.isNotEmpty == true
                              ? '${sw.displayName}  @${sw.username}'
                              : sw.displayName,
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 13,
                              fontWeight: FontWeight.w600),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (sw.switchCount > 1)
                        Text('${sw.switchCount}回',
                            style: const TextStyle(
                                color: Colors.white38, fontSize: 11)),
                    ],
                  ),
                  const SizedBox(height: 3),
                  Row(
                    children: [
                      Text(serviceLabel(sw.from),
                          style: const TextStyle(
                              color: Colors.white38, fontSize: 11)),
                      const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 6),
                        child: Icon(Icons.arrow_forward,
                            size: 11, color: Colors.white24),
                      ),
                      Text(
                        '今は ${serviceLabel(sw.to)}',
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.w600),
                      ),
                      const Spacer(),
                      Text(fmtDate(sw.changedAt),
                          style: const TextStyle(
                              color: Colors.white24, fontSize: 10)),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// 参考値: 投稿の楽曲メタデータの取得元。連携先とは一致しないので別枠にする。
  Widget _buildTrackSourceReference(Map<String, int> sources) {
    final apple = sources['appleMusic'] ?? 0;
    final spotify = sources['spotify'] ?? 0;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 6),
      decoration: BoxDecoration(
        color: const Color(0xFF191922),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('参考: 投稿の楽曲取得元',
              style: TextStyle(
                  color: Colors.white54,
                  fontSize: 11,
                  fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          Text('Apple Music 由来 $apple 人 / Spotify 由来 $spotify 人',
              style: const TextStyle(color: Colors.white, fontSize: 13)),
          const SizedBox(height: 6),
          const Text(
            '投稿のアートワーク配信元から判別したもので、連携先とは一致しません。'
            '未連携ユーザーの検索結果は Spotify から、おすすめは全員 Apple Music の'
            'チャートから取得されるためです。傾向を見る参考値として扱ってください。',
            style: TextStyle(color: Colors.white30, fontSize: 10, height: 1.5),
          ),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: _serviceBackfilling ? null : _runServiceBackfill,
              icon: const Icon(Icons.autorenew, size: 15),
              label: Text(_serviceBackfilling ? '再計算中...' : '再計算'),
              style: TextButton.styleFrom(foregroundColor: Colors.white38),
            ),
          ),
        ],
      ),
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

  String _fmt(int? n) {
    if (n == null) return '–';
    if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(1)}M';
    if (n >= 1000) return '${(n / 1000).toStringAsFixed(1)}K';
    return n.toString();
  }

  /// 継続率の表示。母数 0 / 未取得は '–'。
  String _pct(int? retained, int? cohort) {
    if (retained == null || cohort == null || cohort == 0) return '–';
    return '${(retained / cohort * 100).toStringAsFixed(1)}%';
  }
}

/// 現サイクル（通知 〜 現在）の投稿集計。
class _CycleStats {
  final int? posters;
  final int? completions;
  const _CycleStats({this.posters, this.completions});
}

/// D1 / D7 継続率の内訳。母集団は「15s Day」単位。
class _Retention {
  /// 母集団になった 15s Day のラベル（"9/1"）。
  final String? d1Label;
  final int? d1Cohort;
  final int? d1Retained;
  final String? d7Label;
  final int? d7Cohort;
  final int? d7Retained;

  const _Retention({
    this.d1Label,
    this.d1Cohort,
    this.d1Retained,
    this.d7Label,
    this.d7Cohort,
    this.d7Retained,
  });
}

/// 音楽サービス別のユーザー数・投稿数。分類の根拠は連携スタンプのみ。
class _ServiceStat {
  /// バケット識別子（appleMusic / spotify / none / unstamped）。
  final String key;
  final String label;
  final Color color;
  final int users;
  final int? posts;

  const _ServiceStat({
    required this.key,
    required this.label,
    required this.color,
    required this.users,
    required this.posts,
  });
}

/// サービスを乗り換えたユーザー 1 人分。
class _ServiceSwitch {
  final String uid;
  final String displayName;
  final String? username;

  /// 乗り換え前 / 後（appleMusic / spotify / none）。
  final String from;
  final String to;

  final DateTime? changedAt;
  final int switchCount;

  const _ServiceSwitch({
    required this.uid,
    required this.displayName,
    required this.username,
    required this.from,
    required this.to,
    required this.changedAt,
    required this.switchCount,
  });
}

/// サービス識別子を日本語表示に直す。
String serviceLabel(String key) {
  switch (key) {
    case 'appleMusic':
      return 'Apple Music';
    case 'spotify':
      return 'Spotify';
    case 'none':
      return '未連携';
    default:
      return key.isEmpty ? '不明' : key;
  }
}

class _AnalyticsData {
  // ── 累計（時間軸に依らない） ──
  final int? totalUsers;
  final int? totalPosters;
  final int? totalPostCompletions;

  // ── 15s Day（通知 〜 次の通知）単位 ──
  /// 新しい→古い順の 15s Day 一覧。先頭が現在進行中。空なら通知が未発火。
  final List<MusicMemoryDayWindow> days;
  final int? newUsersInDay;
  final int? dau;
  final int? mau;
  final int? dayPosters;
  final int? dayPostCompletions;

  final _Retention retention;
  final List<_ServiceStat> services;

  /// サービスを乗り換えたユーザー（新しい順）。
  final List<_ServiceSwitch> switches;

  /// 参考値: 投稿の楽曲取得元（連携先とは一致しない）。
  final Map<String, int> trackSources;

  const _AnalyticsData({
    this.totalUsers,
    this.totalPosters,
    this.totalPostCompletions,
    required this.days,
    this.newUsersInDay,
    this.dau,
    this.mau,
    this.dayPosters,
    this.dayPostCompletions,
    this.retention = const _Retention(),
    this.services = const [],
    this.switches = const [],
    this.trackSources = const {},
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
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}

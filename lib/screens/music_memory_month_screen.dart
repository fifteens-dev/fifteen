import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../models/post_model.dart';
import '../services/post_service.dart';
import '../constants/profile_fonts.dart';
import '../widgets/variable_blur.dart';
import 'vibe_user_story_screen.dart';
import 'home/vibe_story_bar_section.dart';
import 'music_memory_detail_screen.dart';

/// Music Memory - Month 画面。
///
/// Figma 4773:10006 / 4773:10371(ヘッダ) / 4773:10259(月カード) 準拠。
///
/// - 上部ヘッダは position: fixed。"Music Memory" 20px Bold + 左に 44×44 の
///   円形戻るボタン。
/// - スクロールコンテンツ: 月ブロックを 古い→新しい の順で上から並べる。
///   月ブロック間は 55px 間隔、最下部に記録カード(236×47)。
/// - 初期表示は下端にオートスクロール → 「今月＋記録カード」が見える状態。
///   上へ pull すると過去月が現れる。
/// - 戻りは iOS 風エッジスワイプ(CupertinoPageRoute)、戻る矢印タップも同じ。
class MusicMemoryMonthScreen extends StatefulWidget {
  /// 表示する月ごとの投稿。key = "YYYY-MM"、value = その月に投稿された投稿一覧。
  final Map<String, List<PostModel>> postsByMonth;

  /// アカウント作成日時。指定されている場合、その月から現在の月までを
  /// （投稿の有無に関わらず）連続して表示する。
  final DateTime? accountCreatedAt;

  /// 表示対象ユーザーの uid。指定されている場合は投稿を一気に読み込まず、
  /// 3ヶ月区切りで（新しい月から）スクロールに応じて遅延ロードする。
  final String? userId;

  /// 記録カードに表示する総投稿数。遅延ロード中はロード済み分しか集計できないため、
  /// 呼び出し側が把握している総数があればここで上書きする。
  final int? totalPostCount;

  /// ルートタブとして埋め込む場合 true。戻るボタンを非表示にする。
  final bool embedded;

  const MusicMemoryMonthScreen({
    super.key,
    this.postsByMonth = const {},
    this.accountCreatedAt,
    this.userId,
    this.totalPostCount,
    this.embedded = false,
  });

  static Future<void> push(
    BuildContext context, {
    Map<String, List<PostModel>> postsByMonth = const {},
    DateTime? accountCreatedAt,
    String? userId,
    int? totalPostCount,
  }) {
    return Navigator.of(context).push(
      CupertinoPageRoute(
        fullscreenDialog: false,
        builder: (_) => MusicMemoryMonthScreen(
          postsByMonth: postsByMonth,
          accountCreatedAt: accountCreatedAt,
          userId: userId,
          totalPostCount: totalPostCount,
        ),
      ),
    );
  }

  @override
  State<MusicMemoryMonthScreen> createState() =>
      _MusicMemoryMonthScreenState();
}

class _MusicMemoryMonthScreenState extends State<MusicMemoryMonthScreen> {
  final ScrollController _scrollController = ScrollController();
  final PostService _postService = PostService();

  /// 1 チャンク = 3ヶ月。スクロールでこの単位ずつ過去へ読み込む。
  static const int _chunkMonths = 3;

  /// 新しい→古い順の全月キー ("YYYY-MM")。表示範囲の骨格。
  late final List<String> _monthsNewToOld;

  /// 月キー → その月の投稿。ロード済みチャンク分だけ埋まる。
  final Map<String, List<PostModel>> _postsByMonth = {};

  /// 新しい方から数えたロード済みチャンク数。
  int _loadedChunks = 0;
  bool _isLoading = false;

  /// userId 指定時のみ遅延ロード。無ければ渡された postsByMonth を静的表示。
  late final bool _lazy;

  int get _monthCount => _monthsNewToOld.length;
  int get _loadedMonthCount =>
      (_loadedChunks * _chunkMonths).clamp(0, _monthCount);
  bool get _hasMore => _loadedMonthCount < _monthCount;

  int get _loadedTotalCount =>
      _postsByMonth.values.fold(0, (a, b) => a + b.length);

  int get _totalCount => widget.totalPostCount ?? _loadedTotalCount;

  int get _streak {
    final days = <DateTime>{};
    for (final posts in _postsByMonth.values) {
      for (final p in posts) {
        final d = p.createdAt;
        days.add(DateTime(d.year, d.month, d.day));
      }
    }
    var streak = 0;
    var cursor = DateTime.now();
    cursor = DateTime(cursor.year, cursor.month, cursor.day);
    while (days.contains(cursor)) {
      streak++;
      cursor = cursor.subtract(const Duration(days: 1));
    }
    return streak;
  }

  @override
  void initState() {
    super.initState();
    _monthsNewToOld = _buildMonthsNewToOld();
    _lazy = widget.userId != null && widget.userId!.isNotEmpty;
    if (_lazy) {
      _loadNextChunk(); // 最新 3ヶ月を先行ロード
    } else {
      // 静的表示: 渡された分を全ロード済み扱いにする。
      _postsByMonth.addAll(widget.postsByMonth);
      _loadedChunks = (_monthCount / _chunkMonths).ceil();
    }
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  /// 表示する月の骨格を「新しい→古い」順で構築する。
  List<String> _buildMonthsNewToOld() {
    final now = DateTime.now();
    final created = widget.accountCreatedAt;
    if (created != null) {
      final result = <String>[];
      var y = now.year;
      var m = now.month;
      while (y > created.year || (y == created.year && m >= created.month)) {
        result.add('$y-${m.toString().padLeft(2, '0')}');
        m--;
        if (m < 1) {
          m = 12;
          y--;
        }
      }
      return result;
    }
    final keys = widget.postsByMonth.keys.toList()..sort(); // 古い→新しい
    if (keys.isNotEmpty) return keys.reversed.toList();
    return List.generate(3, (i) {
      final d = DateTime(now.year, now.month - i);
      return '${d.year}-${d.month.toString().padLeft(2, '0')}';
    });
  }

  /// reverse:true のリストでは、上（過去）方向へスクロールすると pixels が
  /// maxScrollExtent に近づく。手前で次チャンクを先読みする。
  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final pos = _scrollController.position;
    if (pos.pixels >= pos.maxScrollExtent - 400) {
      _loadNextChunk();
    }
  }

  Future<void> _loadNextChunk() async {
    if (!_lazy || _isLoading || !_hasMore) return;
    setState(() => _isLoading = true);

    final chunk = _loadedChunks; // 0-based
    final newestIdx = chunk * _chunkMonths;
    final oldestIdx =
        ((chunk + 1) * _chunkMonths - 1).clamp(0, _monthCount - 1);
    final rangeStart = _firstDayOfMonthKey(_monthsNewToOld[oldestIdx]);
    final rangeEnd = _firstDayOfNextMonth(_monthsNewToOld[newestIdx]);

    final posts = await _postService.getUserPostsInRange(
      widget.userId!,
      rangeStart,
      rangeEnd,
    );
    if (!mounted) return;

    for (final p in posts) {
      final key =
          '${p.createdAt.year}-${p.createdAt.month.toString().padLeft(2, '0')}';
      (_postsByMonth[key] ??= []).add(p);
    }
    setState(() {
      _loadedChunks++;
      _isLoading = false;
    });
  }

  DateTime _firstDayOfMonthKey(String key) {
    final parts = key.split('-');
    return DateTime(int.parse(parts[0]), int.parse(parts[1]), 1);
  }

  DateTime _firstDayOfNextMonth(String key) {
    final parts = key.split('-');
    return DateTime(int.parse(parts[0]), int.parse(parts[1]) + 1, 1);
  }

  /// ロード済みの全投稿を新しい順で平坦化。
  List<PostModel> _allLoadedPosts() {
    final list = <PostModel>[];
    for (final v in _postsByMonth.values) {
      list.addAll(v);
    }
    list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return list;
  }

  /// カレンダー上のアルバムアートタップ。
  /// ストーリー（Vibe 投稿）は Vibe プレイリスト形式、気分投稿は投稿カード形式で開く。
  void _openPost(PostModel post) {
    // Vibe 機能は一時的に全面非表示。過去の Vibe 投稿も含め、
    // すべて投稿カード（Music Memory 詳細）形式で表示する（表示時変換・可逆）。
    _openPostCard(post);
  }

  void _openVibeStory(PostModel post) {
    final uid = widget.userId ?? '';
    bool sameDay(DateTime a, DateTime b) =>
        a.year == b.year && a.month == b.month && a.day == b.day;
    final vibePosts = _allLoadedPosts()
        .where((p) => p.isVibe && sameDay(p.createdAt, post.createdAt))
        .toList();
    final idx = vibePosts.indexWhere((p) => p.postId == post.postId);
    final storyItem = VibeStoryItem(
      userId: uid,
      unread: false,
      posts: vibePosts.isEmpty ? [post] : vibePosts,
    );
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => VibeUserStoryScreen(
          stories: [storyItem],
          currentUserId: uid,
          initialPostIndex: idx < 0 ? 0 : idx,
        ),
      ),
    );
  }

  /// 気分投稿を Music Memory 詳細（日カルーセル）で開く。
  /// 各日の代表（最新1件）を新しい→古い順に並べ、タップした日を初期表示にする。
  void _openPostCard(PostModel post) {
    bool sameDay(DateTime a, DateTime b) =>
        a.year == b.year && a.month == b.month && a.day == b.day;

    // ロード済みの気分投稿を日ごとにグルーピングし、各日の最新を代表にする。
    final repByDay = <String, PostModel>{};
    // Vibe 投稿も含めた全投稿を対象にする（過去 Vibe を投稿カードとして表示）。
    for (final p in _allLoadedPosts()) {
      final key = '${p.createdAt.year}-${p.createdAt.month}-${p.createdAt.day}';
      final ex = repByDay[key];
      if (ex == null || p.createdAt.isAfter(ex.createdAt)) repByDay[key] = p;
    }
    final days = repByDay.values.toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt)); // 新しい→古い
    if (days.isEmpty) days.add(post);
    final idx = days.indexWhere((p) => sameDay(p.createdAt, post.createdAt));

    // 詳細画面でも端まで来たら 3ヶ月前を追加ロードできるよう、遅延ロードの
    // 骨格（月一覧・ロード済みチャンク数・userId）を渡す。
    MusicMemoryDetailScreen.push(
      context,
      posts: days,
      initialIndex: idx < 0 ? 0 : idx,
      userId: widget.userId,
      monthsNewToOld: _monthsNewToOld,
      loadedChunks: _loadedChunks,
    );
  }

  @override
  Widget build(BuildContext context) {
    // reverse:true の ListView で「最下部 = 現在月＋記録カード」を初期表示。
    // children は下→上の順で並べる（index 0 が最下部）。
    // 画面上部の黒い空白をなくすため SafeArea(top) を無効化し、
    // ステータスバー下まで内容とぼかしを敷く。その分の余白は topInset で確保。
    final topInset = MediaQuery.of(context).padding.top;
    // すりガラスは画面上部およそ 30% の帯に収め、そこから下へフェードさせる。
    final fadeH = MediaQuery.of(context).size.height * 0.3;
    final loadedCount = _loadedMonthCount;
    final children = <Widget>[
      // 最下部余白。ルートタブ埋め込み時(embedded)はボトムナビ(画面下から約94px)と
      // 重ならないよう、Figma 5189:11310 準拠で記録カード下端を画面下から約160pxに上げる。
      SizedBox(height: widget.embedded ? 160 : 40),
      // 記録カード(Figma: (83, 1214), 236×47) — 中央 83px マージン
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 83),
        child: _RecordCard(
          musicCount: _totalCount,
          streak: _streak,
        ),
      ),
      const SizedBox(height: 55),
      for (int i = 0; i < loadedCount; i++) ...[
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: _MonthBlock(
            monthKey: _monthsNewToOld[i],
            posts: _postsByMonth[_monthsNewToOld[i]] ?? const [],
            onPostTap: _openPost,
          ),
        ),
        const SizedBox(height: 55),
      ],
      if (_isLoading)
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 16),
          child: Center(
            child: SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.white54,
              ),
            ),
          ),
        ),
      SizedBox(height: 60 + 24 + topInset), // 最上部ヘッダー＋ステータスバー分の余白
    ];

    final list = ListView(
      controller: _scrollController,
      reverse: true,
      physics: const BouncingScrollPhysics(),
      children: children,
    );

    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      // 上下の黒い空白をなくすため SafeArea を使わず、画面端まで内容を敷く。
      body: Stack(
        children: [
          Positioned.fill(child: list),
          // 上部の連続ぼかし: iOS ネイティブ(UIVisualEffectView + グラデマスク)。
          // ビューは画面全体に広げ、マスクを上端(フル)→画面の約28%地点で 0 に
          // フェードする。ぼかしが見える範囲は上部だけだが、ビューの矩形下端は
          // 画面下(＝ぼかし0の領域)にあるため、境目が一切見えない。
          const Positioned.fill(
            child: VariableBlur(fullUntil: 0.0, fadeEnd: 0.28, passes: 2),
          ),
          // 黒グラデーション: ぼかしと同じ帯に上→下で重ね、ぼかしの薄れと同時に
          // 内容が背景色へ溶けるようにして境目を目立たなくする。
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: fadeH,
            child: const IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Color(0xA6121212), Color(0x00121212)],
                    stops: [0.0, 1.0],
                  ),
                ),
              ),
            ),
          ),
          // ヘッダー(Figma 4773:10371) — ステータスバー分下げて固定表示。
          _Header(topInset: topInset, showBack: !widget.embedded),
        ],
      ),
    );
  }
}

/// ヘッダ: "Music Memory" タイトル(中央) + 左に円形戻るボタン。
/// Figma 4773:10371:
///   - 全体 248×44 at (20, 63)
///   - タイトル 20px SF Pro Rounded Bold @ (113, 10)
///   - 戻るボタン 44×44 @ (0, 0)
class _Header extends StatelessWidget {
  const _Header({this.topInset = 0, this.showBack = true});

  /// ステータスバー高。SafeArea(top:false) 下でヘッダーを実画面上端から下げる分。
  final double topInset;

  /// 戻るボタンを表示するか（ルートタブ埋め込み時は false）。
  final bool showBack;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: 0,
      right: 0,
      top: topInset,
      height: 60,
      // 背景は上部フェード(グラデーション)側が描くので、ヘッダー自体は透明。
      child: DecoratedBox(
        decoration: const BoxDecoration(color: Colors.transparent),
        child: Stack(
          alignment: Alignment.center,
          children: [
            const Text(
              'Music Memory',
              style: TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.w700,
                fontFamily: kSfProRounded,
              ),
            ),
            if (showBack)
              Positioned(
                left: 20,
                top: (60 - 44) / 2,
                width: 44,
                height: 44,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => Navigator.of(context).maybePop(),
                  child: Container(
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      color: Color(0xFF1E1E1E),
                    ),
                    alignment: Alignment.center,
                    child: const Icon(
                      CupertinoIcons.chevron_left,
                      color: Colors.white,
                      size: 20,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// 1か月分のブロック(Figma 4773:10259)。
/// - コンテナ: border #272627 1px / radius 19 / 上下で 2 色分割
/// - 上部ヘッダ 44 高 / bg #131315: "n月" 18px SF Pro Rounded Bold @ (17, 12)
/// - 下部ドットエリア (bg #0B0B0B): 高さ = ドット行数×48 - 36 + 62(上下 31px)
class _MonthBlock extends StatelessWidget {
  final String monthKey; // "YYYY-MM"
  final List<PostModel> posts;
  final ValueChanged<PostModel>? onPostTap;

  const _MonthBlock({
    required this.monthKey,
    required this.posts,
    this.onPostTap,
  });

  int get _year => int.parse(monthKey.split('-').first);
  int get _month => int.parse(monthKey.split('-').last);

  @override
  Widget build(BuildContext context) {
    final label = '$_month月';
    final firstDay = DateTime(_year, _month, 1);
    final daysInMonth = DateTime(_year, _month + 1, 0).day;
    // Sunday=0 起点。DateTime.weekday は Mon=1..Sun=7 → %7 で Sun=0..Sat=6
    final firstDayCol = firstDay.weekday % 7;
    final byDay = <int, PostModel>{};
    for (final p in posts) {
      byDay.putIfAbsent(p.createdAt.day, () => p);
    }

    // 行数: 月初の曜日オフセット + 日数 を 7 で割り上げ
    final rows = ((firstDayCol + daysInMonth) / 7).ceil();
    // 各セル 48px 間隔。最終行のドットは 12px 高、他の行は次のドットまで 48。
    // → グリッド高 = rows * 48 - (48 - 12) = rows * 48 - 36
    final gridHeight = rows * 48 - 36;
    // 上下 31px マージン(Figma: 5行=266, 6行=314 と一致)
    final dotAreaHeight = (gridHeight + 62).toDouble();

    // border は foregroundDecoration で「子より前面」に描く。
    // decoration の border は子の背景色(#0B0B0B)に上書きされて丸角部分で
    // 消えてしまうため、前景に置くことで丸角にもきちんと線が乗る。
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF131315),
        borderRadius: BorderRadius.circular(19),
      ),
      foregroundDecoration: BoxDecoration(
        borderRadius: BorderRadius.circular(19),
        border: Border.all(color: const Color(0xFF272627), width: 1),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          // 月ヘッダ 44 高
          SizedBox(
            height: 44,
            child: Padding(
              padding: const EdgeInsets.only(left: 17, top: 12),
              child: Text(
                label,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  fontFamily: kSfProRounded,
                  height: 1.0,
                ),
              ),
            ),
          ),
          // ドットグリッドエリア
          Container(
            height: dotAreaHeight,
            color: const Color(0xFF0B0B0B),
            child: _MonthDotGrid(
              firstDayCol: firstDayCol,
              daysInMonth: daysInMonth,
              byDay: byDay,
              onPostTap: onPostTap,
            ),
          ),
        ],
      ),
    );
  }
}

/// 月内 N 日ぶんの 7 列ドットグリッド(Figma 4773:10262/10263 準拠)。
/// - グリッド起点: (35, 31) ドットエリア内
/// - セル 48×48、dot 12×12(セル左上に配置)
/// - アルバムアート 42×42 radius 10、dot と中心合わせ
class _MonthDotGrid extends StatelessWidget {
  final int firstDayCol;
  final int daysInMonth;
  final Map<int, PostModel> byDay;
  final ValueChanged<PostModel>? onPostTap;

  const _MonthDotGrid({
    required this.firstDayCol,
    required this.daysInMonth,
    required this.byDay,
    this.onPostTap,
  });

  @override
  Widget build(BuildContext context) {
    const dotSize = 12.0;
    const artSize = 42.0;
    const cellSize = 48.0;
    const gridLeft = 35.0;
    const gridTop = 31.0;

    // day → (col, row) を計算する関数
    (int, int) posOf(int day) {
      final idx = firstDayCol + (day - 1);
      return (idx % 7, idx ~/ 7);
    }

    return Stack(
      clipBehavior: Clip.hardEdge,
      children: [
        // 全日ドット
        for (int day = 1; day <= daysInMonth; day++)
          () {
            final (col, row) = posOf(day);
            return Positioned(
              left: gridLeft + col * cellSize,
              top: gridTop + row * cellSize,
              width: dotSize,
              height: dotSize,
              child: Image.asset(
                'assets/profile/memory_dot.png',
                errorBuilder: (_, __, ___) => Container(
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    color: Color(0xFF2A2A2A),
                  ),
                ),
              ),
            );
          }(),
        // 投稿がある日はアルバムアートで上書き
        for (final entry in byDay.entries)
          () {
            final (col, row) = posOf(entry.key);
            return Positioned(
              left: gridLeft + col * cellSize + (dotSize - artSize) / 2,
              top: gridTop + row * cellSize + (dotSize - artSize) / 2,
              width: artSize,
              height: artSize,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: onPostTap == null
                    ? null
                    : () => onPostTap!(entry.value),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: entry.value.track.albumImageUrl.isNotEmpty
                      ? CachedNetworkImage(
                          imageUrl: entry.value.track.albumImageUrl,
                          fit: BoxFit.cover,
                          errorWidget: (_, __, ___) => _placeholder(),
                        )
                      : _placeholder(),
                ),
              ),
            );
          }(),
      ],
    );
  }

  Widget _placeholder() => Container(
        color: const Color(0xFF3A3A3A),
        alignment: Alignment.center,
        child: const Icon(Icons.album, color: Colors.white38, size: 18),
      );
}

/// 記録カード(Figma 4773:10253) — 236×47。
/// 中身は プロフィール画面と同じ「💜 n Music | 🔥 nd 連続」。
class _RecordCard extends StatelessWidget {
  final int musicCount;
  final int streak;

  const _RecordCard({required this.musicCount, required this.streak});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 47,
      decoration: BoxDecoration(
        color: const Color(0xFF09090A),
        borderRadius: BorderRadius.circular(15),
      ),
      foregroundDecoration: BoxDecoration(
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: const Color(0xFF272627), width: 1),
      ),
      clipBehavior: Clip.antiAlias,
      child: Row(
        children: [
          Expanded(
            child: Center(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('💜', style: TextStyle(fontSize: 14)),
                  const SizedBox(width: 6),
                  Text(
                    '$musicCount Music',
                    style: const TextStyle(
                      color: Color(0xFF5C5656),
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      fontFamily: kSfProRounded,
                    ),
                  ),
                ],
              ),
            ),
          ),
          Container(width: 1, height: 14, color: const Color(0xFF272627)),
          Expanded(
            child: Center(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('🔥', style: TextStyle(fontSize: 14)),
                  const SizedBox(width: 4),
                  Text(
                    '${streak}d 連続',
                    style: const TextStyle(
                      color: Color(0xFF5C5656),
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      fontFamily: kSfProRounded,
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
}

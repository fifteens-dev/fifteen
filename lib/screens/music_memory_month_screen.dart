import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../models/post_model.dart';
import '../constants/profile_fonts.dart';

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

  const MusicMemoryMonthScreen({
    super.key,
    this.postsByMonth = const {},
  });

  static Future<void> push(
    BuildContext context, {
    Map<String, List<PostModel>> postsByMonth = const {},
  }) {
    return Navigator.of(context).push(
      CupertinoPageRoute(
        fullscreenDialog: false,
        builder: (_) => MusicMemoryMonthScreen(postsByMonth: postsByMonth),
      ),
    );
  }

  @override
  State<MusicMemoryMonthScreen> createState() =>
      _MusicMemoryMonthScreenState();
}

class _MusicMemoryMonthScreenState extends State<MusicMemoryMonthScreen> {
  final ScrollController _scrollController = ScrollController();

  int get _totalCount =>
      widget.postsByMonth.values.fold(0, (a, b) => a + b.length);

  int get _streak {
    final days = <DateTime>{};
    for (final posts in widget.postsByMonth.values) {
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
    // 初期表示は「最下部 = 現在月＋記録カード」が見える状態。
    // 上に pull すると過去月が現れる(Figma のスクロール位置に準拠)。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) return;
      _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // 昇順ソート(古い→新しい)。データが無ければ直近3か月を空リストで表示。
    final now = DateTime.now();
    final keys = widget.postsByMonth.keys.toList()..sort();
    final months = keys.isNotEmpty
        ? keys
        : List.generate(3, (i) {
            final d = DateTime(now.year, now.month - (2 - i));
            return '${d.year}-${d.month.toString().padLeft(2, '0')}';
          });

    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      body: SafeArea(
        child: Stack(
          children: [
            Positioned.fill(
              child: SingleChildScrollView(
                controller: _scrollController,
                physics: const BouncingScrollPhysics(),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SizedBox(height: 60), // ヘッダー分の余白
                    const SizedBox(height: 24),
                    for (int i = 0; i < months.length; i++) ...[
                      if (i > 0) const SizedBox(height: 55),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: _MonthBlock(
                          monthKey: months[i],
                          posts: widget.postsByMonth[months[i]] ?? const [],
                        ),
                      ),
                    ],
                    const SizedBox(height: 55),
                    // 記録カード(Figma: (83, 1214), 236×47) — 中央 83px マージン
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 83),
                      child: _RecordCard(
                        musicCount: _totalCount,
                        streak: _streak,
                      ),
                    ),
                    const SizedBox(height: 40),
                  ],
                ),
              ),
            ),
            // ヘッダー(Figma 4773:10371) — 位置固定
            const _Header(),
          ],
        ),
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
  const _Header();

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: 0,
      right: 0,
      top: 0,
      height: 60,
      child: Container(
        color: const Color(0xFF121212),
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

  const _MonthBlock({required this.monthKey, required this.posts});

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

  const _MonthDotGrid({
    required this.firstDayCol,
    required this.daysInMonth,
    required this.byDay,
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

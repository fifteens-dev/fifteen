import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import '../constants/app_colors.dart';
import '../models/milfolha_team_score.dart';
import '../services/milfolha_service.dart';
import 'milfolha_team_profile_screen.dart';

/// Milfolha 対抗バトルのランキング画面（参加者全員が閲覧可）。
///
/// モック（バレー大会イベント）準拠のUIを黒背景・紫アクセントで再現。
/// 上部にイベントサマリー（残り時間・自分のチーム順位/ポイント・自分の個人ポイント）、
/// 下部にチームランキング（王冠付き）を表示する。
class MilfolhaRankingScreen extends StatefulWidget {
  const MilfolhaRankingScreen({super.key});

  @override
  State<MilfolhaRankingScreen> createState() => _MilfolhaRankingScreenState();
}

class _MilfolhaRankingScreenState extends State<MilfolhaRankingScreen> {
  static const Color _purple = Color(0xFF7B6FE6);

  final MilfolhaService _service = MilfolhaService();

  MilfolhaRankingResult? _result;
  MilfolhaPeriods? _periods;
  String? _myTeamId;
  String? _myUid;
  bool _loading = true;
  bool _finalized = false;

  Timer? _ticker;
  Duration _remaining = Duration.zero;

  @override
  void initState() {
    super.initState();
    _myUid = FirebaseAuth.instance.currentUser?.uid;
    _load();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final uid = _myUid;
      final results = await Future.wait([
        _service.computeRanking(),
        _service.getPeriods(),
        _service.isResultFinalizedOnce(),
        if (uid != null)
          _service.getMembership(uid)
        else
          Future<Map<String, dynamic>?>.value(null),
      ]);
      if (!mounted) return;
      final membership = results[3] as Map<String, dynamic>?;
      setState(() {
        _result = results[0] as MilfolhaRankingResult;
        _periods = results[1] as MilfolhaPeriods;
        _finalized = results[2] as bool;
        _myTeamId = membership?['teamId'] as String?;
        _loading = false;
      });
      _tick();
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _tick() {
    final end = _periods?.end;
    if (end == null) return;
    final now = DateTime.now();
    final diff = end.difference(now);
    setState(() => _remaining = diff.isNegative ? Duration.zero : diff);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Column(
          children: [
            _header(),
            Expanded(
              child: _loading
                  ? const Center(
                      child: CupertinoActivityIndicator(
                          color: Colors.white, radius: 14))
                  : RefreshIndicator(
                      color: Colors.white,
                      backgroundColor: const Color(0xFF1C1C1E),
                      onRefresh: _load,
                      child: ListView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                        children: [
                          _summaryCard(),
                          const SizedBox(height: 16),
                          _rankingCard(),
                          const SizedBox(height: 10),
                          const Center(
                            child: Text(
                              'ⓘ ランキングはリアルタイムで更新されます',
                              style: TextStyle(
                                  color: Color(0xFF7A7A7A), fontSize: 11),
                            ),
                          ),
                        ],
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  // ── ヘッダー（× + タイトル）──
  Widget _header() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => Navigator.pop(context),
            behavior: HitTestBehavior.opaque,
            child: const Icon(Icons.close, color: Colors.white),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Text(
              _finalized ? '最終結果' : 'ランキング',
              style: TextStyle(
                color: _finalized ? const Color(0xFFFFD700) : Colors.white,
                fontSize: 17,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const Icon(Icons.emoji_events, color: Color(0xFFFFD700), size: 22),
        ],
      ),
    );
  }

  String _fmtRemaining(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes % 60;
    final s = d.inSeconds % 60;
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(h)}:${two(m)}:${two(s)}';
  }

  String _fmtPeriod(MilfolhaPeriods? p) {
    if (p == null) return '';
    String jst(DateTime d) {
      final j = d.toUtc().add(const Duration(hours: 9));
      return '${j.month}/${j.day} ${j.hour.toString().padLeft(2, '0')}:${j.minute.toString().padLeft(2, '0')}';
    }

    return '${jst(p.start)} 〜 ${jst(p.end)}';
  }

  String _fmtPt(int n) {
    final s = n.toString();
    final buf = StringBuffer();
    for (int i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) buf.write(',');
      buf.write(s[i]);
    }
    return buf.toString();
  }

  // ── サマリーカード ──
  Widget _summaryCard() {
    final teams = _result?.teams ?? const <MilfolhaTeamScore>[];
    // 自分のチーム順位・ポイント
    int? myRank;
    int myTeamPt = 0;
    int diffToTop = 0;
    if (_myTeamId != null && teams.isNotEmpty) {
      for (int i = 0; i < teams.length; i++) {
        if (teams[i].teamId == _myTeamId) {
          myRank = i + 1;
          myTeamPt = teams[i].total;
          diffToTop = teams.first.total - myTeamPt;
          break;
        }
      }
    }
    // 自分の個人ポイント・順位
    final myPt = (_myUid != null)
        ? (_result?.individualPoints[_myUid] ?? 0)
        : 0;
    final myPtRank =
        (_myUid != null) ? _result?.individualRank[_myUid] : null;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF161616),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF262626)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // タイトル行 + 残り時間
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '🏐 バレー大会イベント',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _fmtPeriod(_periods),
                      style: const TextStyle(
                          color: Color(0xFF9A9A9A), fontSize: 12),
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  const Text('残り',
                      style: TextStyle(color: Color(0xFF9A9A9A), fontSize: 11)),
                  const SizedBox(height: 2),
                  Text(
                    _remaining == Duration.zero
                        ? '終了'
                        : _fmtRemaining(_remaining),
                    style: const TextStyle(
                      color: _purple,
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 14),
          const Divider(color: Color(0xFF262626), height: 1),
          const SizedBox(height: 14),
          // 3スタット
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _stat(
                label: 'あなたのチーム順位',
                value: myRank != null ? '$myRank' : '-',
                unit: myRank != null ? '位' : '',
                sub: '/ ${teams.length}チーム',
              ),
              _stat(
                label: 'あなたのチームポイント',
                value: _fmtPt(myTeamPt),
                unit: 'pt',
                sub: (myRank != null && myRank > 1)
                    ? '1位まであと ${_fmtPt(diffToTop)}pt'
                    : (myRank == 1 ? '1位' : ''),
                chip: true,
              ),
              _stat(
                label: 'あなたの個人ポイント',
                value: _fmtPt(myPt),
                unit: 'pt',
                sub: myPtRank != null ? '個人ランキング $myPtRank位' : '',
                chip: true,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _stat({
    required String label,
    required String value,
    required String unit,
    required String sub,
    bool chip = false,
  }) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: const TextStyle(color: Color(0xFF9A9A9A), fontSize: 10)),
          const SizedBox(height: 6),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Flexible(
                child: Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: _purple,
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              if (unit.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(left: 1, bottom: 2),
                  child: Text(unit,
                      style: const TextStyle(color: _purple, fontSize: 12)),
                ),
            ],
          ),
          const SizedBox(height: 6),
          if (sub.isNotEmpty)
            chip
                ? Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: _purple.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(sub,
                        style: const TextStyle(
                            color: _purple, fontSize: 9.5)),
                  )
                : Text(sub,
                    style: const TextStyle(
                        color: Color(0xFF7A7A7A), fontSize: 10)),
        ],
      ),
    );
  }

  // ── ランキングカード ──
  Widget _rankingCard() {
    final teams = _result?.teams ?? const <MilfolhaTeamScore>[];
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF161616),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF262626)),
      ),
      child: Column(
        children: [
          // タブ見出し（チームランキングのみ）
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            alignment: Alignment.centerLeft,
            child: const Text(
              'チームランキング',
              style: TextStyle(
                color: _purple,
                fontSize: 14,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const Divider(color: Color(0xFF262626), height: 1),
          for (int i = 0; i < teams.length; i++) ...[
            if (i > 0) const Divider(color: Color(0xFF222222), height: 1),
            _rankRow(i + 1, teams[i]),
          ],
        ],
      ),
    );
  }

  Widget _rankRow(int rank, MilfolhaTeamScore s) {
    final isMine = s.teamId == _myTeamId;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      // チーム名タップで班アカウントのプロフィール画面へ。
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => MilfolhaTeamProfileScreen(teamId: s.teamId),
        ),
      ),
      child: Container(
        color: isMine ? _purple.withValues(alpha: 0.10) : Colors.transparent,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
        children: [
          SizedBox(width: 36, child: _rankBadge(rank)),
          const SizedBox(width: 8),
          Expanded(
            child: RichText(
              text: TextSpan(
                children: [
                  TextSpan(
                    text: '${s.displayName}チーム',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (isMine)
                    const TextSpan(
                      text: '（あなたのチーム）',
                      style: TextStyle(color: _purple, fontSize: 12),
                    ),
                ],
              ),
            ),
          ),
          Text(
            '${_fmtPt(s.total)}',
            style: const TextStyle(
              color: _purple,
              fontSize: 18,
              fontWeight: FontWeight.w800,
            ),
          ),
          const Padding(
            padding: EdgeInsets.only(left: 1, top: 4),
            child: Text('pt', style: TextStyle(color: _purple, fontSize: 11)),
          ),
        ],
        ),
      ),
    );
  }

  Widget _rankBadge(int rank) {
    if (rank <= 3) {
      final color = rank == 1
          ? const Color(0xFFFFC93C)
          : rank == 2
              ? const Color(0xFFB9C0CC)
              : const Color(0xFFCD8E52);
      return Stack(
        alignment: Alignment.center,
        children: [
          Icon(Icons.emoji_events, color: color, size: 30),
          Positioned(
            bottom: 2,
            child: Text(
              '$rank',
              style: const TextStyle(
                color: Colors.black87,
                fontSize: 10,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      );
    }
    return Center(
      child: Text(
        '$rank',
        style: const TextStyle(
          color: Color(0xFF9A9A9A),
          fontSize: 15,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

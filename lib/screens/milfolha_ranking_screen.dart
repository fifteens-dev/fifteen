import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import '../constants/app_colors.dart';
import '../models/milfolha_team_score.dart';
import '../services/milfolha_service.dart';

/// Milfolha 対抗バトルのランキング画面（参加者全員が閲覧可）。
///
/// 画面を開いた時に [MilfolhaService.computeRanking] でクライアント集計し、
/// チーム別の総ポイント＋内訳（登録/投稿/外部登録/外部投稿）を降順表示する。
class MilfolhaRankingScreen extends StatefulWidget {
  const MilfolhaRankingScreen({super.key});

  @override
  State<MilfolhaRankingScreen> createState() => _MilfolhaRankingScreenState();
}

class _MilfolhaRankingScreenState extends State<MilfolhaRankingScreen> {
  final MilfolhaService _service = MilfolhaService();
  List<MilfolhaTeamScore>? _scores;
  bool _loading = true;
  bool _finalized = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final results = await Future.wait([
        _service.computeRanking(),
        _service.isResultFinalizedOnce(),
      ]);
      if (!mounted) return;
      setState(() {
        _scores = results[0] as List<MilfolhaTeamScore>;
        _finalized = results[1] as bool;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            // ヘッダー
            Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: const Icon(Icons.close, color: Colors.white),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Text(
                      _finalized ? '最終結果' : 'ランキング',
                      style: TextStyle(
                        color: _finalized
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
            const Divider(color: AppColors.divider, height: 1),
            Expanded(
              child: _loading
                  ? const Center(
                      child: CupertinoActivityIndicator(
                          color: Colors.white, radius: 14))
                  : RefreshIndicator(
                      color: Colors.white,
                      backgroundColor: AppColors.surface,
                      onRefresh: _load,
                      child: _buildList(),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildList() {
    final scores = _scores ?? const <MilfolhaTeamScore>[];
    return ListView.separated(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 40),
      itemCount: scores.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (context, i) => _teamCard(i + 1, scores[i]),
    );
  }

  Widget _teamCard(int rank, MilfolhaTeamScore s) {
    final medal = rank == 1
        ? const Color(0xFFFFD700)
        : rank == 2
            ? const Color(0xFFC0C0C0)
            : rank == 3
                ? const Color(0xFFCD7F32)
                : Colors.white24;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF1C1C1E),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF2C2C2E), width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              // 順位バッジ
              Container(
                width: 34,
                height: 34,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: medal.withValues(alpha: 0.18),
                  shape: BoxShape.circle,
                  border: Border.all(color: medal, width: 1.5),
                ),
                child: Text(
                  '$rank',
                  style: TextStyle(
                    color: medal == Colors.white24 ? Colors.white70 : medal,
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'チーム ${s.displayName}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      '${s.memberCount}人参加',
                      style: const TextStyle(
                          color: Color(0xFF9E9E9E), fontSize: 11),
                    ),
                  ],
                ),
              ),
              // 総ポイント
              Text(
                '${s.total}',
                style: const TextStyle(
                  color: Color(0xFFFFD700),
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const Padding(
                padding: EdgeInsets.only(left: 2, top: 8),
                child: Text('pt',
                    style: TextStyle(color: Color(0xFFFFD700), fontSize: 12)),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // 内訳
          Row(
            children: [
              _breakdown('登録', s.regPt),
              _breakdown('投稿', s.memberPostPt),
              _breakdown('外部登録', s.extRegPt),
              _breakdown('外部投稿', s.extPostPt),
            ],
          ),
        ],
      ),
    );
  }

  Widget _breakdown(String label, int pt) {
    return Expanded(
      child: Column(
        children: [
          Text(
            '+$pt',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 15,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: const TextStyle(color: Color(0xFF8B8B8B), fontSize: 10),
          ),
        ],
      ),
    );
  }
}

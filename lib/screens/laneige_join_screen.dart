import 'package:flutter/material.dart';
import '../constants/app_colors.dart';
import '../constants/laneige_teams.dart';
import '../services/laneige_service.dart';
import '../widgets/common/app_toast.dart';
import 'laneige_ranking_screen.dart';

/// Laneige イベント参加画面（チームコード入力 / 参加・切替・離脱 + ランキング）。
class LaneigeJoinScreen extends StatefulWidget {
  final String? currentTeamId;

  const LaneigeJoinScreen({super.key, this.currentTeamId});

  @override
  State<LaneigeJoinScreen> createState() => _LaneigeJoinScreenState();
}

class _LaneigeJoinScreenState extends State<LaneigeJoinScreen> {
  final _codeCtrl = TextEditingController();
  final _service = LaneigeService();
  bool _isLoading = false;
  String? _currentTeamId;

  @override
  void initState() {
    super.initState();
    _currentTeamId = widget.currentTeamId;
  }

  @override
  void dispose() {
    _codeCtrl.dispose();
    super.dispose();
  }

  Future<void> _join() async {
    final code = _codeCtrl.text.trim();
    if (code.isEmpty) return;
    setState(() => _isLoading = true);
    final result = await _service.joinTeamWithCode(code);
    if (!mounted) return;
    setState(() => _isLoading = false);

    switch (result) {
      case LaneigeJoinResult.success:
        AppToast.show(context, 'チームに参加しました！');
        setState(() {
          _currentTeamId = LaneigeTeamDefinitions.normalizeCode(code);
          _codeCtrl.clear();
        });
      case LaneigeJoinResult.switched:
        AppToast.show(context, 'チームを切り替えました');
        setState(() {
          _currentTeamId = LaneigeTeamDefinitions.normalizeCode(code);
          _codeCtrl.clear();
        });
      case LaneigeJoinResult.alreadyJoined:
        AppToast.show(context, 'すでにこのチームに参加しています');
      case LaneigeJoinResult.invalidCode:
        AppToast.show(context, 'チームコードが正しくありません');
      case LaneigeJoinResult.disabled:
        AppToast.show(context, 'イベントは現在開催されていません');
      case LaneigeJoinResult.error:
        AppToast.show(context, 'エラーが発生しました');
    }
  }

  Future<void> _leave() async {
    setState(() => _isLoading = true);
    final result = await _service.leaveTeam();
    if (!mounted) return;
    setState(() => _isLoading = false);
    if (result == LaneigeLeaveResult.success) {
      AppToast.show(context, 'チームから離脱しました');
      setState(() => _currentTeamId = null);
    } else if (result == LaneigeLeaveResult.notJoined) {
      AppToast.show(context, 'チームに参加していません');
    } else {
      AppToast.show(context, 'エラーが発生しました');
    }
  }

  @override
  Widget build(BuildContext context) {
    final isJoined = _currentTeamId != null;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        foregroundColor: Colors.white,
        title: const Text('LANEIGEイベント',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
        elevation: 0,
        actions: [
          TextButton.icon(
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const LaneigeRankingScreen()),
            ),
            icon: const Icon(Icons.emoji_events,
                color: Color(0xFFFFD700), size: 18),
            label: const Text('ランキング',
                style: TextStyle(color: Colors.white, fontSize: 13)),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 参加状況
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: const Color(0xFF1C1C1E),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFF2C2C2E)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    isJoined ? '参加中のチーム' : 'まだチームに参加していません',
                    style: const TextStyle(
                        color: Color(0xFF9E9E9E), fontSize: 12),
                  ),
                  if (isJoined) ...[
                    const SizedBox(height: 6),
                    Text(
                      'チーム ${LaneigeTeamDefinitions.displayNameOf(_currentTeamId!)}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 32),
            Text(
              isJoined ? '別のチームに切り替える' : 'チームコードを入力',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _codeCtrl,
              enabled: !_isLoading,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: '例: laneige_A',
                hintStyle: const TextStyle(color: Color(0xFF6B6B6B)),
                filled: true,
                fillColor: const Color(0xFF1C1C1E),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                onPressed: _isLoading ? null : _join,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: Colors.black,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(25),
                  ),
                ),
                child: _isLoading
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.black54),
                      )
                    : Text(
                        isJoined ? '切り替える' : '参加する',
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
              ),
            ),
            if (isJoined) ...[
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: OutlinedButton(
                  onPressed: _isLoading ? null : _leave,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFFFF453A),
                    side: const BorderSide(color: Color(0xFF3A3A3C)),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(25),
                    ),
                  ),
                  child: const Text('チームから離脱する'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

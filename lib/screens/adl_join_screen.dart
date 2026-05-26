import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../constants/adl_teams.dart';
import '../constants/app_colors.dart';
import '../services/adl_service.dart';
import '../widgets/common/app_toast.dart';
import 'adl_ranking_screen.dart';

/// ADLイベント参加画面（招待コード入力 / 離脱）
///
/// 9つの固定コード（adl_house, adl_break, ...）のいずれかを入力すると
/// その班に参加する。既に別の班に参加している場合は自動で切り替わる。
/// 画面下部に「班から離脱する」ボタンも表示する（参加中のみ）。
class AdlJoinScreen extends StatefulWidget {
  final String? currentTeamName; // 既に参加済みの場合の表示用
  final String? currentTeamId; // 切替判定用

  const AdlJoinScreen({
    super.key,
    this.currentTeamName,
    this.currentTeamId,
  });

  @override
  State<AdlJoinScreen> createState() => _AdlJoinScreenState();
}

class _AdlJoinScreenState extends State<AdlJoinScreen> {
  final _codeCtrl = TextEditingController();
  final _adl = AdlService();
  bool _isLoading = false;
  bool _isLeaving = false;

  // ローカル状態（参加 → 離脱や切替を画面遷移なしに反映するため）
  String? _currentTeamName;
  String? _currentTeamId;

  @override
  void initState() {
    super.initState();
    _currentTeamName = widget.currentTeamName;
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
    final result = await _adl.joinTeamWithCode(code);
    if (!mounted) return;
    setState(() => _isLoading = false);

    switch (result) {
      case AdlJoinResult.success:
        AppToast.show(context, 'チームに参加しました！');
        setState(() {
          _currentTeamId = AdlTeamDefinitions.normalizeCode(code);
          _currentTeamName =
              AdlTeamDefinitions.displayNameOf(_currentTeamId ?? '');
          _codeCtrl.clear();
        });
        // 呼び出し元に変更を通知（pop はせず画面に留まる）
      case AdlJoinResult.switched:
        AppToast.show(context, 'チームを切り替えました');
        setState(() {
          _currentTeamId = AdlTeamDefinitions.normalizeCode(code);
          _currentTeamName =
              AdlTeamDefinitions.displayNameOf(_currentTeamId ?? '');
          _codeCtrl.clear();
        });
      case AdlJoinResult.alreadyJoined:
        AppToast.show(context, 'すでにこの班に参加しています');
      case AdlJoinResult.invalidCode:
        AppToast.show(context, '招待コードが正しくありません');
      case AdlJoinResult.notSeeded:
        AppToast.show(context, '班データが未準備です（管理者にお問い合わせください）');
      case AdlJoinResult.disabled:
        AppToast.show(context, 'ADLイベントは現在開催されていません');
      case AdlJoinResult.error:
        AppToast.show(context, 'エラーが発生しました');
    }
  }

  Future<void> _leave() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surfaceLight,
        title: const Text('班から離脱しますか？',
            style: TextStyle(color: Colors.white, fontSize: 16)),
        content: Text(
          '${_currentTeamName ?? "現在の班"} から離脱します。\n班アカウントとのフォロー関係も自動的に解除されます。',
          style: const TextStyle(color: Colors.grey, fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('キャンセル',
                style: TextStyle(color: Colors.grey)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('離脱する',
                style: TextStyle(color: AppColors.error)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _isLeaving = true);
    final result = await _adl.leaveTeam();
    if (!mounted) return;
    setState(() => _isLeaving = false);

    switch (result) {
      case AdlLeaveResult.success:
        AppToast.show(context, '班から離脱しました');
        setState(() {
          _currentTeamId = null;
          _currentTeamName = null;
        });
      case AdlLeaveResult.notJoined:
        AppToast.show(context, '参加している班がありません');
        setState(() {
          _currentTeamId = null;
          _currentTeamName = null;
        });
      case AdlLeaveResult.error:
        AppToast.show(context, 'エラーが発生しました');
    }
  }

  @override
  Widget build(BuildContext context) {
    final isJoined = _currentTeamId != null;

    return PopScope(
      canPop: true,
      child: Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          backgroundColor: AppColors.background,
          foregroundColor: Colors.white,
          title: const Text('ADLイベント',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
          elevation: 0,
          actions: [
            TextButton.icon(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const AdlRankingScreen()),
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
              // ── 参加状況パネル ──
              _buildStatusPanel(isJoined),

              const SizedBox(height: 32),

              // ── 招待コード入力 ──
              Text(
                isJoined ? '別の班に切り替える' : '招待コードを入力',
                style: const TextStyle(
                    color: Colors.grey,
                    fontSize: 13,
                    fontWeight: FontWeight.w500),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _codeCtrl,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 1.2,
                    fontFamily: 'monospace'),
                textCapitalization: TextCapitalization.none,
                maxLength: 20,
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z0-9_]')),
                  _LowerCaseFormatter(),
                ],
                decoration: const InputDecoration(
                  hintText: 'adl_xxxx',
                  hintStyle: TextStyle(
                      color: Colors.grey,
                      fontSize: 18,
                      letterSpacing: 1.2,
                      fontFamily: 'monospace'),
                  counterText: '',
                  enabledBorder: UnderlineInputBorder(
                      borderSide: BorderSide(color: AppColors.border)),
                  focusedBorder: UnderlineInputBorder(
                      borderSide: BorderSide(color: Colors.white)),
                ),
              ),

              const SizedBox(height: 24),

              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _isLoading ? null : _join,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                  ),
                  child: _isLoading
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.black),
                        )
                      : Text(isJoined ? '班を切り替える' : '班に参加',
                          style: const TextStyle(
                              fontSize: 16, fontWeight: FontWeight.w700)),
                ),
              ),

              // ── 離脱ボタン（参加中のみ） ──
              if (isJoined) ...[
                const SizedBox(height: 24),
                Center(
                  child: TextButton(
                    onPressed: _isLeaving ? null : _leave,
                    style: TextButton.styleFrom(
                      foregroundColor: AppColors.error,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 24, vertical: 12),
                    ),
                    child: _isLeaving
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: AppColors.error),
                          )
                        : const Text(
                            '班から離脱する',
                            style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                decoration: TextDecoration.underline),
                          ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatusPanel(bool isJoined) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isJoined
            ? AppColors.success.withValues(alpha: 0.15)
            : AppColors.surfaceLight,
        borderRadius: BorderRadius.circular(14),
        border: isJoined
            ? Border.all(color: AppColors.success.withValues(alpha: 0.4))
            : null,
      ),
      child: isJoined
          ? Row(
              children: [
                const Icon(Icons.check_circle,
                    color: AppColors.success, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '$_currentTeamName 班に参加中',
                    style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                        fontSize: 15),
                  ),
                ),
              ],
            )
          : const Text(
              '班の招待コードを入力して参加してください',
              style: TextStyle(color: Colors.grey, fontSize: 14),
            ),
    );
  }
}

class _LowerCaseFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
      TextEditingValue oldValue, TextEditingValue newValue) {
    return newValue.copyWith(text: newValue.text.toLowerCase());
  }
}

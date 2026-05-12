import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../constants/app_colors.dart';
import '../models/adl_event_model.dart';
import '../services/adl_service.dart';
import '../widgets/common/app_toast.dart';
import 'adl_ranking_screen.dart';

/// ADLイベント参加画面（招待コード入力）
class AdlJoinScreen extends StatefulWidget {
  final AdlEventModel event;
  final String? currentTeamName; // 既に参加済みの場合

  const AdlJoinScreen({
    super.key,
    required this.event,
    this.currentTeamName,
  });

  @override
  State<AdlJoinScreen> createState() => _AdlJoinScreenState();
}

class _AdlJoinScreenState extends State<AdlJoinScreen> {
  final _codeCtrl = TextEditingController();
  final _adl = AdlService();
  bool _isLoading = false;

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
        Navigator.pop(context, true);
      case AdlJoinResult.invalidCode:
        AppToast.show(context, '招待コードが正しくありません');
      case AdlJoinResult.expired:
        AppToast.show(context, '招待コードの有効期限が切れています');
      case AdlJoinResult.alreadyJoined:
        AppToast.show(context, 'すでにチームに参加しています');
      case AdlJoinResult.error:
        AppToast.show(context, 'エラーが発生しました');
    }
  }

  @override
  Widget build(BuildContext context) {
    final alreadyJoined = widget.currentTeamName != null;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        foregroundColor: Colors.white,
        title: Text(widget.event.name,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
        elevation: 0,
        actions: [
          TextButton.icon(
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (_) => AdlRankingScreen(event: widget.event)),
            ),
            icon: const Icon(Icons.emoji_events,
                color: Color(0xFFFFD700), size: 18),
            label: const Text('ランキング',
                style: TextStyle(color: Colors.white, fontSize: 13)),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 参加状況
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: alreadyJoined
                    ? AppColors.success.withValues(alpha: 0.15)
                    : AppColors.surfaceLight,
                borderRadius: BorderRadius.circular(14),
                border: alreadyJoined
                    ? Border.all(
                        color: AppColors.success.withValues(alpha: 0.4))
                    : null,
              ),
              child: alreadyJoined
                  ? Row(
                      children: [
                        const Icon(Icons.check_circle,
                            color: AppColors.success, size: 20),
                        const SizedBox(width: 8),
                        Text(
                          '${widget.currentTeamName} に参加中',
                          style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w600,
                              fontSize: 15),
                        ),
                      ],
                    )
                  : const Text(
                      '班の招待コードを入力して参加してください',
                      style: TextStyle(color: Colors.grey, fontSize: 14),
                    ),
            ),

            if (!alreadyJoined) ...[
              const SizedBox(height: 32),
              const Text('招待コード',
                  style: TextStyle(
                      color: Colors.grey,
                      fontSize: 13,
                      fontWeight: FontWeight.w500)),
              const SizedBox(height: 8),
              TextField(
                controller: _codeCtrl,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 4,
                    fontFamily: 'monospace'),
                textCapitalization: TextCapitalization.characters,
                maxLength: 6,
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z0-9]')),
                  _UpperCaseFormatter(),
                ],
                decoration: const InputDecoration(
                  hintText: 'XXXXXX',
                  hintStyle: TextStyle(
                      color: Colors.grey,
                      fontSize: 22,
                      letterSpacing: 4,
                      fontFamily: 'monospace'),
                  counterText: '',
                  enabledBorder: UnderlineInputBorder(
                      borderSide: BorderSide(color: AppColors.border)),
                  focusedBorder: UnderlineInputBorder(
                      borderSide: BorderSide(color: Colors.white)),
                ),
              ),
              const SizedBox(height: 32),
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
                      : const Text('チームに参加',
                          style: TextStyle(
                              fontSize: 16, fontWeight: FontWeight.w700)),
                ),
              ),
            ],

            if (alreadyJoined) ...[
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) =>
                            AdlRankingScreen(event: widget.event)),
                  ),
                  icon: const Icon(Icons.emoji_events,
                      color: Color(0xFFFFD700)),
                  label: const Text('チームランキングを見る'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.surfaceLight,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _UpperCaseFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
      TextEditingValue oldValue, TextEditingValue newValue) {
    return newValue.copyWith(text: newValue.text.toUpperCase());
  }
}

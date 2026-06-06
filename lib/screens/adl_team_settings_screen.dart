import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import '../models/adl_team_model.dart';
import '../services/adl_service.dart';
import '../widgets/common/app_toast.dart';
import '../widgets/dialogs/confirm_dialog.dart';
import 'adl_team_account_edit_screen.dart';

/// ADL班プロフィールの設定画面。
/// 「班のアカウント」と「ADLイベント」の2セクションのみを縦に並べる。
class AdlTeamSettingsScreen extends StatefulWidget {
  final AdlTeamModel team;
  final String displayName;
  final VoidCallback? onChanged;

  const AdlTeamSettingsScreen({
    super.key,
    required this.team,
    required this.displayName,
    this.onChanged,
  });

  @override
  State<AdlTeamSettingsScreen> createState() => _AdlTeamSettingsScreenState();
}

class _AdlTeamSettingsScreenState extends State<AdlTeamSettingsScreen> {
  late AdlTeamModel _team;
  final AdlService _adlService = AdlService();
  bool _isLeaving = false;

  @override
  void initState() {
    super.initState();
    _team = widget.team;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(context),
            Expanded(
              child: SingleChildScrollView(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 8),

                      // 班のアカウント
                      _buildSectionLabel('班のアカウント'),
                      const SizedBox(height: 8),
                      _buildAccountCard(context),

                      const SizedBox(height: 24),

                      // ADLイベント
                      _buildSectionLabel('ADLイベント'),
                      const SizedBox(height: 8),
                      _buildAdlEventCard(),

                      const SizedBox(height: 24),

                      // 班を離脱するボタン
                      _buildLeaveButton(context),

                      const SizedBox(height: 32),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLeaveButton(BuildContext context) {
    return Container(
      width: double.infinity,
      height: 50,
      decoration: BoxDecoration(
        color: Colors.grey[800],
        borderRadius: BorderRadius.circular(15),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(15),
          onTap: _isLeaving ? null : () => _showLeaveDialog(context),
          child: Center(
            child: _isLeaving
                ? const CupertinoActivityIndicator(color: Colors.red, radius: 10)
                : const Text(
                    '班を離脱する',
                    style: TextStyle(
                      color: Colors.red,
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
          ),
        ),
      ),
    );
  }

  Future<void> _showLeaveDialog(BuildContext context) async {
    final confirmed = await ConfirmDialog.show(
      context,
      title: '班を離脱する',
      message: '${widget.displayName} 班から離脱しますか？',
      cancelText: 'キャンセル',
      confirmText: '離脱する',
      confirmColor: Colors.red,
    );
    if (!confirmed || !mounted) return;

    setState(() => _isLeaving = true);
    try {
      final result = await _adlService.leaveTeam();
      if (!mounted) return;
      if (result == AdlLeaveResult.success ||
          result == AdlLeaveResult.notJoined) {
        widget.onChanged?.call();
        AppToast.show(context, '班から離脱しました');
        // 設定画面と班プロフィール画面の両方を閉じる
        Navigator.of(context)..pop()..pop();
      } else {
        AppToast.show(context, '離脱に失敗しました');
      }
    } catch (e) {
      if (!mounted) return;
      AppToast.show(context, '離脱に失敗しました: $e');
    } finally {
      if (mounted) setState(() => _isLeaving = false);
    }
  }

  Widget _buildHeader(BuildContext context) {
    return Container(
      height: 45,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.chevron_left, color: Colors.white, size: 28),
            onPressed: () => Navigator.pop(context),
          ),
          const Expanded(
            child: Text(
              '設定',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white,
                fontSize: 15,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(width: 48),
        ],
      ),
    );
  }

  Widget _buildSectionLabel(String label) {
    return Text(
      label,
      style: const TextStyle(
        color: Color(0xFF555557),
        fontSize: 11,
        fontWeight: FontWeight.bold,
      ),
    );
  }

  Widget _buildAccountCard(BuildContext context) {
    final imageUrl = _team.profileImageUrl;
    return Container(
      height: 82,
      decoration: BoxDecoration(
        color: Colors.grey[800],
        borderRadius: BorderRadius.circular(15),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(15),
          onTap: () async {
            final changed = await Navigator.push<bool>(
              context,
              MaterialPageRoute(
                builder: (_) => AdlTeamAccountEditScreen(
                  team: _team,
                  displayName: widget.displayName,
                ),
              ),
            );
            if (changed == true) {
              widget.onChanged?.call();
              // 自画面のカードプレビュー用に最新スナップショットを再取得
              // 簡便化のため、edit 画面から戻ってきたら親に再ロードを促す
            }
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
            child: Row(
              children: [
                Container(
                  width: 59,
                  height: 59,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.grey[700],
                  ),
                  child: ClipOval(
                    child: (imageUrl != null && imageUrl.isNotEmpty)
                        ? CachedNetworkImage(
                            imageUrl: imageUrl,
                            width: 59,
                            height: 59,
                            fit: BoxFit.cover,
                            errorWidget: (_, __, ___) => _initial(),
                          )
                        : _initial(),
                  ),
                ),
                const SizedBox(width: 18),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${widget.displayName} 班',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '@${_team.teamId}',
                        style: const TextStyle(
                          color: Color(0xCCFFFFFF),
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
                const Icon(
                  Icons.chevron_right,
                  color: Colors.white54,
                  size: 29,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _initial() {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF1937EF), Color(0xFFFE1F56)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      alignment: Alignment.center,
      child: Text(
        widget.displayName.isNotEmpty
            ? widget.displayName.substring(0, 1).toUpperCase()
            : '?',
        style: const TextStyle(
          color: Colors.white,
          fontSize: 24,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }

  Widget _buildAdlEventCard() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.grey[800],
        borderRadius: BorderRadius.circular(15),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
        child: Row(
          children: [
            const Icon(Icons.groups, color: Colors.white, size: 22),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                '${widget.displayName} 班（運営中）',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

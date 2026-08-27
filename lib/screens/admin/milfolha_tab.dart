import 'package:flutter/material.dart';
import '../../constants/app_colors.dart';
import '../../constants/milfolha_teams.dart';
import '../../models/milfolha_team_score.dart';
import '../../services/milfolha_service.dart';
import '../../widgets/common/app_toast.dart';

/// 管理者パネル: Milfolha イベント管理タブ。
/// モード ON/OFF、期間表示、結果確定、集計プレビュー、チームコード一覧。
class MilfolhaTab extends StatefulWidget {
  const MilfolhaTab({super.key});

  @override
  State<MilfolhaTab> createState() => _MilfolhaTabState();
}

class _MilfolhaTabState extends State<MilfolhaTab> {
  final _service = MilfolhaService();
  bool _busy = false;
  List<MilfolhaTeamScore>? _preview;
  bool _previewing = false;

  Future<void> _toggleActive(bool v) async {
    setState(() => _busy = true);
    await _service.setActive(v);
    if (mounted) setState(() => _busy = false);
    if (mounted) {
      AppToast.show(context, v ? 'Milfolha を開始しました' : 'Milfolha を停止しました');
    }
  }

  Future<void> _toggleFinalized(bool v) async {
    setState(() => _busy = true);
    await _service.setResultFinalized(v);
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _runPreview() async {
    setState(() => _previewing = true);
    try {
      final scores = await _service.computeRanking();
      if (mounted) setState(() => _preview = scores);
    } catch (_) {
      if (mounted) AppToast.show(context, '集計に失敗しました');
    } finally {
      if (mounted) setState(() => _previewing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // モード ON/OFF
          StreamBuilder<bool>(
            stream: _service.watchIsActive(),
            builder: (context, snap) {
              final active = snap.data ?? false;
              return _card(
                child: SwitchListTile(
                  value: active,
                  onChanged: _busy ? null : _toggleActive,
                  activeThumbColor: AppColors.accentBlue,
                  title: const Text('Milfolha モード',
                      style: TextStyle(
                          color: Colors.white, fontWeight: FontWeight.w700)),
                  subtitle: Text(
                    active ? '開催中（参加者にセクション表示）' : '停止中',
                    style: const TextStyle(color: Color(0xFF9E9E9E)),
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 12),
          // 結果確定
          StreamBuilder<bool>(
            stream: _service.watchResultFinalized(),
            builder: (context, snap) {
              final finalized = snap.data ?? false;
              return _card(
                child: SwitchListTile(
                  value: finalized,
                  onChanged: _busy ? null : _toggleFinalized,
                  activeThumbColor: const Color(0xFFFFD700),
                  title: const Text('結果を確定（最終結果表示）',
                      style: TextStyle(
                          color: Colors.white, fontWeight: FontWeight.w700)),
                ),
              );
            },
          ),
          const SizedBox(height: 12),
          // 期間表示
          FutureBuilder<MilfolhaPeriods>(
            future: _service.getPeriods(),
            builder: (context, snap) {
              final p = snap.data;
              String fmt(DateTime? d) {
                if (d == null) return '-';
                final j = d.toUtc().add(const Duration(hours: 9));
                return '${j.month}/${j.day} ${j.hour.toString().padLeft(2, '0')}:${j.minute.toString().padLeft(2, '0')} (JST)';
              }

              return _card(
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('集計期間',
                          style: TextStyle(
                              color: Color(0xFF9E9E9E), fontSize: 12)),
                      const SizedBox(height: 6),
                      Text('${fmt(p?.start)}  〜  ${fmt(p?.end)}',
                          style: const TextStyle(
                              color: Colors.white, fontSize: 14)),
                      const SizedBox(height: 4),
                      const Text('（既定 8/30 0:00〜8/31 23:59 JST）',
                          style: TextStyle(
                              color: Color(0xFF6B6B6B), fontSize: 11)),
                    ],
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 12),
          // チームコード一覧
          _card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('チームコード',
                      style:
                          TextStyle(color: Color(0xFF9E9E9E), fontSize: 12)),
                  const SizedBox(height: 8),
                  for (final t in MilfolhaTeamDefinitions.all)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: Text('チーム ${t.displayName}:  ${t.id}',
                          style: const TextStyle(
                              color: Colors.white, fontSize: 13)),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          // 集計プレビュー
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _previewing ? null : _runPreview,
              icon: const Icon(Icons.calculate),
              label: Text(_previewing ? '集計中...' : '集計をプレビュー'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.accentBlue,
                foregroundColor: Colors.white,
              ),
            ),
          ),
          if (_preview != null) ...[
            const SizedBox(height: 12),
            for (int i = 0; i < _preview!.length; i++)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Text(
                  '${i + 1}位  チーム ${_preview![i].displayName}   ${_preview![i].total}pt'
                  '  (登録${_preview![i].regPt}/投稿${_preview![i].memberPostPt}'
                  '/外部登録${_preview![i].extRegPt}/外部投稿${_preview![i].extPostPt})',
                  style: const TextStyle(color: Colors.white, fontSize: 13),
                ),
              ),
          ],
        ],
      ),
    );
  }

  Widget _card({required Widget child}) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1C1C1E),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF2C2C2E)),
      ),
      child: child,
    );
  }
}

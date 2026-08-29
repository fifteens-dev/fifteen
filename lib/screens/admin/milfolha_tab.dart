import 'package:flutter/material.dart';
import '../../constants/app_colors.dart';
import '../../constants/milfolha_teams.dart';
import '../../models/milfolha_team_score.dart';
import '../../services/milfolha_service.dart';
import '../../widgets/common/app_toast.dart';

/// 管理者パネル: WATERFALLS イベント管理タブ。
/// モード ON/OFF、期間表示、ランキング非公開ウィンドウ、結果確定、
/// 集計プレビュー、チームコード一覧。
class MilfolhaTab extends StatefulWidget {
  const MilfolhaTab({super.key});

  @override
  State<MilfolhaTab> createState() => _MilfolhaTabState();
}

class _MilfolhaTabState extends State<MilfolhaTab> {
  static const Color _purple = Color(0xFF7B6FE6);

  final _service = MilfolhaService();
  bool _busy = false;
  List<MilfolhaTeamScore>? _preview;
  bool _previewing = false;

  Future<void> _toggleActive(bool v) async {
    setState(() => _busy = true);
    await _service.setActive(v);
    if (mounted) setState(() => _busy = false);
    if (mounted) {
      AppToast.show(context, v ? 'WATERFALLS を開始しました' : 'WATERFALLS を停止しました');
    }
  }

  Future<void> _toggleFinalized(bool v) async {
    setState(() => _busy = true);
    await _service.setResultFinalized(v);
    if (mounted) setState(() => _busy = false);
  }

  // ---- ランキング非公開ウィンドウ ----

  Future<void> _toggleBlackout(bool v) async {
    setState(() => _busy = true);
    await _service.setBlackout(enabled: v);
    if (mounted) setState(() => _busy = false);
    if (mounted) {
      AppToast.show(
          context, v ? '非公開ウィンドウを有効にしました' : 'ランキングを公開しました');
    }
  }

  /// 非公開の開始 / 終了時刻を選ぶ。ピッカーは端末ローカル時刻で操作し、
  /// JST 相当の DateTime に組み立て直して保存する。
  Future<void> _pickBlackoutTime({
    required bool isStart,
    required MilfolhaBlackout current,
  }) async {
    final base = (isStart ? current.start : current.end)
        .toUtc()
        .add(const Duration(hours: 9));

    final date = await showDatePicker(
      context: context,
      initialDate: DateTime(base.year, base.month, base.day),
      firstDate: DateTime(2026, 1, 1),
      lastDate: DateTime(2027, 12, 31),
    );
    if (date == null || !mounted) return;

    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: base.hour, minute: base.minute),
    );
    if (time == null || !mounted) return;

    // 選んだ「JST の壁時計時刻」を UTC 基準の DateTime に戻す。
    final jstWall = DateTime.utc(
        date.year, date.month, date.day, time.hour, time.minute);
    final picked = jstWall.subtract(const Duration(hours: 9));

    setState(() => _busy = true);
    await _service.setBlackout(
      start: isStart ? picked : null,
      end: isStart ? null : picked,
    );
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _runPreview() async {
    setState(() => _previewing = true);
    try {
      final scores = await _service.computeTeamRanking();
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
                  title: const Text('WATERFALLS モード',
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
                      const Text('（既定 8/30 0:00〜8/31 21:20 JST）',
                          style: TextStyle(
                              color: Color(0xFF6B6B6B), fontSize: 11)),
                    ],
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 12),
          // ランキング非公開ウィンドウ
          StreamBuilder<MilfolhaBlackout>(
            stream: _service.watchBlackout(),
            builder: (context, snap) {
              final b = snap.data;
              if (b == null) {
                return _card(
                  child: const Padding(
                    padding: EdgeInsets.all(14),
                    child: Text('ランキング非公開: 読み込み中...',
                        style: TextStyle(
                            color: Color(0xFF9E9E9E), fontSize: 12)),
                  ),
                );
              }
              String fmtJst(DateTime d) {
                final j = d.toUtc().add(const Duration(hours: 9));
                return '${j.month}/${j.day} '
                    '${j.hour.toString().padLeft(2, '0')}:'
                    '${j.minute.toString().padLeft(2, '0')} (JST)';
              }

              final hiddenNow = b.isHiddenAt(DateTime.now());
              return _card(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SwitchListTile(
                      value: b.enabled,
                      onChanged: _busy ? null : _toggleBlackout,
                      activeThumbColor: _purple,
                      title: const Text('ランキングを非公開にする',
                          style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w700)),
                      subtitle: Text(
                        !b.enabled
                            ? '無効（常に公開）'
                            : hiddenNow
                                ? '現在 非公開中'
                                : '有効（ウィンドウ外なので現在は公開中）',
                        style: TextStyle(
                          color: hiddenNow
                              ? const Color(0xFFFF6B6B)
                              : const Color(0xFF9E9E9E),
                        ),
                      ),
                    ),
                    const Divider(height: 1, color: Color(0xFF2C2C2E)),
                    ListTile(
                      dense: true,
                      title: const Text('非公開 開始',
                          style: TextStyle(
                              color: Color(0xFF9E9E9E), fontSize: 12)),
                      subtitle: Text(fmtJst(b.start),
                          style: const TextStyle(
                              color: Colors.white, fontSize: 14)),
                      trailing: const Icon(Icons.edit,
                          color: Color(0xFF9E9E9E), size: 18),
                      onTap: _busy
                          ? null
                          : () =>
                              _pickBlackoutTime(isStart: true, current: b),
                    ),
                    ListTile(
                      dense: true,
                      title: const Text('公開（非公開 終了）',
                          style: TextStyle(
                              color: Color(0xFF9E9E9E), fontSize: 12)),
                      subtitle: Text(fmtJst(b.end),
                          style: const TextStyle(
                              color: Colors.white, fontSize: 14)),
                      trailing: const Icon(Icons.edit,
                          color: Color(0xFF9E9E9E), size: 18),
                      onTap: _busy
                          ? null
                          : () =>
                              _pickBlackoutTime(isStart: false, current: b),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            '非公開中もポイントの加算・集計は通常どおり続きます。'
                            '止まるのはユーザー側ランキング画面の表示だけです。',
                            style: TextStyle(
                                color: Color(0xFF6B6B6B),
                                fontSize: 11,
                                height: 1.5),
                          ),
                          if (hiddenNow) ...[
                            const SizedBox(height: 10),
                            SizedBox(
                              width: double.infinity,
                              child: OutlinedButton.icon(
                                onPressed: _busy
                                    ? null
                                    : () => _toggleBlackout(false),
                                icon: const Icon(Icons.lock_open, size: 18),
                                label: const Text('今すぐ公開する'),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: Colors.white,
                                  side: const BorderSide(
                                      color: Color(0xFF3A3A3C)),
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
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

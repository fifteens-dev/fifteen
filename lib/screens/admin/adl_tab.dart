import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../constants/app_colors.dart';
import '../../models/adl_periods.dart';
import '../../models/adl_team_model.dart';
import '../../services/adl_service.dart';
import '../../widgets/common/app_toast.dart';
import '../adl_team_playlist_screen.dart';

/// 管理パネル ADLイベントタブ
///
/// ADLイベントは1回限りの運用のため、ON/OFFトグルのみのシンプル構成にしてある。
/// 9つの固定班（adl_house ほか）は seed_adl_teams.js で事前作成済み。
class AdlTab extends StatefulWidget {
  const AdlTab({super.key});

  @override
  State<AdlTab> createState() => _AdlTabState();
}

class _AdlTabState extends State<AdlTab> {
  final _adl = AdlService();

  bool _adlActive = false;
  bool _loading = true;
  bool _toggleBusy = false;
  bool _recomputing = false;
  bool _recomputingMembers = false;
  bool _creatingDummy = false;
  bool _cleaningDummy = false;
  bool _creatingAuth = false;
  bool _cleaningAuth = false;
  bool _settingFollows = false;
  bool _clearingFollows = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final active = await _adl.isAdlModeActive();
    if (mounted) {
      setState(() {
        _adlActive = active;
        _loading = false;
      });
    }
  }

  Future<void> _toggleAdlMode(bool value) async {
    setState(() => _toggleBusy = true);
    await _adl.setAdlMode(value);
    if (!mounted) return;
    setState(() {
      _adlActive = value;
      _toggleBusy = false;
    });
    AppToast.show(context, value ? 'ADLモードをONにしました' : 'ADLモードをOFFにしました');
  }

  Future<void> _createBulkDummy() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surfaceLight,
        title: const Text('ダミーユーザーを600人作成しますか？',
            style: TextStyle(color: Colors.white, fontSize: 16)),
        content: const Text(
          '9班に均等配分（各66〜67人）のダミーユーザーをFirestoreに作成します。\n'
          '毎日投稿スケジュールの対象にも追加されます。\n\n'
          'プレテスト後は必ずクリーンアップを実行してください。',
          style: TextStyle(color: Colors.grey, fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('キャンセル', style: TextStyle(color: Colors.grey)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('作成', style: TextStyle(color: AppColors.accentBlue)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _creatingDummy = true);
    try {
      final result = await _adl.createBulkDummyUsers(count: 600);
      if (!mounted) return;
      final count = result['createdCount'] ?? 0;
      AppToast.show(context, '$count人のダミーユーザーを作成しました');
    } catch (e) {
      if (!mounted) return;
      AppToast.show(context, '作成に失敗しました: $e');
    } finally {
      if (mounted) setState(() => _creatingDummy = false);
    }
  }

  Future<void> _cleanupBulkDummy() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surfaceLight,
        title: const Text('ダミーユーザーを全削除しますか？',
            style: TextStyle(color: Colors.white, fontSize: 16)),
        content: const Text(
          'createBulkDummyUsers で作成したダミーユーザーとその投稿を全削除します。\n'
          '元の10人のダミーユーザーは削除されません。',
          style: TextStyle(color: Colors.grey, fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('キャンセル', style: TextStyle(color: Colors.grey)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('削除', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _cleaningDummy = true);
    try {
      final result = await _adl.cleanupBulkDummyUsers();
      if (!mounted) return;
      final users = result['deletedUsers'] ?? 0;
      final posts = result['deletedPosts'] ?? 0;
      AppToast.show(context, 'ユーザー$users人・投稿$posts件を削除しました');
    } catch (e) {
      if (!mounted) return;
      AppToast.show(context, 'クリーンアップに失敗しました: $e');
    } finally {
      if (mounted) setState(() => _cleaningDummy = false);
    }
  }

  Future<void> _createBulkAuth() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surfaceLight,
        title: const Text('Authアカウントを作成しますか？',
            style: TextStyle(color: Colors.white, fontSize: 16)),
        content: const Text(
          '600人のダミーユーザー全員にFirebase Authアカウント（メール+共通PW）を付与します。\n'
          '負荷テストの同時ログインシナリオ用です。\n\n'
          '所要時間: 約30秒〜1分',
          style: TextStyle(color: Colors.grey, fontSize: 13),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('キャンセル', style: TextStyle(color: Colors.grey))),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('作成', style: TextStyle(color: AppColors.accentBlue))),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _creatingAuth = true);
    try {
      final result = await _adl.createBulkDummyAuthAccounts();
      if (!mounted) return;
      final c = result['created'] ?? 0;
      final s = result['skipped'] ?? 0;
      final f = result['failed'] ?? 0;
      AppToast.show(context, 'Auth: 作成$c / 既存$s / 失敗$f');
    } catch (e) {
      if (!mounted) return;
      AppToast.show(context, 'Auth作成に失敗: $e');
    } finally {
      if (mounted) setState(() => _creatingAuth = false);
    }
  }

  Future<void> _cleanupBulkAuth() async {
    setState(() => _cleaningAuth = true);
    try {
      final result = await _adl.cleanupBulkDummyAuthAccounts();
      if (!mounted) return;
      final d = result['deleted'] ?? 0;
      AppToast.show(context, 'Auth $d件を削除しました');
    } catch (e) {
      if (!mounted) return;
      AppToast.show(context, 'Auth削除に失敗: $e');
    } finally {
      if (mounted) setState(() => _cleaningAuth = false);
    }
  }

  Future<void> _setupTestFollows() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surfaceLight,
        title: const Text('テストフォローを設定しますか？',
            style: TextStyle(color: Colors.white, fontSize: 16)),
        content: const Text(
          'あなたのアカウントが600人のダミーを双方向フォローします。\n'
          '負荷テスト中に通知が大量に届く・タイムラインに600投稿が流れる状態を再現します。\n\n'
          'プレテスト中の通知暴発検証・実機表示確認用。',
          style: TextStyle(color: Colors.grey, fontSize: 13),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('キャンセル', style: TextStyle(color: Colors.grey))),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('設定', style: TextStyle(color: AppColors.accentBlue))),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _settingFollows = true);
    try {
      final result = await _adl.setupTestFollows(bidirectional: true);
      if (!mounted) return;
      final n = result['followedCount'] ?? 0;
      AppToast.show(context, '$n人を双方向フォローしました');
    } catch (e) {
      if (!mounted) return;
      AppToast.show(context, 'フォロー設定に失敗: $e');
    } finally {
      if (mounted) setState(() => _settingFollows = false);
    }
  }

  Future<void> _clearTestFollows() async {
    setState(() => _clearingFollows = true);
    try {
      final result = await _adl.cleanupTestFollows();
      if (!mounted) return;
      final n = result['unfollowed'] ?? 0;
      AppToast.show(context, '$n人のフォローを解除しました');
    } catch (e) {
      if (!mounted) return;
      AppToast.show(context, 'フォロー解除に失敗: $e');
    } finally {
      if (mounted) setState(() => _clearingFollows = false);
    }
  }

  Future<void> _recompute() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surfaceLight,
        title: const Text('集計を再計算しますか？',
            style: TextStyle(color: Colors.white, fontSize: 16)),
        content: const Text(
          '全投稿を走査して各班の likeCount / postCount を再計算します。\n'
          'ドリフトしている場合の修正用です。',
          style: TextStyle(color: Colors.grey, fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('キャンセル',
                style: TextStyle(color: Colors.grey)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('実行',
                style: TextStyle(color: AppColors.accentBlue)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _recomputing = true);
    try {
      final totals = await _adl.recomputeLikeCounts();
      if (!mounted) return;
      final teamCount = totals.length;
      AppToast.show(context, '$teamCount班の集計を再計算しました');
    } catch (e) {
      if (!mounted) return;
      AppToast.show(context, '再集計に失敗しました: $e');
    } finally {
      if (mounted) setState(() => _recomputing = false);
    }
  }

  Future<void> _recomputeMembers() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surfaceLight,
        title: const Text('班員数を再集計しますか？',
            style: TextStyle(color: Colors.white, fontSize: 16)),
        content: const Text(
          'users.adlTeamId を全走査して各班の memberCount を実態に合わせます。\n'
          'ダミー削除・直接削除等でカウンターがズレた場合の修正用です。',
          style: TextStyle(color: Colors.grey, fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('キャンセル',
                style: TextStyle(color: Colors.grey)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('実行',
                style: TextStyle(color: AppColors.accentBlue)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _recomputingMembers = true);
    try {
      final counts = await _adl.recomputeMemberCounts();
      if (!mounted) return;
      final total = counts.values.fold<int>(0, (a, b) => a + b);
      AppToast.show(context, '班員数を再集計: 合計 $total人');
    } catch (e) {
      if (!mounted) return;
      AppToast.show(context, '班員数の再集計に失敗しました: $e');
    } finally {
      if (mounted) setState(() => _recomputingMembers = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(
          child: CupertinoActivityIndicator(color: Colors.white));
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // ── ADLモードトグル ──
        _Section(
          title: 'ADLモード',
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _adlActive ? 'ON（開催中）' : 'OFF',
                    style: TextStyle(
                      color: _adlActive ? AppColors.success : Colors.grey,
                      fontWeight: FontWeight.w600,
                      fontSize: 15,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _adlActive
                        ? '参加者が設定画面から班に参加できます'
                        : 'ONにすると参加者が班コードで参加可能になります',
                    style: const TextStyle(color: Colors.grey, fontSize: 11),
                  ),
                ],
              ),
              _toggleBusy
                  ? const SizedBox(
                      width: 28,
                      height: 28,
                      child: CupertinoActivityIndicator(color: Colors.white),
                    )
                  : CupertinoSwitch(
                      value: _adlActive,
                      activeTrackColor: AppColors.success,
                      onChanged: _toggleAdlMode,
                    ),
            ],
          ),
        ),

        const SizedBox(height: 16),

        // ── 期間設定 ──
        const _PeriodsSection(),

        const SizedBox(height: 16),

        // ── 結果確定 ──
        const _ResultFinalizeSection(),

        const SizedBox(height: 16),

        // ── プレテスト用ダミーユーザー ──
        _Section(
          title: 'プレテスト（負荷テスト）',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '手順: ①ユーザー作成 → ②Auth作成 → ③フォロー設定 → 負荷テスト実行\n'
                '「全削除」はAuth・フォローも連鎖クリーンアップ',
                style: TextStyle(color: Colors.grey, fontSize: 11),
              ),
              const SizedBox(height: 12),

              // ① ダミーユーザー（Firestore）
              const Text('① ダミーユーザー (Firestore 600人)',
                  style: TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w600)),
              const SizedBox(height: 6),
              _PreTestButtonRow(
                left: _PreTestButton(
                  busy: _creatingDummy,
                  onPressed: _createBulkDummy,
                  icon: Icons.group_add,
                  label: '600人作成',
                  color: AppColors.accentBlue,
                ),
                right: _PreTestButton(
                  busy: _cleaningDummy,
                  onPressed: _cleanupBulkDummy,
                  icon: Icons.delete_sweep,
                  label: '全削除',
                  color: Colors.red,
                ),
              ),

              const SizedBox(height: 12),

              // ② Auth アカウント
              const Text('② Firebase Auth アカウント',
                  style: TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w600)),
              const SizedBox(height: 6),
              _PreTestButtonRow(
                left: _PreTestButton(
                  busy: _creatingAuth,
                  onPressed: _createBulkAuth,
                  icon: Icons.lock_open,
                  label: 'Auth作成',
                  color: AppColors.accentBlue,
                ),
                right: _PreTestButton(
                  busy: _cleaningAuth,
                  onPressed: _cleanupBulkAuth,
                  icon: Icons.lock_outline,
                  label: 'Auth削除',
                  color: Colors.red,
                ),
              ),

              const SizedBox(height: 12),

              // ③ テストフォロー
              const Text('③ テストフォロー (自分↔全ダミー)',
                  style: TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w600)),
              const SizedBox(height: 6),
              _PreTestButtonRow(
                left: _PreTestButton(
                  busy: _settingFollows,
                  onPressed: _setupTestFollows,
                  icon: Icons.people_alt,
                  label: 'フォロー設定',
                  color: AppColors.accentBlue,
                ),
                right: _PreTestButton(
                  busy: _clearingFollows,
                  onPressed: _clearTestFollows,
                  icon: Icons.person_remove,
                  label: 'フォロー解除',
                  color: Colors.red,
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 16),

        // ── 9班ストリーム（サマリと班一覧を共有） ──
        StreamBuilder<List<AdlTeamModel>>(
          stream: _adl.watchFixedTeams(),
          builder: (ctx, snap) {
            if (!snap.hasData) {
              return const _Section(
                title: '集計',
                child: Center(
                  child: CupertinoActivityIndicator(color: Colors.white),
                ),
              );
            }
            final teams = snap.data!;
            if (teams.isEmpty) {
              return const _Section(
                title: '集計',
                child: Text(
                  '班データがありません。scripts/seed_adl_teams.js を実行してください',
                  style: TextStyle(color: Colors.grey, fontSize: 13),
                ),
              );
            }
            return Column(
              children: [
                _SummaryCard(teams: teams),
                const SizedBox(height: 16),
                _Section(
                  title: 'チーム賞 / 班ランキング',
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _recomputingMembers
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CupertinoActivityIndicator(
                                  color: Colors.white),
                            )
                          : TextButton.icon(
                              onPressed: _recomputeMembers,
                              icon: const Icon(Icons.groups_outlined,
                                  size: 16, color: AppColors.accentBlue),
                              label: const Text('班員再集計',
                                  style: TextStyle(
                                      color: AppColors.accentBlue,
                                      fontSize: 12)),
                              style: TextButton.styleFrom(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 4),
                                minimumSize: const Size(0, 28),
                              ),
                            ),
                      const SizedBox(width: 4),
                      _recomputing
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CupertinoActivityIndicator(
                                  color: Colors.white),
                            )
                          : TextButton.icon(
                              onPressed: _recompute,
                              icon: const Icon(Icons.refresh,
                                  size: 16, color: AppColors.accentBlue),
                              label: const Text('再集計',
                                  style: TextStyle(
                                      color: AppColors.accentBlue,
                                      fontSize: 12)),
                              style: TextButton.styleFrom(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 4),
                                minimumSize: const Size(0, 28),
                              ),
                            ),
                    ],
                  ),
                  child: Column(
                    children: teams.asMap().entries.map((entry) {
                      return _TeamTile(
                        rank: entry.key + 1,
                        team: entry.value,
                      );
                    }).toList(),
                  ),
                ),
                const SizedBox(height: 16),
                const _InviteRankingSection(),
              ],
            );
          },
        ),
      ],
    );
  }
}

// ---- 期間設定 ----

class _PeriodsSection extends StatefulWidget {
  const _PeriodsSection();

  @override
  State<_PeriodsSection> createState() => _PeriodsSectionState();
}

class _PeriodsSectionState extends State<_PeriodsSection> {
  final _adl = AdlService();
  AdlPeriods? _periods;
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final p = await _adl.getAdlPeriods();
    if (mounted) {
      setState(() {
        _periods = p;
        _loading = false;
      });
    }
  }

  Future<void> _pickDate(
      DateTime? current, void Function(DateTime) onPicked) async {
    final initial = current ?? DateTime.now();
    // ADL本番は 2026/6 想定だが、運用上は前後1年の範囲で十分
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(initial.year - 1),
      lastDate: DateTime(initial.year + 1),
      builder: (ctx, child) {
        return Theme(
          data: ThemeData.dark().copyWith(
            colorScheme: const ColorScheme.dark(
              primary: AppColors.accentBlue,
              surface: AppColors.surfaceLight,
              onSurface: Colors.white,
            ),
          ),
          child: child!,
        );
      },
    );
    if (picked == null) return;
    onPicked(picked);
  }

  Future<void> _save() async {
    if (_periods == null) return;
    setState(() => _saving = true);
    try {
      await _adl.setAdlPeriods(_periods!);
      if (!mounted) return;
      AppToast.show(context, '期間設定を保存しました');
    } catch (e) {
      if (!mounted) return;
      AppToast.show(context, '保存に失敗しました: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return _Section(
      title: '期間設定',
      trailing: _saving
          ? const SizedBox(
              width: 18,
              height: 18,
              child: CupertinoActivityIndicator(color: Colors.white),
            )
          : TextButton.icon(
              onPressed: _periods == null ? null : _save,
              icon: const Icon(Icons.save,
                  size: 16, color: AppColors.accentBlue),
              label: const Text('保存',
                  style: TextStyle(
                      color: AppColors.accentBlue, fontSize: 12)),
              style: TextButton.styleFrom(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                minimumSize: const Size(0, 28),
              ),
            ),
      child: _loading
          ? const SizedBox(
              height: 80,
              child: Center(
                  child: CupertinoActivityIndicator(color: Colors.white)),
            )
          : Column(
              children: [
                _DateRow(
                  label: 'チーム賞 開始',
                  hint: '例: 6/10 0:00',
                  value: _periods!.teamRankingStart,
                  onTap: () => _pickDate(_periods!.teamRankingStart, (d) {
                    setState(() => _periods =
                        _periods!.copyWith(teamRankingStart: d));
                  }),
                ),
                _DateRow(
                  label: 'チーム賞 終了',
                  hint: '例: 6/20 23:59',
                  value: _periods!.teamRankingEnd,
                  onTap: () => _pickDate(_periods!.teamRankingEnd, (d) {
                    // 終了日は1日の終わりに合わせる
                    final end = DateTime(d.year, d.month, d.day, 23, 59, 59);
                    setState(() =>
                        _periods = _periods!.copyWith(teamRankingEnd: end));
                  }),
                ),
                _DateRow(
                  label: '個人賞 開始',
                  hint: '例: 6/10 0:00',
                  value: _periods!.inviteRankingStart,
                  onTap: () => _pickDate(_periods!.inviteRankingStart, (d) {
                    setState(() => _periods =
                        _periods!.copyWith(inviteRankingStart: d));
                  }),
                ),
                _DateRow(
                  label: '個人賞 終了',
                  hint: '例: 6/24 23:59',
                  value: _periods!.inviteRankingEnd,
                  onTap: () => _pickDate(_periods!.inviteRankingEnd, (d) {
                    final end = DateTime(d.year, d.month, d.day, 23, 59, 59);
                    setState(() => _periods =
                        _periods!.copyWith(inviteRankingEnd: end));
                  }),
                ),
                _DateRow(
                  label: '結果連絡日',
                  hint: '例: 6/27',
                  value: _periods!.resultAnnouncementDate,
                  onTap: () =>
                      _pickDate(_periods!.resultAnnouncementDate, (d) {
                    setState(() => _periods =
                        _periods!.copyWith(resultAnnouncementDate: d));
                  }),
                ),
                _DateRow(
                  label: '最終発表日',
                  hint: '例: 6/28',
                  value: _periods!.finalAnnouncementDate,
                  onTap: () =>
                      _pickDate(_periods!.finalAnnouncementDate, (d) {
                    setState(() => _periods =
                        _periods!.copyWith(finalAnnouncementDate: d));
                  }),
                ),
                const SizedBox(height: 4),
                const Text(
                  'チーム賞期間内に作成された投稿のいいねのみが集計対象になります。',
                  style: TextStyle(color: Colors.grey, fontSize: 11),
                ),
              ],
            ),
    );
  }
}

class _DateRow extends StatelessWidget {
  final String label;
  final String hint;
  final DateTime? value;
  final VoidCallback onTap;
  const _DateRow({
    required this.label,
    required this.hint,
    required this.value,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final hasValue = value != null;
    final text = hasValue
        ? '${value!.year}/${value!.month.toString().padLeft(2, '0')}/${value!.day.toString().padLeft(2, '0')} '
            '${value!.hour.toString().padLeft(2, '0')}:${value!.minute.toString().padLeft(2, '0')}'
        : hint;

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          children: [
            Expanded(
              flex: 3,
              child: Text(label,
                  style: const TextStyle(
                      color: Colors.white, fontSize: 13)),
            ),
            Expanded(
              flex: 5,
              child: Text(
                text,
                style: TextStyle(
                  color: hasValue ? Colors.white : Colors.grey,
                  fontSize: 13,
                  fontFamily: 'monospace',
                ),
              ),
            ),
            const Icon(Icons.edit_calendar,
                color: AppColors.accentBlue, size: 18),
          ],
        ),
      ),
    );
  }
}

// ---- 結果確定 ----

class _ResultFinalizeSection extends StatefulWidget {
  const _ResultFinalizeSection();

  @override
  State<_ResultFinalizeSection> createState() => _ResultFinalizeSectionState();
}

class _ResultFinalizeSectionState extends State<_ResultFinalizeSection> {
  final _adl = AdlService();
  bool _busy = false;

  Future<void> _toggle(bool currentlyFinalized) async {
    final finalize = !currentlyFinalized;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surfaceLight,
        title: Text(
          finalize ? '結果を確定しますか？' : '確定を解除しますか？',
          style: const TextStyle(color: Colors.white, fontSize: 16),
        ),
        content: Text(
          finalize
              ? '確定するとユーザー側ランキング画面が「最終結果」モードに切り替わり、'
                  '上位3位が強調表示されます。\n'
                  '計画書では 6/27 に確定する想定です。'
              : '確定を解除すると、ユーザー側ランキングは通常モードに戻ります。',
          style: const TextStyle(color: Colors.grey, fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child:
                const Text('キャンセル', style: TextStyle(color: Colors.grey)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              finalize ? '確定する' : '解除する',
              style: TextStyle(
                  color:
                      finalize ? AppColors.success : AppColors.accentBlue),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _busy = true);
    try {
      await _adl.setResultFinalized(finalize);
      if (!mounted) return;
      AppToast.show(context, finalize ? '結果を確定しました' : '確定を解除しました');
    } catch (e) {
      if (!mounted) return;
      AppToast.show(context, '操作に失敗しました: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<bool>(
      stream: _adl.watchResultFinalized(),
      builder: (ctx, snap) {
        final finalized = snap.data == true;
        return _Section(
          title: '結果確定',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    finalized ? Icons.emoji_events : Icons.lock_clock,
                    color: finalized
                        ? const Color(0xFFFFD700)
                        : Colors.grey,
                    size: 22,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      finalized ? '確定済み（最終結果モード）' : '未確定',
                      style: TextStyle(
                        color: finalized
                            ? const Color(0xFFFFD700)
                            : Colors.grey,
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                      ),
                    ),
                  ),
                  if (_busy)
                    const SizedBox(
                      width: 18,
                      height: 18,
                      child:
                          CupertinoActivityIndicator(color: Colors.white),
                    )
                  else
                    TextButton(
                      onPressed: () => _toggle(finalized),
                      style: TextButton.styleFrom(
                        backgroundColor: finalized
                            ? AppColors.surfaceLighter
                            : AppColors.success.withValues(alpha: 0.15),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 6),
                      ),
                      child: Text(
                        finalized ? '解除' : '結果を確定する',
                        style: TextStyle(
                          color: finalized
                              ? Colors.grey
                              : AppColors.success,
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                finalized
                    ? 'ユーザー側ランキング画面に「最終結果」バナーと冠演出が表示されています。'
                    : '6/27（結果連絡日）に確定すると、ユーザー側で最終結果として表示されます。',
                style:
                    const TextStyle(color: Colors.grey, fontSize: 11),
              ),
            ],
          ),
        );
      },
    );
  }
}

// ---- 個人賞（招待人数）ランキング ----

class _InviteRankingSection extends StatefulWidget {
  const _InviteRankingSection();

  @override
  State<_InviteRankingSection> createState() => _InviteRankingSectionState();
}

class _InviteRankingSectionState extends State<_InviteRankingSection> {
  final _adl = AdlService();
  late Future<List<InviteRankingEntry>> _future;

  @override
  void initState() {
    super.initState();
    _future = _fetch();
  }

  Future<List<InviteRankingEntry>> _fetch() async {
    final periods = await _adl.getAdlPeriods();
    return _adl.getInviteRanking(
      from: periods.inviteRankingStart,
      to: periods.inviteRankingEnd,
      limit: 20,
    );
  }

  Future<void> _reload() async {
    setState(() {
      _future = _fetch();
    });
    await _future;
  }

  @override
  Widget build(BuildContext context) {
    return _Section(
      title: '個人賞 / 招待人数ランキング',
      trailing: TextButton.icon(
        onPressed: _reload,
        icon: const Icon(Icons.refresh,
            size: 16, color: AppColors.accentBlue),
        label: const Text('更新',
            style:
                TextStyle(color: AppColors.accentBlue, fontSize: 12)),
        style: TextButton.styleFrom(
          padding:
              const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          minimumSize: const Size(0, 28),
        ),
      ),
      child: FutureBuilder<List<InviteRankingEntry>>(
        future: _future,
        builder: (ctx, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const SizedBox(
              height: 80,
              child: Center(
                  child: CupertinoActivityIndicator(color: Colors.white)),
            );
          }
          if (snap.hasError) {
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Text('読み込みに失敗しました: ${snap.error}',
                  style: const TextStyle(color: Colors.red, fontSize: 12)),
            );
          }
          final entries = snap.data ?? const <InviteRankingEntry>[];
          if (entries.isEmpty) {
            return const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Text('招待実績がまだありません',
                  style: TextStyle(color: Colors.grey, fontSize: 13)),
            );
          }
          return Column(
            children: entries
                .asMap()
                .entries
                .map((e) => _InviteRankTile(rank: e.key + 1, entry: e.value))
                .toList(),
          );
        },
      ),
    );
  }
}

class _InviteRankTile extends StatelessWidget {
  final int rank;
  final InviteRankingEntry entry;
  const _InviteRankTile({required this.rank, required this.entry});

  @override
  Widget build(BuildContext context) {
    final rankColors = [
      const Color(0xFFFFD700),
      const Color(0xFFC0C0C0),
      const Color(0xFFCD7F32),
    ];
    final rankColor = rank <= 3 ? rankColors[rank - 1] : Colors.grey;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.surfaceLighter,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 28,
            child: Text(
              '$rank',
              style: TextStyle(
                  color: rankColor,
                  fontWeight: FontWeight.w800,
                  fontSize: 16),
            ),
          ),
          _AdminAvatar(
              profileImageUrl: entry.profileImageUrl,
              displayName: entry.displayName),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  entry.displayName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                      fontSize: 14),
                ),
                if (entry.username.isNotEmpty)
                  Text('@${entry.username}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          color: Colors.grey, fontSize: 11)),
              ],
            ),
          ),
          Column(
            children: [
              Text(
                '${entry.inviteCount}',
                style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 18),
              ),
              const Text('招待',
                  style: TextStyle(color: Colors.grey, fontSize: 10)),
            ],
          ),
        ],
      ),
    );
  }
}

class _AdminAvatar extends StatelessWidget {
  final String? profileImageUrl;
  final String displayName;
  const _AdminAvatar(
      {required this.profileImageUrl, required this.displayName});

  @override
  Widget build(BuildContext context) {
    final hasUrl = profileImageUrl != null && profileImageUrl!.isNotEmpty;
    return Container(
      width: 32,
      height: 32,
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        color: AppColors.surfaceLight,
      ),
      clipBehavior: Clip.antiAlias,
      child: hasUrl
          ? CachedNetworkImage(
              imageUrl: profileImageUrl!,
              fit: BoxFit.cover,
              errorWidget: (_, __, ___) => _placeholder(),
            )
          : _placeholder(),
    );
  }

  Widget _placeholder() {
    final initial =
        displayName.isNotEmpty ? displayName[0].toUpperCase() : '?';
    return Center(
      child: Text(initial,
          style: const TextStyle(
              color: Colors.white,
              fontSize: 13,
              fontWeight: FontWeight.bold)),
    );
  }
}

// ---- プレテストボタン共通ウィジェット ----

class _PreTestButtonRow extends StatelessWidget {
  final Widget left;
  final Widget right;
  const _PreTestButtonRow({required this.left, required this.right});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(child: left),
        const SizedBox(width: 8),
        Expanded(child: right),
      ],
    );
  }
}

class _PreTestButton extends StatelessWidget {
  final bool busy;
  final VoidCallback onPressed;
  final IconData icon;
  final String label;
  final Color color;

  const _PreTestButton({
    required this.busy,
    required this.onPressed,
    required this.icon,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    if (busy) {
      return const Center(
        child: SizedBox(
          width: 22,
          height: 22,
          child: CupertinoActivityIndicator(color: Colors.white),
        ),
      );
    }
    return OutlinedButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 16, color: color),
      label: Text(label, style: TextStyle(color: color, fontSize: 13)),
      style: OutlinedButton.styleFrom(
        side: BorderSide(color: color),
        padding: const EdgeInsets.symmetric(vertical: 10),
      ),
    );
  }
}

// ---- サブウィジェット ----

class _Section extends StatelessWidget {
  final String title;
  final Widget child;
  final Widget? trailing;

  const _Section({required this.title, required this.child, this.trailing});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surfaceLight,
        borderRadius: BorderRadius.circular(12),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(title,
                  style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 14)),
              if (trailing != null) trailing!,
            ],
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  final List<AdlTeamModel> teams;

  const _SummaryCard({required this.teams});

  @override
  Widget build(BuildContext context) {
    int totalMembers = 0;
    int totalPosts = 0;
    int totalLikes = 0;
    for (final t in teams) {
      totalMembers += t.memberCount;
      totalPosts += t.postCount;
      totalLikes += t.likeCount;
    }

    return Container(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF1937EF), Color(0xFFFE1F56)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(12),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '全体サマリ',
            style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
                fontSize: 14),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _SummaryStat(label: '投稿', value: totalPosts),
              _SummaryStat(label: 'メンバー', value: totalMembers),
              _SummaryStat(label: 'いいね', value: totalLikes),
            ],
          ),
        ],
      ),
    );
  }
}

class _SummaryStat extends StatelessWidget {
  final String label;
  final int value;

  const _SummaryStat({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          '$value',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 24,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: const TextStyle(color: Colors.white70, fontSize: 11),
        ),
      ],
    );
  }
}

class _TeamTile extends StatelessWidget {
  final int rank;
  final AdlTeamModel team;

  const _TeamTile({required this.rank, required this.team});

  @override
  Widget build(BuildContext context) {
    final rankColors = [
      const Color(0xFFFFD700), // gold
      const Color(0xFFC0C0C0), // silver
      const Color(0xFFCD7F32), // bronze
    ];
    final rankColor = rank <= 3 ? rankColors[rank - 1] : Colors.grey;

    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => AdlTeamPlaylistScreen(teamId: team.teamId),
          ),
        );
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: AppColors.surfaceLighter,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            // 順位
            SizedBox(
              width: 28,
              child: Text(
                '$rank',
                style: TextStyle(
                    color: rankColor,
                    fontWeight: FontWeight.w800,
                    fontSize: 16),
              ),
            ),
            // 班名 + コード + 投稿数
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(team.name,
                      style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                          fontSize: 14)),
                  Row(
                    children: [
                      Text(
                        'コード: ${team.inviteCode}',
                        style: const TextStyle(
                            color: Colors.grey,
                            fontSize: 12,
                            fontFamily: 'monospace'),
                      ),
                      const SizedBox(width: 4),
                      GestureDetector(
                        onTap: () {
                          Clipboard.setData(
                              ClipboardData(text: team.inviteCode));
                          AppToast.show(context, 'コードをコピーしました');
                        },
                        child: const Icon(Icons.copy,
                            color: Colors.grey, size: 14),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      _MetaChip(
                          icon: Icons.people,
                          label: '${team.memberCount}人'),
                      const SizedBox(width: 8),
                      _MetaChip(
                          icon: Icons.photo_library_outlined,
                          label: '${team.postCount}件'),
                    ],
                  ),
                ],
              ),
            ),
            // いいね数
            Column(
              children: [
                Text(
                  '${team.likeCount}',
                  style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                      fontSize: 18),
                ),
                const Text('いいね',
                    style: TextStyle(color: Colors.grey, fontSize: 10)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _MetaChip extends StatelessWidget {
  final IconData icon;
  final String label;

  const _MetaChip({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: Colors.grey, size: 11),
        const SizedBox(width: 3),
        Text(label,
            style: const TextStyle(color: Colors.grey, fontSize: 11)),
      ],
    );
  }
}

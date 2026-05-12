import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../constants/app_colors.dart';
import '../../models/adl_event_model.dart';
import '../../models/adl_team_model.dart';
import '../../services/adl_service.dart';
import '../../widgets/common/app_toast.dart';

/// 管理パネル ADLイベントタブ
class AdlTab extends StatefulWidget {
  const AdlTab({super.key});

  @override
  State<AdlTab> createState() => _AdlTabState();
}

class _AdlTabState extends State<AdlTab> {
  final _adl = AdlService();

  bool _adlActive = false;
  AdlEventModel? _activeEvent;
  List<AdlEventModel> _events = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final [active, events] = await Future.wait([
      _adl.isAdlModeActive(),
      _adl.getEvents(),
    ]);
    final activeEvent = await _adl.getActiveEvent();
    if (mounted) {
      setState(() {
        _adlActive = active as bool;
        _events = events as List<AdlEventModel>;
        _activeEvent = activeEvent;
        _loading = false;
      });
    }
  }

  // ---- ADLモード切替 ----

  Future<void> _toggleAdlMode(bool value) async {
    if (value) {
      // アクティブにするにはイベントが必要
      if (_activeEvent == null) {
        AppToast.show(context, 'まずイベントを作成・選択してください');
        return;
      }
      await _adl.activateEvent(_activeEvent!.eventId);
    } else {
      await _adl.deactivateAdlMode();
    }
    await _load();
    if (mounted) {
      AppToast.show(context, value ? 'ADLモードをONにしました' : 'ADLモードをOFFにしました');
    }
  }

  // ---- イベント作成 ----

  Future<void> _showCreateEventDialog() async {
    final nameCtrl = TextEditingController();
    int durationHours = 4;

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          backgroundColor: AppColors.surfaceLight,
          title: const Text('新しいADLイベントを作成',
              style: TextStyle(color: Colors.white, fontSize: 16)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameCtrl,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(
                  labelText: 'イベント名',
                  labelStyle: TextStyle(color: Colors.grey),
                  enabledBorder: UnderlineInputBorder(
                      borderSide: BorderSide(color: Colors.grey)),
                  focusedBorder: UnderlineInputBorder(
                      borderSide: BorderSide(color: Colors.white)),
                ),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  const Text('招待コード有効時間: ',
                      style: TextStyle(color: Colors.grey, fontSize: 13)),
                  DropdownButton<int>(
                    value: durationHours,
                    dropdownColor: AppColors.surfaceLight,
                    style: const TextStyle(color: Colors.white),
                    items: [1, 2, 3, 4]
                        .map((h) => DropdownMenuItem(
                            value: h, child: Text('$h時間')))
                        .toList(),
                    onChanged: (v) =>
                        setDialogState(() => durationHours = v ?? 4),
                  ),
                ],
              ),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('キャンセル',
                    style: TextStyle(color: Colors.grey))),
            TextButton(
              onPressed: () async {
                if (nameCtrl.text.trim().isEmpty) return;
                Navigator.pop(ctx);
                final now = DateTime.now();
                final event = await _adl.createEvent(
                  name: nameCtrl.text.trim(),
                  startTime: now,
                  inviteCodeDuration: Duration(hours: durationHours),
                );
                await _load();
                if (mounted) {
                  AppToast.show(context,
                      'イベント「${event.name}」を作成しました');
                }
              },
              child: const Text('作成',
                  style: TextStyle(color: AppColors.accentBlue)),
            ),
          ],
        ),
      ),
    );
  }

  // ---- チーム作成 ----

  Future<void> _showCreateTeamDialog(AdlEventModel event) async {
    final nameCtrl = TextEditingController();

    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surfaceLight,
        title: const Text('班を追加',
            style: TextStyle(color: Colors.white, fontSize: 16)),
        content: TextField(
          controller: nameCtrl,
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(
            labelText: '班名（例: A班）',
            labelStyle: TextStyle(color: Colors.grey),
            enabledBorder: UnderlineInputBorder(
                borderSide: BorderSide(color: Colors.grey)),
            focusedBorder: UnderlineInputBorder(
                borderSide: BorderSide(color: Colors.white)),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('キャンセル',
                  style: TextStyle(color: Colors.grey))),
          TextButton(
            onPressed: () async {
              if (nameCtrl.text.trim().isEmpty) return;
              Navigator.pop(ctx);
              await _adl.createTeam(
                eventId: event.eventId,
                name: nameCtrl.text.trim(),
                inviteCodeExpiresAt: event.inviteCodeExpiresAt,
              );
              setState(() {}); // watchTeams が更新
              if (mounted) AppToast.show(context, '班を作成しました');
            },
            child: const Text('作成',
                style: TextStyle(color: AppColors.accentBlue)),
          ),
        ],
      ),
    );
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
        // ---- ADLモードスイッチ ----
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
                      color: _adlActive
                          ? AppColors.success
                          : Colors.grey,
                      fontWeight: FontWeight.w600,
                      fontSize: 15,
                    ),
                  ),
                  if (_activeEvent != null)
                    Text(
                      _activeEvent!.name,
                      style: const TextStyle(
                          color: Colors.grey, fontSize: 12),
                    ),
                ],
              ),
              CupertinoSwitch(
                value: _adlActive,
                activeTrackColor: AppColors.success,
                onChanged: _toggleAdlMode,
              ),
            ],
          ),
        ),

        const SizedBox(height: 16),

        // ---- イベント一覧 ----
        _Section(
          title: 'イベント',
          trailing: IconButton(
            icon: const Icon(Icons.add, color: AppColors.accentBlue),
            onPressed: _showCreateEventDialog,
          ),
          child: _events.isEmpty
              ? const Text('イベントがありません',
                  style: TextStyle(color: Colors.grey, fontSize: 13))
              : Column(
                  children: _events.map((e) => _EventTile(
                    event: e,
                    isSelected: _activeEvent?.eventId == e.eventId,
                    onSelect: () {
                      setState(() => _activeEvent = e);
                      AppToast.show(context, '「${e.name}」を選択しました');
                    },
                    onAddTeam: () => _showCreateTeamDialog(e),
                  )).toList(),
                ),
        ),

        const SizedBox(height: 16),

        // ---- 選択中イベントのチーム・ランキング ----
        if (_activeEvent != null) ...[
          _Section(
            title: '${_activeEvent!.name} — 班一覧 / ランキング',
            trailing: IconButton(
              icon: const Icon(Icons.group_add, color: AppColors.accentBlue),
              onPressed: () => _showCreateTeamDialog(_activeEvent!),
            ),
            child: StreamBuilder<List<AdlTeamModel>>(
              stream: _adl.watchTeams(_activeEvent!.eventId),
              builder: (ctx, snap) {
                if (!snap.hasData) {
                  return const Center(
                    child: CupertinoActivityIndicator(color: Colors.white),
                  );
                }
                final teams = snap.data!;
                if (teams.isEmpty) {
                  return const Text('班がありません',
                      style: TextStyle(color: Colors.grey, fontSize: 13));
                }
                return Column(
                  children: teams.asMap().entries.map((entry) {
                    return _TeamTile(
                      rank: entry.key + 1,
                      team: entry.value,
                      onRegenCode: () async {
                        await _adl.regenerateInviteCode(
                          entry.value.teamId,
                          _activeEvent!.inviteCodeExpiresAt,
                        );
                        if (mounted) {
                          AppToast.show(context, '招待コードを再発行しました');
                        }
                      },
                      onDelete: () async {
                        await _adl.deleteTeam(entry.value.teamId);
                        if (mounted) {
                          AppToast.show(context, '班を削除しました');
                        }
                      },
                    );
                  }).toList(),
                );
              },
            ),
          ),
        ],
      ],
    );
  }
}

// ---- サブウィジェット ----

class _Section extends StatelessWidget {
  final String title;
  final Widget child;
  final Widget? trailing;

  const _Section(
      {required this.title, required this.child, this.trailing});

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

class _EventTile extends StatelessWidget {
  final AdlEventModel event;
  final bool isSelected;
  final VoidCallback onSelect;
  final VoidCallback onAddTeam;

  const _EventTile({
    required this.event,
    required this.isSelected,
    required this.onSelect,
    required this.onAddTeam,
  });

  @override
  Widget build(BuildContext context) {
    final expiry = event.inviteCodeExpiresAt;
    final valid = event.isInviteCodeValid;

    return GestureDetector(
      onTap: onSelect,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isSelected
              ? AppColors.accentBlue.withValues(alpha: 0.15)
              : AppColors.surfaceLighter,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isSelected ? AppColors.accentBlue : Colors.transparent,
            width: 1.5,
          ),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Text(event.name,
                        style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w600)),
                    if (event.isActive) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: AppColors.success,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Text('開催中',
                            style: TextStyle(
                                color: Colors.white, fontSize: 10)),
                      ),
                    ],
                  ]),
                  const SizedBox(height: 4),
                  Text(
                    '招待コード: ${valid ? "有効" : "期限切れ"} '
                    '(${expiry.month}/${expiry.day} ${expiry.hour}:${expiry.minute.toString().padLeft(2, "0")}まで)',
                    style: TextStyle(
                        color: valid ? Colors.grey : AppColors.error,
                        fontSize: 11),
                  ),
                ],
              ),
            ),
            if (isSelected)
              const Icon(Icons.check_circle,
                  color: AppColors.accentBlue, size: 18),
          ],
        ),
      ),
    );
  }
}

class _TeamTile extends StatelessWidget {
  final int rank;
  final AdlTeamModel team;
  final VoidCallback onRegenCode;
  final VoidCallback onDelete;

  const _TeamTile({
    required this.rank,
    required this.team,
    required this.onRegenCode,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final rankColors = [
      const Color(0xFFFFD700), // gold
      const Color(0xFFC0C0C0), // silver
      const Color(0xFFCD7F32), // bronze
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
          // 班名 + コード
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
                      '招待コード: ${team.inviteCode}',
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
                    const SizedBox(width: 4),
                    Text(
                      team.isInviteCodeValid ? '✓有効' : '×期限切',
                      style: TextStyle(
                          color: team.isInviteCodeValid
                              ? AppColors.success
                              : AppColors.error,
                          fontSize: 11),
                    ),
                  ],
                ),
                Text('${team.memberCount}人',
                    style: const TextStyle(
                        color: Colors.grey, fontSize: 11)),
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
          const SizedBox(width: 8),
          // アクション
          PopupMenuButton<String>(
            color: AppColors.surfaceLight,
            icon: const Icon(Icons.more_vert, color: Colors.grey, size: 18),
            onSelected: (v) {
              if (v == 'regen') onRegenCode();
              if (v == 'delete') onDelete();
            },
            itemBuilder: (_) => [
              const PopupMenuItem(
                value: 'regen',
                child: Text('コード再発行',
                    style: TextStyle(color: Colors.white, fontSize: 13)),
              ),
              const PopupMenuItem(
                value: 'delete',
                child: Text('班を削除',
                    style: TextStyle(color: Colors.red, fontSize: 13)),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

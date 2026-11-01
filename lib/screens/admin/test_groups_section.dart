import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../models/group_model.dart';
import '../../models/user_model.dart';
import '../../services/group_service.dart';
import '../../services/user_service.dart';
import '../../widgets/common/app_toast.dart';

/// テスト用グループを作る・消す（開発者ツール内）。
///
/// グループ作成の画面ができるまでの代わり。自分は必ずメンバーに入り、
/// 残りはユーザー検索で選ぶ（友達機能は廃止予定なので友達には頼らない）。
class TestGroupsSection extends StatefulWidget {
  const TestGroupsSection({super.key});

  @override
  State<TestGroupsSection> createState() => _TestGroupsSectionState();
}

class _TestGroupsSectionState extends State<TestGroupsSection> {
  final GroupService _groupService = GroupService();
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _searchController = TextEditingController();

  List<UserModel> _results = const [];

  /// 選んだメンバー（uid → ユーザー）。検索し直しても残す。
  final Map<String, UserModel> _selected = {};
  bool _busy = false;

  /// 自分の枠を引いた、選べる残りの人数。
  int get _remaining => GroupModel.maxMembers - 1 - _selected.length;

  String? get _uid => FirebaseAuth.instance.currentUser?.uid;

  @override
  void dispose() {
    _nameController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    final q = _searchController.text.trim();
    if (q.isEmpty) return;
    setState(() => _busy = true);
    final users = await UserService().searchUsers(query: q);
    if (!mounted) return;
    setState(() {
      _results = users.where((u) => u.uid != _uid).toList();
      _busy = false;
    });
  }

  static String _label(UserModel u) =>
      u.name?.isNotEmpty == true ? u.name! : (u.username ?? u.uid);

  Future<void> _create() async {
    final uid = _uid;
    final name = _nameController.text.trim();
    if (uid == null) return;
    if (name.isEmpty) {
      AppToast.show(context, 'グループ名を入れてください');
      return;
    }
    setState(() => _busy = true);
    try {
      await _groupService.createGroup(
        name: name,
        ownerId: uid,
        memberIds: _selected.keys.toList(),
      );
      if (!mounted) return;
      _nameController.clear();
      setState(() {
        _selected.clear();
        _results = const [];
      });
      AppToast.show(context, 'グループ「$name」を作りました');
    } catch (e) {
      if (mounted) AppToast.show(context, '作成に失敗しました: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _delete(GroupModel group) async {
    try {
      await _groupService.deleteGroup(group.groupId);
      if (mounted) AppToast.show(context, '「${group.name}」を消しました');
    } catch (e) {
      if (mounted) AppToast.show(context, '削除に失敗しました: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final uid = _uid;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'テスト用グループ',
          style: TextStyle(
              color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 4),
        const Text(
          '自分＋選んだ友達でグループを作ります。作成画面ができるまでの代わりです。',
          style: TextStyle(color: Colors.white38, fontSize: 11, height: 1.5),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _nameController,
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(
            hintText: 'グループ名',
            hintStyle: TextStyle(color: Colors.white38),
            isDense: true,
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _searchController,
                style: const TextStyle(color: Colors.white),
                textInputAction: TextInputAction.search,
                onSubmitted: (_) => _search(),
                decoration: const InputDecoration(
                  hintText: 'メンバーを名前・ユーザー名で検索',
                  hintStyle: TextStyle(color: Colors.white38),
                  isDense: true,
                ),
              ),
            ),
            const SizedBox(width: 8),
            ElevatedButton(
              onPressed: _busy ? null : _search,
              child: const Text('検索'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          'メンバー ${_selected.length + 1}/${GroupModel.maxMembers}人（自分を含む）',
          style: const TextStyle(color: Colors.white38, fontSize: 11),
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            // 選んだ人を先に、検索結果のうち未選択の人を後に並べる。
            for (final u in [
              ..._selected.values,
              ..._results.where((u) => !_selected.containsKey(u.uid)),
            ])
              FilterChip(
                label: Text(_label(u)),
                selected: _selected.containsKey(u.uid),
                onSelected: (on) {
                  if (on && _remaining <= 0) {
                    AppToast.show(
                        context, 'グループは${GroupModel.maxMembers}人までです');
                    return;
                  }
                  setState(() {
                    on ? _selected[u.uid] = u : _selected.remove(u.uid);
                  });
                },
              ),
          ],
        ),
        const SizedBox(height: 8),
        ElevatedButton(
          onPressed: _busy ? null : _create,
          child: Text('作成（${_selected.length + 1}人）'),
        ),
        const SizedBox(height: 12),
        if (uid != null)
          StreamBuilder<List<GroupModel>>(
            stream: _groupService.watchMyGroups(uid),
            builder: (context, snap) {
              if (snap.hasError) {
                return Text('読み込み失敗: ${snap.error}',
                    style:
                        const TextStyle(color: Colors.redAccent, fontSize: 12));
              }
              final groups = snap.data;
              if (groups == null) return const SizedBox.shrink();
              if (groups.isEmpty) {
                return const Text('所属グループはありません',
                    style: TextStyle(color: Colors.white38, fontSize: 12));
              }
              return Column(
                children: [
                  for (final g in groups)
                    ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      title: Text(g.name,
                          style: const TextStyle(color: Colors.white)),
                      subtitle: Text(
                          '${g.memberIds.length}/${GroupModel.maxMembers}人',
                          style: const TextStyle(color: Colors.white38)),
                      trailing: IconButton(
                        icon: const Icon(Icons.delete_outline,
                            color: Colors.white38),
                        onPressed: () => _delete(g),
                      ),
                    ),
                ],
              );
            },
          ),
        const SizedBox(height: 20),
      ],
    );
  }
}

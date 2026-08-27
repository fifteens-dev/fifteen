import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import '../constants/app_colors.dart';
import '../models/user_model.dart';
import '../services/milfolha_service.dart';
import '../services/user_service.dart';
import '../widgets/profile_widgets.dart';
import 'other_user_profile_screen.dart';

/// Milfolha 班メンバー一覧（milfolha_memberships の teamId 一致で取得）。
/// ADL の AdlTeamMembersScreen に準拠したシンプル版。
class MilfolhaTeamMembersScreen extends StatefulWidget {
  final String teamId;
  final String teamDisplayName;

  const MilfolhaTeamMembersScreen({
    super.key,
    required this.teamId,
    required this.teamDisplayName,
  });

  @override
  State<MilfolhaTeamMembersScreen> createState() =>
      _MilfolhaTeamMembersScreenState();
}

class _MilfolhaTeamMembersScreenState extends State<MilfolhaTeamMembersScreen> {
  final MilfolhaService _service = MilfolhaService();
  final UserService _userService = UserService();
  final FirebaseAuth _auth = FirebaseAuth.instance;

  List<UserModel> _members = [];
  bool _isLoading = true;
  String? _currentUserId;

  @override
  void initState() {
    super.initState();
    _currentUserId = _auth.currentUser?.uid;
    _loadData();
  }

  Future<void> _loadData() async {
    try {
      final uids = (await _service.getTeamMemberUids(widget.teamId))
          .where((uid) => uid != widget.teamId) // 班アカウント自身は除外
          .toList();
      final users = await Future.wait(uids.map(_userService.getUser));
      if (!mounted) return;
      setState(() {
        _members = users.whereType<UserModel>().toList();
        _isLoading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            SizedBox(
              height: 44,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Align(
                    alignment: Alignment.centerLeft,
                    child: GestureDetector(
                      onTap: () => Navigator.pop(context),
                      child: const Padding(
                        padding: EdgeInsets.only(left: 16),
                        child: Icon(Icons.arrow_back_ios_new,
                            color: Colors.white, size: 20),
                      ),
                    ),
                  ),
                  Text(
                    '${widget.teamDisplayName} チーム',
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ),
            Expanded(
              child: _isLoading
                  ? const Center(
                      child: CupertinoActivityIndicator(
                          color: Colors.white, radius: 12))
                  : _members.isEmpty
                      ? const Center(
                          child: Text('メンバーがいません',
                              style: TextStyle(
                                  color: Colors.grey, fontSize: 13)))
                      : ListView.builder(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          itemCount: _members.length,
                          itemBuilder: (context, i) => _memberTile(_members[i]),
                        ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _memberTile(UserModel u) {
    final isSelf = u.uid == _currentUserId;
    return ListTile(
      onTap: isSelf
          ? null
          : () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => OtherUserProfileScreen(userId: u.uid),
                ),
              ),
      leading: ClipOval(
        child: ProfileImage(imageUrl: u.profileImageUrl, size: 44),
      ),
      title: Text(
        u.name?.isNotEmpty == true ? u.name! : (u.username ?? '名前未設定'),
        style: const TextStyle(color: Colors.white, fontSize: 14),
      ),
      subtitle: u.username != null
          ? Text('@${u.username}',
              style: const TextStyle(color: Colors.grey, fontSize: 12))
          : null,
    );
  }
}

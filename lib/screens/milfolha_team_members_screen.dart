import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import '../constants/app_colors.dart';
import '../models/user_model.dart';
import '../services/milfolha_service.dart';
import '../widgets/profile_widgets.dart';
import 'other_user_profile_screen.dart';

/// WATERFALLS 班メンバー一覧。
///
/// メンバーの解決は [MilfolhaService.getTeamMembers] に集約している。
/// 以前はここで uid ごとに UserService.getUser を呼んでおり、読み取りに失敗した
/// メンバーが無言で一覧から消えて班プロフィールの「メンバー」数とズレていた。
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
  final FirebaseAuth _auth = FirebaseAuth.instance;

  List<UserModel> _members = [];
  bool _isLoading = true;
  bool _hasError = false;
  String? _currentUserId;

  @override
  void initState() {
    super.initState();
    _currentUserId = _auth.currentUser?.uid;
    _loadData();
  }

  Future<void> _loadData() async {
    if (mounted) setState(() => _hasError = false);
    try {
      final members = await _service.getTeamMembers(widget.teamId);
      if (!mounted) return;
      setState(() {
        _members = members;
        _isLoading = false;
      });
    } catch (_) {
      // 読み取り失敗を「メンバー0人」として黙らせず、再試行を出す。
      if (mounted) {
        setState(() {
          _hasError = true;
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _refresh() async {
    await _loadData();
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
            Expanded(child: _buildBody()),
          ],
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(
        child: CupertinoActivityIndicator(color: Colors.white, radius: 12),
      );
    }
    if (_hasError) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('メンバーを読み込めませんでした',
                style: TextStyle(color: Colors.grey, fontSize: 13)),
            const SizedBox(height: 12),
            TextButton(
              onPressed: _loadData,
              child: const Text('再試行',
                  style: TextStyle(color: Colors.white, fontSize: 13)),
            ),
          ],
        ),
      );
    }
    // 引っ張って更新できるよう、空のときもスクロール可能にしておく。
    return RefreshIndicator(
      onRefresh: _refresh,
      backgroundColor: const Color(0xFF1C1C1E),
      color: Colors.white,
      child: _members.isEmpty
          ? ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              children: const [
                SizedBox(height: 120),
                Center(
                  child: Text('メンバーがいません',
                      style: TextStyle(color: Colors.grey, fontSize: 13)),
                ),
              ],
            )
          : ListView.builder(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemCount: _members.length,
              itemBuilder: (context, i) => _memberTile(_members[i]),
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

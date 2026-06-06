import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../constants/app_colors.dart';
import '../models/user_model.dart';
import '../services/user_service.dart';
import '../widgets/profile_widgets.dart';
import 'other_user_profile_screen.dart';

/// 班に所属するメンバー一覧。FollowListScreen と同じ視覚スタイル。
class AdlTeamMembersScreen extends StatefulWidget {
  final String teamId;
  final String teamDisplayName;

  const AdlTeamMembersScreen({
    super.key,
    required this.teamId,
    required this.teamDisplayName,
  });

  @override
  State<AdlTeamMembersScreen> createState() => _AdlTeamMembersScreenState();
}

class _AdlTeamMembersScreenState extends State<AdlTeamMembersScreen> {
  final UserService _userService = UserService();
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final TextEditingController _searchController = TextEditingController();

  List<UserModel> _members = [];
  bool _isLoading = true;
  String? _currentUserId;
  Set<String> _followingIds = {};
  final Set<String> _loadingIds = {};
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _currentUserId = _auth.currentUser?.uid;
    _loadData();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    try {
      final snap = await FirebaseFirestore.instance
          .collection('users')
          .where('adlTeamId', isEqualTo: widget.teamId)
          .get();
      // 班アカウント自身（users/{teamId}）はメンバー一覧から除外
      final members = snap.docs
          .where((d) => d.id != widget.teamId)
          .map(UserModel.fromFirestore)
          .toList();

      UserModel? currentUser;
      if (_currentUserId != null) {
        currentUser = await _userService.getUser(_currentUserId!);
      }

      if (!mounted) return;
      setState(() {
        _members = members;
        _followingIds = Set<String>.from(currentUser?.following ?? []);
        _isLoading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _toggleFollow(String targetUserId) async {
    if (_currentUserId == null) return;
    final isFollowing = _followingIds.contains(targetUserId);
    HapticFeedback.mediumImpact();
    setState(() {
      if (isFollowing) {
        _followingIds.remove(targetUserId);
      } else {
        _followingIds.add(targetUserId);
      }
      _loadingIds.add(targetUserId);
    });
    try {
      if (isFollowing) {
        await _userService.unfollowUser(
          currentUserId: _currentUserId!,
          targetUserId: targetUserId,
        );
      } else {
        await _userService.followUser(
          currentUserId: _currentUserId!,
          targetUserId: targetUserId,
        );
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          if (isFollowing) {
            _followingIds.add(targetUserId);
          } else {
            _followingIds.remove(targetUserId);
          }
        });
      }
    } finally {
      if (mounted) setState(() => _loadingIds.remove(targetUserId));
    }
  }

  List<UserModel> get _filtered {
    if (_searchQuery.isEmpty) return _members;
    final q = _searchQuery.toLowerCase();
    return _members.where((u) {
      final username = (u.username ?? '').toLowerCase();
      final name = (u.name ?? '').toLowerCase();
      return username.contains(q) || name.contains(q);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(),
            _buildSearchBar(),
            Expanded(
              child: _isLoading
                  ? const Center(
                      child: CupertinoActivityIndicator(
                        color: Colors.white,
                        radius: 12,
                      ),
                    )
                  : _buildList(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return SizedBox(
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
                child: Icon(
                  Icons.arrow_back_ios_new,
                  color: Colors.white,
                  size: 20,
                ),
              ),
            ),
          ),
          Text(
            '${widget.teamDisplayName} 班',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
      child: Container(
        height: 36,
        decoration: BoxDecoration(
          color: const Color(0xFF2A2A2A),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            const SizedBox(width: 10),
            const Icon(Icons.search, color: Color(0xFF888888), size: 18),
            const SizedBox(width: 6),
            Expanded(
              child: TextField(
                controller: _searchController,
                style: const TextStyle(color: Colors.white, fontSize: 14),
                cursorColor: Colors.white,
                decoration: const InputDecoration(
                  hintText: '検索',
                  hintStyle: TextStyle(color: Color(0xFF888888), fontSize: 14),
                  border: InputBorder.none,
                  contentPadding: EdgeInsets.symmetric(vertical: 0),
                  isCollapsed: true,
                ),
                onChanged: (v) => setState(() => _searchQuery = v),
              ),
            ),
            if (_searchQuery.isNotEmpty)
              GestureDetector(
                onTap: () {
                  _searchController.clear();
                  setState(() => _searchQuery = '');
                },
                child: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 8),
                  child: Icon(Icons.close, color: Color(0xFF888888), size: 16),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildList() {
    final users = _filtered;
    if (users.isEmpty) {
      return Center(
        child: Text(
          _searchQuery.isNotEmpty
              ? '該当するユーザーが見つかりません'
              : 'メンバーがいません',
          style: const TextStyle(color: Colors.white54, fontSize: 14),
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.only(top: 4),
      itemCount: users.length,
      itemBuilder: (context, index) {
        final user = users[index];
        final isFollowingThisUser = _followingIds.contains(user.uid);
        final isLoading = _loadingIds.contains(user.uid);
        final isSelf = user.uid == _currentUserId;

        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () {
            if (isSelf) {
              Navigator.pushNamed(context, '/profile');
            } else {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => OtherUserProfileScreen(userId: user.uid),
                ),
              );
            }
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                Container(
                  width: 50,
                  height: 50,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.grey[800],
                  ),
                  child: ClipOval(
                    child: ProfileImage(
                      imageUrl: user.profileImageUrl,
                      size: 50,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        user.username ?? 'ユーザー',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (user.name != null &&
                          user.name!.isNotEmpty &&
                          user.name != user.username)
                        Text(
                          user.name!,
                          style: const TextStyle(
                            color: Colors.white54,
                            fontSize: 13,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                if (!isSelf)
                  _buildFollowButton(user.uid, isFollowingThisUser, isLoading),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildFollowButton(String uid, bool isFollowing, bool isLoading) {
    return GestureDetector(
      onTap: isLoading ? null : () => _toggleFollow(uid),
      child: Container(
        height: 32,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        decoration: BoxDecoration(
          color: isFollowing ? Colors.transparent : const Color(0xFF5D8FFF),
          borderRadius: BorderRadius.circular(23),
          border: isFollowing ? Border.all(color: Colors.grey, width: 1) : null,
        ),
        child: Center(
          child: isLoading
              ? const CupertinoActivityIndicator(
                  color: Colors.white,
                  radius: 7,
                )
              : Text(
                  isFollowing ? 'フォロー中' : 'フォロー',
                  style: TextStyle(
                    color: isFollowing ? Colors.grey : Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
        ),
      ),
    );
  }
}

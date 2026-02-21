import 'package:flutter/material.dart';
import '../models/user_model.dart';
import '../services/user_service.dart';
import '../widgets/profile_widgets.dart';
import 'other_user_profile_screen.dart';

/// フォロー/フォロワー一覧画面
class FollowListScreen extends StatefulWidget {
  final String userId;
  final bool showFollowers; // true: フォロワー, false: フォロー中

  const FollowListScreen({
    super.key,
    required this.userId,
    required this.showFollowers,
  });

  @override
  State<FollowListScreen> createState() => _FollowListScreenState();
}

class _FollowListScreenState extends State<FollowListScreen> {
  final UserService _userService = UserService();
  List<UserModel> _users = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadUsers();
  }

  Future<void> _loadUsers() async {
    try {
      final users = widget.showFollowers
          ? await _userService.getFollowers(widget.userId)
          : await _userService.getFollowing(widget.userId);
      if (mounted) {
        setState(() {
          _users = users;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.showFollowers ? 'フォロワー' : 'フォロー中';

    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      appBar: AppBar(
        backgroundColor: const Color(0xFF121212),
        title: Text(title, style: const TextStyle(color: Colors.white)),
        iconTheme: const IconThemeData(color: Colors.white),
        elevation: 0,
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: Colors.white),
            )
          : _users.isEmpty
              ? Center(
                  child: Text(
                    widget.showFollowers
                        ? 'フォロワーはいません'
                        : 'フォロー中のユーザーはいません',
                    style: const TextStyle(color: Colors.white54, fontSize: 14),
                  ),
                )
              : ListView.builder(
                  itemCount: _users.length,
                  itemBuilder: (context, index) {
                    final user = _users[index];
                    return ListTile(
                      leading: Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.grey[800],
                        ),
                        child: ClipOval(
                          child: ProfileImage(
                            imageUrl: user.profileImageUrl,
                            size: 44,
                          ),
                        ),
                      ),
                      title: Text(
                        user.name ?? user.username ?? 'ユーザー',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      subtitle: Text(
                        '@${user.username}',
                        style: const TextStyle(
                          color: Colors.white54,
                          fontSize: 13,
                        ),
                      ),
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => OtherUserProfileScreen(
                              userId: user.uid,
                            ),
                          ),
                        );
                      },
                    );
                  },
                ),
    );
  }
}

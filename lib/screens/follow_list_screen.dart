import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/cupertino.dart';
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
  final FirebaseAuth _auth = FirebaseAuth.instance;
  List<UserModel> _users = [];
  bool _isLoading = true;
  String? _currentUserId;
  Set<String> _followingIds = {};
  final Set<String> _loadingIds = {};
  final Set<String> _removedIds = {};

  @override
  void initState() {
    super.initState();
    _currentUserId = _auth.currentUser?.uid;
    _loadData();
  }

  Future<void> _loadData() async {
    try {
      // フォロワー/フォロー中の取得と自分のフォロー状態を並列で取得
      final usersFuture = widget.showFollowers
          ? _userService.getFollowers(widget.userId)
          : _userService.getFollowing(widget.userId);
      final currentUserFuture = _currentUserId != null
          ? _userService.getUser(_currentUserId!)
          : Future<UserModel?>.value(null);

      final (users, currentUserModel) = await (usersFuture, currentUserFuture).wait;

      if (mounted) {
        setState(() {
          _users = users;
          _followingIds = Set<String>.from(currentUserModel?.following ?? []);
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _toggleFollow(String targetUserId) async {
    if (_currentUserId == null) return;
    final isFollowing = _followingIds.contains(targetUserId);

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

  Future<void> _removeFollower(String followerUid) async {
    if (_currentUserId == null) return;
    setState(() => _loadingIds.add(followerUid));
    try {
      await _userService.removeFollower(
        currentUserId: _currentUserId!,
        followerUserId: followerUid,
      );
      if (mounted) {
        setState(() {
          _removedIds.add(followerUid);
          _users.removeWhere((u) => u.uid == followerUid);
        });
      }
    } catch (_) {
      // エラー時は何もしない（ロールバック不要）
    } finally {
      if (mounted) setState(() => _loadingIds.remove(followerUid));
    }
  }

  Widget _buildRemoveButton(String uid) {
    final isLoading = _loadingIds.contains(uid);
    return GestureDetector(
      onTap: isLoading ? null : () => _removeFollower(uid),
      child: Container(
        height: 32,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        decoration: BoxDecoration(
          color: const Color(0xFF2A2A2A),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Center(
          child: isLoading
              ? const CupertinoActivityIndicator(
                  color: Colors.white54,
                  radius: 7,
                )
              : const Text(
                  '削除',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
        ),
      ),
    );
  }

  Widget _buildFollowButton(String uid) {
    if (uid == _currentUserId) return const SizedBox.shrink();
    final isFollowing = _followingIds.contains(uid);
    final isLoading = _loadingIds.contains(uid);

    return GestureDetector(
      onTap: isLoading ? null : () => _toggleFollow(uid),
      child: Container(
        height: 32,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        decoration: BoxDecoration(
          color: isFollowing ? Colors.transparent : const Color(0xFF5D8FFF),
          borderRadius: BorderRadius.circular(23),
          border: isFollowing
              ? Border.all(color: Colors.grey, width: 1)
              : null,
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

  @override
  Widget build(BuildContext context) {
    final title = widget.showFollowers ? 'フォロワー' : 'フォロー中';

    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      appBar: AppBar(
        backgroundColor: const Color(0xFF121212),
        title: Text(title, style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w600)),
        centerTitle: true,
        iconTheme: const IconThemeData(color: Colors.white),
        elevation: 0,
      ),
      body: _isLoading
          ? const Center(
              child: CupertinoActivityIndicator(color: Colors.white, radius: 14),
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
                  itemCount: _users.length + (widget.showFollowers ? 1 : 0),
                  itemBuilder: (context, index) {
                    if (widget.showFollowers && index == 0) {
                      return const Padding(
                        padding: EdgeInsets.fromLTRB(16, 12, 16, 8),
                        child: Text(
                          'すべてのフォロワー',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      );
                    }
                    final user = _users[widget.showFollowers ? index - 1 : index];
                    final isOwnPage = widget.userId == _currentUserId;
                    final isFollowingBack = _followingIds.contains(user.uid);

                    return GestureDetector(
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
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 8,
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 54,
                              height: 54,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: Colors.grey[800],
                              ),
                              child: ClipOval(
                                child: ProfileImage(
                                  imageUrl: user.profileImageUrl,
                                  size: 54,
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  // フォロワー欄(自分のページ): username + フォローバックバッジ
                                  if (widget.showFollowers && isOwnPage)
                                    Row(
                                      children: [
                                        Flexible(
                                          child: Text(
                                            user.username ?? 'ユーザー',
                                            style: const TextStyle(
                                              color: Colors.white,
                                              fontWeight: FontWeight.w600,
                                              fontSize: 14,
                                            ),
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                        if (!isFollowingBack &&
                                            user.uid != _currentUserId) ...[
                                          const SizedBox(width: 6),
                                          const Text(
                                            '· ',
                                            style: TextStyle(
                                              color: Colors.white54,
                                              fontSize: 13,
                                            ),
                                          ),
                                          GestureDetector(
                                            onTap: () =>
                                                _toggleFollow(user.uid),
                                            child: const Text(
                                              'フォローバック',
                                              style: TextStyle(
                                                color: Color(0xFF5D8FFF),
                                                fontSize: 13,
                                                fontWeight: FontWeight.w500,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ],
                                    )
                                  else
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
                            if (widget.showFollowers)
                              if (isOwnPage && user.uid != _currentUserId)
                                _buildRemoveButton(user.uid)
                              else
                                _buildFollowButton(user.uid)
                            else
                              _buildFollowButton(user.uid),
                          ],
                        ),
                      ),
                    );
                  },
                ),
    );
  }
}

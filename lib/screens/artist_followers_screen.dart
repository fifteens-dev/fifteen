import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/user_model.dart';
import '../services/artist_service.dart';
import '../services/user_service.dart';
import '../widgets/profile_widgets.dart';
import 'other_user_profile_screen.dart';

/// アーティストのフォロワー一覧画面
class ArtistFollowersScreen extends StatefulWidget {
  final String artistId;
  final String artistName;

  const ArtistFollowersScreen({
    super.key,
    required this.artistId,
    required this.artistName,
  });

  @override
  State<ArtistFollowersScreen> createState() => _ArtistFollowersScreenState();
}

class _ArtistFollowersScreenState extends State<ArtistFollowersScreen> {
  final ArtistService _artistService = ArtistService();
  final UserService _userService = UserService();

  List<UserModel> _followers = [];
  bool _isLoading = true;
  String? _currentUserId;
  Set<String> _followingIds = {};
  final Set<String> _loadingIds = {};

  @override
  void initState() {
    super.initState();
    _currentUserId = FirebaseAuth.instance.currentUser?.uid;
    _loadData();
  }

  Future<void> _loadData() async {
    try {
      final artist = await _artistService.getArtist(widget.artistId);
      final followerIds = artist?.followerIds ?? [];

      // フォロワーの UserModel を並列取得
      final results = await Future.wait(
        followerIds.map((id) => _userService.getUser(id)),
      );
      final followers =
          results.whereType<UserModel>().toList();

      // 自分のフォロー中リストを取得
      Set<String> followingIds = {};
      if (_currentUserId != null) {
        final me = await _userService.getUser(_currentUserId!);
        followingIds = Set<String>.from(me?.following ?? []);
      }

      if (mounted) {
        setState(() {
          _followers = followers;
          _followingIds = followingIds;
          _isLoading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _toggleFollow(String targetUserId) async {
    if (_currentUserId == null) return;
    HapticFeedback.mediumImpact();

    final isFollowing = _followingIds.contains(targetUserId);
    setState(() {
      _loadingIds.add(targetUserId);
      if (isFollowing) {
        _followingIds.remove(targetUserId);
      } else {
        _followingIds.add(targetUserId);
      }
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(),
            Expanded(
              child: _isLoading
                  ? const Center(
                      child: CupertinoActivityIndicator(
                          color: Colors.white, radius: 14),
                    )
                  : _buildList(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      height: 45,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Stack(
        children: [
          Center(
            child: Text(
              widget.artistName,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          Positioned(
            left: 0,
            top: 0,
            bottom: 0,
            child: IconButton(
              icon: const Icon(Icons.arrow_back_ios, color: Colors.white),
              onPressed: () => Navigator.pop(context),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildList() {
    if (_followers.isEmpty) {
      return const Center(
        child: Text(
          'フォロワーはいません',
          style: TextStyle(color: Colors.white54, fontSize: 14),
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.only(top: 4),
      itemCount: _followers.length,
      itemBuilder: (context, index) => _buildUserRow(_followers[index]),
    );
  }

  Widget _buildUserRow(UserModel user) {
    final isMe = user.uid == _currentUserId;
    final isFollowing = _followingIds.contains(user.uid);
    final isLoading = _loadingIds.contains(user.uid);

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        if (isMe) {
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
            // アバター
            Container(
              width: 50,
              height: 50,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.grey[800],
              ),
              child: ClipOval(
                child: ProfileImage(imageUrl: user.profileImageUrl, size: 50),
              ),
            ),
            const SizedBox(width: 12),
            // ユーザー名
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
            // フォローボタン（自分以外）
            if (!isMe)
              GestureDetector(
                onTap: isLoading ? null : () => _toggleFollow(user.uid),
                child: Container(
                  height: 30,
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  decoration: BoxDecoration(
                    color: isFollowing
                        ? Colors.transparent
                        : const Color(0xFF0098FE),
                    border: isFollowing
                        ? Border.all(color: const Color(0xFF929292))
                        : null,
                    borderRadius: BorderRadius.circular(9),
                  ),
                  alignment: Alignment.center,
                  child: isLoading
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(
                              strokeWidth: 1.5, color: Colors.white),
                        )
                      : Text(
                          isFollowing ? 'フォロー中' : 'フォロー',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

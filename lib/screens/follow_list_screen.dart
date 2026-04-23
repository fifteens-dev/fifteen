import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/user_model.dart';
import '../services/user_service.dart';
import '../widgets/profile_widgets.dart';
import 'other_user_profile_screen.dart';

/// フォロー/フォロワー一覧画面（横スライドタブ）
class FollowListScreen extends StatefulWidget {
  final String userId;
  final bool showFollowers;

  const FollowListScreen({
    super.key,
    required this.userId,
    required this.showFollowers,
  });

  @override
  State<FollowListScreen> createState() => _FollowListScreenState();
}

class _FollowListScreenState extends State<FollowListScreen>
    with SingleTickerProviderStateMixin {
  final UserService _userService = UserService();
  final FirebaseAuth _auth = FirebaseAuth.instance;

  late TabController _tabController;
  late PageController _pageController;

  List<UserModel> _followers = [];
  List<UserModel> _following = [];
  bool _isLoading = true;
  String? _currentUserId;
  Set<String> _followingIds = {};
  final Set<String> _loadingIds = {};

  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _currentUserId = _auth.currentUser?.uid;
    final initialIndex = widget.showFollowers ? 0 : 1;
    _tabController = TabController(
      length: 2,
      vsync: this,
      initialIndex: initialIndex,
    );
    _pageController = PageController(initialPage: initialIndex);
    _tabController.addListener(_onTabControllerChanged);
    _loadData();
  }

  void _onTabControllerChanged() {
    if (_tabController.indexIsChanging) return;
    if (_pageController.hasClients) {
      _pageController.animateToPage(
        _tabController.index,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeInOut,
      );
    }
  }

  @override
  void dispose() {
    _tabController.removeListener(_onTabControllerChanged);
    _tabController.dispose();
    _pageController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    try {
      final results = await Future.wait([
        _userService.getFollowers(widget.userId),
        _userService.getFollowing(widget.userId),
        _currentUserId != null
            ? _userService.getUser(_currentUserId!)
            : Future<UserModel?>.value(null),
      ]);

      if (mounted) {
        setState(() {
          _followers = results[0] as List<UserModel>;
          _following = results[1] as List<UserModel>;
          final currentUser = results[2] as UserModel?;
          _followingIds = Set<String>.from(currentUser?.following ?? []);
          _isLoading = false;
        });
      }
    } catch (e) {
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
          _followers.removeWhere((u) => u.uid == followerUid);
        });
      }
    } catch (_) {
    } finally {
      if (mounted) setState(() => _loadingIds.remove(followerUid));
    }
  }

  List<UserModel> _filteredList(List<UserModel> users) {
    if (_searchQuery.isEmpty) return users;
    final q = _searchQuery.toLowerCase();
    return users.where((u) {
      final username = (u.username ?? '').toLowerCase();
      final name = (u.name ?? '').toLowerCase();
      return username.contains(q) || name.contains(q);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(),
            _buildTabBar(),
            _buildSearchBar(),
            Expanded(
              child: _isLoading
                  ? const Center(
                      child: CupertinoActivityIndicator(
                        color: Colors.white,
                        radius: 12,
                      ),
                    )
                  : PageView(
                      controller: _pageController,
                      onPageChanged: (index) {
                        _tabController.animateTo(index);
                      },
                      children: [
                        _buildUserList(_filteredList(_followers), isFollowers: true),
                        _buildUserList(_filteredList(_following), isFollowers: false),
                      ],
                    ),
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
              child: Padding(
                padding: const EdgeInsets.only(left: 16),
                child: const Icon(
                  Icons.arrow_back_ios_new,
                  color: Colors.white,
                  size: 20,
                ),
              ),
            ),
          ),
          // ユーザー名
          FutureBuilder<UserModel?>(
            future: _userService.getUser(widget.userId),
            builder: (context, snapshot) {
              final name = snapshot.data?.username ?? '';
              return Text(
                name,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildTabBar() {
    return Column(
      children: [
        SizedBox(
          height: 37,
          child: Stack(
            children: [
              // タブボタン
              Row(
                children: [
                  // フォロワータブ
                  Expanded(
                    child: GestureDetector(
                      onTap: () => _tabController.animateTo(0),
                      behavior: HitTestBehavior.opaque,
                      child: Center(
                        child: AnimatedBuilder(
                          animation: _pageController,
                          builder: (context, _) {
                            final t = _pageController.hasClients
                                ? (_pageController.page ?? _tabController.index.toDouble()).clamp(0.0, 1.0)
                                : _tabController.index.toDouble();
                            final opacity = 1.0 - t;
                            return Text(
                              '${_followers.length}フォロワー',
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.4 + 0.6 * opacity),
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                  ),
                  // フォロー中タブ
                  Expanded(
                    child: GestureDetector(
                      onTap: () => _tabController.animateTo(1),
                      behavior: HitTestBehavior.opaque,
                      child: Center(
                        child: AnimatedBuilder(
                          animation: _pageController,
                          builder: (context, _) {
                            final t = _pageController.hasClients
                                ? (_pageController.page ?? _tabController.index.toDouble()).clamp(0.0, 1.0)
                                : _tabController.index.toDouble();
                            return Text(
                              '${_following.length}フォロー中',
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.4 + 0.6 * t),
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              // スライドインジケーター
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: AnimatedBuilder(
                  animation: _pageController,
                  builder: (context, _) {
                    final screenWidth = MediaQuery.of(context).size.width;
                    final tabWidth = screenWidth / 2;
                    const indicatorWidth = 80.0;
                    final t = _pageController.hasClients
                        ? (_pageController.page ?? _tabController.index.toDouble()).clamp(0.0, 1.0)
                        : _tabController.index.toDouble();
                    final left = t * tabWidth + (tabWidth - indicatorWidth) / 2;
                    return SizedBox(
                      height: 2,
                      child: Stack(
                        children: [
                          Positioned(
                            left: left,
                            width: indicatorWidth,
                            top: 0,
                            bottom: 0,
                            child: Container(
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(1),
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
        Container(
          height: 0.5,
          color: const Color(0xFF2D2D2D),
        ),
      ],
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
                cursorColor: Colors.black,
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

  Widget _buildUserList(List<UserModel> users, {required bool isFollowers}) {
    if (users.isEmpty) {
      return Center(
        child: Text(
          _searchQuery.isNotEmpty
              ? '該当するユーザーが見つかりません'
              : isFollowers
                  ? 'フォロワーはいません'
                  : 'フォロー中のユーザーはいません',
          style: const TextStyle(color: Colors.white54, fontSize: 14),
        ),
      );
    }

    final isOwnPage = widget.userId == _currentUserId;

    return ListView.builder(
      padding: const EdgeInsets.only(top: 4),
      itemCount: users.length,
      itemBuilder: (context, index) {
        final user = users[index];
        final isFollowingThisUser = _followingIds.contains(user.uid);
        final isLoading = _loadingIds.contains(user.uid);

        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () {
            if (user.uid == _currentUserId) {
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
                    child: ProfileImage(
                      imageUrl: user.profileImageUrl,
                      size: 50,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                // ユーザー情報
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (isFollowers && isOwnPage)
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
                            if (!isFollowingThisUser && user.uid != _currentUserId) ...[
                              const SizedBox(width: 6),
                              const Text(
                                '· ',
                                style: TextStyle(
                                  color: Colors.white54,
                                  fontSize: 13,
                                ),
                              ),
                              GestureDetector(
                                onTap: () => _toggleFollow(user.uid),
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
                // ボタン
                if (isFollowers && isOwnPage && user.uid != _currentUserId)
                  _buildRemoveButton(user.uid, isLoading)
                else if (user.uid != _currentUserId)
                  _buildFollowButton(user.uid, isFollowingThisUser, isLoading),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildRemoveButton(String uid, bool isLoading) {
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

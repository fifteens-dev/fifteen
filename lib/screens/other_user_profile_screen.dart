import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/user_model.dart';
import '../models/post_model.dart';
import '../services/user_service.dart';
import '../services/post_service.dart';
import '../services/audio_player_service.dart';
import '../widgets/profile_widgets.dart';
import 'follow_list_screen.dart';

/// プロフィール画面（他人）
class OtherUserProfileScreen extends StatefulWidget {
  final String userId;

  const OtherUserProfileScreen({
    super.key,
    required this.userId,
  });

  @override
  State<OtherUserProfileScreen> createState() => _OtherUserProfileScreenState();
}

class _OtherUserProfileScreenState extends State<OtherUserProfileScreen>
    with SingleTickerProviderStateMixin {
  final UserService _userService = UserService();
  final PostService _postService = PostService();
  final AudioPlayerService _audioService = AudioPlayerService();
  late TabController _tabController;

  // ダミーユーザーの定数
  static const List<String> _dummyUsernames = [
    'momo.hirai',
    'mina.myoi',
    'm.by__sana',
  ];

  UserModel? _userData;
  List<PostModel> _otherPosts = [];
  List<PostModel> _savedPosts = [];
  bool _isLoading = true;
  bool _isFollowing = false;
  bool _isFollowedBy = false; // 相手が自分をフォローしているか


  // ダミーユーザー用フォロワー数オーバーライド
  int? _followerCountOverride;

  int get _followersCount =>
      _followerCountOverride ?? _userData?.followersCount ?? 0;
  int get _followingCount => _userData?.followingCount ?? 0;
  int get _tracksCount => _otherPosts.length;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) {
        setState(() {});
      }
      if (_tabController.index == 1 && _savedPosts.isEmpty) {
        _loadSavedPosts();
      }
    });
    _loadData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _audioService.stop();
    super.dispose();
  }

  /// プロフィール画像を拡大表示
  void _showProfileImageDialog(String imageUrl) {
    showDialog(
      context: context,
      barrierColor: Colors.black87,
      builder: (context) => GestureDetector(
        onTap: () => Navigator.pop(context),
        child: Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.all(16),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: CachedNetworkImage(
              imageUrl: imageUrl,
              fit: BoxFit.contain,
              errorWidget: (_, __, ___) => const Icon(
                Icons.person,
                color: Colors.white54,
                size: 80,
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// データを全て再読み込み
  Future<void> _refresh() async {
    await Future.wait([
      _loadData(),
      _loadSavedPosts(),
    ]);
  }

  /// データを読み込み
  Future<void> _loadData() async {
    try {
      final userData = await _userService.getUser(widget.userId);

      final currentUserId = FirebaseAuth.instance.currentUser?.uid;
      UserModel? currentUser;
      if (currentUserId != null) {
        currentUser = await _userService.getUser(currentUserId);
      }

      final otherPosts =
          await _postService.getPostsExcludingToday(widget.userId, limit: 50);

      if (mounted) {
        final isDummyUser =
            _dummyUsernames.contains(userData?.username ?? '');

        // 48時間フィルタ
        final cutoff48h = DateTime.now().subtract(const Duration(hours: 48));
        final visibleOtherPosts =
            otherPosts.where((p) => p.createdAt.isBefore(cutoff48h)).toList();

        setState(() {
          _userData = userData;
          _otherPosts = visibleOtherPosts;
          _isFollowing = currentUser?.isFollowing(widget.userId) ?? false;
          _isFollowedBy = userData?.following.contains(currentUserId) ?? false;
          _isLoading = false;

          if (isDummyUser) {
            _followerCountOverride = userData?.followers.length ?? 0;
          }
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  /// 保存済み投稿を読み込み
  Future<void> _loadSavedPosts() async {
    try {
      final savedPosts =
          await _postService.getPostsSavedByUser(widget.userId);
      if (mounted) {
        setState(() {
          _savedPosts = savedPosts;
        });
      }
    } catch (e) {
      if (kDebugMode) {
        print('保存済み投稿の読み込みエラー: $e');
      }
    }
  }

  /// フォロー/アンフォローを切り替え
  Future<void> _toggleFollow() async {
    final currentUsername = _userData?.username ?? '';

    if (_dummyUsernames.contains(currentUsername)) {
      setState(() {
        _isFollowing = !_isFollowing;
        _followerCountOverride ??= _userData?.followers.length ?? 0;
        _followerCountOverride = _isFollowing
            ? (_followerCountOverride! + 1)
            : (_followerCountOverride! - 1);
      });
      return;
    }

    final currentUserId = FirebaseAuth.instance.currentUser?.uid;
    if (currentUserId == null) return;

    final previousState = _isFollowing;
    setState(() {
      _isFollowing = !_isFollowing;
    });

    try {
      if (_isFollowing) {
        await _userService.followUser(
          currentUserId: currentUserId,
          targetUserId: widget.userId,
        );
      } else {
        await _userService.unfollowUser(
          currentUserId: currentUserId,
          targetUserId: widget.userId,
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isFollowing = previousState;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('エラーが発生しました: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        backgroundColor: Color(0xFF121212),
        body: Center(
          child: CupertinoActivityIndicator(color: Colors.white, radius: 14),
        ),
      );
    }

    if (_userData == null) {
      return Scaffold(
        backgroundColor: const Color(0xFF121212),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text(
                'ユーザーが見つかりません',
                style: TextStyle(color: Colors.white, fontSize: 16),
              ),
              const SizedBox(height: 16),
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('戻る'),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      body: SafeArea(
        child: Column(
          children: [
            // ヘッダー（固定）
            _buildHeader(),
            // リフレッシュ＋スクロールエリア（単一CustomScrollViewで統合）
            Expanded(
              child: CustomScrollView(
                physics: const AlwaysScrollableScrollPhysics(
                  parent: BouncingScrollPhysics(),
                ),
                slivers: [
                  CupertinoSliverRefreshControl(
                    onRefresh: _refresh,
                  ),
                  // プロフィール情報
                  SliverToBoxAdapter(child: _buildProfileInfo()),
                  // フォローボタン
                  SliverToBoxAdapter(child: _buildActionButtons()),
                  // タブ切り替え（スクロール時に上部に固定）
                  SliverPersistentHeader(
                    pinned: true,
                    delegate: _TabBarDelegate(child: _buildTabSelector()),
                  ),
                  // アクティブなタブのコンテンツ
                  ..._buildActiveTabSlivers(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// ヘッダー（戻るボタン + ユーザーID）
  Widget _buildHeader() {
    final username = _userData?.username ?? 'ユーザー名';

    return Container(
      height: 45,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Stack(
        children: [
          // ユーザーID（中央）
          Center(
            child: Text(
              username,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          // 戻るボタン（左端）
          Positioned(
            left: 0,
            top: 0,
            bottom: 0,
            child: IconButton(
              icon: const Icon(Icons.arrow_back_ios, color: Colors.white),
              onPressed: () {
                _audioService.stop();
                Navigator.pop(context);
              },
            ),
          ),
        ],
      ),
    );
  }

  /// プロフィール情報セクション
  Widget _buildProfileInfo() {
    final displayName = _userData?.name ?? '名前未設定';
    final bio = _userData?.bio ?? '';
    final profileImageUrl = _userData?.profileImageUrl;

    return Padding(
      padding: const EdgeInsets.fromLTRB(27, 30, 27, 16),
      child: Column(
        children: [
          // ユーザー情報行
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 左側: 名前・ユーザーID・bio
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      displayName,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    if (bio.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        bio,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.7),
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              // 右側: プロフィール画像（タップで拡大）
              GestureDetector(
                onTap: profileImageUrl != null && profileImageUrl.isNotEmpty
                    ? () => _showProfileImageDialog(profileImageUrl)
                    : null,
                child: Container(
                  width: 65,
                  height: 65,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.grey[800],
                  ),
                  child: ClipOval(
                    child: ProfileImage(
                      imageUrl: profileImageUrl,
                      size: 65,
                    ),
                  ),
                ),
              ),
            ],
          ),

          // 統計情報
          Row(
            children: [
              ProfileStatItem(count: '$_tracksCount', label: 'Tracks'),
              const SizedBox(width: 20),
              GestureDetector(
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => FollowListScreen(
                        userId: widget.userId,
                        showFollowers: true,
                      ),
                    ),
                  );
                },
                child: ProfileStatItem(
                    count: '$_followersCount', label: 'Followers'),
              ),
              const SizedBox(width: 20),
              GestureDetector(
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => FollowListScreen(
                        userId: widget.userId,
                        showFollowers: false,
                      ),
                    ),
                  );
                },
                child: ProfileStatItem(
                    count: '$_followingCount', label: 'Following'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// アクションボタン（フォロー）
  Widget _buildActionButtons() {
    // 自分のプロフィールの場合はフォローボタンを非表示
    final currentUserId = FirebaseAuth.instance.currentUser?.uid;
    if (currentUserId == widget.userId) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 21),
      child: GestureDetector(
        onTap: _toggleFollow,
        child: Container(
          height: 30,
          decoration: BoxDecoration(
            color: _isFollowing
                ? Colors.transparent
                : const Color(0xFF0095F6),
            border: Border.all(
              color: _isFollowing
                  ? const Color(0xFF929292)
                  : const Color(0xFF0095F6),
            ),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Center(
            child: Text(
              _isFollowing
                  ? 'フォロー中'
                  : _isFollowedBy
                      ? 'フォローバック'
                      : 'フォロー',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// タブ切り替え（スライドインジケーター付き）
  Widget _buildTabSelector() {
    const indicatorWidth = 60.0;
    const indicatorHeight = 2.0;

    return AnimatedBuilder(
      animation: _tabController.animation!,
      builder: (context, _) {
        final t = _tabController.animation!.value.clamp(0.0, 1.0);
        final color0 = Color.lerp(Colors.grey, Colors.white, 1.0 - t)!;
        final color1 = Color.lerp(Colors.grey, Colors.white, t)!;

        return LayoutBuilder(
          builder: (context, constraints) {
            final tabWidth = constraints.maxWidth / 2;
            final indicatorLeft = (tabWidth - indicatorWidth) / 2 + t * tabWidth;

            return Stack(
              children: [
                SizedBox(
                  height: 40,
                  child: Row(
                    children: [
                      Expanded(
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: () => _tabController.animateTo(0),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              Icon(Icons.grid_view, color: color0, size: 24),
                              const SizedBox(height: 4 + indicatorHeight),
                            ],
                          ),
                        ),
                      ),
                      Expanded(
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: () => _tabController.animateTo(1),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              Container(
                                width: 25,
                                height: 25,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  border: Border.all(color: color1, width: 1.5),
                                ),
                                child: Icon(Icons.add, color: color1, size: 16),
                              ),
                              const SizedBox(height: 4 + indicatorHeight),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Positioned(
                  bottom: 0,
                  left: indicatorLeft,
                  child: Container(
                    width: indicatorWidth,
                    height: indicatorHeight,
                    color: Colors.white,
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  /// アクティブなタブのスライバーリストを返す
  List<Widget> _buildActiveTabSlivers() {
    if (_tabController.index == 0) {
      return _buildPostsGridSlivers();
    } else {
      return _buildSavedPostsGridSlivers();
    }
  }

  /// 投稿グリッドのスライバーリスト
  List<Widget> _buildPostsGridSlivers() {
    if (_otherPosts.isEmpty) {
      return [
        const SliverFillRemaining(
          child: Center(
            child: Text(
              '投稿がありません',
              style: TextStyle(color: Colors.white54, fontSize: 14),
            ),
          ),
        ),
      ];
    }

    return [
      SliverGrid(
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3,
          childAspectRatio: 131 / 192,
          crossAxisSpacing: 0,
          mainAxisSpacing: 5,
        ),
        delegate: SliverChildBuilderDelegate(
          (context, index) {
            final post = _otherPosts[index];
            return ProfilePostGridItem(
              post: post,
              allPosts: _otherPosts,
              initialIndex: index,
              disableInteractions: true,
            );
          },
          childCount: _otherPosts.length,
        ),
      ),
    ];
  }

  /// 保存済み投稿グリッドのスライバーリスト
  List<Widget> _buildSavedPostsGridSlivers() {
    if (_savedPosts.isEmpty) {
      return [
        const SliverFillRemaining(
          child: Center(
            child: Text(
              '保存済みの投稿がありません',
              style: TextStyle(color: Colors.white54, fontSize: 14),
            ),
          ),
        ),
      ];
    }

    return [
      SliverGrid(
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3,
          childAspectRatio: 1,
          crossAxisSpacing: 1,
          mainAxisSpacing: 1,
        ),
        delegate: SliverChildBuilderDelegate(
          (context, index) {
            final post = _savedPosts[index];
            return ProfilePostGridItem(
              post: post,
              allPosts: _savedPosts,
              initialIndex: index,
              disableInteractions: true,
            );
          },
          childCount: _savedPosts.length,
        ),
      ),
    ];
  }
}

/// タブバーをスクロール時に上部に固定するためのデリゲート
class _TabBarDelegate extends SliverPersistentHeaderDelegate {
  final Widget child;

  _TabBarDelegate({required this.child});

  @override
  double get minExtent => 40;

  @override
  double get maxExtent => 40;

  @override
  Widget build(
      BuildContext context, double shrinkOffset, bool overlapsContent) {
    return Container(
      color: const Color(0xFF121212),
      child: child,
    );
  }

  @override
  bool shouldRebuild(covariant _TabBarDelegate oldDelegate) => true;
}

import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../services/user_service.dart';
import '../services/post_service.dart';
import '../services/audio_player_service.dart';
import '../models/user_model.dart';
import '../models/post_model.dart';
import '../utils/test_data.dart';
import '../widgets/profile_widgets.dart';
import 'settings_screen.dart';
import 'post_detail_screen.dart';
import 'follow_list_screen.dart';

/// プロフィール画面（自分）
class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> with SingleTickerProviderStateMixin {
  final UserService _userService = UserService();
  final PostService _postService = PostService();
  final AudioPlayerService _audioService = AudioPlayerService();
  late TabController _tabController;

  // ユーザーデータ
  UserModel? _userData;
  bool _isLoading = true;

  // 保存済み投稿
  List<PostModel> _savedPosts = [];

  // 投稿
  List<PostModel> _otherPosts = [];

  int get _tracksCount => _otherPosts.length;
  int get _followersCount => _userData?.followersCount ?? 0;
  int get _followingCount => _userData?.followingCount ?? 0;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(() {
      if (_tabController.index == 1) {
        _loadSavedPosts();
      }
      setState(() {});
    });
    _loadUserData();
    _loadUserPosts();
    _loadSavedPosts();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _audioService.stop();
    super.dispose();
  }

  /// ユーザーデータを読み込み
  Future<void> _loadUserData() async {
    final currentUser = FirebaseAuth.instance.currentUser;

    // Web開発用：Firebase認証がない場合はダミーデータを使用
    if (currentUser == null) {
      setState(() {
        _isLoading = false;
      });
      return;
    }

    try {
      final userData = await _userService.getUser(currentUser.uid);
      if (mounted) {
        setState(() {
          _userData = userData;
          _isLoading = false;
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

  /// ユーザーの投稿を読み込み（今日の投稿と今日以外の投稿）
  Future<void> _loadUserPosts() async {
    final currentUser = FirebaseAuth.instance.currentUser;
    final userId = currentUser?.uid ?? 'test_user_temp';

    try {
      final otherPosts = await _postService.getPostsExcludingToday(userId, limit: 50);

      if (mounted) {
        setState(() {
          _otherPosts = otherPosts;
        });
      }
    } catch (e) {
      print('ユーザー投稿の読み込みエラー: $e');
    }
  }


  /// 保存済み投稿を読み込み
  Future<void> _loadSavedPosts() async {
    final currentUser = FirebaseAuth.instance.currentUser;

    // ダミーユーザーの場合はTestDataから保存済み投稿を読み込み
    if (currentUser == null) {
      try {
        const userId = 'test_user_temp';

        // TestDataから保存済み投稿IDリストを取得
        final savedPostIds = await TestData.getSavedPosts(userId);

        print('🔍 保存済み投稿ID: $savedPostIds');

        if (savedPostIds.isEmpty) {
          print('⚠️ 保存済み投稿が0件です');
          if (mounted) {
            setState(() {
              _savedPosts = [];
            });
          }
          return;
        }

        // Firestoreから投稿を取得
        final firestorePosts = await _postService.getPosts(limit: 50);

        // TestDataの投稿も取得
        final testPosts = TestData.generateTestPosts();

        // すべての投稿を結合
        final allPosts = [...firestorePosts, ...testPosts];

        print('📦 全投稿数: ${allPosts.length}');
        print('📋 投稿ID一覧: ${allPosts.map((p) => p.postId).toList()}');

        // 保存済み投稿のみをフィルタリング
        final savedPosts = allPosts
            .where((post) => savedPostIds.contains(post.postId))
            .toList();

        print('✅ フィルタリング後の保存済み投稿数: ${savedPosts.length}');

        if (mounted) {
          setState(() {
            _savedPosts = savedPosts;
          });
        }
      } catch (e) {
        print('保存済み投稿の読み込みエラー: $e');
      }
      return;
    }

    try {
      // ユーザーデータを取得して保存済み投稿IDリストを取得
      final userData = await _userService.getUser(currentUser.uid);
      if (userData == null || userData.savedPosts.isEmpty) {
        if (mounted) {
          setState(() {
            _savedPosts = [];
          });
        }
        return;
      }

      // 保存済み投稿IDから投稿データを並列取得
      final futures = userData.savedPosts.map((postId) => _postService.getPost(postId)).toList();
      final results = await Future.wait(futures);
      final posts = results.whereType<PostModel>().toList();

      if (mounted) {
        setState(() {
          _savedPosts = posts;
        });
      }
    } catch (e) {
      print('保存済み投稿の読み込みエラー: $e');
    }
  }


  /// 投稿を削除
  Future<void> _deletePost(PostModel post) async {
    try {
      await _postService.deletePost(post.postId);
      if (mounted) {
        setState(() {
          _otherPosts.removeWhere((p) => p.postId == post.postId);
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('削除に失敗しました')),
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
          child: CircularProgressIndicator(color: Colors.white),
        ),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      body: SafeArea(
        child: NestedScrollView(
          headerSliverBuilder: (context, innerBoxIsScrolled) {
            return [
              // ヘッダー
              SliverToBoxAdapter(child: _buildHeader()),
              // プロフィール情報
              SliverToBoxAdapter(child: _buildProfileInfo()),
              // タブ切り替え（スクロール時に上に固定）
              SliverPersistentHeader(
                pinned: true,
                delegate: _TabBarDelegate(
                  child: _buildTabSelector(),
                ),
              ),
            ];
          },
          body: TabBarView(
            controller: _tabController,
            children: [
              _buildPostsGridScrollable(),
              _buildSavedPostsGridScrollable(),
            ],
          ),
        ),
      ),
    );
  }

  /// ヘッダー（ユーザーID + 設定アイコン）
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
          // 設定アイコン（右端）
          Positioned(
            right: 0,
            top: 0,
            bottom: 0,
            child: IconButton(
              icon: const Icon(Icons.settings_outlined, color: Colors.white),
              onPressed: () async {
                await Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const SettingsScreen()),
                );
                // 設定画面から戻ったらデータを再読み込み
                _loadUserData();
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
    final bio = _userData?.bio;
    final profileImageUrl = _userData?.profileImageUrl;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 27, vertical: 16),
      child: Column(
        children: [
          // ユーザー情報行
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 左側: 名前とユーザーID
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
                    if (bio != null && bio.isNotEmpty) ...[
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
              // 右側: プロフィール画像
              Container(
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
            ],
          ),

          const SizedBox(height: 16),

          // 統計情報
          Row(
            children: [
              ProfileStatItem(count: '$_tracksCount', label: 'Tracks'),
              const SizedBox(width: 32),
              GestureDetector(
                onTap: () {
                  final userId = FirebaseAuth.instance.currentUser?.uid;
                  if (userId != null) {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => FollowListScreen(
                          userId: userId,
                          showFollowers: true,
                        ),
                      ),
                    );
                  }
                },
                child: ProfileStatItem(count: '$_followersCount', label: 'Followers'),
              ),
              const SizedBox(width: 32),
              GestureDetector(
                onTap: () {
                  final userId = FirebaseAuth.instance.currentUser?.uid;
                  if (userId != null) {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => FollowListScreen(
                          userId: userId,
                          showFollowers: false,
                        ),
                      ),
                    );
                  }
                },
                child: ProfileStatItem(count: '$_followingCount', label: 'Following'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// タブ切り替え
  Widget _buildTabSelector() {
    return Container(
      height: 40,
      child: Row(
        children: [
          // グリッドタブ
          Expanded(
            child: GestureDetector(
              onTap: () => _tabController.animateTo(0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Icon(
                    Icons.grid_view,
                    color: _tabController.index == 0 ? Colors.white : Colors.grey,
                    size: 24,
                  ),
                  const SizedBox(height: 4),
                  // インジケーター（短い横棒）
                  Container(
                    width: 60,
                    height: 2,
                    color: _tabController.index == 0
                        ? Colors.white
                        : Colors.transparent,
                  ),
                ],
              ),
            ),
          ),
          // 保存タブ
          Expanded(
            child: GestureDetector(
              onTap: () => _tabController.animateTo(1),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Container(
                    width: 25,
                    height: 25,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color:
                            _tabController.index == 1 ? Colors.white : Colors.grey,
                        width: 1.5,
                      ),
                    ),
                    child: Icon(
                      Icons.add,
                      color: _tabController.index == 1 ? Colors.white : Colors.grey,
                      size: 16,
                    ),
                  ),
                  const SizedBox(height: 4),
                  // インジケーター（短い横棒）
                  Container(
                    width: 60,
                    height: 2,
                    color: _tabController.index == 1
                        ? Colors.white
                        : Colors.transparent,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 投稿グリッド（スクロール可能、TabBarView内用）
  Widget _buildPostsGridScrollable() {
    if (_otherPosts.isEmpty) {
      return const Center(
        child: Text(
          '投稿がありません',
          style: TextStyle(color: Colors.white54, fontSize: 14),
        ),
      );
    }

    return GridView.builder(
      padding: EdgeInsets.zero,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        childAspectRatio: 131 / 192,
        crossAxisSpacing: 0,
        mainAxisSpacing: 5,
      ),
      itemCount: _otherPosts.length,
      itemBuilder: (context, index) {
        final post = _otherPosts[index];
        return ProfilePostGridItem(
          post: post,
          allPosts: _otherPosts,
          initialIndex: index,
          onDelete: () => _deletePost(post),
          disableInteractions: true,
        );
      },
    );
  }



  /// 保存済み投稿グリッド（スクロール可能、TabBarView内用）
  Widget _buildSavedPostsGridScrollable() {
    if (_savedPosts.isEmpty) {
      return const Center(
        child: Text(
          '保存済みの投稿がありません',
          style: TextStyle(color: Colors.white54, fontSize: 14),
        ),
      );
    }

    return GridView.builder(
      padding: EdgeInsets.zero,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        childAspectRatio: 1,
        crossAxisSpacing: 1,
        mainAxisSpacing: 1,
      ),
      itemCount: _savedPosts.length,
      itemBuilder: (context, index) {
        final post = _savedPosts[index];
        return _buildSavedPostItem(post);
      },
    );
  }

  /// 保存済み投稿アイテム（アルバムアートのみ）
  Widget _buildSavedPostItem(PostModel post) {
    final albumArt = post.track.albumImageUrl;

    return GestureDetector(
      onTap: () {
        // 投稿詳細画面に遷移
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => PostDetailScreen(post: post),
          ),
        );
      },
      child: Container(
        decoration: BoxDecoration(
          color: Colors.grey[800],
        ),
        child: albumArt.isNotEmpty
            ? CachedNetworkImage(
                imageUrl: albumArt,
                fit: BoxFit.cover,
                errorWidget: (context, url, error) {
                  return const Icon(
                    Icons.album,
                    size: 50,
                    color: Colors.white54,
                  );
                },
              )
            : const Icon(
                Icons.album,
                size: 50,
                color: Colors.white54,
              ),
      ),
    );
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
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    return Container(
      color: const Color(0xFF121212),
      child: child,
    );
  }

  @override
  bool shouldRebuild(covariant _TabBarDelegate oldDelegate) => true;
}

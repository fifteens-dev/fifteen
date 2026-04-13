import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../services/user_service.dart';
import '../services/post_service.dart';
import '../services/audio_player_service.dart';
import '../models/user_model.dart';
import '../models/post_model.dart';
import '../widgets/profile_widgets.dart';
import 'settings_screen.dart';
import 'post_detail_screen.dart';
import 'follow_list_screen.dart';
import '../widgets/common/app_toast.dart';

/// プロフィール画面（自分）
class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => ProfileScreenState();
}

class ProfileScreenState extends State<ProfileScreen> with SingleTickerProviderStateMixin {
  final UserService _userService = UserService();
  final PostService _postService = PostService();
  final AudioPlayerService _audioService = AudioPlayerService();
  late TabController _tabController;
  final ScrollController _scrollController = ScrollController();

  // ユーザーデータ
  UserModel? _userData;
  bool _isLoading = true;

  // 保存済み投稿
  List<PostModel> _savedPosts = [];

  // 投稿（ページネーション）
  List<PostModel> _otherPosts = [];
  DocumentSnapshot? _lastPostDoc;
  bool _hasMorePosts = true;
  bool _isLoadingMore = false;

  int get _tracksCount => _otherPosts.length;
  int get _followersCount => _userData?.followersCount ?? 0;
  int get _followingCount => _userData?.followingCount ?? 0;

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
    _scrollController.addListener(_onScroll);
    _loadUserData();
    _loadUserPosts();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _scrollController.dispose();
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
      print('[ProfileScreen] _loadUserData: fetching uid=${currentUser.uid}');
      final userData = await _userService.getUser(currentUser.uid);
      print('[ProfileScreen] _loadUserData: success name=${userData?.name} username=${userData?.username}');
      if (mounted) {
        setState(() {
          _userData = userData;
          _isLoading = false;
        });
      }
    } catch (e) {
      print('[ProfileScreen] _loadUserData: error=$e');
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  /// ユーザーの投稿を読み込み（初回）
  /// [limit] 起動時は9件、リフレッシュ時は20件
  Future<void> _loadUserPosts({int limit = 9}) async {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) return;

    try {
      print('[ProfileScreen] _loadUserPosts: fetching uid=${currentUser.uid}');
      final result = await _postService.getPostsByUserIdPaged(
        currentUser.uid,
        limit: limit,
      );
      print('[ProfileScreen] _loadUserPosts: success count=${result.posts.length} hasMore=${result.hasMore}');

      if (mounted) {
        setState(() {
          _otherPosts = result.posts;
          _lastPostDoc = result.lastDoc;
          _hasMorePosts = result.hasMore;
        });
      }
    } catch (e) {
      print('[ProfileScreen] _loadUserPosts: error=$e');
    }
  }

  /// スクロール末尾付近で追加取得
  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final pos = _scrollController.position;
    if (pos.pixels >= pos.maxScrollExtent - 300) {
      _loadMorePosts();
    }
  }

  /// 追加投稿を読み込み（2段階：最初の9件を即表示、残り11件をバックグラウンドで追加）
  Future<void> _loadMorePosts() async {
    if (_isLoadingMore || !_hasMorePosts || _lastPostDoc == null) return;
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) return;

    setState(() => _isLoadingMore = true);

    try {
      // 第1段階：9件を取得して即表示
      final firstResult = await _postService.getPostsByUserIdPaged(
        currentUser.uid,
        limit: 9,
        startAfter: _lastPostDoc,
      );

      if (!mounted) return;
      setState(() {
        _otherPosts.addAll(firstResult.posts);
        _lastPostDoc = firstResult.lastDoc;
        _hasMorePosts = firstResult.hasMore;
        // まだ続きがある場合はスピナーを維持
        if (!firstResult.hasMore) _isLoadingMore = false;
      });

      // 第2段階：続きがあれば残り11件をバックグラウンドで取得
      if (firstResult.hasMore && firstResult.lastDoc != null) {
        final secondResult = await _postService.getPostsByUserIdPaged(
          currentUser.uid,
          limit: 11,
          startAfter: firstResult.lastDoc,
        );

        if (mounted) {
          setState(() {
            _otherPosts.addAll(secondResult.posts);
            _lastPostDoc = secondResult.lastDoc;
            _hasMorePosts = secondResult.hasMore;
            _isLoadingMore = false;
          });
        }
      }
    } catch (e) {
      print('追加投稿の読み込みエラー: $e');
      if (mounted) setState(() => _isLoadingMore = false);
    }
  }


  /// 保存済み投稿を読み込み
  Future<void> _loadSavedPosts() async {
    final currentUser = FirebaseAuth.instance.currentUser;

    if (currentUser == null) return;

    try {
      // savedByUserIds フィールドを使った単一クエリで取得
      final posts = await _postService.getPostsSavedByUser(currentUser.uid);

      if (mounted) {
        setState(() {
          _savedPosts = posts;
        });
      }
    } catch (e) {
      print('保存済み投稿の読み込みエラー: $e');
    }
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
    print('[ProfileScreen] refresh started');
    await Future.wait([
      _loadUserData(),
      _loadUserPosts(limit: 20),
    ]);
    print('[ProfileScreen] refresh completed');
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
        AppToast.show(context, '削除に失敗しました');
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

    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      body: SafeArea(
        child: Column(
          children: [
            // ユーザーネームバー（固定）
            _buildHeader(),
            // リフレッシュ＋スクロールエリア（単一CustomScrollViewで統合）
            Expanded(
              child: CustomScrollView(
                controller: _scrollController,
                physics: const AlwaysScrollableScrollPhysics(
                  parent: BouncingScrollPhysics(),
                ),
                slivers: [
                  CupertinoSliverRefreshControl(
                    onRefresh: _refresh,
                  ),
                  // プロフィール情報
                  SliverToBoxAdapter(child: _buildProfileInfo()),
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
              const SizedBox(width: 20),
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

  /// タブ切り替え（スライドインジケーター付き）
  Widget _buildTabSelector() {
    const indicatorWidth = 60.0;
    const indicatorHeight = 2.0;

    return AnimatedBuilder(
      animation: _tabController.animation!,
      builder: (context, _) {
        // スワイプ中も含め 0.0〜1.0 の連続値
        final t = _tabController.animation!.value.clamp(0.0, 1.0);

        // アイコン色：スワイプ量に応じて白⇔グレーを補間
        final color0 = Color.lerp(Colors.grey, Colors.white, 1.0 - t)!;
        final color1 = Color.lerp(Colors.grey, Colors.white, t)!;

        return LayoutBuilder(
          builder: (context, constraints) {
            final totalWidth = constraints.maxWidth;
            final tabWidth = totalWidth / 2;
            // インジケーターはそれぞれのタブ中央に配置
            final indicatorLeft = (tabWidth - indicatorWidth) / 2 + t * tabWidth;

            return Stack(
              children: [
                // タブボタン
                SizedBox(
                  height: 40,
                  child: Row(
                    children: [
                      // グリッドタブ
                      Expanded(
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: () => _tabController.animateTo(0),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              Icon(Icons.grid_view, color: color0, size: 25),
                              const SizedBox(height: 4 + indicatorHeight),
                            ],
                          ),
                        ),
                      ),
                      // 保存タブ
                      Expanded(
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: () => _tabController.animateTo(1),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              Container(
                                width: 26,
                                height: 26,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  border: Border.all(color: color1, width: 1.5),
                                ),
                                child: Icon(Icons.add, color: color1, size: 17),
                              ),
                              const SizedBox(height: 4 + indicatorHeight),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                // スライドするインジケーターバー
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
          mainAxisSpacing: 8,
        ),
        delegate: SliverChildBuilderDelegate(
          (context, index) {
            final post = _otherPosts[index];
            return ProfilePostGridItem(
              post: post,
              allPosts: _otherPosts,
              initialIndex: index,
              onDelete: () => _deletePost(post),
              disableInteractions: true,
            );
          },
          childCount: _otherPosts.length,
        ),
      ),
      if (_isLoadingMore)
        const SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Center(
              child: CupertinoActivityIndicator(
                color: Colors.white54,
                radius: 12,
              ),
            ),
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
          (context, index) => _buildSavedPostItem(_savedPosts[index]),
          childCount: _savedPosts.length,
        ),
      ),
    ];
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

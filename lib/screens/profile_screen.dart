import 'package:flutter/material.dart';
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

/// プロフィール画面（自分）
class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final UserService _userService = UserService();
  final PostService _postService = PostService();
  final AudioPlayerService _audioService = AudioPlayerService();
  int _selectedTabIndex = 0; // 0: グリッド, 1: 保存

  // ユーザーデータ
  UserModel? _userData;
  bool _isLoading = true;

  // 保存済み投稿
  List<PostModel> _savedPosts = [];

  // 今日の投稿
  List<PostModel> _todaysPosts = [];

  // 今日以外の投稿
  List<PostModel> _otherPosts = [];

  // 各カードのプレビューURLキャッシュ
  final Map<String, String> _previewUrlCache = {};

  final int _tracksCount = 18;
  final int _followersCount = 87;
  final int _followingCount = 89;

  @override
  void initState() {
    super.initState();
    _loadUserData();
    _loadUserPosts();
    _loadSavedPosts();
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
      // 今日の投稿を取得
      final todaysPosts = await _postService.getTodaysPosts(userId);

      // 今日以外の投稿を取得
      final otherPosts = await _postService.getPostsExcludingToday(userId, limit: 50);

      if (mounted) {
        setState(() {
          _todaysPosts = todaysPosts;
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

      // 保存済み投稿IDから投稿データを取得
      final List<PostModel> posts = [];
      for (final postId in userData.savedPosts) {
        final post = await _postService.getPost(postId);
        if (post != null) {
          posts.add(post);
        }
      }

      if (mounted) {
        setState(() {
          _savedPosts = posts;
        });
      }
    } catch (e) {
      print('保存済み投稿の読み込みエラー: $e');
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
        child: Column(
          children: [
            // ヘッダー
            _buildHeader(),

            // メインコンテンツ
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  children: [
                    // プロフィール情報
                    _buildProfileInfo(),

                    // 今日の楽曲カード
                    _buildTodaysTrack(),

                    const SizedBox(height: 16),

                    // タブ切り替え
                    _buildTabSelector(),

                    // タブに応じたコンテンツ表示
                    _selectedTabIndex == 0
                        ? _buildPostsGrid()
                        : _buildSavedPostsGrid(),
                  ],
                ),
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
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // 戻るボタン
          IconButton(
            icon: const Icon(Icons.arrow_back, color: Colors.white),
            onPressed: () => Navigator.pop(context),
          ),
          // ユーザーID
          Text(
            username,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.w800,
            ),
          ),
          // 設定アイコン
          IconButton(
            icon: const Icon(Icons.settings_outlined, color: Colors.white),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const SettingsScreen()),
              );
            },
          ),
        ],
      ),
    );
  }

  /// プロフィール情報セクション
  Widget _buildProfileInfo() {
    final displayName = _userData?.name ?? '名前未設定';
    final bio = 'aoyama'; // TODO: UserModelにbioフィールドを追加
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
                    const SizedBox(height: 4),
                    Text(
                      bio,
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.7),
                        fontSize: 12,
                      ),
                    ),
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
                  child: profileImageUrl != null
                      ? Image.network(
                          profileImageUrl,
                          width: 65,
                          height: 65,
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) {
                            return Icon(
                              Icons.person,
                              size: 40,
                              color: Colors.grey[600],
                            );
                          },
                        )
                      : Icon(
                          Icons.person,
                          size: 40,
                          color: Colors.grey[600],
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
              ProfileStatItem(count: '$_followersCount', label: 'Followers'),
              const SizedBox(width: 32),
              ProfileStatItem(count: '$_followingCount', label: 'Following'),
            ],
          ),
        ],
      ),
    );
  }


  /// 今日の楽曲カード（スクロール可能なリスト表示）
  Widget _buildTodaysTrack() {
    // 今日の投稿がない場合は何も表示しない
    if (_todaysPosts.isEmpty) {
      return const SizedBox.shrink();
    }

    // 最大5枚まで表示
    final displayPosts = _todaysPosts.take(5).toList();

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 見出し
          const Padding(
            padding: EdgeInsets.only(left: 4, bottom: 12),
            child: Text(
              '今日の楽曲',
              style: TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          // スクロール可能な楽曲リスト
          SizedBox(
            height: 300,
            child: ListView.builder(
              itemCount: displayPosts.length,
              itemBuilder: (context, index) {
                return Padding(
                  padding: EdgeInsets.only(
                    bottom: index < displayPosts.length - 1 ? 8 : 0,
                  ),
                  child: TodaysTrackCard(
                    post: displayPosts[index],
                    audioService: _audioService,
                    previewUrlCache: _previewUrlCache,
                  ),
                );
              },
            ),
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
              onTap: () => setState(() => _selectedTabIndex = 0),
              child: Container(
                decoration: BoxDecoration(
                  border: Border(
                    bottom: BorderSide(
                      color: _selectedTabIndex == 0
                          ? Colors.white
                          : Colors.transparent,
                      width: 2,
                    ),
                  ),
                ),
                child: Icon(
                  Icons.grid_view,
                  color: _selectedTabIndex == 0 ? Colors.white : Colors.grey,
                  size: 24,
                ),
              ),
            ),
          ),
          // 保存タブ
          Expanded(
            child: GestureDetector(
              onTap: () {
                setState(() => _selectedTabIndex = 1);
                // 保存タブを選択したときに保存済み投稿を再読み込み
                _loadSavedPosts();
              },
              child: Container(
                decoration: BoxDecoration(
                  border: Border(
                    bottom: BorderSide(
                      color: _selectedTabIndex == 1
                          ? Colors.white
                          : Colors.transparent,
                      width: 2,
                    ),
                  ),
                ),
                child: Container(
                  width: 25,
                  height: 25,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color:
                          _selectedTabIndex == 1 ? Colors.white : Colors.grey,
                      width: 1.5,
                    ),
                  ),
                  child: Icon(
                    Icons.add,
                    color: _selectedTabIndex == 1 ? Colors.white : Colors.grey,
                    size: 16,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 投稿グリッド（今日の楽曲を除外）
  Widget _buildPostsGrid() {
    // 投稿がない場合は空のメッセージを表示
    // _otherPosts は既にFirestoreレベルで今日以外の投稿のみを取得済み
    if (_otherPosts.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Text(
            '投稿がありません',
            style: TextStyle(
              color: Colors.white54,
              fontSize: 14,
            ),
          ),
        ),
      );
    }

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.symmetric(vertical: 8),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        childAspectRatio: 131 / 200, // 185 → 200に変更してオーバーフロー解消
        crossAxisSpacing: 0,
        mainAxisSpacing: 5,
      ),
      itemCount: _otherPosts.length,
      itemBuilder: (context, index) {
        final post = _otherPosts[index];
        return ProfilePostGridItem(post: post);
      },
    );
  }



  /// 保存済み投稿グリッド（アルバムアートのみ表示）
  Widget _buildSavedPostsGrid() {
    if (_savedPosts.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Text(
            '保存済みの投稿がありません',
            style: TextStyle(
              color: Colors.white54,
              fontSize: 14,
            ),
          ),
        ),
      );
    }

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.all(0),
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
            ? Image.network(
                albumArt,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) {
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

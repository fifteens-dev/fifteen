import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/user_model.dart';
import '../models/post_model.dart';
import '../services/user_service.dart';
import '../services/post_service.dart';
import '../services/audio_player_service.dart';
import '../widgets/profile_widgets.dart';

/// プロフィール画面（他人）
/// Figmaデザインに基づいた他のユーザーのプロフィール画面
class OtherUserProfileScreen extends StatefulWidget {
  final String userId; // 表示するユーザーのID

  const OtherUserProfileScreen({
    super.key,
    required this.userId,
  });

  @override
  State<OtherUserProfileScreen> createState() => _OtherUserProfileScreenState();
}

class _OtherUserProfileScreenState extends State<OtherUserProfileScreen> {
  final UserService _userService = UserService();
  final PostService _postService = PostService();
  final AudioPlayerService _audioService = AudioPlayerService();

  UserModel? _userData;
  UserModel? _currentUser;
  List<PostModel> _todaysPosts = [];  // 今日の投稿
  List<PostModel> _otherPosts = [];   // 今日以外の投稿
  bool _isLoading = true;
  bool _isFollowing = false;

  // プレビューURLキャッシュ（投稿IDをキーとする）
  final Map<String, String> _previewUrlCache = {};

  // ダミーユーザー用のフォロワー数オーバーライド
  int? _followerCountOverride;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  /// データを読み込み
  Future<void> _loadData() async {
    try {
      // 表示するユーザーのデータを取得
      final userData = await _userService.getUser(widget.userId);

      // 現在のユーザーのデータを取得
      final currentUserId = FirebaseAuth.instance.currentUser?.uid;
      UserModel? currentUser;
      if (currentUserId != null) {
        currentUser = await _userService.getUser(currentUserId);
      }

      // ユーザーの投稿を取得（今日と今日以外を分けて取得）
      final todaysPosts = await _postService.getTodaysPosts(widget.userId);
      final otherPosts = await _postService.getPostsExcludingToday(widget.userId, limit: 50);

      if (mounted) {
        // ダミーユーザーかどうかを判定
        const dummyUsernames = ['momo.hirai', 'mina.myoi', 'm.by__sana'];
        final isDummyUser = dummyUsernames.contains(userData?.username ?? '');

        setState(() {
          _userData = userData;
          _currentUser = currentUser;
          _todaysPosts = todaysPosts;
          _otherPosts = otherPosts;
          _isFollowing = currentUser?.isFollowing(widget.userId) ?? false;
          _isLoading = false;

          // ダミーユーザーの場合は初期フォロワー数を設定
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

  /// フォロー/アンフォローを切り替え
  Future<void> _toggleFollow() async {
    print('🔄 toggleFollow called, current state: $_isFollowing');

    // ダミーユーザーのリスト（テスト用）
    const dummyUsernames = ['momo.hirai', 'mina.myoi', 'm.by__sana'];
    final currentUsername = _userData?.username ?? '';

    // ダミーユーザーの場合は、UIだけ変更（Firebase操作なし）
    if (dummyUsernames.contains(currentUsername)) {
      print('🎭 Dummy user detected: $currentUsername - UI only mode');
      setState(() {
        _isFollowing = !_isFollowing;

        // フォロワー数を増減
        if (_followerCountOverride == null) {
          _followerCountOverride = _userData?.followers.length ?? 0;
        }
        _followerCountOverride = _isFollowing
            ? (_followerCountOverride! + 1)
            : (_followerCountOverride! - 1);
      });
      print('✅ UI updated to: $_isFollowing (dummy user), followers: $_followerCountOverride');
      return;
    }

    // 以下、通常のフォロー処理（実際のユーザー）
    final currentUserId = FirebaseAuth.instance.currentUser?.uid;
    print('👤 currentUserId: $currentUserId');

    if (currentUserId == null) {
      print('❌ No authenticated user');

      // 認証されていない場合は、ダイアログを表示してログイン画面へ誘導
      if (mounted) {
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            backgroundColor: const Color(0xFF1E1E1E),
            title: const Text(
              '認証が必要です',
              style: TextStyle(color: Colors.white),
            ),
            content: const Text(
              'フォロー機能を使用するには、ログインが必要です。\n\nWeb環境では、電話番号認証画面で「00000000000」または「11111111111」を入力してください。',
              style: TextStyle(color: Colors.white70),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('キャンセル'),
              ),
              TextButton(
                onPressed: () {
                  Navigator.pop(context);
                  Navigator.pushNamed(context, '/');
                },
                child: const Text('ログイン画面へ'),
              ),
            ],
          ),
        );
      }
      return;
    }

    // 現在の状態を保存
    final previousState = _isFollowing;

    // 楽観的UI更新
    setState(() {
      _isFollowing = !_isFollowing;
    });
    print('✅ UI updated to: $_isFollowing');

    try {
      if (_isFollowing) {
        print('📤 Calling followUser...');
        await _userService.followUser(
          currentUserId: currentUserId,
          targetUserId: widget.userId,
        );
        print('✅ followUser completed');
      } else {
        print('📤 Calling unfollowUser...');
        await _userService.unfollowUser(
          currentUserId: currentUserId,
          targetUserId: widget.userId,
        );
        print('✅ unfollowUser completed');
      }

      // フォロー/アンフォローが成功したら、状態はそのまま維持
      // _loadData()は呼ばない（Firestoreインデックスエラーを回避）
      print('✅ Operation successful, state maintained');
    } catch (e) {
      // エラーが発生した場合は元に戻す
      print('❌ Error occurred: $e');
      if (mounted) {
        setState(() {
          _isFollowing = previousState;
        });
        print('🔙 Reverted to previous state: $_isFollowing');

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
          child: CircularProgressIndicator(color: Colors.white),
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
            // ヘッダー
            _buildHeader(),

            // メインコンテンツ
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  children: [
                    // プロフィール情報
                    _buildProfileInfo(),

                    const SizedBox(height: 16),

                    // フォロー・メッセージボタン
                    _buildActionButtons(),

                    const SizedBox(height: 16),

                    // 今日の楽曲（ダミーデータ）
                    _buildTodaysTrack(),

                    const SizedBox(height: 16),

                    // タブ切り替え
                    _buildTabSelector(),

                    // 投稿グリッド（ダミーデータ）
                    _buildPostsGrid(),
                  ],
                ),
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
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        children: [
          // 戻るボタン
          IconButton(
            icon: const Icon(Icons.arrow_back_ios, color: Colors.white),
            onPressed: () {
              Navigator.pop(context);
            },
          ),
          // ユーザーID（中央寄せ）
          Expanded(
            child: Center(
              child: Text(
                username,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ),
          // 右側のスペース（左右対称にするため）
          const SizedBox(width: 48),
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
      padding: const EdgeInsets.symmetric(horizontal: 27, vertical: 16),
      child: Column(
        children: [
          // ユーザー情報行
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 左側: 名前とbio
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
                          color: Colors.white.withOpacity(0.7),
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
                  child: profileImageUrl != null && profileImageUrl.isNotEmpty
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
              ProfileStatItem(
                count: '${_userData?.postsCount ?? 0}',
                label: 'Tracks',
              ),
              const SizedBox(width: 32),
              ProfileStatItem(
                count: '${_followerCountOverride ?? _userData?.followersCount ?? 0}',
                label: 'Followers',
              ),
              const SizedBox(width: 32),
              ProfileStatItem(
                count: '${_userData?.followingCount ?? 0}',
                label: 'Following',
              ),
            ],
          ),
        ],
      ),
    );
  }


  /// アクションボタン（フォロー）
  Widget _buildActionButtons() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 21),
      child: GestureDetector(
        onTap: _toggleFollow,
        child: Container(
          height: 30,
          decoration: BoxDecoration(
            color: _isFollowing ? const Color(0xFF0095F6) : Colors.transparent,
            border: Border.all(
              color: _isFollowing ? const Color(0xFF0095F6) : const Color(0xFF929292),
            ),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Center(
            child: Text(
              _isFollowing ? 'フォロー中' : 'フォロー',
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
            child: Container(
              decoration: const BoxDecoration(
                border: Border(
                  bottom: BorderSide(
                    color: Colors.white,
                    width: 2,
                  ),
                ),
              ),
              child: const Icon(
                Icons.grid_view,
                color: Colors.white,
                size: 24,
              ),
            ),
          ),
          // 保存タブ
          Expanded(
            child: Container(
              decoration: const BoxDecoration(
                border: Border(
                  bottom: BorderSide(
                    color: Colors.transparent,
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
                    color: Colors.grey,
                    width: 1.5,
                  ),
                ),
                child: const Icon(
                  Icons.add,
                  color: Colors.grey,
                  size: 16,
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
    // 投稿がない場合は空のメッセージ
    // _otherPosts は既にFirestoreレベルで今日以外の投稿のみを取得済み
    if (_otherPosts.isEmpty) {
      return const SizedBox.shrink();
    }

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.symmetric(vertical: 8),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        childAspectRatio: 131 / 200, // 185 → 200に変更してアイテムを縦長に
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

}

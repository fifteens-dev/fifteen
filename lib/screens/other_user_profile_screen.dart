import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:just_audio/just_audio.dart';
import '../models/user_model.dart';
import '../models/post_model.dart';
import '../services/user_service.dart';
import '../services/post_service.dart';
import '../services/audio_player_service.dart';
import '../services/itunes_search_service.dart';

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
  final ITunesSearchService _itunesService = ITunesSearchService();

  UserModel? _userData;
  UserModel? _currentUser;
  List<PostModel> _userPosts = [];
  bool _isLoading = true;
  bool _isFollowing = false;

  // 今日の楽曲のプレビューURL（キャッシュ）
  String? _todaysTrackPreviewUrl;

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

      // ユーザーの投稿を取得
      final userPosts = await _postService.getPostsByUserId(widget.userId);

      if (mounted) {
        // ダミーユーザーかどうかを判定
        const dummyUsernames = ['momo.hirai', 'mina.myoi', 'm.by__sana'];
        final isDummyUser = dummyUsernames.contains(userData?.username ?? '');

        setState(() {
          _userData = userData;
          _currentUser = currentUser;
          _userPosts = userPosts;
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
              _buildStatItem('${_userData?.postsCount ?? 0}', 'Tracks'),
              const SizedBox(width: 32),
              _buildStatItem(
                '${_followerCountOverride ?? _userData?.followersCount ?? 0}',
                'Followers',
              ),
              const SizedBox(width: 32),
              _buildStatItem('${_userData?.followingCount ?? 0}', 'Following'),
            ],
          ),
        ],
      ),
    );
  }

  /// 統計アイテム
  Widget _buildStatItem(String count, String label) {
    return Column(
      children: [
        Text(
          count,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
        Text(
          label,
          style: const TextStyle(
            color: Color(0xFF919191),
            fontSize: 12,
          ),
        ),
      ],
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

  /// 今日の楽曲カード
  Widget _buildTodaysTrack() {
    // 最初の投稿を表示
    final latestPost = _userPosts.isNotEmpty ? _userPosts.first : null;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 22),
      decoration: BoxDecoration(
        border: Border.all(color: const Color(0xFF464646)),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Padding(
        padding: const EdgeInsets.all(6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ラベル
            const Padding(
              padding: EdgeInsets.only(left: 8, top: 2, bottom: 8),
              child: Text(
                '今日の楽曲',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                ),
              ),
            ),
            // 楽曲情報
            Row(
              children: [
                // アルバムアート
                Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    color: Colors.grey[800],
                    borderRadius: BorderRadius.circular(3),
                  ),
                  child: latestPost != null &&
                          latestPost.track.albumImageUrl.isNotEmpty
                      ? ClipRRect(
                          borderRadius: BorderRadius.circular(3),
                          child: Image.network(
                            latestPost.track.albumImageUrl,
                            width: 80,
                            height: 80,
                            fit: BoxFit.cover,
                            errorBuilder: (context, error, stackTrace) {
                              return const Icon(
                                Icons.album,
                                size: 40,
                                color: Colors.white54,
                              );
                            },
                          ),
                        )
                      : const Icon(
                          Icons.album,
                          size: 40,
                          color: Colors.white54,
                        ),
                ),
                const SizedBox(width: 14),
                // 曲名とアーティスト
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        latestPost?.track.trackName ?? 'No tracks yet',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 24,
                          fontWeight: FontWeight.w600,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        latestPost?.track.artistName ?? '',
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 13,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                // 再生ボタンと時間
                if (latestPost != null)
                  Column(
                    children: [
                      StreamBuilder<PlayerState>(
                        stream: _audioService.playerStateStream,
                        builder: (context, snapshot) {
                          final isThisTrackPlaying = _todaysTrackPreviewUrl != null &&
                              _audioService.isPlayingUrl(_todaysTrackPreviewUrl!);
                          final isPaused = _audioService.isPaused;

                          return GestureDetector(
                            onTap: () async {
                              if (isThisTrackPlaying) {
                                // 再生中の場合は一時停止
                                _audioService.pause();
                              } else if (isPaused && _todaysTrackPreviewUrl != null) {
                                // 一時停止中の場合は再開
                                _audioService.resume();
                              } else {
                                // 停止中の場合は再生開始
                                String? urlToPlay = _todaysTrackPreviewUrl;

                                // preview URLがまだ取得されていない場合は取得
                                if (urlToPlay == null) {
                                  print('🍎 Fetching preview URL for ${latestPost.track.trackName}...');
                                  urlToPlay = await _itunesService.getPreviewUrl(
                                    trackName: latestPost.track.trackName,
                                    artistName: latestPost.track.artistName,
                                  );

                                  if (urlToPlay != null) {
                                    setState(() {
                                      _todaysTrackPreviewUrl = urlToPlay;
                                    });
                                    print('✅ Preview URL obtained and cached');
                                  } else {
                                    print('❌ Failed to obtain preview URL');
                                    return;
                                  }
                                }

                                _audioService.playPreview(urlToPlay);
                              }
                            },
                            child: Container(
                              width: 40,
                              height: 40,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: isThisTrackPlaying ? Colors.greenAccent : Colors.white,
                                  width: 2,
                                ),
                              ),
                              child: Icon(
                                isThisTrackPlaying ? Icons.pause : Icons.play_arrow,
                                color: isThisTrackPlaying ? Colors.greenAccent : Colors.white,
                                size: 24,
                              ),
                            ),
                          );
                        },
                      ),
                      const SizedBox(height: 8),
                      StreamBuilder<Duration>(
                        stream: _audioService.positionStream,
                        builder: (context, positionSnapshot) {
                          return StreamBuilder<Duration?>(
                            stream: _audioService.durationStream,
                            builder: (context, durationSnapshot) {
                              final duration = durationSnapshot.data;
                              final position = positionSnapshot.data ?? Duration.zero;

                              // 残り時間を計算
                              // durationがnullの場合は、iTunesプレビューのデフォルト長さ（30秒）を表示
                              final remaining = duration != null
                                  ? duration - position
                                  : const Duration(seconds: 30);

                              // フォーマット
                              final minutes = remaining.inMinutes;
                              final seconds = remaining.inSeconds % 60;
                              final timeText = '$minutes:${seconds.toString().padLeft(2, '0')}';

                              return Text(
                                timeText,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600,
                                ),
                              );
                            },
                          );
                        },
                      ),
                    ],
                  ),
              ],
            ),
          ],
        ),
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

  /// 投稿グリッド
  Widget _buildPostsGrid() {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.all(0),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        childAspectRatio: 131 / 185,
        crossAxisSpacing: 0,
        mainAxisSpacing: 5,
      ),
      itemCount: _userPosts.length,
      itemBuilder: (context, index) {
        final post = _userPosts[index];
        return _buildPostItem(post);
      },
    );
  }

  /// 投稿アイテム
  Widget _buildPostItem(PostModel post) {
    return Container(
      padding: const EdgeInsets.all(0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // アルバムアート
          AspectRatio(
            aspectRatio: 1,
            child: Container(
              margin: const EdgeInsets.all(0.5),
              decoration: BoxDecoration(
                color: Colors.grey[800],
                borderRadius: BorderRadius.circular(3),
              ),
              child: post.track.albumImageUrl.isNotEmpty
                  ? ClipRRect(
                      borderRadius: BorderRadius.circular(3),
                      child: Image.network(
                        post.track.albumImageUrl,
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) {
                          return const Icon(
                            Icons.album,
                            size: 50,
                            color: Colors.white54,
                          );
                        },
                      ),
                    )
                  : const Icon(
                      Icons.album,
                      size: 50,
                      color: Colors.white54,
                    ),
            ),
          ),
          // 曲名
          Padding(
            padding: const EdgeInsets.only(left: 6, top: 4),
            child: Text(
              post.track.trackName,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          // アーティスト名
          Padding(
            padding: const EdgeInsets.only(left: 6),
            child: Text(
              post.track.artistName,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 10,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          // 追加ボタン
          Padding(
            padding: const EdgeInsets.only(left: 6, top: 2),
            child: Container(
              width: 13,
              height: 13,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 1),
              ),
              child: const Icon(
                Icons.add,
                color: Colors.white,
                size: 10,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

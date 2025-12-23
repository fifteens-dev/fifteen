import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:just_audio/just_audio.dart';
import '../constants/app_colors.dart';
import '../services/user_service.dart';
import '../services/post_service.dart';
import '../services/spotify_service.dart';
import '../services/audio_player_service.dart';
import '../services/itunes_search_service.dart';
import '../models/user_model.dart';
import '../models/post_model.dart';
import '../utils/test_data.dart';
import 'settings_screen.dart';

/// プロフィール画面（自分）
class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final UserService _userService = UserService();
  final PostService _postService = PostService();
  final SpotifyService _spotifyService = SpotifyService();
  final AudioPlayerService _audioService = AudioPlayerService();
  final ITunesSearchService _itunesService = ITunesSearchService();
  int _selectedTabIndex = 0; // 0: グリッド, 1: 保存

  // ユーザーデータ
  UserModel? _userData;
  bool _isLoading = true;

  // 保存済み投稿
  List<PostModel> _savedPosts = [];

  final int _tracksCount = 18;
  final int _followersCount = 87;
  final int _followingCount = 89;

  // 今日の楽曲のアルバムアートワーク
  String? _todaysTrackAlbumArt;

  // 今日の楽曲のプレビューURL（キャッシュ）
  String? _todaysTrackPreviewUrl;

  @override
  void initState() {
    super.initState();
    _loadUserData();
    _loadAlbumArtworks();
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

  /// アルバムアートワークを読み込み
  Future<void> _loadAlbumArtworks() async {
    // 今日の楽曲のアルバムアートワークを取得
    try {
      final todaysTracks = await _spotifyService.searchTracks(
        'いとしのエリー サザンオールスターズ',
        limit: 1,
      );
      if (todaysTracks.isNotEmpty && mounted) {
        setState(() {
          _todaysTrackAlbumArt = todaysTracks.first.albumImageUrl;
        });
      }
    } catch (e) {
      print('今日の楽曲のアルバムアートワーク取得エラー: $e');
    }

    // 投稿グリッドの各楽曲のアルバムアートワークを取得
    for (int i = 0; i < _posts.length; i++) {
      final post = _posts[i];
      try {
        final searchQuery = '${post['trackName']} ${post['artistName']}';
        final tracks =
            await _spotifyService.searchTracks(searchQuery, limit: 1);

        if (tracks.isNotEmpty && mounted) {
          setState(() {
            _posts[i]['albumArt'] = tracks.first.albumImageUrl ?? '';
          });
        }
      } catch (e) {
        print('投稿 $i のアルバムアートワーク取得エラー: $e');
      }
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

  // ダミーの投稿データ
  final List<Map<String, String>> _posts = [
    {
      'trackName': 'Miss Luxury',
      'artistName': 'YZERR, LANA, JP THE WAVY, ¥ellow Bucks',
      'albumArt': '',
    },
    {
      'trackName': 'High Land(feat. Tiji Jojo, Vingo & YZERR)',
      'artistName': 'BAD HOP, Tiji Jojo, Vingo, YZERR',
      'albumArt': '',
    },
    {
      'trackName': 'かわいいだけじゃダメですか',
      'artistName': 'CUTIE STREET',
      'albumArt': '',
    },
    {
      'trackName': 'ヒロイン',
      'artistName': 'back number',
      'albumArt': '',
    },
    {
      'trackName': '愛のかたまり',
      'artistName': 'Kinki Kids',
      'albumArt': '',
    },
    {
      'trackName': 'ラブホテル',
      'artistName': 'クリープハイプ',
      'albumArt': '',
    },
  ];

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
              _buildStatItem('$_tracksCount', 'Tracks'),
              const SizedBox(width: 32),
              _buildStatItem('$_followersCount', 'Followers'),
              const SizedBox(width: 32),
              _buildStatItem('$_followingCount', 'Following'),
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

  /// 今日の楽曲カード
  Widget _buildTodaysTrack() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 22),
      decoration: BoxDecoration(
        border: Border.all(color: const Color(0xFF3C3C3C)),
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
                  child: _todaysTrackAlbumArt != null
                      ? ClipRRect(
                          borderRadius: BorderRadius.circular(3),
                          child: Image.network(
                            _todaysTrackAlbumArt!,
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
                      const Text(
                        'いとしのエリー',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 24,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'サザンオールスターズ',
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.8),
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
                // 再生ボタンと時間
                Column(
                  children: [
                    StreamBuilder<PlayerState>(
                      stream: _audioService.playerStateStream,
                      builder: (context, snapshot) {
                        final isThisTrackPlaying = _todaysTrackPreviewUrl !=
                                null &&
                            _audioService.isPlayingUrl(_todaysTrackPreviewUrl!);
                        final isPaused = _audioService.isPaused;

                        return GestureDetector(
                          onTap: () async {
                            if (isThisTrackPlaying) {
                              // 再生中の場合は一時停止
                              _audioService.pause();
                            } else if (isPaused &&
                                _todaysTrackPreviewUrl != null) {
                              // 一時停止中の場合は再開
                              _audioService.resume();
                            } else {
                              // 停止中の場合は再生開始
                              String? urlToPlay = _todaysTrackPreviewUrl;

                              // preview URLがまだ取得されていない場合は取得
                              if (urlToPlay == null) {
                                print(
                                    '🍎 Fetching preview URL for today\'s track...');
                                urlToPlay = await _itunesService.getPreviewUrl(
                                  trackName: 'いとしのエリー',
                                  artistName: 'サザンオールスターズ',
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
                                color: isThisTrackPlaying
                                    ? Colors.greenAccent
                                    : Colors.white,
                                width: 2,
                              ),
                            ),
                            child: Icon(
                              isThisTrackPlaying
                                  ? Icons.pause
                                  : Icons.play_arrow,
                              color: isThisTrackPlaying
                                  ? Colors.greenAccent
                                  : Colors.white,
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
                            final position =
                                positionSnapshot.data ?? Duration.zero;

                            // 残り時間を計算
                            // durationがnullの場合は、iTunesプレビューのデフォルト長さ（30秒）を表示
                            final remaining = duration != null
                                ? duration - position
                                : const Duration(seconds: 30);

                            // フォーマット
                            final minutes = remaining.inMinutes;
                            final seconds = remaining.inSeconds % 60;
                            final timeText =
                                '$minutes:${seconds.toString().padLeft(2, '0')}';

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
      itemCount: _posts.length,
      itemBuilder: (context, index) {
        final post = _posts[index];
        return _buildPostItem(post);
      },
    );
  }

  /// 投稿アイテム
  Widget _buildPostItem(Map<String, String> post) {
    final albumArt = post['albumArt'];

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
              child: albumArt != null && albumArt.isNotEmpty
                  ? ClipRRect(
                      borderRadius: BorderRadius.circular(3),
                      child: Image.network(
                        albumArt,
                        width: double.infinity,
                        height: double.infinity,
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
              post['trackName'] ?? '',
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
              post['artistName'] ?? '',
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

    return Container(
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
    );
  }
}

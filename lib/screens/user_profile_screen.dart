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
import '../models/track_model.dart';
import '../utils/test_data.dart';
import 'settings_screen.dart';
import 'post_detail_screen.dart';

/// プロフィール画面（他のユーザー）
class UserProfileScreen extends StatefulWidget {
  final String userId;
  final String? username; // オプション：ヘッダー表示用

  const UserProfileScreen({
    super.key,
    required this.userId,
    this.username,
  });

  @override
  State<UserProfileScreen> createState() => _UserProfileScreenState();
}

class _UserProfileScreenState extends State<UserProfileScreen> {
  final UserService _userService = UserService();
  final PostService _postService = PostService();
  final SpotifyService _spotifyService = SpotifyService();
  final AudioPlayerService _audioService = AudioPlayerService();
  final ITunesSearchService _itunesService = ITunesSearchService();

  // ユーザーデータ
  UserModel? _userData;
  bool _isLoading = true;

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
    _loadDummyPostsAlbumArt();
  }

  /// ユーザーデータを読み込み
  Future<void> _loadUserData() async {
    try {
      final userData = await _userService.getUser(widget.userId);
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
    final userId = widget.userId;

    try {
      // 今日の投稿を取得
      var todaysPosts = await _postService.getTodaysPosts(userId);

      // 今日の投稿がない場合はダミーデータを追加
      if (todaysPosts.isEmpty) {
        todaysPosts = _createDummyTodaysPost();

        // ダミーデータのアルバムアートをSpotifyから取得
        await _loadAlbumArtForDummyPost(todaysPosts);
      }

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

  /// ダミー投稿のアルバムアートを取得（今日の楽曲用）
  Future<void> _loadAlbumArtForDummyPost(List<PostModel> posts) async {
    for (int i = 0; i < posts.length; i++) {
      final post = posts[i];
      if (post.track.albumImageUrl.isEmpty) {
        try {
          final searchQuery = '${post.track.trackName} ${post.track.artistName}';
          final tracks = await _spotifyService.searchTracks(searchQuery, limit: 1);

          if (tracks.isNotEmpty && mounted) {
            final updatedTrack = post.track.copyWith(
              albumImageUrl: tracks.first.albumImageUrl,
            );
            posts[i] = post.copyWith(track: updatedTrack);
          }
        } catch (e) {
          print('ダミー投稿のアルバムアート取得エラー: $e');
        }
      }
    }
  }

  /// 投稿グリッドのダミーデータのアルバムアートを取得
  Future<void> _loadDummyPostsAlbumArt() async {
    for (int i = 0; i < _posts.length; i++) {
      final post = _posts[i];
      try {
        final searchQuery = '${post['trackName']} ${post['artistName']}';
        final tracks = await _spotifyService.searchTracks(searchQuery, limit: 1);

        if (tracks.isNotEmpty && mounted) {
          setState(() {
            _posts[i]['albumArt'] = tracks.first.albumImageUrl;
          });
        }
      } catch (e) {
        print('投稿グリッドのダミーデータのアルバムアート取得エラー: $e');
      }
    }
  }

  /// ダミーの今日の楽曲を作成
  List<PostModel> _createDummyTodaysPost() {
    return [
      PostModel(
        postId: 'dummy_today_post',
        userId: 'test_user_temp',
        username: 'taroooooda',
        track: TrackModel(
          trackId: 'dummy_track_1',
          trackName: 'いとしのエリー',
          artistName: 'サザンオールスターズ',
          albumImageUrl: '', // Spotifyから取得される
          previewUrl: null,
        ),
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      ),
    ];
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

                    // 投稿グリッド
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

  /// ヘッダー（ユーザーID）
  Widget _buildHeader() {
    final username = widget.username ?? _userData?.username ?? 'ユーザー名';

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
          // 右側スペース（設定アイコンの代わり）
          const SizedBox(width: 48),
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
                  child: _buildTodaysTrackCard(displayPosts[index], index == 0),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  /// 今日の楽曲カード（1枚）
  Widget _buildTodaysTrackCard(PostModel post, bool isTopCard) {
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: const Color(0xFF3C3C3C)),
        borderRadius: BorderRadius.circular(4),
        color: const Color(0xFF121212),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          children: [
            // アルバムアート
            Container(
              width: 60,
              height: 60,
              decoration: BoxDecoration(
                color: Colors.grey[800],
                borderRadius: BorderRadius.circular(4),
              ),
              child: post.track.albumImageUrl.isNotEmpty
                  ? ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: Image.network(
                        post.track.albumImageUrl,
                        width: 60,
                        height: 60,
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) {
                          return const Icon(
                            Icons.album,
                            size: 30,
                            color: Colors.white54,
                          );
                        },
                      ),
                    )
                  : const Icon(
                      Icons.album,
                      size: 30,
                      color: Colors.white54,
                    ),
            ),
            const SizedBox(width: 12),
            // 曲名とアーティスト
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    post.track.trackName,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    post.track.artistName,
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.7),
                      fontSize: 14,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            // 再生ボタンと時間（全てのカードに表示）
            _buildPlayButton(post),
          ],
        ),
      ),
    );
  }

  /// 再生ボタンと時間表示
  Widget _buildPlayButton(PostModel post) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        StreamBuilder<PlayerState>(
          stream: _audioService.playerStateStream,
          builder: (context, snapshot) {
            final previewUrl = _previewUrlCache[post.postId];
            final isThisTrackPlaying =
                previewUrl != null && _audioService.isPlayingUrl(previewUrl);
            final isPaused = _audioService.isPaused;

            return GestureDetector(
              onTap: () async {
                if (isThisTrackPlaying) {
                  // 再生中の場合は一時停止
                  _audioService.pause();
                } else if (isPaused && previewUrl != null) {
                  // 一時停止中の場合は再開
                  _audioService.resume();
                } else {
                  // 停止中の場合は再生開始
                  String? urlToPlay = previewUrl;

                  // preview URLがまだ取得されていない場合は取得
                  if (urlToPlay == null) {
                    print('🍎 Fetching preview URL for ${post.track.trackName}...');
                    urlToPlay = await _itunesService.getPreviewUrl(
                      trackName: post.track.trackName,
                      artistName: post.track.artistName,
                    );

                    if (urlToPlay != null) {
                      setState(() {
                        _previewUrlCache[post.postId] = urlToPlay!;
                      });
                      print('✅ Preview URL obtained and cached');
                    } else {
                      print('❌ Failed to obtain preview URL');
                      return;
                    }
                  }

                  // 再生開始（ループ再生は自動的に有効）
                  await _audioService.playPreview(urlToPlay);
                }
              },
              child: Container(
                width: 50,
                height: 50,
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
                  size: 28,
                ),
              ),
            );
          },
        ),
        const SizedBox(height: 4),
        StreamBuilder<Duration>(
          stream: _audioService.positionStream,
          builder: (context, positionSnapshot) {
            return StreamBuilder<Duration?>(
              stream: _audioService.durationStream,
              builder: (context, durationSnapshot) {
                final duration = durationSnapshot.data;
                final position = positionSnapshot.data ?? Duration.zero;

                // 残り時間を計算
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
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                );
              },
            );
          },
        ),
      ],
    );
  }

  /// 投稿グリッド
  Widget _buildPostsGrid() {
    // 実際の投稿データがある場合はそれを使用、なければダミーデータを使用
    final hasRealPosts = _otherPosts.isNotEmpty;

    if (hasRealPosts) {
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
        itemCount: _otherPosts.length,
        itemBuilder: (context, index) {
          final post = _otherPosts[index];
          return _buildPostItemFromModel(post);
        },
      );
    } else {
      // ダミーデータを使用
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
  }

  /// 投稿アイテム（PostModelから）
  Widget _buildPostItemFromModel(PostModel post) {
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
      ),
    );
  }

  /// 投稿アイテム（ダミーデータから）
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

}

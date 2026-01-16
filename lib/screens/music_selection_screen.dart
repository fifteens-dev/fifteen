import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import '../models/track_model.dart';
import '../models/vibe_topic_model.dart';
import '../services/spotify_service.dart';
import '../services/music_service_manager.dart';
import '../services/post_service.dart';
import '../services/vibe_topic_service.dart';
import '../services/lyrics_service.dart';
import '../utils/test_data.dart';
import '../utils/color_extractor.dart';
import 'post_preview_screen.dart';

/// 投稿用楽曲選択画面
class MusicSelectionScreen extends StatefulWidget {
  const MusicSelectionScreen({super.key});

  @override
  State<MusicSelectionScreen> createState() => _MusicSelectionScreenState();
}

class _MusicSelectionScreenState extends State<MusicSelectionScreen> {
  final TextEditingController _searchController = TextEditingController();
  final SpotifyService _spotifyService = SpotifyService();
  final MusicServiceManager _musicServiceManager = MusicServiceManager();
  final PostService _postService = PostService();
  final VibeTopicService _vibeTopicService = VibeTopicService();

  // 選択された楽曲
  TrackModel? _selectedTrack;

  // 今日のVibeお題
  VibeTopicModel? _todaysTopic;

  // タブ選択状態: 0 = おすすめ, 1 = My Playlist, 2 = 保存済み
  int _selectedTab = 0;

  // 表示モード: true = グリッド, false = リスト
  bool _isGridView = false;

  // カテゴリー選択状態: null = 未選択, 'vibe' = Vibe, 'emotion' = 感情
  String? _selectedCategoryType;

  // 選択されたVibeカテゴリー（例: 「ドライブで聴きたい曲」）
  String? _selectedVibeCategory;

  // 楽曲リスト（Spotify APIから取得）
  List<TrackModel> _tracks = [];

  // ローディング状態
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _loadInitialTracks();
    _loadTodaysTopic();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  /// 初期楽曲を読み込み（おすすめ = 日本の人気曲）
  Future<void> _loadInitialTracks() async {
    setState(() => _isLoading = true);

    try {
      // Spotify検索APIを使用（Recommendations APIの404エラーを回避）
      // 日本の人気曲を検索クエリで取得
      final searchQueries = [
        '日本TOP',
        'J-POP',
        '日本 音楽',
        'Japanese pop',
      ];

      List<TrackModel> tracks = [];

      // 各検索クエリを順番に試す
      for (final query in searchQueries) {
        try {
          print('🔍 Spotify検索API (クエリ: "$query") を試行中...');
          tracks = await _spotifyService.searchTracks(query, limit: 50);

          if (tracks.isNotEmpty) {
            print('✅ 取得成功: クエリ "$query" (${tracks.length}曲取得)');
            break;
          }
        } catch (e) {
          print('❌ クエリ "$query" での取得に失敗: $e');
          continue;
        }
      }

      // それでも失敗した場合は、デフォルトクエリを使用
      if (tracks.isEmpty) {
        print('⚠️ すべての方法が失敗。デフォルトクエリを使用...');
        tracks = await _spotifyService.searchTracks('J-POP 人気', limit: 50);
      }

      if (mounted) {
        setState(() {
          _tracks = tracks;
          _isLoading = false;
        });
      }
    } catch (e) {
      print('Error loading initial tracks: $e');
      if (mounted) {
        setState(() {
          _tracks = [];
          _isLoading = false;
        });
      }
    }
  }

  /// 今日のVibeお題を読み込み
  Future<void> _loadTodaysTopic() async {
    try {
      final topic = await _vibeTopicService.getTodaysTopic();
      if (mounted) {
        setState(() {
          _todaysTopic = topic;
        });
      }
    } catch (e) {
      print('Error loading today\'s topic: $e');
    }
  }

  /// My Playlistの楽曲を読み込み
  Future<void> _loadMyPlaylistTracks() async {
    setState(() => _isLoading = true);

    try {
      // 音楽サービスに連携している場合は、ユーザーのお気に入り楽曲を取得
      final isAuthenticated = await _musicServiceManager.isAuthenticated();

      List<TrackModel> tracks;
      if (isAuthenticated) {
        // 連携済み: お気に入り楽曲を取得
        tracks = await _musicServiceManager.getSavedTracks(limit: 50);

        // お気に入り楽曲が取得できなかった場合はフォールバック
        if (tracks.isEmpty) {
          print('お気に入り楽曲が見つかりませんでした。デフォルトの検索結果を表示します。');
          tracks = await _spotifyService.searchTracks('J-POP 人気', limit: 20);
        }
      } else {
        // 未連携: 人気のJ-POPを表示
        tracks = await _spotifyService.searchTracks('J-POP 人気', limit: 20);
      }

      if (mounted) {
        setState(() {
          _tracks = tracks;
          _isLoading = false;
        });
      }
    } catch (e) {
      print('Error loading my playlist tracks: $e');
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  /// 楽曲を検索
  Future<void> _searchTracks(String query) async {
    if (query.isEmpty) {
      _loadInitialTracks();
      return;
    }

    setState(() => _isLoading = true);

    try {
      final tracks = await _spotifyService.searchTracks(query, limit: 20);

      if (mounted) {
        setState(() {
          _tracks = tracks;
          _isLoading = false;
        });
      }
    } catch (e) {
      print('Error searching tracks: $e');
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  /// 保存済み曲を読み込み
  Future<void> _loadSavedTracks() async {
    setState(() => _isLoading = true);

    try {
      final currentUser = FirebaseAuth.instance.currentUser;
      final userId = currentUser?.uid ?? 'test_user_temp';

      // TestDataから保存済み投稿IDリストを取得
      final savedPostIds = await TestData.getSavedPosts(userId);

      if (savedPostIds.isEmpty) {
        if (mounted) {
          setState(() {
            _tracks = [];
            _isLoading = false;
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

      // 保存済み投稿のみをフィルタリング
      final savedPosts =
          allPosts.where((post) => savedPostIds.contains(post.postId)).toList();

      // 投稿から曲を抽出（重複を除外）
      final Map<String, TrackModel> uniqueTracks = {};
      for (final post in savedPosts) {
        uniqueTracks[post.track.trackId] = post.track;
      }

      final tracks = uniqueTracks.values.toList();

      if (mounted) {
        setState(() {
          _tracks = tracks;
          _isLoading = false;
        });
      }
    } catch (e) {
      print('Error loading saved tracks: $e');
      if (mounted) {
        setState(() {
          _tracks = [];
          _isLoading = false;
        });
      }
    }
  }

  /// 楽曲を選択
  void _toggleTrackSelection(TrackModel track) {
    // カテゴリーが選択されていない場合は何もしない
    if (_selectedCategoryType == null) {
      return;
    }

    setState(() {
      if (_selectedTrack?.trackId == track.trackId) {
        _selectedTrack = null;
      } else {
        _selectedTrack = track;
      }
    });
  }

  /// 次へ進む
  Future<void> _onNext() async {
    if (_selectedTrack == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('楽曲を選択してください'),
          backgroundColor: Color(0xFFE53935),
        ),
      );
      return;
    }

    // アルバムアートから色を事前抽出
    Color? gradientStart;
    Color? gradientEnd;

    try {
      print('🎨 楽曲選択時に色抽出を開始...');
      final imageUrl = _selectedTrack!.albumImageUrl;
      if (imageUrl.isNotEmpty) {
        final extractedColors = await ColorExtractor.extractGradientColors(imageUrl);
        gradientStart = extractedColors.$1;
        gradientEnd = extractedColors.$2;
        print('✅ 色抽出完了！投稿プレビュー画面に渡します');
      }
    } catch (e) {
      print('⚠️ 色抽出エラー: $e');
      // エラーが発生しても続行（PostPreviewScreenで再抽出）
    }

    // 歌詞を取得（バックグラウンドで開始、完了を待たない）
    print('🎵 楽曲選択時に歌詞取得をバックグラウンドで開始...');
    final lyricsService = LyricsService();
    final appleDevToken = dotenv.env['APPLE_MUSIC_DEVELOPER_TOKEN'] ?? '';

    final Future<LyricsData?> lyricsFuture = lyricsService.getLyrics(
      trackName: _selectedTrack!.trackName,
      artistName: _selectedTrack!.artistName,
      durationSeconds: null,
      appleDevToken: appleDevToken,
    ).then((lyricsData) {
      if (lyricsData != null) {
        print('✅ 歌詞取得完了: ${lyricsData.source}');
      } else {
        print('⚠️ 歌詞が見つかりませんでした');
      }
      return lyricsData;
    }).catchError((e) {
      print('⚠️ 歌詞取得エラー: $e');
      return null;
    });

    // 投稿プレビュー画面へ遷移（歌詞取得を待たない）
    if (mounted) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => PostPreviewScreen(
            track: _selectedTrack!,
            lyricsData: null, // nullを渡す
            lyricsFuture: lyricsFuture, // Futureを渡す
            isVibe: _selectedCategoryType == 'vibe',
            vibeTopicId: _todaysTopic?.topicId,
            preExtractedGradientStart: gradientStart,
            preExtractedGradientEnd: gradientEnd,
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      body: SafeArea(
        child: Column(
          children: [
            // ヘッダー
            _buildHeader(),

            // 検索バー
            _buildSearchBar(),

            // Vibe/感情選択ボタン
            _buildCategoryButtons(),

            // タブバー
            _buildTabBar(),

            // 区切り線
            Container(
              height: 1,
              color: const Color(0xFF2D2D2D),
            ),

            // 楽曲リスト or グリッド
            Expanded(
              child: Stack(
                children: [
                  // 楽曲リスト/グリッド
                  _isLoading
                      ? const Center(
                          child: CircularProgressIndicator(
                            color: Color(0xFF5D8FFF),
                          ),
                        )
                      : _tracks.isEmpty
                          ? const Center(
                              child: Text(
                                '楽曲が見つかりませんでした',
                                style: TextStyle(
                                  fontSize: 13,
                                  color: Color(0xFF9F9F9F),
                                ),
                              ),
                            )
                          : _isGridView
                              ? _buildTrackGrid()
                              : _buildTrackList(),

                  // カテゴリー未選択時のオーバーレイ
                  if (_selectedCategoryType == null)
                    Positioned.fill(
                      child: Container(
                        color: Colors.black.withOpacity(0.7),
                        child: const Center(
                          child: Text(
                            'VibeまたはEmotionを選択してください',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// ヘッダー
  Widget _buildHeader() {
    return Container(
      height: 62,
      padding: const EdgeInsets.symmetric(horizontal: 19),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // 戻るボタン
          GestureDetector(
            onTap: () => Navigator.pop(context),
            child: const Icon(
              Icons.close,
              color: Colors.white,
              size: 20,
            ),
          ),

          // タイトル
          const Text(
            '新規投稿',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: Colors.white,
            ),
          ),

          // 次へボタン
          GestureDetector(
            onTap: _selectedTrack != null ? _onNext : null,
            child: Text(
              '次へ',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: _selectedTrack != null
                    ? const Color(0xFF5D8FFF)
                    : const Color(0xFF5B5B5B),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 検索バー
  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Container(
        height: 36,
        decoration: BoxDecoration(
          color: const Color(0xFF2D2D2D),
          borderRadius: BorderRadius.circular(11),
        ),
        child: Row(
          children: [
            const SizedBox(width: 13),
            const Icon(
              Icons.search,
              color: Color(0xFF9F9F9F),
              size: 20,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                controller: _searchController,
                style: const TextStyle(
                  fontSize: 13,
                  color: Colors.white,
                ),
                decoration: const InputDecoration(
                  hintText: '検索',
                  hintStyle: TextStyle(
                    fontSize: 13,
                    color: Color(0xFF9F9F9F),
                  ),
                  border: InputBorder.none,
                  contentPadding: EdgeInsets.zero,
                ),
                onChanged: (value) {
                  _searchTracks(value);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Vibe/感情選択ボタン
  Widget _buildCategoryButtons() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 23, vertical: 16),
      child: Row(
        children: [
          // Vibeボタン
          Expanded(
            child: _buildCategoryButtonWithImage(
              imagePath: 'assets/icons/Vibe.png',
              label: 'Vibe',
              subtitle: _todaysTopic != null ? '【${_todaysTopic!.title}】' : '【読み込み中...】',
              isSelected: _selectedCategoryType == 'vibe',
              onTap: () {
                setState(() {
                  _selectedCategoryType = 'vibe';
                  _selectedVibeCategory = _todaysTopic?.title;
                });
              },
            ),
          ),
          const SizedBox(width: 7),
          // 感情選択ボタン
          Expanded(
            child: _buildCategoryButtonWithImage(
              imagePath: 'assets/icons/emotion.png',
              label: '感情で音楽を選ぶ',
              subtitle: null,
              isSelected: _selectedCategoryType == 'emotion',
              onTap: () {
                setState(() {
                  _selectedCategoryType = 'emotion';
                  _selectedVibeCategory = null;
                });
              },
            ),
          ),
        ],
      ),
    );
  }

  /// カテゴリーボタン（画像版）
  Widget _buildCategoryButtonWithImage({
    required String imagePath,
    required String label,
    String? subtitle,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Stack(
        children: [
          Container(
            height: 70,
            width: 210,
            decoration: BoxDecoration(
              color: const Color(0xFF202020),
              border: Border.all(
                color: const Color(0xFF4C4C4C),
                width: 1,
              ),
              borderRadius: BorderRadius.circular(5),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Image.asset(
                  imagePath,
                  width: 24,
                  height: 24,
                  fit: BoxFit.contain,
                  errorBuilder: (context, error, stackTrace) {
                    return const Icon(
                      Icons.music_note,
                      color: Colors.white,
                      size: 24,
                    );
                  },
                ),
                const SizedBox(height: 4),
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                  textAlign: TextAlign.center,
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      fontSize: 8,
                      color: Colors.white,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ],
            ),
          ),
          // チェックマークオーバーレイ
          if (isSelected)
            Positioned.fill(
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.5),
                  borderRadius: BorderRadius.circular(5),
                ),
                child: const Center(
                  child: Icon(
                    Icons.check_circle,
                    color: Colors.white,
                    size: 32,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// タブバー
  Widget _buildTabBar() {
    return Padding(
      padding: const EdgeInsets.only(left: 21, top: 11, bottom: 11, right: 21),
      child: Row(
        children: [
          // おすすめタブ
          GestureDetector(
            onTap: () {
              setState(() => _selectedTab = 0);
              _loadInitialTracks();
            },
            child: Container(
              height: 30,
              padding: const EdgeInsets.symmetric(horizontal: 11),
              decoration: BoxDecoration(
                color:
                    _selectedTab == 0 ? Colors.white : const Color(0xFF3A3A3A),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Center(
                child: Text(
                  'おすすめ',
                  style: TextStyle(
                    fontSize: 8,
                    fontWeight: FontWeight.w500,
                    color: _selectedTab == 0
                        ? const Color(0xFF101010)
                        : Colors.white,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 6),
          // My Playlistタブ
          GestureDetector(
            onTap: () {
              setState(() => _selectedTab = 1);
              _loadMyPlaylistTracks();
            },
            child: Container(
              height: 30,
              padding: const EdgeInsets.symmetric(horizontal: 11),
              decoration: BoxDecoration(
                color:
                    _selectedTab == 1 ? Colors.white : const Color(0xFF3A3A3A),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Center(
                child: Text(
                  'My Playlist',
                  style: TextStyle(
                    fontSize: 8,
                    fontWeight: FontWeight.w500,
                    color: _selectedTab == 1
                        ? const Color(0xFF101010)
                        : Colors.white,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 6),
          // 保存済みタブ
          GestureDetector(
            onTap: () {
              setState(() => _selectedTab = 2);
              _loadSavedTracks();
            },
            child: Container(
              height: 30,
              padding: const EdgeInsets.symmetric(horizontal: 21),
              decoration: BoxDecoration(
                color:
                    _selectedTab == 2 ? Colors.white : const Color(0xFF3A3A3A),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Center(
                child: Text(
                  '保存済み',
                  style: TextStyle(
                    fontSize: 8,
                    fontWeight: FontWeight.w500,
                    color: _selectedTab == 2
                        ? const Color(0xFF101010)
                        : Colors.white,
                  ),
                ),
              ),
            ),
          ),
          const Spacer(),
          // グリッド/リスト切り替えボタン
          GestureDetector(
            onTap: () => setState(() => _isGridView = !_isGridView),
            child: SvgPicture.asset(
              'assets/icons/grid.svg',
              width: 25,
              height: 25,
              colorFilter: const ColorFilter.mode(
                Colors.white,
                BlendMode.srcIn,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 楽曲リスト
  Widget _buildTrackList() {
    return ListView.builder(
      itemCount: _tracks.length,
      itemBuilder: (context, index) {
        final track = _tracks[index];
        final isSelected = _selectedTrack?.trackId == track.trackId;

        return _buildTrackItem(track, isSelected);
      },
    );
  }

  /// 楽曲グリッド
  Widget _buildTrackGrid() {
    return GridView.builder(
      padding: const EdgeInsets.all(16),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
        childAspectRatio: 0.75,
      ),
      itemCount: _tracks.length,
      itemBuilder: (context, index) {
        final track = _tracks[index];
        final isSelected = _selectedTrack?.trackId == track.trackId;

        return _buildGridTrackItem(track, isSelected);
      },
    );
  }

  /// 楽曲アイテム（リスト表示用）
  Widget _buildTrackItem(TrackModel track, bool isSelected) {
    return GestureDetector(
      onTap: () => _toggleTrackSelection(track),
      child: Container(
        height: 59,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        child: Row(
          children: [
            // アルバムアート
            ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: track.albumImageUrl != null
                  ? Image.network(
                      track.albumImageUrl!,
                      width: 47,
                      height: 47,
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) {
                        return _buildPlaceholderImage();
                      },
                    )
                  : _buildPlaceholderImage(),
            ),
            const SizedBox(width: 11),

            // 楽曲情報
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    track.trackName,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    track.artistName,
                    style: const TextStyle(
                      fontSize: 10,
                      color: Colors.white,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),

            // 選択ボタン
            Container(
              width: 19,
              height: 19,
              decoration: BoxDecoration(
                color:
                    isSelected ? const Color(0xFF4CAF50) : Colors.transparent,
                shape: BoxShape.circle,
                border: Border.all(
                  color: isSelected
                      ? const Color(0xFF4CAF50)
                      : const Color(0xFF9F9F9F),
                  width: 2,
                ),
              ),
              child: isSelected
                  ? const Icon(
                      Icons.check,
                      color: Colors.white,
                      size: 12,
                    )
                  : null,
            ),
          ],
        ),
      ),
    );
  }

  /// 楽曲アイテム（グリッド表示用）
  Widget _buildGridTrackItem(TrackModel track, bool isSelected) {
    return GestureDetector(
      onTap: () => _toggleTrackSelection(track),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // アルバムアート
          AspectRatio(
            aspectRatio: 1,
            child: Stack(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(5),
                  child: track.albumImageUrl != null
                      ? Image.network(
                          track.albumImageUrl!,
                          width: double.infinity,
                          height: double.infinity,
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) {
                            return _buildGridPlaceholderImage();
                          },
                        )
                      : _buildGridPlaceholderImage(),
                ),
                // 選択インジケーター
                if (isSelected)
                  Positioned(
                    top: 8,
                    right: 8,
                    child: Container(
                      width: 24,
                      height: 24,
                      decoration: BoxDecoration(
                        color: const Color(0xFF4CAF50),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: Colors.white,
                          width: 2,
                        ),
                      ),
                      child: const Icon(
                        Icons.check,
                        color: Colors.white,
                        size: 14,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 4),
          // 楽曲名
          Text(
            track.trackName,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: Colors.white,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          // アーティスト名
          Text(
            track.artistName,
            style: const TextStyle(
              fontSize: 9,
              color: Color(0xFF9F9F9F),
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  /// プレースホルダー画像（リスト用）
  Widget _buildPlaceholderImage() {
    return Container(
      width: 47,
      height: 47,
      decoration: BoxDecoration(
        color: const Color(0xFF2D2D2D),
        borderRadius: BorderRadius.circular(3),
      ),
      child: const Icon(
        Icons.music_note,
        color: Color(0xFF9F9F9F),
        size: 24,
      ),
    );
  }

  /// プレースホルダー画像（グリッド用）
  Widget _buildGridPlaceholderImage() {
    return Container(
      width: double.infinity,
      height: double.infinity,
      decoration: BoxDecoration(
        color: const Color(0xFF2D2D2D),
        borderRadius: BorderRadius.circular(5),
      ),
      child: const Icon(
        Icons.music_note,
        color: Color(0xFF9F9F9F),
        size: 40,
      ),
    );
  }
}

import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/track_model.dart';
import '../models/vibe_topic_model.dart';
import '../services/music_service_manager.dart';
import '../services/post_service.dart';
import '../services/user_service.dart';
import '../services/vibe_topic_service.dart';
import '../services/lyrics_service.dart';
import '../utils/color_extractor.dart';
import '../services/audio_player_service.dart';
import '../services/itunes_search_service.dart';
import 'post_preview_screen.dart';

/// 投稿用楽曲選択画面
class MusicSelectionScreen extends StatefulWidget {
  final String? initialCategoryType; // 'vibe' or 'emotion' — 事前選択用

  const MusicSelectionScreen({
    super.key,
    this.initialCategoryType,
  });

  @override
  State<MusicSelectionScreen> createState() => _MusicSelectionScreenState();
}

class _MusicSelectionScreenState extends State<MusicSelectionScreen> {
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  final MusicServiceManager _musicServiceManager = MusicServiceManager();
  final PostService _postService = PostService();
  final UserService _userService = UserService();
  final VibeTopicService _vibeTopicService = VibeTopicService();
  final AudioPlayerService _audioService = AudioPlayerService();
  final ITunesSearchService _itunesService = ITunesSearchService();

  // 選択された楽曲
  TrackModel? _selectedTrack;

  // 今日のVibeお題
  VibeTopicModel? _todaysTopic;

  // タブ選択状態: 0 = 最近聞いた曲, 1 = おすすめ, 2 = My Playlist, 3 = 保存済み
  int _selectedTab = 1;

  // 表示モード: true = グリッド, false = リスト
  bool _isGridView = false;

  // カテゴリー選択状態: null = 未選択, 'vibe' = Vibe, 'emotion' = 感情
  String? _selectedCategoryType;

  // 楽曲リスト（Spotify APIから取得）
  List<TrackModel> _tracks = [];

  // ローディング状態
  bool _isLoading = false;

  // 音楽サービス未連携状態
  bool _notConnected = false;

  // 検索フォーカス状態
  bool _isSearchFocused = false;

  // 検索中のクエリ
  String _currentSearchQuery = '';

  // 最近の検索履歴
  List<Map<String, String>> _recentMusicSearches = [];
  static const String _recentMusicSearchesKey = 'recent_music_searches';

  // Vibeおすすめ楽曲（常時表示の大カード）
  List<TrackModel> _recommendedTracks = [];
  bool _isLoadingRecommended = false;

  // 感情カテゴリー用ランダム検索ワード候補
  static const List<String> _emotionKeywords = [
    '恋愛ソング',
    '失恋バラード',
    'シティポップ',
    'ドライブBGM',
    '夜に聴く曲',
    'テンション上がる曲',
    '泣ける名曲',
    '夏ヒット',
    'カフェBGM',
    '懐かしいJPOP',
    '日本語ラップ',
    'ロック邦楽',
    'アニソン人気',
    'J-R&B',
    'エモい曲',
    '朝に聴く曲',
    '応援ソング',
    'K-POP人気',
    'EDM人気',
    'チルミュージック',
  ];

  // 現在選択中の感情キーワード（ヘッダー表示用）
  String? _currentEmotionKeyword;

  @override
  void initState() {
    super.initState();
    _selectedCategoryType = widget.initialCategoryType ?? 'vibe';
    _searchFocusNode.addListener(_onSearchFocusChanged);
    _loadRecentMusicSearches();
    _loadInitialTracks();
    _loadTodaysTopic();
  }

  @override
  void dispose() {
    _audioService.stop();
    _searchController.dispose();
    _searchFocusNode.removeListener(_onSearchFocusChanged);
    _searchFocusNode.dispose();
    super.dispose();
  }

  void _onSearchFocusChanged() {
    setState(() {
      _isSearchFocused = _searchFocusNode.hasFocus;
    });
  }

  /// 最近の検索履歴を読み込み
  Future<void> _loadRecentMusicSearches() async {
    final prefs = await SharedPreferences.getInstance();
    final data = prefs.getStringList(_recentMusicSearchesKey);
    if (data != null && mounted) {
      setState(() {
        _recentMusicSearches = data
            .map((e) => Map<String, String>.from(jsonDecode(e)))
            .toList();
      });
    }
  }

  /// 最近の検索履歴に追加
  Future<void> _addToRecentMusicSearches(TrackModel track) async {
    final entry = {
      'trackId': track.trackId,
      'trackName': track.trackName,
      'artistName': track.artistName,
      'albumImageUrl': track.albumImageUrl,
    };

    _recentMusicSearches.removeWhere((e) => e['trackId'] == track.trackId);
    _recentMusicSearches.insert(0, entry);

    if (_recentMusicSearches.length > 10) {
      _recentMusicSearches = _recentMusicSearches.sublist(0, 10);
    }

    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
      _recentMusicSearchesKey,
      _recentMusicSearches.map((e) => jsonEncode(e)).toList(),
    );

    if (mounted) setState(() {});
  }

  /// 最近の検索履歴から削除
  Future<void> _removeFromRecentMusicSearches(String trackId) async {
    _recentMusicSearches.removeWhere((e) => e['trackId'] == trackId);

    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
      _recentMusicSearchesKey,
      _recentMusicSearches.map((e) => jsonEncode(e)).toList(),
    );

    if (mounted) setState(() {});
  }

  /// 最近聞いた曲を読み込み
  Future<void> _loadRecentlyPlayedTracks() async {
    setState(() { _isLoading = true; _notConnected = false; });

    try {
      final isAuthenticated = await _musicServiceManager.isAuthenticated();

      if (!isAuthenticated) {
        if (mounted) {
          setState(() { _tracks = []; _isLoading = false; _notConnected = true; });
        }
        return;
      }

      final tracks = await _musicServiceManager.getRecentlyPlayedTracks(limit: 30);

      if (mounted) {
        setState(() {
          _tracks = tracks;
          _isLoading = false;
        });
      }
    } catch (e) {
      print('Error loading recently played tracks: $e');
      if (mounted) {
        setState(() {
          _tracks = [];
          _isLoading = false;
        });
      }
    }
  }

  /// 初期楽曲を読み込み（おすすめ = 日本の人気曲）
  Future<void> _loadInitialTracks() async {
    setState(() { _isLoading = true; _notConnected = false; });

    try {
      // Apple Music日本トップチャートからおすすめ楽曲を取得
      List<TrackModel> tracks = await _musicServiceManager.getRecommendedTracks(limit: 50);

      if (tracks.isEmpty) {
        print('⚠️ おすすめ取得が空。検索にフォールバック...');
        tracks = await _musicServiceManager.searchTracks('J-POP 人気', limit: 25);
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
        // トピック取得後におすすめ楽曲を検索
        _loadRecommendedTracks();
      }
    } catch (e) {
      print('Error loading today\'s topic: $e');
    }
  }

  /// おすすめ楽曲（上部大カード用）を読み込み
  Future<void> _loadRecommendedTracks() async {
    if (mounted) setState(() => _isLoadingRecommended = true);
    try {
      List<TrackModel> tracks = [];

      if (_selectedCategoryType == 'vibe' && _todaysTopic != null) {
        // Vibeカテゴリー: トピック名で検索
        tracks = await _musicServiceManager.searchTracks(_todaysTopic!.title, limit: 6);
      } else if (_selectedCategoryType != 'vibe') {
        // 感情カテゴリー: ランダムキーワードで検索
        final keyword = _emotionKeywords[Random().nextInt(_emotionKeywords.length)];
        if (mounted) setState(() => _currentEmotionKeyword = keyword);
        tracks = await _musicServiceManager.searchTracks(keyword, limit: 6);
      }

      // フォールバック
      if (tracks.isEmpty) {
        tracks = await _musicServiceManager.getRecommendedTracks(limit: 6);
      }
      if (tracks.isEmpty) {
        tracks = await _musicServiceManager.searchTracks('J-POP 人気', limit: 6);
      }

      if (mounted) {
        setState(() {
          _recommendedTracks = tracks.take(3).toList();
          _isLoadingRecommended = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isLoadingRecommended = false);
    }
  }

  /// My Playlistの楽曲を読み込み
  Future<void> _loadMyPlaylistTracks() async {
    setState(() { _isLoading = true; _notConnected = false; });

    try {
      final isAuthenticated = await _musicServiceManager.isAuthenticated();

      if (!isAuthenticated) {
        if (mounted) {
          setState(() { _tracks = []; _isLoading = false; _notConnected = true; });
        }
        return;
      }

      final tracks = await _musicServiceManager.getSavedTracks(limit: 50);

      if (mounted) {
        setState(() {
          _tracks = tracks;
          _isLoading = false;
        });
      }
    } catch (e) {
      print('Error loading my playlist tracks: $e');
      if (mounted) {
        setState(() {
          _tracks = [];
          _isLoading = false;
        });
      }
    }
  }

  /// 楽曲を検索
  Future<void> _searchTracks(String query) async {
    final trimmed = query.trim();
    setState(() => _currentSearchQuery = trimmed);

    if (trimmed.isEmpty) {
      if (_selectedTab == 0) {
        _loadRecentlyPlayedTracks();
      } else if (_selectedTab == 1) {
        _loadInitialTracks();
      } else if (_selectedTab == 2) {
        _loadMyPlaylistTracks();
      } else {
        _loadSavedTracks();
      }
      return;
    }

    setState(() => _isLoading = true);

    try {
      final tracks = await _musicServiceManager.searchTracks(trimmed, limit: 20);

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
    setState(() { _isLoading = true; _notConnected = false; });

    try {
      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) {
        if (mounted) setState(() { _tracks = []; _isLoading = false; });
        return;
      }

      final userData = await _userService.getUser(currentUser.uid);
      final savedPostIds = userData?.savedPosts ?? [];

      if (savedPostIds.isEmpty) {
        if (mounted) {
          setState(() {
            _tracks = [];
            _isLoading = false;
          });
        }
        return;
      }

      final firestorePosts = await _postService.getPosts(limit: 50);
      final savedPosts = firestorePosts
          .where((post) => savedPostIds.contains(post.postId))
          .toList();

      final Map<String, TrackModel> uniqueTracks = {};
      for (final post in savedPosts) {
        uniqueTracks[post.track.trackId] = post.track;
      }

      if (mounted) {
        setState(() {
          _tracks = uniqueTracks.values.toList();
          _isLoading = false;
        });
      }
    } catch (e) {
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

    if (_selectedTrack?.trackId == track.trackId) {
      setState(() { _selectedTrack = null; });
      _audioService.stop();
    } else {
      setState(() {
        _selectedTrack = track;
        // 検索履歴に追加
        _addToRecentMusicSearches(track);
      });
      _playTrackPreview(track);
    }
  }

  /// 楽曲のプレビューを再生
  Future<void> _playTrackPreview(TrackModel track) async {
    await _audioService.stop();

    String? previewUrl = track.previewUrl;

    if (previewUrl == null || previewUrl.isEmpty) {
      final result = await _itunesService.getPreviewUrlWithArt(
        trackName: track.trackName,
        artistName: track.artistName,
      );
      previewUrl = result?['previewUrl'];
    }

    if (previewUrl != null && previewUrl.isNotEmpty && mounted) {
      try {
        await _audioService.playPreview(previewUrl, durationSeconds: 15);
      } catch (e) {
        print('Preview playback error: $e');
      }
    }
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
            vibeTopicTitle: _todaysTopic?.title,
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
        bottom: false,
        child: Column(
          children: [
            // ヘッダー
            _buildHeader(),

            // 検索バー
            _buildSearchBar(),

            // 検索フォーカス中＆クエリ空 → 検索履歴を表示
            if (_isSearchFocused && _currentSearchQuery.isEmpty) ...[
              Expanded(
                child: _buildRecentMusicSearches(),
              ),
            ] else ...[
              Expanded(
                child: CustomScrollView(
                  slivers: [
                    // カテゴリーボタン（スクロールで消える）
                    SliverToBoxAdapter(child: _buildCategoryButtons()),
                    // セクションヘッダー（スクロールで消える）
                    SliverToBoxAdapter(child: _buildSectionHeader()),
                    // おすすめ楽曲（スクロールで消える）
                    SliverToBoxAdapter(child: _buildRecommendedSection()),
                    // タブバー＋区切り線（検索バー直下にピン留め）
                    SliverPersistentHeader(
                      pinned: true,
                      delegate: _TabBarSliverDelegate(
                        height: 53,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _buildTabBar(),
                            Container(height: 1, color: const Color(0xFF2D2D2D)),
                          ],
                        ),
                      ),
                    ),
                    // 楽曲リスト or グリッド
                    if (_isLoading)
                      const SliverFillRemaining(
                        child: Center(
                          child: CircularProgressIndicator(color: Color(0xFF5D8FFF)),
                        ),
                      )
                    else if (_notConnected)
                      SliverFillRemaining(child: _buildNotConnectedView())
                    else if (_tracks.isEmpty)
                      const SliverFillRemaining(
                        child: Center(
                          child: Text(
                            '楽曲が見つかりませんでした',
                            style: TextStyle(
                              fontSize: 13,
                              color: Color(0xFF9F9F9F),
                            ),
                          ),
                        ),
                      )
                    else if (_isGridView)
                      _buildTrackGridSliver()
                    else
                      _buildTrackListSliver(),
                  ],
                ),
              ),
            ],
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
        children: [
          // 戻るボタン
          Expanded(
            child: Align(
              alignment: Alignment.centerLeft,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => Navigator.pop(context),
                child: const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: Icon(
                    Icons.close,
                    color: Colors.white,
                    size: 27,
                  ),
                ),
              ),
            ),
          ),

          // タイトル
          const Text(
            '新規投稿',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: Colors.white,
            ),
          ),

          // 次へボタン
          Expanded(
            child: Align(
              alignment: Alignment.centerRight,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: _selectedTrack != null ? _onNext : null,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Text(
                    '次へ',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: _selectedTrack != null
                          ? const Color(0xFF5D8FFF)
                          : const Color(0xFF5B5B5B),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 検索キャンセル
  void _onSearchCancel() {
    _searchController.clear();
    _searchTracks('');
    _searchFocusNode.unfocus();
    setState(() {
      _currentSearchQuery = '';
    });
  }

  /// 検索バー
  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          Expanded(
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
                    size: 22,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: _searchController,
                      focusNode: _searchFocusNode,
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
                        isDense: true,
                        contentPadding: EdgeInsets.symmetric(vertical: 8),
                      ),
                      onChanged: (value) {
                        _searchTracks(value);
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (_isSearchFocused)
            GestureDetector(
              onTap: _onSearchCancel,
              child: const Padding(
                padding: EdgeInsets.only(left: 10),
                child: Text(
                  'キャンセル',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w400,
                    color: Color(0xFF99999B),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// Vibe/感情選択ボタン
  Widget _buildCategoryButtons() {
    return Padding(
      padding: const EdgeInsets.only(left: 23, right: 23, top: 16, bottom: 5),
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
                });
                _loadRecommendedTracks();
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
                });
                _loadRecommendedTracks();
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
          // 最近聞いた曲タブ
          _buildTabButton(0, '最近聞いた曲', () => _loadRecentlyPlayedTracks()),
          const SizedBox(width: 6),
          // おすすめタブ
          _buildTabButton(1, 'おすすめ', () => _loadInitialTracks()),
          const SizedBox(width: 6),
          // My Playlistタブ
          _buildTabButton(2, 'My Playlist', () => _loadMyPlaylistTracks()),
          const SizedBox(width: 6),
          // 保存済みタブ
          _buildTabButton(3, '保存済み', () => _loadSavedTracks()),
          const Spacer(),
          // グリッド/リスト切り替えボタン
          GestureDetector(
            onTap: () => setState(() => _isGridView = !_isGridView),
            child: _isGridView
                ? const Icon(Icons.menu, color: Colors.white, size: 25)
                : SvgPicture.asset(
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

  /// 最近の検索履歴セクション
  Widget _buildRecentMusicSearches() {
    if (_recentMusicSearches.isEmpty) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.only(left: 16, top: 12, bottom: 8),
          child: Text(
            '最近',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: Colors.white,
            ),
          ),
        ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: _recentMusicSearches.length,
            itemBuilder: (context, index) {
              final entry = _recentMusicSearches[index];
              return _buildRecentMusicSearchItem(entry);
            },
          ),
        ),
      ],
    );
  }

  /// 最近の検索アイテム
  Widget _buildRecentMusicSearchItem(Map<String, String> entry) {
    return InkWell(
      onTap: () {
        // 検索フィールドに曲名を入れて検索
        _searchController.text = entry['trackName'] ?? '';
        _searchTracks(entry['trackName'] ?? '');
        _searchFocusNode.unfocus();
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            // アルバムアート
            ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: (entry['albumImageUrl']?.isNotEmpty == true)
                  ? CachedNetworkImage(
                      imageUrl: entry['albumImageUrl']!,
                      width: 44,
                      height: 44,
                      fit: BoxFit.cover,
                      errorWidget: (_, __, ___) => Container(
                        width: 44,
                        height: 44,
                        color: const Color(0xFF2D2D2D),
                        child: const Icon(Icons.music_note, color: Color(0xFF9F9F9F), size: 24),
                      ),
                    )
                  : Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: const Color(0xFF2D2D2D),
                        borderRadius: BorderRadius.circular(3),
                      ),
                      child: const Icon(Icons.music_note, color: Color(0xFF9F9F9F), size: 24),
                    ),
            ),
            const SizedBox(width: 12),

            // 曲情報
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    entry['trackName'] ?? 'Unknown',
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (entry['artistName']?.isNotEmpty == true)
                    Text(
                      entry['artistName']!,
                      style: const TextStyle(
                        fontSize: 13,
                        color: Color(0xFF9F9F9F),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                ],
              ),
            ),

            // 削除ボタン
            GestureDetector(
              onTap: () => _removeFromRecentMusicSearches(entry['trackId'] ?? ''),
              child: const Padding(
                padding: EdgeInsets.all(8),
                child: Icon(
                  Icons.close,
                  size: 18,
                  color: Color(0xFF9F9F9F),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// タブボタン
  Widget _buildTabButton(int index, String label, VoidCallback onLoad) {
    final isSelected = _selectedTab == index;
    return GestureDetector(
      onTap: () {
        setState(() => _selectedTab = index);
        onLoad();
      },
      child: Container(
        height: 30,
        padding: const EdgeInsets.symmetric(horizontal: 11),
        decoration: BoxDecoration(
          color: isSelected ? Colors.white : const Color(0xFF3A3A3A),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Center(
          child: Text(
            label,
            style: TextStyle(
              fontSize: 8,
              fontWeight: FontWeight.w500,
              color: isSelected ? const Color(0xFF101010) : Colors.white,
            ),
          ),
        ),
      ),
    );
  }

  /// 楽曲リスト（Sliver版 - CustomScrollView用）
  Widget _buildTrackListSliver() {
    return SliverList(
      delegate: SliverChildBuilderDelegate(
        (context, index) {
          final track = _tracks[index];
          final isSelected = _selectedTrack?.trackId == track.trackId;
          return _buildTrackItem(track, isSelected);
        },
        childCount: _tracks.length,
      ),
    );
  }

  /// 楽曲グリッド（Sliver版 - CustomScrollView用）
  Widget _buildTrackGridSliver() {
    return SliverPadding(
      padding: const EdgeInsets.all(16),
      sliver: SliverGrid(
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3,
          crossAxisSpacing: 8,
          mainAxisSpacing: 8,
          childAspectRatio: 0.75,
        ),
        delegate: SliverChildBuilderDelegate(
          (context, index) {
            final track = _tracks[index];
            final isSelected = _selectedTrack?.trackId == track.trackId;
            return _buildGridTrackItem(track, isSelected);
          },
          childCount: _tracks.length,
        ),
      ),
    );
  }

  /// 楽曲アイテム（リスト表示用）
  Widget _buildTrackItem(TrackModel track, bool isSelected) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => _toggleTrackSelection(track),
      child: Container(
        height: 59,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        color: isSelected ? const Color(0xFF2A2A2A) : Colors.transparent,
        child: Row(
          children: [
            // アルバムアート
            ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: CachedNetworkImage(
                    imageUrl: track.albumImageUrl,
                    width: 47,
                    height: 47,
                    fit: BoxFit.cover,
                    errorWidget: (context, url, error) {
                      return _buildPlaceholderImage();
                    },
                  ),
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
                  child: CachedNetworkImage(
                        imageUrl: track.albumImageUrl,
                        width: double.infinity,
                        height: double.infinity,
                        fit: BoxFit.cover,
                        errorWidget: (context, url, error) {
                          return _buildGridPlaceholderImage();
                        },
                      ),
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

  /// セクションヘッダー（Vibe時は "Vibe【#topic】", 感情時は "今の気分で選ぶ"）
  Widget _buildSectionHeader() {
    final isVibe = _selectedCategoryType == 'vibe';
    return SizedBox(
      width: double.infinity,
      child: Padding(
      padding: const EdgeInsets.only(left: 21, right: 21, top: 0, bottom: 5),
      child: isVibe && _todaysTopic != null
          ? Text.rich(
              TextSpan(
                children: [
                  const TextSpan(
                    text: 'Vibe',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  TextSpan(
                    text: '【#${_todaysTopic!.title}】',
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w400,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
            )
          : const Text(
              '今の気分で選ぶ',
              style: TextStyle(
                fontSize: 19,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
      ),
    );
  }

  /// おすすめ楽曲セクション（大カード横並び）
  Widget _buildRecommendedSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // "🎧 おすすめ" ラベル（感情カテゴリー時はキーワードも表示）
        Padding(
          padding: const EdgeInsets.only(left: 21, bottom: 10),
          child: Row(
            children: [
              const Icon(Icons.headphones, color: Colors.white, size: 16),
              const SizedBox(width: 6),
              const Text(
                'おすすめ',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                ),
              ),
              if (_selectedCategoryType != 'vibe' && _currentEmotionKeyword != null) ...[
                const SizedBox(width: 8),
                Text(
                  '#$_currentEmotionKeyword',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: Color(0xFF5D8FFF),
                  ),
                ),
              ],
            ],
          ),
        ),
        // 大カード横スクロール
        SizedBox(
          height: 168,
          child: _isLoadingRecommended
              ? const Center(
                  child: SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(
                      color: Color(0xFF5D8FFF),
                      strokeWidth: 2,
                    ),
                  ),
                )
              : _recommendedTracks.isEmpty
                  ? const SizedBox.shrink()
                  : ListView.builder(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: 21),
                      itemCount: _recommendedTracks.length,
                      itemBuilder: (context, index) {
                        return _buildRecommendedCard(_recommendedTracks[index]);
                      },
                    ),
        ),
        const SizedBox(height: 4),
      ],
    );
  }

  /// おすすめ大カード
  Widget _buildRecommendedCard(TrackModel track) {
    final isSelected = _selectedTrack?.trackId == track.trackId;
    return GestureDetector(
      onTap: () => _toggleTrackSelection(track),
      child: Container(
        width: 130,
        margin: const EdgeInsets.only(right: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Stack(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: track.albumImageUrl.isNotEmpty
                      ? CachedNetworkImage(
                          imageUrl: track.albumImageUrl,
                          width: 130,
                          height: 130,
                          fit: BoxFit.cover,
                          errorWidget: (_, __, ___) => _buildGridPlaceholderImage(),
                        )
                      : _buildGridPlaceholderImage(),
                ),
                if (isSelected)
                  Positioned(
                    top: 6,
                    right: 6,
                    child: Container(
                      width: 24,
                      height: 24,
                      decoration: BoxDecoration(
                        color: const Color(0xFF4CAF50),
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 1.5),
                      ),
                      child: const Icon(Icons.check, color: Colors.white, size: 14),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 5),
            Text(
              track.trackName,
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w500,
                color: Colors.white,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            Text(
              track.artistName,
              style: const TextStyle(fontSize: 10, color: Color(0xFF9F9F9F)),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }

  /// 音楽サービス未連携時のビュー
  Widget _buildNotConnectedView() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.music_off,
            color: Color(0xFF9F9F9F),
            size: 48,
          ),
          const SizedBox(height: 16),
          const Text(
            '音楽サービスと連携してください',
            style: TextStyle(
              fontSize: 14,
              color: Color(0xFF9F9F9F),
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            '設定 → 音楽サービス連携 から連携できます',
            style: TextStyle(
              fontSize: 12,
              color: Color(0xFF6F6F6F),
            ),
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

/// タブバー固定用 SliverPersistentHeaderDelegate
class _TabBarSliverDelegate extends SliverPersistentHeaderDelegate {
  final Widget child;
  final double height;

  _TabBarSliverDelegate({required this.child, required this.height});

  @override
  double get minExtent => height;

  @override
  double get maxExtent => height;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    return Container(
      color: const Color(0xFF121212),
      child: child,
    );
  }

  @override
  bool shouldRebuild(_TabBarSliverDelegate oldDelegate) => true;
}

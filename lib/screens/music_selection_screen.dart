import 'dart:convert';
import 'dart:math';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/track_model.dart';
import '../models/vibe_topic_model.dart';
import '../services/music_service_manager.dart';
import '../services/post_service.dart';
import '../services/user_service.dart';
import '../services/vibe_topic_service.dart';
import '../services/adl_service.dart';
import '../services/lyrics_service.dart';
import '../utils/color_extractor.dart';
import '../services/audio_player_service.dart';
import '../services/itunes_search_service.dart';
import 'post_preview_screen.dart';
import 'home_screen.dart';
import '../widgets/common/common.dart';
import '../widgets/music/music_search_bar.dart';
import '../widgets/music/music_track_list_item.dart';
import 'home/home_bottom_nav.dart';
import '../widgets/common/app_toast.dart';

/// 投稿用楽曲選択画面
class MusicSelectionScreen extends StatefulWidget {
  final String? initialCategoryType; // 'vibe' or 'emotion' — 事前選択用
  final bool isPickerMode; // true = 選択後にpopで結果を返す（PostCardEditScreenから呼ばれる場合）
  final bool fromVibePlaylist; // true = Vibe専用投稿ボタンを最終画面に表示

  const MusicSelectionScreen({
    super.key,
    this.initialCategoryType,
    this.isPickerMode = false,
    this.fromVibePlaylist = false,
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

  // 音楽サービス認証済み状態（未連携時はタブを非表示）
  bool _isAuthenticated = false;

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
    _loadTodaysTopic();
    _initializeTabAndTracks();
    if (!widget.isPickerMode) _trackPostStart();
  }

  /// 投稿開始イベントを記録（analytics_events コレクション）
  Future<void> _trackPostStart() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    try {
      await _postService.trackAnalyticsEvent(uid: uid, type: 'post_start');
    } catch (_) {}
  }

  @override
  void dispose() {
    _audioService.stopIfOwner(this);
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

  /// 起動時：連携済みなら「最近聞いた曲」タブを表示＋先頭曲をプリセレクト
  /// 未連携なら「おすすめ」タブを表示（従来動作）
  Future<void> _initializeTabAndTracks() async {
    final isAuthenticated = await _musicServiceManager.isAuthenticated();
    if (!mounted) return;

    setState(() => _isAuthenticated = isAuthenticated);

    if (isAuthenticated) {
      setState(() => _selectedTab = 0);
      await _loadRecentlyPlayedTracks();
    } else {
      await _loadInitialTracks();
    }
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
      final forAdl = await AdlService().isCurrentUserAdlParticipant();
      final topic = await _vibeTopicService.getTodaysTopic(forAdl: forAdl);
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

  /// 保存済み曲を読み込み（プロフィールの保存済みタブと同一ロジック）
  Future<void> _loadSavedTracks() async {
    setState(() { _isLoading = true; _notConnected = false; });

    try {
      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) {
        if (mounted) setState(() { _tracks = []; _isLoading = false; });
        return;
      }

      final results = await Future.wait([
        _postService.getPostsSavedByUser(currentUser.uid),
        _userService.getUser(currentUser.uid),
      ]);

      final savedPosts = results[0] as List;
      final me = results[1] as dynamic;

      // 保存時刻で統合ソートするため、(savedAt, TrackModel) のペアで管理
      final List<({DateTime savedAt, TrackModel track})> entries = [];
      final seen = <String>{};

      // アーティストプロフィールから保存したトラック
      final savedTracksData =
          (me?.savedTracksData as Map<String, dynamic>?) ?? {};
      for (final entry in savedTracksData.entries) {
        final m = entry.value as Map<String, dynamic>;
        final trackId = m['trackId']?.toString() ?? '';
        if (trackId.isEmpty || seen.contains(trackId)) continue;
        seen.add(trackId);
        final ts = m['savedAt'];
        entries.add((
          savedAt: ts is Timestamp ? ts.toDate() : DateTime(0),
          track: TrackModel(
            trackId: trackId,
            trackName: m['trackName']?.toString() ?? '',
            artistName: m['artistName']?.toString() ?? '',
            albumImageUrl: m['albumImageUrl']?.toString() ?? '',
            previewUrl: m['previewUrl']?.toString(),
          ),
        ));
      }

      // 投稿から保存したトラック（重複はスキップ）
      final savedPostsAt =
          (me?.savedPostsAt as Map<String, dynamic>?) ?? {};
      for (final post in savedPosts) {
        if (seen.contains(post.track.trackId)) continue;
        seen.add(post.track.trackId);
        final ts = savedPostsAt[post.postId];
        entries.add((
          savedAt: ts is Timestamp ? ts.toDate() : DateTime(0),
          track: post.track,
        ));
      }

      // 保存時刻 降順
      entries.sort((a, b) => b.savedAt.compareTo(a.savedAt));

      if (mounted) {
        setState(() {
          _tracks = entries.map((e) => e.track).toList();
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

    // 非同期処理中に別の曲が選択された場合は再生しない（レースコンディション対策）
    if (!mounted || _selectedTrack?.trackId != track.trackId) return;

    if (previewUrl != null && previewUrl.isNotEmpty) {
      // iTunesから取得したURLを_selectedTrackに反映（PostPreviewScreenに正しいURLを引き渡すため）
      if ((track.previewUrl == null || track.previewUrl!.isEmpty) && mounted) {
        setState(() {
          _selectedTrack = track.copyWith(previewUrl: previewUrl);
        });
      }
      try {
        await _audioService.playPreview(previewUrl, durationSeconds: 15);
      } catch (e) {
        print('Preview playback error: $e');
      }
    } else {
      if (mounted) {
        AppToast.show(context, '音楽が見つかりません');
      }
    }
  }

  /// 次へ進む
  Future<void> _onNext() async {
    if (_selectedTrack == null) {
      AppToast.show(context, '楽曲を選択してください');
      return;
    }

    // ピッカーモード: 選択されたトラックをpopで返す
    if (widget.isPickerMode) {
      _audioService.stop();
      if (mounted) Navigator.pop(context, _selectedTrack);
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
        PageRouteBuilder(
          pageBuilder: (context, animation, secondaryAnimation) => PostPreviewScreen(
            track: _selectedTrack!,
            lyricsData: null,
            lyricsFuture: lyricsFuture,
            isVibe: true,
            vibeTopicId: _todaysTopic?.topicId,
            vibeTopicTitle: _todaysTopic?.title,
            fromVibePlaylist: widget.fromVibePlaylist,
            preExtractedGradientStart: gradientStart,
            preExtractedGradientEnd: gradientEnd,
          ),
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            final tween = Tween(begin: const Offset(0, 1), end: Offset.zero)
                .chain(CurveTween(curve: Curves.easeOutCubic));
            return SlideTransition(position: animation.drive(tween), child: child);
          },
          transitionDuration: const Duration(milliseconds: 350),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final showNav = !widget.isPickerMode;
    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      body: Stack(
        children: [
          SafeArea(
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
                        // 検索中はヘッダー・おすすめを非表示
                        if (!_isSearchFocused) ...[
                          // セクションヘッダー（スクロールで消える）
                          SliverToBoxAdapter(child: _buildSectionHeader()),
                          // おすすめ楽曲（スクロールで消える）
                          SliverToBoxAdapter(child: _buildRecommendedSection()),
                        ],
                        // タブバー＋区切り線（検索中は非表示）
                        if (!_isSearchFocused)
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
                              child: CupertinoActivityIndicator(color: Color(0xFF5D8FFF), radius: 14),
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
          // ボトムナビゲーション（投稿ボタンは白・タップでこの画面を閉じる）
          if (showNav && MediaQuery.of(context).viewInsets.bottom == 0)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: HomeBottomNavigation(
                selectedIndex: 2,
                onItemTapped: (i) {
                  _audioService.stop();
                  if (i == 2) {
                    // 投稿ボタン再タップ → 画面を閉じてホームへ
                    Navigator.pop(context, 0);
                  } else {
                    // ホーム/検索/プロフィール → 結果インデックスを渡してタブ切り替え
                    Navigator.pop(context, i);
                  }
                },
              ),
            ),
        ],
      ),
    );
  }

  /// ヘッダー
  Widget _buildHeader() {
    return Hero(
      tag: 'post_flow_header',
      flightShuttleBuilder: (_, __, ___, ____, _____) => const Material(
        color: Colors.transparent,
        child: SizedBox(
          height: 50,
          child: Center(
            child: Text(
              '新規投稿',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: Colors.white,
              ),
            ),
          ),
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: Container(
          height: 50,
          padding: const EdgeInsets.symmetric(horizontal: 19),
          child: Row(
            children: [
              // 戻るボタン
              Expanded(
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () {
                      _audioService.stop();
                      Navigator.pushAndRemoveUntil(
                        context,
                        PageRouteBuilder(
                          pageBuilder: (_, __, ___) => const HomeScreen(),
                          transitionDuration: Duration.zero,
                          reverseTransitionDuration: Duration.zero,
                        ),
                        (route) => false,
                      );
                    },
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
                  fontWeight: FontWeight.w700,
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
                          fontWeight: FontWeight.w700,
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
        ),
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
    return MusicSearchBar(
      controller: _searchController,
      focusNode: _searchFocusNode,
      isFocused: _isSearchFocused,
      onCancel: _onSearchCancel,
      onChanged: _searchTracks,
    );
  }

  /// タブバー
  Widget _buildTabBar() {
    return Padding(
      padding: const EdgeInsets.only(left: 21, top: 11, bottom: 11, right: 21),
      child: Row(
        children: [
          // おすすめタブ
          _buildTabButton(1, 'おすすめ', () => _loadInitialTracks()),
          const SizedBox(width: 6),
          // 最近聞いた曲タブ（連携済みのみ表示）
          if (_isAuthenticated) ...[
            _buildTabButton(0, '最近聞いた曲', () => _loadRecentlyPlayedTracks()),
            const SizedBox(width: 6),
          ],
          // My Playlistタブ（連携済みのみ表示）
          if (_isAuthenticated) ...[
            _buildTabButton(2, 'My Playlist', () => _loadMyPlaylistTracks()),
            const SizedBox(width: 6),
          ],
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
              fontSize: 12,
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
    return MusicTrackListItem(
      track: track,
      isSelected: isSelected,
      onTap: () => _toggleTrackSelection(track),
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
                      fontSize: 12,
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
                  child: CupertinoActivityIndicator(
                    color: Color(0xFF5D8FFF),
                    radius: 12,
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

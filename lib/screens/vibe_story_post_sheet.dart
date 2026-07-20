import 'dart:ui';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/post_theme.dart';
import '../models/track_model.dart';
import '../models/vibe_topic_model.dart';
import '../services/audio_player_service.dart';
import '../services/itunes_search_service.dart';
import '../services/music_service_manager.dart';
import '../services/post_service.dart';
import '../services/user_service.dart';
import '../utils/color_extractor.dart';
import '../widgets/music/music_track_list_item.dart';
import 'vibe_story_preview_screen.dart';

/// Vibe ストーリーバー左端の「Vibe（+）」をタップしたときに開く
/// ストーリー投稿フローのトップシート（楽曲選択画面）。
///
/// 投稿フローの [MusicSelectionScreen] と同じ Spotify/Apple Music 経由で
/// 楽曲を取得する。3 タブ構成にスリム化:
///   - 最近聞いた曲（音楽サービス連携の getRecentlyPlayedTracks）
///   - おすすめ（Apple Music 日本TOPチャート、fallback で J-POP 検索）
///   - 保存済み（プロフィール保存タブと同じソース）
///
/// 行タップで楽曲プレビュー再生、もう一度タップで停止/解除。
/// 「次へ」相当のアクションはまだ未配線（onTrackChosen コールバックを後で渡す想定）。
class VibeStoryPostSheet extends StatefulWidget {
  /// 投稿先となる Vibe のお題（ヘッダー表示に使う）
  final VibeTopicModel? topic;

  /// 楽曲を選んでシートを次フローへ閉じる時のコールバック（未指定なら閉じない）
  final ValueChanged<TrackModel>? onTrackChosen;

  /// Music Memory 投稿（主に Spotify ユーザー）向けモード。
  /// - お題ヘッダー（Vibe【#…】）を非表示
  /// - 楽曲決定時は Vibe プレビューを挟まず onTrackChosen で親に返す（親が写真フローへ）
  final bool moodPostMode;

  const VibeStoryPostSheet({
    super.key,
    this.topic,
    this.onTrackChosen,
    this.moodPostMode = false,
  });

  /// 下から showModalBottomSheet で開く便利メソッド。
  /// Figma: シート上端 y=196 / 全画面高 874 → 比率 ≈ 0.776 を上限とする。
  /// 端末によらず Vibe ストーリーバーが上に覗くように相対指定する。
  static Future<void> show(
    BuildContext context, {
    VibeTopicModel? topic,
    ValueChanged<TrackModel>? onTrackChosen,
    bool moodPostMode = false,
  }) {
    return showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.35),
      isScrollControlled: true,
      // 高さの上限を画面の約 77.6% に抑え、上に Vibe ストーリーバーを覗かせる
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * (678.0 / 874.0),
      ),
      builder: (ctx) => VibeStoryPostSheet(
        topic: topic,
        onTrackChosen: onTrackChosen,
        moodPostMode: moodPostMode,
      ),
    );
  }

  @override
  State<VibeStoryPostSheet> createState() => _VibeStoryPostSheetState();
}

enum _SourceTab { recentlyPlayed, recommended, saved }

class _VibeStoryPostSheetState extends State<VibeStoryPostSheet> {
  final TextEditingController _searchController = TextEditingController();
  final MusicServiceManager _musicServiceManager = MusicServiceManager();
  final ITunesSearchService _itunesService = ITunesSearchService();
  final AudioPlayerService _audioService = AudioPlayerService();
  final PostService _postService = PostService();
  final UserService _userService = UserService();

  _SourceTab _tab = _SourceTab.recommended; // 初期表示はおすすめ
  List<TrackModel> _tracks = const [];
  bool _isLoading = false;
  bool _notConnected = false;
  TrackModel? _selectedTrack;
  String _currentSearchQuery = '';
  // 下部 Now Playing バー: 再生中かどうか（一時停止ボタンと再生ボタンの切替に使用）
  bool _isPlaying = false;

  // おすすめカルーセル（Figma 4530:10680）: 最初の getRecommendedTracks 結果の
  // 先頭 5 曲を確定してキャッシュ。タブ切替では変わらない。
  List<TrackModel> _recommendedTop5 = const [];
  int _carouselIndex = 0;
  final PageController _carouselController = PageController();

  // 選択中楽曲のアルバムアートから抽出したテーマ（バーの色決定に使う）。
  // 投稿カードと同じ ColorExtractor.extractThemeFromAlbumArt を利用。
  PostTheme? _selectedTrackTheme;
  String? _themeLoadingForUrl; // 競合判定用

  @override
  void initState() {
    super.initState();
    _loadInitialTracks();
  }

  @override
  void dispose() {
    _audioService.stop();
    _searchController.dispose();
    _carouselController.dispose();
    super.dispose();
  }

  // ───────────────────────────────────────────────────────────────
  // データ取得
  // ───────────────────────────────────────────────────────────────

  Future<void> _loadCurrentTab() async {
    switch (_tab) {
      case _SourceTab.recentlyPlayed:
        await _loadRecentlyPlayed();
        break;
      case _SourceTab.recommended:
        await _loadInitialTracks();
        break;
      case _SourceTab.saved:
        await _loadSavedTracks();
        break;
    }
  }

  Future<void> _loadInitialTracks() async {
    setState(() {
      _isLoading = true;
      _notConnected = false;
    });
    try {
      List<TrackModel> tracks =
          await _musicServiceManager.getRecommendedTracks(limit: 50);
      if (tracks.isEmpty) {
        tracks = await _musicServiceManager.searchTracks('J-POP 人気', limit: 25);
      }
      if (mounted) {
        setState(() {
          _tracks = tracks;
          // カルーセル用 Top5 は最初に取得した内容を確定させる
          //（タブ切替で消えない/入れ替わらない）
          if (_recommendedTop5.isEmpty && tracks.isNotEmpty) {
            _recommendedTop5 = tracks.take(5).toList();
          }
          _isLoading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _tracks = [];
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _loadRecentlyPlayed() async {
    setState(() {
      _isLoading = true;
      _notConnected = false;
    });
    try {
      final isAuthenticated = await _musicServiceManager.isAuthenticated();
      if (!isAuthenticated) {
        if (mounted) {
          setState(() {
            _tracks = [];
            _isLoading = false;
            _notConnected = true;
          });
        }
        return;
      }
      final tracks =
          await _musicServiceManager.getRecentlyPlayedTracks(limit: 30);
      if (mounted) {
        setState(() {
          _tracks = tracks;
          _isLoading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _tracks = [];
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _loadSavedTracks() async {
    setState(() {
      _isLoading = true;
      _notConnected = false;
    });
    try {
      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) {
        if (mounted) {
          setState(() {
            _tracks = [];
            _isLoading = false;
          });
        }
        return;
      }
      final results = await Future.wait([
        _postService.getPostsSavedByUser(currentUser.uid),
        _userService.getUser(currentUser.uid),
      ]);
      final savedPosts = results[0] as List;
      final me = results[1] as dynamic;

      final List<({DateTime savedAt, TrackModel track})> entries = [];
      final seen = <String>{};

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
      entries.sort((a, b) => b.savedAt.compareTo(a.savedAt));

      if (mounted) {
        setState(() {
          _tracks = entries.map((e) => e.track).toList();
          _isLoading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _tracks = [];
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _searchTracks(String query) async {
    final trimmed = query.trim();
    setState(() => _currentSearchQuery = trimmed);
    if (trimmed.isEmpty) {
      await _loadCurrentTab();
      return;
    }
    setState(() => _isLoading = true);
    try {
      final tracks =
          await _musicServiceManager.searchTracks(trimmed, limit: 20);
      if (mounted) {
        setState(() {
          _tracks = tracks;
          _isLoading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // ───────────────────────────────────────────────────────────────
  // 楽曲選択 & プレビュー再生
  // ───────────────────────────────────────────────────────────────

  void _toggleTrackSelection(TrackModel track) {
    if (_selectedTrack?.trackId == track.trackId) {
      setState(() {
        _selectedTrack = null;
        _selectedTrackTheme = null;
        _themeLoadingForUrl = null;
        _isPlaying = false;
      });
      _audioService.stop();
    } else {
      setState(() {
        _selectedTrack = track;
        _selectedTrackTheme = null; // 抽出中はフォールバック色を表示
        _isPlaying = true;
      });
      _playTrackPreview(track);
      _loadThemeForTrack(track);
    }
  }

  /// 投稿カードと同じ [ColorExtractor.extractThemeFromAlbumArt] でテーマを抽出。
  /// 抽出中に別の曲が選ばれた場合は結果を破棄する（レースガード）。
  Future<void> _loadThemeForTrack(TrackModel track) async {
    final url = track.albumImageUrl;
    if (url.isEmpty) return;
    _themeLoadingForUrl = url;
    try {
      final theme = await ColorExtractor.extractThemeFromAlbumArt(url);
      if (!mounted) return;
      // 抽出完了時点で既に別の曲が選ばれていれば反映しない
      if (_themeLoadingForUrl != url) return;
      if (_selectedTrack?.albumImageUrl != url) return;
      if (theme == null) return;
      setState(() => _selectedTrackTheme = theme);
    } catch (_) {
      // 抽出失敗時はフォールバック色のまま
    }
  }

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
    // レースコンディション: 非同期中に別曲が選ばれていたら何もしない
    if (!mounted || _selectedTrack?.trackId != track.trackId) return;
    if (previewUrl == null || previewUrl.isEmpty) return;

    // 取得した previewUrl を選択トラックに反映（次画面で使えるように）
    if ((track.previewUrl == null || track.previewUrl!.isEmpty) && mounted) {
      setState(() {
        _selectedTrack = track.copyWith(previewUrl: previewUrl);
      });
    }
    await _audioService.playPreview(previewUrl, durationSeconds: 15);
    if (mounted) setState(() => _isPlaying = true);
  }

  /// 「次へ」矢印タップで開く公開範囲選択プレビュー画面。
  /// Figma 4546:9255。下からスライドインで全画面表示。
  Future<void> _openPreview(TrackModel track) async {
    // Music Memory モード（Spotify）: Vibe プレビューを挟まず、選択トラックを
    // 親に返して Apple Music と同じ写真フロー（PostPhotoSelectionScreen）へ。
    if (widget.moodPostMode) {
      widget.onTrackChosen?.call(_selectedTrack ?? track);
      if (mounted) Navigator.of(context).maybePop();
      return;
    }
    // プレビュー画面でも再生継続したいので audio はそのまま
    final currentUser = FirebaseAuth.instance.currentUser;
    String? iconUrl;
    if (currentUser != null) {
      try {
        final me = await _userService.getUser(currentUser.uid);
        iconUrl = me?.profileImageUrl;
      } catch (_) {}
    }
    if (!mounted) return;
    await VibeStoryPreviewScreen.pushWithSlideUp<void>(
      context,
      track: track,
      authorIconUrl: iconUrl,
      onAudienceSelected: (audience) {
        // 親フローへ通知（投稿モードの選択を保持）
        widget.onTrackChosen?.call(track);
        // 既存シートも閉じる（投稿フローは後続で組み込み）
        if (mounted) Navigator.of(context).maybePop();
      },
    );
  }

  /// Now Playing バーの「再生/一時停止」トグル
  Future<void> _togglePlayPause() async {
    final track = _selectedTrack;
    if (track == null) return;
    if (_isPlaying) {
      await _audioService.pause();
      if (mounted) setState(() => _isPlaying = false);
    } else {
      // previewUrl があれば再開、無ければ再フェッチ
      if (track.previewUrl != null && track.previewUrl!.isNotEmpty) {
        await _audioService.resume();
        if (mounted) setState(() => _isPlaying = true);
      } else {
        await _playTrackPreview(track);
      }
    }
  }

  // ───────────────────────────────────────────────────────────────
  // build
  // ───────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final mediaInsets = MediaQuery.of(context).viewInsets.bottom;

    return Padding(
      padding: EdgeInsets.only(bottom: mediaInsets),
      child: Container(
        decoration: const BoxDecoration(
          color: Color(0xFF171C1F),
          borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
        ),
        child: Stack(
          children: [
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildHandle(),
                _buildSearchBar(),
                const SizedBox(height: 13),
                _buildTabs(),
                const SizedBox(height: 7),
                _buildVibeLabel(),
                const SizedBox(height: 7),
                _buildRecommendationCarousel(),
                const SizedBox(height: 16),
                // リストは画面下端まで流す（バーの背後にも続く）→ 半透明バーから
                // リスト項目が透けて見えるホームナビバー風の見た目になる。
                // ListView 側 padding で最終行がバーに隠れないようスクロール余白を確保。
                Expanded(child: _buildBody()),
              ],
            ),
            // 楽曲選択中だけ表示する下部固定バー（画面底辺から 36px 浮かせる）。
            //
            // 色抽出が終わるまではバー本体を非表示（フォールバック色のチラつき防止）。
            // AnimatedSwitcher は **常時マウント** しないと初回 transition が発火しないため、
            // 空の SizedBox と bar を入れ替える形にする。曲を切り替えたときも key が
            // 変わって SlideTransition + FadeTransition が走る。
            Positioned(
              left: 10,
              right: 10,
              bottom: 36,
              child: IgnorePointer(
                // 非表示中（SizedBox.shrink）のときも Positioned はクリックを奪うため、
                // bar が無い時はタップを下層に通す。
                ignoring:
                    _selectedTrack == null || _selectedTrackTheme == null,
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 220),
                  switchInCurve: Curves.easeOutCubic,
                  switchOutCurve: Curves.easeIn,
                  transitionBuilder: (child, anim) => SlideTransition(
                    position: Tween<Offset>(
                      begin: const Offset(0, 1.0), // バー高さぶん下から
                      end: Offset.zero,
                    ).animate(anim),
                    child: FadeTransition(
                      opacity: anim,
                      child: child,
                    ),
                  ),
                  child: (_selectedTrack == null ||
                          _selectedTrackTheme == null)
                      ? const SizedBox.shrink(key: ValueKey('__bar_empty__'))
                      : KeyedSubtree(
                          key: ValueKey(_selectedTrack!.trackId),
                          child: _buildNowPlayingBar(_selectedTrack!),
                        ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── ヘッダー要素 ───────────────────────────────────────────────

  Widget _buildHandle() {
    return Container(
      width: 56,
      height: 4,
      margin: const EdgeInsets.only(top: 10, bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(2),
      ),
    );
  }

  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Container(
        height: 36,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          color: const Color(0xFF293038),
          borderRadius: BorderRadius.circular(11),
        ),
        child: Row(
          children: [
            const Icon(Icons.search, color: Colors.white54, size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                controller: _searchController,
                onChanged: _searchTracks,
                style: const TextStyle(color: Colors.white, fontSize: 13),
                decoration: const InputDecoration(
                  isDense: true,
                  contentPadding: EdgeInsets.zero,
                  border: InputBorder.none,
                  hintText: '楽曲を検索',
                  hintStyle:
                      TextStyle(color: Colors.white38, fontSize: 13),
                ),
              ),
            ),
            if (_currentSearchQuery.isNotEmpty)
              GestureDetector(
                onTap: () {
                  _searchController.clear();
                  _searchTracks('');
                },
                child: const Icon(Icons.close,
                    color: Colors.white54, size: 16),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildTabs() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          _buildTabChip(
            label: '最近聞いた曲',
            tab: _SourceTab.recentlyPlayed,
            width: 73,
          ),
          const SizedBox(width: 10),
          _buildTabChip(
            label: 'おすすめ',
            tab: _SourceTab.recommended,
            width: 62,
          ),
          const SizedBox(width: 10),
          _buildTabChip(
            label: '保存済み',
            tab: _SourceTab.saved,
            width: 61,
          ),
        ],
      ),
    );
  }

  Widget _buildTabChip({
    required String label,
    required _SourceTab tab,
    required double width,
  }) {
    final selected = _tab == tab;
    return GestureDetector(
      onTap: () async {
        if (_tab == tab) return;
        setState(() {
          _tab = tab;
          _searchController.clear();
          _currentSearchQuery = '';
        });
        await _audioService.stop();
        _selectedTrack = null;
        await _loadCurrentTab();
      },
      child: Container(
        width: width,
        height: 31,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? Colors.white : const Color(0xFF293038),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? Colors.black : Colors.white,
            fontSize: 9,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }

  Widget _buildVibeLabel() {
    // Figma 4530:10679: 「Vibe【#topic】」+ 改行 +「🎧おすすめ」
    // - Vibe: 16px semibold / 【】: 11px semibold / おすすめ: 11px semibold
    // - おすすめ行は先頭に headphones アイコンを置く（Figma では絵文字 🎧）
    //
    // NOTE: 外側 Column の crossAxisAlignment がデフォルト center なので、
    // ここが intrinsic 幅（テキスト分だけ）だと親にセンタリングされて左端に
    // 揃わない。SizedBox(width: infinity) で必ずシート全幅を取らせる。
    final title = widget.topic?.title ?? '今日のお題';
    return SizedBox(
      width: double.infinity,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
          // Music Memory モード（Spotify）ではお題ヘッダー（Vibe【#…】）を非表示。
          if (!widget.moodPostMode) ...[
            RichText(
              text: TextSpan(
                children: [
                  const TextSpan(
                    text: 'Vibe',
                    style: TextStyle(
                      fontSize: 16,
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  TextSpan(
                    text: '【#$title】',
                    style: const TextStyle(
                      fontSize: 11,
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 4),
          ],
          const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.headphones, color: Colors.white, size: 14),
              SizedBox(width: 4),
              Text(
                'おすすめ',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ],
        ),
      ),
    );
  }

  // ── おすすめカルーセル（Figma 4530:10680）───────────────────────
  //
  // カード仕様（Figma）:
  //   - 全体 370×56 / 角丸 13 / 白ベース
  //   - 左 0,0: 56×56 の低解像アルバムアート
  //   - 右 56 以降: 同じアルバムアートをブラー sigma 5.8 で敷き、
  //     カラフルな背景として使う（Figma 上は 314×315 を top:-129 で敷いている
  //     ＝上下トリミングされた「アルバム中央帯」を使う。実装は BoxFit.cover）
  //   - タイトル: (65, 12) #393939 / 13px semibold
  //   - アーティスト: 下段 #A19E9D / 11px
  //
  // カルーセル本体:
  //   - PageView.builder（1ページ=1カード, viewportFraction=1.0）
  //   - 下部にドット indicator（5個・6×6・3px 間隔）
  //   - カードタップは通常のリスト行タップと同じく _toggleTrackSelection
  Widget _buildRecommendationCarousel() {
    final items = _recommendedTop5;
    if (items.isEmpty) return const SizedBox.shrink();
    return Column(
      children: [
        SizedBox(
          height: 56,
          child: PageView.builder(
            controller: _carouselController,
            itemCount: items.length,
            onPageChanged: (i) => setState(() => _carouselIndex = i),
            itemBuilder: (context, i) => Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: _buildRecommendationCard(items[i]),
            ),
          ),
        ),
        const SizedBox(height: 15),
        _buildCarouselDots(items.length),
      ],
    );
  }

  Widget _buildRecommendationCard(TrackModel track) {
    final selected = _selectedTrack?.trackId == track.trackId;
    return GestureDetector(
      onTap: () => _toggleTrackSelection(track),
      behavior: HitTestBehavior.opaque,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(13),
        child: SizedBox(
          height: 56,
          child: Stack(
            children: [
              // 白ベース
              const Positioned.fill(child: ColoredBox(color: Colors.white)),
              // 右側にブラーしたアルバムアートを敷く
              Positioned(
                left: 56,
                right: 0,
                top: 0,
                bottom: 0,
                child: ClipRect(
                  child: track.albumImageUrl.isNotEmpty
                      ? ImageFiltered(
                          imageFilter: ImageFilter.blur(
                              sigmaX: 5.8, sigmaY: 5.8),
                          child: Image.network(
                            track.albumImageUrl,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) =>
                                const SizedBox.shrink(),
                          ),
                        )
                      : const SizedBox.shrink(),
                ),
              ),
              // 左端アルバムアート 56×56
              SizedBox(
                width: 56,
                height: 56,
                child: track.albumImageUrl.isNotEmpty
                    ? Image.network(
                        track.albumImageUrl,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => _recommendPlaceholder(),
                      )
                    : _recommendPlaceholder(),
              ),
              // テキスト（タイトル + アーティスト）
              Positioned(
                left: 65,
                right: 12,
                top: 12,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      track.trackName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xFF393939),
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        height: 1.36,
                      ),
                    ),
                    Text(
                      track.artistName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xFFA19E9D),
                        fontSize: 11,
                        height: 1.57,
                      ),
                    ),
                  ],
                ),
              ),
              // 選択中の視覚フィードバック（うっすら青枠）
              if (selected)
                Positioned.fill(
                  child: IgnorePointer(
                    child: Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(13),
                        border: Border.all(
                          color: const Color(0xFF3D5AF1),
                          width: 1.5,
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

  Widget _recommendPlaceholder() => Container(
        width: 56,
        height: 56,
        color: const Color(0xFF2A2A2A),
        alignment: Alignment.center,
        child: const Icon(Icons.music_note, color: Colors.white54, size: 22),
      );

  // 現在位置からの距離でドットサイズを段階的に小さくする
  // （素材画像「おすすめバナーのスライド点.png」に準拠）
  double _dotSizeForDistance(int distance) {
    switch (distance) {
      case 0:
        return 10.0;
      case 1:
        return 8.0;
      case 2:
        return 7.0;
      case 3:
        return 5.0;
      default:
        return 3.0;
    }
  }

  Widget _buildCarouselDots(int count) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: List.generate(count, (i) {
        final distance = (i - _carouselIndex).abs();
        final active = distance == 0;
        final size = _dotSizeForDistance(distance);
        return AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          margin: const EdgeInsets.symmetric(horizontal: 3),
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color:
                active ? const Color(0xFF3B82F6) : const Color(0xFF3F4750),
          ),
        );
      }),
    );
  }

  // ── 本体 ─────────────────────────────────────────────────────

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(
        child: CupertinoActivityIndicator(color: Colors.white, radius: 12),
      );
    }
    if (_notConnected) {
      return _buildNotConnected();
    }
    if (_tracks.isEmpty) {
      return Center(
        child: Text(
          _currentSearchQuery.isNotEmpty
              ? '「$_currentSearchQuery」に一致する楽曲が見つかりません'
              : '楽曲が見つかりません',
          style: const TextStyle(color: Colors.white54, fontSize: 13),
        ),
      );
    }
    // バーが画面下端から 36 + 56 = 92px の領域を占めるため、
    // 楽曲選択中はリスト末尾にその分の余白を入れて最終行が隠れないようにする。
    // バー自体は半透明なので、スクロール中はリストがバー越しに見える。
    final bottomPadding = _selectedTrack != null ? 36.0 + 56.0 + 12.0 : 24.0;
    return ListView.builder(
      padding: EdgeInsets.only(bottom: bottomPadding),
      itemCount: _tracks.length,
      itemBuilder: (context, index) {
        final track = _tracks[index];
        final isSelected = _selectedTrack?.trackId == track.trackId;
        return MusicTrackListItem(
          track: track,
          isSelected: isSelected,
          onTap: () => _toggleTrackSelection(track),
        );
      },
    );
  }

  /// 下部固定の「Now Playing バー」。Figma: Frame 4530:10732 (w=386, h=56)。
  /// 仕様:
  ///   - 角丸 16px、背景は抽出色 × opacity 90%（楽曲一覧が透けて見える）
  ///   - アルバムアート 32×32、角丸 8px
  ///   - 一時停止 = 2本バー、再生 = 三角、サイズ 16×20
  ///   - 「次へ」= 28×28 円 + 矢印
  ///
  /// 色は **投稿カードと同じ ColorExtractor** で抽出した PostTheme を使う。
  Widget _buildNowPlayingBar(TrackModel track) {
    final theme = _selectedTrackTheme;
    final Color baseColor = theme?.gradientEnd ?? const Color(0xFFC9DD77);
    final Color background = baseColor.withValues(alpha: 0.9);
    final Color foreground = theme?.textColor ?? Colors.black;
    final Color secondary =
        theme?.secondaryTextColor ?? const Color(0xFF878179);
    // 「次へ」ボタンの円は前景色（黒/白）を採用、矢印はその反転色
    final Color nextCircle = foreground;
    final Color nextArrow =
        foreground.computeLuminance() > 0.5 ? Colors.black : Colors.white;
    // 再生/一時停止アイコンは前景色（白系のときに白バーで視認性確保）
    final Color playPauseColor = foreground;

    return Container(
      height: 56,
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          const SizedBox(width: 16),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: track.albumImageUrl.isNotEmpty
                ? Image.network(
                    track.albumImageUrl,
                    width: 32,
                    height: 32,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => _albumPlaceholder(),
                  )
                : _albumPlaceholder(),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  track.trackName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: foreground,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  track.artistName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: secondary,
                    fontSize: 11,
                    fontWeight: FontWeight.w400,
                  ),
                ),
              ],
            ),
          ),
          // 再生/一時停止トグル
          // pause = 2本バー（高さ20）。play は Material アイコンの内側余白が大きいため、
          // 視覚的に同じ大きさに見えるよう size=28 で描く。
          GestureDetector(
            onTap: _togglePlayPause,
            behavior: HitTestBehavior.opaque,
            child: SizedBox(
              width: 28,
              height: 28,
              child: Center(
                child: _isPlaying
                    ? _PauseIcon(color: playPauseColor)
                    : Icon(Icons.play_arrow,
                        color: playPauseColor, size: 28),
              ),
            ),
          ),
          const SizedBox(width: 10),
          // 「次へ」ボタン → 公開範囲選択プレビュー画面を下からスライドイン
          GestureDetector(
            onTap: () => _openPreview(track),
            behavior: HitTestBehavior.opaque,
            child: Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: nextCircle,
              ),
              alignment: Alignment.center,
              child: Icon(
                Icons.arrow_forward,
                color: nextArrow,
                size: 16,
              ),
            ),
          ),
          const SizedBox(width: 16),
        ],
      ),
    );
  }

  Widget _albumPlaceholder() => Container(
        width: 32,
        height: 32,
        color: const Color(0xFF2A2A2A),
        alignment: Alignment.center,
        child: const Icon(Icons.music_note, color: Colors.white54, size: 18),
      );

  Widget _buildNotConnected() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.music_off, color: Colors.white54, size: 36),
            const SizedBox(height: 12),
            Text(
              _tab == _SourceTab.recentlyPlayed
                  ? '最近聞いた曲を表示するには\nSpotify または Apple Music の連携が必要です'
                  : '音楽サービスの連携が必要です',
              style: const TextStyle(color: Colors.white70, fontSize: 13),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

/// Figma 仕様の 2 本バー pause アイコン（16×20 の縦長バー × 2）
class _PauseIcon extends StatelessWidget {
  final Color color;
  const _PauseIcon({required this.color});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 16,
      height: 20,
      child: Row(
        children: [
          Container(
            width: 6,
            height: 20,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(1),
            ),
          ),
          const Spacer(),
          Container(
            width: 6,
            height: 20,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(1),
            ),
          ),
        ],
      ),
    );
  }
}

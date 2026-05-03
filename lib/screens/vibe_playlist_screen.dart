import 'dart:async';
import 'dart:math' as math;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:url_launcher/url_launcher.dart';
import '../constants/app_colors.dart';
import '../models/music_service_type.dart';
import '../models/post_model.dart';
import '../models/track_model.dart';
import '../models/vibe_ranking_item.dart';
import '../models/vibe_topic_model.dart';
import '../services/audio_player_service.dart';
import '../services/tutorial_controller.dart';
import '../widgets/tutorial/animated_hand_cursor.dart';
import '../widgets/tutorial/tutorial_coachmark.dart';
import '../services/itunes_search_service.dart';
import '../services/music_service_manager.dart';
import '../services/post_service.dart';
import '../services/user_service.dart';
import '../widgets/profile_widgets.dart';
import 'comment_screen.dart';
import 'music_selection_screen.dart';
import 'post_preview_screen.dart';

/// Vibeプレイリスト画面
/// - 投稿タブ: TikTok形式でVibe投稿を全画面スクロール
/// - 曲リストタブ: ランキング曲一覧
class VibePlaylistScreen extends StatefulWidget {
  final VibeTopicModel topic;
  final List<VibeRankingItem> ranking;
  final String currentUserId;
  final bool hasPostedToday;

  const VibePlaylistScreen({
    super.key,
    required this.topic,
    required this.ranking,
    required this.currentUserId,
    this.hasPostedToday = false,
  });

  @override
  State<VibePlaylistScreen> createState() => _VibePlaylistScreenState();
}

class _VibePlaylistScreenState extends State<VibePlaylistScreen>
    with TickerProviderStateMixin {
  late TabController _tabController;
  late PageController _tabPageController;
  int _selectedTab = 0; // 0=投稿, 1=曲リスト
  List<PostModel>? _posts;
  bool _isLoading = true;

  // Figma: card 814px + gap 8px = page 822px
  // viewportFraction を実際の画面高さで割ることで、機種問わず常に814pxのカード高さを維持する
  PageController? _pageController;
  final AudioPlayerService _audioService = AudioPlayerService();
  final ITunesSearchService _itunesService = ITunesSearchService();
  final PostService _postService = PostService();
  final UserService _userService = UserService();

  int _currentPage = 0;
  final Map<int, String?> _previewUrlCache = {};
  final Map<String, int> _likeCountCache = {};
  final Map<String, bool> _isLikedCache = {};
  final Map<String, bool> _isSavedCache = {};

  // 各投稿のランキングアイテムをキャッシュ
  final Map<String, VibeRankingItem?> _rankingItemCache = {};

  // 並び替え済みランキング (postCount desc → trackName asc)
  late final List<VibeRankingItem> _sortedRanking;

  // サマリー画像の固定スロット（写真2 + ジャケット2、ランダム抽選を一度だけ）
  List<String> _summaryImages = const [];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabPageController = PageController();
    _tabController.addListener(_onTabControllerChanged);
    _sortedRanking = _sortRanking(widget.ranking);
    _loadPosts();
  }

  void _onTabControllerChanged() {
    if (_tabController.indexIsChanging) return;
    if (_tabPageController.hasClients) {
      _tabPageController.animateToPage(
        _tabController.index,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeInOut,
      );
    }
    if (_selectedTab != _tabController.index) {
      setState(() => _selectedTab = _tabController.index);
    }
  }

  List<VibeRankingItem> _sortRanking(List<VibeRankingItem> source) {
    final list = List<VibeRankingItem>.of(source);
    list.sort((a, b) {
      final byCount = b.postCount.compareTo(a.postCount);
      if (byCount != 0) return byCount;
      return a.track.trackName.compareTo(b.track.trackName);
    });
    return list;
  }

  /// _posts と ranking から「写真2 + ジャケット2」をランダム抽選してキャッシュ
  void _buildSummaryImages() {
    final rng = math.Random(widget.topic.topicId.hashCode);
    final photos = <String>[
      for (final p in (_posts ?? const <PostModel>[]))
        if (p.photoUrl != null && p.photoUrl!.startsWith('http')) p.photoUrl!,
    ]..shuffle(rng);
    final jackets = <String>[
      for (final r in _sortedRanking)
        if (r.track.albumImageUrl.isNotEmpty) r.track.albumImageUrl,
    ]..shuffle(rng);

    // 左・中央: 写真のみ、右上・右下: アルバムアートのみ（不足時は空文字）
    _summaryImages = [
      photos.isNotEmpty ? photos[0] : '',
      photos.length > 1 ? photos[1] : '',
      jackets.isNotEmpty ? jackets[0] : '',
      jackets.length > 1 ? jackets[1] : '',
    ];
  }

  @override
  void dispose() {
    _tabController.removeListener(_onTabControllerChanged);
    _tabController.dispose();
    _tabPageController.dispose();
    _pageController?.dispose();
    _audioService.dispose();
    super.dispose();
  }

  Future<void> _loadPosts() async {
    try {
      final posts = await _postService.getVibePostsByTopic(
        widget.topic.topicId,
        DateTime.now(),
      );
      if (!mounted) return;
      setState(() {
        _posts = posts;
        _isLoading = false;
        _buildSummaryImages();
      });
      if (posts.isNotEmpty) {
        _playMusicForPage(0);
      }
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _playMusicForPage(int index) async {
    if (_posts == null || index >= _posts!.length) return;
    final post = _posts![index];

    if (!_previewUrlCache.containsKey(index)) {
      final url = await _itunesService.getPreviewUrl(
        trackName: post.track.trackName,
        artistName: post.track.artistName,
      );
      _previewUrlCache[index] = url;
    }

    final url = _previewUrlCache[index];
    if (url != null && mounted) {
      await _audioService.playPreview(url);
    }
    // 隣接（次ページ）の音声をプリロードしておく
    _preloadNeighborAudio(index);
  }

  /// 次ページの楽曲を事前 setUrl してタップ→再生のネットワーク待ちを排除
  void _preloadNeighborAudio(int currentIndex) {
    final posts = _posts;
    if (posts == null) return;
    final next = currentIndex + 1;
    if (next >= posts.length) return;
    final url = _previewUrlCache[next];
    if (url == null || url.isEmpty) {
      // URL未取得の場合はバックグラウンドで取りに行く（次回 page change で間に合わせる）
      final nextPost = posts[next];
      unawaited(_itunesService
          .getPreviewUrl(
        trackName: nextPost.track.trackName,
        artistName: nextPost.track.artistName,
      )
          .then((u) {
        if (!mounted) return;
        _previewUrlCache[next] = u;
        if (u != null && u.isNotEmpty) {
          _audioService.preload(u);
        }
      }));
      return;
    }
    _audioService.preload(url);
  }

  void _onPageChanged(int index) {
    setState(() => _currentPage = index);
    _playMusicForPage(index);
    // チュートリアルの上スワイプ完了検出
    if (TutorialController.instance.step == TutorialStep.swipeUpInPlaylist) {
      TutorialController.instance.complete();
    }
  }

  VibeRankingItem? _rankingFor(PostModel post) {
    final key = post.postId;
    if (_rankingItemCache.containsKey(key)) return _rankingItemCache[key];

    final trackKey = post.track.trackId.isNotEmpty
        ? post.track.trackId
        : '${post.track.trackName}_${post.track.artistName}';

    final found = _sortedRanking.cast<VibeRankingItem?>().firstWhere(
      (r) {
        if (r == null) return false;
        final rKey = r.track.trackId.isNotEmpty
            ? r.track.trackId
            : '${r.track.trackName}_${r.track.artistName}';
        return rKey == trackKey;
      },
      orElse: () => null,
    );

    _rankingItemCache[key] = found;
    return found;
  }

  /// 楽曲未指定で投稿フローへ（楽曲選択から）
  Future<void> _navigateToVibePost() async {
    _audioService.stop();
    await Navigator.push<int>(
      context,
      PageRouteBuilder(
        pageBuilder: (_, __, ___) =>
            const MusicSelectionScreen(initialCategoryType: 'vibe', fromVibePlaylist: true),
        transitionDuration: Duration.zero,
        reverseTransitionDuration: Duration.zero,
      ),
    );
  }

  /// 指定の楽曲で投稿フロー（カード反転起点）へ直接遷移
  /// 音符ボタン・モーダルの「楽曲をVibeに追加」から呼び出し
  Future<void> _navigateToPostPreviewWithTrack(TrackModel track) async {
    _audioService.stop();
    if (!mounted) return;
    await Navigator.push(
      context,
      PageRouteBuilder(
        pageBuilder: (_, __, ___) => PostPreviewScreen(
          track: track,
          isVibe: true,
          vibeTopicId: widget.topic.topicId,
          vibeTopicTitle: widget.topic.title,
          fromVibePlaylist: true,
        ),
        transitionsBuilder: (context, animation, _, child) {
          final tween = Tween(begin: const Offset(0, 1), end: Offset.zero)
              .chain(CurveTween(curve: Curves.easeOutCubic));
          return SlideTransition(position: animation.drive(tween), child: child);
        },
        transitionDuration: const Duration(milliseconds: 350),
      ),
    );
  }

  /// 曲行タップで開くモーダル（Figma 3870:6805 仕様）
  Future<void> _showSongModal(VibeRankingItem item) async {
    // この楽曲を使った投稿の写真を抽出（trackId or trackName+artistNameでマッチ）
    final trackKey = item.track.trackId.isNotEmpty
        ? item.track.trackId
        : '${item.track.trackName}_${item.track.artistName}';
    final photos = <String>[
      for (final p in (_posts ?? const <PostModel>[]))
        if ((p.photoUrl ?? '').startsWith('http') &&
            (p.track.trackId.isNotEmpty
                    ? p.track.trackId
                    : '${p.track.trackName}_${p.track.artistName}') ==
                trackKey)
          p.photoUrl!,
    ];

    final matchingPost = (_posts ?? []).cast<PostModel?>().firstWhere(
      (p) => p != null && (
        p.track.trackId.isNotEmpty
          ? p.track.trackId == item.track.trackId
          : '${p.track.trackName}_${p.track.artistName}' == trackKey
      ),
      orElse: () => null,
    );
    final isSaved = matchingPost != null
        ? (_isSavedCache[matchingPost.postId] ??
            matchingPost.savedByUserIds.contains(widget.currentUserId))
        : false;

    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true, // 背の高いモーダル + 内部スクロール
      builder: (ctx) => _SongActionSheet(
        item: item,
        photos: photos,
        isSaved: isSaved,
        onPlayFull: () {
          Navigator.of(ctx).pop();
          _openExternalMusicService(item.track);
        },
        onAddToVibe: () {
          Navigator.of(ctx).pop();
          _navigateToPostPreviewWithTrack(item.track);
        },
        onSave: () {
          if (matchingPost != null) _handleSave(matchingPost);
        },
      ),
    );
  }

  /// Apple Music / Spotify を外部で開く（ユーザーの優先サービスに従う）
  Future<void> _openExternalMusicService(TrackModel track) async {
    final manager = MusicServiceManager();
    final selected = await manager.getSelectedService();
    final service = selected == MusicServiceType.spotify
        ? MusicServiceType.spotify
        : MusicServiceType.appleMusic; // 未設定/none は Apple Music
    final query = Uri.encodeComponent('${track.trackName} ${track.artistName}');
    final url = service == MusicServiceType.spotify
        ? 'https://open.spotify.com/search/$query'
        : 'https://music.apple.com/jp/search?term=$query';
    final uri = Uri.parse(url);
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('音楽サービスを開けませんでした')),
        );
      }
    }
  }

  int get _totalUsers {
    final ids = <String>{};
    for (final r in _sortedRanking) {
      ids.addAll(r.userIds);
    }
    return ids.length;
  }

  String _fmt(int n) {
    if (n >= 10000) return '${(n / 10000).toStringAsFixed(n % 10000 != 0 ? 1 : 0)}万';
    if (n >= 1000) return '${(n / 1000).toStringAsFixed(n % 1000 != 0 ? 1 : 0)}K';
    return n.toString();
  }

  // ────────────────────────────────────────────
  // BUILD
  // ────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final topPadding = MediaQuery.of(context).padding.top;
    final screenH = MediaQuery.of(context).size.height;
    // PageView の viewportFraction は 0..1 の範囲が安全。
    // 小型端末（screenH < 822）では 1.0 にクランプして崩れを防ぐ。
    final fraction = screenH > 0
        ? (822.0 / screenH).clamp(0.5, 1.0)
        : 1.0;
    _pageController ??= PageController(viewportFraction: fraction);

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: AppColors.background,
        body: Stack(
          children: [
            // ── コンテンツ（横スワイプで投稿⇔曲リスト） ──
            Positioned.fill(
              child: PageView(
                controller: _tabPageController,
                onPageChanged: (index) {
                  _tabController.animateTo(index);
                  setState(() => _selectedTab = index);
                },
                children: [
                  _buildPostsTab(),
                  Padding(
                    padding: EdgeInsets.only(top: topPadding + 35 + 32),
                    child: _buildSongListTab(),
                  ),
                ],
              ),
            ),

            // ── 上部グラデーション（投稿タブ用・テキスト可読性） ──
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              height: topPadding + 35 + 31 + 20,
              child: AnimatedBuilder(
                animation: _tabPageController,
                builder: (context, _) {
                  final t = _tabPageController.hasClients
                      ? (_tabPageController.page ?? _tabController.index.toDouble()).clamp(0.0, 1.0)
                      : _tabController.index.toDouble();
                  // 投稿タブ(t=0)で不透明、曲リストタブ(t=1)で透明
                  final opacity = (1.0 - t).clamp(0.0, 1.0);
                  if (opacity == 0.0) return const SizedBox.shrink();
                  return Opacity(
                    opacity: opacity,
                    child: const DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [Color(0xCC000000), Colors.transparent],
                        ),
                      ),
                      child: SizedBox.expand(),
                    ),
                  );
                },
              ),
            ),

            // ── ヘッダー＋タブバー（常に前面） ──
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: AnimatedBuilder(
                animation: _tabPageController,
                builder: (context, child) {
                  final t = _tabPageController.hasClients
                      ? (_tabPageController.page ?? _tabController.index.toDouble()).clamp(0.0, 1.0)
                      : _tabController.index.toDouble();
                  return Container(
                    color: AppColors.background.withValues(alpha: t),
                    child: child,
                  );
                },
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(height: topPadding),
                    _buildHeader(),
                    _buildTabBar(),
                  ],
                ),
              ),
            ),

            // チュートリアル: 上スワイプ誘導
            Positioned.fill(
              child: ListenableBuilder(
                listenable: TutorialController.instance,
                builder: (context, _) {
                  final active = TutorialController.instance.step ==
                      TutorialStep.swipeUpInPlaylist;
                  return TutorialCoachmark(
                    active: active,
                    text: '上にスワイプしてください',
                    subText: '次の投稿を見てみよう',
                    handVariant: HandCursorVariant.swipeUp,
                    placement: CoachmarkPlacement.center,
                    handSize: 64,
                    dimOpacity: 0.4,
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Figma: header h=35
  //   タイトル top=6 fontSize=13 bold center
  //   サブタイトル top=23 fontSize=10 color=#B7BCC0 center
  //   戻るボタン left=11 top=0 size=33
  Widget _buildHeader() {
    return SizedBox(
      height: 35,
      width: double.infinity,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // タイトル（top=6, 中央寄せ）
          Positioned(
            left: 0,
            right: 0,
            top: 6,
            child: Text(
              '#${widget.topic.title}',
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.bold,
                color: Colors.white,
                height: 1.0,
              ),
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          // サブタイトル（top=23, 中央寄せ）
          Positioned(
            left: 0,
            right: 0,
            top: 23,
            child: Text(
              '🔥${_fmt(_totalUsers)}人が追加・${_sortedRanking.length}曲',
              style: const TextStyle(
                fontSize: 10,
                color: Color(0xFFB7BCC0),
                height: 1.0,
              ),
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          // 戻るボタン（left=11, top=0, size=33）
          Positioned(
            left: 11,
            top: 0,
            width: 33,
            height: 33,
            child: GestureDetector(
              onTap: () {
                _audioService.stop();
                Navigator.of(context).pop();
              },
              behavior: HitTestBehavior.opaque,
              child: const Icon(
                Icons.chevron_left,
                color: Colors.white,
                size: 28,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── タブバー ──────────────────────────────────

  Widget _buildTabBar() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          height: 31,
          child: Stack(
            children: [
              // タブボタン
              Row(
                children: [
                  _buildTabButton(label: '投稿', index: 0),
                  _buildTabButton(label: '曲リスト', index: 1),
                ],
              ),
              // スライドインジケーター
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: AnimatedBuilder(
                  animation: _tabPageController,
                  builder: (context, _) {
                    final screenWidth = MediaQuery.of(context).size.width;
                    final tabWidth = screenWidth / 2;
                    const indicatorWidth = 64.0;
                    final t = _tabPageController.hasClients
                        ? (_tabPageController.page ?? _tabController.index.toDouble()).clamp(0.0, 1.0)
                        : _tabController.index.toDouble();
                    final left = tabWidth * (0.625 + 0.75 * t) - indicatorWidth / 2;
                    return SizedBox(
                      height: 2,
                      child: Stack(
                        children: [
                          Positioned(
                            left: left,
                            width: indicatorWidth,
                            top: 0,
                            bottom: 0,
                            child: Container(
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(1),
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildTabButton({required String label, required int index}) {
    final align = index == 0 ? const Alignment(0.25, 0) : const Alignment(-0.25, 0);
    return Expanded(
      child: GestureDetector(
        onTap: () => _tabController.animateTo(index),
        behavior: HitTestBehavior.opaque,
        child: Align(
          alignment: align,
          child: AnimatedBuilder(
            animation: _tabPageController,
            builder: (context, _) {
              final t = _tabPageController.hasClients
                  ? (_tabPageController.page ?? _tabController.index.toDouble()).clamp(0.0, 1.0)
                  : _tabController.index.toDouble();
              final opacity = index == 0 ? (1.0 - t) : t;
              return Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: Colors.white.withValues(alpha: 0.4 + 0.6 * opacity),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  // ────────────────────────────────────────────
  // 投稿タブ（全画面 PageView）
  // ────────────────────────────────────────────

  Widget _buildPostsTab() {
    if (_isLoading) {
      return const Center(
        child: CupertinoActivityIndicator(color: Colors.white, radius: 14),
      );
    }
    if (_posts == null || _posts!.isEmpty) {
      return const Center(
        child: Text('まだ投稿がありません',
            style: TextStyle(color: Colors.white, fontSize: 14)),
      );
    }
    // padEnds:false で先頭ページが上端に揃い、各ページ下に次カードがピーク
    return PageView.builder(
      scrollDirection: Axis.vertical,
      controller: _pageController!,
      pageSnapping: true,
      padEnds: false,
      itemCount: _posts!.length,
      onPageChanged: _onPageChanged,
      itemBuilder: (context, index) {
        final post = _posts![index];
        return _buildVibePostCard(post, _rankingFor(post));
      },
    );
  }

  // Figmaの各「ページ」は 822px (card 814 + gap 8)。下部 8px は次カードへの余白。
  Widget _buildVibePostCard(PostModel post, VibeRankingItem? rankingItem) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(23),
        child: Stack(
          children: [
            // 背景写真
            Positioned.fill(child: _buildPhotoBackground(post)),


            // 下部コンテンツ（275px）
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              height: 275,
              child: _buildCardBottom(post, rankingItem),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPhotoBackground(PostModel post) {
    final hasPhoto = post.photoUrl != null &&
        post.photoUrl!.isNotEmpty &&
        post.photoUrl!.startsWith('http');
    final url = hasPhoto ? post.photoUrl! : post.track.albumImageUrl;

    if (url.isEmpty) return Container(color: Colors.grey[900]);

    // アルバムアートはレイアウト情報なし → BoxFit.cover のみ
    if (!hasPhoto) {
      return CachedNetworkImage(
        imageUrl: url,
        fit: BoxFit.cover,
        errorWidget: (_, __, ___) => Container(color: Colors.grey[900]),
      );
    }

    // 投稿写真: 投稿カード裏面と同じレイアウトを再現
    return LayoutBuilder(
      builder: (context, constraints) {
        final cardW = constraints.maxWidth;
        final cardH = constraints.maxHeight;
        final imgScale = post.imageScale != 0 ? post.imageScale : 1.0;
        final natW = post.imageNaturalWidth;
        final natH = post.imageNaturalHeight;

        final image = CachedNetworkImage(
          imageUrl: url,
          fit: BoxFit.fill,
          errorWidget: (_, __, ___) => Container(color: Colors.grey[900]),
        );

        if (natW > 0 && natH > 0) {
          // 新方式: 投稿カード裏面と同じ計算（363基準スケール）
          final scaleFactor = cardW / 363.0;
          final baseScale = cardH / natH;
          final displayW = natW * baseScale;
          final displayH = natH * baseScale;

          return Stack(
            clipBehavior: Clip.hardEdge,
            children: [
              Positioned(
                left: post.imageOffsetX * scaleFactor,
                top: post.imageOffsetY * scaleFactor,
                child: Transform.scale(
                  scale: imgScale,
                  alignment: Alignment.topLeft,
                  child: SizedBox(
                    width: displayW,
                    height: displayH,
                    child: image,
                  ),
                ),
              ),
            ],
          );
        } else {
          // 旧方式: BoxFit.cover + オフセット + スケール
          return ClipRect(
            child: Transform.translate(
              offset: Offset(post.imageOffsetX, post.imageOffsetY),
              child: Transform.scale(
                scale: imgScale,
                child: CachedNetworkImage(
                  imageUrl: url,
                  fit: BoxFit.cover,
                  width: cardW,
                  height: cardH,
                  errorWidget: (_, __, ___) => Container(color: Colors.grey[900]),
                ),
              ),
            ),
          );
        }
      },
    );
  }

  // ── カード下部（275px Stack, Figma: top=539 height=275, w=402） ──

  Widget _buildCardBottom(PostModel post, VibeRankingItem? rankingItem) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        // ユーザー情報（icon left=18 top=46 size=32, name left=59 top=52）
        Positioned(
          left: 18,
          top: 46,
          width: 32,
          height: 32,
          child: ClipOval(
            child: ProfileImage(imageUrl: post.userIconUrl, size: 32),
          ),
        ),
        Positioned(
          left: 59,
          top: 52,
          right: 60,
          child: Text(
            post.username,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: Colors.white,
              letterSpacing: -0.12,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),

        // 楽曲タイトル（left=18, top=90, fontSize=24 bold）
        Positioned(
          left: 18,
          top: 90,
          right: 60,
          child: Text(
            post.track.trackName,
            style: const TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: Colors.white,
              height: 1.0,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),

        // アーティスト名（left=18, top=119）
        Positioned(
          left: 18,
          top: 119,
          right: 60,
          child: Text(
            post.track.artistName,
            style: const TextStyle(
              fontSize: 12,
              color: Color(0xFFA7ACB1),
              letterSpacing: 0.36,
              height: 1.0,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),

        // アーティスト行（left=0, top=147, w=402, h=32）
        Positioned(
          left: 0,
          right: 0,
          top: 147,
          height: 32,
          child: _buildArtistRow(post, rankingItem),
        ),

        // 曲リストバー（left=14, top=191, w=374, h=72）
        Positioned(
          left: 14,
          right: 14,
          top: 191,
          height: 72,
          child: _buildCuratorBar(post, rankingItem),
        ),

        // 右サイドバー（Figma: left=347 top=5 w=30 h=165, → right=25）
        Positioned(
          right: 25,
          top: 5,
          width: 30,
          height: 165,
          child: _buildRightSidebar(post),
        ),
      ],
    );
  }

  // Figma: container left=0 top=147 w=402 h=32
  // album icon at left=16 size=32 (white-bg, circular)
  // artist name at left=56 top=1 fontSize=13 fontWeight=600 letterSpacing=-0.78
  // follower count at left=56 top=17 fontSize=10
  // follow button at left=158 top=7 w=83 h=19 fontSize=11 fontWeight=600
  Widget _buildArtistRow(PostModel post, VibeRankingItem? rankingItem) {
    final followerCount = rankingItem?.userIds.length ?? 0;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        // アーティストアイコン（白背景円, 32x32）
        Positioned(
          left: 16,
          top: 0,
          width: 32,
          height: 32,
          child: Container(
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white,
            ),
            child: ClipOval(
              child: CachedNetworkImage(
                imageUrl: post.track.albumImageUrl,
                width: 32,
                height: 32,
                fit: BoxFit.cover,
                errorWidget: (_, __, ___) =>
                    const Icon(Icons.music_note, color: Colors.grey, size: 18),
              ),
            ),
          ),
        ),
        // アーティスト名（left=56, top=1, right=252 → 右端 x=150 = フォロー ボタン左 158 - 8px gap）
        Positioned(
          left: 56,
          top: 1,
          right: 252,
          child: Text(
            post.track.artistName,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: Colors.white,
              letterSpacing: -0.78,
              height: 1.0,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        // フォロワー数（left=56, top=17, fontSize=10）
        Positioned(
          left: 56,
          top: 17,
          right: 252,
          child: Text(
            '${_fmt(followerCount)}人のフォロワー',
            style: const TextStyle(
              fontSize: 10,
              color: Colors.white,
              height: 1.0,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        // フォローするボタン（left=158, top=7, w=83, h=19）
        Positioned(
          left: 158,
          top: 7,
          width: 83,
          height: 19,
          child: Container(
            decoration: BoxDecoration(
              border: Border.all(color: Colors.white, width: 1),
              borderRadius: BorderRadius.circular(25),
            ),
            alignment: Alignment.center,
            child: const Text(
              'フォローする',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: Colors.white,
                height: 1.0,
              ),
            ),
          ),
        ),
      ],
    );
  }

  // Figma: container left=14 top=191 w=374 h=72 bg=rgba(0,0,0,0.5) rounded=16
  // album left=8 top=8 size=56 rounded=7
  // track name left=72 top=13 fontSize=13 bold (line-height normal)
  // artist line beneath fontSize=11 normal
  // count text left=72 top=46 fontSize=11 color=#858585 letterSpacing=-0.22
  // vibe button left=328 top=16 size=40 (icon 20x26.67 at left=10 top=7)
  Widget _buildCuratorBar(PostModel post, VibeRankingItem? rankingItem) {
    final postCount = rankingItem?.postCount ?? 0;
    // 該当楽曲のランキングが見つからない場合は、postの情報から仮の VibeRankingItem を構築
    final modalItem = rankingItem ??
        VibeRankingItem(rank: 0, track: post.track, postCount: 0);
    return GestureDetector(
      onTap: () => _showSongModal(modalItem),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Stack(
          clipBehavior: Clip.hardEdge,
          children: [
            // アルバムアート（left=8, top=8, 56×56, rounded=7）
            Positioned(
              left: 8,
              top: 8,
              width: 56,
              height: 56,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(7),
                child: CachedNetworkImage(
                  imageUrl: post.track.albumImageUrl,
                  width: 56,
                  height: 56,
                  fit: BoxFit.cover,
                  errorWidget: (_, __, ___) => Container(
                    color: Colors.grey[800],
                    child: const Icon(Icons.album, color: Colors.white54),
                  ),
                ),
              ),
            ),
            // 楽曲タイトル（left=72, top=13, fontSize=13 bold）
            Positioned(
              left: 72,
              top: 13,
              right: 60,
              child: Text(
                post.track.trackName,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                  height: 1.0,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            // アーティスト名（left=72, top=29 = 13+16 line height, fontSize=11）
            Positioned(
              left: 72,
              top: 29,
              right: 60,
              child: Text(
                post.track.artistName,
                style: const TextStyle(
                  fontSize: 11,
                  color: Colors.white,
                  height: 1.0,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            // Vibe追加カウント（left=72, top=46, fontSize=11, color=#858585）
            Positioned(
              left: 72,
              top: 46,
              right: 60,
              child: Text(
                '🔥$postCount人がVibeにこの曲を追加',
                style: const TextStyle(
                  fontSize: 11,
                  color: Color(0xFF858585),
                  letterSpacing: -0.22,
                  height: 1.0,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            // 投稿ボタン（left=328, top=16, size=40）
            // 既存ナビバーと同じ post_icon.svg を使用（28×28 white）
            Positioned(
              left: 328,
              top: 16,
              width: 40,
              height: 40,
              child: GestureDetector(
                onTap: () => _navigateToPostPreviewWithTrack(post.track),
                behavior: HitTestBehavior.opaque,
                child: Center(
                  child: SvgPicture.asset(
                    'assets/icons/post_icon.svg',
                    width: 28,
                    height: 28,
                    colorFilter: const ColorFilter.mode(
                      Colors.white,
                      BlendMode.srcIn,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Figma: container left=347 top=5 w=30 h=165
  //   heart       left=2 top=0  size=27
  //   like count  left=6 top=35 fontSize=10
  //   message     left=0 top=66 size=30  → 既存の message_circle.svg
  //   save mark   left=0 top=135 size=30 → 既存の save_button.png
  Widget _buildRightSidebar(PostModel post) {
    final likeCount = _likeCountCache[post.postId] ?? post.likeCount;
    final isLiked = _isLikedCache[post.postId] ?? post.isLikedBy(widget.currentUserId);

    return Stack(
      clipBehavior: Clip.none,
      children: [
        // ♡ いいねアイコン（left=2, top=0, size=27）
        // Material iconの内部余白（~17%）を scale 1.2 で相殺し、見た目上27px相当にする
        Positioned(
          left: 2,
          top: 0,
          width: 27,
          height: 27,
          child: GestureDetector(
            onTap: () => _handleLike(post),
            behavior: HitTestBehavior.opaque,
            child: Transform.scale(
              scale: 1.2,
              child: Icon(
                isLiked ? Icons.favorite : Icons.favorite_border,
                color: isLiked ? Colors.red : Colors.white,
                size: 27,
              ),
            ),
          ),
        ),

        // いいね数（top=35, 中央寄せ, fontSize=10）
        Positioned(
          left: 0,
          right: 0,
          top: 35,
          child: Text(
            _fmt(likeCount),
            style: const TextStyle(
              fontSize: 10,
              color: Colors.white,
              height: 1.0,
            ),
            textAlign: TextAlign.center,
          ),
        ),

        // 💬 コメントボタン（既存 message_circle.svg, top=66, size=30）
        Positioned(
          left: 0,
          top: 66,
          width: 30,
          height: 30,
          child: GestureDetector(
            onTap: () => _handleComment(post),
            behavior: HitTestBehavior.opaque,
            child: SvgPicture.asset(
              'assets/icons/message_circle.svg',
              width: 30,
              height: 30,
              colorFilter: const ColorFilter.mode(
                Colors.white,
                BlendMode.srcIn,
              ),
            ),
          ),
        ),

        // 保存ボタン（top=135, size=30）
        Positioned(
          left: 0,
          top: 135,
          width: 30,
          height: 30,
          child: GestureDetector(
            onTap: () => _handleSave(post),
            behavior: HitTestBehavior.opaque,
            child: Center(
              child: _buildSaveIcon(post),
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _handleLike(PostModel post) async {
    HapticFeedback.lightImpact();
    final postId = post.postId;
    final wasLiked = _isLikedCache[postId] ?? post.isLikedBy(widget.currentUserId);
    final count = _likeCountCache[postId] ?? post.likeCount;
    setState(() {
      _isLikedCache[postId] = !wasLiked;
      _likeCountCache[postId] = wasLiked ? (count - 1).clamp(0, 999999) : count + 1;
    });
    try {
      await _postService.toggleLike(
        postId: postId,
        userId: widget.currentUserId,
      );
    } catch (_) {
      if (mounted) {
        setState(() {
          _isLikedCache[postId] = wasLiked;
          _likeCountCache[postId] = count;
        });
      }
    }
  }

  Widget _buildSaveIcon(PostModel post) {
    final isSaved = _isSavedCache[post.postId] ??
        post.savedByUserIds.contains(widget.currentUserId);
    if (isSaved) {
      return Stack(
        alignment: Alignment.center,
        children: [
          Container(
            width: 30,
            height: 30,
            decoration: const BoxDecoration(
              color: Colors.lightGreen,
              shape: BoxShape.circle,
            ),
          ),
          Icon(Icons.check, size: 18, color: Colors.grey[700]),
        ],
      );
    }
    return const Icon(Icons.add_circle_outline, size: 32, color: Colors.white);
  }

  Future<void> _handleSave(PostModel post) async {
    HapticFeedback.lightImpact();
    final postId = post.postId;
    final wasSaved = _isSavedCache[postId] ??
        post.savedByUserIds.contains(widget.currentUserId);
    setState(() {
      _isSavedCache[postId] = !wasSaved;
    });
    try {
      await _userService.toggleSavePost(
        userId: widget.currentUserId,
        postId: postId,
      );
    } catch (_) {
      if (mounted) {
        setState(() {
          _isSavedCache[postId] = wasSaved;
        });
      }
    }
  }

  Future<void> _handleComment(PostModel post) async {
    _audioService.stop();
    await CommentScreen.show(context, post: post);
  }

  // ────────────────────────────────────────────
  // 曲リストタブ
  // ────────────────────────────────────────────

  // Figma: 投稿カード left=14 top=132 w=374 h=742
  //   写真エリア left=47 top=10 w=280 h=186 (絶対位置・カード基準)
  //   タイトル/サブ left=0 top=208
  //   青枠 + グラデーションボタン行 top=266 h=40
  //   曲リスト top=318 (各48px, gap=16, → step=64)
  Widget _buildSongListTab() {
    final posts = _posts;
    final currentPost = (posts != null && posts.isNotEmpty)
        ? posts[_currentPage.clamp(0, posts.length - 1)]
        : null;

    final itemCount = _sortedRanking.length;
    final songListHeight = itemCount > 0 ? itemCount * 64 - 16 : 200; // 空状態は仮の高さ
    final totalHeight = 318 + songListHeight + 32;

    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14),
        child: SizedBox(
          width: 374,
          height: totalHeight.toDouble(),
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              // サマリー画像 2×2（写真2枚 + ジャケット2枚 ランダム）
              // 仕様: タップ無効。プレイリストであることを訴求するエリア。
              Positioned(
                left: 47,
                top: 10,
                width: 280,
                height: 186,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: _buildSummaryGrid(),
                ),
              ),
              // タイトル（left=0, top=208, fontSize=20 fontWeight=600）
              Positioned(
                left: 0,
                top: 208,
                right: 0,
                child: Text(
                  '#${widget.topic.title}',
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                    letterSpacing: -0.11,
                    height: 1.0,
                  ),
                ),
              ),
              // サブテキスト（left=0, top=235=208+27 line gap, fontSize=10）
              Positioned(
                left: 0,
                top: 235,
                right: 0,
                child: Text(
                  '🔥${_fmt(_totalUsers)}人がこのVibeに追加',
                  style: const TextStyle(
                    fontSize: 10,
                    color: Color(0xFFA8A8A8),
                    height: 1.9, // Figma leading-[19px]
                  ),
                ),
              ),
              // アクションボタン行（top=266, h=40）
              Positioned(
                left: 0,
                top: 266,
                width: 374,
                height: 40,
                child: _buildActionButtons(currentPost),
              ),
              // 曲リスト or 空状態（top=318, w=374）
              Positioned(
                left: 0,
                top: 318,
                width: 374,
                child: itemCount > 0
                    ? _buildSongList()
                    : _buildEmptyState(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // 2×2 サマリーグリッド（写真2 + ジャケット2 / タップ無効）
  // 検索画面と同じ3カラムコラージュ
  // 左・中央: 写真（fitHeight）/ 右: アルバムアート上下2分割（cover）
  Widget _buildSummaryGrid() {
    final urls = _summaryImages;
    bool hasUrl(int i) => i < urls.length && urls[i].isNotEmpty;

    Widget photoCell(int i) {
      if (!hasUrl(i)) return Container(color: Colors.grey[850]);
      return ClipRect(
        child: SizedBox.expand(
          child: CachedNetworkImage(
            imageUrl: urls[i],
            fit: BoxFit.fitHeight,
            alignment: Alignment.center,
            width: double.infinity,
            height: double.infinity,
            errorWidget: (_, __, ___) => Container(color: Colors.grey[850]),
          ),
        ),
      );
    }

    Widget jacketCell(int i) {
      if (!hasUrl(i)) return Container(color: Colors.grey[850]);
      return SizedBox.expand(
        child: CachedNetworkImage(
          imageUrl: urls[i],
          fit: BoxFit.cover,
          width: double.infinity,
          height: double.infinity,
          errorWidget: (_, __, ___) => Container(color: Colors.grey[850]),
        ),
      );
    }

    return IgnorePointer(
      child: Row(
        children: [
          Expanded(child: photoCell(0)),
          const SizedBox(width: 1),
          Expanded(child: photoCell(1)),
          const SizedBox(width: 1),
          Expanded(
            child: Column(
              children: [
                Expanded(child: jacketCell(2)),
                const SizedBox(height: 1),
                Expanded(child: jacketCell(3)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // Figma: 青枠カード left=0 w=32 h=40 (border 2px #0C51F7 rounded=7)
  //        内部画像 left=2 top=1.5 w=24.75 h=33 rounded=4
  //        グラデーションボタン left=43 w=181 h=40 rounded=30
  //          Vibeアイコン枠 left=23 top=8 size=24 (内部19x19 at 2,2)
  //          テキスト left=54 top=12 fontSize=13 letterSpacing=-0.26
  Widget _buildActionButtons(PostModel? currentPost) {
    return SizedBox(
      height: 40,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // グラデーション枠カード（left=0, 24×40）タップで「投稿」タブへ
          Positioned(
            left: 0,
            top: 0,
            width: 24,
            height: 40,
            child: GestureDetector(
              onTap: () {
                _tabController.animateTo(0);
                _tabPageController.animateToPage(
                  0,
                  duration: const Duration(milliseconds: 300),
                  curve: Curves.easeInOut,
                );
              },
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  // 内部画像（全辺2.5px inset、投稿カードと同じ切り取り）
                  Positioned(
                    left: 2.5,
                    top: 2.5,
                    right: 2.5,
                    bottom: 2.5,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: currentPost != null
                          ? _buildPhotoBackground(currentPost)
                          : Container(color: Colors.grey[900]),
                    ),
                  ),
                  // グラデーション枠PNG（最前面）
                  Positioned.fill(
                    child: IgnorePointer(
                      child: Image.asset(
                        'assets/images/vibe_song_frame.png',
                        fit: BoxFit.fill,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          // グラデーションボタン（left=35, 181×40, rounded=30）
          Positioned(
            left: 35,
            top: 0,
            width: 181,
            height: 40,
            child: GestureDetector(
              onTap: _navigateToVibePost,
              child: Container(
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF1937EF), Color(0xFFFE1F56)],
                    begin: Alignment.centerLeft,
                    end: Alignment.centerRight,
                  ),
                  borderRadius: BorderRadius.circular(30),
                ),
                child: Stack(
                  children: [
                    // Vibeアイコン（left=23, top=8, size=24, 内部19×19）
                    Positioned(
                      left: 23,
                      top: 8,
                      width: 24,
                      height: 24,
                      child: Center(
                        child: Image.asset(
                          'assets/icons/Vibe.png',
                          width: 19,
                          height: 19,
                          fit: BoxFit.contain,
                          errorBuilder: (_, __, ___) => const Icon(
                              Icons.music_note,
                              color: Colors.white,
                              size: 19),
                        ),
                      ),
                    ),
                    // テキスト（left=54, top=12, fontSize=13）
                    const Positioned(
                      left: 54,
                      top: 12,
                      child: Text(
                        '楽曲をVibeに追加',
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.white,
                          letterSpacing: -0.26,
                          height: 1.0,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // 空状態: ranking.isEmpty 時にタイトル + 案内文 + CTA
  Widget _buildEmptyState() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          const SizedBox(height: 8),
          const Text(
            'まだ曲が追加されていません',
            style: TextStyle(
              fontSize: 14,
              color: Color(0xFFA8A8A8),
              height: 1.4,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          GestureDetector(
            onTap: _navigateToVibePost,
            behavior: HitTestBehavior.opaque,
            child: Container(
              height: 44,
              padding: const EdgeInsets.symmetric(horizontal: 24),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF1937EF), Color(0xFFFE1F56)],
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                ),
                borderRadius: BorderRadius.circular(30),
              ),
              alignment: Alignment.center,
              child: const Text(
                '最初の曲をVibeに追加',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                  letterSpacing: -0.28,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSongList() {
    if (_sortedRanking.isEmpty) return const SizedBox.shrink();

    // 各アイテム top: i*64 (48 + 16 gap)
    return SizedBox(
      width: 374,
      height: _sortedRanking.length * 64 - 16,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          for (int i = 0; i < _sortedRanking.length; i++)
            Positioned(
              left: 0,
              top: (i * 64).toDouble(),
              width: 374,
              height: 48,
              child: _buildSongListItem(_sortedRanking[i]),
            ),
        ],
      ),
    );
  }

  // Figma: 幅374, 高さ48
  //   album left=0 top=0 size=48 rounded=3
  //   track name left=61 top=0 fontSize=12 letterSpacing=-0.12
  //   artist name left=61 top=14 fontSize=10
  //   count left=61 top=33 fontSize=10 color=#858585 letterSpacing=-0.2
  //   add_circle left=307 top=14 size=20
  //   post button left=334 top=4 size=40 (内部ロゴ20x26.67 at 10,7)
  Widget _buildSongListItem(VibeRankingItem item) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        // 行全体タップ領域（モーダル起動）— 後続の Positioned 子（アイコン等）が前面に来るので
        // それらのタップは行モーダルより優先される
        Positioned.fill(
          child: GestureDetector(
            onTap: () => _showSongModal(item),
            behavior: HitTestBehavior.opaque,
            child: const SizedBox.expand(),
          ),
        ),
        // アルバムアート（48×48, rounded=3）
        Positioned(
          left: 0,
          top: 0,
          width: 48,
          height: 48,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: CachedNetworkImage(
              imageUrl: item.track.albumImageUrl,
              width: 48,
              height: 48,
              imageBuilder: (context, imageProvider) => Container(
                decoration: BoxDecoration(
                  image: DecorationImage(
                    image: imageProvider,
                    fit: BoxFit.cover,
                  ),
                ),
              ),
              placeholder: (_, __) => const SizedBox.shrink(),
              errorWidget: (_, __, ___) => Container(
                color: const Color(0xFF121212),
                child: const Icon(Icons.album, color: Colors.white54, size: 24),
              ),
            ),
          ),
        ),
        // トラック名（left=61, top=0, fontSize=12）
        Positioned(
          left: 61,
          top: 0,
          right: 75,
          child: Text(
            item.track.trackName,
            style: const TextStyle(
              fontSize: 12,
              color: Colors.white,
              letterSpacing: -0.12,
              height: 1.2,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        // アーティスト名（left=61, top=15, fontSize=10）
        Positioned(
          left: 61,
          top: 15,
          right: 75,
          child: Text(
            item.track.artistName,
            style: const TextStyle(
              fontSize: 10,
              color: Colors.white,
              letterSpacing: -0.12,
              height: 1.2,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        // Vibe追加カウント（left=61, top=33, fontSize=10, #858585）
        Positioned(
          left: 61,
          top: 33,
          right: 75,
          child: Text(
            '🔥${item.postCount}人がVibeにこの曲を追加',
            style: const TextStyle(
              fontSize: 10,
              color: Color(0xFF858585),
              letterSpacing: -0.2,
              height: 1.0,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        // add_circle（left=307, top=14, size=20）
        Positioned(
          left: 307,
          top: 14,
          width: 20,
          height: 20,
          child: Builder(builder: (_) {
            final trackKey = item.track.trackId.isNotEmpty
                ? item.track.trackId
                : '${item.track.trackName}_${item.track.artistName}';
            final matchingPost = (_posts ?? []).cast<PostModel?>().firstWhere(
              (p) => p != null && (
                p.track.trackId.isNotEmpty
                  ? p.track.trackId == item.track.trackId
                  : '${p.track.trackName}_${p.track.artistName}' == trackKey
              ),
              orElse: () => null,
            );
            final saved = matchingPost != null
                ? (_isSavedCache[matchingPost.postId] ??
                    matchingPost.savedByUserIds.contains(widget.currentUserId))
                : false;
            return GestureDetector(
              onTap: () {
                if (matchingPost != null) _handleSave(matchingPost);
              },
              behavior: HitTestBehavior.opaque,
              child: saved
                  ? Stack(
                      alignment: Alignment.center,
                      children: [
                        Container(
                          width: 20,
                          height: 20,
                          decoration: const BoxDecoration(
                            color: Colors.lightGreen,
                            shape: BoxShape.circle,
                          ),
                        ),
                        Icon(Icons.check, size: 14, color: Colors.grey[700]),
                      ],
                    )
                  : const Icon(
                      Icons.add_circle_outline,
                      color: Colors.white,
                      size: 20,
                    ),
            );
          }),
        ),
        // 投稿ボタン（left=334, top=4, size=40）
        // 既存ナビバーと同じ post_icon.svg を使用（28×28 white）
        // 仕様: その楽曲で投稿フロー（カード反転起点）を開始
        Positioned(
          left: 334,
          top: 4,
          width: 40,
          height: 40,
          child: GestureDetector(
            onTap: () => _navigateToPostPreviewWithTrack(item.track),
            behavior: HitTestBehavior.opaque,
            child: Center(
              child: SvgPicture.asset(
                'assets/icons/post_icon.svg',
                width: 28,
                height: 28,
                colorFilter: const ColorFilter.mode(
                  Colors.white,
                  BlendMode.srcIn,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// 曲行タップで表示されるアクションシート（Figma 3870:6805）
/// - 上部: 曲情報バー（アルバム / 曲名 / アーティスト / Vibe追加カウント / +保存）
/// - 中段: アクションボタン2つ
/// - 下部: その楽曲を使った投稿写真の3列グリッド（スクロール）
class _SongActionSheet extends StatefulWidget {
  final VibeRankingItem item;
  final List<String> photos;
  final VoidCallback onPlayFull;
  final VoidCallback onAddToVibe;
  final VoidCallback onSave;
  final bool isSaved;

  const _SongActionSheet({
    required this.item,
    required this.photos,
    required this.onPlayFull,
    required this.onAddToVibe,
    required this.onSave,
    this.isSaved = false,
  });

  @override
  State<_SongActionSheet> createState() => _SongActionSheetState();
}

class _SongActionSheetState extends State<_SongActionSheet> {
  late bool _isSaved;

  @override
  void initState() {
    super.initState();
    _isSaved = widget.isSaved;
  }

  @override
  Widget build(BuildContext context) {
    final bottomPadding = MediaQuery.of(context).padding.bottom;
    final screenH = MediaQuery.of(context).size.height;
    // モーダル全体の高さ = 画面の85%（残り15%は背景の曲リストが見える余白）
    final modalHeight = screenH * 0.85;

    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF313131),
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(11),
          topRight: Radius.circular(11),
        ),
      ),
      child: SizedBox(
        height: modalHeight,
        child: Column(
          children: [
            // 固定ヘッダー（ハンドル + 曲情報バー + アクションボタン）
            // = top=9(handle) + 20+72(barまで) + 残り余白で 152 高さ
            SizedBox(
              height: 153,
              child: _buildHeader(),
            ),
            // 写真グリッド（3列、スクロール）
            Expanded(
              child: _buildPhotoGrid(bottomPadding),
            ),
          ],
        ),
      ),
    );
  }

  /// 写真3列グリッド（Figma: 各セル 133×178、左から left=0,134/135,269）
  /// 画面幅 402 想定。実機ではセルを画面幅に合わせて等分し、aspect 133:178 を維持。
  Widget _buildPhotoGrid(double bottomPadding) {
    if (widget.photos.isEmpty) {
      return Padding(
        padding: EdgeInsets.only(bottom: bottomPadding),
        child: const Center(
          child: Text(
            'まだこの曲で投稿された写真はありません',
            style: TextStyle(color: Color(0xFF858585), fontSize: 12),
          ),
        ),
      );
    }
    return GridView.builder(
      padding: EdgeInsets.only(
        left: 0,
        right: 0,
        top: 0,
        bottom: bottomPadding,
      ),
      physics: const ClampingScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        mainAxisSpacing: 1,
        crossAxisSpacing: 1,
        childAspectRatio: 133 / 178,
      ),
      itemCount: widget.photos.length,
      itemBuilder: (context, index) {
        return CachedNetworkImage(
          imageUrl: widget.photos[index],
          fit: BoxFit.cover,
          errorWidget: (_, __, ___) => Container(color: Colors.grey[900]),
        );
      },
    );
  }

  Widget _buildHeader() {
    return Stack(
          clipBehavior: Clip.none,
          children: [
            // ドラッグハンドル（line133: 中央, 幅44, top=9 / 高さ4）
            Positioned(
              top: 9,
              left: 0,
              right: 0,
              child: Center(
                child: Container(
                  width: 44,
                  height: 4,
                  decoration: BoxDecoration(
                    color: const Color(0xFF6E6E6E),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
            ),
            // 曲情報バー（left=14, top=20, w=374, h=72, rounded=16）
            Positioned(
              left: 14,
              top: 20,
              right: 14,
              height: 72,
              child: Container(
                decoration: BoxDecoration(
                  color: const Color(0xFF1F1F1F),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Stack(
                  children: [
                    // アルバム（left=8 top=8 size=56 rounded=7）
                    Positioned(
                      left: 8,
                      top: 8,
                      width: 56,
                      height: 56,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(7),
                        child: CachedNetworkImage(
                          imageUrl: widget.item.track.albumImageUrl,
                          fit: BoxFit.cover,
                          errorWidget: (_, __, ___) => Container(
                            color: Colors.grey[800],
                            child: const Icon(Icons.album, color: Colors.white54),
                          ),
                        ),
                      ),
                    ),
                    // 曲名（left=72 top=13 fontSize=13 bold）
                    Positioned(
                      left: 72,
                      top: 13,
                      right: 60,
                      child: Text(
                        widget.item.track.trackName,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                          height: 1.0,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    // アーティスト（left=72 top=29 fontSize=11）
                    Positioned(
                      left: 72,
                      top: 29,
                      right: 60,
                      child: Text(
                        widget.item.track.artistName,
                        style: const TextStyle(
                          fontSize: 11,
                          color: Colors.white,
                          height: 1.0,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    // Vibe追加カウント（left=72 top=46 fontSize=11 #858585）
                    Positioned(
                      left: 72,
                      top: 46,
                      right: 60,
                      child: Text(
                        '🔥${widget.item.postCount}人がVibeにこの曲を追加',
                        style: const TextStyle(
                          fontSize: 11,
                          color: Color(0xFF858585),
                          letterSpacing: -0.22,
                          height: 1.0,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    // +保存（left=327 top=19 size=34）
                    Positioned(
                      right: 13,
                      top: 19,
                      width: 34,
                      height: 34,
                      child: GestureDetector(
                        onTap: () {
                          setState(() => _isSaved = !_isSaved);
                          widget.onSave();
                        },
                        behavior: HitTestBehavior.opaque,
                        child: _isSaved
                            ? Stack(
                                alignment: Alignment.center,
                                children: [
                                  Container(
                                    width: 30,
                                    height: 30,
                                    decoration: const BoxDecoration(
                                      color: Colors.lightGreen,
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                                  Icon(Icons.check, size: 18, color: Colors.grey[700]),
                                ],
                              )
                            : const Icon(
                                Icons.add_circle_outline,
                                color: Colors.white,
                                size: 30,
                              ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            // 「楽曲をフルで聴く」（left=14 top=102 w=181 h=40 rounded=30 bg=#454545）
            Positioned(
              left: 14,
              top: 102,
              width: 181,
              height: 40,
              child: GestureDetector(
                onTap: widget.onPlayFull,
                child: Container(
                  decoration: BoxDecoration(
                    color: const Color(0xFF454545),
                    borderRadius: BorderRadius.circular(30),
                  ),
                  alignment: Alignment.center,
                  child: const Text(
                    '楽曲をフルで聴く',
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.white,
                      letterSpacing: -0.26,
                      height: 1.0,
                    ),
                  ),
                ),
              ),
            ),
            // 「楽曲をVibeに追加」（left=207 top=103 w=181 h=40 rounded=30 グラデ）
            //   Vibeアイコン枠 left=23 top=8 size=24（内部19×19）
            //   テキスト left=54 top=12 fontSize=13
            Positioned(
              left: 207,
              top: 103,
              width: 181,
              height: 40,
              child: GestureDetector(
                onTap: widget.onAddToVibe,
                child: Container(
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF1937EF), Color(0xFFFE1F56)],
                      begin: Alignment.centerLeft,
                      end: Alignment.centerRight,
                    ),
                    borderRadius: BorderRadius.circular(30),
                  ),
                  child: Stack(
                    children: [
                      Positioned(
                        left: 23,
                        top: 8,
                        width: 24,
                        height: 24,
                        child: Center(
                          child: Image.asset(
                            'assets/icons/Vibe.png',
                            width: 19,
                            height: 19,
                            fit: BoxFit.contain,
                            errorBuilder: (_, __, ___) => const Icon(
                                Icons.music_note,
                                color: Colors.white,
                                size: 19),
                          ),
                        ),
                      ),
                      const Positioned(
                        left: 54,
                        top: 12,
                        child: Text(
                          '楽曲をVibeに追加',
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.white,
                            letterSpacing: -0.26,
                            height: 1.0,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        );
  }
}

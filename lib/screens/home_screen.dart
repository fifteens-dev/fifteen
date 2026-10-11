import 'dart:async';
import 'package:cached_network_image/cached_network_image.dart';
import '../main.dart' show routeObserver;
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:provider/provider.dart';
import '../constants/app_colors.dart';
import '../models/post_model.dart';
import '../models/user_model.dart';
import '../providers/post_ui_state.dart';
import '../providers/saved_items_provider.dart';
import '../models/vibe_ranking_item.dart';
import '../models/vibe_topic_model.dart';
import '../widgets/post_card.dart';
import '../widgets/notification_badge.dart';
import '../widgets/dialogs/delete_post_dialog.dart';
import '../services/post_service.dart';
import '../services/spotify_service.dart';
import '../services/audio_player_service.dart';
import '../services/deep_link_service.dart';
import '../services/live_activity_service.dart';
import '../services/music_memory_cycle_service.dart';
import '../services/music_service_manager.dart';
import '../models/music_service_type.dart';
import '../services/itunes_search_service.dart';
import '../services/user_service.dart';
import '../services/notification_service.dart';
import '../models/notification_model.dart';
import '../services/vibe_topic_service.dart';
import '../services/adl_service.dart';
import '../utils/campus_vibe_utils.dart';
import '../widgets/campus_vibe_card.dart';
import '../providers/current_user_provider.dart';
import 'comment_screen.dart';
import 'profile_screen.dart';
import 'friend_add_sheet.dart';
import '../services/friend_match_service.dart';
import '../services/friend_widget_service.dart';
import '../services/now_playing_share_service.dart';
import '../services/post_photo_service.dart';
import 'post_flow/add_photo_flow.dart';
import 'music_selection_screen.dart';
import 'music_memory_month_screen.dart';
import 'post_flow/music_memory_modal.dart';
import 'notification_list_screen.dart';
import 'vibe_track_posts_screen.dart';
import 'vibe_playlist/vibe_playlist_screen.dart';
import 'card_share_screen.dart';
import '../widgets/home/vibe_bar_section.dart';
import '../widgets/home/vibe_story_bar_section.dart';
import 'vibe_story_post_sheet.dart';
import 'vibe_user_story_screen.dart';
import '../widgets/home/home_bottom_nav.dart';
import '../widgets/common/app_toast.dart';
import '../services/posting_state.dart';
import '../services/post_write_service.dart';
import '../services/apple_music_service.dart';
import '../models/track_model.dart';
import '../tutorial/tutorial.dart';
import 'post_flow/mood_post_final_preview_screen.dart';
import '../utils/app_log.dart';

/// ホーム画面（タイムライン）
// home/ の中身はすべて home_screen.dart の一部（part）。
//
// part ファイルは自分で import を持てないので、新しいパッケージが要るときは
// このファイルの import に足すこと。代わりに _HomeScreenState のプライベート
// メンバーがそのまま見える。
//
// 単独のウィジェット（ボトムナビ・Vibe バー）は lib/widgets/home/ にある。
part 'home/home_header.dart';
part 'home/home_grid_cell.dart';

part 'home/home_data.dart';
part 'home/home_stories.dart';
part 'home/home_post_actions.dart';
part 'home/home_post_flow.dart';
part 'home/home_build.dart';
part 'home/home_playback.dart';
part 'home/home_startup.dart';
class HomeScreen extends StatefulWidget {
  final List<PostModel>? initialPosts;
  final Map<String, dynamic>? initialVibeData;
  final UserModel? initialUserModel;
  final bool initialHasPostedToday;
  const HomeScreen({
    super.key,
    this.initialPosts,
    this.initialVibeData,
    this.initialUserModel,
    this.initialHasPostedToday = false,
  });

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with AutomaticKeepAliveClientMixin, WidgetsBindingObserver
    implements RouteAware {
  // ナビゲーション: 0=Music Memory(カレンダー) / 1=ホーム / 2=プロフィール。
  // 起動時はホーム(中央)を表示。
  int _selectedIndex = 1;
  // ホームのタイムライン表示: false=1列(既定) / true=2列グリッド。
  bool _isGridView = false;
  // 2列グリッドの拡大オーバーレイ表示中フラグ。
  // 拡大中は再生カードがグリッド上で非表示（プレースホルダ）になるため、
  // 可視性チェックによる自動停止をスキップして拡大カードの再生を守る。
  bool _gridEnlargedActive = false;
  final PostService _postService = PostService();
  final MusicServiceManager _musicServiceManager = MusicServiceManager();
  final UserService _userService = UserService();
  final VibeTopicService _vibeTopicService = VibeTopicService();
  final SpotifyService _spotifyService = SpotifyService();
  final ITunesSearchService _itunesService = ITunesSearchService();
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final ScrollController _scrollController = ScrollController();
  final ValueNotifier<double> _bellOpacity = ValueNotifier<double>(1.0);

  // ホーム画面専用の音楽再生サービス（全てのPostCardで共有）
  final AudioPlayerService _homeAudioService = AudioPlayerService();

  // チュートリアル用
  final GlobalKey _tutorialVibeIconKey = GlobalKey();
  final GlobalKey _tutorialAddButtonKey = GlobalKey();
  TrackModel? _tutorialTrack;
  int _tutorialActiveIndex = 0;

  // 各PostCardのGlobalKey（可視性チェック・flipToFront用）
  final Map<String, GlobalKey<PostCardState>> _postCardKeys = {};

  // 現在再生中の投稿ID
  String? _playingPostId;

  // Vibeデータのキャッシュ（buildごとに再取得しないよう）
  Future<Map<String, dynamic>>? _vibeDataFuture;

  // スクロールイベントのスロットル用
  DateTime? _lastScrollCheckAt;

  @override
  bool get wantKeepAlive => true;

  // 投稿リストをキャッシュ（再構築を避けるため）
  List<PostModel>? _cachedPosts;

  // Vibe ストーリーバー用: 24h 以内に投稿したユーザーごとの可視投稿群（新しい順）。
  // タイムラインフェッチと同じタイミングで一度だけ取得する。
  List<VibeStoryItem> _storyItems = const [];
  /// 自分の 24h 投稿を「Vibe」円タップで表示するためのキャッシュ。
  /// 投稿が無い場合は null。
  VibeStoryItem? _ownStoryItem;

  /// ストーリーバーをアクティブに更新するための周期タイマー。
  /// 30 秒間隔で [_refreshStoriesOnly] を呼び、投稿反映のタイムラインズレを縮める。
  /// dispose とバックグラウンド時に停止し、レジューム時に再開する。
  Timer? _storyRefreshTimer;
  static const Duration _kStoryRefreshInterval = Duration(seconds: 30);

  /// Vibe ストーリーで一度開いた postId のセット（SharedPreferences 永続化）。
  /// インスタ風: ユーザーの全直近投稿がこのセットに含まれていれば、
  /// その人のリングを「グレー（既読）」表示にする。
  Set<String> _viewedStoryPostIds = {};

  // 投稿ごとの音楽プレビューURL（postId → URL）
  final Map<String, String?> _previewUrlCache = {};

  // 現在のユーザーが今日投稿済みかどうか（裏面表示制御用）
  bool _hasPostedToday = false;

  /// 現サイクルで投稿済みか。まだ調べていなければ null。
  ///
  /// 投稿ボタンを押すたびに Firestore へ聞くと、曲選びのモーダルが出るまで
  /// その往復ぶん待たされる。起動時に一度調べ、投稿したら更新して持っておく。
  bool? _postedThisCycle;

  /// [_postedThisCycle] がどのサイクルについての判定か。
  ///
  /// アプリを開いたまま 21:00 をまたぐと、前日の「投稿済み」が残って
  /// 新しいサイクルで投稿できなくなる。サイクルが変わったら捨てる。
  DateTime? _postedThisCycleFor;

  /// 曲選びのモーダルに渡す、温めておいた再生履歴。
  ///
  /// モーダルは開いてから履歴を取りに行くので、その間スピナーになる。
  /// 投稿できる時間帯に入っていれば先に取っておき、開いた瞬間に出す。
  List<TrackModel>? _warmTracks;

  /// 自分の投稿のうち、既に写真が付いているもの。バーを出すかの判定に使う。
  Set<String> _postsWithPhoto = {};

  /// 今が写真を足せる時間帯か（24:00 まで）。
  /// 判定には通知時刻が要るので、取得できてから立てる。
  bool _canAddPhoto = false;

  @override
  void initState() {
    super.initState();
    AppLog.debug('🏠 ホーム画面: initState()が呼ばれました');
    PostPhotoService.instance.photoAdded.addListener(_onPhotoAdded);
    PostWriteService.postCreated.addListener(_onPostCreated);
    _vibeDataFuture = widget.initialVibeData != null
        ? Future.value(widget.initialVibeData)
        : _loadVibeData();
    _loadViewedStoryPostIds();
    // CurrentUserProvider に initialUserModel を流し込んでおく（Firestore 再フェッチ不要）
    if (widget.initialUserModel != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          context.read<CurrentUserProvider>().initFromModel(widget.initialUserModel!);
        }
      });
    }
    _updateLastActive();

    // ロック画面の Live Activity: 現在の状況を反映しつつ、
    // 「投稿する」タップ（fifteenapp://compose）で投稿フローを開けるようにする。
    DeepLinkService().composeHandler = _openPostFlow;
    // ignore: discarded_futures
    LiveActivityService().refresh();
    // ホーム画面ウィジェット（友達が今聴いてる曲）。
    // 自分の再生状態も共有する（友達のウィジェットに出るのはこれ）。
    // ignore: discarded_futures
    _loadCanAddPhoto();
    // ignore: discarded_futures
    NowPlayingShareService.instance.publish();
    // ignore: discarded_futures
    FriendWidgetService.instance.refresh();
    // ignore: discarded_futures
    _runStartupFlows();
    _processPendingFollowNotification();
    PostingState.instance.addListener(_onPostingStateChanged);
    WidgetsBinding.instance.addObserver(this);
    _startStoryRefreshTimer();
    if (widget.initialPosts != null) {
      // バックグラウンドで事前取得済みのデータをそのまま表示（追加フェッチ不要）
      _cachedPosts = widget.initialPosts;
      _hasPostedToday = widget.initialHasPostedToday;
      // precacheImage は MediaQuery を使うため initState 完了後に実行
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _prefetchBacksideImages(widget.initialPosts!);
      });
      _prefetchPreviewUrls(widget.initialPosts!);
      _initializePostUIState(widget.initialPosts!, userModel: widget.initialUserModel);
    } else {
      _loadPosts();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    routeObserver.subscribe(this, ModalRoute.of(context)!);
  }

  /// 他画面から戻ったタイミングで最新データを再取得
  @override
  void didPopNext() {
    _loadPosts();
    setState(() {
      _vibeDataFuture = _loadVibeData();
    });
  }

  @override
  void didPush() {}

  @override
  void didPushNext() {}

  @override
  void didPop() {}

  @override
  void dispose() {
    PostPhotoService.instance.photoAdded.removeListener(_onPhotoAdded);
    PostWriteService.postCreated.removeListener(_onPostCreated);
    PostingState.instance.removeListener(_onPostingStateChanged);
    WidgetsBinding.instance.removeObserver(this);
    _storyRefreshTimer?.cancel();
    routeObserver.unsubscribe(this);
    _scrollController.dispose();
    _bellOpacity.dispose();
    _postCardKeys.clear();
    _previewUrlCache.clear();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.resumed) {
      // フォアグラウンド復帰時: 即再取得 + タイマー再開 (即時 fire は
      // _startStoryRefreshTimer 内で行われるので個別呼び出し不要)。
      _startStoryRefreshTimer();
      // ロック画面の Live Activity を現在の状況に合わせ直す
      // （締切超過なら終了、フォロー中の投稿があれば「友達が待っています」へ）。
      // ignore: discarded_futures
      LiveActivityService().refresh();
      // 日付をまたいでいることがあるので取り直す。
      // ignore: discarded_futures
      _loadCanAddPhoto();
      // ignore: discarded_futures
      NowPlayingShareService.instance.publish();
      // ignore: discarded_futures
      FriendWidgetService.instance.refresh();
      // ignore: discarded_futures
      _runStartupFlows();
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      // バックグラウンドでは無駄なポーリングを止める
      _storyRefreshTimer?.cancel();
      _storyRefreshTimer = null;
    }
  }

  /// 投稿アップロード完了時にタイムライン＋Vibeを自動リロード
  void _onPostingStateChanged() {
    if (!PostingState.instance.isPosting) {
      setState(() {
        _vibeDataFuture = _loadVibeData();
      });
      _loadPosts();
    }
  }

  /// カレンダーを読み直させるための持ち手。タブは生かされたままで
  /// initState が二度と走らないので、外から呼べるようにしておく。
  final GlobalKey<MusicMemoryMonthScreenState> _musicMemoryKey =
      GlobalKey<MusicMemoryMonthScreenState>();

  Future<void> _onItemTapped(int index) async {
    // ホームタブ(1)を既に表示中にもう一度タップ
    // → 先頭へスムーズに戻ってからリフレッシュを実行
    if (index == 1 && _selectedIndex == 1) {
      // 先頭へスムーズに戻す。寸法未確定のときの animateTo クラッシュを防ぐため
      // try/catch で保護し、続けて最新データを再読込（プル更新の代替導線）。
      if (_scrollController.hasClients) {
        try {
          await _scrollController.animateTo(
            0,
            duration: const Duration(milliseconds: 400),
            curve: Curves.easeOut,
          );
        } catch (_) {}
      }
      _loadPosts();
      return;
    }

    if (index != _selectedIndex) {
      _homeAudioService.stop();
      _playingPostId = null;
      setState(() {
        _selectedIndex = index;
      });
      // Music Memory は投稿したあとに見に来るので、入るたび読み直す。
      // 生かされたままのタブなので、黙っていると前に読んだ内容が残る。
      if (index == 0) {
        // ignore: unawaited_futures
        _musicMemoryKey.currentState?.reload();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context); // AutomaticKeepAliveClientMixinのために必要
    final postUIState = context.watch<PostUIState>();
    final savedItems = context.watch<SavedItemsProvider>();
    final currentUserIconUrl = context.watch<CurrentUserProvider>().iconUrl;
    final topPadding = MediaQuery.of(context).padding.top;
    final headerHeight = 48.0 + topPadding;
    // 上部ぼかしのフェード帯の高さ。投稿カードに掛からない程度に抑える（画面の約4%）。
    final fadeH = MediaQuery.of(context).size.height * 0.04;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: Stack(
          children: [
            // タブコンテンツ
            IndexedStack(
              index: _selectedIndex,
              children: [
                // index 0: Music Memory（カレンダー）
                _buildMusicMemoryTab(),
                // index 1: ホーム
                NotificationListener<ScrollNotification>(
                  onNotification: (notification) {
                    if (notification is ScrollUpdateNotification) {
                      final now = DateTime.now();
                      if (_lastScrollCheckAt == null ||
                          now.difference(_lastScrollCheckAt!) >= const Duration(milliseconds: 100)) {
                        _lastScrollCheckAt = now;
                        _checkPlayingCardVisibility();
                        _updateBellOpacity();
                      }
                    }
                    return false;
                  },
                  child: CustomScrollView(
                    controller: _scrollController,
                    physics: const BouncingScrollPhysics(
                      parent: AlwaysScrollableScrollPhysics(),
                    ),
                    slivers: [
                      SliverPersistentHeader(
                        pinned: true,
                        delegate: _HomeHeaderDelegate(
                          height: headerHeight,
                          topPadding: topPadding,
                          bellOpacity: _bellOpacity,
                          bellButton: NotificationBadge(
                            child: IconButton(
                              icon: const Icon(Icons.notifications_outlined,
                                  color: Colors.white),
                              onPressed: () {
                                _homeAudioService.stop();
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                      builder: (_) =>
                                          const NotificationListScreen()),
                                );
                              },
                            ),
                          ),
                        ),
                      ),
                      // リフレッシュコントロール（ヘッダーの下に表示される）
                      CupertinoSliverRefreshControl(
                        onRefresh: _onRefresh,
                      ),
                      if (_cachedPosts == null) ...[
                        const SliverFillRemaining(
                          hasScrollBody: false,
                          child: Center(
                            child: CupertinoActivityIndicator(
                              color: Colors.white,
                              radius: 14,
                            ),
                          ),
                        ),
                      ] else ...[
                        // 新 Vibe ストーリーバー（インスタ風、ユーザー単位）
                        // Vibe 機能は一時的に全面非表示（将来再利用のため if(false) で温存）。
                        if (false)
                        SliverToBoxAdapter(
                          child: FutureBuilder<Map<String, dynamic>>(
                            future: _vibeDataFuture!,
                            builder: (context, snap) {
                              final topic = snap.data?['topic'];
                              // 「右から左に新しい順」= 並びを反転して描画。
                              // _storyItems は最新順（先頭=最新）なので reverse する。
                              final stories = _storyItems.reversed.toList();
                              return VibeStoryBarSection(
                                topic: topic,
                                myIconUrl: context
                                    .read<CurrentUserProvider>()
                                    .iconUrl,
                                stories: stories,
                                onAddVibeTap: () => VibeStoryPostSheet.show(
                                  context,
                                  topic: topic,
                                ),
                                hasOwnStory: _ownStoryItem != null,
                                ownStoryUnread:
                                    _ownStoryItem?.unread ?? true,
                                onOwnStoryTap: _ownStoryItem == null
                                    ? null
                                    : () {
                                        final own = _ownStoryItem!;
                                        _markStoryPostsViewed(
                                            own.posts.map((p) => p.postId));
                                        // 自分のストーリーは単独遷移 (フォロー中との横スクロールに混ぜない)
                                        Navigator.push(
                                          context,
                                          MaterialPageRoute(
                                            builder: (_) => VibeUserStoryScreen(
                                              stories: [own],
                                              currentUserId:
                                                  _auth.currentUser?.uid ?? '',
                                              hasPostedToday: _hasPostedToday,
                                            ),
                                          ),
                                        );
                                      },
                                onPlaylistTap: _navigateToVibePost,
                                onStoryTap: (story) {
                                  // タップした瞬間にそのストーリーの全 postId を
                                  // 既読セットに追加 → リングが即グレーに変わる。
                                  _markStoryPostsViewed(
                                      story.posts.map((p) => p.postId));
                                  // 表示中のストーリー配列 (stories) は上の
                                  // FutureBuilder builder スコープで作られている。
                                  // 現在の順序どおりで cross-user 横スクロールを可能に。
                                  final startIdx = stories.indexOf(story);
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) => VibeUserStoryScreen(
                                        stories: stories,
                                        initialUserIndex:
                                            startIdx < 0 ? 0 : startIdx,
                                        currentUserId:
                                            _auth.currentUser?.uid ?? '',
                                        hasPostedToday: _hasPostedToday,
                                      ),
                                    ),
                                  );
                                },
                              );
                            },
                          ),
                        ),
                        // 旧バーは無効化（差し替え）
                        if (false)
                          SliverToBoxAdapter(
                            child: VibeBarSection(
                              vibeDataFuture: _vibeDataFuture!,
                              onRankingItemTap: _handleRankingItemTap,
                              onPostTap: _navigateToVibePost,
                              onAddTap: _navigateToPostFlow,
                              vibeIconKey: _tutorialVibeIconKey,
                              addButtonKey: _tutorialAddButtonKey,
                            ),
                          ),
                        if (false && CampusVibeUtils.shouldShow())
                          SliverToBoxAdapter(
                            child: Padding(
                              padding: const EdgeInsets.fromLTRB(12, 0, 12, 0),
                              child: CampusVibeCard(
                                university: CampusVibeUtils.targetUniversity,
                                currentUserId: _auth.currentUser?.uid ?? '',
                              ),
                            ),
                          ),
                        const SliverToBoxAdapter(child: SizedBox(height: 9)),
                        _buildTimelineSliver(postUIState, savedItems, currentUserIconUrl),
                        const SliverToBoxAdapter(child: SizedBox(height: 80)),
                      ],
                    ],
                  ),
                ),
                // index 2: プロフィール
                const ProfileScreen(),
              ],
            ),

            // 上部の静的グラデーション幕（ホームタブのみ）。画面最上部(top:0)から
            // 背景色へ溶ける純粋なグラデーション（＝画像貼り付け相当・ネイティブ非使用）。
            // スクロール構造・ピン留めヘッダーには一切触れず、外側 Stack に IgnorePointer の
            // Positioned オーバーレイとして重ねるだけなのでホーム機能を壊さない。
            if (_selectedIndex == 1) ...[
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                height: headerHeight + fadeH,
                child: IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          AppColors.background,
                          AppColors.background.withValues(alpha: 0.0),
                        ],
                        stops: const [0.0, 1.0],
                      ),
                    ),
                  ),
                ),
              ),
              // 幕の上にヘッダー（15s + ベル）を鮮明に浮かせる。背景色は持たせず、
              // ベルのみ操作可能なので、ヘッダー領域でもスクロール/プル更新は透過する。
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: _homeHeaderOverlay(headerHeight, topPadding),
              ),
            ],

            // 投稿フローの起点 FAB（ホームタブのみ・キーボード非表示時）。
            // ナビ中央の投稿ボタンを廃止したため、ここから投稿フローへ入る。
            // タイムライン0件時は空状態カードのボタンを使うため FAB は隠す。
            if (_selectedIndex == 1 &&
                !(_cachedPosts != null && _cachedPosts!.isEmpty) &&
                MediaQuery.of(context).viewInsets.bottom == 0)
              Positioned(
                right: 20,
                bottom: 110,
                child: GestureDetector(
                  onTap: _openPostFlow,
                  behavior: HitTestBehavior.opaque,
                  child: Container(
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.35),
                          blurRadius: 12,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: const Icon(Icons.add, color: Colors.black, size: 30),
                  ),
                ),
              ),

            // フローティングボトムナビゲーション（キーボード表示中は非表示）
            if (MediaQuery.of(context).viewInsets.bottom == 0)
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: HomeBottomNavigation(
                  selectedIndex: _selectedIndex,
                  onItemTapped: _onItemTapped,
                ),
              ),

            // チュートリアルオーバーレイ（最前面）
            ListenableBuilder(
              listenable: TutorialController.instance,
              builder: (context, _) {
                final step = TutorialController.instance.step;
                if (_selectedIndex != 1) return const SizedBox.shrink();

                if (step == TutorialStep.showHomeHint) {
                  return Positioned.fill(
                    child: TutorialFrame628Overlay(
                      onConfirm: _onTutorialSongConfirmed,
                      onActiveChanged: _onTutorialAlbumChanged,
                    ),
                  );
                }

                if (step == TutorialStep.takingPhoto && _tutorialTrack != null) {
                  return Positioned.fill(
                    child: TutorialCameraOverlay(
                      track: _tutorialTrack!,
                      isVibe: true,
                      vibeTopicId: 'tutorial_topic_drive',
                      vibeTopicTitle: 'ドライブで聴きたい曲',
                    ),
                  );
                }

                if (step == TutorialStep.showVibePlaylistHint) {
                  return TutorialCoachmark(
                    active: true,
                    text: '他の人の投稿も見てみよう',
                    subText: 'Vibeアイコンをタップ',
                    handVariant: HandCursorVariant.tap,
                    target: _tutorialVibeIconKey,
                    placement: CoachmarkPlacement.belowTarget,
                  );
                }

                return const SizedBox.shrink();
              },
            ),
          ],
        ),
    );
  }

}


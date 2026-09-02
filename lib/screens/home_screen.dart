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
import 'search_screen.dart';
import 'music_selection_screen.dart';
import 'music_memory_month_screen.dart';
import 'post_flow/music_memory_modal.dart';
import 'notification_list_screen.dart';
import 'vibe_track_posts_screen.dart';
import 'vibe_playlist/vibe_playlist_screen.dart';
import 'card_share_screen.dart';
import 'home/vibe_bar_section.dart';
import 'home/vibe_story_bar_section.dart';
import 'vibe_story_post_sheet.dart';
import 'vibe_user_story_screen.dart';
import 'home/home_bottom_nav.dart';
import '../widgets/common/app_toast.dart';
import '../services/posting_state.dart';
import '../models/track_model.dart';
import '../tutorial/tutorial.dart';
import 'post_photo_selection_screen.dart';

/// ホーム画面（タイムライン）
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

  // 現サイクルで「期限内（Late でない）投稿」済みか。
  // true のときだけ他人の投稿への**リアクション**を許可する（Late 投稿者は不可）。
  bool _postedOnTimeThisCycle = false;

  // 現サイクルで（Late 含む）投稿済みか。
  // true のとき他人の投稿の**裏面（写真）閲覧**を許可する。
  // 未投稿者は false（表面のみ）。Late 投稿者も投稿した時点で裏面は見られる。
  bool _postedAnyThisCycle = false;

  // 一度裏面を見た投稿IDのセット（永続化済み）
  Set<String> _revealedPostIds = {};

  @override
  void initState() {
    super.initState();
    print('🏠 ホーム画面: initState()が呼ばれました');
    _vibeDataFuture = widget.initialVibeData != null
        ? Future.value(widget.initialVibeData)
        : _loadVibeData();
    _loadRevealedPostIds();
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

  /// PostUIState / SavedItemsProvider を投稿リストから初期化する
  Future<void> _initializePostUIState(List<PostModel> posts, {UserModel? userModel}) async {
    final currentUser = _auth.currentUser;
    if (currentUser == null) return;
    UserModel? user = userModel;
    if (user == null) {
      try {
        user = await _userService.getUser(currentUser.uid);
      } catch (_) {}
    }
    if (mounted) {
      context.read<PostUIState>().resetAndInitialize(
        posts: posts,
        currentUserId: currentUser.uid,
      );
      if (user != null) {
        context.read<SavedItemsProvider>().initialize(
          userId: currentUser.uid,
          user: user,
        );
      }
    }
  }

  /// 一度裏面を見た投稿IDをSharedPreferencesから読み込む
  Future<void> _loadRevealedPostIds() async {
    final prefs = await SharedPreferences.getInstance();
    final currentUserId = _auth.currentUser?.uid;
    if (currentUserId == null) return;
    final key = 'revealed_posts_$currentUserId';
    final ids = prefs.getStringList(key) ?? [];
    if (mounted) {
      setState(() {
        _revealedPostIds = ids.toSet();
      });
    }
  }

  /// 投稿IDを「裏面閲覧済み」として記録・永続化する
  Future<void> _markPostRevealed(String postId) async {
    if (_revealedPostIds.contains(postId)) return;
    setState(() {
      _revealedPostIds.add(postId);
    });
    final prefs = await SharedPreferences.getInstance();
    final currentUserId = _auth.currentUser?.uid;
    if (currentUserId == null) return;
    final key = 'revealed_posts_$currentUserId';
    await prefs.setStringList(key, _revealedPostIds.toList());
  }

  /// Vibe ストーリー既読 postId を読み込む
  Future<void> _loadViewedStoryPostIds() async {
    final currentUserId = _auth.currentUser?.uid;
    if (currentUserId == null) return;
    final prefs = await SharedPreferences.getInstance();
    final ids = prefs.getStringList('viewed_story_posts_$currentUserId') ?? [];
    if (mounted) {
      setState(() => _viewedStoryPostIds = ids.toSet());
    }
  }

  /// Vibe ストーリー閲覧時に呼ぶ: 渡された postId 群を既読セットに追加 + 永続化。
  /// 既読のリング表示（グレー化）にも即時反映するため _storyItems も再構成する。
  Future<void> _markStoryPostsViewed(Iterable<String> postIds) async {
    final newIds = postIds.where((id) => !_viewedStoryPostIds.contains(id));
    if (newIds.isEmpty) return;
    final updated = {..._viewedStoryPostIds, ...newIds};
    setState(() {
      _viewedStoryPostIds = updated;
      // unread フラグを再評価して即時反映
      _storyItems = _storyItems
          .map((s) => VibeStoryItem(
                userId: s.userId,
                username: s.username,
                iconUrl: s.iconUrl,
                posts: s.posts,
                unread: _isStoryUnread(s, updated),
              ))
          .toList();
    });
    final currentUserId = _auth.currentUser?.uid;
    if (currentUserId == null) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
      'viewed_story_posts_$currentUserId',
      updated.toList(),
    );
  }

  /// ストーリーアイテムの全投稿が既読セットに含まれていれば既読扱い（false）
  bool _isStoryUnread(VibeStoryItem story, Set<String> viewedIds) {
    return story.posts.any((p) => !viewedIds.contains(p.postId));
  }

  /// 招待コードによる自動フォローの通知を遅延送信（認証フロー完了後）
  Future<void> _processPendingFollowNotification() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final ownerUid = prefs.getString('pending_follow_owner_uid');
      if (ownerUid == null || ownerUid.isEmpty) return;

      final currentUser = _auth.currentUser;
      if (currentUser == null) return;

      // ユーザー情報が揃ってから通知を送信
      final senderUser = await _userService.getUser(currentUser.uid);
      if (senderUser == null) return;

      final username = senderUser.username;
      if (username == null || username.isEmpty || username == 'unknown') return;

      // 通知を送信
      final notificationService = NotificationService();
      await notificationService.createNotification(
        type: NotificationType.follow,
        recipientId: ownerUid,
        senderId: currentUser.uid,
        senderUsername: username,
        senderIconUrl: senderUser.profileImageUrl,
      );

      // 送信済みのpendingを削除
      await prefs.remove('pending_follow_owner_uid');
    } catch (_) {}
  }

  /// lastActiveAt を Firestore に書き込む（DAU/MAU 計測）
  /// 併せて、端末ローカルにしか無い「選択中の音楽サービス」を users doc へ同期する
  /// （管理者パネルのサービス別集計用）。同期は**そのユーザーを一度も刻んで
  /// いないときだけ**走り、既存ユーザーを埋め終われば起動時の処理は無くなる。
  Future<void> _updateLastActive() async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return;
    await _userService.updateLastActive(uid);
    await _musicServiceManager.syncSelectedServiceToProfile();
  }

  /// プルダウン更新（投稿リスト＋ユーザー情報＋Vibeを再取得）
  /// setState を1回にまとめてカクつきを防止
  Future<void> _onRefresh() async {
    final refreshStart = DateTime.now();
    // Vibe / 投稿 / ユーザーを並列取得。
    // 旧データを表示し続けたいので _vibeDataFuture は即時には差し替えず、
    // 完了済みデータと差し替える。
    final vibeDataFuture = _loadVibeData();
    final postsFuture = _fetchPostsData();
    final userRefreshFuture = context.read<CurrentUserProvider>().refresh();

    final postsResult = await postsFuture;
    await userRefreshFuture;
    final vibeData = await vibeDataFuture;

    // 最低1秒間はリフレッシュインジケーターを表示
    final elapsed = DateTime.now().difference(refreshStart);
    if (elapsed < const Duration(seconds: 1)) {
      await Future.delayed(Duration(seconds: 1) - elapsed);
    }

    if (mounted) {
      setState(() {
        _cachedPosts = postsResult.posts;
        _hasPostedToday = postsResult.hasPostedToday;
        _postedOnTimeThisCycle = postsResult.postedOnTimeThisCycle;
        _postedAnyThisCycle = postsResult.postedAnyThisCycle;
        _previewUrlCache.clear(); // リフレッシュ時はキャッシュをリセット
        // 完了済みFutureに差し替えればFutureBuilderはwaitingにならず暗転しない
        _vibeDataFuture = Future.value(vibeData);
      });
      final uid = _auth.currentUser?.uid ?? '';
      context.read<PostUIState>().resetAndInitialize(
        posts: postsResult.posts,
        currentUserId: uid,
      );
      if (postsResult.user != null && uid.isNotEmpty) {
        context.read<SavedItemsProvider>().initialize(
          userId: uid,
          user: postsResult.user!,
        );
      }
      _prefetchBacksideImages(postsResult.posts);
      _prefetchPreviewUrls(postsResult.posts);
    }
  }

  /// Vibe ストーリーバー用に、フォロー先 + 自分の 24h 投稿をユーザー単位で取得する。
  ///
  /// 仕様（[VibeStoryBarSection]）:
  /// - 24時間以内に投稿があるユーザーだけを並べる
  /// - 鍵投稿（audience=followers）は閲覧権限がない人には見えない
  ///   → そのユーザーに公開可能な投稿が0件なら、ストーリー円自体も出さない
  /// - 並びは「最新投稿の createdAt 降順」（左 = 最新、右 = 古い順）
  Future<List<VibeStoryItem>> _fetchStoryItems({
    required UserModel? viewer,
    required List<String> targetUserIds,
  }) async {
    if (targetUserIds.isEmpty) return const [];
    try {
      // viewer がフォローしている UID 集合（鍵投稿の可視判定に使う）
      final followingSet = (viewer?.following ?? const []).toSet();
      final viewerUid = viewer?.uid;
      bool viewerFollowsAuthor(String authorUid) {
        if (authorUid == viewerUid) return true; // 自分の投稿は常に可視
        return followingSet.contains(authorUid);
      }

      final grouped = await _postService.getRecentPostsGroupedByUser(
        userIds: targetUserIds,
        viewerFollowsAuthor: viewerFollowsAuthor,
      );

      return grouped
          .where((posts) => posts.isNotEmpty)
          .map((posts) {
            final head = posts.first;
            final tmp = VibeStoryItem(
              userId: head.userId,
              username: head.username,
              iconUrl: head.userIconUrl,
              posts: posts,
              unread: true,
            );
            return VibeStoryItem(
              userId: tmp.userId,
              username: tmp.username,
              iconUrl: tmp.iconUrl,
              posts: tmp.posts,
              // 既読セットに全 postId が含まれていればグレー枠（unread=false）
              unread: _isStoryUnread(tmp, _viewedStoryPostIds),
            );
          })
          .toList();
    } catch (e) {
      print('⚠️ ストーリーアイテム取得エラー: $e');
      return const [];
    }
  }

/// 投稿データをFirestoreから取得して返す（setState なし・_loadPosts/_onRefresh 共用）
  Future<({List<PostModel> posts, bool hasPostedToday, bool postedOnTimeThisCycle, bool postedAnyThisCycle, UserModel? user})> _fetchPostsData() async {
    try {
      final currentUser = _auth.currentUser;

      // 今日投稿済みかチェック
      bool hasPostedToday = false;
      // 現サイクルで期限内投稿済みか（リアクション可否のゲーティング用）
      bool postedOnTimeThisCycle = false;
      // 現サイクルで（Late 含む）投稿済みか（裏面閲覧のゲーティング用）
      bool postedAnyThisCycle = false;
      if (currentUser != null) {
        hasPostedToday = await _postService.hasUserPostedToday(currentUser.uid);
        postedOnTimeThisCycle =
            await _postService.hasOnTimePostInCurrentCycle(currentUser.uid);
        postedAnyThisCycle =
            await _postService.hasAnyPostInCurrentCycle(currentUser.uid);
      }

      // フォロー中のユーザーIDと保存済み情報を取得
      List<String> followingIds = [];
      UserModel? userModel;
      if (currentUser != null) {
        try {
          userModel = await _userService.getUser(currentUser.uid);
          followingIds = userModel?.following ?? [];
        } catch (e) {
          print('⚠️ フォロー一覧取得エラー: $e');
        }
      }
      final allTargetIds = currentUser != null
          ? [...followingIds, currentUser.uid]
          : followingIds;

      List<PostModel> firestorePosts = [];
      try {
        firestorePosts = allTargetIds.isEmpty
            ? []
            : await _postService.getPostsForFollowing(allTargetIds, limit: 50);
        print('📥 Firestoreから取得した投稿数: ${firestorePosts.length}');
      } catch (e) {
        print('⚠️ Firestore取得エラー（権限エラーの可能性）: $e');
      }

      // 【重要】Vibe ストーリーバーは現在非表示のため、その取得（_fetchStoryItems=
      // getRecentPostsGroupedByUser: limit なしで24h全投稿＋全ユーザー情報を逐次取得）は
      // 行わない。これを await で挟むと、重い/遅い場合にタイムライン表示が丸ごと
      // ブロックされ、_cachedPosts がセットされずスピナーのまま固まる不具合になる。
      // ストーリーバー復活時は、タイムライン表示をブロックしない別 Future で取得すること。

      final postsToUse = firestorePosts;
      print('📊 表示する投稿数: ${postsToUse.length} (Firestore)');

      // アルバムアートワークが空の投稿はSpotifyで補完（並列実行）
      final postsNeedingArt = <int>[];
      for (int i = 0; i < postsToUse.length; i++) {
        if (postsToUse[i].track.albumImageUrl.isEmpty) {
          postsNeedingArt.add(i);
        }
      }

      final updatedPosts = List<PostModel>.from(postsToUse);
      if (postsNeedingArt.isNotEmpty) {
        final futures = postsNeedingArt.map((i) async {
          final post = postsToUse[i];
          try {
            final searchQuery = '${post.track.trackName} ${post.track.artistName}';
            final tracks = await _spotifyService.searchTracks(searchQuery, limit: 1);
            if (tracks.isNotEmpty) {
              final updatedTrack = post.track.copyWith(
                albumImageUrl: tracks.first.albumImageUrl,
              );
              return MapEntry(i, post.copyWith(track: updatedTrack));
            }
          } catch (e) {
            print('⚠️ Spotifyアルバムアートワーク取得エラー: $e');
          }
          return MapEntry(i, post);
        }).toList();

        final artResults = await Future.wait(futures);
        for (final entry in artResults) {
          updatedPosts[entry.key] = entry.value;
        }
      }

      return (posts: updatedPosts, hasPostedToday: hasPostedToday, postedOnTimeThisCycle: postedOnTimeThisCycle, postedAnyThisCycle: postedAnyThisCycle, user: userModel);
    } catch (e) {
      print('❌ 投稿読み込みエラー: $e');
      return (posts: <PostModel>[], hasPostedToday: false, postedOnTimeThisCycle: false, postedAnyThisCycle: false, user: null);
    }
  }

  /// 投稿リストを読み込み（Firestoreから取得）
  Future<void> _loadPosts() async {
    print('📥 _loadPosts()開始');
    final result = await _fetchPostsData();
    if (mounted) {
      print('✅ 投稿読み込み完了: ${result.posts.length}件の投稿をセット');
      // 新しい投稿リストに存在しないキー・キャッシュを削除してメモリ節約
      final newPostIds = result.posts.map((p) => p.postId).toSet();
      _postCardKeys.removeWhere((id, _) => !newPostIds.contains(id));
      _previewUrlCache.removeWhere((id, _) => !newPostIds.contains(id));
      setState(() {
        _cachedPosts = result.posts;
        _hasPostedToday = result.hasPostedToday;
        _postedOnTimeThisCycle = result.postedOnTimeThisCycle;
        _postedAnyThisCycle = result.postedAnyThisCycle;
      });
      print('🔄 setState()完了');
      final uid = _auth.currentUser?.uid ?? '';
      context.read<PostUIState>().resetAndInitialize(
        posts: result.posts,
        currentUserId: uid,
      );
      if (result.user != null && uid.isNotEmpty) {
        context.read<SavedItemsProvider>().initialize(
          userId: uid,
          user: result.user!,
        );
      }
      _prefetchBacksideImages(result.posts);
      _prefetchPreviewUrls(result.posts);
    } else {
      print('⚠️ mountedがfalseのため、setStateをスキップ');
    }
  }

  /// 再生開始した index の隣接（i+1）投稿の音声を AudioPlayerService にプリロード。
  /// 次にタップされる可能性が高いカードの setUrl を先行実行し、
  /// タップ→再生までのネットワーク待ちをスキップする。
  void _preloadNeighborAudio(int currentIndex) {
    final posts = _cachedPosts;
    if (posts == null) return;
    final nextIndex = currentIndex + 1;
    if (nextIndex >= posts.length) return;
    final next = posts[nextIndex];
    final url = _previewUrlCache[next.postId];
    if (url == null || url.isEmpty) return;
    _homeAudioService.preload(
      url,
      startFrom: Duration(milliseconds: next.audioStartMs),
      durationSeconds: next.audioDurationSec,
    );
  }

  /// 全投稿の音楽プレビューURLをバックグラウンドで先取りする
  /// カードタップ時の遅延をなくすため、投稿読み込み直後にiTunes APIを叩いておく
  /// 3件ずつバッチで並列処理してAPIレート制限を緩和する
  Future<void> _prefetchPreviewUrls(List<PostModel> posts) async {
    const batchSize = 3;
    for (int i = 0; i < posts.length; i += batchSize) {
      if (!mounted) return;
      final batch = posts.skip(i).take(batchSize).toList();
      final futures = <Future<void>>[];

      for (final post in batch) {
        // 既にキャッシュ済みならスキップ
        if (_previewUrlCache.containsKey(post.postId)) continue;

        // post自身にpreviewUrlが入っていればそれを使う（API不要）
        if (post.track.previewUrl != null && post.track.previewUrl!.isNotEmpty) {
          _previewUrlCache[post.postId] = post.track.previewUrl;
          continue;
        }

        // iTunes APIでURL取得（バッチ内は並列）
        futures.add(() async {
          try {
            final result = await _itunesService.getPreviewUrlWithArt(
              trackName: post.track.trackName,
              artistName: post.track.artistName,
            );
            if (mounted) {
              _previewUrlCache[post.postId] = result?['previewUrl'];
            }
          } catch (_) {
            _previewUrlCache[post.postId] = null;
          }
        }());
      }

      // バッチ内の全URL取得が完了するまで待ってから次の3件へ
      await Future.wait(futures, eagerError: false);
    }
    // キャッシュが更新されたらPostCardに反映
    if (mounted) setState(() {});
  }

  /// 全投稿の裏面画像を3件ずつバッチでバックグラウンドプリフェッチ
  Future<void> _prefetchBacksideImages(List<PostModel> posts) async {
    const batchSize = 3;
    for (int i = 0; i < posts.length; i += batchSize) {
      if (!mounted) return;
      final batch = posts.skip(i).take(batchSize);
      final futures = <Future<void>>[];
      for (final post in batch) {
        // アルバムアート
        final albumUrl = post.track.albumImageUrl;
        if (albumUrl.isNotEmpty && albumUrl.startsWith('http')) {
          futures.add(precacheImage(CachedNetworkImageProvider(albumUrl), context));
        }
        // ユーザーアイコン
        final iconUrl = post.userIconUrl;
        if (iconUrl != null && iconUrl.isNotEmpty && iconUrl.startsWith('http')) {
          futures.add(precacheImage(CachedNetworkImageProvider(iconUrl), context));
        }
        // 投稿写真
        final photoUrl = post.photoUrl;
        if (photoUrl != null && photoUrl.isNotEmpty && photoUrl.startsWith('http')) {
          futures.add(precacheImage(CachedNetworkImageProvider(photoUrl), context));
        }
        // いいねユーザーアイコン（表示上限の3件のみ）
        for (final likedIconUrl in post.likedByUserIconUrls.take(3)) {
          if (likedIconUrl.isNotEmpty && likedIconUrl.startsWith('http')) {
            futures.add(precacheImage(CachedNetworkImageProvider(likedIconUrl), context));
          }
        }
      }
      // バッチ内の全画像が完了するまで待ってから次の3件へ
      await Future.wait(futures, eagerError: false);
    }
  }

  @override
  void dispose() {
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
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      // バックグラウンドでは無駄なポーリングを止める
      _storyRefreshTimer?.cancel();
      _storyRefreshTimer = null;
    }
  }

  /// ストーリーバー用の周期タイマーを (再) 開始する。
  /// 即時に 1 回 fire (fire-and-forget) してから 30 秒間隔でポーリング。
  ///
  /// アプリ起動時: initState から呼ばれ、prefetch データで initialPosts が
  /// 埋まっているケースでも即時にストーリーを更新する (prefetch はストーリーを
  /// 含まないため、これが無いと最初の 30 秒間ストーリーが空になる)。
  /// フォアグラウンド復帰時: didChangeAppLifecycleState から呼ばれ、停止した
  /// タイマーを再開しつつ即時同期する。
  void _startStoryRefreshTimer() {
    _storyRefreshTimer?.cancel();
    // ignore: discarded_futures
    _refreshStoriesOnly();
    _storyRefreshTimer =
        Timer.periodic(_kStoryRefreshInterval, (_) => _refreshStoriesOnly());
  }

  /// ストーリーバー用のデータだけを再取得 (タイムライン等のフェッチはしない)。
  /// [_loadPosts] に比べて Firestore 読み込みは 1 バッチのみで軽量。
  Future<void> _refreshStoriesOnly() async {
    if (!mounted) return;
    final currentUser = _auth.currentUser;
    if (currentUser == null) return;
    try {
      // 対象 UID: フォロー中 + 自分。CurrentUserProvider には following が
      // 無いので Firestore から取り直す。バッチ 1 回 + createdAt 24h 制約なので軽量。
      UserModel? viewer;
      List<String> followingIds = const [];
      try {
        viewer = await _userService.getUser(currentUser.uid);
        followingIds = viewer?.following ?? const [];
      } catch (_) {}
      final targetIds = [...followingIds, currentUser.uid];
      final allStories = await _fetchStoryItems(
        viewer: viewer,
        targetUserIds: targetIds,
      );
      if (!mounted) return;
      VibeStoryItem? own;
      final followingStories = <VibeStoryItem>[];
      for (final s in allStories) {
        if (s.userId == currentUser.uid) {
          own = s;
        } else {
          followingStories.add(s);
        }
      }
      setState(() {
        _storyItems = followingStories;
        _ownStoryItem = (own != null && own.posts.isNotEmpty) ? own : null;
      });
    } catch (e) {
      // 静かに失敗させる。次回ティックで再試行。
      if (kDebugMode) {
        print('⚠️ ストーリー自動更新エラー: $e');
      }
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

  /// スクロール時に各カードの可視性を確認し、
  /// 最も多く見えているカード（50%超）以外の裏面カードを表面に戻す
  void _checkPlayingCardVisibility() {
    // 2列グリッドの拡大オーバーレイ表示中は、再生カードがグリッド上で
    // プレースホルダ扱いになり「画面外」と誤判定されるため、停止処理をスキップ。
    if (_gridEnlargedActive) return;
    final screenHeight = MediaQuery.of(context).size.height;

    String? dominantPostId;
    double bestVisibleFraction = 0;

    // 全カードの可視割合を計算し、最も多く見えているカードを特定
    for (final entry in _postCardKeys.entries) {
      final postId = entry.key;
      final key = entry.value;
      final renderBox = key.currentContext?.findRenderObject() as RenderBox?;
      if (renderBox == null || !renderBox.attached) continue;

      final cardTop = renderBox.localToGlobal(Offset.zero).dy;
      final cardHeight = renderBox.size.height;
      final cardBottom = cardTop + cardHeight;

      // 完全に画面外のカードはスキップ
      if (cardBottom <= 0 || cardTop >= screenHeight) continue;

      final visibleTop = cardTop.clamp(0.0, screenHeight.toDouble());
      final visibleBottom = cardBottom.clamp(0.0, screenHeight.toDouble());
      final visibleFraction = (visibleBottom - visibleTop) / cardHeight;

      if (visibleFraction > 0.5 && visibleFraction > bestVisibleFraction) {
        bestVisibleFraction = visibleFraction;
        dominantPostId = postId;
      }
    }

    // 再生中カードが画面外 or dominant以外になったら音楽を停止し、同時に表面に戻す
    if (_playingPostId != null && _playingPostId != dominantPostId) {
      _homeAudioService.stop();
      _postCardKeys[_playingPostId]?.currentState?.flipToFront();
      _playingPostId = null;
    }

    // dominant以外のカードをすべて表面に戻す（音楽停止と同タイミング）
    for (final entry in _postCardKeys.entries) {
      final postId = entry.key;
      final key = entry.value;
      if (postId != dominantPostId) {
        key.currentState?.flipToFront();
      }
    }
  }

  /// スクロール量に応じてベルアイコンの透明度を更新
  void _updateBellOpacity() {
    if (!_scrollController.hasClients) return;
    final offset = _scrollController.offset;
    _bellOpacity.value = (1.0 - (offset / 80.0)).clamp(0.0, 1.0);
  }

  /// グラデーション幕の上に浮かせるヘッダー（"15s" + 通知ベル）。
  /// 背景色を持たず（＝タッチを吸わない）、タイトルは IgnorePointer、ベルのみ操作可能。
  /// これによりヘッダー領域でもスクロール/プル更新のジェスチャーが背後のリストへ通る。
  Widget _homeHeaderOverlay(double headerHeight, double topPadding) {
    return SizedBox(
      height: headerHeight,
      child: Padding(
        padding: EdgeInsets.only(left: 16, right: 16, top: topPadding),
        child: Stack(
          children: [
            const Center(
              child: IgnorePointer(
                child: Text(
                  '15s',
                  style: TextStyle(
                    fontSize: 30,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                    fontFamily: 'SFPro',
                  ),
                ),
              ),
            ),
            // 左上: 友達追加ボタン（遷移先UIは作成中のため現状はトースト表示）。
            // Figma 5189:11175: グリフ箱 42×29 @x=23。素材は4x書き出しのタイト画像
            // (155×102) なので実寸 38.75×25.5。ヘッダー左padding16を差し引き left=8。
            Positioned(
              left: 8,
              top: 0,
              bottom: 0,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () {
                  _homeAudioService.stop();
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const SearchScreen(showBackButton: true),
                    ),
                  );
                },
                child: Center(
                  child: Image.asset(
                    'assets/icons/friend_add.png',
                    width: 38.75,
                    height: 25.5,
                    fit: BoxFit.fill,
                    color: Colors.white,
                    colorBlendMode: BlendMode.srcIn,
                  ),
                ),
              ),
            ),
            // 右上: グリッド切替 + 通知ベル。
            Positioned(
              right: 0,
              top: 0,
              bottom: 0,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // グリッド切替（1列 ⇔ 2列）。表示中の列数に応じてアイコンを切替。
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => setState(() => _isGridView = !_isGridView),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 8),
                      child: Image.asset(
                        _isGridView
                            ? 'assets/icons/grid_1col.png'
                            : 'assets/icons/grid_2col.png',
                        width: 24,
                        height: 24,
                        color: Colors.white,
                        colorBlendMode: BlendMode.srcIn,
                      ),
                    ),
                  ),
                  ValueListenableBuilder<double>(
                    valueListenable: _bellOpacity,
                    builder: (_, opacity, child) => Opacity(
                      opacity: opacity,
                      child:
                          IgnorePointer(ignoring: opacity < 0.1, child: child),
                    ),
                    child: NotificationBadge(
                      child: IconButton(
                        icon: const Icon(Icons.notifications_outlined,
                            color: Colors.white),
                        onPressed: () {
                          _homeAudioService.stop();
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                                builder: (_) => const NotificationListScreen()),
                          );
                        },
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


  // ボトムナビゲーションのタップ処理
  /// VibeバーのVibeアイコン円タップでVibeプレイリスト画面へ遷移
  Future<void> _navigateToVibePost() async {
    // データ未ロード/失敗時は強制的に再読み込み
    _vibeDataFuture ??= _loadVibeData();
    final data = await _vibeDataFuture!;
    if (!mounted) return;
    final topic = data['topic'] as VibeTopicModel?;
    final ranking =
        (data['ranking'] as List?)?.cast<VibeRankingItem>() ?? <VibeRankingItem>[];

    // トピックが取れなかった場合は再読み込みしてもう一度試す
    if (topic == null) {
      _vibeDataFuture = _loadVibeData();
      final retry = await _vibeDataFuture!;
      if (!mounted) return;
      final retryTopic = retry['topic'] as VibeTopicModel?;
      final retryRanking = (retry['ranking'] as List?)
              ?.cast<VibeRankingItem>() ??
          <VibeRankingItem>[];
      if (retryTopic == null) {
        _showMessage('お題が見つかりませんでした');
        return;
      }
      _navigateToVibePlaylistInternal(retryTopic, retryRanking);
      return;
    }

    _navigateToVibePlaylistInternal(topic, ranking);
  }

  /// VibePlaylistScreen への実遷移
  Future<void> _navigateToVibePlaylistInternal(
    VibeTopicModel topic,
    List<VibeRankingItem> ranking,
  ) async {
    _homeAudioService.stop();
    if (TutorialController.instance.step == TutorialStep.showVibePlaylistHint) {
      await TutorialController.instance.goTo(TutorialStep.swipeUpInPlaylist);
    }
    if (!mounted) return;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => VibePlaylistScreen(
          topic: topic,
          ranking: ranking,
          currentUserId: _auth.currentUser?.uid ?? '',
          hasPostedToday: _hasPostedToday,
        ),
      ),
    );
  }

  /// チュートリアル Frame628 でアクティブカードが変わったときに呼ばれる
  Future<void> _onTutorialAlbumChanged(int index) async {
    _tutorialActiveIndex = index;
    final items = TutorialAlbumCarousel.defaultItems;
    if (index >= items.length) return;
    final item = items[index];
    final cacheKey = '${item.title}__${item.artist}';
    await TutorialPrefetchService.instance.ensureReady(cacheKey, item);
    if (!mounted || _tutorialActiveIndex != index) return;
    final previewUrl = TutorialPrefetchService.instance.previewCache[cacheKey];
    if (previewUrl != null && previewUrl.isNotEmpty) {
      // owner: this を渡すことで、他画面の dispose() が呼ぶ
      // stopIfOwner() に巻き添えで止められないようにする
      _homeAudioService
          .playPreview(previewUrl, owner: this)
          .catchError((_) {});
    }
    // 次のカードを2秒遅延で preload する。
    // 即座に preload するとメインプレイヤーの再生が iOS 側で中断される現象が発生したため、
    // 現在再生中の音声が安定してから preload を開始する。
    final nextIndex = (index + 1) % items.length;
    Future.delayed(const Duration(seconds: 2), () {
      if (!mounted || _tutorialActiveIndex != index) return;
      TutorialPrefetchService.instance
          .preloadAudio(items[nextIndex])
          .catchError((_) {});
    });
  }

  /// チュートリアル Frame628 で曲が確定されたときに呼ばれる
  Future<void> _onTutorialSongConfirmed(TutorialAlbumItem item) async {
    _homeAudioService.stop();
    final cacheKey = '${item.title}__${item.artist}';
    await TutorialPrefetchService.instance.ensureReady(cacheKey, item);
    if (!mounted) return;
    final cache = TutorialPrefetchService.instance;
    final albumArtUrl = cache.artCache[cacheKey]?.isNotEmpty == true
        ? cache.artCache[cacheKey]!
        : item.assetPath;
    _tutorialTrack = TrackModel(
      trackId: 'tutorial_${item.title.hashCode}',
      trackName: item.title,
      artistName: item.artist,
      albumImageUrl: albumArtUrl,
      previewUrl: cache.previewCache[cacheKey],
    );
    await TutorialController.instance.goTo(TutorialStep.takingPhoto);
  }

  /// 「楽曲をVibeに追加」ボタンタップで投稿フロー（楽曲選択）へ遷移
  Future<void> _navigateToPostFlow() async {
    _homeAudioService.stop();

    final targetIndex = await Navigator.push<int>(
      context,
      PageRouteBuilder(
        pageBuilder: (_, __, ___) => const MusicSelectionScreen(initialCategoryType: 'vibe', fromVibePlaylist: true),
        transitionDuration: Duration.zero,
        reverseTransitionDuration: Duration.zero,
      ),
    );
    if (targetIndex != null && mounted) {
      setState(() => _selectedIndex = targetIndex);
    }
  }

  /// 投稿フローの起点（ホームの FAB から呼ぶ）。
  /// - Apple Music: 「今日のMusic Memory」カルーセル(MusicMemoryModal)。
  /// - Spotify / 未連携: ログが取れないため Vibe 楽曲選択シート（お題非表示）→
  ///   曲決定で Apple と同じ写真フロー(PostPhotoSelectionScreen)へ。
  Future<void> _openPostFlow() async {
    _homeAudioService.stop();
    final service = await _musicServiceManager.getSelectedService();
    if (!mounted) return;
    if (service == MusicServiceType.appleMusic) {
      await MusicMemoryModal.open(context);
    } else {
      VibeStoryPostSheet.show(
        context,
        moodPostMode: true,
        onTrackChosen: (track) {
          Navigator.of(context).push(
            MaterialPageRoute(
              fullscreenDialog: true,
              builder: (_) => PostPhotoSelectionScreen(
                track: track,
                isMoodPost: true,
              ),
            ),
          );
        },
      );
    }
  }

  /// Music Memory タブ（カレンダー）。プロフィールから開く月画面を
  /// ルートタブとして埋め込む（戻るボタンは非表示）。
  Widget _buildMusicMemoryTab() {
    final user = _auth.currentUser;
    return MusicMemoryMonthScreen(
      key: const ValueKey('music_memory_tab'),
      embedded: true,
      userId: user?.uid,
      accountCreatedAt: user?.metadata.creationTime,
    );
  }

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

  /// Vibeデータを読み込み（今日のお題とランキング）
  Future<Map<String, dynamic>> _loadVibeData() async {
    try {
      final forAdl = await AdlService().isCurrentUserAdlParticipant();
      final topic = await _vibeTopicService.getTodaysTopic(forAdl: forAdl);
      if (topic == null) {
        return {'topic': null, 'ranking': []};
      }

      final ranking = await _postService.calculateVibeRanking(
        topic.topicId,
        DateTime.now(),
        limit: 1000,
      );

      return {'topic': topic, 'ranking': ranking};
    } catch (e) {
      print('Error loading vibe data: $e');
      return {'topic': null, 'ranking': []};
    }
  }

  /// ランキングアイテムがタップされたときの処理
  Future<void> _handleRankingItemTap(VibeRankingItem item) async {
    try {
      // 今日のお題を取得
      final forAdl = await AdlService().isCurrentUserAdlParticipant();
      final topic = await _vibeTopicService.getTodaysTopic(forAdl: forAdl);
      if (topic == null) {
        _showMessage('お題が見つかりませんでした');
        return;
      }

      // そのお題の全投稿を取得
      final allPosts = await _postService.getVibePostsByTopic(
        topic.topicId,
        DateTime.now(),
      );

      // タップされたトラックに一致する投稿のみをフィルタ
      final trackKey = item.track.trackId.isNotEmpty
          ? item.track.trackId
          : '${item.track.trackName}_${item.track.artistName}';

      final matchingPosts = allPosts.where((post) {
        final postTrackKey = post.track.trackId.isNotEmpty
            ? post.track.trackId
            : '${post.track.trackName}_${post.track.artistName}';
        return postTrackKey == trackKey;
      }).toList();

      if (matchingPosts.isEmpty) {
        _showMessage('投稿が見つかりませんでした');
        return;
      }

      // ホーム画面の音楽を停止
      _homeAudioService.stop();

      // 投稿一覧画面に遷移（hasPostedTodayを渡してローディングをスキップ）
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => VibeTrackPostsScreen(
            track: item.track,
            posts: matchingPosts,
            currentUserId: _auth.currentUser?.uid ?? 'test_user_temp',
            initialHasPostedToday: _hasPostedToday,
            onTabSwitch: (i) {
              if (mounted) setState(() => _selectedIndex = i);
            },
          ),
        ),
      );
    } catch (e) {
      print('Error handling ranking item tap: $e');
      _showMessage('投稿の読み込みに失敗しました');
    }
  }

  /// タイムライン（投稿カードリスト）- Sliver版
  /// 1件分の PostCard を構築（1列・2列グリッド共用）。
  PostCard _buildPostCardFor({
    required PostModel post,
    required int index,
    required PostUIState postUIState,
    required SavedItemsProvider savedItems,
    required String? currentUserIconUrl,
    required GlobalKey<PostCardState> cardKey,
    bool externalFlipControl = false,
    VoidCallback? onCardTap,
    // 共有/コメント/削除など別シート・ダイアログを開く直前に呼ぶ。
    // 2列グリッドの拡大オーバーレイを閉じ、シートの上に残らないようにする。
    VoidCallback? onBeforeSheet,
  }) {
    final currentUserId = _auth.currentUser?.uid ?? 'test_user_temp';
    final displayPost = postUIState.getDisplayPost(
      post,
      currentUserId: currentUserId,
      currentUserIconUrl: currentUserIconUrl,
    );

    // ゲーティング（裏面閲覧とリアクションを分離）:
    //  - 裏面（写真）閲覧: 自分の投稿 or 現サイクルで投稿済み（Late 含む）
    //    or 既に裏を見た投稿。未投稿者は表面のみ。
    //  - リアクション（いいね・コメント）: 自分の投稿 or 現サイクルで
    //    「期限内（25:00 まで）」投稿済みのときのみ。Late 投稿者は不可。
    final isOwnPost = post.userId == currentUserId;
    final canViewBack = isOwnPost ||
        _postedAnyThisCycle ||
        _revealedPostIds.contains(post.postId);
    final canReact = isOwnPost || _postedOnTimeThisCycle;

    return PostCard(
      key: cardKey,
      post: displayPost,
      currentUserId: currentUserId,
      currentUserIconUrl: currentUserIconUrl,
      audioService: _homeAudioService,
      externalPreviewUrl: _previewUrlCache[post.postId],
      externalFlipControl: externalFlipControl,
      onCardTap: onCardTap,
      onLike: () => _handleLike(post),
      onComment: () {
        onBeforeSheet?.call();
        _handleComment(post);
      },
      onReaction: (emoji) => _handleReaction(post, emoji),
      onAdd: () => _handleAdd(post),
      onDelete: post.userId == currentUserId
          ? () {
              onBeforeSheet?.call();
              _handleDelete(post);
            }
          : null,
      isSaved: savedItems.isPostOrTrackSaved(post),
      backSideEnabled: canViewBack,
      disableInteractions: !canReact,
      onFlipToBack: () => _markPostRevealed(post.postId),
      onPlayStarted: () {
        _playingPostId = post.postId;
        // 2列グリッドの拡大プレビューでは隣接プリロードをしない。
        // 隣の音声用に別 AudioPlayer を生成すると、iOS の共有オーディオセッション経由で
        // メイン再生の setUrl が中断され（"Loading interrupted"）音が鳴らないため。
        if (!externalFlipControl) _preloadNeighborAudio(index);
      },
      onShare: () {
        onBeforeSheet?.call();
        showCardShareSheet(
          context,
          post: post,
          currentUserId: currentUserId,
          currentUserIconUrl: currentUserIconUrl,
          isSaved: savedItems.isPostOrTrackSaved(post),
        );
      },
    );
  }

  /// タイムライン0件時の投稿促しカード（Figma 5227:10820 / 5231:11175）。
  /// 投稿カードと同じ 363:645 の暗いカードに、中央の文言＋白ピルボタンを配置。
  Widget _buildEmptyTimelinePromptSliver() {
    const grey = Color(0xFF9D9D9D);
    return SliverPadding(
      padding: const EdgeInsets.fromLTRB(15, 9, 15, 0),
      sliver: SliverToBoxAdapter(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final w = constraints.maxWidth;
            final h = w * 645 / 363;
            return Container(
              width: w,
              height: h,
              decoration: BoxDecoration(
                color: const Color(0xFF141414),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFF2A2A2A), width: 1),
              ),
              alignment: Alignment.center,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    '今日のMusic Memory',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 22,
                      fontWeight: FontWeight.w600,
                      height: 1.5,
                    ),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'まだ投稿していません',
                    style: TextStyle(color: grey, fontSize: 11, height: 1.5),
                  ),
                  const SizedBox(height: 21),
                  const Text(
                    'あなたの今日を彩る1曲を\n残してみましょう',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: grey, fontSize: 11, height: 1.5),
                  ),
                  const SizedBox(height: 26),
                  // 白ピルボタン 174×46（＋アイコン + テキスト）→ 投稿フロー。
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: _openPostFlow,
                    child: Container(
                      width: 174,
                      height: 46,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(49),
                      ),
                      child: const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.add, color: Colors.black, size: 22),
                          SizedBox(width: 8),
                          Text(
                            '今日の1曲を残す',
                            style: TextStyle(
                              color: Colors.black,
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildTimelineSliver(PostUIState postUIState, SavedItemsProvider savedItems, String? currentUserIconUrl) {
    final posts = _cachedPosts!;

    // タイムラインに投稿が0件のとき、投稿を促すカードを表示（Figma 5227:10820）。
    if (posts.isEmpty) {
      return _buildEmptyTimelinePromptSliver();
    }

    if (_isGridView) {
      // 2列グリッド。タップで「その場拡大 → 0.2秒後に自動反転」。
      return SliverPadding(
        padding: const EdgeInsets.symmetric(horizontal: 15),
        sliver: SliverGrid(
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            crossAxisSpacing: 11,
            mainAxisSpacing: 16,
            // PostCard 前面の縦横比 363:645 に合わせる。
            childAspectRatio: 363 / 645,
          ),
          delegate: SliverChildBuilderDelegate(
            (context, index) {
              final post = posts[index];
              final cardKey = _postCardKeys.putIfAbsent(
                  post.postId, () => GlobalKey<PostCardState>());
              final currentUserId = _auth.currentUser?.uid ?? 'test_user_temp';
              final isOwnPost = post.userId == currentUserId;
              final canViewBack = isOwnPost ||
                  _postedAnyThisCycle ||
                  _revealedPostIds.contains(post.postId);
              return _GridPostCell(
                key: ValueKey('grid_${post.postId}'),
                cardKey: cardKey,
                canViewBack: canViewBack,
                onEnlargedChanged: (v) => _gridEnlargedActive = v,
                builder: (key, onTap, requestClose) => _buildPostCardFor(
                  post: post,
                  index: index,
                  postUIState: postUIState,
                  savedItems: savedItems,
                  currentUserIconUrl: currentUserIconUrl,
                  cardKey: key,
                  externalFlipControl: true,
                  onCardTap: onTap,
                  onBeforeSheet: requestClose,
                ),
              );
            },
            childCount: posts.length,
          ),
        ),
      );
    }

    return SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: 15),
      sliver: SliverList(
        delegate: SliverChildBuilderDelegate(
          (context, index) {
            final post = posts[index];
            final cardKey = _postCardKeys.putIfAbsent(
                post.postId, () => GlobalKey<PostCardState>());

            return Padding(
              padding: const EdgeInsets.only(bottom: 24),
              child: RepaintBoundary(
                child: _buildPostCardFor(
                  post: post,
                  index: index,
                  postUIState: postUIState,
                  savedItems: savedItems,
                  currentUserIconUrl: currentUserIconUrl,
                  cardKey: cardKey,
                ),
              ),
            );
          },
          childCount: posts.length,
        ),
      ),
    );
  }

  /// いいねボタンが押されたときの処理
  Future<void> _handleLike(PostModel post) async {
    final currentUser = _auth.currentUser;
    final userId = currentUser?.uid ?? 'test_user_temp';
    final postUIState = context.read<PostUIState>();

    final currentLikeCount = postUIState.getLikeCount(post.postId) ?? post.likeCount;
    final wasLiked = postUIState.isLiked(post.postId);

    // 楽観的UI更新（notifyListeners → build再実行）
    postUIState.toggleLike(post.postId, currentLikeCount: currentLikeCount);

    try {
      await _postService.toggleLike(
        postId: post.postId,
        userId: userId,
      );
    } catch (e) {
      // エラー時はロールバック
      if (mounted) {
        postUIState.revertLikeToggle(
          post.postId,
          originalLikeCount: currentLikeCount,
          wasLiked: wasLiked,
        );
      }
      _showMessage('いいねに失敗しました');
    }
  }

  /// 絵文字リアクションが選ばれたときの処理（1ユーザー＝1つ・変更/取消可）。
  /// カード側で楽観的UI・アニメを済ませているので、ここでは Firestore 書き込みのみ。
  Future<void> _handleReaction(PostModel post, String emoji) async {
    final userId = _auth.currentUser?.uid;
    if (userId == null) return;
    try {
      await _postService.setReaction(
        postId: post.postId,
        emoji: emoji,
        userId: userId,
      );
    } catch (e) {
      _showMessage('リアクションに失敗しました');
    }
  }

  /// コメント数を更新（コメント画面から呼ばれる）
  void _updateCommentCount(String postId, int count) {
    if (mounted) {
      context.read<PostUIState>().updateCommentCount(postId, count);
    }
  }

  /// コメントボタンが押されたときの処理
  Future<void> _handleComment(PostModel post) async {
    // コメント画面をボトムシートで表示（音楽は継続）
    await CommentScreen.show(
      context,
      post: post,
      onCommentCountChanged: (count) =>
          _updateCommentCount(post.postId, count),
    );

    // 戻ってきた後、投稿データを更新
    if (mounted) {
      final updatedPost = await _postService.getPost(post.postId);
      if (updatedPost != null && _cachedPosts != null) {
        setState(() {
          final index = _cachedPosts!.indexWhere((p) => p.postId == post.postId);
          if (index != -1) {
            _cachedPosts![index] = updatedPost;
          }
        });
      }
    }
  }

  /// 追加ボタンが押されたときの処理（投稿を保存）
  Future<void> _handleAdd(PostModel post) async {
    await SavedItemsProvider.togglePostWithToast(context, post);
  }

  /// 削除ボタンが押されたときの処理
  Future<void> _handleDelete(PostModel post) async {
    final confirmed = await showDeletePostConfirmDialog(context);

    if (!confirmed) return;

    try {
      await _postService.deletePost(post.postId);
      if (mounted) {
        setState(() {
          _cachedPosts?.removeWhere((p) => p.postId == post.postId);
        });
        _showMessage('投稿を削除しました');
      }
    } catch (e) {
      if (mounted) _showMessage('削除に失敗しました');
    }
  }

  /// メッセージを表示
  void _showMessage(String message) {
    if (mounted) {
      AppToast.show(context, message);
    }
  }

}

/// ホーム画面の透明ピン留めヘッダー用デリゲート（15s タイトル + 通知ベル）。
class _HomeHeaderDelegate extends SliverPersistentHeaderDelegate {
  final double height;
  final double topPadding;
  final ValueNotifier<double> bellOpacity;
  final Widget bellButton;

  _HomeHeaderDelegate({
    required this.height,
    required this.topPadding,
    required this.bellOpacity,
    required this.bellButton,
  });

  @override
  double get minExtent => height;

  @override
  double get maxExtent => height;

  @override
  Widget build(
      BuildContext context, double shrinkOffset, bool overlapsContent) {
    return Container(
      color: Colors.transparent,
      padding: EdgeInsets.only(left: 16, right: 16, top: topPadding),
      child: Stack(
        children: [
          const Center(
            child: Text(
              '15s',
              style: TextStyle(
                fontSize: 30,
                fontWeight: FontWeight.w600,
                color: Colors.white,
                fontFamily: 'SFPro',
              ),
            ),
          ),
          Positioned(
            right: 0,
            top: 0,
            bottom: 0,
            child: ValueListenableBuilder<double>(
              valueListenable: bellOpacity,
              builder: (_, opacity, child) => Opacity(
                opacity: opacity,
                child: IgnorePointer(ignoring: opacity < 0.1, child: child),
              ),
              child: bellButton,
            ),
          ),
        ],
      ),
    );
  }

  @override
  bool shouldRebuild(_HomeHeaderDelegate old) =>
      old.height != height || old.topPadding != topPadding;
}

/// ホーム2列グリッドの1セル。
/// タップすると、その投稿カードが元の位置から**拡大**し（オーバーレイで前面に浮かせて
/// 中央・1列幅へ）、0.2秒後に自動で裏面へ反転する。もう一度タップ（またはカード外
/// タップ）で表面へ戻し縮小。
///
/// 拡大表示はオーバーレイに**別インスタンスの PostCard**（[_overlayCardKey]）を生成して
/// 行う。セル内カードを移動させないため、従来通りの裏返しアニメーションが確実に動く。
/// 拡大中はセル側を空プレースホルダにして二重描画・二重再生を防ぐ。
class _GridPostCell extends StatefulWidget {
  final GlobalKey<PostCardState> cardKey;
  final bool canViewBack;
  /// builder(key, onTap, requestClose): key=カードに付与する GlobalKey、
  /// onTap=カードタップ処理、requestClose=拡大を即キャンセル。
  final Widget Function(GlobalKey<PostCardState> key, VoidCallback onTap,
      VoidCallback requestClose) builder;
  /// 拡大オーバーレイの表示/非表示が変わったとき（true=表示中）に通知。
  final ValueChanged<bool>? onEnlargedChanged;

  const _GridPostCell({
    super.key,
    required this.cardKey,
    required this.canViewBack,
    required this.builder,
    this.onEnlargedChanged,
  });

  @override
  State<_GridPostCell> createState() => _GridPostCellState();
}

class _GridPostCellState extends State<_GridPostCell>
    with SingleTickerProviderStateMixin {
  final GlobalKey _cellKey = GlobalKey();
  // オーバーレイの拡大カード用（セル内カードとは別インスタンス）。
  final GlobalKey<PostCardState> _overlayCardKey = GlobalKey<PostCardState>();
  late final AnimationController _anim; // 0=セル内, 1=拡大
  OverlayEntry? _entry;
  Rect _startRect = Rect.zero;
  bool _active = false;

  // 1列タイムラインと同じ左右padding（15px）。拡大時はこの幅の中央配置にする。
  static const double _oneColPadding = 15.0;
  // PostCard 前面の縦横比（363:645）。
  static const double _cardAspect = 363 / 645;

  @override
  void initState() {
    super.initState();
    _anim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 220),
    )..addListener(() => _entry?.markNeedsBuild());
  }

  @override
  void dispose() {
    _removeEntry();
    _anim.dispose();
    super.dispose();
  }

  void _onTap() {
    if (!_active) {
      _open();
    } else {
      _close();
    }
  }

  void _open() {
    final box = _cellKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return;
    _startRect = box.localToGlobal(Offset.zero) & box.size;
    _active = true;
    widget.onEnlargedChanged?.call(true);
    setState(() {}); // セル → プレースホルダ（拡大カードはオーバーレイに別途生成）
    _entry = OverlayEntry(builder: _buildOverlay);
    Overlay.of(context, rootOverlay: true).insert(_entry!);
    _anim.forward(from: 0);
    // 拡大後 0.2秒で自動アクション。
    // - 裏面閲覧可: 反転＋音楽再生。
    // - 裏面閲覧不可（他人の投稿など）: 反転はせず音楽だけ再生（1列表示と同じ挙動）。
    Future.delayed(const Duration(milliseconds: 200), () {
      if (!_active) return;
      final st = _overlayCardKey.currentState;
      if (widget.canViewBack) {
        st?.flipToBack(playAudio: true);
      } else {
        st?.playAudioOnly();
      }
    });
  }

  Future<void> _close() async {
    _overlayCardKey.currentState?.flipToFront();
    try {
      await _anim.reverse();
    } catch (_) {}
    _removeEntry();
    if (mounted) setState(() {}); // カードをセルへ戻す
  }

  /// アニメーションなしで即座に拡大をキャンセルする。
  /// 共有/コメント/削除など別シートを開く直前に呼び、シートの上に残らないようにする。
  void _closeNow() {
    if (!_active) return;
    _anim.stop();
    _overlayCardKey.currentState?.flipToFront();
    _removeEntry();
    if (mounted) setState(() {});
  }

  void _removeEntry() {
    _entry?.remove();
    _entry = null;
    _active = false;
    widget.onEnlargedChanged?.call(false);
  }

  /// 拡大の目標矩形 = 1列配置と同じ「中央・1列カード幅」。
  Rect _targetRect(Size media) {
    // 1列カード幅（左右15pxマージン）。ただし高さが画面に収まらない場合は高さ基準に。
    double w = media.width - _oneColPadding * 2;
    double h = w / _cardAspect;
    final maxH = media.height - 120; // 上下マージン
    if (h > maxH) {
      h = maxH;
      w = h * _cardAspect;
    }
    final left = (media.width - w) / 2;
    final top = (media.height - h) / 2;
    return Rect.fromLTWH(left, top, w, h);
  }

  Widget _buildOverlay(BuildContext ctx) {
    final media = MediaQuery.of(ctx).size;
    final t = Curves.easeOut.transform(_anim.value);
    // セル位置 → 中央1列位置へ補間（縦横比は一定なので歪みなし）。
    final rect = Rect.lerp(_startRect, _targetRect(media), t)!;
    return Stack(
      children: [
        // 透明バリア（暗転なし）。カード外タップで閉じる。スクロールも遮る。
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _close,
            child: const SizedBox.expand(),
          ),
        ),
        Positioned(
          left: rect.left,
          top: rect.top,
          width: rect.width,
          height: rect.height,
          // Material の祖先を与えないと Text に黄色い二重下線が出るため透明 Material で包む。
          child: Material(
            type: MaterialType.transparency,
            child: FittedBox(
              fit: BoxFit.contain,
              // 拡大カードは別インスタンス（_overlayCardKey）。従来通り反転可能。
              child: widget.builder(_overlayCardKey, _onTap, _closeNow),
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox.expand(
      key: _cellKey,
      child: _active
          ? const SizedBox.expand() // 拡大中はセル内カードを退避（空表示）
          : RepaintBoundary(
              child: FittedBox(
                fit: BoxFit.contain,
                child: widget.builder(widget.cardKey, _onTap, _closeNow),
              ),
            ),
    );
  }
}

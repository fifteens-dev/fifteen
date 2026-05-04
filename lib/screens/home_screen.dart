import 'dart:async';
import 'package:cached_network_image/cached_network_image.dart';
import '../main.dart' show routeObserver;
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:provider/provider.dart';
import '../constants/app_colors.dart';
import '../models/post_model.dart';
import '../models/user_model.dart';
import '../providers/post_ui_state.dart';
import '../models/vibe_ranking_item.dart';
import '../models/vibe_topic_model.dart';
import '../widgets/post_card.dart';
import '../widgets/notification_badge.dart';
import '../widgets/dialogs/delete_post_dialog.dart';
import '../services/post_service.dart';
import '../services/spotify_service.dart';
import '../services/audio_player_service.dart';
import '../services/itunes_search_service.dart';
import '../services/user_service.dart';
import '../services/notification_service.dart';
import '../models/notification_model.dart';
import '../services/vibe_topic_service.dart';
import '../utils/campus_vibe_utils.dart';
import '../widgets/campus_vibe_card.dart';
import '../utils/current_user_helper.dart';
import 'comment_screen.dart';
import 'search_screen.dart';
import 'profile_screen.dart';
import 'music_selection_screen.dart';
import 'notification_list_screen.dart';
import 'vibe_track_posts_screen.dart';
import 'vibe_playlist_screen.dart';
import 'card_share_screen.dart';
import 'home/vibe_bar_section.dart';
import 'home/home_bottom_nav.dart';
import '../widgets/common/app_toast.dart';
import '../services/tutorial_controller.dart';
import '../services/tutorial_prefetch_service.dart';
import '../widgets/tutorial/tutorial_coachmark.dart';
import '../widgets/tutorial/animated_hand_cursor.dart';
import '../widgets/tutorial/tutorial_frame628_overlay.dart';
import '../widgets/tutorial/tutorial_album_carousel.dart';
import '../widgets/tutorial/tutorial_camera_overlay.dart';
import '../models/track_model.dart';
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
    with AutomaticKeepAliveClientMixin
    implements RouteAware {
  int _selectedIndex = 0;
  final PostService _postService = PostService();
  final UserService _userService = UserService();
  final VibeTopicService _vibeTopicService = VibeTopicService();
  final SpotifyService _spotifyService = SpotifyService();
  final ITunesSearchService _itunesService = ITunesSearchService();
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final ScrollController _scrollController = ScrollController();
  final ValueNotifier<double> _bellOpacity = ValueNotifier<double>(1.0);

  // ホーム画面専用の音楽再生サービス（全てのPostCardで共有）
  final AudioPlayerService _homeAudioService = AudioPlayerService();

  // 各PostCardのGlobalKey（可視性チェック・flipToFront用）
  final Map<String, GlobalKey<PostCardState>> _postCardKeys = {};

  // チュートリアル誘導用のキー
  final GlobalKey _tutorialAddButtonKey = GlobalKey();
  final GlobalKey _tutorialVibeIconKey = GlobalKey();

  // カメラオーバーレイに渡すトラック（takingPhoto ステップで使用）
  TrackModel? _tutorialTrack;

  int _tutorialActiveIndex = 0;

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

  // 投稿ごとの音楽プレビューURL（postId → URL）
  final Map<String, String?> _previewUrlCache = {};

  // 現在のユーザーのアイコンURL（楽観的UI用）
  String? _currentUserIconUrl;

  // 現在のユーザーが今日投稿済みかどうか（裏面表示制御用）
  bool _hasPostedToday = false;

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
    // initialUserModel があればFirestoreアクセス不要
    if (widget.initialUserModel != null) {
      _currentUserIconUrl = widget.initialUserModel!.profileImageUrl;
    } else {
      _loadCurrentUserIconUrl();
    }
    _updateLastActive();
    _processPendingFollowNotification();
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
  }

  @override
  void didPush() {}

  @override
  void didPushNext() {}

  @override
  void didPop() {}

  /// PostUIState を投稿リストから初期化する（initialPosts 使用時に呼ぶ）
  Future<void> _initializePostUIState(List<PostModel> posts, {UserModel? userModel}) async {
    final currentUser = _auth.currentUser;
    if (currentUser == null) return;
    List<String> savedPostIds = userModel?.savedPosts ?? [];
    if (userModel == null) {
      try {
        final fetched = await _userService.getUser(currentUser.uid);
        savedPostIds = fetched?.savedPosts ?? [];
      } catch (_) {}
    }
    if (mounted) {
      context.read<PostUIState>().resetAndInitialize(
        posts: posts,
        currentUserId: currentUser.uid,
        savedPostIds: savedPostIds.toSet(),
      );
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

  /// 現在のユーザーのアイコンURLを取得
  Future<void> _loadCurrentUserIconUrl() async {
    final userInfo = await CurrentUserHelper.load();
    if (mounted) {
      setState(() {
        _currentUserIconUrl = userInfo.iconUrl;
      });
    }
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
  Future<void> _updateLastActive() async {
    final uid = _auth.currentUser?.uid;
    if (uid != null) await _userService.updateLastActive(uid);
  }

  /// プルダウン更新（投稿リスト＋ユーザー情報＋Vibeを再取得）
  /// setState を1回にまとめてカクつきを防止
  Future<void> _onRefresh() async {
    final refreshStart = DateTime.now();
    // Vibe Future をセットするだけ（setState なし）
    _vibeDataFuture = _loadVibeData();

    // 投稿データとユーザー情報を並列取得
    final results = await Future.wait([
      _fetchPostsData(),
      CurrentUserHelper.load(),
    ]);

    final postsResult = results[0] as ({List<PostModel> posts, bool hasPostedToday, List<String> savedPostIds});
    final userInfo = results[1] as ({String username, String? iconUrl, String? university});

    // 最低1秒間はリフレッシュインジケーターを表示
    final elapsed = DateTime.now().difference(refreshStart);
    if (elapsed < const Duration(seconds: 1)) {
      await Future.delayed(Duration(seconds: 1) - elapsed);
    }

    if (mounted) {
      setState(() {
        _cachedPosts = postsResult.posts;
        _hasPostedToday = postsResult.hasPostedToday;
        _currentUserIconUrl = userInfo.iconUrl;
        _previewUrlCache.clear(); // リフレッシュ時はキャッシュをリセット
      });
      context.read<PostUIState>().resetAndInitialize(
        posts: postsResult.posts,
        currentUserId: _auth.currentUser?.uid ?? '',
        savedPostIds: postsResult.savedPostIds.toSet(),
      );
      _prefetchBacksideImages(postsResult.posts);
      _prefetchPreviewUrls(postsResult.posts);
    }
  }

/// 投稿データをFirestoreから取得して返す（setState なし・_loadPosts/_onRefresh 共用）
  Future<({List<PostModel> posts, bool hasPostedToday, List<String> savedPostIds})> _fetchPostsData() async {
    try {
      final currentUser = _auth.currentUser;

      // 今日投稿済みかチェック
      bool hasPostedToday = false;
      if (currentUser != null) {
        hasPostedToday = await _postService.hasUserPostedToday(currentUser.uid);
      }

      // フォロー中のユーザーIDと保存済み投稿IDを取得
      List<String> followingIds = [];
      List<String> savedPostIds = [];
      if (currentUser != null) {
        try {
          final userModel = await _userService.getUser(currentUser.uid);
          followingIds = userModel?.following ?? [];
          savedPostIds = userModel?.savedPosts ?? [];
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

      return (posts: updatedPosts, hasPostedToday: hasPostedToday, savedPostIds: savedPostIds);
    } catch (e) {
      print('❌ 投稿読み込みエラー: $e');
      return (posts: <PostModel>[], hasPostedToday: false, savedPostIds: <String>[]);
    }
  }

  /// 投稿リストを読み込み（Firestoreから取得）
  Future<void> _loadPosts() async {
    print('📥 _loadPosts()開始');
    final result = await _fetchPostsData();
    if (mounted) {
      print('✅ 投稿読み込み完了: ${result.posts.length}件の投稿をセット');
      setState(() {
        _cachedPosts = result.posts;
        _hasPostedToday = result.hasPostedToday;
      });
      print('🔄 setState()完了');
      context.read<PostUIState>().resetAndInitialize(
        posts: result.posts,
        currentUserId: _auth.currentUser?.uid ?? '',
        savedPostIds: result.savedPostIds.toSet(),
      );
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
    routeObserver.unsubscribe(this);
    _scrollController.dispose();
    _bellOpacity.dispose();
    super.dispose();
  }

  /// スクロール時に各カードの可視性を確認し、
  /// 最も多く見えているカード（50%超）以外の裏面カードを表面に戻す
  void _checkPlayingCardVisibility() {
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

  /// VibePlaylistScreen への実遷移（チュートリアル状態の前進も含む）
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

  /// 「楽曲をVibeに追加」ボタンタップで投稿フロー（楽曲選択）へ遷移
  Future<void> _navigateToPostFlow() async {
    _homeAudioService.stop();

    // チュートリアル中は Frame 628 が前面に出ているのでこのパスは通常通らない
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

  /// チュートリアル Frame 628 でカルーセルのアクティブ曲が変わったときに呼ばれる
  Future<void> _onTutorialAlbumChanged(int index) async {
    _tutorialActiveIndex = index;
    final items = TutorialAlbumCarousel.defaultItems;
    if (index >= items.length) return;
    final item = items[index];
    final cacheKey = '${item.title}__${item.artist}';

    // MusicConnectionScreen で既にプリフェッチ済みのはずだが、未完の場合は待機
    await TutorialPrefetchService.instance.ensureReady(cacheKey, item);

    // 非同期中にインデックスが変わっていたら再生しない
    if (!mounted || _tutorialActiveIndex != index) return;

    final previewUrl = TutorialPrefetchService.instance.previewCache[cacheKey];
    if (previewUrl != null && previewUrl.isNotEmpty) {
      _homeAudioService.playPreview(previewUrl);
    }
  }

  /// チュートリアル Frame 628 で曲を確定したときに呼ばれる
  Future<void> _onTutorialSongConfirmed(TutorialAlbumItem item) async {
    _homeAudioService.stop();
    final cacheKey = '${item.title}__${item.artist}';

    await TutorialPrefetchService.instance.ensureReady(cacheKey, item);

    if (!mounted) return;

    final cache = TutorialPrefetchService.instance;
    // Spotify のアルバムアートURL（取得失敗時はローカル assetPath をフォールバック）
    final albumArtUrl =
        cache.artCache[cacheKey]?.isNotEmpty == true
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

  Future<void> _onItemTapped(int index) async {
    if (index == 2) {
      // 楽曲選択画面へ遷移（投稿フローの起点）
      _homeAudioService.stop();
      final targetIndex = await Navigator.push<int>(
        context,
        PageRouteBuilder(
          pageBuilder: (_, __, ___) => const MusicSelectionScreen(),
          transitionDuration: Duration.zero,
          reverseTransitionDuration: Duration.zero,
        ),
      );
      if (targetIndex != null && mounted) {
        setState(() => _selectedIndex = targetIndex);
      }
      return;
    }

    // ホームタブを既に表示中にもう一度タップ
    // → 先頭へスムーズに戻ってからリフレッシュを実行
    if (index == 0 && _selectedIndex == 0) {
      if (!_scrollController.hasClients) return;
      // 現在位置から直接リフレッシュトリガー位置まで一気にスクロール
      final distance = _scrollController.offset - (-100);
      final duration = (distance.abs() / 2000 * 1000).clamp(300, 600).toInt();
      await _scrollController.animateTo(
        -100,
        duration: Duration(milliseconds: duration),
        curve: Curves.easeOut,
      );
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
    final topPadding = MediaQuery.of(context).padding.top;
    final headerHeight = 48.0 + topPadding;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: Stack(
          children: [
            // タブコンテンツ
            IndexedStack(
              index: _selectedIndex <= 1 ? _selectedIndex : (_selectedIndex == 3 ? 2 : 0),
              children: [
                // index 0: ホーム
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
                      // 透明ヘッダー（ピン留め）
                      SliverPersistentHeader(
                        pinned: true,
                        delegate: _HomeHeaderDelegate(
                          height: headerHeight,
                          topPadding: topPadding,
                          bellOpacity: _bellOpacity,
                          bellButton: NotificationBadge(
                            child: IconButton(
                              icon: const Icon(Icons.notifications_outlined, color: Colors.white),
                              onPressed: () {
                                _homeAudioService.stop();
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(builder: (_) => const NotificationListScreen()),
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
                        _buildTimelineSliver(postUIState),
                        const SliverToBoxAdapter(child: SizedBox(height: 80)),
                      ],
                    ],
                  ),
                ),
                // index 1: 検索
                const SearchScreen(),
                // index 2: プロフィール
                const ProfileScreen(),
              ],
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

            // チュートリアル Frame 628 オーバーレイ（最前面）
            ListenableBuilder(
              listenable: TutorialController.instance,
              builder: (context, _) {
                final step = TutorialController.instance.step;
                if (_selectedIndex != 0) return const SizedBox.shrink();

                if (step == TutorialStep.showHomeHint) {
                  // 背景のホーム画面操作を完全にブロックしつつ Frame 628 を表示
                  return Positioned.fill(
                    child: TutorialFrame628Overlay(
                      onConfirm: _onTutorialSongConfirmed,
                      onActiveChanged: _onTutorialAlbumChanged,
                    ),
                  );
                }

                if (step == TutorialStep.takingPhoto && _tutorialTrack != null) {
                  // カメラオーバーレイ: Component 126 がホーム画面の上に乗る
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
      final topic = await _vibeTopicService.getTodaysTopic();
      if (topic == null) {
        return {'topic': null, 'ranking': []};
      }

      final ranking = await _postService.calculateVibeRanking(
        topic.topicId,
        DateTime.now(),
        limit: 10,
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
      final topic = await _vibeTopicService.getTodaysTopic();
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
  Widget _buildTimelineSliver(PostUIState postUIState) {
    final posts = _cachedPosts!;
    final currentUserId = _auth.currentUser?.uid ?? 'test_user_temp';

    return SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: 15),
      sliver: SliverList(
        delegate: SliverChildBuilderDelegate(
          (context, index) {
            final post = posts[index];
            final displayPost = postUIState.getDisplayPost(
              post,
              currentUserId: currentUserId,
              currentUserIconUrl: _currentUserIconUrl,
            );

            _postCardKeys.putIfAbsent(post.postId, () => GlobalKey<PostCardState>());
            final cardKey = _postCardKeys[post.postId]!;

            return Padding(
              padding: const EdgeInsets.only(bottom: 24),
              child: RepaintBoundary(
                child: PostCard(
                  key: cardKey,
                  post: displayPost,
                  currentUserId: currentUserId,
                  currentUserIconUrl: _currentUserIconUrl,
                  audioService: _homeAudioService,
                  externalPreviewUrl: _previewUrlCache[post.postId],
                  onLike: () => _handleLike(post),
                  onComment: () => _handleComment(post),
                  onAdd: () => _handleAdd(post),
                  onDelete: post.userId == currentUserId ? () => _handleDelete(post) : null,
                  isSaved: postUIState.isSaved(post.postId),
                  backSideEnabled: _hasPostedToday || _revealedPostIds.contains(post.postId),
                  onFlipToBack: () => _markPostRevealed(post.postId),
                  onPlayStarted: () {
                    _playingPostId = post.postId;
                    _preloadNeighborAudio(index);
                  },
                  onShare: () => showCardShareSheet(
                    context,
                    post: post,
                    currentUserId: currentUserId,
                    currentUserIconUrl: _currentUserIconUrl,
                    isSaved: postUIState.isSaved(post.postId),
                  ),
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
    final currentUser = _auth.currentUser;
    if (currentUser == null) return;

    final postUIState = context.read<PostUIState>();
    final wasSaved = postUIState.isSaved(post.postId);

    // 楽観的UI更新（notifyListeners → build再実行）
    postUIState.toggleSave(post.postId);

    try {
      await _userService.toggleSavePost(
        userId: currentUser.uid,
        postId: post.postId,
      );
      _showMessage(wasSaved ? '投稿の保存を解除しました' : '投稿を保存しました');
    } catch (e) {
      print('投稿の保存に失敗: $e');
      if (mounted) postUIState.revertSaveToggle(post.postId);
      _showMessage('投稿の保存に失敗しました');
    }
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

/// ホーム画面の透明ピン留めヘッダー用デリゲート
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
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
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

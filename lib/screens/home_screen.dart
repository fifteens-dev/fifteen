import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../constants/app_colors.dart';
import '../models/post_model.dart';
import '../models/vibe_ranking_item.dart';
import '../widgets/post_card.dart';
import '../widgets/notification_badge.dart';
import '../services/post_service.dart';
import '../services/spotify_service.dart';
import '../services/audio_player_service.dart';
import '../services/user_service.dart';
import '../services/vibe_topic_service.dart';
import '../utils/current_user_helper.dart';
import 'comment_screen.dart';
import 'search_screen.dart';
import 'profile_screen.dart';
import 'music_selection_screen.dart';
import 'notification_list_screen.dart';
import 'vibe_track_posts_screen.dart';
import 'home/vibe_bar_section.dart';
import 'home/home_bottom_nav.dart';

/// ホーム画面（タイムライン）
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with AutomaticKeepAliveClientMixin {
  int _selectedIndex = 0;
  final PostService _postService = PostService();
  final UserService _userService = UserService();
  final VibeTopicService _vibeTopicService = VibeTopicService();
  final SpotifyService _spotifyService = SpotifyService();
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final ScrollController _scrollController = ScrollController();

  // ホーム画面専用の音楽再生サービス（全てのPostCardで共有）
  final AudioPlayerService _homeAudioService = AudioPlayerService();

  // 各PostCardのGlobalKey（可視性チェック用）
  final Map<String, GlobalKey> _postCardKeys = {};

  // 現在再生中の投稿ID
  String? _playingPostId;

  @override
  bool get wantKeepAlive => true;

  // 投稿ごとのコメント数を保持（楽観的UI更新用）
  final Map<String, int> _commentCounts = {};

  // 投稿ごとのいいね数を保持（楽観的UI更新用）
  final Map<String, int> _likeCounts = {};

  // ユーザーがいいねした投稿IDのセット（楽観的UI更新用）
  final Set<String> _likedPostIds = {};

  // ユーザーが保存した投稿IDのセット（楽観的UI更新用）
  final Set<String> _savedPostIds = {};

  // 投稿リストをキャッシュ（再構築を避けるため）
  List<PostModel>? _cachedPosts;

  // 現在のユーザーのアイコンURL（楽観的UI用）
  String? _currentUserIconUrl;

  // 現在のユーザーが今日投稿済みかどうか（裏面表示制御用）
  bool _hasPostedToday = false;

  @override
  void initState() {
    super.initState();
    print('🏠 ホーム画面: initState()が呼ばれました');
    _loadPosts();
    _loadCurrentUserIconUrl();
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

  /// 投稿リストを読み込み（Firestoreから取得）
  Future<void> _loadPosts() async {
    print('📥 _loadPosts()開始');
    try {
      final currentUser = _auth.currentUser;
      print('👤 現在のユーザー: ${currentUser?.uid ?? "未認証"}');

      // 今日投稿済みかチェック（裏面表示制御用）
      if (currentUser != null) {
        _hasPostedToday = await _postService.hasUserPostedToday(currentUser.uid);
      }

      List<PostModel> firestorePosts = [];

      // Firestoreから投稿を取得（認証の有無に関わらず試みる）
      try {
        firestorePosts = await _postService.getPosts(limit: 50);
        print('📥 Firestoreから取得した投稿数: ${firestorePosts.length}');
      } catch (e) {
        print('⚠️ Firestore取得エラー（権限エラーの可能性）: $e');
        // エラーの場合は空配列のまま
      }

      // Firestoreの投稿のみを使用（テストデータは除外）
      final postsToUse = firestorePosts;

      print('📊 表示する投稿数: ${postsToUse.length} (Firestore)');

      // 各投稿の楽曲名でSpotify検索し、アルバムアートワークを更新（必要な場合のみ、並列実行）
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
            final searchQuery =
                '${post.track.trackName} ${post.track.artistName}';
            final tracks =
                await _spotifyService.searchTracks(searchQuery, limit: 1);
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

        final results = await Future.wait(futures);
        for (final entry in results) {
          updatedPosts[entry.key] = entry.value;
        }
      }

      if (mounted) {
        print('✅ 投稿読み込み完了: ${updatedPosts.length}件の投稿をセット');
        setState(() {
          _cachedPosts = updatedPosts;
        });
        print('🔄 setState()完了');
      } else {
        print('⚠️ mountedがfalseのため、setStateをスキップ');
      }
    } catch (e) {
      print('❌ 投稿読み込みエラー: $e');
      if (mounted) {
        setState(() {
          _cachedPosts = [];
        });
      }
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _bellOpacity.dispose();
    super.dispose();
  }

  /// スクロール時に再生中のカードが完全に画面外に出たら音楽を停止
  void _checkPlayingCardVisibility() {
    if (!_homeAudioService.isPlaying && !_homeAudioService.isPaused) return;
    if (_playingPostId == null) {
      // playingPostIdが不明だが再生中 → 安全のため停止
      _homeAudioService.stop();
      return;
    }

    final key = _postCardKeys[_playingPostId];
    if (key == null) {
      _homeAudioService.stop();
      _playingPostId = null;
      return;
    }

    final currentContext = key.currentContext;
    if (currentContext == null) {
      // ウィジェットがSliverListに破棄された → 画面外
      _homeAudioService.stop();
      _playingPostId = null;
      return;
    }

    final renderBox = currentContext.findRenderObject() as RenderBox?;
    if (renderBox == null || !renderBox.attached) {
      _homeAudioService.stop();
      _playingPostId = null;
      return;
    }

    final position = renderBox.localToGlobal(Offset.zero);
    final size = renderBox.size;
    final screenHeight = MediaQuery.of(context).size.height;

    // カードが完全に画面外に出たら停止
    if (position.dy + size.height <= 0 || position.dy >= screenHeight) {
      _homeAudioService.stop();
      _playingPostId = null;
    }
  }

  // ボトムナビゲーションのタップ処理
  /// Vibeの「投稿する」ボタンから楽曲選択画面へ遷移（Vibe事前選択済み）
  void _navigateToVibePost() {
    _homeAudioService.stop();
    Navigator.push(
      context,
      PageRouteBuilder(
        pageBuilder: (_, __, ___) => const MusicSelectionScreen(
          initialCategoryType: 'vibe',
        ),
        transitionDuration: Duration.zero,
        reverseTransitionDuration: Duration.zero,
      ),
    );
  }

  void _onItemTapped(int index) {
    if (index == 2) {
      // 楽曲選択画面へ遷移（別画面として開く）
      _homeAudioService.stop();
      Navigator.push(
        context,
        PageRouteBuilder(
          pageBuilder: (_, __, ___) => const MusicSelectionScreen(),
          transitionDuration: Duration.zero,
          reverseTransitionDuration: Duration.zero,
        ),
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

  // ベルアイコンの透明度（スクロールに応じてフェードアウト）
  final ValueNotifier<double> _bellOpacity = ValueNotifier<double>(1.0);

  /// スクロール量に応じてベルアイコンの透明度を更新
  void _updateBellOpacity() {
    if (!_scrollController.hasClients) return;
    final offset = _scrollController.offset;
    // 0〜80pxのスクロールで1.0→0.0にフェードアウト
    _bellOpacity.value = (1.0 - (offset / 80.0)).clamp(0.0, 1.0);
  }

  @override
  Widget build(BuildContext context) {
    super.build(context); // AutomaticKeepAliveClientMixinのために必要
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
                    _checkPlayingCardVisibility();
                    _updateBellOpacity();
                    return false;
                  },
                  child: CustomScrollView(
                    controller: _scrollController,
                    slivers: [
                    // ヘッダー分のスペース（固定ヘッダーの下にコンテンツが隠れないように）
                    SliverToBoxAdapter(
                      child: SizedBox(height: headerHeight),
                    ),
                    SliverToBoxAdapter(
                      child: VibeBarSection(
                        vibeDataFuture: _loadVibeData(),
                        onRankingItemTap: _handleRankingItemTap,
                        onPostTap: _navigateToVibePost,
                      ),
                    ),
                    const SliverToBoxAdapter(
                      child: SizedBox(height: 9),
                    ),
                    _buildTimelineSliver(),
                    const SliverToBoxAdapter(
                      child: SizedBox(height: 80),
                    ),
                    ],
                  ),
                ),
                // index 1: 検索
                const SearchScreen(),
                // index 2: プロフィール
                const ProfileScreen(),
              ],
            ),

            // 固定ヘッダー（15sロゴ + ベルアイコン）
            if (_selectedIndex == 0)
              Positioned(
                left: 0,
                right: 0,
                top: 0,
                child: Container(
                  height: headerHeight,
                  color: AppColors.background,
                  padding: EdgeInsets.only(left: 16, right: 16, top: topPadding),
                  child: Stack(
                    children: [
                      // 15sロゴ（中央固定）
                      const Center(
                        child: Text(
                          '15s',
                          style: TextStyle(
                            fontSize: 30,
                            fontWeight: FontWeight.w600,
                            color: Colors.white,
                          ),
                        ),
                      ),
                      // 通知アイコン（スクロールでフェードアウト）
                      Positioned(
                        right: 0,
                        top: 0,
                        bottom: 0,
                        child: ValueListenableBuilder<double>(
                          valueListenable: _bellOpacity,
                          builder: (context, opacity, child) {
                            return Opacity(
                              opacity: opacity,
                              child: IgnorePointer(
                                ignoring: opacity < 0.1,
                                child: child,
                              ),
                            );
                          },
                          child: NotificationBadge(
                            child: IconButton(
                              icon: const Icon(Icons.notifications_outlined, color: Colors.white),
                              onPressed: () {
                                _homeAudioService.stop();
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(builder: (context) => const NotificationListScreen()),
                                );
                              },
                            ),
                          ),
                        ),
                      ),
                    ],
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

      // 投稿一覧画面に遷移
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => VibeTrackPostsScreen(
            track: item.track,
            posts: matchingPosts,
            currentUserId: _auth.currentUser?.uid ?? 'test_user_temp',
          ),
        ),
      );
    } catch (e) {
      print('Error handling ranking item tap: $e');
      _showMessage('投稿の読み込みに失敗しました');
    }
  }

  /// タイムライン（投稿カードリスト）- Sliver版
  ///
  /// キャッシュされた投稿リストを使用してスクロール位置を確実に保持します。
  Widget _buildTimelineSliver() {
    print('🎨 _buildTimelineSliver()呼び出し: _cachedPosts = ${_cachedPosts?.length ?? "null"}');

    // キャッシュされた投稿リストがない場合はローディング表示
    if (_cachedPosts == null) {
      print('⏳ ローディング表示中...');
      return const SliverToBoxAdapter(
        child: Center(
          child: Padding(
            padding: EdgeInsets.all(32),
            child: CircularProgressIndicator(color: Colors.white),
          ),
        ),
      );
    }

    final posts = _cachedPosts!;
    print('📋 ${posts.length}件の投稿を表示します');
    final currentUserId = _auth.currentUser?.uid ?? 'test_user_temp';

    return SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: 15),
      sliver: SliverList(
        delegate: SliverChildBuilderDelegate(
          (context, index) {
            final post = posts[index];

            // コメント数といいね数のオーバーライドを適用
            var displayPost = post;

            // コメント数のオーバーライド
            if (_commentCounts.containsKey(post.postId)) {
              displayPost = displayPost.copyWith(
                  commentCount: _commentCounts[post.postId]);
            }

            // いいね数のオーバーライド
            if (_likeCounts.containsKey(post.postId)) {
              displayPost =
                  displayPost.copyWith(likeCount: _likeCounts[post.postId]);
            }

            // いいね状態のオーバーライド
            if (_likedPostIds.contains(post.postId)) {
              // ユーザーがいいねしている場合、likedUserIdsにユーザーIDを追加
              final updatedLikedUserIds =
                  List<String>.from(displayPost.likedUserIds);
              if (!updatedLikedUserIds.contains(currentUserId)) {
                updatedLikedUserIds.add(currentUserId);
                displayPost =
                    displayPost.copyWith(likedUserIds: updatedLikedUserIds);
              }
            } else if (_likeCounts.containsKey(post.postId)) {
              // いいね解除した場合、likedUserIdsからユーザーIDを削除
              final updatedLikedUserIds =
                  List<String>.from(displayPost.likedUserIds);
              updatedLikedUserIds.remove(currentUserId);
              displayPost =
                  displayPost.copyWith(likedUserIds: updatedLikedUserIds);
            }

            // PostCardにGlobalKeyを割り当て（可視性チェック用）
            _postCardKeys.putIfAbsent(post.postId, () => GlobalKey());
            final cardKey = _postCardKeys[post.postId]!;

            return Padding(
              key: cardKey,
              padding: const EdgeInsets.only(bottom: 16),
              child: PostCard(
                key: ValueKey(post.postId), // 投稿IDをkeyにして状態を保持
                post: displayPost,
                currentUserId: currentUserId,
                currentUserIconUrl: _currentUserIconUrl,
                audioService: _homeAudioService, // ホーム画面専用の音楽再生サービスを渡す
                onLike: () => _handleLike(post),
                onComment: () => _handleComment(post),
                onAdd: () => _handleAdd(post),
                isSaved: _savedPostIds.contains(post.postId),
                backSideEnabled: _hasPostedToday,
                onPlayStarted: () {
                  _playingPostId = post.postId;
                },
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

    // 現在のいいね状態を取得
    final currentLikeCount = _likeCounts[post.postId] ?? post.likeCount;
    final isCurrentlyLiked =
        _likedPostIds.contains(post.postId) || post.isLikedBy(userId);

    // 楽観的UI更新: 先に状態を更新
    setState(() {
      if (isCurrentlyLiked) {
        // いいね解除
        _likedPostIds.remove(post.postId);
        _likeCounts[post.postId] = currentLikeCount - 1;
      } else {
        // いいね追加
        _likedPostIds.add(post.postId);
        _likeCounts[post.postId] = currentLikeCount + 1;
      }
    });

    try {
      await _postService.toggleLike(
        postId: post.postId,
        userId: userId,
      );
    } catch (e) {
      // エラーが発生したら状態を元に戻す
      if (mounted) {
        setState(() {
          if (isCurrentlyLiked) {
            _likedPostIds.add(post.postId);
            _likeCounts[post.postId] = currentLikeCount;
          } else {
            _likedPostIds.remove(post.postId);
            _likeCounts[post.postId] = currentLikeCount;
          }
        });
      }

      _showMessage('いいねに失敗しました');
    }
  }

  /// コメント数を更新（コメント画面から呼ばれる）
  void _updateCommentCount(String postId, int count) {
    if (mounted) {
      setState(() {
        _commentCounts[postId] = count;
      });
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

    final userId = currentUser.uid;

    try {
      final isSaved = _savedPostIds.contains(post.postId);

      // 楽観的UI更新
      setState(() {
        if (isSaved) {
          _savedPostIds.remove(post.postId);
        } else {
          _savedPostIds.add(post.postId);
        }
      });

      await _userService.toggleSavePost(
        userId: userId,
        postId: post.postId,
      );

      _showMessage(isSaved ? '投稿の保存を解除しました' : '投稿を保存しました');
    } catch (e) {
      print('投稿の保存に失敗: $e');

      // エラー時は状態を元に戻す
      setState(() {
        if (_savedPostIds.contains(post.postId)) {
          _savedPostIds.remove(post.postId);
        } else {
          _savedPostIds.add(post.postId);
        }
      });

      _showMessage('投稿の保存に失敗しました');
    }
  }

  /// メッセージを表示
  void _showMessage(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

}

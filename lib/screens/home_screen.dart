import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../constants/app_colors.dart';
import '../models/post_model.dart';
import '../models/track_model.dart';
import '../models/vibe_topic_model.dart';
import '../models/vibe_ranking_item.dart';
import '../widgets/post_card.dart';
import '../widgets/notification_badge.dart';
import '../services/post_service.dart';
import '../services/spotify_service.dart';
import '../services/audio_player_service.dart';
import '../services/user_service.dart';
import '../services/vibe_topic_service.dart';
import '../utils/test_data.dart';
import 'comment_screen.dart';
import 'search_screen.dart';
import 'profile_screen.dart';
import 'activity_screen.dart';
import 'notification_list_screen.dart';
import 'vibe_topic_voting_screen.dart';

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

  @override
  void initState() {
    super.initState();
    print('🏠 ホーム画面: initState()が呼ばれました');
    _loadPosts();
    _loadLocalLikeStates();
    _loadLocalSaveStates();
  }

  /// 投稿リストを読み込み（Firestoreから取得）
  Future<void> _loadPosts() async {
    print('📥 _loadPosts()開始');
    try {
      final currentUser = _auth.currentUser;
      print('👤 現在のユーザー: ${currentUser?.uid ?? "未認証"}');
      List<PostModel> firestorePosts = [];

      // Firestoreから投稿を取得（認証の有無に関わらず試みる）
      try {
        firestorePosts = await _postService.getPosts(limit: 50);
        print('📥 Firestoreから取得した投稿数: ${firestorePosts.length}');
      } catch (e) {
        print('⚠️ Firestore取得エラー（権限エラーの可能性）: $e');
        // エラーの場合は空配列のまま（TestDataのみ表示）
      }

      // Firestoreの投稿のみを使用（テストデータは除外）
      final postsToUse = firestorePosts;

      print('📊 表示する投稿数: ${postsToUse.length} (Firestore)');

      // 各投稿の楽曲名でSpotify検索し、アルバムアートワークを更新（必要な場合のみ）
      final updatedPosts = <PostModel>[];

      for (final post in postsToUse) {
        // アルバムアートワークが既にある場合はSpotify検索をスキップ
        if (post.track.albumImageUrl.isNotEmpty) {
          updatedPosts.add(post);
          continue;
        }

        // アルバムアートがない場合はSpotify検索を試みる
        try {
          // 楽曲名とアーティスト名で検索
          final searchQuery =
              '${post.track.trackName} ${post.track.artistName}';
          final tracks =
              await _spotifyService.searchTracks(searchQuery, limit: 1);

          if (tracks.isNotEmpty) {
            // 検索結果の最初のトラックのアルバムアートワークを使用
            final spotifyTrack = tracks.first;
            final updatedTrack = post.track.copyWith(
              albumImageUrl: spotifyTrack.albumImageUrl,
            );
            final updatedPost = post.copyWith(track: updatedTrack);
            updatedPosts.add(updatedPost);
            print('🎵 Spotify検索成功: ${post.track.trackName}');
          } else {
            // 検索結果がない場合は元の投稿をそのまま使用
            updatedPosts.add(post);
            print('⚠️ Spotify検索結果なし: ${post.track.trackName}');
          }
        } catch (e) {
          print('⚠️ Spotifyアルバムアートワーク取得エラー: $e');
          // エラーの場合は元の投稿をそのまま使用
          updatedPosts.add(post);
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
      print('📦 エラー発生のため、TestDataのみを表示します');
      // エラー時はテストデータを使用
      if (mounted) {
        setState(() {
          _cachedPosts = TestData.generateTestPosts();
        });
      }
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  /// ローカルストレージからいいね状態を読み込み
  Future<void> _loadLocalLikeStates() async {
    final posts = TestData.generateTestPosts();
    final userId = _auth.currentUser?.uid ?? 'test_user_temp';

    for (final post in posts) {
      if (post.postId.startsWith('test_post_')) {
        // ローカルストレージからいいね状態を読み込み
        final likeState = await TestData.getLikeState(post.postId);
        final likeCount = likeState['likeCount'] as int;
        final likedUserIds = List<String>.from(likeState['likedUserIds']);

        if (likeCount > 0) {
          _likeCounts[post.postId] = likeCount;
        }

        if (likedUserIds.contains(userId)) {
          _likedPostIds.add(post.postId);
        }
      }
    }

    if (mounted) {
      setState(() {});
    }
  }

  /// ローカルストレージから保存状態を読み込み
  Future<void> _loadLocalSaveStates() async {
    final userId = _auth.currentUser?.uid ?? 'test_user_temp';

    // TestDataから保存済み投稿IDリストを取得
    final savedPostIds = await TestData.getSavedPosts(userId);

    if (mounted) {
      setState(() {
        _savedPostIds.addAll(savedPostIds);
      });
    }
  }

  // ボトムナビゲーションのタップ処理
  void _onItemTapped(int index) {
    setState(() {
      _selectedIndex = index;
    });

    switch (index) {
      case 0:
        // ホーム（現在の画面）
        break;
      case 1:
        // 検索画面へ遷移
        // ホーム画面の音楽を停止
        _homeAudioService.stop();
        Navigator.push(
          context,
          MaterialPageRoute(builder: (context) => const SearchScreen()),
        );
        break;
      case 2:
        // 楽曲選択画面へ遷移
        // ホーム画面の音楽を停止
        _homeAudioService.stop();
        Navigator.pushNamed(context, '/music-selection');
        break;
      case 3:
        // プロフィール画面へ遷移
        // ホーム画面の音楽を停止
        _homeAudioService.stop();
        Navigator.push(
          context,
          MaterialPageRoute(builder: (context) => const ProfileScreen()),
        );
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context); // AutomaticKeepAliveClientMixinのために必要
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            // ヘッダー
            _buildHeader(),

            // メインコンテンツ（スクロール可能）
            Expanded(
              child: CustomScrollView(
                controller: _scrollController,
                slivers: [
                  // Vibeバー
                  SliverToBoxAdapter(
                    child: _buildVibeBar(),
                  ),

                  const SliverToBoxAdapter(
                    child: SizedBox(height: 16),
                  ),

                  // 投稿カード束（タイムライン）
                  _buildTimelineSliver(),
                ],
              ),
            ),
          ],
        ),
      ),
      // ボトムナビゲーション
      bottomNavigationBar: _buildBottomNavigation(),
    );
  }

  /// ヘッダー（15sロゴ + 通知アイコン）
  Widget _buildHeader() {
    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          const Spacer(),
          // 15sロゴ（中央）
          const Text(
            '15s',
            style: TextStyle(
              fontSize: 30,
              fontWeight: FontWeight.w600,
              color: Colors.white,
            ),
          ),
          const Spacer(),
          // 通知アイコン（バッジ付き）
          NotificationBadge(
            child: IconButton(
              icon: const Icon(Icons.notifications_outlined, color: Colors.white),
              onPressed: () {
                // ホーム画面の音楽を停止
                _homeAudioService.stop();
                // 通知一覧画面へ遷移
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const NotificationListScreen()),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  /// Vibeバー（ランキング表示）
  Widget _buildVibeBar() {
    return FutureBuilder<Map<String, dynamic>>(
      future: _loadVibeData(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return _buildVibeBarSkeleton();
        }

        if (!snapshot.hasData ||
            snapshot.data!['topic'] == null) {
          return _buildVibeBarEmpty();
        }

        final topic = snapshot.data!['topic'] as VibeTopicModel;
        final ranking = snapshot.data!['ranking'] as List<VibeRankingItem>;

        return Container(
          height: 190,
          color: AppColors.background,
          child: Column(
            children: [
              // ヘッダー（お題タイトル + 投票ボタン）
              _buildVibeBarHeader(topic),

              // ランキング（横スクロール）
              Expanded(
                child: ranking.isEmpty
                    ? _buildNoRankingMessage()
                    : ListView.builder(
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        itemCount: ranking.length,
                        itemBuilder: (context, index) {
                          return _buildRankingItem(ranking[index], index + 1);
                        },
                      ),
              ),
            ],
          ),
        );
      },
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

  /// Vibeバーのヘッダー
  Widget _buildVibeBarHeader(VibeTopicModel topic) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          // Vibeアイコン
          Image.asset(
            'assets/icons/Vibe.png',
            width: 40,
            height: 40,
            errorBuilder: (context, error, stackTrace) {
              return Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: Colors.purple,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.music_note, color: Colors.white),
              );
            },
          ),
          const SizedBox(width: 12),
          // お題タイトル
          Expanded(
            child: Text(
              'Vibe【${topic.title}】',
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: Colors.white,
              ),
            ),
          ),
          // 投票ボタン
          GestureDetector(
            onTap: () => _navigateToVoting(),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: const Color(0xFF5D8FFF),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Text(
                '明日のVibeに投票',
                style: TextStyle(
                  fontSize: 10,
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// ランキングアイテム
  Widget _buildRankingItem(VibeRankingItem item, int rank) {
    return Container(
      width: 80,
      margin: const EdgeInsets.symmetric(horizontal: 4),
      child: Column(
        children: [
          // ランク番号（円形バッジ）
          Container(
            width: 20,
            height: 20,
            decoration: BoxDecoration(
              color: _getRankColor(rank),
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(
                '$rank',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
            ),
          ),
          const SizedBox(height: 4),

          // アルバムアートワーク
          Container(
            width: 70,
            height: 70,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(4),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: Image.network(
                item.track.albumImageUrl,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) {
                  return Container(
                    color: Colors.grey[800],
                    child: const Icon(Icons.album, color: Colors.white54),
                  );
                },
              ),
            ),
          ),
          const SizedBox(height: 4),

          // 楽曲名
          Text(
            item.track.trackName,
            style: const TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.w600,
              color: Colors.white,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
          ),
          // アーティスト名
          Text(
            item.track.artistName,
            style: TextStyle(
              fontSize: 7,
              color: Colors.white.withOpacity(0.7),
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
          ),

          // 投稿数
          Text(
            '${item.postCount}投稿',
            style: const TextStyle(
              fontSize: 7,
              color: Color(0xFF5D8FFF),
            ),
          ),
        ],
      ),
    );
  }

  /// ランク別の色を取得
  Color _getRankColor(int rank) {
    switch (rank) {
      case 1:
        return const Color(0xFFFFD700); // ゴールド
      case 2:
        return const Color(0xFFC0C0C0); // シルバー
      case 3:
        return const Color(0xFFCD7F32); // ブロンズ
      default:
        return const Color(0xFF5D8FFF); // デフォルト
    }
  }

  /// 投票画面へ遷移
  void _navigateToVoting() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const VibeTopicVotingScreen(),
      ),
    );
  }

  /// Vibeバーのスケルトン（ローディング表示）
  Widget _buildVibeBarSkeleton() {
    return Container(
      height: 190,
      color: AppColors.background,
      padding: const EdgeInsets.all(16),
      child: const Center(
        child: CircularProgressIndicator(),
      ),
    );
  }

  /// Vibeバーの空状態（お題がない場合）
  Widget _buildVibeBarEmpty() {
    return Container(
      height: 190,
      color: AppColors.background,
      child: Column(
        children: [
          // ヘッダー（アイコンと見出し）
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                // Vibeアイコン
                Image.asset(
                  'assets/icons/Vibe.png',
                  width: 40,
                  height: 40,
                  errorBuilder: (context, error, stackTrace) {
                    return Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: Colors.purple,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(Icons.music_note, color: Colors.white),
                    );
                  },
                ),
                const SizedBox(width: 12),
                // Vibe見出し
                const Text(
                  'Vibe',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
          ),
          // メッセージ
          Expanded(
            child: Center(
              child: Text(
                '今日のVibeお題はありません',
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.white.withOpacity(0.6),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// ランキングがない場合のメッセージ
  Widget _buildNoRankingMessage() {
    return Center(
      child: Text(
        'まだ投稿がありません',
        style: TextStyle(
          fontSize: 12,
          color: Colors.white.withOpacity(0.6),
        ),
      ),
    );
  }

  /// アルバムアイテム（Vibeバー用）
  Widget _buildAlbumItem() {
    return Container(
      width: 70,
      margin: const EdgeInsets.symmetric(horizontal: 4),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // アルバムジャケット
          Container(
            width: 60,
            height: 60,
            decoration: BoxDecoration(
              color: Colors.grey[800],
              borderRadius: BorderRadius.circular(4),
            ),
            child: const Icon(Icons.album, color: Colors.white54),
          ),
          const SizedBox(height: 2),
          // アーティスト名 / 曲名
          const Text(
            'アーティスト / 曲名',
            style: TextStyle(
              fontSize: 7,
              color: Colors.white,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
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

            return Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: PostCard(
                key: ValueKey(post.postId), // 投稿IDをkeyにして状態を保持
                post: displayPost,
                currentUserId: currentUserId,
                audioService: _homeAudioService, // ホーム画面専用の音楽再生サービスを渡す
                onLike: () => _handleLike(post),
                onComment: () => _handleComment(post),
                onAdd: () => _handleAdd(post),
                isSaved: _savedPostIds.contains(post.postId),
              ),
            );
          },
          childCount: posts.length,
        ),
      ),
    );
  }

  /// タイムライン（投稿カードリスト）- 旧版（未使用）
  ///
  /// StreamBuilderを使用してFirestoreからリアルタイムで投稿データを取得します。
  /// 他のユーザーが投稿を作成したり、いいねを押した場合、
  /// 自動的にUIが更新され、すべてのユーザーに変更が即座に反映されます。
  Widget _buildTimeline() {
    return StreamBuilder<List<PostModel>>(
      stream: _postService.getPostsStream(limit: 20),
      builder: (context, snapshot) {
        // ローディング中
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(32),
              child: CircularProgressIndicator(color: Colors.white),
            ),
          );
        }

        // エラー発生
        if (snapshot.hasError) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Text(
                'エラーが発生しました\n${snapshot.error}',
                style: const TextStyle(color: Colors.white),
                textAlign: TextAlign.center,
              ),
            ),
          );
        }

        // デバッグ用: 常にテストデータを表示（Firestoreの古いデータを無視）
        final posts = TestData.generateTestPosts();

        // 本番用（Firestoreデータを使用する場合）:
        // final posts = (snapshot.hasData && snapshot.data!.isNotEmpty)
        //     ? snapshot.data!
        //     : TestData.generateTestPosts();
        // テストモード用: currentUserがnullの場合はダミーユーザーIDを使用
        final currentUserId = _auth.currentUser?.uid ?? 'test_user_temp';

        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 15),
          child: Column(
            children: posts.map((post) {
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

              return Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: PostCard(
                  key: ValueKey(post.postId), // 投稿IDをkeyにして状態を保持
                  post: displayPost,
                  currentUserId: currentUserId,
                  audioService: _homeAudioService,
                  onLike: () => _handleLike(post),
                  onComment: () => _handleComment(post),
                  onAdd: () => _handleAdd(post),
                ),
              );
            }).toList(),
          ),
        );
      },
    );
  }

  /// いいねボタンが押されたときの処理
  Future<void> _handleLike(PostModel post) async {
    final currentUser = _auth.currentUser;

    // テストモード用: currentUserがnullの場合はダミーユーザーIDを使用
    final userId = currentUser?.uid ?? 'test_user_temp';

    // テスト投稿の場合はTestDataを使用
    if (post.postId.startsWith('test_post_')) {
      try {
        // 元のいいね数を取得（表示上のオーバーライドがあればそれを使用）
        final originalLikeCount = _likeCounts[post.postId] ?? post.likeCount;

        // TestDataでいいねをトグル（ローカルストレージに保存）
        await TestData.toggleLike(post.postId, userId, originalLikeCount);

        // 更新されたいいね状態を取得
        final likeState = await TestData.getLikeState(post.postId);
        final likeCount = likeState['likeCount'] as int;
        final likedUserIds = List<String>.from(likeState['likedUserIds']);

        // ローカルの状態マップを更新（setState不要 - PostCardの楽観的UIが表示を担当）
        if (likeCount > 0) {
          _likeCounts[post.postId] = likeCount;
        } else {
          _likeCounts.remove(post.postId);
        }

        if (likedUserIds.contains(userId)) {
          _likedPostIds.add(post.postId);
        } else {
          _likedPostIds.remove(post.postId);
        }
      } catch (e) {
        print('いいねの保存に失敗: $e');
        _showMessage('いいねに失敗しました');
      }
      return;
    }

    // 通常の投稿の場合は既存のロジック
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
    // コメント画面では音楽を継続するため、停止しない
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => CommentScreen(
          post: post,
          onCommentCountChanged: (count) =>
              _updateCommentCount(post.postId, count),
        ),
      ),
    );

    // 戻ってきた後、投稿データを更新
    if (mounted) {
      if (post.postId.startsWith('test_post_')) {
        // テスト投稿の場合
        final commentCount = await TestData.getCommentCount(post.postId);
        setState(() {
          _commentCounts[post.postId] = commentCount;
        });
      } else {
        // 通常の投稿の場合、Firestoreから最新のデータを取得
        final updatedPost = await _postService.getPost(post.postId);
        if (updatedPost != null && _cachedPosts != null) {
          setState(() {
            // キャッシュ内の投稿を更新
            final index = _cachedPosts!.indexWhere((p) => p.postId == post.postId);
            if (index != -1) {
              _cachedPosts![index] = updatedPost;
            }
          });
        }
      }
    }
  }

  /// 追加ボタンが押されたときの処理（投稿を保存）
  Future<void> _handleAdd(PostModel post) async {
    final currentUser = _auth.currentUser;

    // テストモード用: currentUserがnullの場合はダミーユーザーIDを使用
    final userId = currentUser?.uid ?? 'test_user_temp';

    // ダミーユーザーの場合は常にTestDataを使用（Firestoreにユーザーが存在しないため）
    if (currentUser == null) {
      try {
        print('💾 保存処理開始 - 投稿ID: ${post.postId}');

        // 現在の保存状態を確認
        final isSaved = await TestData.hasSavedPost(userId, post.postId);
        print('📌 現在の保存状態: ${isSaved ? "保存済み" : "未保存"}');

        // 楽観的UI更新: 先に状態を更新
        setState(() {
          if (isSaved) {
            _savedPostIds.remove(post.postId);
          } else {
            _savedPostIds.add(post.postId);
          }
        });

        // TestDataで保存をトグル（ローカルストレージに保存）
        await TestData.toggleSavePost(userId, post.postId);

        // 保存後の状態を確認
        final savedPosts = await TestData.getSavedPosts(userId);
        print('📁 保存済み投稿一覧: $savedPosts');

        // 成功メッセージを表示
        if (isSaved) {
          _showMessage('投稿の保存を解除しました');
        } else {
          _showMessage('投稿を保存しました');
        }
      } catch (e) {
        print('投稿の保存に失敗: $e');

        // エラーが発生したら状態を元に戻す
        setState(() {
          if (_savedPostIds.contains(post.postId)) {
            _savedPostIds.remove(post.postId);
          } else {
            _savedPostIds.add(post.postId);
          }
        });

        _showMessage('投稿の保存に失敗しました');
      }
      return;
    }

    // 認証済みユーザーの場合はFirestoreを使用
    try {
      await _userService.toggleSavePost(
        userId: userId,
        postId: post.postId,
      );

      // 成功メッセージを表示
      _showMessage('投稿を保存しました');
    } catch (e) {
      print('投稿の保存に失敗: $e');
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

  /// ボトムナビゲーション
  Widget _buildBottomNavigation() {
    return Container(
      height: 80,
      padding: const EdgeInsets.symmetric(horizontal: 46, vertical: 10),
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFF191919).withOpacity(0.77),
          borderRadius: BorderRadius.circular(30),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            // ホームボタン
            _buildNavItem(
              icon: Icons.home_outlined,
              selectedIcon: Icons.home,
              index: 0,
            ),
            // 検索ボタン
            _buildNavItem(
              icon: Icons.search,
              index: 1,
            ),
            // 投稿ボタン
            _buildNavItemSvg(
              svgPath: 'assets/icons/post_icon.svg',
              index: 2,
            ),
            // アカウントボタン
            _buildNavItem(
              icon: Icons.account_circle_outlined,
              selectedIcon: Icons.account_circle,
              index: 3,
            ),
          ],
        ),
      ),
    );
  }

  /// ナビゲーションアイテム
  Widget _buildNavItem({
    required IconData icon,
    IconData? selectedIcon,
    required int index,
  }) {
    final isSelected = _selectedIndex == index;
    return IconButton(
      icon: Icon(
        isSelected ? (selectedIcon ?? icon) : icon,
        color: Colors.white,
        size: 28,
      ),
      onPressed: () => _onItemTapped(index),
    );
  }

  /// ナビゲーションアイテム（SVG版）
  Widget _buildNavItemSvg({
    required String svgPath,
    required int index,
  }) {
    final isSelected = _selectedIndex == index;
    return IconButton(
      icon: SvgPicture.asset(
        svgPath,
        width: 28,
        height: 28,
        colorFilter: const ColorFilter.mode(
          Colors.white,
          BlendMode.srcIn,
        ),
      ),
      onPressed: () => _onItemTapped(index),
    );
  }
}

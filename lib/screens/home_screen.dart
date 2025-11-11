import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../constants/app_colors.dart';
import '../models/post_model.dart';
import '../models/track_model.dart';
import '../widgets/post_card.dart';
import '../services/post_service.dart';

/// ホーム画面（タイムライン）
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _selectedIndex = 0;
  final PostService _postService = PostService();
  final FirebaseAuth _auth = FirebaseAuth.instance;

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
        // 検索画面
        _showMessage('検索機能は今後実装予定です');
        break;
      case 2:
        // 投稿作成画面へ遷移
        Navigator.pushNamed(context, '/create-post');
        break;
      case 3:
        // アカウント画面
        _showMessage('アカウント画面は今後実装予定です');
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            // ヘッダー
            _buildHeader(),

            // メインコンテンツ（スクロール可能）
            Expanded(
              child: ListView(
                children: [
                  // Vibeバー
                  _buildVibeBar(),

                  const SizedBox(height: 16),

                  // 投稿カード束（タイムライン）
                  _buildTimeline(),
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
          // 通知アイコン
          IconButton(
            icon: const Icon(Icons.notifications_outlined, color: Colors.white),
            onPressed: () {
              // TODO: 通知画面へ遷移
            },
          ),
        ],
      ),
    );
  }

  /// Vibeバー（横スクロールの音楽アルバムリスト）
  Widget _buildVibeBar() {
    return Container(
      height: 130,
      color: AppColors.background,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ヘッダー
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                // Vibeアイコン（仮）
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: Colors.purple,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.music_note, color: Colors.white),
                ),
                const SizedBox(width: 12),
                const Text(
                  'Vibe【#ドライブで聴きたい曲】',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
          ),
          // 横スクロールアルバムリスト
          Expanded(
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              itemCount: 8, // ダミーデータ
              itemBuilder: (context, index) {
                return _buildAlbumItem();
              },
            ),
          ),
        ],
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

  /// タイムライン（投稿カードリスト）
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

        // データがない場合
        if (!snapshot.hasData || snapshot.data!.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.music_note,
                    size: 64,
                    color: Colors.white54,
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'まだ投稿がありません',
                    style: TextStyle(
                      fontSize: 18,
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '最初の投稿をしてみましょう！',
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.white.withOpacity(0.7),
                    ),
                  ),
                ],
              ),
            ),
          );
        }

        // 投稿カードリストを表示
        final posts = snapshot.data!;
        // テストモード用: currentUserがnullの場合はダミーユーザーIDを使用
        final currentUserId = _auth.currentUser?.uid ?? 'test_user_temp';

        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 15),
          child: Column(
            children: posts.map((post) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: PostCard(
                  key: ValueKey(post.postId), // 投稿IDをkeyにして状態を保持
                  post: post,
                  currentUserId: currentUserId,
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

    try {
      await _postService.toggleLike(
        postId: post.postId,
        userId: userId,
      );
    } catch (e) {
      _showMessage('いいねに失敗しました');
    }
  }

  /// コメントボタンが押されたときの処理
  void _handleComment(PostModel post) {
    // TODO: コメント画面への遷移を実装
    _showMessage('コメント機能は今後実装予定です');
  }

  /// 追加ボタンが押されたときの処理
  void _handleAdd(PostModel post) {
    // TODO: プレイリストへの追加機能を実装
    _showMessage('プレイリストへの追加機能は今後実装予定です');
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
            _buildNavItem(
              icon: Icons.add_box_outlined,
              selectedIcon: Icons.add_box,
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
}

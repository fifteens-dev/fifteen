import 'package:flutter/material.dart';
import '../constants/app_colors.dart';
import '../constants/app_dimensions.dart';

/// 初回タイムライン画面
///
/// 音楽ライブラリ接続後に表示される、投稿がまだない空の状態の画面
/// 最初の投稿を促すUI
/// テスト段階では、ダミーの投稿カードを表示
class FirstTimelineScreen extends StatefulWidget {
  const FirstTimelineScreen({super.key});

  @override
  State<FirstTimelineScreen> createState() => _FirstTimelineScreenState();
}

class _FirstTimelineScreenState extends State<FirstTimelineScreen> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            // ヘッダー
            _buildHeader(),

            // Vibeバー（プレースホルダー）
            _buildVibeBar(),

            // メインコンテンツ（投稿カードのタイムライン）
            Expanded(
              child: _buildTimeline(context),
            ),

            // ボトムナビゲーション
            _buildBottomNavigation(context),
          ],
        ),
      ),
    );
  }

  /// ヘッダー
  Widget _buildHeader() {
    return Container(
      height: 32,
      padding: const EdgeInsets.symmetric(horizontal: AppDimensions.paddingLarge),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Spacer(),
          const Text(
            '15s',
            style: TextStyle(
              fontSize: 30,
              fontWeight: FontWeight.w600,
              color: Colors.white,
            ),
          ),
          const Spacer(),
          IconButton(
            icon: const Icon(Icons.notifications_outlined, color: Colors.white),
            onPressed: () {
              // TODO: 通知画面への遷移
            },
          ),
        ],
      ),
    );
  }

  /// Vibeバー（プレースホルダー）
  Widget _buildVibeBar() {
    return Container(
      height: 130,
      margin: const EdgeInsets.only(top: 48),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ヘッダー
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                // Vibeアイコン
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
                  'Vibe',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                const Text(
                  '【#ドライブで聴きたい曲】',
                  style: TextStyle(
                    fontSize: 10,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
          ),

          // アルバムリスト（プレースホルダー）
          Expanded(
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: 5,
              itemBuilder: (context, index) {
                return Container(
                  width: 60,
                  margin: const EdgeInsets.only(right: 8),
                  child: Column(
                    children: [
                      Container(
                        width: 60,
                        height: 60,
                        decoration: BoxDecoration(
                          color: Colors.grey[800],
                          borderRadius: BorderRadius.circular(5),
                        ),
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        'アーティスト',
                        style: TextStyle(
                          fontSize: 6,
                          color: Colors.grey,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  /// タイムライン（空の状態）
  Widget _buildTimeline(BuildContext context) {
    return const Center(
      child: Text(
        '最初の投稿を作ってみましょう',
        style: TextStyle(color: Colors.white54, fontSize: 14),
      ),
    );
  }

  /// ボトムナビゲーション
  Widget _buildBottomNavigation(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 17),
      child: Container(
        width: 301,
        height: 61,
        decoration: BoxDecoration(
          color: const Color(0xFF191919).withOpacity(0.77),
          borderRadius: BorderRadius.circular(30),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            IconButton(
              icon: const Icon(Icons.home, color: Colors.white),
              onPressed: () {
                // ホーム画面へ遷移
                Navigator.pushReplacementNamed(context, '/home');
              },
            ),
            IconButton(
              icon: const Icon(Icons.search, color: Colors.white),
              onPressed: () {
                // TODO: 検索画面への遷移
              },
            ),
            IconButton(
              icon: const Icon(Icons.add_box_outlined, color: Colors.white),
              onPressed: () => _navigateToCreatePost(context),
            ),
            IconButton(
              icon: const Icon(Icons.account_circle_outlined, color: Colors.white),
              onPressed: () {
                // TODO: プロフィール画面への遷移
              },
            ),
          ],
        ),
      ),
    );
  }

  /// 投稿作成画面への遷移
  void _navigateToCreatePost(BuildContext context) {
    Navigator.pushNamed(context, '/create-post');
  }
}

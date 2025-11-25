import 'package:flutter/material.dart';
import '../constants/app_colors.dart';
import '../constants/app_text_styles.dart';
import '../constants/app_dimensions.dart';
import '../services/settings_service.dart';

/// 音楽ライブラリ接続画面
///
/// プロフィール設定完了後に表示される画面
/// SpotifyまたはApple Musicとの連携を促す
class MusicConnectionScreen extends StatelessWidget {
  const MusicConnectionScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Stack(
          children: [
            // 背景の投稿カード（ぼかし効果）
            _buildBackgroundCard(),

            // グラデーションオーバーレイ
            _buildGradientOverlay(),

            // メインコンテンツ
            _buildContent(context),
          ],
        ),
      ),
    );
  }

  /// 背景の投稿カード（ぼかし効果付き）
  Widget _buildBackgroundCard() {
    return Positioned.fill(
      child: Opacity(
        opacity: 0.3,
        child: Container(
          margin: const EdgeInsets.only(top: 210, left: 15, right: 15),
          decoration: BoxDecoration(
            border: Border.all(color: Colors.white, width: 1),
            borderRadius: BorderRadius.circular(18),
          ),
          child: const Center(
            child: Text(
              'サンプル投稿カード',
              style: TextStyle(color: Colors.white54),
            ),
          ),
        ),
      ),
    );
  }

  /// グラデーションオーバーレイ
  Widget _buildGradientOverlay() {
    return Positioned(
      left: 0,
      right: 0,
      top: 367,
      height: 485,
      child: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color(0x00C3C1BD), // 透明（グラデーション開始）
              Color(0xFF807F7D), // グレー（グラデーション終了）
            ],
            stops: [0.03925, 1.0],
          ),
        ),
      ),
    );
  }

  /// メインコンテンツ
  Widget _buildContent(BuildContext context) {
    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppDimensions.paddingLarge),
        child: Column(
          children: [
            const SizedBox(height: 500), // 上部スペース

            // タイトル
            const Text(
              '音楽ライブラリに接続',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 24),

            // 説明文
            const Text(
              '自身の音楽ライブラリと連携して、あなたの音を15秒に。\nまだ登録していなくても、プレビュー再生は無料で楽しめます。',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12,
                color: Colors.white,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 32),

            // Spotifyボタン
            _buildMusicServiceButton(
              context: context,
              icon: Icons.music_note, // 実際のSpotifyアイコンの代わり
              iconColor: const Color(0xFF1DB954), // Spotify緑
              label: 'Spotifyと連携する',
              onTap: () => _handleSpotifyConnection(context),
            ),
            const SizedBox(height: 16),

            // Apple Musicボタン
            _buildMusicServiceButton(
              context: context,
              icon: Icons.music_note, // 実際のApple Musicアイコンの代わり
              iconColor: const Color(0xFFFA243C), // Apple Music赤
              label: 'Apple Musicと連携する',
              onTap: () => _handleAppleMusicConnection(context),
            ),
            const SizedBox(height: 24),

            // 接続せずに続行
            TextButton(
              onPressed: () => _skipConnection(context),
              child: const Text(
                '接続せずに続行',
                style: TextStyle(
                  fontSize: 13,
                  color: Color(0xFFEBEBEA),
                  decoration: TextDecoration.none,
                ),
              ),
            ),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  /// 音楽サービス接続ボタン
  Widget _buildMusicServiceButton({
    required BuildContext context,
    required IconData icon,
    required Color iconColor,
    required String label,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 315,
        height: 50,
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(33),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 25,
              height: 25,
              decoration: BoxDecoration(
                color: iconColor,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Icon(
                icon,
                size: 16,
                color: Colors.white,
              ),
            ),
            const SizedBox(width: 12),
            Text(
              label,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Spotify接続処理
  void _handleSpotifyConnection(BuildContext context) async {
    // 連携サービス設定を保存（Spotifyをオン、Apple Musicをオフ）
    final settingsService = SettingsService();
    await settingsService.saveAllLinkedServicesSettings(
      spotifyConnected: true,
      appleMusicConnected: false,
    );

    // TODO: 実際のSpotify OAuth認証を実装

    // 初回タイムライン画面へ遷移
    if (context.mounted) {
      Navigator.pushReplacementNamed(context, '/first-timeline');
    }
  }

  /// Apple Music接続処理
  void _handleAppleMusicConnection(BuildContext context) async {
    // 連携サービス設定を保存（Apple Musicをオン、Spotifyをオフ）
    final settingsService = SettingsService();
    await settingsService.saveAllLinkedServicesSettings(
      spotifyConnected: false,
      appleMusicConnected: true,
    );

    // TODO: 実際のApple Music認証を実装

    // 初回タイムライン画面へ遷移
    if (context.mounted) {
      Navigator.pushReplacementNamed(context, '/first-timeline');
    }
  }

  /// 接続をスキップ
  void _skipConnection(BuildContext context) async {
    // 連携サービス設定を保存（両方オフ）
    final settingsService = SettingsService();
    await settingsService.saveAllLinkedServicesSettings(
      spotifyConnected: false,
      appleMusicConnected: false,
    );

    // 初回タイムライン画面へ遷移
    if (context.mounted) {
      Navigator.pushReplacementNamed(context, '/first-timeline');
    }
  }
}

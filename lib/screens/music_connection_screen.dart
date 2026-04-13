import 'package:flutter/material.dart';
import '../constants/app_colors.dart';
import '../services/settings_service.dart';
import '../services/music_service_manager.dart';
import '../services/apple_music_service.dart';
import '../models/music_service_type.dart';
import '../widgets/dialogs/bottom_sheet_dialog.dart';
import 'home_screen.dart';
import '../widgets/common/app_toast.dart';

/// 音楽ライブラリ接続画面
///
/// プロフィール設定完了後に表示される画面
/// SpotifyまたはApple Musicとの連携を促す
/// 背景にホーム画面を表示し、ダイアログ的なUIで接続オプションを表示
class MusicConnectionScreen extends StatelessWidget {
  const MusicConnectionScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Stack(
        children: [
          // 背景: ホーム画面（非インタラクティブ）
          const IgnorePointer(
            child: Opacity(
              opacity: 0.3,
              child: HomeScreen(),
            ),
          ),

          // グラデーションオーバーレイ
          _buildGradientOverlay(),

          // メインコンテンツ
          SafeArea(
            child: _buildContent(context),
          ),
        ],
      ),
    );
  }

  /// グラデーションオーバーレイ
  Widget _buildGradientOverlay() {
    return Positioned(
      left: 0,
      right: 0,
      top: 367,
      bottom: 0,
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
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 39),
      child: Column(
        children: [
          const Spacer(flex: 324),

          // タイトル
          const Align(
            alignment: Alignment.centerLeft,
            child: Text(
              '音楽ライブラリに接続',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
          ),
          const SizedBox(height: 21),

          // 説明文
          const Text(
            '自身の音楽ライブラリと連携して、あなたの音を15秒に。\nまだ登録していなくても、プレビュー再生は無料で楽しめます。',
            textAlign: TextAlign.left,
            style: TextStyle(
              fontSize: 12,
              color: Color(0xFFEBEBEA),
              height: 1.5,
            ),
          ),
          const SizedBox(height: 31),

          // Apple Musicボタン（順序変更：Apple Music → Spotify）
          _buildMusicServiceButton(
            context: context,
            iconAsset: 'assets/icons/Apple_Music.png', // TODO: アイコンを追加
            label: 'Apple Musicと連携する',
            onTap: () => _handleAppleMusicConnection(context),
          ),
          const SizedBox(height: 21),

          // Spotifyボタン
          _buildMusicServiceButton(
            context: context,
            iconAsset: 'assets/icons/Spotify.png', // TODO: アイコンを追加
            label: 'Spotifyと連携する',
            onTap: () => _handleSpotifyConnection(context),
          ),
          const SizedBox(height: 22),

          // 接続せずに続行
          TextButton(
            onPressed: () => _skipConnection(context),
            style: TextButton.styleFrom(
              padding: EdgeInsets.zero,
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: const Text(
              '接続せずに続行',
              style: TextStyle(
                fontSize: 13,
                color: Color(0xFFEBEBEA),
                decoration: TextDecoration.none,
              ),
            ),
          ),

          const Spacer(flex: 161),
        ],
      ),
    );
  }

  /// 音楽サービス接続ボタン
  Widget _buildMusicServiceButton({
    required BuildContext context,
    required String iconAsset,
    required String label,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 315,
        height: 50,
        decoration: BoxDecoration(
          color: const Color(0xFF121212),
          borderRadius: BorderRadius.circular(33),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // アイコン
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: Image.asset(
                iconAsset,
                width: 25,
                height: 25,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) {
                  // フォールバック: アイコンが見つからない場合
                  return Container(
                    width: 25,
                    height: 25,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Icon(
                      Icons.music_note,
                      size: 16,
                      color: label.contains('Apple')
                          ? const Color(0xFFFA243C)
                          : const Color(0xFF1DB954),
                    ),
                  );
                },
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

  /// Apple Music接続処理
  void _handleAppleMusicConnection(BuildContext context) async {
    final musicServiceManager = MusicServiceManager();
    final settingsService = SettingsService();
    final appleMusicService = AppleMusicService();

    // Apple Musicを一時的に選択（login()がgetSelectedService()を参照するため）
    await musicServiceManager.setSelectedService(MusicServiceType.appleMusic);

    // Apple Music認証を試行
    final success = await musicServiceManager.login();

    if (!context.mounted) return;

    if (success) {
      // 認証成功: 連携サービス設定を保存
      await settingsService.saveAllLinkedServicesSettings(
        spotifyConnected: false,
        appleMusicConnected: true,
      );

      // サブスクリプション確認
      final hasSubscription = await appleMusicService.checkSubscriptionAccess();

      if (!context.mounted) return;

      if (!hasSubscription) {
        // 未加入ダイアログを表示してからホームへ
        await BottomSheetDialog.showAppleMusicNoSubscription(context);
        if (!context.mounted) return;
      } else {
        AppToast.show(context, 'Apple Musicと連携しました');
      }

      // ホーム画面へ遷移
      Navigator.pushReplacementNamed(context, '/home');
    } else {
      // 認証失敗: サービス選択をリセット
      await musicServiceManager.setSelectedService(MusicServiceType.none);
      await settingsService.saveAllLinkedServicesSettings(
        spotifyConnected: false,
        appleMusicConnected: false,
      );

      // AppToast.show(context, 'Apple Musicの連携に失敗しました。Apple Musicのサブスクリプションが有効か確認してください。');

      if (context.mounted) {
        Navigator.pushReplacementNamed(context, '/home');
      }
    }
  }

  /// Spotify接続処理
  void _handleSpotifyConnection(BuildContext context) async {
    final musicServiceManager = MusicServiceManager();
    final settingsService = SettingsService();

    // Spotifyを選択
    await musicServiceManager.setSelectedService(MusicServiceType.spotify);

    // Spotify OAuth認証を試行
    final success = await musicServiceManager.login();

    if (!context.mounted) return;

    if (success) {
      // 認証成功: 連携サービス設定を保存
      await settingsService.saveAllLinkedServicesSettings(
        spotifyConnected: true,
        appleMusicConnected: false,
      );

      // AppToast.show(context, 'Spotifyと連携しました');

      // ホーム画面へ遷移
      Navigator.pushReplacementNamed(context, '/home');
    } else {
      // 認証失敗またはキャンセル: AppToast.show(context, 'Spotifyの連携に失敗しました。もう一度お試しください。');

      // 連携なしでホーム画面へ遷移
      await settingsService.saveAllLinkedServicesSettings(
        spotifyConnected: false,
        appleMusicConnected: false,
      );

      if (context.mounted) {
        Navigator.pushReplacementNamed(context, '/home');
      }
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

    // ホーム画面へ遷移
    if (context.mounted) {
      Navigator.pushReplacementNamed(context, '/home');
    }
  }
}

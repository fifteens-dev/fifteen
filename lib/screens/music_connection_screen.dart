import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import '../constants/app_colors.dart';
import '../services/settings_service.dart';
import '../services/music_service_manager.dart';
import '../services/apple_music_service.dart';
import '../services/musickit_service.dart';
import '../models/music_service_type.dart';
import '../widgets/dialogs/bottom_sheet_dialog.dart';
import 'home_screen.dart';
import '../widgets/common/app_toast.dart';
import '../tutorial/tutorial.dart';

/// 音楽ライブラリ接続画面
///
/// プロフィール設定完了後に表示される画面
/// SpotifyまたはApple Musicとの連携を促す
/// 背景にホーム画面を表示し、ダイアログ的なUIで接続オプションを表示
class MusicConnectionScreen extends StatefulWidget {
  const MusicConnectionScreen({super.key});

  @override
  State<MusicConnectionScreen> createState() => _MusicConnectionScreenState();
}

class _MusicConnectionScreenState extends State<MusicConnectionScreen> {
  bool _isAppleMusicLoading = false;
  bool _isSpotifyLoading = false;

  @override
  void initState() {
    super.initState();
    TutorialPrefetchService.instance.prefetchAll();
  }

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
              Color(0x00C3C1BD),
              Color(0xFF807F7D),
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

          // Apple Musicボタン
          _buildMusicServiceButton(
            iconAsset: 'assets/icons/Apple_Music.png',
            label: 'Apple Musicと連携する',
            isLoading: _isAppleMusicLoading,
            onTap: _isAppleMusicLoading || _isSpotifyLoading
                ? null
                : _handleAppleMusicConnection,
          ),
          const SizedBox(height: 21),

          // Spotifyボタン
          _buildMusicServiceButton(
            iconAsset: 'assets/icons/Spotify.png',
            label: 'Spotifyと連携する',
            isLoading: _isSpotifyLoading,
            onTap: _isAppleMusicLoading || _isSpotifyLoading
                ? null
                : _handleSpotifyConnection,
          ),
          const SizedBox(height: 22),

          // 接続せずに続行
          TextButton(
            onPressed: _isAppleMusicLoading || _isSpotifyLoading
                ? null
                : _skipConnection,
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
    required String iconAsset,
    required String label,
    required bool isLoading,
    required VoidCallback? onTap,
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
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Row(
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
            // ラベル（残りスペースを占有）
            Expanded(
              child: Text(
                label,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                ),
              ),
            ),
            // 読み込みマーク（右端）
            if (isLoading)
              const CupertinoActivityIndicator(
                color: Colors.white,
                radius: 9,
              ),
          ],
        ),
      ),
    );
  }

  /// Apple Music接続処理
  Future<void> _handleAppleMusicConnection() async {
    setState(() => _isAppleMusicLoading = true);

    final musicServiceManager = MusicServiceManager();
    final settingsService = SettingsService();
    final appleMusicService = AppleMusicService();

    try {
      await musicServiceManager.setSelectedService(MusicServiceType.appleMusic);

      bool success;
      try {
        success = await musicServiceManager.login();
      } on AppleMusicNoSubscriptionException {
        if (mounted) {
          AppToast.show(context, 'Apple Musicのサブスクリプションが必要です');
          await musicServiceManager.setSelectedService(MusicServiceType.none);
          await settingsService.saveAllLinkedServicesSettings(
            spotifyConnected: false,
            appleMusicConnected: false,
          );
        }
        return;
      }

      if (!mounted) return;

      if (success) {
        await settingsService.saveAllLinkedServicesSettings(
          spotifyConnected: false,
          appleMusicConnected: true,
        );

        final hasSubscription = await appleMusicService.checkSubscriptionAccess();

        if (!mounted) return;

        if (!hasSubscription) {
          await BottomSheetDialog.showAppleMusicNoSubscription(context);
          if (!mounted) return;
        } else {
          AppToast.show(context, 'Apple Musicと連携しました');
        }

        _goToHome();
      } else {
        // 認証拒否またはその他のエラー: リセットして画面に留まる
        await musicServiceManager.setSelectedService(MusicServiceType.none);
        await settingsService.saveAllLinkedServicesSettings(
          spotifyConnected: false,
          appleMusicConnected: false,
        );
        if (mounted) {
          AppToast.show(context, 'Apple Musicの連携に失敗しました');
        }
      }
    } finally {
      if (mounted) setState(() => _isAppleMusicLoading = false);
    }
  }

  /// Spotify接続処理
  Future<void> _handleSpotifyConnection() async {
    setState(() => _isSpotifyLoading = true);

    final musicServiceManager = MusicServiceManager();
    final settingsService = SettingsService();

    try {
      await musicServiceManager.setSelectedService(MusicServiceType.spotify);

      final success = await musicServiceManager.login();

      if (!mounted) return;

      if (success) {
        await settingsService.saveAllLinkedServicesSettings(
          spotifyConnected: true,
          appleMusicConnected: false,
        );
        _goToHome();
      } else {
        await settingsService.saveAllLinkedServicesSettings(
          spotifyConnected: false,
          appleMusicConnected: false,
        );
      }
    } finally {
      if (mounted) setState(() => _isSpotifyLoading = false);
    }
  }

  /// 接続をスキップ
  Future<void> _skipConnection() async {
    final settingsService = SettingsService();
    await settingsService.saveAllLinkedServicesSettings(
      spotifyConnected: false,
      appleMusicConnected: false,
    );

    if (mounted) {
      _goToHome();
    }
  }

  /// チュートリアルを開始してホームへ遷移
  Future<void> _goToHome() async {
    await TutorialController.instance.startFresh();
    if (!mounted) return;
    Navigator.pushReplacementNamed(context, '/home');
  }
}

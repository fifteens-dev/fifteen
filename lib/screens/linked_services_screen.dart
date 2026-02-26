import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import '../services/music_service_manager.dart';
import '../models/music_service_type.dart';
import '../widgets/dialogs/dialogs.dart';

/// 連携サービス画面
class LinkedServicesScreen extends StatefulWidget {
  const LinkedServicesScreen({super.key});

  @override
  State<LinkedServicesScreen> createState() => _LinkedServicesScreenState();
}

class _LinkedServicesScreenState extends State<LinkedServicesScreen> {
  final MusicServiceManager _manager = MusicServiceManager();

  // 連携状態
  MusicServiceType _selectedService = MusicServiceType.none;
  bool _isAuthenticated = false;

  // ローディング状態
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  /// 設定を読み込む
  Future<void> _loadSettings() async {
    final service = await _manager.getSelectedService();
    final authenticated = await _manager.isAuthenticated();

    if (mounted) {
      setState(() {
        _selectedService = service;
        _isAuthenticated = authenticated;
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      body: SafeArea(
        child: Column(
          children: [
            // ヘッダー
            _buildHeader(context),

            // メインコンテンツ
            Expanded(
              child: _isLoading
                  ? const Center(
                      child: CircularProgressIndicator(
                        color: Color(0xFF5D8FFF),
                      ),
                    )
                  : SingleChildScrollView(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Column(
                          children: [
                            const SizedBox(height: 17),

                            // サービスカード
                            _buildServicesCard(),
                          ],
                        ),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  /// ヘッダー
  Widget _buildHeader(BuildContext context) {
    return Container(
      height: 45,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        children: [
          // 戻るボタン
          IconButton(
            icon: const Icon(Icons.chevron_left, color: Colors.white, size: 28),
            onPressed: () => Navigator.pop(context),
          ),
          // タイトル
          const Expanded(
            child: Text(
              '音楽サービス連携',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white,
                fontSize: 15,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          // スペーサー（バランス用）
          const SizedBox(width: 48),
        ],
      ),
    );
  }

  /// サービスカード
  Widget _buildServicesCard() {
    final spotifyConnected =
        _selectedService == MusicServiceType.spotify && _isAuthenticated;
    final appleMusicConnected =
        _selectedService == MusicServiceType.appleMusic && _isAuthenticated;

    return Container(
      decoration: BoxDecoration(
        color: Colors.grey[800],
        borderRadius: BorderRadius.circular(15),
      ),
      child: Column(
        children: [
          // Spotify
          _buildServiceItem(
            icon: _buildSpotifyIcon(),
            title: 'Spotify',
            description: '世界最大の音楽ストリーミング',
            isConnected: spotifyConnected,
            onTap: () => _handleServiceTap(MusicServiceType.spotify),
            isFirst: true,
          ),
          _buildDivider(),
          // Apple Music
          _buildServiceItem(
            icon: _buildAppleMusicIcon(),
            title: 'Apple Music',
            description: 'Appleの音楽サービス',
            isConnected: appleMusicConnected,
            onTap: () => _handleServiceTap(MusicServiceType.appleMusic),
            isLast: true,
          ),
        ],
      ),
    );
  }

  /// Spotifyアイコン
  Widget _buildSpotifyIcon() {
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Image.asset(
        'assets/icons/Spotify.png',
        width: 40,
        height: 40,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) {
          // フォールバック: アイコンが見つからない場合
          return Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: const Color(0xFF1DB954),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Center(
              child: Icon(
                Icons.music_note,
                color: Colors.black,
                size: 24,
              ),
            ),
          );
        },
      ),
    );
  }

  /// Apple Musicアイコン
  Widget _buildAppleMusicIcon() {
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Image.asset(
        'assets/icons/Apple_Music.png',
        width: 40,
        height: 40,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) {
          // フォールバック: アイコンが見つからない場合
          return Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFFFA2D48), Color(0xFFFA6E58)],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Center(
              child: Icon(
                Icons.music_note,
                color: Colors.white,
                size: 24,
              ),
            ),
          );
        },
      ),
    );
  }

  /// サービス項目
  Widget _buildServiceItem({
    required Widget icon,
    required String title,
    required String description,
    required bool isConnected,
    required VoidCallback onTap,
    bool isFirst = false,
    bool isLast = false,
  }) {
    return Container(
      height: 70,
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
      child: Row(
        children: [
          // アイコン
          icon,
          const SizedBox(width: 12),
          // タイトルと説明
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  description,
                  style: TextStyle(
                    color: Colors.grey[400],
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          // 接続ボタン
          GestureDetector(
            onTap: onTap,
            child: Container(
              height: 32,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                color: isConnected
                    ? const Color(0xFF4CAF50)
                    : const Color(0xFF5D8FFF),
                borderRadius: BorderRadius.circular(23),
              ),
              child: Center(
                child: Text(
                  isConnected ? '連携中' : '連携',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 区切り線
  Widget _buildDivider() {
    return Container(
      height: 1,
      color: Colors.grey[700],
    );
  }

  /// サービスタップ処理
  Future<void> _handleServiceTap(MusicServiceType service) async {
    final isConnected =
        _selectedService == service && _isAuthenticated;

    if (isConnected) {
      // 接続済みの場合は解除確認ダイアログを表示
      _showDisconnectDialog(service.displayName, () async {
        await _disconnectService();
      });
    } else {
      // 未接続の場合は説明ダイアログを表示
      _showServiceInfoDialog(service, () async {
        // 他のサービスが接続中の場合は切り替え確認ダイアログを表示
        if (_selectedService != MusicServiceType.none && _isAuthenticated) {
          _showSwitchConnectionDialog(
              service.displayName, _selectedService.displayName, () async {
            await _connectService(service);
          });
        } else {
          // 他のサービスが接続されていない場合は直接接続
          await _connectService(service);
        }
      });
    }
  }

  /// サービスに接続
  Future<void> _connectService(MusicServiceType service) async {
    // Web環境では認証機能を無効化
    if (kIsWeb) {
      if (mounted) {
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            backgroundColor: Colors.grey[900],
            title: const Text(
              '音楽サービス連携',
              style: TextStyle(color: Colors.white),
            ),
            content: const Text(
              'Web環境では音楽サービス連携機能は利用できません。\n\niOS/Androidデバイスまたはエミュレータでアプリを実行してください。',
              style: TextStyle(color: Colors.white70),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text(
                  'OK',
                  style: TextStyle(color: Color(0xFF5D8FFF)),
                ),
              ),
            ],
          ),
        );
      }
      return;
    }

    setState(() => _isLoading = true);

    // 前のサービスを記憶（失敗時のリセット用）
    final previousService = _selectedService;

    try {
      // サービスを選択（login()がgetSelectedService()を参照するため先に設定）
      await _manager.setSelectedService(service);

      // ログイン実行
      final success = await _manager.login();

      if (mounted) {
        if (success) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('${service.displayName}に連携しました'),
              backgroundColor: const Color(0xFF4CAF50),
            ),
          );
          await _loadSettings();
        } else {
          // 失敗時は前のサービスに戻す
          await _manager.setSelectedService(previousService);

          String errorMessage = '${service.displayName}の連携に失敗しました';
          if (service == MusicServiceType.appleMusic) {
            errorMessage = 'Apple Musicの連携に失敗しました。Apple Musicのサブスクリプションが有効か確認してください。';
          }

          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(errorMessage),
              backgroundColor: const Color(0xFFE53935),
              duration: const Duration(seconds: 4),
            ),
          );
          setState(() => _isLoading = false);
        }
      }
    } catch (e) {
      // 例外時も前のサービスに戻す
      await _manager.setSelectedService(previousService);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('エラーが発生しました: $e'),
            backgroundColor: const Color(0xFFE53935),
          ),
        );
        setState(() => _isLoading = false);
      }
    }
  }

  /// サービスから切断
  Future<void> _disconnectService() async {
    setState(() => _isLoading = true);

    try {
      await _manager.logout();
      await _manager.setSelectedService(MusicServiceType.none);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('音楽サービスとの連携を解除しました'),
            backgroundColor: Color(0xFF9F9F9F),
          ),
        );
        await _loadSettings();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('エラーが発生しました: $e'),
            backgroundColor: const Color(0xFFE53935),
          ),
        );
        setState(() => _isLoading = false);
      }
    }
  }

  /// サービス情報ダイアログ
  Future<void> _showServiceInfoDialog(MusicServiceType service, VoidCallback onConnect) async {
    // サービスごとの説明
    String title;
    List<String> features;
    String icon;

    switch (service) {
      case MusicServiceType.spotify:
        title = 'Spotifyと連携';
        icon = '🎵';
        features = [
          '自身のプレイリストを取得',
        ];
        break;
      case MusicServiceType.appleMusic:
        title = 'Apple Musicと連携';
        icon = '🎧';
        features = [
          '自身のプレイリストを取得',
          '全ての歌詞データ取得可能',
        ];
        break;
      default:
        return;
    }

    final shouldConnect = await ServiceInfoBottomSheet.show(
      context,
      title: title,
      icon: icon,
      features: features,
    );

    if (shouldConnect) {
      onConnect();
    }
  }

  /// 接続切り替え確認ダイアログ
  Future<void> _showSwitchConnectionDialog(String newService, String currentService, VoidCallback onSwitch) async {
    final shouldSwitch = await BottomSheetDialog.showSwitchService(
      context,
      newService: newService,
      currentService: currentService,
    );

    if (shouldSwitch) {
      onSwitch();
    }
  }

  /// 接続解除確認ダイアログ
  Future<void> _showDisconnectDialog(String serviceName, VoidCallback onDisconnect) async {
    final shouldDisconnect = await BottomSheetDialog.showDisconnect(
      context,
      serviceName: serviceName,
    );

    if (shouldDisconnect) {
      onDisconnect();
    }
  }
}

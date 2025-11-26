import 'package:flutter/material.dart';
import '../services/settings_service.dart';

/// 連携サービス画面
class LinkedServicesScreen extends StatefulWidget {
  const LinkedServicesScreen({super.key});

  @override
  State<LinkedServicesScreen> createState() => _LinkedServicesScreenState();
}

class _LinkedServicesScreenState extends State<LinkedServicesScreen> {
  final SettingsService _settingsService = SettingsService();

  // 連携状態
  bool _spotifyConnected = false;
  bool _appleMusicConnected = false;

  // ローディング状態
  bool _isLoading = true;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  /// 設定を読み込む
  Future<void> _loadSettings() async {
    final settings = await _settingsService.getAllLinkedServicesSettings();
    if (mounted) {
      setState(() {
        _spotifyConnected = settings['spotifyConnected'] ?? false;
        _appleMusicConnected = settings['appleMusicConnected'] ?? false;
        _isLoading = false;
      });
    }
  }

  /// 設定を保存する
  Future<void> _saveSettings() async {
    setState(() => _isSaving = true);

    await _settingsService.saveAllLinkedServicesSettings(
      spotifyConnected: _spotifyConnected,
      appleMusicConnected: _appleMusicConnected,
    );

    if (mounted) {
      setState(() => _isSaving = false);
      Navigator.pop(context);
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
              '連携サービス',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white,
                fontSize: 15,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          // 保存ボタン
          TextButton(
            onPressed: _isSaving ? null : _saveSettings,
            child: _isSaving
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Color(0xFF5D8FFF),
                    ),
                  )
                : const Text(
                    '保存',
                    style: TextStyle(
                      color: Color(0xFF5D8FFF),
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  /// サービスカード
  Widget _buildServicesCard() {
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
            isConnected: _spotifyConnected,
            onTap: () => _handleServiceTap('Spotify', _spotifyConnected, (value) {
              setState(() => _spotifyConnected = value);
            }),
            isFirst: true,
          ),
          _buildDivider(),
          // Apple Music
          _buildServiceItem(
            icon: _buildAppleMusicIcon(),
            title: 'Apple Music',
            isConnected: _appleMusicConnected,
            onTap: () => _handleServiceTap('Apple Music', _appleMusicConnected, (value) {
              setState(() => _appleMusicConnected = value);
            }),
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
        'assets/icons/spotify.png',
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
        'assets/icons/apple_music.png',
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
    required bool isConnected,
    required VoidCallback onTap,
    bool isFirst = false,
    bool isLast = false,
  }) {
    return Container(
      height: 58,
      padding: const EdgeInsets.symmetric(horizontal: 11),
      child: Row(
        children: [
          // アイコン
          icon,
          const SizedBox(width: 12),
          // タイトル
          Expanded(
            child: Text(
              title,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 15,
                fontWeight: FontWeight.bold,
              ),
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
                    ? const Color(0xFFBFB6F8)
                    : const Color(0xFF624AF5),
                borderRadius: BorderRadius.circular(23),
              ),
              child: Center(
                child: Text(
                  isConnected ? 'Connected' : 'Connect',
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
  void _handleServiceTap(String serviceName, bool isConnected, Function(bool) onUpdate) {
    if (isConnected) {
      // 接続済みの場合は解除確認ダイアログを表示
      _showDisconnectDialog(serviceName, () {
        onUpdate(false);
      });
    } else {
      // 未接続の場合
      // 他のサービスが接続中かチェック
      String? otherConnectedService = _getOtherConnectedService(serviceName);
      if (otherConnectedService != null) {
        // 他のサービスが接続中の場合は切り替え確認ダイアログを表示
        _showSwitchConnectionDialog(serviceName, otherConnectedService, () {
          // 他のサービスを解除して新しいサービスを接続
          if (serviceName == 'Spotify') {
            setState(() {
              _appleMusicConnected = false;
              _spotifyConnected = true;
            });
          } else {
            setState(() {
              _spotifyConnected = false;
              _appleMusicConnected = true;
            });
          }
        });
      } else {
        // 他のサービスが接続されていない場合は直接接続
        onUpdate(true);
      }
    }
  }

  /// 他の接続中のサービスを取得
  String? _getOtherConnectedService(String currentService) {
    if (currentService == 'Spotify' && _appleMusicConnected) {
      return 'Apple Music';
    } else if (currentService == 'Apple Music' && _spotifyConnected) {
      return 'Spotify';
    }
    return null;
  }

  /// 接続切り替え確認ダイアログ
  void _showSwitchConnectionDialog(String newService, String currentService, VoidCallback onSwitch) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        margin: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.grey[800],
          borderRadius: BorderRadius.circular(36),
        ),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // タイトル
              Text(
                '${newService}と接続',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              // メッセージ
              Text(
                '${currentService}との接続を解除して${newService}と接続しますか？',
                style: TextStyle(
                  color: Colors.grey[400],
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 24),
              // ボタン
              Row(
                children: [
                  // キャンセルボタン
                  Expanded(
                    child: GestureDetector(
                      onTap: () => Navigator.pop(context),
                      child: Container(
                        height: 45,
                        decoration: BoxDecoration(
                          color: Colors.grey[700],
                          borderRadius: BorderRadius.circular(13),
                        ),
                        child: const Center(
                          child: Text(
                            'キャンセル',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  // 接続ボタン
                  Expanded(
                    child: GestureDetector(
                      onTap: () {
                        Navigator.pop(context);
                        onSwitch();
                      },
                      child: Container(
                        height: 45,
                        decoration: BoxDecoration(
                          color: Colors.grey[700],
                          borderRadius: BorderRadius.circular(13),
                        ),
                        child: const Center(
                          child: Text(
                            '接続',
                            style: TextStyle(
                              color: Colors.red,
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 接続解除確認ダイアログ
  void _showDisconnectDialog(String serviceName, VoidCallback onDisconnect) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        margin: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.grey[800],
          borderRadius: BorderRadius.circular(36),
        ),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // タイトル
              Text(
                '${serviceName}との接続を解除',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),
              // メッセージ
              Text(
                '本当に接続を解除しますか？',
                style: TextStyle(
                  color: Colors.grey[400],
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 24),
              // ボタン
              Row(
                children: [
                  // キャンセルボタン
                  Expanded(
                    child: GestureDetector(
                      onTap: () => Navigator.pop(context),
                      child: Container(
                        height: 45,
                        decoration: BoxDecoration(
                          color: Colors.grey[700],
                          borderRadius: BorderRadius.circular(13),
                        ),
                        child: const Center(
                          child: Text(
                            'キャンセル',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  // 解除ボタン
                  Expanded(
                    child: GestureDetector(
                      onTap: () {
                        Navigator.pop(context);
                        onDisconnect();
                      },
                      child: Container(
                        height: 45,
                        decoration: BoxDecoration(
                          color: Colors.grey[700],
                          borderRadius: BorderRadius.circular(13),
                        ),
                        child: const Center(
                          child: Text(
                            '解除',
                            style: TextStyle(
                              color: Colors.red,
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

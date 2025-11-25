import 'package:flutter/material.dart';
import '../services/settings_service.dart';

/// 通知設定画面
class NotificationSettingsScreen extends StatefulWidget {
  const NotificationSettingsScreen({super.key});

  @override
  State<NotificationSettingsScreen> createState() =>
      _NotificationSettingsScreenState();
}

class _NotificationSettingsScreenState
    extends State<NotificationSettingsScreen> {
  final SettingsService _settingsService = SettingsService();

  // 通知設定の状態
  bool _vibeNotification = true;
  bool _likeCommentNotification = true;
  bool _followNotification = true;
  bool _officialNotification = true;

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
    final settings = await _settingsService.getAllNotificationSettings();
    if (mounted) {
      setState(() {
        _vibeNotification = settings['vibeNotification'] ?? true;
        _likeCommentNotification = settings['likeCommentNotification'] ?? true;
        _followNotification = settings['followNotification'] ?? true;
        _officialNotification = settings['officialNotification'] ?? true;
        _isLoading = false;
      });
    }
  }

  /// 設定を保存する
  Future<void> _saveSettings() async {
    setState(() => _isSaving = true);

    await _settingsService.saveAllNotificationSettings(
      vibeNotification: _vibeNotification,
      likeCommentNotification: _likeCommentNotification,
      followNotification: _followNotification,
      officialNotification: _officialNotification,
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

                            // 通知設定カード
                            _buildNotificationCard(),
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
              '通知',
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

  /// 通知設定カード
  Widget _buildNotificationCard() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.grey[800],
        borderRadius: BorderRadius.circular(15),
      ),
      child: Column(
        children: [
          // Vibe通知
          _buildNotificationItem(
            icon: _buildVibeIcon(),
            title: 'Vibe通知',
            value: _vibeNotification,
            onChanged: (value) {
              setState(() => _vibeNotification = value);
            },
            isFirst: true,
          ),
          _buildDivider(),
          // いいね/コメント通知
          _buildNotificationItem(
            icon: const Icon(
              Icons.favorite_outline,
              color: Colors.white,
              size: 20,
            ),
            title: 'いいね/コメント通知',
            value: _likeCommentNotification,
            onChanged: (value) {
              setState(() => _likeCommentNotification = value);
            },
          ),
          _buildDivider(),
          // フォロー通知
          _buildNotificationItem(
            icon: _buildFollowIcon(),
            title: 'フォロー通知',
            value: _followNotification,
            onChanged: (value) {
              setState(() => _followNotification = value);
            },
          ),
          _buildDivider(),
          // 運営からのお知らせ通知
          _buildNotificationItem(
            icon: const Icon(
              Icons.account_circle_outlined,
              color: Colors.white,
              size: 20,
            ),
            title: '運営からのお知らせ通知',
            value: _officialNotification,
            onChanged: (value) {
              setState(() => _officialNotification = value);
            },
            isLast: true,
          ),
        ],
      ),
    );
  }

  /// Vibeアイコン（グラデーション）
  Widget _buildVibeIcon() {
    return Container(
      width: 20,
      height: 20,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(4),
        gradient: const LinearGradient(
          colors: [Color(0xFFFF6B9D), Color(0xFF8B5CF6), Color(0xFF3B82F6)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: const Icon(
        Icons.play_arrow,
        color: Colors.white,
        size: 14,
      ),
    );
  }

  /// フォローアイコン
  Widget _buildFollowIcon() {
    return Container(
      width: 20,
      height: 20,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 1.5),
      ),
      child: const Icon(
        Icons.add,
        color: Colors.white,
        size: 12,
      ),
    );
  }

  /// 通知項目
  Widget _buildNotificationItem({
    required Widget icon,
    required String title,
    required bool value,
    required ValueChanged<bool> onChanged,
    bool isFirst = false,
    bool isLast = false,
  }) {
    return Container(
      height: 58,
      padding: const EdgeInsets.symmetric(horizontal: 20),
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
          // トグルスイッチ
          Switch(
            value: value,
            onChanged: onChanged,
            activeColor: Colors.white,
            activeTrackColor: const Color(0xFF34C759),
            inactiveThumbColor: Colors.white,
            inactiveTrackColor: Colors.grey[600],
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
}

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
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
  bool _postNotification = true;
  bool _officialNotification = true;

  // ローディング状態
  bool _isLoading = true;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  /// 設定を読み込む（SharedPreferences → Firestore の順で上書き）
  Future<void> _loadSettings() async {
    // まずSharedPreferencesから即時表示
    final localSettings = await _settingsService.getAllNotificationSettings();
    if (mounted) {
      setState(() {
        _vibeNotification = localSettings['vibeNotification'] ?? true;
        _likeCommentNotification = localSettings['likeCommentNotification'] ?? true;
        _followNotification = localSettings['followNotification'] ?? true;
        _postNotification = localSettings['postNotification'] ?? true;
        _officialNotification = localSettings['officialNotification'] ?? true;
      });
    }

    // Firestoreから読み込んで上書き（機種変更時の同期）
    final userId = FirebaseAuth.instance.currentUser?.uid;
    if (userId != null) {
      try {
        final doc = await FirebaseFirestore.instance
            .collection('users')
            .doc(userId)
            .get();
        if (doc.exists && mounted) {
          final data = doc.data()!;
          setState(() {
            if (data.containsKey('notifVibeEnabled')) {
              _vibeNotification = data['notifVibeEnabled'] as bool;
            }
            if (data.containsKey('notifLikeCommentEnabled')) {
              _likeCommentNotification = data['notifLikeCommentEnabled'] as bool;
            }
            if (data.containsKey('notifFollowEnabled')) {
              _followNotification = data['notifFollowEnabled'] as bool;
            }
            if (data.containsKey('notifPostEnabled')) {
              _postNotification = data['notifPostEnabled'] as bool;
            }
            if (data.containsKey('notifOfficialEnabled')) {
              _officialNotification = data['notifOfficialEnabled'] as bool;
            }
          });
          // Firestoreの値でSharedPreferencesも同期
          await _settingsService.saveAllNotificationSettings(
            vibeNotification: _vibeNotification,
            likeCommentNotification: _likeCommentNotification,
            followNotification: _followNotification,
            postNotification: _postNotification,
            officialNotification: _officialNotification,
          );
        }
      } catch (_) {
        // Firestore読み込み失敗時はSharedPreferencesの値を使用
      }
    }

    if (mounted) setState(() => _isLoading = false);
  }

  /// 設定を保存する
  Future<void> _saveSettings() async {
    setState(() => _isSaving = true);

    // SharedPreferencesに保存（クライアント側チェック用）
    await _settingsService.saveAllNotificationSettings(
      vibeNotification: _vibeNotification,
      likeCommentNotification: _likeCommentNotification,
      followNotification: _followNotification,
      postNotification: _postNotification,
      officialNotification: _officialNotification,
    );

    // Firestoreにも全5項目保存（Cloud Functionが参照 + 機種変更時の同期用）
    final userId = FirebaseAuth.instance.currentUser?.uid;
    if (userId != null) {
      await FirebaseFirestore.instance.collection('users').doc(userId).update({
        'notifVibeEnabled': _vibeNotification,
        'notifLikeCommentEnabled': _likeCommentNotification,
        'notifFollowEnabled': _followNotification,
        'notifPostEnabled': _postNotification,
        'notifOfficialEnabled': _officialNotification,
      });
    }

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
                      child: CupertinoActivityIndicator(
                        color: Color(0xFF5D8FFF),
                        radius: 14,
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
                ? const CupertinoActivityIndicator(
                    color: Color(0xFF5D8FFF),
                    radius: 8,
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
          // 投稿通知
          _buildNotificationItem(
            icon: _buildPostIcon(),
            title: '投稿通知',
            value: _postNotification,
            onChanged: (value) {
              setState(() => _postNotification = value);
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

  /// 投稿通知アイコン
  Widget _buildPostIcon() {
    return const Icon(
      Icons.music_note,
      color: Colors.white,
      size: 20,
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
            activeThumbColor: Colors.white,
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

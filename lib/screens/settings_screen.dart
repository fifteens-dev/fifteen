import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:provider/provider.dart';
import '../providers/saved_items_provider.dart';
import '../providers/current_user_provider.dart';
import '../services/user_service.dart';
import '../services/admin_service.dart';
import '../models/user_model.dart';
import '../widgets/dialogs/dialogs.dart';
import 'account_edit_screen.dart';
import 'notification_settings_screen.dart';
import 'linked_services_screen.dart';
import 'help_screen.dart';
import 'login_info_screen.dart';
import 'invitation_screen.dart';
import 'basic_info_screen.dart';
import 'admin/admin_screen.dart';
import 'adl_join_screen.dart';
import '../services/adl_service.dart';
import 'milfolha_join_screen.dart';
import '../services/milfolha_service.dart';
import '../constants/milfolha_teams.dart';

/// 設定画面
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final UserService _userService = UserService();
  final AdminService _adminService = AdminService();
  final AdlService _adlService = AdlService();
  final MilfolhaService _milfolhaService = MilfolhaService();
  UserModel? _userData;
  bool _isAdmin = false;
  bool _adlActive = false;
  bool _milfolhaActive = false;
  String? _milfolhaTeamId;

  @override
  void initState() {
    super.initState();
    _loadUserData();
  }

  /// ユーザーデータを読み込み
  Future<void> _loadUserData() async {
    final currentUser = FirebaseAuth.instance.currentUser;

    if (currentUser == null) return;

    try {
      final userData = await _userService.getUser(currentUser.uid);
      final isAdmin = await _adminService.isCurrentUserAdmin();
      if (mounted) {
        setState(() {
          _userData = userData;
          _isAdmin = isAdmin;
        });
      }
    } catch (_) {}

    // ADL情報は独立してロード（失敗しても上記に影響しない）
    try {
      final adlActive = await _adlService.isAdlModeActive();
      if (mounted) {
        setState(() {
          _adlActive = adlActive;
        });
      }
    } catch (_) {}

    // Milfolha情報も独立してロード
    try {
      final active = await _milfolhaService.isActive();
      final membership =
          await _milfolhaService.getMembership(currentUser.uid);
      if (mounted) {
        setState(() {
          _milfolhaActive = active;
          _milfolhaTeamId = membership?['teamId'] as String?;
        });
      }
    } catch (_) {}
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
              child: SingleChildScrollView(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 8),

                      // あなたのアカウント
                      _buildSectionLabel('あなたのアカウント'),
                      const SizedBox(height: 8),
                      _buildAccountCard(context),

                      const SizedBox(height: 24),

                      // アカウント設定
                      _buildSectionLabel('アカウント設定'),
                      const SizedBox(height: 8),
                      _buildSettingsCard([
                        _SettingsItem(
                          icon: Icons.account_circle_outlined,
                          title: 'ログイン情報の確認',
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                  builder: (context) =>
                                      const LoginInfoScreen()),
                            );
                          },
                        ),
                      ]),

                      const SizedBox(height: 24),

                      // 設定
                      _buildSectionLabel('設定'),
                      const SizedBox(height: 8),
                      _buildSettingsCard([
                        _SettingsItem(
                          icon: Icons.notifications_outlined,
                          title: '通知',
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                  builder: (context) =>
                                      const NotificationSettingsScreen()),
                            );
                          },
                        ),
                        _SettingsItem(
                          icon: Icons.music_note_outlined,
                          title: '連携サービス',
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                  builder: (context) =>
                                      const LinkedServicesScreen()),
                            );
                          },
                          showDivider: true,
                        ),
                        _SettingsItem(
                          icon: Icons.info_outline,
                          title: '招待',
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                  builder: (context) =>
                                      const InvitationScreen()),
                            );
                          },
                          showDivider: true,
                        ),
                      ]),

                      const SizedBox(height: 24),

                      // 基本情報
                      _buildSectionLabel('基本情報'),
                      const SizedBox(height: 8),
                      _buildSettingsCard([
                        _SettingsItem(
                          icon: Icons.help_outline,
                          title: 'ヘルプ',
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                  builder: (context) => const HelpScreen()),
                            );
                          },
                        ),
                        _SettingsItem(
                          icon: Icons.info_outline,
                          title: '基本情報',
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                  builder: (context) =>
                                      const BasicInfoScreen()),
                            );
                          },
                          showDivider: true,
                        ),
                      ]),

                      // ADLイベント（開催中のみ表示）
                      if (_adlActive) ...[
                        const SizedBox(height: 24),
                        _buildSectionLabel('ADLイベント'),
                        const SizedBox(height: 8),
                        _buildSettingsCard([
                          _SettingsItem(
                            icon: Icons.groups,
                            title: _userData?.adlTeamName != null
                                ? '${_userData!.adlTeamName}（参加中）'
                                : '班に参加する',
                            onTap: () async {
                              await Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => AdlJoinScreen(
                                    currentTeamName: _userData?.adlTeamName,
                                    currentTeamId: _userData?.adlTeamId,
                                  ),
                                ),
                              );
                              // 参加・切替・離脱いずれの結果でも最新状態を反映
                              _loadUserData();
                            },
                          ),
                        ]),
                      ],

                      // Milfolha イベント（開催中のみ表示）
                      if (_milfolhaActive) ...[
                        const SizedBox(height: 24),
                        _buildSectionLabel('WATERFALLSイベント'),
                        const SizedBox(height: 8),
                        _buildSettingsCard([
                          _SettingsItem(
                            icon: Icons.emoji_events,
                            title: _milfolhaTeamId != null
                                ? 'チーム ${MilfolhaTeamDefinitions.displayNameOf(_milfolhaTeamId!)}（参加中）'
                                : 'チームに参加する',
                            onTap: () async {
                              await Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => MilfolhaJoinScreen(
                                    currentTeamId: _milfolhaTeamId,
                                  ),
                                ),
                              );
                              _loadUserData();
                            },
                          ),
                        ]),
                      ],

                      // 管理者向け（管理者のみ表示）
                      if (_isAdmin) ...[
                        const SizedBox(height: 24),
                        _buildSectionLabel('管理者'),
                        const SizedBox(height: 8),
                        _buildSettingsCard([
                          _SettingsItem(
                            icon: Icons.admin_panel_settings,
                            title: '管理者パネル',
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                    builder: (context) =>
                                        const AdminScreen()),
                              );
                            },
                          ),
                        ]),
                      ],

                      const SizedBox(height: 24),

                      // ログアウトボタン
                      _buildLogoutButton(context),

                      const SizedBox(height: 32),
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
              '設定',
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

  /// セクションラベル
  Widget _buildSectionLabel(String label) {
    return Text(
      label,
      style: const TextStyle(
        color: Color(0xFF555557),
        fontSize: 11,
        fontWeight: FontWeight.bold,
      ),
    );
  }

  /// アカウントカード
  Widget _buildAccountCard(BuildContext context) {
    final name = _userData?.name ?? '名前未設定';
    final username = _userData?.username ?? 'ユーザー名';
    final profileImageUrl = _userData?.profileImageUrl;

    return Container(
      height: 82,
      decoration: BoxDecoration(
        color: Colors.grey[800],
        borderRadius: BorderRadius.circular(15),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(15),
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (context) => const AccountEditScreen()),
            );
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
            child: Row(
              children: [
                // プロフィール画像
                Container(
                  width: 59,
                  height: 59,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.grey[700],
                  ),
                  child: ClipOval(
                    child: profileImageUrl != null
                        ? CachedNetworkImage(
                            imageUrl: profileImageUrl,
                            width: 59,
                            height: 59,
                            fit: BoxFit.cover,
                            errorWidget: (context, url, error) {
                              return const Icon(
                                Icons.person,
                                size: 35,
                                color: Colors.white54,
                              );
                            },
                          )
                        : const Icon(
                            Icons.person,
                            size: 35,
                            color: Colors.white54,
                          ),
                  ),
                ),
                const SizedBox(width: 18),
                // 名前とユーザーID
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        username,
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.8),
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
                // 矢印
                const Icon(
                  Icons.chevron_right,
                  color: Colors.white54,
                  size: 29,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// 設定カード
  Widget _buildSettingsCard(List<_SettingsItem> items) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.grey[800],
        borderRadius: BorderRadius.circular(15),
      ),
      child: Column(
        children: items.asMap().entries.map((entry) {
          final index = entry.key;
          final item = entry.value;
          final isFirst = index == 0;
          final isLast = index == items.length - 1;

          return Column(
            children: [
              if (item.showDivider)
                Divider(
                  height: 1,
                  thickness: 0.5,
                  color: Colors.grey[700],
                ),
              Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.only(
                    topLeft: isFirst ? const Radius.circular(15) : Radius.zero,
                    topRight: isFirst ? const Radius.circular(15) : Radius.zero,
                    bottomLeft: isLast ? const Radius.circular(15) : Radius.zero,
                    bottomRight: isLast ? const Radius.circular(15) : Radius.zero,
                  ),
                  onTap: item.onTap,
                  child: Container(
                    height: 50,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Row(
                      children: [
                        Icon(
                          item.icon,
                          color: Colors.white,
                          size: 20,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            item.title,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        const Icon(
                          Icons.chevron_right,
                          color: Colors.white54,
                          size: 29,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          );
        }).toList(),
      ),
    );
  }

  /// ログアウトボタン
  Widget _buildLogoutButton(BuildContext context) {
    return Container(
      width: double.infinity,
      height: 50,
      decoration: BoxDecoration(
        color: Colors.grey[800],
        borderRadius: BorderRadius.circular(15),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(15),
          onTap: () => _showLogoutDialog(context),
          child: const Center(
            child: Text(
              'ログアウト',
              style: TextStyle(
                color: Colors.red,
                fontSize: 15,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// ログアウト確認ダイアログ
  Future<void> _showLogoutDialog(BuildContext context) async {
    final confirmed = await ConfirmDialog.show(
      context,
      title: 'ログアウト',
      message: 'ログアウトしますか？',
      cancelText: 'キャンセル',
      confirmText: 'ログアウト',
      confirmColor: Colors.red,
    );

    if (confirmed && context.mounted) {
      context.read<SavedItemsProvider>().clear();
      context.read<CurrentUserProvider>().clear();
      await FirebaseAuth.instance.signOut();
      if (context.mounted) {
        Navigator.of(context).pushNamedAndRemoveUntil(
          '/phone-auth',
          (route) => false,
        );
      }
    }
  }
}

/// 設定項目データクラス
class _SettingsItem {
  final IconData icon;
  final String title;
  final VoidCallback onTap;
  final bool showDivider;

  _SettingsItem({
    required this.icon,
    required this.title,
    required this.onTap,
    this.showDivider = false,
  });
}

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import '../../constants/app_colors.dart';
import '../../constants/app_constants.dart';
import '../../services/admin_service.dart';
import 'broadcast_notification_tab.dart';
import 'vibe_topic_management_tab.dart';
import 'vibe_posts_viewer_tab.dart';
import 'dev_tools_tab.dart';
import 'invitation_stats_tab.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'reports_tab.dart';
import 'analytics_tab.dart';
import '../../widgets/common/app_toast.dart';

/// 管理者画面
/// 一斉通知とVibeお題管理のタブを持つ
class AdminScreen extends StatefulWidget {
  const AdminScreen({super.key});

  @override
  State<AdminScreen> createState() => _AdminScreenState();
}

class _AdminScreenState extends State<AdminScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final AdminService _adminService = AdminService();
  bool _isAdmin = false;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 8, vsync: this);
    _checkAdminStatus();
  }

  Future<void> _checkAdminStatus() async {
    final isAdmin = await _adminService.isCurrentUserAdmin();
    if (mounted) {
      setState(() {
        _isAdmin = isAdmin;
        _isLoading = false;
      });

      if (!isAdmin) {
        // 管理者でない場合は前の画面に戻る
        Navigator.of(context).pop();
        AppToast.show(context, '管理者権限がありません');
      }
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        backgroundColor: AppColors.backgroundElevated,
        body: Center(
          child: CupertinoActivityIndicator(color: Colors.white, radius: 14),
        ),
      );
    }

    if (!_isAdmin) {
      return const Scaffold(
        backgroundColor: AppColors.backgroundElevated,
        body: Center(
          child: Text(
            '管理者権限がありません',
            style: TextStyle(color: Colors.white),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: AppColors.backgroundElevated,
      appBar: AppBar(
        backgroundColor: AppColors.backgroundElevated,
        title: const Text(
          '管理者パネル',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
          ),
        ),
        iconTheme: const IconThemeData(color: Colors.white),
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          indicatorColor: AppColors.accentBlue,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.grey,
          tabs: const [
            Tab(
              icon: Icon(Icons.bar_chart),
              text: '集計',
            ),
            Tab(
              icon: Icon(Icons.notifications),
              text: '一斉通知',
            ),
            Tab(
              icon: Icon(Icons.topic),
              text: 'Vibeお題',
            ),
            Tab(
              icon: Icon(Icons.list_alt),
              text: 'Vibe投稿',
            ),
            Tab(
              icon: Icon(Icons.developer_mode),
              text: '開発ツール',
            ),
            Tab(
              icon: Icon(Icons.people),
              text: '招待統計',
            ),
            Tab(
              icon: Icon(Icons.flag_outlined),
              text: '通報',
            ),
            Tab(
              icon: Icon(Icons.verified_user),
              text: '公式アカウント',
            ),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: const [
          AnalyticsTab(),
          BroadcastNotificationTab(),
          VibeTopicManagementTab(),
          VibePostsViewerTab(),
          DevToolsTab(),
          InvitationStatsTab(),
          ReportsTab(),
          _OfficialAccountTab(),
        ],
      ),
    );
  }
}

/// 公式アカウントタブ
class _OfficialAccountTab extends StatefulWidget {
  const _OfficialAccountTab();

  @override
  State<_OfficialAccountTab> createState() => _OfficialAccountTabState();
}

class _OfficialAccountTabState extends State<_OfficialAccountTab> {
  bool _isLoading = false;

  Future<void> _loginAsOfficial() async {
    final email = dotenv.env['OFFICIAL_ACCOUNT_EMAIL'] ?? '';
    final password = dotenv.env['OFFICIAL_ACCOUNT_PASSWORD'] ?? '';

    if (email.isEmpty || password.isEmpty) {
      AppToast.show(context, '.env に OFFICIAL_ACCOUNT_EMAIL と OFFICIAL_ACCOUNT_PASSWORD を設定してください');
      return;
    }

    setState(() => _isLoading = true);
    try {
      final credential = await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: email,
        password: password,
      );
      final uid = credential.user!.uid;

      // Firestoreドキュメントをupsert（全フィールドを確実にセット）
      final docRef = FirebaseFirestore.instance.collection('users').doc(uid);
      final existing = await docRef.get();
      await docRef.set({
        'uid': uid,
        'phoneNumber': '',
        'name': '15s',
        'username': '15s_official',
        'bio': '15s公式アカウント',
        'profileImageUrl': existing.data()?['profileImageUrl'],
        'isAdmin': true,
        'followers': existing.data()?['followers'] ?? [],
        'following': existing.data()?['following'] ?? [],
        'savedPosts': existing.data()?['savedPosts'] ?? [],
        'inviteCode': existing.data()?['inviteCode'],
        'createdAt': existing.data()?['createdAt'] ?? FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });

      if (!mounted) return;
      Navigator.pushNamedAndRemoveUntil(context, '/home', (route) => false);
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      AppToast.show(context, e.message ?? 'ログインに失敗しました');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentUser = FirebaseAuth.instance.currentUser;
    final isLoggedInAsOfficial =
        currentUser?.uid == AppConstants.officialAccountUid;

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 現在のログイン状態
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFF1E1E2E),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isLoggedInAsOfficial
                    ? Colors.green.withValues(alpha: 0.5)
                    : Colors.white12,
              ),
            ),
            child: Row(
              children: [
                Icon(
                  isLoggedInAsOfficial ? Icons.verified : Icons.account_circle_outlined,
                  color: isLoggedInAsOfficial ? Colors.green : Colors.white54,
                  size: 22,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        isLoggedInAsOfficial ? '公式アカウントでログイン中' : '通常アカウントでログイン中',
                        style: TextStyle(
                          color: isLoggedInAsOfficial ? Colors.green : Colors.white70,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        currentUser?.email ?? currentUser?.phoneNumber ?? currentUser?.uid ?? '',
                        style: const TextStyle(color: Colors.white38, fontSize: 11),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 32),

          // ワンタップログインボタン
          SizedBox(
            width: double.infinity,
            height: 56,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: isLoggedInAsOfficial
                    ? const Color(0xFF2D2D2D)
                    : const Color(0xFF5D8FFF),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              icon: _isLoading
                  ? const CupertinoActivityIndicator(color: Colors.white, radius: 10)
                  : Icon(
                      isLoggedInAsOfficial ? Icons.check_circle : Icons.login,
                      color: Colors.white,
                    ),
              label: Text(
                isLoggedInAsOfficial ? '公式アカウントでログイン済み' : '公式アカウントに切り替え',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              onPressed: isLoggedInAsOfficial || _isLoading ? null : _loginAsOfficial,
            ),
          ),

          const SizedBox(height: 16),
          const Text(
            '公式アカウントでログインすると 15s 公式として投稿・コメントができます。\n通常アカウントへ戻るにはログアウトして再ログインしてください。',
            style: TextStyle(color: Colors.white38, fontSize: 12),
          ),
        ],
      ),
    );
  }
}

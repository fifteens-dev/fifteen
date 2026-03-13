import 'package:flutter/material.dart';
import '../../constants/app_colors.dart';
import '../../services/admin_service.dart';
import 'broadcast_notification_tab.dart';
import 'vibe_topic_management_tab.dart';
import 'vibe_posts_viewer_tab.dart';
import 'dev_tools_tab.dart';
import 'invitation_stats_tab.dart';
import 'reports_tab.dart';

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
    _tabController = TabController(length: 6, vsync: this);
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
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('管理者権限がありません'),
            backgroundColor: Colors.red,
          ),
        );
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
          child: CircularProgressIndicator(color: Colors.white),
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
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: const [
          BroadcastNotificationTab(),
          VibeTopicManagementTab(),
          VibePostsViewerTab(),
          DevToolsTab(),
          InvitationStatsTab(),
          ReportsTab(),
        ],
      ),
    );
  }
}

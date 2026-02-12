import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'privacy_policy_screen.dart';
import 'terms_of_service_screen.dart';

/// 基本情報画面
class BasicInfoScreen extends StatelessWidget {
  const BasicInfoScreen({super.key});

  // アプリ情報
  static const String _appName = '15s';
  static const String _version = 'v1.0.0';
  static const String _developer = 'FIFTEENs';
  static const String _copyright = '© 2025 FIFTEENs';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
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
                      const SizedBox(height: 5),

                      // アプリ情報セクション
                      _buildSectionLabel('アプリ情報'),
                      const SizedBox(height: 8),
                      _buildAppInfoCard(),

                      const SizedBox(height: 24),

                      // 法的情報セクション
                      _buildSectionLabel('法的情報'),
                      const SizedBox(height: 8),
                      _buildLegalInfoCard(context),

                      const SizedBox(height: 24),

                      // クレジットセクション
                      _buildSectionLabel('クレジット'),
                      const SizedBox(height: 8),
                      _buildCreditCard(),
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
              '基本情報',
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
    return Padding(
      padding: const EdgeInsets.only(left: 6),
      child: Text(
        label,
        style: const TextStyle(
          color: Color(0xFF555557),
          fontSize: 11,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  /// アプリ情報カード
  Widget _buildAppInfoCard() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.grey[800],
        borderRadius: BorderRadius.circular(15),
      ),
      child: Column(
        children: [
          _buildInfoRow('アプリ名：$_appName', isFirst: true),
          _buildDivider(),
          _buildInfoRow('バージョン：$_version'),
          _buildDivider(),
          _buildInfoRow('開発元：$_developer'),
          _buildDivider(),
          _buildInfoRow(_copyright, isLast: true),
        ],
      ),
    );
  }

  /// 情報行
  Widget _buildInfoRow(String text, {bool isFirst = false, bool isLast = false}) {
    return Container(
      height: 50,
      padding: const EdgeInsets.symmetric(horizontal: 18),
      alignment: Alignment.centerLeft,
      child: Text(
        text,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 15,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  /// 法的情報カード
  Widget _buildLegalInfoCard(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.grey[800],
        borderRadius: BorderRadius.circular(15),
      ),
      child: Column(
        children: [
          _buildLegalItem(
            icon: Icons.description_outlined,
            title: 'プライバシーポリシー',
            onTap: () => _openLegalPage(context, 'プライバシーポリシー'),
            isFirst: true,
          ),
          _buildDivider(),
          _buildLegalItem(
            icon: Icons.description_outlined,
            title: '利用規約',
            onTap: () => _openLegalPage(context, '利用規約'),
            isLast: true,
          ),
        ],
      ),
    );
  }

  /// 法的情報項目
  Widget _buildLegalItem({
    required IconData icon,
    required String title,
    required VoidCallback onTap,
    bool isFirst = false,
    bool isLast = false,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.only(
          topLeft: isFirst ? const Radius.circular(15) : Radius.zero,
          topRight: isFirst ? const Radius.circular(15) : Radius.zero,
          bottomLeft: isLast ? const Radius.circular(15) : Radius.zero,
          bottomRight: isLast ? const Radius.circular(15) : Radius.zero,
        ),
        onTap: onTap,
        child: Container(
          height: 58,
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Row(
            children: [
              // アイコン
              Icon(
                icon,
                color: Colors.white,
                size: 20,
              ),
              const SizedBox(width: 20),
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
    );
  }

  /// クレジットカード
  Widget _buildCreditCard() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.grey[800],
        borderRadius: BorderRadius.circular(15),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(15),
          onTap: () async {
            final url = Uri.parse('https://getsongbpm.com');
            if (await canLaunchUrl(url)) {
              await launchUrl(url, mode: LaunchMode.externalApplication);
            }
          },
          child: Container(
            height: 50,
            padding: const EdgeInsets.symmetric(horizontal: 18),
            alignment: Alignment.centerLeft,
            child: Text(
              'BPM data provided by GetSongBPM',
              style: TextStyle(
                color: Colors.grey[400],
                fontSize: 13,
              ),
            ),
          ),
        ),
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

  /// 法的情報画面への遷移
  void _openLegalPage(BuildContext context, String title) {
    if (title == 'プライバシーポリシー') {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (context) => const PrivacyPolicyScreen()),
      );
    } else if (title == '利用規約') {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (context) => const TermsOfServiceScreen()),
      );
    }
  }
}

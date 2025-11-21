import 'package:flutter/material.dart';
import 'faq_screen.dart';
import 'contact_screen.dart';

/// ヘルプ画面
class HelpScreen extends StatelessWidget {
  const HelpScreen({super.key});

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
                    children: [
                      const SizedBox(height: 17),

                      // ヘルプカード
                      _buildHelpCard(context),
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
              'ヘルプ',
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

  /// ヘルプカード
  Widget _buildHelpCard(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.grey[800],
        borderRadius: BorderRadius.circular(15),
      ),
      child: Column(
        children: [
          // お問い合わせ
          _buildHelpItem(
            icon: const Icon(
              Icons.mail_outline,
              color: Colors.white,
              size: 20,
            ),
            title: 'お問い合わせ',
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const ContactScreen()),
              );
            },
            isFirst: true,
          ),
          _buildDivider(),
          // よくある質問
          _buildHelpItem(
            icon: _buildQuestionIcon(),
            title: 'よくある質問',
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const FaqScreen()),
              );
            },
            isLast: true,
          ),
        ],
      ),
    );
  }

  /// よくある質問アイコン（?マーク）
  Widget _buildQuestionIcon() {
    return Container(
      width: 20,
      height: 20,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 1.5),
      ),
      child: const Center(
        child: Text(
          '?',
          style: TextStyle(
            color: Colors.white,
            fontSize: 12,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }

  /// ヘルプ項目
  Widget _buildHelpItem({
    required Widget icon,
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

  /// 区切り線
  Widget _buildDivider() {
    return Container(
      height: 1,
      color: Colors.grey[700],
    );
  }
}

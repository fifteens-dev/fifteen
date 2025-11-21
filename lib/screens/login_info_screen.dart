import 'package:flutter/material.dart';

/// ログイン情報画面
class LoginInfoScreen extends StatelessWidget {
  const LoginInfoScreen({super.key});

  // ダミーデータ（実際にはFirebaseAuthから取得）
  final String _phoneNumber = '+818079690520';

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

                      // セクションラベル
                      _buildSectionLabel('個人の情報'),

                      const SizedBox(height: 8),

                      // 連絡先情報カード
                      _buildContactInfoCard(context),
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
              'ログイン情報',
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

  /// 連絡先情報カード
  Widget _buildContactInfoCard(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.grey[800],
        borderRadius: BorderRadius.circular(15),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(15),
          onTap: () {
            // TODO: 連絡先情報の編集画面への遷移
          },
          child: Container(
            height: 50,
            padding: const EdgeInsets.symmetric(horizontal: 18),
            child: Row(
              children: [
                // 連絡先情報
                Expanded(
                  child: Text(
                    '連絡先情報：$_phoneNumber',
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
      ),
    );
  }
}

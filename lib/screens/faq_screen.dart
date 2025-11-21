import 'package:flutter/material.dart';

/// よくある質問画面
class FaqScreen extends StatelessWidget {
  const FaqScreen({super.key});

  // FAQデータ
  static const List<Map<String, String>> _faqItems = [
    {
      'question': '音楽が再生されない',
      'answer': 'Apple MusicまたはSpotifyの連携が必要です。\n設定 > 連携サービスから設定しください',
    },
    {
      'question': '投稿できません',
      'answer': 'ネットワーク接続を確認し、15秒以内の音源を選択してください',
    },
    {
      'question': 'ログインできない',
      'answer': 'SMS認証コードを再送してください。それでもダメな場合はお問い合わせに連絡してください',
    },
    {
      'question': 'どの音楽サービスが使えますか？',
      'answer': '現在はApple MusicとSpotifyに対応しています',
    },
    {
      'question': 'アプリが重い',
      'answer': '音源や画像のキャッシュを削除することで改善される場合があります',
    },
    {
      'question': '通知が届かない',
      'answer': 'iPhoneの設定で15s > 通知をオンにしてください',
    },
  ];

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
                      const SizedBox(height: 14),

                      // FAQリスト
                      ..._faqItems.map((item) => Padding(
                        padding: const EdgeInsets.only(bottom: 25),
                        child: _buildFaqCard(
                          question: item['question']!,
                          answer: item['answer']!,
                        ),
                      )),

                      const SizedBox(height: 20),
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
              'よくある質問',
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

  /// FAQカード
  Widget _buildFaqCard({
    required String question,
    required String answer,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.grey[800],
        borderRadius: BorderRadius.circular(15),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 質問部分
          Container(
            height: 59,
            padding: const EdgeInsets.symmetric(horizontal: 18),
            alignment: Alignment.centerLeft,
            child: Text(
              'Q. $question',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 15,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          // 区切り線
          Container(
            height: 1,
            color: Colors.grey[700],
          ),
          // 回答部分
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'A.',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    answer,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

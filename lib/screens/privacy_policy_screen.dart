import 'package:flutter/material.dart';

/// プライバシーポリシー画面
class PrivacyPolicyScreen extends StatelessWidget {
  const PrivacyPolicyScreen({super.key});

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
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 19),

                      // タイトル
                      const Text(
                        '15sプライバシーポリシー',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 27,
                          fontWeight: FontWeight.w600,
                        ),
                      ),

                      const SizedBox(height: 16),

                      // 序文
                      _buildParagraph(
                        '15s(以下「本アプリ」)の運営者（以下「当社」）は、本アプリを利用するユーザー(以下「ユーザー」)の個人情報を保護することを重要な責務と考え、以下の通りプライバシーポリシー(以下「本ポリシー」)を定めます。',
                      ),

                      const SizedBox(height: 24),

                      // 第1条
                      _buildSectionTitle('第1条(取得する情報)'),
                      const SizedBox(height: 8),
                      _buildParagraph(
                        '本アプリは、ユーザー登録およびサービス利用の際に、以下の情報を取得する場合があります。',
                      ),
                      const SizedBox(height: 16),
                      _buildNumberedList([
                        '電話番号(SMS認証のため)',
                        '氏名、ユーザーネーム、自己紹介文、プロフィール画像などの登録情報',
                        '投稿コンテンツ(音楽・画像・コメント・Vibe設定など)',
                        '利用履歴・アクセスログ・端末情報',
                        'Apple MusicまたはSpotifyアカウント連携情報(連携認証トークン等)',
                      ]),

                      const SizedBox(height: 24),

                      // 第2条
                      _buildSectionTitle('第2条(利用目的)'),
                      const SizedBox(height: 8),
                      _buildParagraph(
                        '当社は、取得した個人情報を以下の目的で利用します。',
                      ),
                      const SizedBox(height: 16),
                      _buildNumberedList([
                        '本アプリの提供および運営のため',
                        'ユーザー認証およびアカウント管理のため',
                        '投稿コンテンツの表示・共有機能の実現のため',
                        'お問い合わせ・サポート対応のため',
                        '不正利用防止・セキュリティ強化のため',
                        '本アプリの改善・新機能開発・利用状況分析のため',
                      ]),

                      const SizedBox(height: 24),

                      // 第3条
                      _buildSectionTitle('第3条(第三者提供)'),
                      const SizedBox(height: 8),
                      _buildParagraph(
                        '当社は、法令に基づく場合を除き、ユーザーの同意なく個人情報を第三者に提供いたしません。',
                      ),

                      const SizedBox(height: 24),

                      // 第4条
                      _buildSectionTitle('第4条(外部サービスの利用)'),
                      const SizedBox(height: 8),
                      _buildParagraph('・Firebase Authentication / Firestore / Storage (Google LLC)'),
                      _buildParagraph('・Apple Music API (Apple Inc.)'),
                      _buildParagraph('・Spotify Web API (Spotify AB)'),
                      const SizedBox(height: 8),
                      _buildParagraph(
                        'これらのサービスによって収集されたデータは、各社のプライバシーポリシーに従って管理されます。',
                      ),

                      const SizedBox(height: 24),

                      // 第5条
                      _buildSectionTitle('第5条(個人情報の管理)'),
                      const SizedBox(height: 8),
                      _buildParagraph(
                        '当社は、個人情報の漏洩、紛失、改ざんを防止するため、適切な安全対策を講じます。',
                      ),

                      const SizedBox(height: 24),

                      // 第6条
                      _buildSectionTitle('第6条(個人情報の開示・訂正・削除)'),
                      const SizedBox(height: 8),
                      _buildParagraph(
                        'ユーザーは、アプリ内またはサポート窓口を通じて、自身の個人情報の開示・訂正・削除を求めることができます。',
                      ),

                      const SizedBox(height: 24),

                      // 第7条
                      _buildSectionTitle('第7条(未成年者の利用)'),
                      const SizedBox(height: 8),
                      _buildParagraph(
                        '未成年ユーザーは、保護者の同意を得た上で本アプリを利用してください。',
                      ),

                      const SizedBox(height: 24),

                      // 第8条
                      _buildSectionTitle('第8条(プライバシーポリシーの変更)'),
                      const SizedBox(height: 8),
                      _buildParagraph(
                        '本ポリシーの内容は、法令その他の必要に応じて改定されることがあります。改定後の内容は、本アプリ上またはウェブサイトに掲載した時点で効力を生じます。',
                      ),

                      const SizedBox(height: 24),

                      // フッター情報
                      _buildParagraph('制定日：2026年4月1日'),
                      _buildParagraph('運営者：15s運営チーム(FIFTEENs)'),
                      _buildParagraph('責任者：後藤　太郎'),
                      _buildParagraph('所在地：東京都渋谷区'),
                      _buildParagraph('お問い合わせ：support@15s.app'),

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
      height: 58,
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
              '規約とポリシー',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white,
                fontSize: 16,
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

  /// セクションタイトル
  Widget _buildSectionTitle(String title) {
    return Text(
      title,
      style: const TextStyle(
        color: Colors.white,
        fontSize: 18,
        fontWeight: FontWeight.w500,
      ),
    );
  }

  /// 段落テキスト
  Widget _buildParagraph(String text) {
    return Text(
      text,
      style: const TextStyle(
        color: Colors.white,
        fontSize: 15,
        fontWeight: FontWeight.normal,
        height: 1.5,
      ),
    );
  }

  /// 番号付きリスト
  Widget _buildNumberedList(List<String> items) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: items.asMap().entries.map((entry) {
        final index = entry.key + 1;
        final text = entry.value;
        return Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 24,
                child: Text(
                  '$index.',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                  ),
                ),
              ),
              Expanded(
                child: Text(
                  text,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    height: 1.5,
                  ),
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }
}

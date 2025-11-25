import 'package:flutter/material.dart';

/// 利用規約画面
class TermsOfServiceScreen extends StatelessWidget {
  const TermsOfServiceScreen({super.key});

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
                        '15s利用規約',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 27,
                          fontWeight: FontWeight.w600,
                        ),
                      ),

                      const SizedBox(height: 16),

                      // 序文
                      _buildParagraph(
                        'この利用規約(以下「本規約」)は、15s(以下「本アプリ」)の利用規約を定めるものです。ユーザーは、本アプリを利用することにより、本規約に同意したものとみなします。',
                      ),

                      const SizedBox(height: 24),

                      // 第1条
                      _buildSectionTitle('第1条(適用)'),
                      const SizedBox(height: 8),
                      _buildParagraph(
                        '本規約は、ユーザーと当社との間の本アプリの利用に関する一切の関係に適用されます。',
                      ),

                      const SizedBox(height: 24),

                      // 第2条
                      _buildSectionTitle('第2条(登録)'),
                      const SizedBox(height: 8),
                      _buildNumberedList([
                        '本アプリの利用には、電話番号認証によるアカウント登録が必要です。',
                        '登録内容に虚偽や不備がある場合、当社は登録を拒否または削除できるものとします。',
                      ]),

                      const SizedBox(height: 24),

                      // 第3条
                      _buildSectionTitle('第3条(禁止事項)'),
                      const SizedBox(height: 8),
                      _buildParagraph(
                        'ユーザーは、以下の行為を行ってはなりません。',
                      ),
                      const SizedBox(height: 16),
                      _buildNumberedList([
                        '法令または公序良俗に違反する行為',
                        '他人への誹謗中傷やプライバシー侵害',
                        'スパム行為、営業・広告目的の投稿',
                        '著作権・肖像権などの第三者の権利を侵害する行為',
                        'アプリの運営を妨げる行為(リバースエンジニアリング等)',
                        '不正ログインや他人のアカウント使用',
                        'その他、当社が不適切と判断する行為',
                      ]),

                      const SizedBox(height: 24),

                      // 第4条
                      _buildSectionTitle('第4条(サービスの提供・変更・中断)'),
                      const SizedBox(height: 8),
                      _buildParagraph(
                        '当社は、ユーザーへの事前通知なく、本アプリの内容を変更または中断する場合があります。',
                      ),

                      const SizedBox(height: 24),

                      // 第5条
                      _buildSectionTitle('第5条(著作権)'),
                      const SizedBox(height: 8),
                      _buildParagraph(
                        '本アプリ内に掲載される画像・音楽・テキスト等の知的財産権は、当社または正当な権利者に帰属します。ユーザーは、これらを許可なく複製・転載できません。',
                      ),

                      const SizedBox(height: 24),

                      // 第6条
                      _buildSectionTitle('第6条(免責事項)'),
                      const SizedBox(height: 8),
                      _buildNumberedList([
                        '当社は、ユーザー間または第三者との間で生じたトラブルについて一切責任を負いません。',
                        '通信環境や端末の不具合等によって生じた損害についても、当社は責任を負いません。',
                      ]),

                      const SizedBox(height: 24),

                      // 第7条
                      _buildSectionTitle('第7条(退会)'),
                      const SizedBox(height: 8),
                      _buildParagraph(
                        'ユーザーは、アプリ内の設定またはお問い合わせを通じて退会をすることができます。',
                      ),
                      _buildParagraph(
                        '退会時、登録データは一定期間後に削除されます。',
                      ),

                      const SizedBox(height: 24),

                      // 第8条
                      _buildSectionTitle('第8条(利用停止・登録抹消)'),
                      const SizedBox(height: 8),
                      _buildParagraph(
                        '当社は、ユーザーが本規約に違反した場合、事前通知なくアカウントを停止または削除することができます。',
                      ),

                      const SizedBox(height: 24),

                      // 第9条
                      _buildSectionTitle('第9条(準拠法・管轄)'),
                      const SizedBox(height: 8),
                      _buildParagraph(
                        '本規約は日本法を準拠法とし、本アプリに関する紛争は東京地方裁判所を専属的管轄とします。',
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

import 'package:flutter/material.dart';
import '../constants/app_colors.dart';
import '../constants/app_text_styles.dart';
import '../constants/app_dimensions.dart';

/// 利用規約画面
class TermsOfServiceScreen extends StatelessWidget {
  const TermsOfServiceScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close, color: AppColors.textPrimary),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          '利用規約',
          style: TextStyle(
            color: AppColors.textPrimary,
            fontSize: 18,
            fontWeight: FontWeight.w600,
          ),
        ),
        centerTitle: true,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppDimensions.paddingLarge),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildTitle('15s利用規約'),
              const SizedBox(height: AppDimensions.paddingMedium),
              _buildBodyText(
                'この利用規約（以下「本規約」）は、15s（以下「本アプリ」）の利用規約を定めるものです。ユーザーは、本アプリを利用することにより、本規約に同意したものとみなします。',
              ),
              const SizedBox(height: AppDimensions.paddingLarge),
              _buildSectionTitle('第1条（適用）'),
              _buildBodyText(
                '本規約は、ユーザーと当初との間の本アプリの利用に関する一切の関係に適用されます。',
              ),
              const SizedBox(height: AppDimensions.paddingLarge),
              _buildSectionTitle('第2条（登録）'),
              _buildBodyText(
                '1. 本アプリの利用には、電話番号認証によるアカウント登録が必要です。\n'
                '2. 登録内容に虚偽や不備がある場合、当社は登録を拒否または削除できるものとします。',
              ),
              const SizedBox(height: AppDimensions.paddingLarge),
              _buildSectionTitle('第3条（禁止事項）'),
              _buildBodyText(
                'ユーザーは、以下の行為を行ってはなりません。\n\n'
                '1. 法令または公序良俗に違反する行為\n'
                '2. 他人への誹謗中傷やプライバシー侵害\n'
                '3. スパム行為、営業・広告目的の投稿\n'
                '4. 著作権・肖像権などの第三者の権利を侵害する行為\n'
                '5. アプリの運営を妨げる行為（リバースエンジニアリング等）\n'
                '6. 不正ログインや他人のアカウント使用\n'
                '7. その他、当社が不適切と判断する行為',
              ),
              const SizedBox(height: AppDimensions.paddingLarge),
              _buildSectionTitle('第4条（サービスの提供・変更・中断）'),
              _buildBodyText(
                '当社は、ユーザーへの事前通知なく、本アプリの内容を変更または中断する場合があります。',
              ),
              const SizedBox(height: AppDimensions.paddingLarge),
              _buildSectionTitle('第5条（著作権）'),
              _buildBodyText(
                '本アプリ内に掲載される画像・音楽・テキスト等の知的財産権は、当初または正当な権利者に帰属します。ユーザーは、これらを許可なく複製・転載できません。',
              ),
              const SizedBox(height: AppDimensions.paddingLarge),
              _buildSectionTitle('第6条（免責事項）'),
              _buildBodyText(
                '1. 当社は、ユーザー間または第三者との間で生じたトラブルについて一切責任を負いません。\n'
                '2. 通信環境や端末の不具合等によって生じた損害についても、当社は責任を負いません。',
              ),
              const SizedBox(height: AppDimensions.paddingLarge),
              _buildSectionTitle('第7条（退会）'),
              _buildBodyText(
                'ユーザーは、アプリ内の設定またはお問い合わせを通じて退会をすることができます。退会時、登録データは一定期間後に削除されます。',
              ),
              const SizedBox(height: AppDimensions.paddingLarge),
              _buildSectionTitle('第8条（利用停止・登録抹消）'),
              _buildBodyText(
                '当社は、ユーザーが本規約に違反した場合、事前通知なくアカウントを停止または削除することができます。',
              ),
              const SizedBox(height: AppDimensions.paddingLarge),
              _buildSectionTitle('第9条（準拠法・管轄）'),
              _buildBodyText(
                '本規約は日本法を準拠法とし、本アプリに関する紛争は東京地方裁判所を専属的管轄とします。',
              ),
              const SizedBox(height: AppDimensions.paddingXLarge),
              _buildBodyText(
                '制定日：2026年4月1日\n'
                '運営者：15s運営チーム（FIFTEENs）\n'
                '責任者：後藤　太郎\n'
                '所在地：東京都渋谷区\n'
                'お問い合わせ：support@15s.app',
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 12,
                ),
              ),
              const SizedBox(height: AppDimensions.paddingXLarge),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTitle(String text) {
    return Text(
      text,
      style: const TextStyle(
        color: AppColors.textPrimary,
        fontSize: 24,
        fontWeight: FontWeight.bold,
      ),
    );
  }

  Widget _buildSectionTitle(String text) {
    return Text(
      text,
      style: const TextStyle(
        color: AppColors.textPrimary,
        fontSize: 18,
        fontWeight: FontWeight.w600,
      ),
    );
  }

  Widget _buildBodyText(String text, {TextStyle? style}) {
    return Text(
      text,
      style: style ??
          const TextStyle(
            color: AppColors.textPrimary,
            fontSize: 14,
            height: 1.6,
          ),
    );
  }
}

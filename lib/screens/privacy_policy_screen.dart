import 'package:flutter/material.dart';
import '../constants/app_colors.dart';
import '../constants/app_dimensions.dart';

/// プライバシーポリシー画面
class PrivacyPolicyScreen extends StatelessWidget {
  const PrivacyPolicyScreen({super.key});

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
          'プライバシーポリシー',
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
              _buildTitle('15sプライバシーポリシー'),
              const SizedBox(height: AppDimensions.paddingMedium),
              _buildBodyText(
                '15s（以下「本アプリ」）の運営者（以下「当社」）は、本アプリを利用するユーザー（以下「ユーザー」）の個人情報を保護することを重要な責務と考え、以下の通りプライバシーポリシー（以下「本ポリシー」）を定めます。',
              ),
              const SizedBox(height: AppDimensions.paddingLarge),
              _buildSectionTitle('第1条（取得する情報）'),
              _buildBodyText(
                '本アプリは、ユーザー登録およびサービス利用の際に、以下の情報を取得する場合があります。\n\n'
                '1. 電話番号（SMS認証のため）\n'
                '2. 氏名、ユーザーネーム、自己紹介文、プロフィール画像などの登録情報\n'
                '3. 投稿コンテンツ（音楽・画像・コメント・Vibe設定など）\n'
                '4. 利用履歴・アクセスログ・端末情報\n'
                '5. Apple MusicまたはSpotifyアカウント連携情報（連携認証トークン等）',
              ),
              const SizedBox(height: AppDimensions.paddingLarge),
              _buildSectionTitle('第2条（利用目的）'),
              _buildBodyText(
                '当社は、取得した個人情報を以下の目的で利用します。\n\n'
                '1. 本アプリの提供および運営のため\n'
                '2. ユーザー認証およびアカウント管理のため\n'
                '3. 投稿コンテンツの表示・共有機能の実現のため\n'
                '4. お問い合わせ・サポート対応のため\n'
                '5. 不正利用防止・セキュリティ強化のため\n'
                '6. 本アプリの改善・新機能開発・利用状況分析のため',
              ),
              const SizedBox(height: AppDimensions.paddingLarge),
              _buildSectionTitle('第3条（第三者提供）'),
              _buildBodyText(
                '当社は、法令に基づく場合を除き、ユーザーの同意なく個人情報を第三者に提供いたしません。',
              ),
              const SizedBox(height: AppDimensions.paddingLarge),
              _buildSectionTitle('第4条（外部サービスの利用）'),
              _buildBodyText(
                '・Firebase Authentication / Firestore / Storage (Google LLC)\n'
                '・Apple Music API (Apple Inc.)\n'
                '・Spotify Web API (Spotify AB)\n\n'
                'これらのサービスによって収集されたデータは、各社のプライバシーポリシーに従って管理されます。',
              ),
              const SizedBox(height: AppDimensions.paddingLarge),
              _buildSectionTitle('第5条（個人情報の管理）'),
              _buildBodyText(
                '当社は、個人情報の漏洩、紛失、改ざんを防止するため、適切な安全対策を講じます。',
              ),
              const SizedBox(height: AppDimensions.paddingLarge),
              _buildSectionTitle('第6条（個人情報の開示・訂正・削除）'),
              _buildBodyText(
                'ユーザーは、アプリ内またはサポート窓口を通じて、自身の個人情報の開示・訂正・削除を求めることができます。',
              ),
              const SizedBox(height: AppDimensions.paddingLarge),
              _buildSectionTitle('第7条（未成年者の利用）'),
              _buildBodyText(
                '未成年ユーザーは、保護者の同意を得た上で本アプリを利用してください。',
              ),
              const SizedBox(height: AppDimensions.paddingLarge),
              _buildSectionTitle('第8条（プライバシーポリシーの変更）'),
              _buildBodyText(
                '本ポリシーの内容は、法令その他の必要に応じて改定されることがあります。改定後の内容は、本アプリ内またはウェブサイトに掲載した時点で効力を生じます。',
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

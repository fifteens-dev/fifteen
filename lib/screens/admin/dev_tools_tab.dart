import 'package:flutter/material.dart';
import '../../constants/app_colors.dart';
import '../../constants/app_text_styles.dart';
import '../../constants/app_dimensions.dart';
import '../../widgets/primary_button.dart';
import '../../utils/setup_test_data.dart';
import '../../services/invite_code_service.dart';

/// 開発者ツールタブ（管理者パネル内）
class DevToolsTab extends StatefulWidget {
  const DevToolsTab({super.key});

  @override
  State<DevToolsTab> createState() => _DevToolsTabState();
}

class _DevToolsTabState extends State<DevToolsTab> {
  final SetupTestData _setupTestData = SetupTestData();
  final InviteCodeService _inviteCodeService = InviteCodeService();
  final TextEditingController _codeController = TextEditingController();
  final TextEditingController _maxUsesController = TextEditingController(text: '10');
  bool _isLoading = false;
  String _statusMessage = '';

  Future<void> _executeAction({
    required String loadingMessage,
    required String successMessage,
    required String snackBarMessage,
    required Future<void> Function() action,
  }) async {
    setState(() {
      _isLoading = true;
      _statusMessage = loadingMessage;
    });

    try {
      await action();

      if (mounted) {
        setState(() {
          _isLoading = false;
          _statusMessage = successMessage;
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(snackBarMessage),
            backgroundColor: AppColors.success,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _statusMessage = '❌ エラー: $e';
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('エラーが発生しました: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppDimensions.paddingLarge,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 20),

            if (_statusMessage.isNotEmpty) ...[
              Container(
                padding: const EdgeInsets.all(AppDimensions.paddingMedium),
                decoration: BoxDecoration(
                  color: _statusMessage.contains('✅')
                      ? AppColors.success.withOpacity(0.1)
                      : AppColors.error.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: _statusMessage.contains('✅')
                        ? AppColors.success
                        : AppColors.error,
                  ),
                ),
                child: Text(
                  _statusMessage,
                  style: TextStyle(
                    color: _statusMessage.contains('✅')
                        ? AppColors.success
                        : AppColors.error,
                    fontSize: 14,
                  ),
                ),
              ),
              const SizedBox(height: AppDimensions.paddingLarge),
            ],

            // ダミーユーザーセクション
            const Text('ダミーユーザー', style: AppTextStyles.heading),
            const SizedBox(height: AppDimensions.paddingMedium),
            PrimaryButton(
              text: 'ダミーユーザーを作成',
              onPressed: () => _executeAction(
                loadingMessage: 'ダミーユーザーを作成中...',
                successMessage: '✅ ダミーユーザーの作成が完了しました！',
                snackBarMessage: 'ダミーユーザーが作成されました',
                action: _setupTestData.createDummyUsers,
              ),
              isLoading: _isLoading,
            ),
            const SizedBox(height: AppDimensions.paddingMedium),
            PrimaryButton(
              text: 'ダミーユーザーの投稿を作成（Spotify連携）',
              onPressed: () => _executeAction(
                loadingMessage: 'Spotifyから楽曲を検索中...',
                successMessage: '✅ ダミーユーザーの投稿データが作成されました！',
                snackBarMessage: 'ダミーユーザーの投稿データが作成されました',
                action: _setupTestData.createDummyUserPosts,
              ),
              isLoading: _isLoading,
            ),
            const SizedBox(height: AppDimensions.paddingMedium),
            PrimaryButton(
              text: 'ダミーいいねをセットアップ（全員相互）',
              onPressed: () => _executeAction(
                loadingMessage: 'ダミーいいねをセットアップ中...',
                successMessage: '✅ ダミーいいねのセットアップが完了しました！',
                snackBarMessage: '全ダミーユーザーが相互に全投稿をいいねしました',
                action: _setupTestData.setupDummyLikes,
              ),
              isLoading: _isLoading,
            ),
            const SizedBox(height: AppDimensions.paddingMedium),
            PrimaryButton(
              text: 'ダミーコメントをセットアップ',
              onPressed: () => _executeAction(
                loadingMessage: 'ダミーコメントを作成中...',
                successMessage: '✅ ダミーコメントのセットアップが完了しました！',
                snackBarMessage: 'コメント数に合わせてダミーコメントが作成されました',
                action: _setupTestData.setupDummyComments,
              ),
              isLoading: _isLoading,
            ),
            const SizedBox(height: AppDimensions.paddingMedium),

            // 招待コード作成セクション
            const Divider(color: AppColors.border),
            const SizedBox(height: AppDimensions.paddingMedium),
            const Text('招待コード作成', style: AppTextStyles.heading),
            const SizedBox(height: AppDimensions.paddingMedium),
            TextField(
              controller: _codeController,
              style: const TextStyle(color: AppColors.textPrimary),
              textCapitalization: TextCapitalization.characters,
              decoration: InputDecoration(
                labelText: '招待コード',
                labelStyle: const TextStyle(color: AppColors.textSecondary),
                hintText: '例: BETA2026',
                hintStyle: TextStyle(color: AppColors.textSecondary.withOpacity(0.5)),
                enabledBorder: const OutlineInputBorder(
                  borderSide: BorderSide(color: AppColors.border),
                ),
                focusedBorder: const OutlineInputBorder(
                  borderSide: BorderSide(color: AppColors.accentBlue),
                ),
              ),
            ),
            const SizedBox(height: AppDimensions.paddingMedium),
            TextField(
              controller: _maxUsesController,
              style: const TextStyle(color: AppColors.textPrimary),
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: '使用可能回数',
                labelStyle: const TextStyle(color: AppColors.textSecondary),
                hintText: '例: 10',
                hintStyle: TextStyle(color: AppColors.textSecondary.withOpacity(0.5)),
                enabledBorder: const OutlineInputBorder(
                  borderSide: BorderSide(color: AppColors.border),
                ),
                focusedBorder: const OutlineInputBorder(
                  borderSide: BorderSide(color: AppColors.accentBlue),
                ),
              ),
            ),
            const SizedBox(height: AppDimensions.paddingMedium),
            PrimaryButton(
              text: '招待コードを作成',
              onPressed: () {
                final code = _codeController.text.trim();
                final maxUses = int.tryParse(_maxUsesController.text.trim()) ?? 10;
                if (code.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('招待コードを入力してください'),
                      backgroundColor: AppColors.error,
                    ),
                  );
                  return;
                }
                _executeAction(
                  loadingMessage: '招待コード「$code」を作成中...',
                  successMessage: '✅ 招待コード「$code」を作成しました（$maxUses回使用可能）',
                  snackBarMessage: '招待コード「$code」が作成されました',
                  action: () => _inviteCodeService.createInviteCodeWithMaxUses(code, maxUses),
                );
              },
              isLoading: _isLoading,
            ),
            const SizedBox(height: AppDimensions.paddingMedium),

            // データ削除セクション
            const Divider(color: AppColors.border),
            const SizedBox(height: AppDimensions.paddingMedium),
            const Text('データ削除', style: AppTextStyles.heading),
            const SizedBox(height: AppDimensions.paddingMedium),
            OutlinedButton(
              onPressed: _isLoading ? null : () => _executeAction(
                loadingMessage: 'ダミー以外の投稿を削除中...',
                successMessage: '✅ ダミー以外の投稿を削除しました！',
                snackBarMessage: 'ダミー以外の投稿を削除しました',
                action: _setupTestData.deleteNonDummyPosts,
              ),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.error,
                side: const BorderSide(color: AppColors.error),
                minimumSize: const Size(double.infinity, 50),
              ),
              child: const Text('ダミー以外の投稿を削除'),
            ),
            const SizedBox(height: AppDimensions.paddingMedium),
            OutlinedButton(
              onPressed: _isLoading ? null : () => _executeAction(
                loadingMessage: '古いテスト投稿を削除中...',
                successMessage: '✅ 古いテスト投稿が削除されました！',
                snackBarMessage: '古いテスト投稿が削除されました',
                action: _setupTestData.deleteOldTestPosts,
              ),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.error,
                side: const BorderSide(color: AppColors.error),
                minimumSize: const Size(double.infinity, 50),
              ),
              child: const Text('古いテスト投稿を削除'),
            ),
            const SizedBox(height: AppDimensions.paddingMedium),

            // 画面遷移セクション
            const Divider(color: AppColors.border),
            const SizedBox(height: AppDimensions.paddingMedium),
            const Text('画面遷移', style: AppTextStyles.heading),
            const SizedBox(height: AppDimensions.paddingMedium),
            OutlinedButton(
              onPressed: () => Navigator.pushNamed(context, '/phone-auth'),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.textPrimary,
                side: const BorderSide(color: AppColors.border),
                minimumSize: const Size(double.infinity, 50),
              ),
              child: const Text('電話番号認証画面へ'),
            ),
            const SizedBox(height: AppDimensions.paddingMedium),
            OutlinedButton(
              onPressed: () => Navigator.pushNamed(context, '/home'),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.textPrimary,
                side: const BorderSide(color: AppColors.border),
                minimumSize: const Size(double.infinity, 50),
              ),
              child: const Text('ホーム画面へ'),
            ),
            const SizedBox(height: AppDimensions.paddingXLarge),
          ],
        ),
      ),
    );
  }
}

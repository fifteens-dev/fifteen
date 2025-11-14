import 'package:flutter/material.dart';
import '../constants/app_colors.dart';
import '../constants/app_text_styles.dart';
import '../constants/app_dimensions.dart';
import '../widgets/primary_button.dart';
import '../utils/setup_test_data.dart';

/// 開発者ツール画面（デバッグビルドのみ）
class DevToolsScreen extends StatefulWidget {
  const DevToolsScreen({super.key});

  @override
  State<DevToolsScreen> createState() => _DevToolsScreenState();
}

class _DevToolsScreenState extends State<DevToolsScreen> {
  final SetupTestData _setupTestData = SetupTestData();
  bool _isLoading = false;
  String _statusMessage = '';

  Future<void> _handleSetupTestData() async {
    setState(() {
      _isLoading = true;
      _statusMessage = 'テストデータをセットアップ中...';
    });

    try {
      await _setupTestData.setupAllTestData();

      if (mounted) {
        setState(() {
          _isLoading = false;
          _statusMessage = '✅ テストデータのセットアップが完了しました！';
        });

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('テスト用招待コードが作成されました'),
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

  Future<void> _handleCreateTestPosts() async {
    setState(() {
      _isLoading = true;
      _statusMessage = 'テスト用投稿データを作成中...';
    });

    try {
      await _setupTestData.createTestPosts();

      if (mounted) {
        setState(() {
          _isLoading = false;
          _statusMessage = '✅ テスト用投稿データの作成が完了しました！';
        });

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('テスト用投稿データが作成されました'),
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
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios, color: AppColors.textPrimary),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text('開発者ツール', style: AppTextStyles.heading),
        centerTitle: true,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppDimensions.paddingLarge,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
              const SizedBox(height: 40),
              const Text(
                'テストデータのセットアップ',
                style: AppTextStyles.heading,
              ),
              const SizedBox(height: AppDimensions.paddingMedium),
              const Text(
                'Firestoreにテスト用の招待コードを作成します。',
                style: AppTextStyles.body,
              ),
              const SizedBox(height: AppDimensions.paddingLarge),
              Container(
                padding: const EdgeInsets.all(AppDimensions.paddingMedium),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppColors.border),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '作成される招待コード:',
                      style: TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    _buildCodeItem('TEST123'),
                    _buildCodeItem('WELCOME'),
                    _buildCodeItem('HELLO15S'),
                  ],
                ),
              ),
              const SizedBox(height: AppDimensions.paddingLarge),
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
              PrimaryButton(
                text: 'テストデータを作成',
                onPressed: _handleSetupTestData,
                isLoading: _isLoading,
              ),
              const SizedBox(height: AppDimensions.paddingMedium),
              const Text(
                '注意: このボタンは開発中のテスト用です。本番環境では使用しないでください。',
                style: TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 12,
                ),
              ),
              const SizedBox(height: AppDimensions.paddingXLarge),
              const Divider(color: AppColors.border),
              const SizedBox(height: AppDimensions.paddingMedium),

              // テスト用投稿データ作成セクション
              const Text(
                'テスト用投稿データの作成',
                style: AppTextStyles.heading,
              ),
              const SizedBox(height: AppDimensions.paddingMedium),
              const Text(
                'タイムラインに表示するテスト用の投稿データを作成します。',
                style: AppTextStyles.body,
              ),
              const SizedBox(height: AppDimensions.paddingLarge),
              PrimaryButton(
                text: 'テスト用投稿データを作成',
                onPressed: _handleCreateTestPosts,
                isLoading: _isLoading,
              ),
              const SizedBox(height: AppDimensions.paddingXLarge),
              const Divider(color: AppColors.border),
              const SizedBox(height: AppDimensions.paddingMedium),

              // ナビゲーションセクション
              const Text(
                '画面遷移',
                style: AppTextStyles.heading,
              ),
              const SizedBox(height: AppDimensions.paddingMedium),
              OutlinedButton(
                onPressed: () {
                  Navigator.pushNamed(context, '/');
                },
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.textPrimary,
                  side: const BorderSide(color: AppColors.border),
                  minimumSize: const Size(double.infinity, 50),
                ),
                child: const Text('電話番号認証画面へ'),
              ),
              const SizedBox(height: AppDimensions.paddingMedium),
              OutlinedButton(
                onPressed: () {
                  Navigator.pushNamed(context, '/home');
                },
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.textPrimary,
                  side: const BorderSide(color: AppColors.border),
                  minimumSize: const Size(double.infinity, 50),
                ),
                child: const Text('ホーム画面へ'),
              ),
            ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCodeItem(String code) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          const Icon(
            Icons.check_circle_outline,
            color: AppColors.success,
            size: 20,
          ),
          const SizedBox(width: 8),
          Text(
            code,
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontSize: 16,
              fontFamily: 'monospace',
            ),
          ),
        ],
      ),
    );
  }
}

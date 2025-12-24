import 'package:flutter/material.dart';
import '../constants/app_colors.dart';
import '../constants/app_text_styles.dart';
import '../constants/app_dimensions.dart';
import '../widgets/primary_button.dart';
import '../utils/setup_test_data.dart';
import '../utils/create_initial_vibe_topics.dart';

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


  Future<void> _handleCreateDummyUsers() async {
    setState(() {
      _isLoading = true;
      _statusMessage = 'ダミーユーザーを作成中...';
    });

    try {
      await _setupTestData.createDummyUsers();

      if (mounted) {
        setState(() {
          _isLoading = false;
          _statusMessage = '✅ ダミーユーザーの作成が完了しました！';
        });

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('ダミーユーザーが作成されました'),
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

  Future<void> _handleCreateDummyUserPosts() async {
    setState(() {
      _isLoading = true;
      _statusMessage = 'Spotifyから楽曲を検索中...';
    });

    try {
      await _setupTestData.createDummyUserPosts();

      if (mounted) {
        setState(() {
          _isLoading = false;
          _statusMessage = '✅ ダミーユーザーの投稿データが作成されました！';
        });

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('ダミーユーザーの投稿データが作成されました'),
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

  Future<void> _handleDeleteOldTestPosts() async {
    setState(() {
      _isLoading = true;
      _statusMessage = '古いテスト投稿を削除中...';
    });

    try {
      await _setupTestData.deleteOldTestPosts();

      if (mounted) {
        setState(() {
          _isLoading = false;
          _statusMessage = '✅ 古いテスト投稿が削除されました！';
        });

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('古いテスト投稿が削除されました'),
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

  Future<void> _handleCreateInitialVibeTopics() async {
    setState(() {
      _isLoading = true;
      _statusMessage = '初期Vibeお題を作成中...';
    });

    try {
      await createInitialVibeTopics();

      if (mounted) {
        setState(() {
          _isLoading = false;
          _statusMessage = '✅ 今日のお題と投票用お題が作成されました！';
        });

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Vibeお題が作成されました'),
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

  Future<void> _handleCreateAllVotingTopics() async {
    setState(() {
      _isLoading = true;
      _statusMessage = '全てのお題候補を作成中...';
    });

    try {
      await createAllVotingTopics();

      if (mounted) {
        setState(() {
          _isLoading = false;
          _statusMessage = '✅ 全てのお題候補が作成されました！';
        });

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('全てのお題候補が作成されました'),
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

              // ダミーユーザー作成セクション
              const Text(
                'ダミーユーザーの作成',
                style: AppTextStyles.heading,
              ),
              const SizedBox(height: AppDimensions.paddingMedium),
              const Text(
                'Figmaデザインに基づいたダミーユーザー（m.by__sanaなど）を作成します。',
                style: AppTextStyles.body,
              ),
              const SizedBox(height: AppDimensions.paddingLarge),
              PrimaryButton(
                text: 'ダミーユーザーを作成',
                onPressed: _handleCreateDummyUsers,
                isLoading: _isLoading,
              ),
              const SizedBox(height: AppDimensions.paddingMedium),
              PrimaryButton(
                text: 'ダミーユーザーの投稿を作成（Spotify連携）',
                onPressed: _handleCreateDummyUserPosts,
                isLoading: _isLoading,
              ),
              const SizedBox(height: AppDimensions.paddingMedium),
              const Text(
                'Spotifyから実際の楽曲データを取得して投稿を作成します。',
                style: TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 12,
                ),
              ),
              const SizedBox(height: AppDimensions.paddingXLarge),
              const Divider(color: AppColors.border),
              const SizedBox(height: AppDimensions.paddingMedium),

              // 古いテスト投稿削除セクション
              const Text(
                '古いテスト投稿の削除',
                style: AppTextStyles.heading,
              ),
              const SizedBox(height: AppDimensions.paddingMedium),
              const Text(
                'ユーザーが存在しない古いテスト投稿（いとしのエリー、Lemon、きらり等）を削除します。',
                style: AppTextStyles.body,
              ),
              const SizedBox(height: AppDimensions.paddingLarge),
              Container(
                padding: const EdgeInsets.all(AppDimensions.paddingMedium),
                decoration: BoxDecoration(
                  color: AppColors.error.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppColors.error.withOpacity(0.3)),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.warning_amber_rounded,
                      color: AppColors.error,
                      size: 20,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: const Text(
                        'test_user_1/2/3 の投稿がすべて削除されます',
                        style: TextStyle(
                          color: AppColors.error,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppDimensions.paddingLarge),
              OutlinedButton(
                onPressed: _isLoading ? null : _handleDeleteOldTestPosts,
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.error,
                  side: const BorderSide(color: AppColors.error),
                  minimumSize: const Size(double.infinity, 50),
                ),
                child: const Text('古いテスト投稿を削除'),
              ),
              const SizedBox(height: AppDimensions.paddingXLarge),
              const Divider(color: AppColors.border),
              const SizedBox(height: AppDimensions.paddingMedium),

              // Vibeお題作成セクション
              const Text(
                'Vibeお題の作成',
                style: AppTextStyles.heading,
              ),
              const SizedBox(height: AppDimensions.paddingMedium),
              const Text(
                '今日のVibeお題と明日の投票用お題を作成します。',
                style: AppTextStyles.body,
              ),
              const SizedBox(height: AppDimensions.paddingLarge),
              PrimaryButton(
                text: '初期Vibeお題を作成（今日+明日の4候補）',
                onPressed: _handleCreateInitialVibeTopics,
                isLoading: _isLoading,
              ),
              const SizedBox(height: AppDimensions.paddingMedium),
              OutlinedButton(
                onPressed: _isLoading ? null : _handleCreateAllVotingTopics,
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.textPrimary,
                  side: const BorderSide(color: AppColors.border),
                  minimumSize: const Size(double.infinity, 50),
                ),
                child: const Text('全てのお題候補を作成（20個）'),
              ),
              const SizedBox(height: AppDimensions.paddingMedium),
              const Text(
                '※ 事前定義されたお題リストから自動的に選択されます',
                style: TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 12,
                ),
              ),
              const SizedBox(height: AppDimensions.paddingXLarge),
              const Divider(color: AppColors.border),
              const SizedBox(height: AppDimensions.paddingMedium),

              // 開発者用電話番号セクション
              const Text(
                '開発者用電話番号',
                style: AppTextStyles.heading,
              ),
              const SizedBox(height: AppDimensions.paddingMedium),
              const Text(
                '電話番号認証画面で以下の特殊な電話番号を入力すると、開発用のショートカット機能が使えます。\n\n※ Web環境では11111111111を使用して認証をスキップしてください（Firebase認証なし）。',
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
                    _buildPhoneNumberItem(
                      '00000000000',
                      '全ての認証フローをスキップしてホーム画面へ直接移動',
                      Icons.home,
                    ),
                    const SizedBox(height: 12),
                    _buildPhoneNumberItem(
                      '11111111111',
                      '認証をスキップして招待コード画面へ移動（Web開発用）',
                      Icons.confirmation_number,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppDimensions.paddingXLarge),
              const Divider(color: AppColors.border),
              const SizedBox(height: AppDimensions.paddingMedium),

              // 開発者用招待コードセクション
              const Text(
                '開発者用招待コード',
                style: AppTextStyles.heading,
              ),
              const SizedBox(height: AppDimensions.paddingMedium),
              const Text(
                '招待コード画面で以下の特殊なコードを入力すると、Firestore検証をスキップしてUIテストができます。',
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
                    _buildPhoneNumberItem(
                      'DEVMODE',
                      'Firestore検証をスキップして名前入力画面へ移動',
                      Icons.developer_mode,
                    ),
                    const SizedBox(height: 12),
                    _buildPhoneNumberItem(
                      'UITEST',
                      'Firestore検証をスキップして名前入力画面へ移動',
                      Icons.phone_android,
                    ),
                  ],
                ),
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

  Widget _buildPhoneNumberItem(String phoneNumber, String description, IconData icon) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          icon,
          color: AppColors.accent,
          size: 24,
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                phoneNumber,
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  fontFamily: 'monospace',
                ),
              ),
              const SizedBox(height: 4),
              Text(
                description,
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 14,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

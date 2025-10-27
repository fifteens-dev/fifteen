import 'package:flutter/material.dart';
import '../constants/app_colors.dart';
import '../constants/app_text_styles.dart';
import '../constants/app_dimensions.dart';
import '../widgets/common_input_field.dart';
import '../widgets/primary_button.dart';

/// ユーザーネーム作成画面
class UsernameCreationScreen extends StatefulWidget {
  const UsernameCreationScreen({super.key});

  @override
  State<UsernameCreationScreen> createState() => _UsernameCreationScreenState();
}

class _UsernameCreationScreenState extends State<UsernameCreationScreen> {
  final TextEditingController _usernameController = TextEditingController();
  bool _isLoading = false;

  @override
  void dispose() {
    _usernameController.dispose();
    super.dispose();
  }

  void _handleNext() {
    final username = _usernameController.text.trim();
    if (username.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('ユーザーネームを入力してください'),
          backgroundColor: AppColors.error,
        ),
      );
      return;
    }

    // ユーザーネームのバリデーション（英数字とアンダースコアのみ）
    if (!RegExp(r'^[a-zA-Z0-9_]+$').hasMatch(username)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('ユーザーネームは英数字とアンダースコアのみ使用できます'),
          backgroundColor: AppColors.error,
        ),
      );
      return;
    }

    setState(() {
      _isLoading = true;
    });

    // TODO: ユーザーネームの重複チェックと保存
    Future.delayed(const Duration(seconds: 1), () {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
        // TODO: プロフィール設定画面への遷移
        Navigator.pushNamed(context, '/profile-setup');
      }
    });
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
        title: const Text('15s', style: AppTextStyles.appTitle),
        centerTitle: true,
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppDimensions.paddingLarge,
          ),
          child: Column(
            children: [
              const SizedBox(height: 60),
              const Text(
                'ユーザーネームを作成',
                style: AppTextStyles.heading,
              ),
              const SizedBox(height: AppDimensions.paddingLarge),
              CommonInputField(
                controller: _usernameController,
                hintText: 'ユーザーネーム',
                keyboardType: TextInputType.text,
              ),
              const SizedBox(height: AppDimensions.paddingLarge),
              PrimaryButton(
                text: '次へ',
                onPressed: _handleNext,
                isLoading: _isLoading,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

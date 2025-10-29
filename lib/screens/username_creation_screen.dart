import 'package:flutter/material.dart';
import '../constants/app_colors.dart';
import '../constants/app_text_styles.dart';
import '../constants/app_dimensions.dart';
import '../widgets/common_input_field.dart';
import '../widgets/primary_button.dart';
import '../services/user_service.dart';
import '../services/auth_service.dart';

/// ユーザーネーム作成画面
class UsernameCreationScreen extends StatefulWidget {
  const UsernameCreationScreen({super.key});

  @override
  State<UsernameCreationScreen> createState() => _UsernameCreationScreenState();
}

class _UsernameCreationScreenState extends State<UsernameCreationScreen> {
  final TextEditingController _usernameController = TextEditingController();
  final UserService _userService = UserService();
  final AuthService _authService = AuthService();
  bool _isLoading = false;

  @override
  void dispose() {
    _usernameController.dispose();
    super.dispose();
  }

  Future<void> _handleNext() async {
    final username = _usernameController.text.trim().toLowerCase();
    if (username.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('ユーザーネームを入力してください'),
            backgroundColor: AppColors.error,
          ),
        );
      }
      return;
    }

    // ユーザーネームのバリデーション（英数字とアンダースコアのみ）
    if (!RegExp(r'^[a-zA-Z0-9_]+$').hasMatch(username)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('ユーザーネームは英数字とアンダースコアのみ使用できます'),
            backgroundColor: AppColors.error,
          ),
        );
      }
      return;
    }

    // 長さのバリデーション
    if (username.length < 3 || username.length > 20) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('ユーザーネームは3〜20文字で設定してください'),
            backgroundColor: AppColors.error,
          ),
        );
      }
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      // ユーザーネームの重複チェック
      final isAvailable = await _userService.isUsernameAvailable(username);

      if (!isAvailable) {
        if (mounted) {
          setState(() {
            _isLoading = false;
          });
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('このユーザーネームは既に使用されています'),
              backgroundColor: AppColors.error,
            ),
          );
        }
        return;
      }

      // ユーザーネームを保存
      final currentUser = _authService.currentUser;
      if (currentUser != null) {
        await _userService.updateUser(
          uid: currentUser.uid,
          username: username,
        );

        if (mounted) {
          setState(() {
            _isLoading = false;
          });
          // プロフィール設定画面へ遷移
          Navigator.pushReplacementNamed(context, '/profile-setup');
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('ユーザーネームの保存に失敗しました'),
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

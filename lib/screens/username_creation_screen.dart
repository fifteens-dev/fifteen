import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../constants/app_colors.dart';
import '../constants/app_text_styles.dart';
import '../constants/app_dimensions.dart';
import '../widgets/common_input_field.dart';
import '../widgets/primary_button.dart';
import '../services/user_service.dart';
import '../services/auth_service.dart';
import '../widgets/common/app_toast.dart';

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
  String _name = '';

  @override
  void initState() {
    super.initState();
    // 前の画面から名前を受け取る
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final args = ModalRoute.of(context)?.settings.arguments as Map<String, dynamic>?;
      if (args != null && args['name'] != null) {
        setState(() {
          _name = args['name'];
        });
      }
    });
  }

  @override
  void dispose() {
    _usernameController.dispose();
    super.dispose();
  }

  Future<void> _handleNext() async {
    final username = _usernameController.text.trim().toLowerCase();
    if (username.isEmpty) {
      if (mounted) {
        AppToast.show(context, 'ユーザーネームを入力してください');
      }
      return;
    }

    // ユーザーネームのバリデーション（英数字・アンダースコア・ドット）
    if (!RegExp(r'^[a-zA-Z0-9_.]+$').hasMatch(username)) {
      if (mounted) {
        AppToast.show(context, 'ユーザーネームは英数字・アンダースコア・ドットのみ使用できます');
      }
      return;
    }
    // 長さのバリデーション
    if (username.length < 3 || username.length > 20) {
      if (mounted) {
        AppToast.show(context, 'ユーザーネームは3〜20文字で設定してください');
      }
      return;
    }

    // Web開発用：Firebase認証がない場合はFirestoreへの保存をスキップ
    final currentUser = _authService.currentUser;
    if (currentUser == null) {
      // 認証ユーザーがいない場合は、保存せず次の画面へ（名前とユーザーネームを渡す）
      if (mounted) {
        Navigator.pushReplacementNamed(
          context,
          '/profile-setup',
          arguments: {
            'name': _name,
            'username': username,
          },
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
          AppToast.show(context, 'このユーザーネームは既に使用されています');
        }
        return;
      }

      // ユーザーネームを保存
      await _userService.updateUser(
        uid: currentUser.uid,
        username: username,
      );

      if (mounted) {
        setState(() {
          _isLoading = false;
        });
        // プロフィール設定画面へ遷移（名前とユーザーネームを渡す）
        Navigator.pushNamed(
          context,
          '/profile-setup',
          arguments: {
            'name': _name,
            'username': username,
          },
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
        AppToast.show(context, 'ユーザーネームの保存に失敗しました');
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
                hintText: 'ユーザーネーム（英数字・_・.のみ）',
                keyboardType: TextInputType.visiblePassword,
                autocorrect: false,
                enableSuggestions: false,
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[a-zA-Z0-9_.]')),
                ],
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

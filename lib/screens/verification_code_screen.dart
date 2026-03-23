import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../constants/app_colors.dart';
import '../constants/app_text_styles.dart';
import '../constants/app_dimensions.dart';
import '../widgets/common_input_field.dart';
import '../widgets/primary_button.dart';
import '../constants/app_constants.dart';
import '../services/auth_service.dart';
import '../services/user_service.dart';

/// 認証コード入力画面
class VerificationCodeScreen extends StatefulWidget {
  const VerificationCodeScreen({super.key});

  @override
  State<VerificationCodeScreen> createState() => _VerificationCodeScreenState();
}

class _VerificationCodeScreenState extends State<VerificationCodeScreen> {
  final TextEditingController _codeController = TextEditingController();
  final AuthService _authService = AuthService();
  final UserService _userService = UserService();
  bool _isLoading = false;
  String? _verificationId;
  String? _phoneNumber;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // ルートから引数を取得
    final args = ModalRoute.of(context)?.settings.arguments as Map?;
    if (args != null) {
      _verificationId = args['verificationId'] as String?;
      _phoneNumber = args['phoneNumber'] as String?;
    }
  }

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _handleNext() async {
    final code = _codeController.text.trim();
    if (code.isEmpty || code.length != 6) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('6桁の認証コードを入力してください'),
            backgroundColor: AppColors.error,
          ),
        );
      }
      return;
    }

    if (_verificationId == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('認証情報が見つかりません'),
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
      // 認証コードで認証
      final userCredential = await _authService.signInWithVerificationCode(
        verificationId: _verificationId!,
        smsCode: code,
      );

      if (userCredential != null && userCredential.user != null) {
        final user = userCredential.user!;

        // 既存ユーザーかチェック（直接 doc.exists で確認し getUser の parse 失敗を回避）
        final userDoc = await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .get();

        if (mounted) {
          setState(() {
            _isLoading = false;
          });

          if (userDoc.exists) {
            // 既存ユーザー - 登録進捗に応じてナビゲート
            final data = userDoc.data() ?? {};
            final username = data['username'] as String?;
            final name = data['name'] as String?;

            if (username != null && username.isNotEmpty) {
              // 登録完了 → ホーム
              Navigator.pushReplacementNamed(context, '/home');
            } else if (name != null && name.isNotEmpty) {
              // 名前まで完了 → ユーザーネーム入力へ
              Navigator.pushReplacementNamed(
                context,
                '/username-creation',
                arguments: {'name': name},
              );
            } else {
              // 名前未設定 → 名前入力へ
              Navigator.pushReplacementNamed(context, '/name-input');
            }
          } else {
            // 新規ユーザー - 基本情報をFirestoreに作成
            await _userService.createUser(
              uid: user.uid,
              phoneNumber: _phoneNumber ?? user.phoneNumber ?? '',
            );
            // 公式アカウントを自動フォロー（エラーは無視）
            _userService.followUser(
              currentUserId: user.uid,
              targetUserId: AppConstants.officialAccountUid,
            ).catchError((_) {});
            // 招待コード入力画面へ
            Navigator.pushReplacementNamed(context, '/invite-code');
          }
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.toString().replaceAll('Exception: ', '')),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  void _handleResendCode() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('認証コードを再送信しました'),
        backgroundColor: AppColors.success,
      ),
    );
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
                '認証コードを入力してください',
                style: AppTextStyles.heading,
              ),
              const SizedBox(height: AppDimensions.paddingLarge),
              CommonInputField(
                controller: _codeController,
                hintText: '認証コード',
                keyboardType: TextInputType.number,
                maxLength: 6,
              ),
              const SizedBox(height: AppDimensions.paddingLarge),
              PrimaryButton(
                text: '次へ',
                onPressed: _handleNext,
                isLoading: _isLoading,
              ),
              const SizedBox(height: AppDimensions.paddingMedium),
              TextButton(
                onPressed: _handleResendCode,
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    vertical: AppDimensions.paddingMedium,
                  ),
                ),
                child: const Text(
                  'コードが届かなかった',
                  style: TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 16,
                    decoration: TextDecoration.underline,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../constants/app_colors.dart';
import '../constants/app_text_styles.dart';
import '../constants/app_dimensions.dart';
import '../widgets/phone_input_field.dart';
import '../widgets/primary_button.dart';
import '../services/auth_service.dart';
import '../services/user_service.dart';

/// 電話番号認証画面
class PhoneAuthScreen extends StatefulWidget {
  const PhoneAuthScreen({super.key});

  @override
  State<PhoneAuthScreen> createState() => _PhoneAuthScreenState();
}

class _PhoneAuthScreenState extends State<PhoneAuthScreen> {
  final TextEditingController _phoneController = TextEditingController();
  final AuthService _authService = AuthService();
  final UserService _userService = UserService();
  bool _isLoading = false;
  String _countryCode = '+81';

  @override
  void dispose() {
    _phoneController.dispose();
    super.dispose();
  }

  Future<void> _handleSendVerification() async {
    // 電話番号のバリデーション
    final phoneNumber = _phoneController.text.replaceAll(RegExp(r'\D'), '');

    if (phoneNumber.length != 11) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('正しい電話番号を入力してください'),
            backgroundColor: AppColors.error,
          ),
        );
      }
      return;
    }

    setState(() {
      _isLoading = true;
    });

    // 国際電話番号形式に変換
    final fullPhoneNumber = '$_countryCode${phoneNumber.substring(1)}';

    try {
      await _authService.verifyPhoneNumber(
        phoneNumber: fullPhoneNumber,
        onCodeSent: (verificationId) {
          if (mounted) {
            setState(() {
              _isLoading = false;
            });
            // 認証コード入力画面へ遷移
            Navigator.pushNamed(
              context,
              '/verification',
              arguments: {
                'verificationId': verificationId,
                'phoneNumber': fullPhoneNumber,
              },
            );
          }
        },
        onError: (error) {
          if (mounted) {
            setState(() {
              _isLoading = false;
            });
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(error),
                backgroundColor: AppColors.error,
              ),
            );
          }
        },
        onAutoVerify: (credential) async {
          // 自動認証成功（Android）
          if (mounted) {
            // 現在のユーザーを取得
            final currentUser = FirebaseAuth.instance.currentUser;
            if (currentUser != null) {
              // 既存ユーザーかチェック
              final existingUser = await _userService.getUser(currentUser.uid);

              setState(() {
                _isLoading = false;
              });

              if (existingUser != null) {
                // 既存ユーザー - ホーム画面へ直接遷移
                Navigator.pushReplacementNamed(context, '/home');
              } else {
                // 新規ユーザー - ユーザー情報を作成して招待コード画面へ
                await _userService.createUser(
                  uid: currentUser.uid,
                  phoneNumber: fullPhoneNumber,
                );
                Navigator.pushReplacementNamed(context, '/invite-code');
              }
            } else {
              setState(() {
                _isLoading = false;
              });
              Navigator.pushReplacementNamed(context, '/invite-code');
            }
          }
        },
      );
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('認証の送信に失敗しました'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  void _handleCountryCodeTap() {
    // TODO: 国コード選択ダイアログを実装
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('国コード選択機能は開発中です'),
      ),
    );
  }

  Widget _buildTermsText(BuildContext context) {
    return RichText(
      textAlign: TextAlign.center,
      text: TextSpan(
        style: AppTextStyles.caption,
        children: [
          const TextSpan(text: 'この操作を行うと、私たちの'),
          WidgetSpan(
            child: GestureDetector(
              onTap: () {
                Navigator.pushNamed(context, '/terms-of-service');
              },
              child: const Text(
                '利用規約',
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 12,
                  decoration: TextDecoration.underline,
                  height: 1.5,
                ),
              ),
            ),
          ),
          const TextSpan(text: 'と'),
          WidgetSpan(
            child: GestureDetector(
              onTap: () {
                Navigator.pushNamed(context, '/privacy-policy');
              },
              child: const Text(
                'プライバシーポリシー',
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 12,
                  decoration: TextDecoration.underline,
                  height: 1.5,
                ),
              ),
            ),
          ),
          const TextSpan(text: 'に同意したことになります。'),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppDimensions.paddingLarge,
          ),
          child: Column(
            children: [
              const SizedBox(height: 80),
              // アプリ名
              const Text(
                '15s',
                style: AppTextStyles.appTitle,
              ),
              const SizedBox(height: 80),
              // タイトル
              const Text(
                '電話番号を入力してください',
                style: AppTextStyles.heading,
              ),
              const SizedBox(height: AppDimensions.paddingLarge),
              // 電話番号入力フィールド
              PhoneInputField(
                controller: _phoneController,
                onCountryCodeTap: _handleCountryCodeTap,
              ),
              const SizedBox(height: AppDimensions.paddingLarge),
              // 送信ボタン
              PrimaryButton(
                text: '認証メッセージを送信',
                onPressed: _handleSendVerification,
                isLoading: _isLoading,
              ),
              const SizedBox(height: AppDimensions.paddingMedium),
              // 利用規約テキスト
              _buildTermsText(context),
            ],
          ),
        ),
      ),
    );
  }
}

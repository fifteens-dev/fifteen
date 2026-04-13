import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import '../constants/app_colors.dart';
import '../constants/app_text_styles.dart';
import '../constants/app_dimensions.dart';
import '../widgets/common_input_field.dart';
import '../widgets/primary_button.dart';
import '../services/user_service.dart';
import '../services/auth_service.dart';
import '../widgets/common/app_toast.dart';

/// 名前入力画面
class NameInputScreen extends StatefulWidget {
  const NameInputScreen({super.key});

  @override
  State<NameInputScreen> createState() => _NameInputScreenState();
}

class _NameInputScreenState extends State<NameInputScreen> {
  final TextEditingController _nameController = TextEditingController();
  final UserService _userService = UserService();
  final AuthService _authService = AuthService();
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _checkAndSkipIfAlreadySet();
  }

  /// 既にデータが設定されている場合はスキップ
  Future<void> _checkAndSkipIfAlreadySet() async {
    final currentUser = _authService.currentUser;
    if (currentUser == null) {
      setState(() => _isLoading = false);
      return;
    }
    try {
      final user = await _userService.getUser(currentUser.uid);
      if (!mounted) return;
      if (user?.username != null && user!.username!.isNotEmpty) {
        // username まで設定済み → ホームへ
        Navigator.pushReplacementNamed(context, '/home');
        return;
      }
      if (user?.name != null && user!.name!.isNotEmpty) {
        // 名前は設定済みだが username 未設定 → username 入力へ
        Navigator.pushReplacementNamed(
          context,
          '/username-creation',
          arguments: {'name': user.name},
        );
        return;
      }
    } catch (_) {}
    if (mounted) setState(() => _isLoading = false);
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _handleNext() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      if (mounted) {
        AppToast.show(context, '名前を入力してください');
      }
      return;
    }

    // Web開発用：Firebase認証がない場合はFirestoreへの保存をスキップ
    final currentUser = _authService.currentUser;
    if (currentUser == null) {
      // 認証ユーザーがいない場合は、保存せず次の画面へ（名前を渡す）
      if (mounted) {
        Navigator.pushReplacementNamed(
          context,
          '/username-creation',
          arguments: {'name': name},
        );
      }
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      // 名前をFirestoreに保存
      await _userService.updateUser(
        uid: currentUser.uid,
        name: name,
      );

      if (mounted) {
        setState(() {
          _isLoading = false;
        });
        // ユーザーネーム作成画面へ遷移（名前を渡す）
        Navigator.pushNamed(
          context,
          '/username-creation',
          arguments: {'name': name},
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
        AppToast.show(context, '名前の保存に失敗しました: $e');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        backgroundColor: AppColors.background,
        body: Center(child: CupertinoActivityIndicator(color: Colors.white, radius: 14)),
      );
    }

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
                '名前を入力してください',
                style: AppTextStyles.heading,
              ),
              const SizedBox(height: AppDimensions.paddingLarge),
              CommonInputField(
                controller: _nameController,
                hintText: '名前',
                keyboardType: TextInputType.name,
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

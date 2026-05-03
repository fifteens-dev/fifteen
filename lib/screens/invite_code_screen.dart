import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../constants/app_colors.dart';
import '../constants/app_text_styles.dart';
import '../constants/app_dimensions.dart';
import '../widgets/common_input_field.dart';
import '../widgets/primary_button.dart';
import '../services/invite_code_service.dart';
import '../services/user_service.dart';
import '../widgets/common/app_toast.dart';

/// 招待コード入力画面
class InviteCodeScreen extends StatefulWidget {
  const InviteCodeScreen({super.key});

  @override
  State<InviteCodeScreen> createState() => _InviteCodeScreenState();
}

class _InviteCodeScreenState extends State<InviteCodeScreen> {
  final TextEditingController _inviteCodeController = TextEditingController();
  final InviteCodeService _inviteCodeService = InviteCodeService();
  final UserService _userService = UserService();
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _checkAndSkipIfAlreadySet();
  }

  /// 登録が既に完了している場合はスキップ
  Future<void> _checkAndSkipIfAlreadySet() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      setState(() => _isLoading = false);
      return;
    }
    try {
      final user = await _userService.getUser(uid);
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
    _inviteCodeController.dispose();
    super.dispose();
  }

  Future<void> _handleNext() async {
    final inviteCode = _inviteCodeController.text.trim().toUpperCase();
    if (inviteCode.isEmpty) {
      if (mounted) {
        AppToast.show(context, '招待コードを入力してください');
      }
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      // 招待コードを検証（詳細な結果を取得）
      final validationResult = await _inviteCodeService.validateInviteCodeDetailed(inviteCode);

      // 検証結果に応じたエラーメッセージを表示
      String? errorMessage;
      switch (validationResult) {
        case InviteCodeValidationResult.valid:
          // 有効な場合は次のステップへ
          break;
        case InviteCodeValidationResult.notFound:
          errorMessage = '無効な招待コードです';
          break;
        case InviteCodeValidationResult.alreadyUsed:
          errorMessage = 'この招待コードはすでに使用されています';
          break;
        case InviteCodeValidationResult.expired:
          errorMessage = 'この招待コードは有効期限切れです';
          break;
        case InviteCodeValidationResult.error:
          errorMessage = '招待コードの検証に失敗しました';
          break;
      }

      if (errorMessage != null) {
        if (mounted) {
          setState(() {
            _isLoading = false;
          });
          AppToast.show(context, errorMessage);
        }
        return;
      }

      // 招待コードを使用済みにし、コードオーナーをフォロー
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid != null) {
        await _inviteCodeService.markInviteCodeAsUsed(inviteCode, uid);
        // 招待コードのownerUidを取得してフォロー
        try {
          final codeDoc = await FirebaseFirestore.instance
              .collection('invite_codes')
              .doc(inviteCode)
              .get();
          final ownerUid = codeDoc.data()?['ownerUid'] as String?;
          if (ownerUid != null && ownerUid.isNotEmpty && ownerUid != uid) {
            // 通知はスキップ（username未設定のため）。認証フロー完了後に送信
            _userService.followUser(
              currentUserId: uid,
              targetUserId: ownerUid,
              skipNotification: true,
            ).catchError((_) {});
            // フォロー通知を後で送るためにownerUidを保存
            SharedPreferences.getInstance().then((prefs) {
              prefs.setString('pending_follow_owner_uid', ownerUid);
            });
          }
        } catch (_) {}
      }

      // 招待コードが有効な場合、名前入力画面へ遷移
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
        Navigator.pushNamed(context, '/name-input');
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
        AppToast.show(context, 'エラーが発生しました: ${e.toString().replaceFirst('Exception: ', '')}');
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
                '友達から受け取った\n招待コードを入力してください',
                style: AppTextStyles.heading,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: AppDimensions.paddingLarge),
              CommonInputField(
                controller: _inviteCodeController,
                hintText: '招待コード',
                keyboardType: TextInputType.text,
              ),
              const SizedBox(height: AppDimensions.paddingLarge),
              PrimaryButton(
                text: '次へ',
                onPressed: _handleNext,
                isLoading: _isLoading,
              ),
              const SizedBox(height: 24),
              GestureDetector(
                onTap: _isLoading ? null : _handleSkip,
                child: Text(
                  '招待コードをスキップ',
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.white.withValues(alpha: 0.45),
                    decoration: TextDecoration.underline,
                    decorationColor: Colors.white.withValues(alpha: 0.45),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _handleSkip() {
    Navigator.pushNamed(context, '/name-input');
  }
}

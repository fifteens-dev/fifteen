import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../constants/adl_teams.dart';
import '../constants/app_colors.dart';
import '../constants/app_text_styles.dart';
import '../constants/app_dimensions.dart';
import '../widgets/common_input_field.dart';
import '../widgets/primary_button.dart';
import '../services/adl_service.dart';
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
  final AdlService _adlService = AdlService();
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _checkAndSkipIfAlreadySet();
  }

  /// 登録完了済みなら直接ホームへ。未完了なら本画面を表示する。
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
        // 登録完了済み → ホームへ
        Navigator.pushReplacementNamed(context, '/home');
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
    final rawInput = _inviteCodeController.text.trim();
    if (rawInput.isEmpty) {
      if (mounted) {
        AppToast.show(context, '招待コードを入力してください');
      }
      return;
    }

    // ── ADL班コード判定 ──
    // 9つの固定コード（adl_house など）のいずれかなら、班加入フローへ
    if (AdlTeamDefinitions.isValidCode(rawInput)) {
      await _handleAdlTeamCode(rawInput);
      return;
    }

    // ── 通常の招待コード処理 ──
    await _handleNormalInviteCode(rawInput.toUpperCase());
  }

  /// ADL班コードによる加入処理。
  ///
  /// AdlService.joinTeamWithCode 内のトランザクションで以下を atomic に行う:
  /// - users/{uid}.adlTeamId / adlTeamName / adlEventId を更新
  /// - users/{uid}.followers / following に班アカウントUIDを追加（相互フォロー）
  /// - adl_memberships/{uid} を作成
  /// - adl_teams/{teamId}.memberCount を +1
  /// - users/{teamId}.followers / following に自分のUIDを追加
  Future<void> _handleAdlTeamCode(String code) async {
    setState(() => _isLoading = true);

    try {
      final result = await _adlService.joinTeamWithCode(code);
      if (!mounted) return;

      switch (result) {
        case AdlJoinResult.success:
        case AdlJoinResult.switched:
          AppToast.show(context, 'ADL班に参加しました');
          setState(() => _isLoading = false);
          Navigator.pushNamed(context, '/name-input');
        case AdlJoinResult.alreadyJoined:
          // 既に同じ班に所属 → そのまま前進
          setState(() => _isLoading = false);
          Navigator.pushNamed(context, '/name-input');
        case AdlJoinResult.notSeeded:
          setState(() => _isLoading = false);
          AppToast.show(context, '班データが準備中です。管理者にお問い合わせください');
        case AdlJoinResult.disabled:
          setState(() => _isLoading = false);
          AppToast.show(context, 'ADLイベントは現在開催されていません');
        case AdlJoinResult.invalidCode:
          // isValidCode を通過しているので通常は到達しないが念のため
          setState(() => _isLoading = false);
          AppToast.show(context, '班コードが正しくありません');
        case AdlJoinResult.error:
          setState(() => _isLoading = false);
          AppToast.show(context, '班への参加に失敗しました。もう一度お試しください');
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      AppToast.show(context, 'エラーが発生しました');
    }
  }

  /// 通常の招待コード（7文字英数字）の検証 + 使用済みマーク + コードオーナーフォロー
  Future<void> _handleNormalInviteCode(String inviteCode) async {
    setState(() => _isLoading = true);

    try {
      // 招待コードを検証（詳細な結果を取得）
      final validationResult =
          await _inviteCodeService.validateInviteCodeDetailed(inviteCode);

      // 検証結果に応じたエラーメッセージを表示
      String? errorMessage;
      switch (validationResult) {
        case InviteCodeValidationResult.valid:
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
          setState(() => _isLoading = false);
          AppToast.show(context, errorMessage);
        }
        return;
      }

      // 招待コードを使用済みにし、コードオーナーをフォロー
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid != null) {
        await _inviteCodeService.markInviteCodeAsUsed(inviteCode, uid);
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
            SharedPreferences.getInstance().then((prefs) {
              prefs.setString('pending_follow_owner_uid', ownerUid);
            });
          }
        } catch (_) {}
      }

      if (mounted) {
        setState(() => _isLoading = false);
        Navigator.pushNamed(context, '/name-input');
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        AppToast.show(context,
            'エラーが発生しました: ${e.toString().replaceFirst('Exception: ', '')}');
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

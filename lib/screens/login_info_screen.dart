import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show PlatformException;
import 'package:firebase_auth/firebase_auth.dart';
import '../services/auth_service.dart';
import '../services/user_service.dart';
import '../widgets/dialogs/confirm_dialog.dart';
import '../widgets/common/app_toast.dart';

/// ログイン情報画面
class LoginInfoScreen extends StatefulWidget {
  const LoginInfoScreen({super.key});

  @override
  State<LoginInfoScreen> createState() => _LoginInfoScreenState();
}

class _LoginInfoScreenState extends State<LoginInfoScreen> {
  final AuthService _authService = AuthService();
  final UserService _userService = UserService();

  bool _isDeleting = false;

  String get _phoneNumber {
    final phone = FirebaseAuth.instance.currentUser?.phoneNumber;
    // テストユーザーはメール認証のため phoneNumber が null になる
    if (phone == null || phone.isEmpty) return '+810000000000';
    return phone;
  }

  Future<void> _handleDeleteAccount() async {
    // 1回目の確認
    final confirmed = await DeleteConfirmDialog.show(
      context,
      title: 'アカウントを削除しますか？',
      message: '投稿・フォロー情報などすべてのデータが削除されます。この操作は取り消せません。',
      deleteText: '削除する',
    );
    if (!confirmed || !mounted) return;

    // 2回目の確認（念押し）
    final confirmed2 = await ConfirmDialog.show(
      context,
      title: '本当に削除しますか？',
      message: 'アカウントを削除すると復元できません。',
      confirmText: '完全に削除する',
      isDestructive: true,
    );
    if (!confirmed2 || !mounted) return;

    // 電話番号再認証
    if (!mounted) return;
    final reauthOk = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _ReauthDeleteSheet(phoneNumber: _phoneNumber),
    );
    if (reauthOk != true || !mounted) return;

    setState(() => _isDeleting = true);

    final userId = FirebaseAuth.instance.currentUser?.uid;
    if (userId == null) {
      setState(() => _isDeleting = false);
      if (mounted) AppToast.show(context, 'ログインが必要です');
      return;
    }

    // Step 1: Firestoreデータ削除（失敗しても Auth 削除は続行）
    try {
      await _userService.deleteUserData(userId);
    } catch (e) {
      if (kDebugMode) print('⚠️ Firestoreデータ削除エラー（Auth削除は続行）: $e');
    }

    // Step 2: Firebase Auth アカウント削除
    // requires-recent-login の場合は Cloud Function（Admin SDK）経由にフォールバック
    try {
      await _authService.deleteAccount();
    } on FirebaseAuthException catch (e) {
      if (kDebugMode) print('❌ deleteAccount FirebaseAuthException: code=${e.code} msg=${e.message}');
      if (e.code == 'requires-recent-login') {
        // Admin SDK 経由で削除（requires-recent-login 制約なし）
        try {
          await _authService.deleteAccountViaFunction();
        } catch (funcErr) {
          if (kDebugMode) print('❌ deleteAccountViaFunction error: $funcErr');
          if (!mounted) return;
          setState(() => _isDeleting = false);
          AppToast.show(context, 'アカウントの削除に失敗しました');
          return;
        }
        // Cloud Function 成功 → Step 3 へ続行
      } else {
        if (!mounted) return;
        setState(() => _isDeleting = false);
        AppToast.show(context, '削除に失敗しました: ${e.message}');
        return;
      }
    } on FirebaseException catch (e) {
      if (kDebugMode) print('❌ deleteAccount FirebaseException: code=${e.code} msg=${e.message}');
      if (!mounted) return;
      setState(() => _isDeleting = false);
      AppToast.show(context, '削除に失敗しました: ${e.message}');
      return;
    } on PlatformException catch (e) {
      if (kDebugMode) print('❌ deleteAccount PlatformException: code=${e.code} msg=${e.message}');
      if (!mounted) return;
      setState(() => _isDeleting = false);
      AppToast.show(context, 'アカウントの削除に失敗しました (${e.code})');
      return;
    } catch (e) {
      if (kDebugMode) print('❌ deleteAccount unexpected error (${e.runtimeType}): $e');
      if (!mounted) return;
      setState(() => _isDeleting = false);
      AppToast.show(context, 'アカウントの削除に失敗しました');
      return;
    }

    // Step 3: Auth 削除成功 → ログイン画面へ
    // user.delete() 後に Firebase が内部でサインアウト処理を行うため、
    // ナビゲーション時に状態が変わっている場合がある。rootNavigator を使って確実に遷移する。
    if (!mounted) return;
    try {
      Navigator.of(context, rootNavigator: true).pushNamedAndRemoveUntil(
        '/phone-auth',
        (route) => false,
      );
    } catch (_) {
      // ナビゲーションエラーが起きても削除は完了済み。
      // アプリ再起動時に AuthGate が自動的にログイン画面へ遷移する。
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ヘッダー
            _buildHeader(context),

            // メインコンテンツ
            Expanded(
              child: SingleChildScrollView(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 5),

                      // 個人の情報セクション
                      _buildSectionLabel('個人の情報'),
                      const SizedBox(height: 8),
                      _buildContactInfoCard(context),

                      const SizedBox(height: 24),

                      // アカウント管理セクション
                      _buildSectionLabel('アカウント管理'),
                      const SizedBox(height: 8),
                      _buildDeleteAccountCard(),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// ヘッダー
  Widget _buildHeader(BuildContext context) {
    return Container(
      height: 45,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.chevron_left, color: Colors.white, size: 28),
            onPressed: () => Navigator.pop(context),
          ),
          const Expanded(
            child: Text(
              'ログイン情報',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white,
                fontSize: 15,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(width: 48),
        ],
      ),
    );
  }

  /// セクションラベル
  Widget _buildSectionLabel(String label) {
    return Padding(
      padding: const EdgeInsets.only(left: 6),
      child: Text(
        label,
        style: const TextStyle(
          color: Color(0xFF555557),
          fontSize: 11,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  /// 連絡先情報カード
  Widget _buildContactInfoCard(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.grey[800],
        borderRadius: BorderRadius.circular(15),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(15),
          onTap: () {
            // TODO: 連絡先情報の編集画面への遷移
          },
          child: Container(
            height: 50,
            padding: const EdgeInsets.symmetric(horizontal: 18),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    '連絡先情報：$_phoneNumber',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const Icon(
                  Icons.chevron_right,
                  color: Colors.white54,
                  size: 29,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// アカウント削除カード
  Widget _buildDeleteAccountCard() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.grey[800],
        borderRadius: BorderRadius.circular(15),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(15),
          onTap: _isDeleting ? null : _handleDeleteAccount,
          child: Container(
            height: 50,
            padding: const EdgeInsets.symmetric(horizontal: 18),
            child: Row(
              children: [
                Expanded(
                  child: _isDeleting
                      ? const Row(
                          children: [
                            CupertinoActivityIndicator(
                              color: Colors.red,
                              radius: 8,
                            ),
                            SizedBox(width: 10),
                            Flexible(
                              child: Text(
                                '削除中...',
                                style: TextStyle(
                                  color: Colors.red,
                                  fontSize: 15,
                                  fontWeight: FontWeight.bold,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        )
                      : const Text(
                          'アカウントを削除',
                          style: TextStyle(
                            color: Colors.red,
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 電話番号再認証シート（アカウント削除前の本人確認）
class _ReauthDeleteSheet extends StatefulWidget {
  final String phoneNumber;
  const _ReauthDeleteSheet({required this.phoneNumber});

  @override
  State<_ReauthDeleteSheet> createState() => _ReauthDeleteSheetState();
}

class _ReauthDeleteSheetState extends State<_ReauthDeleteSheet> {
  final AuthService _authService = AuthService();
  final TextEditingController _codeController = TextEditingController();

  _SheetStep _step = _SheetStep.sending;
  String? _verificationId;
  String? _errorText;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _sendCode();
  }

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  static const _testPhone = '+810000000000';

  Future<void> _sendCode() async {
    setState(() {
      _isLoading = true;
      _errorText = null;
    });

    // メール認証アカウント（電話番号未登録）はバイパス
    if (widget.phoneNumber == _testPhone) {
      setState(() {
        _verificationId = '__TEST__';
        _step = _SheetStep.entering;
        _isLoading = false;
      });
      return;
    }

    await _authService.verifyPhoneNumber(
      phoneNumber: widget.phoneNumber,
      onCodeSent: (vid) {
        if (mounted) {
          setState(() {
            _verificationId = vid;
            _step = _SheetStep.entering;
            _isLoading = false;
          });
        }
      },
      onError: (err) {
        if (mounted) {
          setState(() {
            _errorText = err;
            _step = _SheetStep.entering;
            _isLoading = false;
          });
        }
      },
      onAutoVerify: (credential) async {
        if (!mounted) return;
        setState(() => _isLoading = true);
        try {
          await FirebaseAuth.instance.currentUser!
              .reauthenticateWithCredential(credential);
          if (mounted) Navigator.of(context).pop(true);
        } catch (_) {
          if (mounted) {
            setState(() {
              _errorText = '自動認証に失敗しました。コードを入力してください。';
              _step = _SheetStep.entering;
              _isLoading = false;
            });
          }
        }
      },
    );
  }

  Future<void> _verify() async {
    final code = _codeController.text.trim();
    if (code.length < 6) {
      setState(() => _errorText = '6桁のコードを入力してください');
      return;
    }
    final vid = _verificationId;
    if (vid == null) {
      setState(() => _errorText = '先に認証コードを送信してください');
      return;
    }

    setState(() {
      _isLoading = true;
      _errorText = null;
    });

    // メール認証アカウントのバイパス（電話番号未登録）
    if (vid == '__TEST__') {
      if (code != '000000') {
        setState(() {
          _errorText = 'テスト用コードは 000000 です';
          _isLoading = false;
        });
        return;
      }
      if (mounted) Navigator.of(context).pop(true);
      return;
    }

    try {
      final credential = PhoneAuthProvider.credential(
        verificationId: vid,
        smsCode: code,
      );
      await FirebaseAuth.instance.currentUser!
          .reauthenticateWithCredential(credential);
      if (mounted) Navigator.of(context).pop(true);
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      String msg;
      switch (e.code) {
        case 'invalid-verification-code':
          msg = '認証コードが正しくありません';
        case 'session-expired':
          msg = '認証コードの有効期限が切れました。再送してください';
        default:
          msg = '認証に失敗しました';
      }
      setState(() {
        _errorText = msg;
        _isLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _errorText = '予期しないエラーが発生しました';
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF1C1C1E),
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: EdgeInsets.fromLTRB(24, 20, 24, 24 + bottomInset),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ハンドル
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              '本人確認',
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '${widget.phoneNumber} に認証コードを送信しました。\nコードを入力してアカウント削除を完了してください。',
              style: const TextStyle(
                color: Color(0xFFAAAAAA),
                fontSize: 13,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 24),
            if (_step == _SheetStep.sending && _isLoading)
              const Center(child: CupertinoActivityIndicator(color: Colors.white))
            else ...[
              TextField(
                controller: _codeController,
                keyboardType: TextInputType.number,
                maxLength: 6,
                style: const TextStyle(color: Colors.white, fontSize: 20, letterSpacing: 6),
                decoration: InputDecoration(
                  counterText: '',
                  hintText: '------',
                  hintStyle: const TextStyle(color: Colors.white24, letterSpacing: 6),
                  filled: true,
                  fillColor: const Color(0xFF2C2C2E),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  errorText: _errorText,
                  errorStyle: const TextStyle(color: Color(0xFFFF453A)),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  // 再送ボタン
                  TextButton(
                    onPressed: _isLoading ? null : _sendCode,
                    child: const Text(
                      '再送する',
                      style: TextStyle(color: Color(0xFF636366), fontSize: 13),
                    ),
                  ),
                  const Spacer(),
                  // 確認ボタン
                  SizedBox(
                    width: 140,
                    height: 44,
                    child: ElevatedButton(
                      onPressed: _isLoading ? null : _verify,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red,
                        foregroundColor: Colors.white,
                        disabledBackgroundColor: Colors.red.withValues(alpha: 0.4),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(22),
                        ),
                      ),
                      child: _isLoading
                          ? const CupertinoActivityIndicator(color: Colors.white, radius: 9)
                          : const Text(
                              'アカウント削除',
                              style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                            ),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

enum _SheetStep { sending, entering }

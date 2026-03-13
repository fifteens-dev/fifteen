import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../services/auth_service.dart';
import '../services/user_service.dart';
import '../widgets/dialogs/confirm_dialog.dart';

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

  String get _phoneNumber =>
      FirebaseAuth.instance.currentUser?.phoneNumber ?? '-';

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

    setState(() => _isDeleting = true);

    try {
      // currentUserがnullの場合、authStateChangesで復元を一度待つ（即時emit）
      User? user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        try {
          user = await FirebaseAuth.instance
              .authStateChanges()
              .first
              .timeout(const Duration(seconds: 3));
        } catch (_) {
          user = null;
        }
      }
      final userId = user?.uid;
      if (userId == null) {
        setState(() => _isDeleting = false);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('ログインが必要です')),
          );
        }
        return;
      }

      // Firestoreデータ削除
      await _userService.deleteUserData(userId);

      // Firebase Auth アカウント削除
      await _authService.deleteAccount();

      if (mounted) {
        Navigator.of(context).pushNamedAndRemoveUntil(
          '/phone-auth',
          (route) => false,
        );
      }
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      setState(() => _isDeleting = false);

      if (e.code == 'requires-recent-login') {
        await ConfirmDialog.show(
          context,
          title: '再ログインが必要です',
          message: 'アカウントを削除するには、一度ログアウトして再度ログインしてください。',
          confirmText: 'OK',
          cancelText: '',
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('削除に失敗しました: ${e.message}')),
        );
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _isDeleting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('削除中にエラーが発生しました')),
      );
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
                      ? Row(
                          children: [
                            const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                color: Colors.red,
                                strokeWidth: 2,
                              ),
                            ),
                            const SizedBox(width: 10),
                            const Flexible(
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

import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;

  // 現在のユーザーを取得
  User? get currentUser => _auth.currentUser;

  // 認証状態の変更をリッスン
  Stream<User?> get authStateChanges => _auth.authStateChanges();

  // 電話番号に認証コードを送信
  Future<bool> verifyPhoneNumber({
    required String phoneNumber,
    required Function(String verificationId) onCodeSent,
    required Function(String error) onError,
    required Function(PhoneAuthCredential credential) onAutoVerify,
  }) async {
    try {
      await _auth.verifyPhoneNumber(
        phoneNumber: phoneNumber,
        timeout: const Duration(seconds: 60),
        verificationCompleted: (PhoneAuthCredential credential) async {
          // 自動認証（Androidの場合）
          onAutoVerify(credential);
        },
        verificationFailed: (FirebaseAuthException e) {
          String errorMessage = '認証に失敗しました';

          if (e.code == 'invalid-phone-number') {
            errorMessage = '電話番号の形式が正しくありません';
          } else if (e.code == 'too-many-requests') {
            errorMessage = 'リクエストが多すぎます。しばらく待ってから再度お試しください';
          } else if (e.code == 'quota-exceeded') {
            errorMessage = '認証の制限に達しました';
          }

          if (kDebugMode) {
            print('FirebaseAuthException: ${e.code} - ${e.message}');
          }

          onError(errorMessage);
        },
        codeSent: (String verificationId, int? resendToken) {
          onCodeSent(verificationId);
        },
        codeAutoRetrievalTimeout: (String verificationId) {},
      );
      return true;
    } catch (e) {
      if (kDebugMode) {
        print('Error in verifyPhoneNumber: $e');
      }
      onError('予期しないエラーが発生しました');
      return false;
    }
  }

  // 認証コードで認証
  Future<UserCredential?> signInWithVerificationCode({
    required String verificationId,
    required String smsCode,
  }) async {
    try {
      final PhoneAuthCredential credential = PhoneAuthProvider.credential(
        verificationId: verificationId,
        smsCode: smsCode,
      );

      return await _auth.signInWithCredential(credential);
    } on FirebaseAuthException catch (e) {
      if (kDebugMode) {
        print('FirebaseAuthException in signIn: ${e.code} - ${e.message}');
      }

      if (e.code == 'invalid-verification-code') {
        throw Exception('認証コードが正しくありません');
      } else if (e.code == 'session-expired') {
        throw Exception('認証コードの有効期限が切れました。もう一度お試しください');
      } else {
        throw Exception('認証に失敗しました');
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error in signInWithVerificationCode: $e');
      }
      throw Exception('予期しないエラーが発生しました');
    }
  }

  // 招待コード認証でサインイン（匿名認証を使用）
  Future<UserCredential?> signInWithInviteCode(String inviteCode) async {
    try {
      // 既にサインイン済みのユーザーがいる場合は、そのユーザーを使用
      final currentUser = _auth.currentUser;
      if (currentUser != null) {
        if (kDebugMode) {
          print('✅ Using existing user for invite code: ${currentUser.uid}');
          print('   Invite code: $inviteCode');
        }
        // 既存のユーザーをUserCredentialとして返す
        // Note: この場合、実際のUserCredentialオブジェクトは作成されないため、
        // 呼び出し側でcurrentUserを直接使用する必要がある
        return null; // currentUserが存在することを示すためnullを返す
      }

      // ユーザーがいない場合は匿名認証でFirebaseユーザーを作成
      final userCredential = await _auth.signInAnonymously();
      if (kDebugMode) {
        print('✅ User signed in with invite code: ${userCredential.user?.uid}');
        print('   Invite code: $inviteCode');
      }
      return userCredential;
    } on FirebaseAuthException catch (e) {
      if (kDebugMode) {
        print('FirebaseAuthException in signInWithInviteCode: ${e.code} - ${e.message}');
      }
      throw Exception('認証に失敗しました');
    } catch (e) {
      if (kDebugMode) {
        print('Error in signInWithInviteCode: $e');
      }
      throw Exception('予期しないエラーが発生しました');
    }
  }

  // メール/パスワードでサインイン（公式アカウント用）
  Future<UserCredential> signInWithEmailAndPassword({
    required String email,
    required String password,
  }) async {
    try {
      return await _auth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );
    } on FirebaseAuthException catch (e) {
      if (kDebugMode) {
        print('FirebaseAuthException in signInWithEmail: ${e.code} - ${e.message}');
      }
      switch (e.code) {
        case 'user-not-found':
          throw Exception('このメールアドレスのアカウントが見つかりません');
        case 'wrong-password':
        case 'invalid-credential':
          throw Exception('メールアドレスまたはパスワードが正しくありません');
        case 'invalid-email':
          throw Exception('メールアドレスの形式が正しくありません');
        case 'user-disabled':
          throw Exception('このアカウントは無効化されています');
        default:
          throw Exception('ログインに失敗しました');
      }
    }
  }

  // メール/パスワードでアカウント作成（公式アカウント用）
  Future<UserCredential> createUserWithEmailAndPassword({
    required String email,
    required String password,
  }) async {
    try {
      return await _auth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );
    } on FirebaseAuthException catch (e) {
      if (kDebugMode) {
        print('FirebaseAuthException in createUser: ${e.code} - ${e.message}');
      }
      switch (e.code) {
        case 'email-already-in-use':
          throw Exception('このメールアドレスは既に使用されています');
        case 'invalid-email':
          throw Exception('メールアドレスの形式が正しくありません');
        case 'weak-password':
          throw Exception('パスワードは6文字以上にしてください');
        default:
          throw Exception('アカウント作成に失敗しました');
      }
    }
  }

  // サインアウト
  Future<void> signOut() async {
    await _auth.signOut();
  }

  // アカウント削除（直接）
  // 再認証直後など requires-recent-login が発生しない場合に使用
  Future<void> deleteAccount() async {
    final user = currentUser;
    if (user != null) {
      try {
        await user.getIdToken(true);
      } catch (e) {
        if (kDebugMode) print('⚠️ getIdToken(force) failed (continuing): $e');
      }
      await user.delete();
    }
  }

  // Cloud Function 経由でアカウント削除（Admin SDK）
  // requires-recent-login 制約なし。再認証が完了できないケースでも動作する。
  Future<void> deleteAccountViaFunction() async {
    await FirebaseFunctions.instance
        .httpsCallable('deleteCurrentUser')
        .call<Map<String, dynamic>>();
  }
}

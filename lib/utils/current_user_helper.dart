import 'package:firebase_auth/firebase_auth.dart';
import '../services/user_service.dart';

/// 現在のユーザー情報を取得するヘルパー
class CurrentUserHelper {
  static final UserService _userService = UserService();
  static final FirebaseAuth _auth = FirebaseAuth.instance;

  /// 現在ログイン中のユーザー情報を取得
  static Future<({String username, String? iconUrl, String? university})> load() async {
    try {
      final currentUser = _auth.currentUser;
      if (currentUser != null) {
        final userData = await _userService.getUser(currentUser.uid);
        return (
          username: userData?.username ?? currentUser.displayName ?? 'ユーザー',
          iconUrl: userData?.profileImageUrl,
          university: userData?.university,
        );
      }
    } catch (e) {
      print('ユーザー情報取得エラー: $e');
    }
    return (username: 'ユーザー', iconUrl: null, university: null);
  }
}

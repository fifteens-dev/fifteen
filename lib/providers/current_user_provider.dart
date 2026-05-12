import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import '../models/user_model.dart';
import '../services/user_service.dart';

/// アプリ全体で共有する現在のユーザー情報。
///
/// `Provider` 経由で `username`/`iconUrl`/`university`/`uid` にアクセスできる。
/// プロフィール更新後は [refresh] を、ログアウト/アカウント削除時は [clear] を呼ぶ。
class CurrentUserProvider extends ChangeNotifier {
  final UserService _userService = UserService();

  String _username = 'ユーザー';
  String? _iconUrl;
  String? _university;
  String? _uid;
  bool _loaded = false;

  String get username => _username;
  String? get iconUrl => _iconUrl;
  String? get university => _university;
  String? get uid => _uid;
  bool get isLoaded => _loaded;

  /// 事前ロード済みの UserModel から初期化（起動時 splash で取得済みの場合等）
  void initFromModel(UserModel model) {
    _username = model.username ?? 'ユーザー';
    _iconUrl = model.profileImageUrl;
    _university = model.university;
    _uid = model.uid;
    _loaded = true;
    notifyListeners();
  }

  /// アプリ起動時や認証完了直後に呼ぶ。
  /// すでにロード済みなら何もしない（force=true で強制再取得）。
  Future<void> ensureLoaded({bool force = false}) async {
    if (_loaded && !force) return;
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) {
      _username = 'ユーザー';
      _iconUrl = null;
      _university = null;
      _uid = null;
      _loaded = true;
      notifyListeners();
      return;
    }
    try {
      final userData = await _userService.getUser(currentUser.uid);
      _username =
          userData?.username ?? currentUser.displayName ?? 'ユーザー';
      _iconUrl = userData?.profileImageUrl;
      _university = userData?.university;
      _uid = currentUser.uid;
      _loaded = true;
      notifyListeners();
    } catch (e) {
      if (kDebugMode) print('CurrentUserProvider load error: $e');
      _uid = currentUser.uid;
      _loaded = true;
      notifyListeners();
    }
  }

  /// プロフィール変更後など、最新情報を取り直したい時に呼ぶ
  Future<void> refresh() => ensureLoaded(force: true);

  /// ログアウト/アカウント削除時にクリア
  void clear() {
    _username = 'ユーザー';
    _iconUrl = null;
    _university = null;
    _uid = null;
    _loaded = false;
    notifyListeners();
  }
}

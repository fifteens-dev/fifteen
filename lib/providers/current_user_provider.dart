import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import '../models/user_model.dart';
import '../services/user_service.dart';

/// アプリ全体で共有する現在のユーザー情報。
///
/// `Provider` 経由で `username`/`iconUrl`/`university`/`uid` にアクセスできる。
/// プロフィール更新後は [refresh] を、ログアウト/アカウント削除時は [clear] を呼ぶ。
/// なお `authStateChanges` を購読しており、UID が変わった瞬間に自動でクリア＆再ロードする。
class CurrentUserProvider extends ChangeNotifier {
  final UserService _userService = UserService();

  String _username = 'ユーザー';
  String? _iconUrl;
  String? _university;
  String? _uid;
  String? _adlTeamId;
  bool _loaded = false;

  StreamSubscription<User?>? _authSub;

  CurrentUserProvider() {
    // 認証状態の変化を購読し、UID が切り替わったら即クリア＆新ユーザーをロード。
    // これにより「前ユーザーのアイコン/名前が新アカウント作成直後に残る」現象を防ぐ。
    _authSub = FirebaseAuth.instance.authStateChanges().listen((user) {
      final newUid = user?.uid;
      if (newUid == _uid) return; // 変化なし
      clear();
      if (newUid != null) {
        ensureLoaded();
      }
    });
  }

  @override
  void dispose() {
    _authSub?.cancel();
    super.dispose();
  }

  String get username => _username;
  String? get iconUrl => _iconUrl;
  String? get university => _university;
  String? get uid => _uid;
  String? get adlTeamId => _adlTeamId;
  bool get isLoaded => _loaded;

  /// 事前ロード済みの UserModel から初期化（起動時 splash で取得済みの場合等）
  void initFromModel(UserModel model) {
    _username = model.username ?? 'ユーザー';
    _iconUrl = model.profileImageUrl;
    _university = model.university;
    _uid = model.uid;
    _adlTeamId = model.adlTeamId;
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
      _adlTeamId = null;
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
      _adlTeamId = userData?.adlTeamId;
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
    _adlTeamId = null;
    _loaded = false;
    notifyListeners();
  }
}

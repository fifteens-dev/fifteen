import 'package:flutter/foundation.dart';

/// 「投稿画面を開いて」という依頼をホームへ渡す。
///
/// つつかれた通知のタップや、グループ画面の自分の枠から来る。投稿フローは
/// ホームの状態（投稿済みか・温めた履歴）を使うのでホームで開く。
/// 依頼が来たときにホームがまだ無い（コールドスタート）こともあるので、
/// [pending] を立てておき、ホームが組み上がったら [take] で受け取る。
class PostFlowRequest extends ChangeNotifier {
  PostFlowRequest._();
  static final PostFlowRequest instance = PostFlowRequest._();

  bool _pending = false;
  bool get pending => _pending;

  void request() {
    _pending = true;
    notifyListeners();
  }

  /// 依頼があれば true を返して取り下げる。
  bool take() {
    if (!_pending) return false;
    _pending = false;
    return true;
  }
}

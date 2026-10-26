import 'package:flutter/widgets.dart';

/// リアクション通知をタップしたときの「ホームで自分のカードを見せる」依頼。
class ReactionRevealRequest {
  final String postId;

  /// リアクションした人。投稿の reactions からその人の絵文字を引く。
  final String senderId;

  const ReactionRevealRequest({required this.postId, required this.senderId});
}

/// 通知のタップ（FCM・通知一覧）からホームへ依頼を渡す。
///
/// 通知を開いた時点でホームがまだ無い（コールドスタート）ことがあるので、
/// 呼び出しで直接ホームを操作せず、依頼を置いておいてホームに取りに来させる。
class ReactionRevealService {
  ReactionRevealService._();
  static final ReactionRevealService instance = ReactionRevealService._();

  final ValueNotifier<ReactionRevealRequest?> pending =
      ValueNotifier<ReactionRevealRequest?>(null);

  void request({required String postId, required String senderId}) {
    pending.value = ReactionRevealRequest(postId: postId, senderId: senderId);
  }

  /// いま表示中のホームの route。通知から戻るときの戻り先。
  ///
  /// `popUntil(isFirst)` だと、登録直後はスタックの底に電話番号認証などの
  /// オンボーディング画面が残っていて、そこまで戻ってしまう。
  Route<dynamic>? _homeRoute;

  void attachHome(Route<dynamic> route) => _homeRoute = route;

  void detachHome(Route<dynamic>? route) {
    if (identical(_homeRoute, route)) _homeRoute = null;
  }

  /// ホームより上の画面を閉じる。ホームがまだ無い（コールドスタート）ときは
  /// 何もしない。依頼はホームができたときに拾われる。
  void popToHome(NavigatorState navigator) {
    final home = _homeRoute;
    if (home == null || !home.isActive) return;
    navigator.popUntil((route) => route == home);
  }

  /// 置かれている依頼を取り出す（取り出したら消える）。
  ReactionRevealRequest? take() {
    final r = pending.value;
    pending.value = null;
    return r;
  }
}

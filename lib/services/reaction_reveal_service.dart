import 'package:flutter/foundation.dart';

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

  /// 置かれている依頼を取り出す（取り出したら消える）。
  ReactionRevealRequest? take() {
    final r = pending.value;
    pending.value = null;
    return r;
  }
}

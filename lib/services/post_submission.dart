import 'dart:async';

import 'package:flutter/foundation.dart';

import '../utils/photo_helper.dart';
import 'post_service.dart';
import 'storage_service.dart';

/// 写真付き投稿の段取り。
///
/// 気分投稿（[MoodPostFinalPreviewScreen]）と Vibe 投稿
/// （[VibeStoryPreviewScreen]）が、同じ手順をそれぞれ書いていた。
/// 投稿の中身は画面ごとに違うが、写真の扱いは共通なのでここに寄せる。
///
/// 片方だけ直す事故が実際に起きていた（写真を 2 回圧縮していた不具合は、
/// 同じ修正を両方に入れる必要があった）。
///
/// ## 手順
///  1. 写真があれば Storage へ上げる
///  2. ダウンロード URL の取得と投稿の作成を**並行**で走らせる
///  3. URL が取れたら投稿に後追いで入れる
///
/// URL 取得を待ってから投稿を作ると、その往復ぶん投稿が遅れる。先に
/// photoUrl なしで作り、あとから埋める。
///
/// 写真のアップロードに失敗したときは投稿を作らない（例外がそのまま出る）。
/// 写真が本体の投稿で、写真だけ落ちたものを残しても意味がないため。
class PostSubmission {
  PostSubmission._();

  /// [photoBytes] は [PhotoHelper.compressForUpload] を通した後のバイト列。
  /// null なら写真なしの投稿。
  ///
  /// [createPost] は photoUrl を渡さずに投稿を作る処理。postId を返すこと。
  ///
  /// 戻り値は作られた投稿の postId。
  static Future<String> submit({
    required String userId,
    required Uint8List? photoBytes,
    required StorageService storage,
    required PostService postService,
    required Future<String> Function() createPost,
  }) async {
    Future<String?> urlFuture = Future<String?>.value(null);

    if (photoBytes != null) {
      final uploaded = await PhotoHelper.uploadCompressedSplit(
        imageBytes: photoBytes,
        userId: userId,
        storageService: storage,
        // 呼び出し側が compressForUpload を通している。ここで掛け直すと
        // 時間が倍かかり、JPEG を再エンコードするぶん画質も落ちる。
        alreadyCompressed: true,
      );
      urlFuture = uploaded.storageRef!
          .getDownloadURL()
          .then<String?>((u) => u)
          // URL が取れなくても投稿自体は成立させる。写真は後から入らない
          // だけで、投稿が丸ごと失敗するよりはよい。
          .catchError((_) => null);
    }

    final results = await Future.wait<dynamic>([urlFuture, createPost()]);
    final photoUrl = results[0] as String?;
    final postId = results[1] as String;

    if (photoUrl != null) {
      // 待たない。ここで待つと投稿完了の表示がそのぶん遅れる。
      unawaited(
        postService.updatePostPhotoUrl(postId: postId, photoUrl: photoUrl),
      );
    }

    return postId;
  }
}

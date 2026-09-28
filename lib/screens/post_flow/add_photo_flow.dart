import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../services/post_photo_service.dart';
import '../../widgets/common/app_toast.dart';
import '../post_photo_selection_screen.dart';

/// 投稿に写真を足す一連の流れ。
///
/// 写真は次の条件でしか足せない:
///  - その日の 24:00 まで（[PostPhotoService.canAddPhotoNow]）
///  - その日撮った写真か、その場で撮ったもの
///
/// 足した写真は本人しか見られない。Music Memory のカレンダーから開いた
/// 投稿カードの裏面にだけ出る。
class AddPhotoFlow {
  AddPhotoFlow._();

  /// 写真を選ばせて保存する。保存できたら true。
  ///
  /// 時間外のときは理由を出して何もしない。
  static Future<bool> start(BuildContext context, {required String postId}) async {
    if (!PostPhotoService.instance.canAddPhotoNow) {
      AppToast.show(context, '写真を追加できるのは24:00までです');
      return false;
    }

    // 投稿フローで使っていたのと同じ画面（カメラ + 写真グリッド）。
    // 「その場で撮る」が要るので、グリッドだけのオーバーレイでは足りない。
    XFile? photo;
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => PostPhotoSelectionScreen(
          todayOnly: true,
          onPhotoTaken: (p) => photo = p,
        ),
      ),
    );
    if (photo == null || !context.mounted) return false;

    final picked = await photo!.readAsBytes();
    if (!context.mounted) return false;

    // 選んでいる間に日付をまたぐことがあるので、保存の直前にもう一度見る。
    if (!PostPhotoService.instance.canAddPhotoNow) {
      AppToast.show(context, '写真を追加できるのは24:00までです');
      return false;
    }

    final ok = await PostPhotoService.instance
        .attach(postId: postId, imageBytes: picked);
    if (!context.mounted) return ok;
    AppToast.show(
      context,
      ok ? '写真を追加しました' : '写真の追加に失敗しました',
    );
    return ok;
  }
}

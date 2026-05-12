/// チュートリアル機能の barrel ファイル。
///
/// 通常コードからチュートリアル機能にアクセスする場合は、このファイル経由でのみ
/// import すること。チュートリアル内部の各実装ファイルを直接 import しない。
///
/// 現在チュートリアル機能はアプリ本体から完全に切り離されており、
/// 再有効化する際は main.dart で `TutorialController.instance.ensureInitialized()` を
/// 呼び、必要な画面でオーバーレイ Widget をマウントすること。
library;

export 'animated_hand_cursor.dart';
export 'tutorial_album_carousel.dart';
export 'tutorial_camera_overlay.dart';
export 'tutorial_coachmark.dart';
export 'tutorial_controller.dart';
export 'tutorial_frame628_overlay.dart';
export 'tutorial_prefetch_service.dart';

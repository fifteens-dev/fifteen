import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// チュートリアル進行段階
enum TutorialStep {
  /// 未開始 / すでに完了
  inactive,

  /// ホーム画面で「Vibeに投稿してみよう」を案内
  showHomeHint,

  /// 楽曲選択画面で 3 つのアルバムから選ぶ
  pickSong,

  /// カメラオーバーレイで写真を撮影中
  takingPhoto,

  /// 通常の投稿フロー進行中（写真撮影〜投稿完了まで）
  posting,

  /// 投稿完了、ホームに戻ってきて Vibe アイコンへの誘導
  showVibePlaylistHint,

  /// Vibeプレイリスト画面で上スワイプを案内
  swipeUpInPlaylist,
}

/// アプリ全体のチュートリアル進行を管理するシングルトン。
///
/// SharedPreferences で永続化し、アプリ再起動後もチュートリアルを継続できる。
/// `Provider` を使うほどの規模ではないため、ChangeNotifier として `ListenableBuilder` で監視する。
class TutorialController extends ChangeNotifier {
  TutorialController._();
  static final TutorialController instance = TutorialController._();

  static const String _prefKey = 'tutorial_step_v1';
  static const String _completedKey = 'tutorial_completed_v1';

  TutorialStep _step = TutorialStep.inactive;
  bool _initialized = false;
  bool _everCompleted = false;

  TutorialStep get step => _step;
  bool get isActive => _step != TutorialStep.inactive;
  bool get isCompleted => _everCompleted;
  bool get initialized => _initialized;

  /// アプリ起動時に1回呼ぶ
  Future<void> ensureInitialized() async {
    if (_initialized) return;
    final prefs = await SharedPreferences.getInstance();
    _everCompleted = prefs.getBool(_completedKey) ?? false;
    final raw = prefs.getString(_prefKey);
    if (raw != null) {
      _step = TutorialStep.values.firstWhere(
        (s) => s.name == raw,
        orElse: () => TutorialStep.inactive,
      );
    }
    _initialized = true;
    notifyListeners();
  }

  /// チュートリアル開始（音楽ライブラリ接続後に呼ぶ）
  Future<void> start() async {
    if (_everCompleted) return; // 一度完了したら再起動しない
    _step = TutorialStep.showHomeHint;
    await _persistStep();
    notifyListeners();
  }

  /// 任意のステップに進める
  Future<void> goTo(TutorialStep step) async {
    _step = step;
    await _persistStep();
    notifyListeners();
  }

  /// チュートリアルを終了
  Future<void> complete() async {
    _step = TutorialStep.inactive;
    _everCompleted = true;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefKey);
    await prefs.setBool(_completedKey, true);
    notifyListeners();
  }

  /// 強制リセット（デバッグ用）
  @visibleForTesting
  Future<void> reset() async {
    _step = TutorialStep.inactive;
    _everCompleted = false;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefKey);
    await prefs.remove(_completedKey);
    notifyListeners();
  }

  Future<void> _persistStep() async {
    final prefs = await SharedPreferences.getInstance();
    if (_step == TutorialStep.inactive) {
      await prefs.remove(_prefKey);
    } else {
      await prefs.setString(_prefKey, _step.name);
    }
  }
}

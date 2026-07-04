import 'dart:math';

/// 2 指 pinch ジェスチャーの「角度の連続性」を保つトラッカー。
///
/// Flutter の `ScaleUpdateDetails.rotation` は内部で `atan2` を使うため、
/// 2 指の上下/左右関係が入れ替わると 1 フレームで ±π ジャンプする。
/// このトラッカーは前フレームとの差が ±π/2 を超えたら ∓π でラップ補正して
/// 累積することで、順序入れ替わりに耐性のある連続的な回転角を返す。
///
/// 使い方:
///   - `onScaleStart` で [reset] を呼ぶ
///   - `onScaleUpdate` の冒頭で [ingest] に `details.rotation` を渡す
///   - 回転計算には [accumulated] を `details.rotation` の代わりに使う
class TwoFingerRotationTracker {
  double _lastRotation = 0.0;
  double _accumulated = 0.0;

  /// `onScaleStart` 時に呼んでリセット
  void reset() {
    _lastRotation = 0.0;
    _accumulated = 0.0;
  }

  /// `onScaleUpdate` で `details.rotation` を渡して累積を更新
  void ingest(double rawRotation) {
    double delta = rawRotation - _lastRotation;
    // ±π/2 を超えるジャンプは順序入れ替わりとみなして補正
    while (delta > pi / 2) delta -= pi;
    while (delta < -pi / 2) delta += pi;
    _accumulated += delta;
    _lastRotation = rawRotation;
  }

  /// ラップ補正済み累積回転（投稿フロー / Vibe Story はこれを `details.rotation`
  /// の代わりに使う）
  double get accumulated => _accumulated;
}

/// カード（歌詞カード / アルバム）の回転に「初期 ±10° まで動かない」ロック
/// を掛けるためのヘルパー。
///
/// 使い方:
///   - `onScaleStart` で [reset]
///   - update 内で [computeRotation] に「現在の累積回転」を渡すと、
///     ロック中は startRotation を、解除後は `startRotation + accumulated * 0.6`
///     を返す。
///   - 投稿フロー / Vibe Story の本体ロジックと完全に一致する挙動。
class InitialRotationLock {
  static const double thresholdRad = 10.0 * pi / 180.0;
  static const double dampingFactor = 0.6;

  bool _locked = true;

  void reset() {
    _locked = true;
  }

  bool get isLocked => _locked;

  /// `startRotation`: ジェスチャー accept 時のカード回転。
  /// `accumulated`: ラップ補正済みの累積指回転。
  double computeRotation({
    required double startRotation,
    required double accumulated,
  }) {
    if (_locked && accumulated.abs() < thresholdRad) {
      return startRotation;
    }
    _locked = false;
    return startRotation + accumulated * dampingFactor;
  }
}

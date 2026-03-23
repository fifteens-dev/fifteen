import 'package:flutter/material.dart';

/// 投稿編集状態を保持するChangeNotifier
/// PostCardEditScreen → PostFinalPreviewScreen 間で共有し、
/// 将来的にPostFinalPreviewScreen上でも編集できるように設計。
class PostEditState extends ChangeNotifier {
  int _selectedLayoutIndex;
  Offset _cardCenter; // 写真エリア内でのカード中心座標
  double _cardScale;
  double _cardRotation;
  double _startPosition; // 0.0〜1.0（30秒トラック内の開始位置）
  int _audioDurationSec;

  static const int totalDurationMs = 30000; // 30秒

  PostEditState({
    int selectedLayoutIndex = 1,
    Offset cardCenter = const Offset(180, 218),
    double cardScale = 1.0,
    double cardRotation = 0.0,
    double startPosition = 0.0,
    int audioDurationSec = 15,
  })  : _selectedLayoutIndex = selectedLayoutIndex,
        _cardCenter = cardCenter,
        _cardScale = cardScale,
        _cardRotation = cardRotation,
        _startPosition = startPosition,
        _audioDurationSec = audioDurationSec;

  int get selectedLayoutIndex => _selectedLayoutIndex;
  Offset get cardCenter => _cardCenter;
  double get cardScale => _cardScale;
  double get cardRotation => _cardRotation;
  double get startPosition => _startPosition;
  int get audioDurationSec => _audioDurationSec;
  int get audioStartMs => (_startPosition * totalDurationMs).round();

  /// カード左上座標を計算（Positioned配置用）
  Offset cardPositionForSize(Size cardSize) => Offset(
        _cardCenter.dx - cardSize.width * _cardScale / 2,
        _cardCenter.dy - cardSize.height * _cardScale / 2,
      );

  void setLayout(int index) {
    _selectedLayoutIndex = index;
    _cardScale = 1.0;
    notifyListeners();
  }

  void setCard({
    required Offset center,
    required double scale,
    required double rotation,
  }) {
    _cardCenter = center;
    _cardScale = scale;
    _cardRotation = rotation;
    notifyListeners();
  }

  void setStartPosition(double pos) {
    _startPosition = pos;
    notifyListeners();
  }

  /// ジェスチャー中に notifyListeners なしで更新（毎フレーム呼ばれるため）
  void updateCardSilent({
    required Offset center,
    required double scale,
    required double rotation,
  }) {
    _cardCenter = center;
    _cardScale = scale;
    _cardRotation = rotation;
  }

  /// 外部から notifyListeners を呼ぶ（ジェスチャー終了時等）
  void notify() => notifyListeners();

  /// 一括更新（PostCardEditScreenからナビゲート直前に使用）
  void updateAll({
    required int selectedLayoutIndex,
    required Offset cardCenter,
    required double cardScale,
    required double cardRotation,
    required double startPosition,
    required int audioDurationSec,
  }) {
    _selectedLayoutIndex = selectedLayoutIndex;
    _cardCenter = cardCenter;
    _cardScale = cardScale;
    _cardRotation = cardRotation;
    _startPosition = startPosition;
    _audioDurationSec = audioDurationSec;
    notifyListeners();
  }
}

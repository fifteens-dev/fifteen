/// PostCardで使用する定数
class PostCardConstants {
  // カードサイズ
  static const double cardBaseWidth = 363.0;
  static const double cardBaseHeight = 644.0;
  static const double cardBorderRadius = 18.0;

  // 写真エリア
  static const double photoHeightRatio = 484.0 / 644.0;

  // コンテンツエリア
  static const double contentHeightRatioFront = 294.0 / 644.0;
  static const double contentHeightRatioBack = 174.0 / 644.0;

  // いいねしたユーザーアイコン
  static const double likedUserIconSize = 25.0;
  static const double likedUserIconMargin = 4.0;
  static const int maxLikedUsersToShow = 2;

  // 再生ボタン
  static const double playButtonSize = 56.0;
  static const double playButtonIconSize = 32.0;
  static const double playButtonBorderWidth = 2.0;
  static const double playButtonBackgroundOpacity = 0.6;

  // アニメーション
  static const Duration flipAnimationDuration = Duration(milliseconds: 400);
  static const Duration playButtonAnimationDuration = Duration(milliseconds: 1000);
  static const Duration autoFlipDelay = Duration(milliseconds: 500);

  PostCardConstants._();
}

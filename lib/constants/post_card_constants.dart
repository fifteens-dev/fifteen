import 'package:flutter/material.dart';

/// 投稿カードのサイズに関する定数
class PostCardDimensions {
  PostCardDimensions._();

  /// カードの幅
  static const double cardWidth = 363.0;

  /// カードの高さ
  static const double cardHeight = 644.0;

  /// 写真エリアの高さ（裏面）
  static const double photoHeight = 484.0;

  /// コンテンツエリアの高さ（裏面）
  static const double contentHeight = 174.0;

  /// 表面のコンテンツエリアの高さ
  static const double frontContentHeight = 294.0;

  /// カードの角丸
  static const double borderRadius = 18.0;

  /// 標準パディング
  static const double horizontalPadding = 12.0;

  /// コメントボタンの高さ
  static const double commentButtonHeight = 43.0;

  /// コメントボタンの角丸
  static const double commentButtonRadius = 12.0;
}

/// アバター（プロフィールアイコン）のサイズ定数
class AvatarSizes {
  AvatarSizes._();

  /// 小サイズ（保存ユーザー表示など）
  static const double small = 25.0;

  /// 中サイズ（カード内ユーザー情報）
  static const double medium = 32.0;

  /// 大サイズ（プロフィール画面など）
  static const double large = 40.0;
}

/// アイコンサイズの定数
class IconSizes {
  IconSizes._();

  /// リアクションアイコン
  static const double reaction = 24.0;

  /// 小アイコン
  static const double small = 18.0;

  /// 中アイコン
  static const double medium = 20.0;

  /// シェアボタン
  static const double shareButton = 36.0;

  /// 再生ボタン
  static const double playButton = 56.0;

  /// 再生ボタン内アイコン
  static const double playButtonIcon = 32.0;
}

/// フォントサイズの定数
class PostCardFontSizes {
  PostCardFontSizes._();

  /// 曲名（大）
  static const double trackTitle = 22.0;

  /// 曲名（表面・大）
  static const double trackTitleLarge = 25.0;

  /// アーティスト名
  static const double artistName = 13.0;

  /// ユーザー名
  static const double username = 12.0;

  /// ハッシュタグ
  static const double hashtag = 8.0;

  /// リアクション数
  static const double reactionCount = 12.0;

  /// コメントボタン
  static const double commentButton = 14.0;

  /// Apple Music クレジット
  static const double credit = 10.0;
}

/// アニメーション時間の定数
class PostCardAnimations {
  PostCardAnimations._();

  /// カード反転アニメーション
  static const Duration flipDuration = Duration(milliseconds: 600);

  /// 自動反転までの遅延
  static const Duration autoFlipDelay = Duration(seconds: 2);

  /// 再生ボタンアニメーション
  static const Duration playButtonDuration = Duration(milliseconds: 1000);

  /// マーキースクロール速度
  static const Duration marqueeScrollDuration = Duration(seconds: 5);

  /// マーキー待機時間
  static const Duration marqueeWaitDuration = Duration(seconds: 1);
}

/// 位置計算用の比率定数
class PostCardPositionRatios {
  PostCardPositionRatios._();

  // 水平方向
  static const double leftPadding = 12 / 363;
  static const double rightPadding = 12 / 363;
  static const double rightLargePadding = 66 / 363;
  static const double shareButtonLeft = 314 / 363;

  // 垂直方向（bottomから）
  static const double reactionBottom = 80 / 644;
  static const double commentButtonBottom = 28 / 644;
  static const double creditBottom = 9 / 644;
  static const double trackInfoBottom = 110 / 644;
  static const double shareButtonBottom = 120 / 644;
}

/// テキストスタイルのプリセット
class PostCardTextStyles {
  PostCardTextStyles._();

  /// ユーザー名（白色）
  static const TextStyle usernameWhite = TextStyle(
    fontSize: PostCardFontSizes.username,
    fontWeight: FontWeight.w600,
    color: Colors.white,
    letterSpacing: -0.12,
  );

  /// ハッシュタグ（白色）
  static const TextStyle hashtagWhite = TextStyle(
    fontSize: PostCardFontSizes.hashtag,
    color: Colors.white,
    letterSpacing: -0.08,
  );
}

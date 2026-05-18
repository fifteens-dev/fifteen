import 'package:flutter/material.dart';

/// 投稿カードのカラーテーマ
///
/// 将来的に何百通りものカラーバリエーションに対応するため、
/// 各テーマは独立したカラー設定を持つ
class PostTheme {
  final Color gradientStart; // グラデーション開始色（透明）
  final Color gradientEnd; // グラデーション終了色
  final Color commentButtonColor; // コメントボタンの背景色
  final Color textColor; // テキストの色（曲名、アーティスト名、ユーザー名など）
  final Color iconColor; // アイコンの色
  final Color secondaryTextColor; // "Provided courtesy of Apple Music"の色

  const PostTheme({
    required this.gradientStart,
    required this.gradientEnd,
    required this.commentButtonColor,
    required this.textColor,
    required this.iconColor,
    this.secondaryTextColor = const Color(0xFFB0B0B0),
  });

  /// Firestoreに保存するためのMap形式に変換
  Map<String, dynamic> toMap() {
    return {
      'gradientStart': gradientStart.value,
      'gradientEnd': gradientEnd.value,
      'commentButtonColor': commentButtonColor.value,
      'textColor': textColor.value,
      'iconColor': iconColor.value,
      'secondaryTextColor': secondaryTextColor.value,
    };
  }

  /// Firestoreから読み込むためのファクトリーメソッド
  factory PostTheme.fromMap(Map<String, dynamic> map) {
    int safeColor(String key, int fallback) {
      final v = map[key];
      return v is int ? v : fallback;
    }

    return PostTheme(
      gradientStart: Color(safeColor('gradientStart', 0x00C9DD77)),
      gradientEnd: Color(safeColor('gradientEnd', 0xFFC9DD77)),
      commentButtonColor: Color(safeColor('commentButtonColor', 0xFFB0C266)),
      textColor: Color(safeColor('textColor', 0xFFFFFFFF)),
      iconColor: Color(safeColor('iconColor', 0xFF000000)),
      secondaryTextColor: Color(safeColor('secondaryTextColor', 0xFFB0B0B0)),
    );
  }

  /// 青緑系テーマ（投稿カード1: いとしのエリー）
  static const PostTheme blueGreen = PostTheme(
    gradientStart: Color(0x004897B7),
    gradientEnd: Color(0xFF4897B7),
    commentButtonColor: Color(0xFF3C7F9A),
    textColor: Colors.white,
    iconColor: Colors.black,
  );

  /// 紫系テーマ（投稿カード2: いつか結婚しても）
  static const PostTheme purple = PostTheme(
    gradientStart: Color(0x002A1E4C),
    gradientEnd: Color(0xFF2A1E4C),
    commentButtonColor: Color(0xFF312458),
    textColor: Colors.white,
    iconColor: Colors.black,
  );

  /// ベージュ系テーマ（投稿カード3: LAST PARTY）
  static const PostTheme beige = PostTheme(
    gradientStart: Color(0x00ECE5D2),
    gradientEnd: Color(0xFFECE5D2),
    commentButtonColor: Color(0xFFDCD6C4),
    textColor: Color(0xFF5D5C4A),
    iconColor: Color(0xFF5D5C4A),
  );

  /// デフォルトテーマ（黄緑系 - 既存の実装）
  static const PostTheme defaultTheme = PostTheme(
    gradientStart: Color(0x00C9DD77),
    gradientEnd: Color(0xFFC9DD77),
    commentButtonColor: Color(0xFFB0C266),
    textColor: Colors.black,
    iconColor: Colors.black,
  );

  /// 利用可能な全テーマのリスト
  static const List<PostTheme> allThemes = [
    blueGreen,
    purple,
    beige,
    defaultTheme,
  ];

  /// ランダムにテーマを取得（将来的に使用）
  static PostTheme random() {
    return allThemes[(DateTime.now().millisecondsSinceEpoch % allThemes.length)];
  }
}

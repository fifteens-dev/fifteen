import 'package:flutter/material.dart';

/// 大学名ごとのグラデーション色テーブル
/// 特定大学は明示マップ、それ以外はハッシュで決定論的に割り当てる
class UniversityColors {
  UniversityColors._();

  static const List<List<Color>> _palette = [
    [Color(0xFF133600), Color(0xFF091B03)], // 緑（デフォルト）
    [Color(0xFF001B6E), Color(0xFF000D38)], // ディープブルー
    [Color(0xFF2D0052), Color(0xFF150026)], // ディープパープル
    [Color(0xFF5C0000), Color(0xFF2A0000)], // ダークレッド
    [Color(0xFF003D3D), Color(0xFF001A1A)], // ダークティール
    [Color(0xFF00225C), Color(0xFF001029)], // ネイビー
    [Color(0xFF3D1600), Color(0xFF1A0800)], // ダークオレンジ
    [Color(0xFF1A0A5C), Color(0xFF08042A)], // ダークインディゴ
    [Color(0xFF003D2D), Color(0xFF001A14)], // ダークグリーンティール
    [Color(0xFF3D0029), Color(0xFF1A0014)], // ダークマルーン
  ];

  /// 大学名ごとに固定された2色グラデーションを返す
  static List<Color> gradientFor(String university) {
    // 明示マップ（大学名 → パレットインデックス）
    const overrides = <String, int>{
      '青山学院大学': 0, // 緑
    };

    for (final key in overrides.keys) {
      if (university.contains(key.replaceAll('大学', ''))) {
        return _palette[overrides[key]!];
      }
    }

    final hash = university.codeUnits.fold(0, (a, b) => a + b);
    return _palette[hash % _palette.length];
  }
}

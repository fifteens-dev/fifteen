/// 感情タグの定数リスト
class EmotionTags {
  /// 感情タグの一覧
  static const List<String> tags = [
    '嬉しい',
    '楽しい',
    '幸せ',
    '悲しい',
    '切ない',
    '寂しい',
    '懐かしい',
    '穏やか',
    'リラックス',
    '元気',
    'テンション高め',
    '落ち着く',
    '癒される',
    '励まされる',
    '前向き',
  ];

  /// ランダムに感情タグを取得
  static String getRandomTag() {
    final index = DateTime.now().millisecondsSinceEpoch % tags.length;
    return tags[index];
  }

  /// 感情タグが有効かチェック
  static bool isValidTag(String tag) {
    return tags.contains(tag);
  }
}

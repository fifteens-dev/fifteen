/// 事前定義されたVibeお題リスト
class PredefinedVibeTopics {
  /// お題の一覧
  static const List<String> topics = [
    'ドライブで聴きたい曲',
    '雨の日に聴きたい曲',
    '朝に聴きたい曲',
    '夜に聴きたい曲',
    '作業中に聴きたい曲',
    '運動中に聴きたい曲',
    'リラックスしたい時の曲',
    'テンションを上げたい曲',
    '懐かしい曲',
    '最近ハマっている曲',
    '通勤・通学で聴きたい曲',
    '勉強中に聴きたい曲',
    '寝る前に聴きたい曲',
    '元気が出る曲',
    '切ない曲',
    '夏に聴きたい曲',
    '冬に聴きたい曲',
    '春に聴きたい曲',
    '秋に聴きたい曲',
    'デートで聴きたい曲',
  ];

  /// ランダムにお題を取得
  static String getRandomTopic() {
    final index = DateTime.now().millisecondsSinceEpoch % topics.length;
    return topics[index];
  }

  /// お題が有効かチェック
  static bool isValidTopic(String topic) {
    return topics.contains(topic);
  }
}

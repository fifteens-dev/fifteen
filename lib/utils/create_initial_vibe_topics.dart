import '../services/vibe_topic_service.dart';
import '../constants/predefined_vibe_topics.dart';
import '../utils/app_log.dart';

/// 初期Vibeお題データを作成する関数
/// 開発環境用のテストデータ
Future<void> createInitialVibeTopics() async {
  final service = VibeTopicService();

  try {
    AppLog.debug('🎵 初期Vibeお題データを作成中...');

    // 今日のアクティブなお題
    final today = DateTime.now();
    final todayTopic = PredefinedVibeTopics.topics[0]; // 最初のお題を使用
    final todayTopicId = await service.createTopic(todayTopic, today);
    AppLog.debug('✅ 今日のお題を作成: $todayTopic (ID: $todayTopicId)');

    // 投票中のお題（明日用）- 事前定義リストからいくつか選択
    final tomorrow = today.add(const Duration(days: 1));
    final votingTopics = PredefinedVibeTopics.topics.sublist(1, 5);

    for (final title in votingTopics) {
      final topicId = await service.createTopic(title, tomorrow);
      AppLog.debug('✅ 投票中のお題を作成: $title (ID: $topicId)');
    }

    AppLog.debug('🎉 初期Vibeお題データの作成が完了しました！');
  } catch (e) {
    AppLog.debug('❌ 初期お題データ作成エラー: $e');
    rethrow;
  }
}

/// すべての事前定義お題を投票候補として作成
/// （翌日用のお題候補を一括作成）
Future<void> createAllVotingTopics() async {
  final service = VibeTopicService();

  try {
    AppLog.debug('🎵 全てのお題候補を作成中...');

    final tomorrow = DateTime.now().add(const Duration(days: 1));

    for (final title in PredefinedVibeTopics.topics) {
      try {
        final topicId = await service.createTopic(title, tomorrow);
        AppLog.debug('✅ お題候補を作成: $title (ID: $topicId)');
      } catch (e) {
        AppLog.debug('⚠️ お題「$title」の作成をスキップ: $e');
      }
    }

    AppLog.debug('🎉 全てのお題候補の作成が完了しました！');
  } catch (e) {
    AppLog.debug('❌ お題候補作成エラー: $e');
    rethrow;
  }
}

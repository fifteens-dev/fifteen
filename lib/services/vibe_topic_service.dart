import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import '../models/vibe_topic_model.dart';

/// Vibeお題データを管理するサービス
class VibeTopicService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final String _topicsCollection = 'vibe_topics';

  /// 今日のお題を取得（activeステータス優先、フォールバックでarchived）
  Future<VibeTopicModel?> getTodaysTopic() async {
    try {
      final today = DateTime.now();
      final startOfDay = DateTime(today.year, today.month, today.day);
      final endOfDay = startOfDay.add(const Duration(days: 1));

      // 今日の日付でお題を取得
      final snapshot = await _firestore
          .collection(_topicsCollection)
          .where('date', isGreaterThanOrEqualTo: Timestamp.fromDate(startOfDay))
          .where('date', isLessThan: Timestamp.fromDate(endOfDay))
          .get();

      if (snapshot.docs.isEmpty) {
        return null;
      }

      final topics = snapshot.docs
          .map((doc) => VibeTopicModel.fromFirestore(doc))
          .toList();

      final activeTopic =
          topics.where((t) => t.status == VibeTopicStatus.active).firstOrNull;
      if (activeTopic != null) return activeTopic;

      // ステータス更新漏れのフォールバック
      return topics.firstOrNull;
    } catch (e) {
      if (kDebugMode) {
        print('Error getting today\'s topic: $e');
      }
      return null;
    }
  }

  /// 翌日の投票候補お題一覧を取得
  Future<List<VibeTopicModel>> getVotingTopics() async {
    try {
      final tomorrow = DateTime.now().add(const Duration(days: 1));
      final start = DateTime(tomorrow.year, tomorrow.month, tomorrow.day);
      final end = start.add(const Duration(days: 1));

      final snapshot = await _firestore
          .collection(_topicsCollection)
          .where('date', isGreaterThanOrEqualTo: Timestamp.fromDate(start))
          .where('date', isLessThan: Timestamp.fromDate(end))
          .get();

      return snapshot.docs
          .map((doc) => VibeTopicModel.fromFirestore(doc))
          .toList();
    } catch (e) {
      if (kDebugMode) print('Error getting voting topics: $e');
      return [];
    }
  }

  /// ユーザーが投票済みのtopicIdを取得（なければnull）
  Future<String?> getUserVote(String userId) async {
    try {
      final snapshot = await _firestore
          .collection('vibeVotes')
          .where('userId', isEqualTo: userId)
          .get();

      if (snapshot.docs.isEmpty) return null;
      return snapshot.docs.first.data()['topicId'] as String?;
    } catch (e) {
      if (kDebugMode) print('Error getting user vote: $e');
      return null;
    }
  }

  /// お題に投票（既存の投票は差し替え）
  Future<void> voteForTopic(String userId, String topicId) async {
    // 既存の投票を削除してvoteCountを減算
    final existing = await _firestore
        .collection('vibeVotes')
        .where('userId', isEqualTo: userId)
        .get();

    for (final doc in existing.docs) {
      final oldTopicId = doc.data()['topicId'] as String?;
      if (oldTopicId != null) {
        await _firestore.collection(_topicsCollection).doc(oldTopicId).update({
          'voteCount': FieldValue.increment(-1),
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }
      await doc.reference.delete();
    }

    // 新規投票を追加
    await _firestore.collection('vibeVotes').add({
      'userId': userId,
      'topicId': topicId,
      'createdAt': FieldValue.serverTimestamp(),
    });

    // voteCountを加算
    await _firestore.collection(_topicsCollection).doc(topicId).update({
      'voteCount': FieldValue.increment(1),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  /// お題を新規作成してIDを返す
  Future<String> createTopic(String title, DateTime date) async {
    final docRef = await _firestore.collection(_topicsCollection).add({
      'title': title,
      'emoji': '🎵',
      'date': Timestamp.fromDate(date),
      'status': VibeTopicStatus.active.name,
      'voteCount': 0,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    return docRef.id;
  }

  /// お題のステータスを更新（日次バッチ用）
  Future<void> updateTopicStatuses() async {
    try {
      final today = DateTime.now();
      final startOfToday = DateTime(today.year, today.month, today.day);
      final endOfToday = startOfToday.add(const Duration(days: 1));

      // 昨日までのactiveなお題をarchivedに
      final oldActiveTopics = await _firestore
          .collection(_topicsCollection)
          .where('status', isEqualTo: 'active')
          .where('date', isLessThan: Timestamp.fromDate(startOfToday))
          .get();

      for (final doc in oldActiveTopics.docs) {
        await doc.reference.update({
          'status': VibeTopicStatus.archived.name,
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }

      // 今日の日付のお題をactiveに
      final todaysTopics = await _firestore
          .collection(_topicsCollection)
          .where('date', isGreaterThanOrEqualTo: Timestamp.fromDate(startOfToday))
          .where('date', isLessThan: Timestamp.fromDate(endOfToday))
          .get();

      for (final doc in todaysTopics.docs) {
        await doc.reference.update({
          'status': VibeTopicStatus.active.name,
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }

      if (kDebugMode) {
        print('Topic statuses updated successfully');
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error updating topic statuses: $e');
      }
      rethrow;
    }
  }
}

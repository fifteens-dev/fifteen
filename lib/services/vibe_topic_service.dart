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

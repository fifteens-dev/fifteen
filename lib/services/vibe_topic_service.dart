import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import '../models/vibe_topic_model.dart';

/// Vibeお題データを管理するサービス
class VibeTopicService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final String _topicsCollection = 'vibe_topics';
  final String _votesCollection = 'vibeVotes';

  /// 今日のお題を取得（activeまたはvotingステータス）
  Future<VibeTopicModel?> getTodaysTopic() async {
    try {
      final today = DateTime.now();
      final startOfDay = DateTime(today.year, today.month, today.day);
      final endOfDay = startOfDay.add(const Duration(days: 1));

      // 今日の日付でお題を取得（インデックス不要のクエリ）
      final snapshot = await _firestore
          .collection(_topicsCollection)
          .where('date', isGreaterThanOrEqualTo: Timestamp.fromDate(startOfDay))
          .where('date', isLessThan: Timestamp.fromDate(endOfDay))
          .get();

      if (snapshot.docs.isEmpty) {
        return null;
      }

      // コード側でステータスをフィルタリング（activeを優先）
      final topics = snapshot.docs
          .map((doc) => VibeTopicModel.fromFirestore(doc))
          .toList();

      // activeなお題を探す
      final activeTopic = topics.where((t) => t.status == VibeTopicStatus.active).firstOrNull;
      if (activeTopic != null) {
        return activeTopic;
      }

      // votingなお題を探す
      final votingTopic = topics.where((t) => t.status == VibeTopicStatus.voting).firstOrNull;
      if (votingTopic != null) {
        return votingTopic;
      }

      return null;
    } catch (e) {
      if (kDebugMode) {
        print('Error getting today\'s topic: $e');
      }
      return null;
    }
  }

  /// 投票中のお題候補を取得（複数）
  Future<List<VibeTopicModel>> getVotingTopics() async {
    try {
      final snapshot = await _firestore
          .collection(_topicsCollection)
          .where('status', isEqualTo: 'voting')
          .orderBy('voteCount', descending: true)
          .get();

      return snapshot.docs
          .map((doc) => VibeTopicModel.fromFirestore(doc))
          .toList();
    } catch (e) {
      if (kDebugMode) {
        print('Error getting voting topics: $e');
      }
      return [];
    }
  }

  /// お題に投票（二重投票防止）
  Future<void> voteForTopic(String userId, String topicId) async {
    try {
      // トランザクションで二重投票を防止
      await _firestore.runTransaction((transaction) async {
        // 既存の投票を確認
        final existingVote = await _firestore
            .collection(_votesCollection)
            .where('userId', isEqualTo: userId)
            .limit(1)
            .get();

        // 既存の投票がある場合は削除
        if (existingVote.docs.isNotEmpty) {
          final oldVoteDoc = existingVote.docs.first;
          final oldTopicId = oldVoteDoc.data()['topicId'] as String;

          // 古い投票を削除
          transaction.delete(oldVoteDoc.reference);

          // 古いお題のvoteCountを減らす
          if (oldTopicId != topicId) {
            final oldTopicRef =
                _firestore.collection(_topicsCollection).doc(oldTopicId);
            transaction.update(oldTopicRef, {
              'voteCount': FieldValue.increment(-1),
              'updatedAt': FieldValue.serverTimestamp(),
            });
          }
        }

        // 新しい投票を追加
        final voteRef = _firestore.collection(_votesCollection).doc();
        transaction.set(voteRef, {
          'userId': userId,
          'topicId': topicId,
          'votedAt': FieldValue.serverTimestamp(),
        });

        // お題のvoteCountを増やす
        final topicRef = _firestore.collection(_topicsCollection).doc(topicId);
        transaction.update(topicRef, {
          'voteCount': FieldValue.increment(1),
          'updatedAt': FieldValue.serverTimestamp(),
        });
      });
    } catch (e) {
      if (kDebugMode) {
        print('Error voting for topic: $e');
      }
      rethrow;
    }
  }

  /// ユーザーの投票状況を取得
  Future<String?> getUserVote(String userId) async {
    try {
      final snapshot = await _firestore
          .collection(_votesCollection)
          .where('userId', isEqualTo: userId)
          .limit(1)
          .get();

      if (snapshot.docs.isEmpty) {
        return null;
      }

      return snapshot.docs.first.data()['topicId'] as String?;
    } catch (e) {
      if (kDebugMode) {
        print('Error getting user vote: $e');
      }
      return null;
    }
  }

  /// 新しいお題を作成（管理者用/初期データ）
  Future<String> createTopic(String title, DateTime targetDate) async {
    try {
      final topicRef = _firestore.collection(_topicsCollection).doc();

      // 日付を正規化（時刻を00:00:00に設定）
      final normalizedDate = DateTime(
        targetDate.year,
        targetDate.month,
        targetDate.day,
      );

      // ステータスの決定（今日の日付ならactive、それ以外はvoting）
      final today = DateTime.now();
      final isToday = normalizedDate.year == today.year &&
          normalizedDate.month == today.month &&
          normalizedDate.day == today.day;

      final status = isToday ? VibeTopicStatus.active : VibeTopicStatus.voting;

      final topicData = {
        'title': title,
        'date': Timestamp.fromDate(normalizedDate),
        'status': status.name,
        'voteCount': 0,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      };

      await topicRef.set(topicData);
      return topicRef.id;
    } catch (e) {
      if (kDebugMode) {
        print('Error creating topic: $e');
      }
      rethrow;
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

  /// 投票数を再集計（データ整合性チェック用）
  Future<void> recalculateVoteCount(String topicId) async {
    try {
      final votesSnapshot = await _firestore
          .collection(_votesCollection)
          .where('topicId', isEqualTo: topicId)
          .get();

      final voteCount = votesSnapshot.docs.length;

      await _firestore.collection(_topicsCollection).doc(topicId).update({
        'voteCount': voteCount,
        'updatedAt': FieldValue.serverTimestamp(),
      });

      if (kDebugMode) {
        print('Vote count recalculated for topic $topicId: $voteCount votes');
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error recalculating vote count: $e');
      }
      rethrow;
    }
  }
}

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import '../models/vibe_topic_model.dart';

/// 管理者用サービス
/// 一斉通知とVibeお題管理の機能を提供
class AdminService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  /// 管理者ユーザー名
  static const String adminUsername = 'Fifteens_Administrator';

  /// 現在のユーザーが管理者かどうかをチェック
  Future<bool> isCurrentUserAdmin() async {
    try {
      final currentUser = _auth.currentUser;
      if (currentUser == null) return false;

      final userDoc = await _firestore
          .collection('users')
          .doc(currentUser.uid)
          .get();

      if (!userDoc.exists) return false;

      final userData = userDoc.data();
      return userData?['isAdmin'] == true;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ 管理者チェックエラー: $e');
      }
      return false;
    }
  }

  /// ユーザーを管理者に設定
  Future<void> setUserAsAdmin(String userId, {bool isAdmin = true}) async {
    try {
      // 現在のユーザーが管理者かチェック
      final isCurrentAdmin = await isCurrentUserAdmin();
      if (!isCurrentAdmin) {
        throw Exception('管理者権限がありません');
      }

      await _firestore.collection('users').doc(userId).update({
        'isAdmin': isAdmin,
        'updatedAt': FieldValue.serverTimestamp(),
      });

      if (kDebugMode) {
        debugPrint('✅ ユーザー $userId の管理者権限を ${isAdmin ? "付与" : "削除"} しました');
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ 管理者設定エラー: $e');
      }
      rethrow;
    }
  }

  /// 管理者アカウントを初期化（最初の管理者を作成）
  /// 注意: この関数は開発時のみ使用し、本番環境では別の方法で管理者を設定すること
  Future<void> initializeAdminAccount(String userId) async {
    try {
      await _firestore.collection('users').doc(userId).update({
        'username': adminUsername,
        'isAdmin': true,
        'updatedAt': FieldValue.serverTimestamp(),
      });

      if (kDebugMode) {
        debugPrint('✅ 管理者アカウントを初期化しました: $adminUsername');
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ 管理者アカウント初期化エラー: $e');
      }
      rethrow;
    }
  }

  // ========== 一斉通知機能 ==========

  /// 全ユーザーに一斉通知を送信
  Future<void> sendBroadcastNotification({
    required String title,
    required String body,
    String? actionType,
    String? actionId,
  }) async {
    try {
      // 管理者チェック
      final isAdmin = await isCurrentUserAdmin();
      if (!isAdmin) {
        throw Exception('管理者権限がありません');
      }

      // 一斉通知ドキュメントを作成
      final notificationRef = _firestore.collection('broadcast_notifications').doc();

      await notificationRef.set({
        'notificationId': notificationRef.id,
        'title': title,
        'body': body,
        'actionType': actionType, // 'vibe', 'post', 'announcement' など
        'actionId': actionId,
        'sentAt': FieldValue.serverTimestamp(),
        'sentBy': _auth.currentUser?.uid,
      });

      // 全ユーザーの通知コレクションに追加
      final usersSnapshot = await _firestore.collection('users').get();

      final batch = _firestore.batch();
      for (final userDoc in usersSnapshot.docs) {
        final userNotificationRef = _firestore
            .collection('users')
            .doc(userDoc.id)
            .collection('notifications')
            .doc();

        batch.set(userNotificationRef, {
          'notificationId': userNotificationRef.id,
          'type': 'broadcast',
          'title': title,
          'body': body,
          'actionType': actionType,
          'actionId': actionId,
          'isRead': false,
          'createdAt': FieldValue.serverTimestamp(),
        });
      }

      await batch.commit();

      if (kDebugMode) {
        debugPrint('✅ 一斉通知を送信しました: $title (${usersSnapshot.docs.length}人)');
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ 一斉通知送信エラー: $e');
      }
      rethrow;
    }
  }

  /// 一斉通知履歴を取得
  Future<List<Map<String, dynamic>>> getBroadcastNotificationHistory({
    int limit = 20,
  }) async {
    try {
      final snapshot = await _firestore
          .collection('broadcast_notifications')
          .orderBy('sentAt', descending: true)
          .limit(limit)
          .get();

      return snapshot.docs.map((doc) => doc.data()).toList();
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ 一斉通知履歴取得エラー: $e');
      }
      return [];
    }
  }

  // ========== Vibeお題管理機能 ==========

  /// 新しいVibeお題を作成
  Future<String> createVibeTopic({
    required String title,
    required DateTime date,
  }) async {
    try {
      // 管理者チェック
      final isAdmin = await isCurrentUserAdmin();
      if (!isAdmin) {
        throw Exception('管理者権限がありません');
      }

      final topicRef = _firestore.collection('vibe_topics').doc();
      final now = DateTime.now();

      final topic = VibeTopicModel(
        topicId: topicRef.id,
        title: title,
        date: date,
        status: VibeTopicStatus.voting,
        createdAt: now,
        updatedAt: now,
      );

      await topicRef.set(topic.toMap());

      if (kDebugMode) {
        debugPrint('✅ Vibeお題を作成しました: $title (${date.toString().substring(0, 10)})');
      }

      return topicRef.id;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ Vibeお題作成エラー: $e');
      }
      rethrow;
    }
  }

  /// Vibeお題を更新
  Future<void> updateVibeTopic({
    required String topicId,
    String? title,
    DateTime? date,
    VibeTopicStatus? status,
  }) async {
    try {
      // 管理者チェック
      final isAdmin = await isCurrentUserAdmin();
      if (!isAdmin) {
        throw Exception('管理者権限がありません');
      }

      final updateData = <String, dynamic>{
        'updatedAt': FieldValue.serverTimestamp(),
      };

      if (title != null) updateData['title'] = title;
      if (date != null) updateData['date'] = Timestamp.fromDate(date);
      if (status != null) updateData['status'] = status.name;

      await _firestore.collection('vibe_topics').doc(topicId).update(updateData);

      if (kDebugMode) {
        debugPrint('✅ Vibeお題を更新しました: $topicId');
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ Vibeお題更新エラー: $e');
      }
      rethrow;
    }
  }

  /// Vibeお題を削除
  Future<void> deleteVibeTopic(String topicId) async {
    try {
      // 管理者チェック
      final isAdmin = await isCurrentUserAdmin();
      if (!isAdmin) {
        throw Exception('管理者権限がありません');
      }

      await _firestore.collection('vibe_topics').doc(topicId).delete();

      if (kDebugMode) {
        debugPrint('✅ Vibeお題を削除しました: $topicId');
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ Vibeお題削除エラー: $e');
      }
      rethrow;
    }
  }

  /// 全てのVibeお題を取得（管理者用）
  Future<List<VibeTopicModel>> getAllVibeTopics({
    int limit = 50,
  }) async {
    try {
      final snapshot = await _firestore
          .collection('vibe_topics')
          .orderBy('date', descending: true)
          .limit(limit)
          .get();

      return snapshot.docs
          .map((doc) => VibeTopicModel.fromFirestore(doc))
          .toList();
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ Vibeお題取得エラー: $e');
      }
      return [];
    }
  }

  /// 今後のVibeお題を取得（予定されているお題）
  Future<List<VibeTopicModel>> getUpcomingVibeTopics() async {
    try {
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);

      final snapshot = await _firestore
          .collection('vibe_topics')
          .where('date', isGreaterThanOrEqualTo: Timestamp.fromDate(today))
          .orderBy('date')
          .get();

      return snapshot.docs
          .map((doc) => VibeTopicModel.fromFirestore(doc))
          .toList();
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ 今後のVibeお題取得エラー: $e');
      }
      return [];
    }
  }
}

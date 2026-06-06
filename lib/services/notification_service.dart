import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import '../models/notification_model.dart';
import 'settings_service.dart';

/// 通知サービス
/// - 通知のCRUD操作
/// - FCMトークン管理
/// - 未読数管理
class NotificationService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final SettingsService _settingsService = SettingsService();
  final String _notificationsCollection = 'notifications';
  final String _fcmTokensCollection = 'user_fcm_tokens';

  // === 通知CRUD操作 ===

  /// 通知を作成（ユーザー設定チェック付き）
  Future<void> createNotification({
    required NotificationType type,
    required String recipientId,
    required String senderId,
    required String senderUsername,
    String? senderIconUrl,
    String? postId,
    String? albumArtUrl,
    String? trackName,
    String? commentText,
    String? title,
    String? body,
    String? imageUrl,
    String? actionUrl,
  }) async {
    try {
      // 自分自身へのアクションはスキップ
      if (recipientId == senderId) {
        if (kDebugMode) {
          print('通知スキップ: 自分自身へのアクション');
        }
        return;
      }

      // テスト投稿（test_post_プレフィックス）の場合はスキップ
      if (postId != null && postId.startsWith('test_post_')) {
        if (kDebugMode) {
          print('通知スキップ: テスト投稿');
        }
        return;
      }

      // ユーザーの通知設定を確認
      final shouldNotify = await _checkUserNotificationSettings(type);
      if (!shouldNotify) {
        if (kDebugMode) {
          print('通知スキップ: ユーザー設定で無効化 (type: $type)');
        }
        return;
      }

      // 通知を作成
      final notification = NotificationModel(
        notificationId: '',
        type: type,
        recipientId: recipientId,
        senderId: senderId,
        senderUsername: senderUsername,
        senderIconUrl: senderIconUrl,
        postId: postId,
        albumArtUrl: albumArtUrl,
        trackName: trackName,
        commentText: commentText,
        title: title,
        body: body,
        imageUrl: imageUrl,
        actionUrl: actionUrl,
        createdAt: DateTime.now(),
      );

      final docRef = await _firestore
          .collection(_notificationsCollection)
          .add(notification.toMap());

      // FCMプッシュ通知を送信（Cloud Function経由）
      await _sendPushNotification(
        recipientId: recipientId,
        notification: notification,
      );

      if (kDebugMode) {
        print('通知作成成功: ${docRef.id} (type: $type)');
      }
    } catch (e) {
      if (kDebugMode) {
        print('通知作成エラー: $e');
      }
      rethrow;
    }
  }

  /// ユーザーの通知設定をチェック
  Future<bool> _checkUserNotificationSettings(NotificationType type) async {
    try {
      switch (type) {
        case NotificationType.like:
        case NotificationType.comment:
          return await _settingsService.getLikeCommentNotification();
        case NotificationType.follow:
          return await _settingsService.getFollowNotification();
        case NotificationType.official:
          return await _settingsService.getOfficialNotification();
        case NotificationType.post:
          return await _settingsService.getPostNotification();
        case NotificationType.vibe:
          return await _settingsService.getVibeNotification();
        case NotificationType.mention:
          return await _settingsService.getLikeCommentNotification();
      }
    } catch (e) {
      if (kDebugMode) {
        print('通知設定チェックエラー: $e');
      }
      // エラー時はデフォルトで通知を送る
      return true;
    }
  }

  /// ユーザーの通知一覧を取得（Stream・先頭ページのリアルタイム監視用）
  Stream<List<NotificationModel>> getNotificationsStream(String userId, {int limit = 20}) {
    return _firestore
        .collection(_notificationsCollection)
        .where('recipientId', isEqualTo: userId)
        .orderBy('createdAt', descending: true)
        .limit(limit)
        .snapshots()
        .map((snapshot) {
      return snapshot.docs
          .map((doc) => NotificationModel.fromFirestore(doc))
          .toList();
    });
  }

  /// 通知をカーソルページネーションで取得（追加読み込み用）
  Future<({List<NotificationModel> notifications, DocumentSnapshot? lastDoc, bool hasMore})>
      getNotificationsPaged(
    String userId, {
    int limit = 20,
    DocumentSnapshot? startAfter,
  }) async {
    var query = _firestore
        .collection(_notificationsCollection)
        .where('recipientId', isEqualTo: userId)
        .orderBy('createdAt', descending: true)
        .limit(limit);

    if (startAfter != null) {
      query = query.startAfterDocument(startAfter);
    }

    final snapshot = await query.get();
    return (
      notifications: snapshot.docs
          .map((doc) => NotificationModel.fromFirestore(doc))
          .toList(),
      lastDoc: snapshot.docs.isNotEmpty ? snapshot.docs.last : null,
      hasMore: snapshot.docs.length == limit,
    );
  }

  /// 未読通知数を取得（Stream）
  Stream<int> getUnreadCountStream(String userId) {
    return _firestore
        .collection(_notificationsCollection)
        .where('recipientId', isEqualTo: userId)
        .where('isRead', isEqualTo: false)
        .snapshots()
        .map((snapshot) => snapshot.docs.length);
  }

  /// 通知を既読にする
  Future<void> markAsRead(String notificationId) async {
    try {
      await _firestore
          .collection(_notificationsCollection)
          .doc(notificationId)
          .update({
        'isRead': true,
        'readAt': FieldValue.serverTimestamp(),
      });

      if (kDebugMode) {
        print('通知を既読にしました: $notificationId');
      }
    } catch (e) {
      if (kDebugMode) {
        print('既読マークエラー: $e');
      }
      rethrow;
    }
  }

  /// 全ての通知を既読にする
  Future<void> markAllAsRead(String userId) async {
    try {
      final snapshot = await _firestore
          .collection(_notificationsCollection)
          .where('recipientId', isEqualTo: userId)
          .where('isRead', isEqualTo: false)
          .get();

      final batch = _firestore.batch();
      for (final doc in snapshot.docs) {
        batch.update(doc.reference, {
          'isRead': true,
          'readAt': FieldValue.serverTimestamp(),
        });
      }
      await batch.commit();

      if (kDebugMode) {
        print('${snapshot.docs.length}件の通知を既読にしました');
      }
    } catch (e) {
      if (kDebugMode) {
        print('一括既読マークエラー: $e');
      }
      rethrow;
    }
  }

  /// 通知を削除
  Future<void> deleteNotification(String notificationId) async {
    try {
      await _firestore
          .collection(_notificationsCollection)
          .doc(notificationId)
          .delete();

      if (kDebugMode) {
        print('通知を削除しました: $notificationId');
      }
    } catch (e) {
      if (kDebugMode) {
        print('通知削除エラー: $e');
      }
      rethrow;
    }
  }

  // === FCMトークン管理 ===

  /// FCMトークンを保存/更新
  Future<void> saveFCMToken(String userId, String token, String platform) async {
    try {
      final docRef = _firestore.collection(_fcmTokensCollection).doc(userId);
      final doc = await docRef.get();

      final now = Timestamp.now();
      final tokenData = {
        'token': token,
        'platform': platform,
        'createdAt': now,
        'lastUsedAt': now,
      };

      if (doc.exists) {
        // 同じプラットフォームの既存トークンをすべて除去してから追加
        // （アプリ再インストール等でトークンが変わった場合に古いものが残るのを防ぐ）
        final currentTokens = List<dynamic>.from(doc.data()?['tokens'] ?? []);
        final filteredTokens = currentTokens
            .where((t) => t['token'] != token && t['platform'] != platform)
            .toList();
        filteredTokens.add(tokenData);
        await docRef.update({
          'tokens': filteredTokens,
          'updatedAt': FieldValue.serverTimestamp(),
        });
      } else {
        // 新規作成
        await docRef.set({
          'userId': userId,
          'tokens': [tokenData],
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }

      if (kDebugMode) {
        print('FCMトークンを保存しました: $userId ($platform)');
      }
    } catch (e) {
      if (kDebugMode) {
        print('FCMトークン保存エラー: $e');
      }
      rethrow;
    }
  }

  /// FCMトークンを削除
  Future<void> deleteFCMToken(String userId, String token) async {
    try {
      final docRef = _firestore.collection(_fcmTokensCollection).doc(userId);
      await docRef.update({
        'tokens': FieldValue.arrayRemove([
          {'token': token}
        ]),
        'updatedAt': FieldValue.serverTimestamp(),
      });

      if (kDebugMode) {
        print('FCMトークンを削除しました: $userId');
      }
    } catch (e) {
      if (kDebugMode) {
        print('FCMトークン削除エラー: $e');
      }
      // トークン削除の失敗は致命的ではないため、エラーを飲み込む
    }
  }

  /// プッシュ通知を送信（Cloud Function経由）
  Future<void> _sendPushNotification({
    required String recipientId,
    required NotificationModel notification,
  }) async {
    try {
      // Cloud Functionを呼び出してプッシュ通知を送信
      // ここではFirestoreに送信リクエストを書き込む方式を採用
      await _firestore.collection('push_notification_requests').add({
        'recipientId': recipientId,
        'notificationType': notification.type.toString().split('.').last,
        'senderId': notification.senderId,
        'senderUsername': notification.senderUsername,
        'message': notification.getMessage(),
        'postId': notification.postId,
        'title': notification.title,
        'body': notification.body,
        'imageUrl': notification.imageUrl,
        'actionUrl': notification.actionUrl,
        'createdAt': FieldValue.serverTimestamp(),
        'processed': false,
      });

      if (kDebugMode) {
        print('プッシュ通知リクエストを作成しました: $recipientId');
      }
    } catch (e) {
      if (kDebugMode) {
        print('プッシュ通知リクエスト作成エラー: $e');
      }
      // プッシュ通知失敗は致命的エラーではないため、続行
    }
  }
}

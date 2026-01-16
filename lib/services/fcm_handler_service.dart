import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'notification_service.dart';

/// トップレベル関数: バックグラウンドメッセージハンドラ
/// アプリがバックグラウンドまたは終了状態のときにFCMメッセージを処理
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  if (kDebugMode) {
    print('🔔 バックグラウンドメッセージ受信: ${message.messageId}');
    print('   タイトル: ${message.notification?.title}');
    print('   本文: ${message.notification?.body}');
    print('   データ: ${message.data}');
  }
}

/// FCMハンドラーサービス
/// - FCMの初期化
/// - プッシュ通知の受信処理
/// - FCMトークンの管理
class FCMHandlerService {
  final FirebaseMessaging _messaging = FirebaseMessaging.instance;
  final NotificationService _notificationService = NotificationService();

  // シングルトンパターン
  static final FCMHandlerService _instance = FCMHandlerService._internal();
  factory FCMHandlerService() => _instance;
  FCMHandlerService._internal();

  /// FCMを初期化
  Future<void> initialize(String userId) async {
    try {
      if (kDebugMode) {
        print('🔔 FCM初期化開始: userId=$userId');
      }

      // 通知権限をリクエスト
      final settings = await _messaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
        provisional: false,
      );

      if (kDebugMode) {
        print('📱 通知権限: ${settings.authorizationStatus}');
      }

      if (settings.authorizationStatus == AuthorizationStatus.denied) {
        if (kDebugMode) {
          print('⚠️ 通知権限が拒否されました');
        }
        return;
      }

      // バックグラウンドメッセージハンドラを設定
      FirebaseMessaging.onBackgroundMessage(
          _firebaseMessagingBackgroundHandler);

      // フォアグラウンドメッセージハンドラを設定
      FirebaseMessaging.onMessage.listen(_handleForegroundMessage);

      // 通知タップ時の処理（アプリがバックグラウンドから起動）
      FirebaseMessaging.onMessageOpenedApp.listen(_handleMessageOpenedApp);

      // アプリが終了状態から通知タップで起動した場合の処理
      final initialMessage = await _messaging.getInitialMessage();
      if (initialMessage != null) {
        _handleMessageOpenedApp(initialMessage);
      }

      // FCMトークンを取得して保存
      final token = await _messaging.getToken();
      if (token != null) {
        final platform = _getPlatform();
        await _notificationService.saveFCMToken(userId, token, platform);

        if (kDebugMode) {
          print('🔑 FCMトークン取得: ${token.substring(0, 20)}...');
        }
      }

      // トークンリフレッシュ時の処理
      _messaging.onTokenRefresh.listen((newToken) {
        final platform = _getPlatform();
        _notificationService.saveFCMToken(userId, newToken, platform);

        if (kDebugMode) {
          print('🔄 FCMトークンリフレッシュ: ${newToken.substring(0, 20)}...');
        }
      });

      // 全ユーザートピックに購読（公式通知用）
      await _messaging.subscribeToTopic('all_users');

      if (kDebugMode) {
        print('📢 トピック購読: all_users');
        print('✅ FCM初期化完了');
      }
    } catch (e) {
      if (kDebugMode) {
        print('❌ FCM初期化エラー: $e');
      }
    }
  }

  /// フォアグラウンドメッセージを処理
  void _handleForegroundMessage(RemoteMessage message) {
    if (kDebugMode) {
      print('🔔 フォアグラウンドメッセージ受信: ${message.messageId}');
      print('   タイトル: ${message.notification?.title}');
      print('   本文: ${message.notification?.body}');
      print('   データ: ${message.data}');
    }

    // アプリ内通知を表示（オプション）
    // ここでSnackBarやカスタムUIを表示可能
    // 例: _showInAppNotification(message);
  }

  /// 通知タップ時の処理
  void _handleMessageOpenedApp(RemoteMessage message) {
    if (kDebugMode) {
      print('👆 通知タップ: ${message.messageId}');
      print('   データ: ${message.data}');
    }

    // 通知データから適切な画面に遷移
    final notificationType = message.data['type'] as String?;
    final postId = message.data['postId'] as String?;
    final userId = message.data['userId'] as String?;
    final actionUrl = message.data['actionUrl'] as String?;

    // TODO: NavigatorKeyを使用して画面遷移を実装
    // 例:
    // if (postId != null) {
    //   navigatorKey.currentState?.pushNamed('/post-detail', arguments: postId);
    // } else if (userId != null) {
    //   navigatorKey.currentState?.pushNamed('/profile', arguments: userId);
    // } else if (actionUrl != null) {
    //   // actionUrlに基づいて遷移
    // }

    if (kDebugMode) {
      print('   遷移先: type=$notificationType, postId=$postId, userId=$userId');
    }
  }

  /// プラットフォーム名を取得
  String _getPlatform() {
    if (kIsWeb) return 'web';
    if (defaultTargetPlatform == TargetPlatform.iOS) return 'ios';
    if (defaultTargetPlatform == TargetPlatform.android) return 'android';
    return 'unknown';
  }

  /// FCMトークンを取得
  Future<String?> getToken() async {
    try {
      return await _messaging.getToken();
    } catch (e) {
      if (kDebugMode) {
        print('FCMトークン取得エラー: $e');
      }
      return null;
    }
  }

  /// FCMトークンを削除
  Future<void> deleteToken(String userId) async {
    try {
      final token = await _messaging.getToken();
      if (token != null) {
        await _notificationService.deleteFCMToken(userId, token);
        await _messaging.deleteToken();

        if (kDebugMode) {
          print('🗑️ FCMトークン削除: $userId');
        }
      }
    } catch (e) {
      if (kDebugMode) {
        print('FCMトークン削除エラー: $e');
      }
    }
  }

  /// トピックから購読解除
  Future<void> unsubscribeFromTopic(String topic) async {
    try {
      await _messaging.unsubscribeFromTopic(topic);

      if (kDebugMode) {
        print('📢 トピック購読解除: $topic');
      }
    } catch (e) {
      if (kDebugMode) {
        print('トピック購読解除エラー: $e');
      }
    }
  }
}

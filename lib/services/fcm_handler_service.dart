import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../screens/other_user_profile_screen.dart';
import '../screens/post_detail_screen.dart';
import 'live_activity_service.dart';
import 'notification_service.dart';
import 'post_service.dart';
import 'auth_service.dart';

/// FCMハンドラーサービス
/// - FCMの初期化
/// - プッシュ通知の受信処理
/// - FCMトークンの管理
class FCMHandlerService {
  final FirebaseMessaging _messaging = FirebaseMessaging.instance;
  final NotificationService _notificationService = NotificationService();
  final PostService _postService = PostService();
  final AuthService _authService = AuthService();

  GlobalKey<NavigatorState>? _navigatorKey;

  // シングルトンパターン
  static final FCMHandlerService _instance = FCMHandlerService._internal();
  factory FCMHandlerService() => _instance;
  FCMHandlerService._internal();

  /// FCMを初期化
  Future<void> initialize(String userId, {GlobalKey<NavigatorState>? navigatorKey}) async {
    _navigatorKey = navigatorKey;

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

      // フォアグラウンドメッセージハンドラを設定
      FirebaseMessaging.onMessage.listen(_handleForegroundMessage);

      // 通知タップ時の処理（アプリがバックグラウンドから起動）
      FirebaseMessaging.onMessageOpenedApp.listen(_handleMessageOpenedApp);

      // アプリが終了状態から通知タップで起動した場合の処理
      final initialMessage = await _messaging.getInitialMessage();
      if (initialMessage != null) {
        // ウィジェットツリーが確定してから遷移する
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _handleMessageOpenedApp(initialMessage);
        });
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

  /// フォアグラウンド時のアプリ内通知バナーを表示
  void _handleForegroundMessage(RemoteMessage message) {
    if (kDebugMode) {
      print('🔔 フォアグラウンドメッセージ受信: ${message.messageId}');
      print('   タイトル: ${message.notification?.title}');
      print('   本文: ${message.notification?.body}');
    }

    // Music Memory の通知＝新しいサイクルの開始。ロック画面の Live Activity を
    // 張り直す（サーバの push-to-start が届かない端末のフォールバックにもなる）。
    if (message.data['notificationType'] == 'music_memory') {
      // ignore: discarded_futures
      LiveActivityService().refresh(force: true);
    }

    final title = message.notification?.title ?? '';
    final body = message.notification?.body ?? '';
    if (title.isEmpty && body.isEmpty) return;

    final overlay = _navigatorKey?.currentState?.overlay;
    if (overlay == null) return;

    late OverlayEntry entry;
    entry = OverlayEntry(
      builder: (context) => _InAppNotificationBanner(
        title: title,
        body: body,
        onTap: () {
          entry.remove();
          _handleMessageOpenedApp(message);
        },
        onDismiss: () => entry.remove(),
      ),
    );

    overlay.insert(entry);
    // 4秒後に自動消去
    Future.delayed(const Duration(seconds: 4), () {
      if (entry.mounted) entry.remove();
    });
  }

  /// 通知タップ時の画面遷移
  void _handleMessageOpenedApp(RemoteMessage message) {
    if (kDebugMode) {
      print('👆 通知タップ: ${message.messageId}');
      print('   データ: ${message.data}');
    }

    final notificationType = message.data['notificationType'] as String?
        ?? message.data['type'] as String?;
    final postId = message.data['postId'] as String?;
    final senderId = message.data['senderId'] as String?;
    final actionUrl = message.data['actionUrl'] as String?;

    final navigator = _navigatorKey?.currentState;
    if (navigator == null) return;

    if (notificationType == 'follow' && senderId != null && senderId.isNotEmpty) {
      navigator.push(MaterialPageRoute(
        builder: (_) => OtherUserProfileScreen(userId: senderId),
      ));
    } else if (postId != null && postId.isNotEmpty) {
      _navigateToPost(navigator, postId);
    } else if (actionUrl != null && actionUrl.isNotEmpty) {
      _launchUrl(actionUrl);
    } else if (notificationType == 'vibe' || notificationType == 'official') {
      // postId も actionUrl もない場合はホーム画面へ
      navigator.pushNamedAndRemoveUntil('/home', (route) => false);
    }
  }

  /// 投稿詳細画面へ遷移
  Future<void> _navigateToPost(NavigatorState navigator, String postId) async {
    try {
      final post = await _postService.getPost(postId);
      if (post != null) {
        final currentUserId = _authService.currentUser?.uid ?? '';
        navigator.push(MaterialPageRoute(
          builder: (_) => PostDetailScreen(
            post: post,
            currentUserId: currentUserId,
          ),
        ));
      }
    } catch (e) {
      if (kDebugMode) {
        print('❌ 投稿詳細への遷移エラー: $e');
      }
    }
  }

  /// URLを外部ブラウザで開く
  Future<void> _launchUrl(String url) async {
    try {
      final uri = Uri.parse(url);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
    } catch (e) {
      if (kDebugMode) {
        print('❌ URL起動エラー: $e');
      }
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

/// フォアグラウンド時のアプリ内通知バナーウィジェット
class _InAppNotificationBanner extends StatefulWidget {
  final String title;
  final String body;
  final VoidCallback onTap;
  final VoidCallback onDismiss;

  const _InAppNotificationBanner({
    required this.title,
    required this.body,
    required this.onTap,
    required this.onDismiss,
  });

  @override
  State<_InAppNotificationBanner> createState() =>
      _InAppNotificationBannerState();
}

class _InAppNotificationBannerState extends State<_InAppNotificationBanner>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<Offset> _slideAnimation;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, -1),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOut));
    _fadeAnimation = Tween<double>(begin: 0, end: 1).animate(_controller);
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final topPadding = MediaQuery.of(context).padding.top;

    return Positioned(
      top: topPadding + 8,
      left: 16,
      right: 16,
      child: SlideTransition(
        position: _slideAnimation,
        child: FadeTransition(
          opacity: _fadeAnimation,
          child: Material(
            color: Colors.transparent,
            child: GestureDetector(
              onTap: widget.onTap,
              child: Dismissible(
                key: const Key('notification_banner'),
                direction: DismissDirection.up,
                onDismissed: (_) => widget.onDismiss(),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFF2D2D2D),
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: const [
                      BoxShadow(
                        color: Colors.black38,
                        blurRadius: 12,
                        offset: Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(8),
                          gradient: const LinearGradient(
                            colors: [
                              Color(0xFFFF6B9D),
                              Color(0xFF8B5CF6),
                              Color(0xFF3B82F6),
                            ],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                        ),
                        child: const Icon(
                          Icons.notifications,
                          color: Colors.white,
                          size: 18,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (widget.title.isNotEmpty)
                              Text(
                                widget.title,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 13,
                                  fontWeight: FontWeight.bold,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            if (widget.body.isNotEmpty)
                              Text(
                                widget.body,
                                style: const TextStyle(
                                  color: Color(0xCCFFFFFF),
                                  fontSize: 13,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                          ],
                        ),
                      ),
                      GestureDetector(
                        onTap: widget.onDismiss,
                        child: const Padding(
                          padding: EdgeInsets.only(left: 8),
                          child: Icon(
                            Icons.close,
                            color: Color(0x80FFFFFF),
                            size: 16,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

import 'dart:async';
import 'dart:io';
import 'package:app_links/app_links.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../screens/post_detail_screen.dart';
import 'post_service.dart';

/// Instagram Stories などの外部リンクから起動されたディープリンクを処理する
///
/// fifteenapp://post/{postId} → PostDetailScreen を開いて音楽を自動再生
///
/// iOS の処理フロー:
///   コールドスタート : AppDelegate が _pendingDeepLinkPostId に保存
///                   → Flutter 初期化後に getInitialPostId で取得
///   バックグラウンド復帰: AppDelegate が onDeepLink を直接 invokeMethod
///                       → setMethodCallHandler で受け取る
class DeepLinkService {
  static final DeepLinkService _instance = DeepLinkService._internal();
  factory DeepLinkService() => _instance;
  DeepLinkService._internal();

  static const _nativeChannel = MethodChannel('com.fifteen.deeplink');

  final _postService = PostService();
  StreamSubscription<Uri>? _androidSub;
  GlobalKey<NavigatorState>? _navigatorKey;
  String? _lastHandledPostId; // 二重処理防止

  Future<void> initialize(GlobalKey<NavigatorState> navigatorKey) async {
    _navigatorKey = navigatorKey;

    if (Platform.isIOS) {
      // バックグラウンド復帰・フォアグラウンド時: AppDelegate からの直接通知
      _nativeChannel.setMethodCallHandler(_onNativeCall);

      // コールドスタート時: AppDelegate が保持していた postId を取得
      try {
        final postId = await _nativeChannel.invokeMethod<String>('getInitialPostId');
        if (postId != null && postId.isNotEmpty) {
          if (kDebugMode) print('DeepLinkService cold-start postId: $postId');
          WidgetsBinding.instance.addPostFrameCallback((_) => _openPost(postId));
        }
      } catch (e) {
        if (kDebugMode) print('DeepLinkService getInitialPostId error: $e');
      }
    } else {
      // Android: app_links でストリームを監視
      final appLinks = AppLinks();
      try {
        final initial = await appLinks.getInitialLink();
        if (initial != null) {
          if (kDebugMode) print('DeepLinkService Android initial: $initial');
          WidgetsBinding.instance.addPostFrameCallback((_) => _handleUri(initial));
        }
      } catch (e) {
        if (kDebugMode) print('DeepLinkService Android initial error: $e');
      }

      _androidSub = appLinks.uriLinkStream.listen(
        _handleUri,
        onError: (e) {
          if (kDebugMode) print('DeepLinkService Android stream error: $e');
        },
      );
    }
  }

  void dispose() {
    _androidSub?.cancel();
    _androidSub = null;
  }

  // iOS バックグラウンド復帰: AppDelegate から invokeMethod で直接届く
  Future<void> _onNativeCall(MethodCall call) async {
    if (call.method == 'onDeepLink') {
      final args = call.arguments as Map?;
      final postId = args?['postId'] as String?;
      if (postId != null && postId.isNotEmpty) {
        if (kDebugMode) print('DeepLinkService iOS onDeepLink: $postId');
        await _openPost(postId);
      }
    }
  }

  // Android: app_links から
  void _handleUri(Uri uri) {
    if (kDebugMode) print('DeepLinkService Android uri: $uri');
    if (uri.scheme == 'fifteenapp' &&
        uri.host == 'post' &&
        uri.pathSegments.isNotEmpty) {
      _openPost(uri.pathSegments.first);
    }
  }

  Future<void> _openPost(String postId) async {
    // 二重処理を防ぐ
    if (postId == _lastHandledPostId) return;
    _lastHandledPostId = postId;

    // Navigator が準備できるまで最大 2 秒待つ
    NavigatorState? navigator;
    for (var i = 0; i < 10; i++) {
      navigator = _navigatorKey?.currentState;
      if (navigator != null) break;
      await Future.delayed(const Duration(milliseconds: 200));
    }
    if (navigator == null) {
      if (kDebugMode) print('DeepLinkService: navigator not ready');
      _lastHandledPostId = null; // リセットして再試行を許容
      return;
    }

    try {
      final post = await _postService.getPost(postId);
      if (post == null) {
        if (kDebugMode) print('DeepLinkService: post not found: $postId');
        _lastHandledPostId = null;
        return;
      }
      final currentUserId = FirebaseAuth.instance.currentUser?.uid;
      navigator.push(MaterialPageRoute(
        builder: (_) => PostDetailScreen(
          post: post,
          currentUserId: currentUserId,
          alwaysShowBack: true,
        ),
      ));
    } catch (e) {
      if (kDebugMode) print('DeepLinkService _openPost error: $e');
      _lastHandledPostId = null;
    }
  }
}

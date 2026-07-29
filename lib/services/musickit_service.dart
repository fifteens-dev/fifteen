import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart';

/// MusicKit認証サービス（iOS/Android/Web対応）
class MusicKitService {
  static final MusicKitService _instance = MusicKitService._internal();
  factory MusicKitService() => _instance;
  MusicKitService._internal();

  static const MethodChannel _channel = MethodChannel('com.fifteen.musickit');

  /// プラットフォームがMusicKitをサポートしているかチェック
  bool get isSupported {
    if (kIsWeb) {
      // WebではMusicKit JSを使用（別途実装が必要）
      print('⚠️ MusicKit JS support is not yet implemented for Web');
      return false; // Web版は未実装のためfalseに変更
    }
    // iOSのみサポート（iOS 15+が必要）
    return Platform.isIOS;
  }

  /// MusicKit認証をリクエスト
  ///
  /// Returns:
  /// - "authorized": 認証成功
  /// - "denied": ユーザーが拒否またはサポートされていない
  /// - "notDetermined": まだ決定されていない
  /// - "restricted": 制限されている（ペアレンタルコントロールなど）
  Future<String> requestAuthorization() async {
    if (!isSupported) {
      if (kIsWeb) {
        print('⚠️ MusicKit is not supported on Web (MusicKit JS not implemented)');
      } else {
        print('⚠️ MusicKit is only supported on iOS');
      }
      return 'denied';
    }

    if (kIsWeb) {
      // Web用の認証（MusicKit JS）
      return await _requestAuthorizationWeb();
    }

    try {
      final String result = await _channel.invokeMethod('requestAuthorization');
      print('✅ MusicKit authorization result: $result');
      return result;
    } on PlatformException catch (e) {
      if (e.code == 'UNAVAILABLE') {
        print('❌ ${e.message ?? "MusicKit requires iOS 15.0 or later"}');
      } else {
        print('❌ MusicKit authorization error: ${e.message}');
      }
      return 'denied';
    } catch (e) {
      print('❌ Unexpected error during MusicKit authorization: $e');
      return 'denied';
    }
  }

  /// 現在の認証状態を取得
  Future<String> getAuthorizationStatus() async {
    if (!isSupported) {
      return 'denied';
    }

    if (kIsWeb) {
      return await _getAuthorizationStatusWeb();
    }

    try {
      final String status = await _channel.invokeMethod('getAuthorizationStatus');
      return status;
    } on PlatformException catch (e) {
      print('❌ Failed to get authorization status: ${e.message}');
      return 'denied';
    }
  }

  /// 認証済みかチェック
  Future<bool> isAuthorized() async {
    final status = await getAuthorizationStatus();
    return status == 'authorized';
  }

  /// User Tokenを取得（認証が必要）
  ///
  /// User TokenはApple Music APIで個人データにアクセスするために必要
  /// [developerToken] Developer Token（SKCloudServiceControllerで必要）
  Future<String?> getUserToken({String? developerToken}) async {
    if (!isSupported) {
      if (kIsWeb) {
        print('⚠️ MusicKit is not supported on Web (MusicKit JS not implemented)');
      } else {
        print('⚠️ MusicKit is only supported on iOS');
      }
      return null;
    }

    if (kIsWeb) {
      return await _getUserTokenWeb();
    }

    try {
      final String token = await _channel.invokeMethod('getUserToken', {
        'developerToken': developerToken,
      });
      print('✅ Got user token (length: ${token.length})');
      return token;
    } on PlatformException catch (e) {
      // ネイティブが分類したコード（NOT_AUTHORIZED / PRIVACY_ACK_REQUIRED /
      // NETWORK_ERROR / TOKEN_ERROR / UNAVAILABLE）をそのまま型付き例外で伝播する。
      // 旧実装は失敗を一律 NO_SUBSCRIPTION に丸めており、加入済みでも「サブスク必要」と
      // 誤表示していた。真のサブスク判定は API 側の 403 で行う。
      print('❌ getUserToken failed: ${e.code} ${e.message}');
      throw AppleMusicTokenException(
          e.code, e.message ?? 'Apple Music トークンの取得に失敗しました');
    } catch (e) {
      print('❌ Unexpected error getting user token: $e');
      throw AppleMusicTokenException('UNKNOWN', 'Apple Music トークンの取得に失敗しました');
    }
  }

  // Web用のメソッド（MusicKit JS）
  // TODO: 実装が必要
  Future<String> _requestAuthorizationWeb() async {
    print('⚠️ MusicKit JS authorization not implemented yet');
    return 'denied';
  }

  Future<String> _getAuthorizationStatusWeb() async {
    print('⚠️ MusicKit JS status check not implemented yet');
    return 'denied';
  }

  Future<String?> _getUserTokenWeb() async {
    print('⚠️ MusicKit JS getUserToken not implemented yet');
    return null;
  }
}

/// Apple Music サブスクリプション未加入を示す例外
class AppleMusicNoSubscriptionException implements Exception {
  final String message;
  const AppleMusicNoSubscriptionException(this.message);
  @override
  String toString() => message;
}

/// User Token 取得に失敗したことを、原因コード付きで示す例外。
/// code: NOT_AUTHORIZED / PRIVACY_ACK_REQUIRED / NETWORK_ERROR /
///       TOKEN_ERROR / UNAVAILABLE / UNKNOWN
/// ※「サブスク未加入」とは区別する（それは API 側 403 で判定）。
class AppleMusicTokenException implements Exception {
  final String code;
  final String message;
  const AppleMusicTokenException(this.code, this.message);
  @override
  String toString() => 'AppleMusicTokenException($code): $message';
}

import 'dart:convert';
import 'package:flutter/foundation.dart';
// import 'package:flutter_web_auth/flutter_web_auth.dart';  // 一時的に無効化
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_dotenv/flutter_dotenv.dart';

/// Spotify OAuth認証サービス
class SpotifyAuthService {
  static final SpotifyAuthService _instance = SpotifyAuthService._internal();
  factory SpotifyAuthService() => _instance;
  SpotifyAuthService._internal();

  final _storage = const FlutterSecureStorage();

  static const String _accessTokenKey = 'spotify_access_token';
  static const String _refreshTokenKey = 'spotify_refresh_token';
  static const String _tokenExpiryKey = 'spotify_token_expiry';

  String? _accessToken;
  String? _refreshToken;
  DateTime? _tokenExpiry;

  /// Client IDとRedirect URIを取得
  String get _clientId => dotenv.env['SPOTIFY_CLIENT_ID'] ?? '';
  String get _clientSecret => dotenv.env['SPOTIFY_CLIENT_SECRET'] ?? '';

  /// プラットフォーム別のリダイレクトURI
  /// Web版: テスト用にlocalhostとFirebase Hostingの両方をサポート
  /// モバイル版: カスタムURLスキーム（iOS/Android本番用）
  String get _redirectUri {
    if (kIsWeb) {
      // Web版はlocalhost（開発用）またはFirebase Hosting（テスト用）
      // Spotify Developer Dashboardには両方を登録する必要があります
      return 'http://localhost:8080/auth/callback';
    } else {
      // iOS/Android版はカスタムURLスキーム
      return 'fifteenapp://callback';
    }
  }

  String get _callbackUrlScheme {
    if (kIsWeb) {
      return 'http';
    } else {
      return 'fifteenapp';
    }
  }

  /// 認証状態を確認
  Future<bool> isAuthenticated() async {
    if (_accessToken != null && _tokenExpiry != null) {
      if (DateTime.now().isBefore(_tokenExpiry!)) {
        return true;
      }
    }

    // ストレージから読み込み
    await _loadTokensFromStorage();

    if (_accessToken != null && _tokenExpiry != null) {
      if (DateTime.now().isBefore(_tokenExpiry!)) {
        return true;
      } else if (_refreshToken != null) {
        // トークンを更新
        return await refreshAccessToken();
      }
    }

    return false;
  }

  /// ストレージからトークンを読み込み
  Future<void> _loadTokensFromStorage() async {
    _accessToken = await _storage.read(key: _accessTokenKey);
    _refreshToken = await _storage.read(key: _refreshTokenKey);

    final expiryString = await _storage.read(key: _tokenExpiryKey);
    if (expiryString != null) {
      _tokenExpiry = DateTime.parse(expiryString);
    }
  }

  /// トークンをストレージに保存
  Future<void> _saveTokensToStorage() async {
    if (_accessToken != null) {
      await _storage.write(key: _accessTokenKey, value: _accessToken);
    }
    if (_refreshToken != null) {
      await _storage.write(key: _refreshTokenKey, value: _refreshToken);
    }
    if (_tokenExpiry != null) {
      await _storage.write(key: _tokenExpiryKey, value: _tokenExpiry!.toIso8601String());
    }
  }

  /// Spotifyにログイン（Authorization Code Flow）
  Future<bool> login() async {
    try {
      // スコープの定義
      final scopes = [
        'user-read-private',
        'user-read-email',
        'playlist-read-private',
        'playlist-read-collaborative',
        'user-library-read',
      ].join(' ');

      // 認証URLを構築
      final authUrl = Uri.https('accounts.spotify.com', '/authorize', {
        'client_id': _clientId,
        'response_type': 'code',
        'redirect_uri': _redirectUri,
        'scope': scopes,
        'show_dialog': 'true',
      });

      // ブラウザで認証ページを開く
      // 一時的に無効化（写真表示テストのため）
      print('Spotify authentication temporarily disabled for testing');
      return false;

      // final result = await FlutterWebAuth.authenticate(
      //   url: authUrl.toString(),
      //   callbackUrlScheme: _callbackUrlScheme,
      // );
      //
      // // 認証コードを抽出
      // final code = Uri.parse(result).queryParameters['code'];
      // if (code == null) {
      //   print('認証コードが取得できませんでした');
      //   return false;
      // }
      //
      // // アクセストークンを取得
      // return await _getAccessTokenFromCode(code);
    } catch (e) {
      print('Spotify login error: $e');
      return false;
    }
  }

  /// 認証コードからアクセストークンを取得
  Future<bool> _getAccessTokenFromCode(String code) async {
    try {
      final credentials = base64.encode(utf8.encode('$_clientId:$_clientSecret'));

      final response = await http.post(
        Uri.parse('https://accounts.spotify.com/api/token'),
        headers: {
          'Authorization': 'Basic $credentials',
          'Content-Type': 'application/x-www-form-urlencoded',
        },
        body: {
          'grant_type': 'authorization_code',
          'code': code,
          'redirect_uri': _redirectUri,
        },
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        _accessToken = data['access_token'];
        _refreshToken = data['refresh_token'];

        final expiresIn = data['expires_in'] as int;
        _tokenExpiry = DateTime.now().add(Duration(seconds: expiresIn - 60));

        await _saveTokensToStorage();
        return true;
      } else {
        print('Token error: ${response.statusCode} ${response.body}');
        return false;
      }
    } catch (e) {
      print('Error getting access token: $e');
      return false;
    }
  }

  /// アクセストークンを更新
  Future<bool> refreshAccessToken() async {
    if (_refreshToken == null) return false;

    try {
      final credentials = base64.encode(utf8.encode('$_clientId:$_clientSecret'));

      final response = await http.post(
        Uri.parse('https://accounts.spotify.com/api/token'),
        headers: {
          'Authorization': 'Basic $credentials',
          'Content-Type': 'application/x-www-form-urlencoded',
        },
        body: {
          'grant_type': 'refresh_token',
          'refresh_token': _refreshToken,
        },
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        _accessToken = data['access_token'];

        // リフレッシュトークンが返される場合は更新
        if (data['refresh_token'] != null) {
          _refreshToken = data['refresh_token'];
        }

        final expiresIn = data['expires_in'] as int;
        _tokenExpiry = DateTime.now().add(Duration(seconds: expiresIn - 60));

        await _saveTokensToStorage();
        return true;
      } else {
        print('Refresh token error: ${response.statusCode} ${response.body}');
        return false;
      }
    } catch (e) {
      print('Error refreshing token: $e');
      return false;
    }
  }

  /// アクセストークンを取得（認証済みの場合）
  Future<String?> getAccessToken() async {
    if (!await isAuthenticated()) {
      return null;
    }
    return _accessToken;
  }

  /// ログアウト
  Future<void> logout() async {
    _accessToken = null;
    _refreshToken = null;
    _tokenExpiry = null;

    await _storage.delete(key: _accessTokenKey);
    await _storage.delete(key: _refreshTokenKey);
    await _storage.delete(key: _tokenExpiryKey);
  }
}

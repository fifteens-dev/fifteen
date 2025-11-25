import 'package:shared_preferences/shared_preferences.dart';

/// 設定サービス
/// SharedPreferencesを使用してアプリ設定を永続化します
class SettingsService {
  static const String _keyVibeNotification = 'vibe_notification';
  static const String _keyLikeCommentNotification = 'like_comment_notification';
  static const String _keyFollowNotification = 'follow_notification';
  static const String _keyOfficialNotification = 'official_notification';
  static const String _keySpotifyConnected = 'spotify_connected';
  static const String _keyAppleMusicConnected = 'apple_music_connected';

  // シングルトンパターン
  static final SettingsService _instance = SettingsService._internal();
  factory SettingsService() => _instance;
  SettingsService._internal();

  SharedPreferences? _prefs;

  /// 初期化
  Future<void> init() async {
    _prefs ??= await SharedPreferences.getInstance();
  }

  /// SharedPreferencesインスタンスを取得
  Future<SharedPreferences> _getPrefs() async {
    if (_prefs == null) {
      await init();
    }
    return _prefs!;
  }

  // ========== 通知設定 ==========

  /// Vibe通知設定を取得
  Future<bool> getVibeNotification() async {
    final prefs = await _getPrefs();
    return prefs.getBool(_keyVibeNotification) ?? true;
  }

  /// Vibe通知設定を保存
  Future<void> setVibeNotification(bool value) async {
    final prefs = await _getPrefs();
    await prefs.setBool(_keyVibeNotification, value);
  }

  /// いいね・コメント通知設定を取得
  Future<bool> getLikeCommentNotification() async {
    final prefs = await _getPrefs();
    return prefs.getBool(_keyLikeCommentNotification) ?? true;
  }

  /// いいね・コメント通知設定を保存
  Future<void> setLikeCommentNotification(bool value) async {
    final prefs = await _getPrefs();
    await prefs.setBool(_keyLikeCommentNotification, value);
  }

  /// フォロー通知設定を取得
  Future<bool> getFollowNotification() async {
    final prefs = await _getPrefs();
    return prefs.getBool(_keyFollowNotification) ?? true;
  }

  /// フォロー通知設定を保存
  Future<void> setFollowNotification(bool value) async {
    final prefs = await _getPrefs();
    await prefs.setBool(_keyFollowNotification, value);
  }

  /// 公式アカウント通知設定を取得
  Future<bool> getOfficialNotification() async {
    final prefs = await _getPrefs();
    return prefs.getBool(_keyOfficialNotification) ?? true;
  }

  /// 公式アカウント通知設定を保存
  Future<void> setOfficialNotification(bool value) async {
    final prefs = await _getPrefs();
    await prefs.setBool(_keyOfficialNotification, value);
  }

  /// 全ての通知設定を一括取得
  Future<Map<String, bool>> getAllNotificationSettings() async {
    return {
      'vibeNotification': await getVibeNotification(),
      'likeCommentNotification': await getLikeCommentNotification(),
      'followNotification': await getFollowNotification(),
      'officialNotification': await getOfficialNotification(),
    };
  }

  /// 全ての通知設定を一括保存
  Future<void> saveAllNotificationSettings({
    required bool vibeNotification,
    required bool likeCommentNotification,
    required bool followNotification,
    required bool officialNotification,
  }) async {
    await setVibeNotification(vibeNotification);
    await setLikeCommentNotification(likeCommentNotification);
    await setFollowNotification(followNotification);
    await setOfficialNotification(officialNotification);
  }

  // ========== 連携サービス設定 ==========

  /// Spotify連携状態を取得
  Future<bool> getSpotifyConnected() async {
    final prefs = await _getPrefs();
    return prefs.getBool(_keySpotifyConnected) ?? false;
  }

  /// Spotify連携状態を保存
  Future<void> setSpotifyConnected(bool value) async {
    final prefs = await _getPrefs();
    await prefs.setBool(_keySpotifyConnected, value);
  }

  /// Apple Music連携状態を取得
  Future<bool> getAppleMusicConnected() async {
    final prefs = await _getPrefs();
    return prefs.getBool(_keyAppleMusicConnected) ?? false;
  }

  /// Apple Music連携状態を保存
  Future<void> setAppleMusicConnected(bool value) async {
    final prefs = await _getPrefs();
    await prefs.setBool(_keyAppleMusicConnected, value);
  }

  /// 全ての連携サービス設定を一括取得
  Future<Map<String, bool>> getAllLinkedServicesSettings() async {
    return {
      'spotifyConnected': await getSpotifyConnected(),
      'appleMusicConnected': await getAppleMusicConnected(),
    };
  }

  /// 全ての連携サービス設定を一括保存
  Future<void> saveAllLinkedServicesSettings({
    required bool spotifyConnected,
    required bool appleMusicConnected,
  }) async {
    await setSpotifyConnected(spotifyConnected);
    await setAppleMusicConnected(appleMusicConnected);
  }
}

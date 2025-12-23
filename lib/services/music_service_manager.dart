import 'package:shared_preferences/shared_preferences.dart';
import '../models/track_model.dart';
import '../models/music_service_type.dart';
import 'spotify_service.dart';
import 'spotify_auth_service.dart';
import 'apple_music_service.dart';

/// 音楽サービスの統一管理クラス
class MusicServiceManager {
  static final MusicServiceManager _instance = MusicServiceManager._internal();
  factory MusicServiceManager() => _instance;
  MusicServiceManager._internal();

  final SpotifyService _spotifyService = SpotifyService();
  final SpotifyAuthService _spotifyAuthService = SpotifyAuthService();
  final AppleMusicService _appleMusicService = AppleMusicService();

  static const String _selectedServiceKey = 'selected_music_service';

  MusicServiceType? _selectedService;

  /// 選択されている音楽サービスを取得
  Future<MusicServiceType> getSelectedService() async {
    if (_selectedService != null) {
      return _selectedService!;
    }

    final prefs = await SharedPreferences.getInstance();
    final serviceString = prefs.getString(_selectedServiceKey);

    if (serviceString == null) {
      _selectedService = MusicServiceType.none;
    } else {
      _selectedService = MusicServiceType.values.firstWhere(
        (e) => e.toString() == serviceString,
        orElse: () => MusicServiceType.none,
      );
    }

    return _selectedService!;
  }

  /// 音楽サービスを選択
  Future<void> setSelectedService(MusicServiceType service) async {
    _selectedService = service;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_selectedServiceKey, service.toString());
  }

  /// 選択されているサービスでログイン
  Future<bool> login() async {
    final service = await getSelectedService();

    switch (service) {
      case MusicServiceType.spotify:
        return await _spotifyAuthService.login();
      case MusicServiceType.appleMusic:
        return await _appleMusicService.login();
      case MusicServiceType.none:
        return false;
    }
  }

  /// ログアウト
  Future<void> logout() async {
    final service = await getSelectedService();

    switch (service) {
      case MusicServiceType.spotify:
        await _spotifyAuthService.logout();
        break;
      case MusicServiceType.appleMusic:
        await _appleMusicService.logout();
        break;
      case MusicServiceType.none:
        break;
    }
  }

  /// 認証状態を確認
  Future<bool> isAuthenticated() async {
    final service = await getSelectedService();

    switch (service) {
      case MusicServiceType.spotify:
        return await _spotifyAuthService.isAuthenticated();
      case MusicServiceType.appleMusic:
        return await _appleMusicService.isAuthenticated();
      case MusicServiceType.none:
        return false;
    }
  }

  /// 楽曲を検索
  Future<List<TrackModel>> searchTracks(String query, {int limit = 20}) async {
    final service = await getSelectedService();

    switch (service) {
      case MusicServiceType.spotify:
        return await _spotifyService.searchTracks(query, limit: limit);
      case MusicServiceType.appleMusic:
        return await _appleMusicService.searchTracks(query, limit: limit);
      case MusicServiceType.none:
        // デフォルトでSpotifyを使用（非認証モード）
        return await _spotifyService.searchTracks(query, limit: limit);
    }
  }

  /// おすすめの楽曲を取得
  Future<List<TrackModel>> getRecommendedTracks({int limit = 50}) async {
    final service = await getSelectedService();

    switch (service) {
      case MusicServiceType.spotify:
        // OAuth認証済みならRecommendations APIを試す
        if (await _spotifyAuthService.isAuthenticated()) {
          final tracks = await _spotifyService.getRecommendations(
            seedGenres: 'j-pop',
            limit: limit,
          );
          if (tracks.isNotEmpty) return tracks;
        }
        // フォールバック: 検索
        return await _spotifyService.searchTracks('J-POP 2025 ヒット',
            limit: limit);

      case MusicServiceType.appleMusic:
        // Apple MusicのTop Chartsを取得
        final charts = await _appleMusicService.getTopCharts(limit: limit);
        if (charts.isNotEmpty) return charts;
        // フォールバック: 検索
        return await _appleMusicService.searchTracks('J-POP', limit: limit);

      case MusicServiceType.none:
        // デフォルトでSpotify検索
        return await _spotifyService.searchTracks('J-POP 2025 ヒット',
            limit: limit);
    }
  }

  /// プレイリストから楽曲を取得
  Future<List<TrackModel>> getPlaylistTracks(String playlistId,
      {int limit = 50}) async {
    final service = await getSelectedService();

    switch (service) {
      case MusicServiceType.spotify:
        return await _spotifyService.getPlaylistTracks(playlistId,
            limit: limit);
      case MusicServiceType.appleMusic:
        return await _appleMusicService.getPlaylistTracks(playlistId,
            limit: limit);
      case MusicServiceType.none:
        return [];
    }
  }
}

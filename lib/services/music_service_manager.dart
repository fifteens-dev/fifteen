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
    print('🎵 MusicServiceManager.searchTracks: service=$service, query="$query"');

    switch (service) {
      case MusicServiceType.spotify:
        try {
          return await _spotifyService.searchTracks(query, limit: limit);
        } catch (e) {
          print('⚠️ Spotify検索失敗: $e');
          return [];
        }
      case MusicServiceType.appleMusic:
        final results = await _appleMusicService.searchTracks(query, limit: limit);
        if (results.isNotEmpty) return results;
        // Apple Musicで結果が空の場合、Spotifyにフォールバック
        print('⚠️ Apple Music検索失敗 - Spotifyにフォールバック');
        try {
          return await _spotifyService.searchTracks(query, limit: limit);
        } catch (e) {
          print('⚠️ Spotifyフォールバックも失敗: $e');
          return [];
        }
      case MusicServiceType.none:
        try {
          return await _spotifyService.searchTracks(query, limit: limit);
        } catch (e) {
          print('⚠️ Spotify検索失敗: $e');
          return [];
        }
    }
  }

  /// おすすめの楽曲を取得
  /// 全サービス共通で Apple Music Charts API（日本トップチャート）を使用
  Future<List<TrackModel>> getRecommendedTracks({int limit = 50}) async {
    final service = await getSelectedService();
    print('🎵 MusicServiceManager.getRecommendedTracks: service=$service');

    // Apple Music日本トップチャートを取得（Developer Tokenのみで動作）
    try {
      final charts = await _appleMusicService.getTopCharts(limit: limit);
      if (charts.isNotEmpty) {
        print('📊 Apple Music日本トップチャートから${charts.length}曲取得');
        return charts;
      }
    } catch (e) {
      print('⚠️ Apple Musicトップチャート取得失敗: $e');
    }

    // フォールバック: サービスに応じた検索
    try {
      if (service == MusicServiceType.appleMusic) {
        final amTracks = await _appleMusicService.searchTracks('J-POP', limit: limit);
        if (amTracks.isNotEmpty) return amTracks;
      }
      return await _spotifyService.searchTracks('J-POP 人気', limit: limit);
    } catch (e) {
      print('⚠️ 検索フォールバックも失敗: $e');
      return [];
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

  /// プレイリスト名で検索してトラックを取得
  Future<List<TrackModel>> searchPlaylistTracks(String playlistName,
      {int limit = 20}) async {
    final service = await getSelectedService();

    switch (service) {
      case MusicServiceType.spotify:
        return await _spotifyService.searchPlaylistTracks(playlistName,
            limit: limit);
      case MusicServiceType.appleMusic:
        return await _appleMusicService.searchPlaylistTracks(playlistName,
            limit: limit);
      case MusicServiceType.none:
        return [];
    }
  }

  /// ユーザーの最近再生した楽曲を取得
  Future<List<TrackModel>> getRecentlyPlayedTracks({int limit = 30}) async {
    final service = await getSelectedService();

    switch (service) {
      case MusicServiceType.spotify:
        if (await _spotifyAuthService.isAuthenticated()) {
          try {
            return await _spotifyService.getRecentlyPlayedTracks(limit: limit);
          } catch (e) {
            print('⚠️ Spotify最近再生した曲の取得失敗: $e');
            return [];
          }
        }
        return [];
      case MusicServiceType.appleMusic:
        try {
          return await _appleMusicService.getRecentlyPlayedTracks(limit: limit);
        } catch (e) {
          print('⚠️ Apple Music最近再生した曲の取得失敗: $e');
          return [];
        }
      case MusicServiceType.none:
        return [];
    }
  }

  /// ユーザーのお気に入り楽曲を取得
  Future<List<TrackModel>> getSavedTracks({int limit = 50}) async {
    final service = await getSelectedService();

    switch (service) {
      case MusicServiceType.spotify:
        // OAuth認証済みの場合のみお気に入り楽曲を取得（フォールバックなし）
        if (await _spotifyAuthService.isAuthenticated()) {
          try {
            return await _spotifyService.getSavedTracks(limit: limit);
          } catch (e) {
            print('⚠️ Spotifyライブラリ取得失敗: $e');
            return [];
          }
        }
        return [];
      case MusicServiceType.appleMusic:
        // ユーザーのライブラリから取得のみ（フォールバックなし）
        try {
          return await _appleMusicService.getSavedTracks(limit: limit);
        } catch (e) {
          print('⚠️ Apple Musicライブラリ取得失敗: $e');
          return [];
        }
      case MusicServiceType.none:
        return [];
    }
  }

  /// 楽曲の歌詞を取得
  /// trackId: トラックID（サービスによって形式が異なる）
  Future<String?> getLyrics(String trackId) async {
    final service = await getSelectedService();

    switch (service) {
      case MusicServiceType.spotify:
        // Spotify APIは公式に歌詞APIを提供していない
        // サードパーティAPIやスクレイピングが必要
        print('Spotify歌詞取得は未実装です');
        return null;
      case MusicServiceType.appleMusic:
        return await _appleMusicService.getLyrics(trackId);
      case MusicServiceType.none:
        // デフォルトでApple Musicを試す
        return await _appleMusicService.getLyrics(trackId);
    }
  }
}

import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../models/track_model.dart';

/// Apple Music API サービス
class AppleMusicService {
  static final AppleMusicService _instance = AppleMusicService._internal();
  factory AppleMusicService() => _instance;
  AppleMusicService._internal();

  final _storage = const FlutterSecureStorage();

  static const String _developerTokenKey = 'apple_music_developer_token';
  static const String _userTokenKey = 'apple_music_user_token';

  String? _developerToken;
  String? _userToken;

  /// Developer Tokenを取得（.envまたはバックエンドから）
  String get _envDeveloperToken => dotenv.env['APPLE_MUSIC_DEVELOPER_TOKEN'] ?? '';

  /// 認証状態を確認
  Future<bool> isAuthenticated() async {
    // Developer Tokenがあれば基本的な検索は可能
    if (_developerToken != null) {
      return true;
    }

    // .envから読み込み
    if (_envDeveloperToken.isNotEmpty) {
      _developerToken = _envDeveloperToken;
      return true;
    }

    // ストレージから読み込み
    _developerToken = await _storage.read(key: _developerTokenKey);
    return _developerToken != null;
  }

  /// User Token認証（将来の実装用）
  Future<bool> login() async {
    // MusicKitを使用したUser Token認証
    // TODO: Platform Channelを使用してiOS/AndroidのMusicKitと統合
    print('Apple Music User Token認証は未実装です');
    return false;
  }

  /// ログアウト
  Future<void> logout() async {
    _userToken = null;
    await _storage.delete(key: _userTokenKey);
  }

  /// 楽曲を検索
  Future<List<TrackModel>> searchTracks(String query, {int limit = 20}) async {
    if (query.isEmpty) return [];

    if (!await isAuthenticated()) {
      print('Apple Music Developer Tokenが設定されていません');
      return [];
    }

    try {
      final encodedQuery = Uri.encodeComponent(query);
      final response = await http.get(
        Uri.parse(
            'https://api.music.apple.com/v1/catalog/jp/search?term=$encodedQuery&types=songs&limit=$limit'),
        headers: {
          'Authorization': 'Bearer $_developerToken',
        },
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final results = data['results'];

        if (results == null || results['songs'] == null) {
          return [];
        }

        final songs = results['songs']['data'] as List;

        return songs.map((songData) {
          final attributes = songData['attributes'];

          // アルバムアートワークURL
          String albumImageUrl = '';
          if (attributes['artwork'] != null) {
            final artworkUrl = attributes['artwork']['url'] as String;
            // {w}x{h}を実際のサイズに置き換え
            albumImageUrl =
                artworkUrl.replaceAll('{w}', '640').replaceAll('{h}', '640');
          }

          // プレビューURL
          String previewUrl = '';
          if (attributes['previews'] != null &&
              attributes['previews'].isNotEmpty) {
            previewUrl = attributes['previews'][0]['url'] ?? '';
          }

          return TrackModel(
            trackId: songData['id'],
            trackName: attributes['name'],
            artistName: attributes['artistName'],
            albumImageUrl: albumImageUrl,
            previewUrl: previewUrl,
          );
        }).toList();
      } else {
        print('Apple Music search error: ${response.statusCode} ${response.body}');
        return [];
      }
    } catch (e) {
      print('Error searching Apple Music tracks: $e');
      return [];
    }
  }

  /// キュレーションプレイリストから楽曲を取得
  Future<List<TrackModel>> getPlaylistTracks(String playlistId,
      {int limit = 50}) async {
    if (!await isAuthenticated()) {
      print('Apple Music Developer Tokenが設定されていません');
      return [];
    }

    try {
      final response = await http.get(
        Uri.parse(
            'https://api.music.apple.com/v1/catalog/jp/playlists/$playlistId'),
        headers: {
          'Authorization': 'Bearer $_developerToken',
        },
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final playlistData = data['data'][0];
        final relationships = playlistData['relationships'];

        if (relationships == null || relationships['tracks'] == null) {
          return [];
        }

        final tracks = relationships['tracks']['data'] as List;

        return tracks.take(limit).map((trackData) {
          final attributes = trackData['attributes'];

          String albumImageUrl = '';
          if (attributes['artwork'] != null) {
            final artworkUrl = attributes['artwork']['url'] as String;
            albumImageUrl =
                artworkUrl.replaceAll('{w}', '640').replaceAll('{h}', '640');
          }

          String previewUrl = '';
          if (attributes['previews'] != null &&
              attributes['previews'].isNotEmpty) {
            previewUrl = attributes['previews'][0]['url'] ?? '';
          }

          return TrackModel(
            trackId: trackData['id'],
            trackName: attributes['name'],
            artistName: attributes['artistName'],
            albumImageUrl: albumImageUrl,
            previewUrl: previewUrl,
          );
        }).toList();
      } else {
        print('Apple Music playlist error: ${response.statusCode} ${response.body}');
        return [];
      }
    } catch (e) {
      print('Error getting Apple Music playlist: $e');
      return [];
    }
  }

  /// 日本のトップチャートを取得
  Future<List<TrackModel>> getTopCharts({int limit = 50}) async {
    if (!await isAuthenticated()) {
      print('Apple Music Developer Tokenが設定されていません');
      return [];
    }

    try {
      final response = await http.get(
        Uri.parse(
            'https://api.music.apple.com/v1/catalog/jp/charts?types=songs&limit=$limit'),
        headers: {
          'Authorization': 'Bearer $_developerToken',
        },
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final results = data['results'];

        if (results == null || results['songs'] == null) {
          return [];
        }

        final charts = results['songs'][0]['data'] as List;

        return charts.map((chartData) {
          final attributes = chartData['attributes'];

          String albumImageUrl = '';
          if (attributes['artwork'] != null) {
            final artworkUrl = attributes['artwork']['url'] as String;
            albumImageUrl =
                artworkUrl.replaceAll('{w}', '640').replaceAll('{h}', '640');
          }

          String previewUrl = '';
          if (attributes['previews'] != null &&
              attributes['previews'].isNotEmpty) {
            previewUrl = attributes['previews'][0]['url'] ?? '';
          }

          return TrackModel(
            trackId: chartData['id'],
            trackName: attributes['name'],
            artistName: attributes['artistName'],
            albumImageUrl: albumImageUrl,
            previewUrl: previewUrl,
          );
        }).toList();
      } else {
        print('Apple Music charts error: ${response.statusCode} ${response.body}');
        return [];
      }
    } catch (e) {
      print('Error getting Apple Music charts: $e');
      return [];
    }
  }
}

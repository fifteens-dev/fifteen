import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter_dotenv/flutter_dotenv.dart';
import '../models/track_model.dart';
import 'itunes_search_service.dart';

/// Spotify Web API サービス
class SpotifyService {
  static final SpotifyService _instance = SpotifyService._internal();
  factory SpotifyService() => _instance;
  SpotifyService._internal();

  String? _accessToken;
  DateTime? _tokenExpiry;

  // iTunes Search APIのフォールバック
  final ITunesSearchService _itunesService = ITunesSearchService();

  /// Client IDとClient Secretを取得
  String get _clientId => dotenv.env['SPOTIFY_CLIENT_ID'] ?? '';
  String get _clientSecret => dotenv.env['SPOTIFY_CLIENT_SECRET'] ?? '';

  /// アクセストークンを取得（Client Credentials Flow）
  Future<String?> _getAccessToken() async {
    // トークンがまだ有効な場合は再利用
    if (_accessToken != null &&
        _tokenExpiry != null &&
        DateTime.now().isBefore(_tokenExpiry!)) {
      return _accessToken;
    }

    try {
      final credentials = base64.encode(utf8.encode('$_clientId:$_clientSecret'));

      final response = await http.post(
        Uri.parse('https://accounts.spotify.com/api/token'),
        headers: {
          'Authorization': 'Basic $credentials',
          'Content-Type': 'application/x-www-form-urlencoded',
        },
        body: {
          'grant_type': 'client_credentials',
        },
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        _accessToken = data['access_token'];
        // トークンは通常3600秒（1時間）有効
        final expiresIn = data['expires_in'] as int;
        _tokenExpiry = DateTime.now().add(Duration(seconds: expiresIn - 60));
        return _accessToken;
      } else {
        print('Spotify token error: ${response.statusCode} ${response.body}');
        return null;
      }
    } catch (e) {
      print('Error getting Spotify access token: $e');
      return null;
    }
  }

  /// 楽曲を検索（アルバムアートはSpotify、プレビューURLはiTunes）
  Future<List<TrackModel>> searchTracks(String query, {int limit = 20}) async {
    if (query.isEmpty) return [];

    final token = await _getAccessToken();
    if (token == null) {
      // トークン取得失敗時はiTunesにフォールバック
      return await _itunesService.searchTracks(query, limit: limit);
    }

    try {
      final encodedQuery = Uri.encodeComponent(query);
      final response = await http.get(
        Uri.parse('https://api.spotify.com/v1/search?q=$encodedQuery&type=track&limit=$limit'),
        headers: {
          'Authorization': 'Bearer $token',
        },
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final tracks = data['tracks']['items'] as List;

        return tracks.map((trackData) {
          // アルバムアートワークを取得
          final images = trackData['album']['images'] as List;
          String albumImageUrl = '';
          if (images.isNotEmpty) {
            albumImageUrl = images[0]['url'];
          }

          // アーティスト名を取得
          final artists = trackData['artists'] as List;
          String artistName = '';
          if (artists.isNotEmpty) {
            artistName = artists.map((a) => a['name']).join(', ');
          }

          return TrackModel(
            trackId: trackData['id'],
            trackName: trackData['name'],
            artistName: artistName,
            albumImageUrl: albumImageUrl,
            previewUrl: '', // previewUrlは空にして、カード裏返し時にiTunesから取得
          );
        }).toList();
      } else {
        print('Spotify search error: ${response.statusCode} ${response.body}');
        // エラー時はiTunesにフォールバック
        return await _itunesService.searchTracks(query, limit: limit);
      }
    } catch (e) {
      print('Error searching tracks: $e');
      // エラー時はiTunesにフォールバック
      return await _itunesService.searchTracks(query, limit: limit);
    }
  }

  /// トラックIDから楽曲情報を取得
  Future<TrackModel?> getTrack(String trackId) async {
    final token = await _getAccessToken();
    if (token == null) return null;

    try {
      final response = await http.get(
        Uri.parse('https://api.spotify.com/v1/tracks/$trackId'),
        headers: {
          'Authorization': 'Bearer $token',
        },
      );

      if (response.statusCode == 200) {
        final trackData = json.decode(response.body);

        // アルバムアートワークを取得
        final images = trackData['album']['images'] as List;
        String albumImageUrl = '';
        if (images.isNotEmpty) {
          albumImageUrl = images[0]['url'];
        }

        // アーティスト名を取得
        final artists = trackData['artists'] as List;
        String artistName = '';
        if (artists.isNotEmpty) {
          artistName = artists.map((a) => a['name']).join(', ');
        }

        return TrackModel(
          trackId: trackData['id'],
          trackName: trackData['name'],
          artistName: artistName,
          albumImageUrl: albumImageUrl,
          previewUrl: trackData['preview_url'],
        );
      } else {
        print('Spotify get track error: ${response.statusCode} ${response.body}');
        return null;
      }
    } catch (e) {
      print('Error getting track: $e');
      return null;
    }
  }

  /// おすすめの楽曲を取得（カテゴリ別）
  Future<List<TrackModel>> getRecommendations({
    String? seedGenres,
    String? seedArtists,
    String? seedTracks,
    int limit = 20,
  }) async {
    final token = await _getAccessToken();
    if (token == null) return [];

    try {
      String url = 'https://api.spotify.com/v1/recommendations?limit=$limit';

      if (seedGenres != null) url += '&seed_genres=$seedGenres';
      if (seedArtists != null) url += '&seed_artists=$seedArtists';
      if (seedTracks != null) url += '&seed_tracks=$seedTracks';

      final response = await http.get(
        Uri.parse(url),
        headers: {
          'Authorization': 'Bearer $token',
        },
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final tracks = data['tracks'] as List;

        return tracks.map((trackData) {
          final images = trackData['album']['images'] as List;
          String albumImageUrl = '';
          if (images.isNotEmpty) {
            albumImageUrl = images[0]['url'];
          }

          final artists = trackData['artists'] as List;
          String artistName = '';
          if (artists.isNotEmpty) {
            artistName = artists.map((a) => a['name']).join(', ');
          }

          return TrackModel(
            trackId: trackData['id'],
            trackName: trackData['name'],
            artistName: artistName,
            albumImageUrl: albumImageUrl,
            previewUrl: trackData['preview_url'],
          );
        }).toList();
      } else {
        print('Spotify recommendations error: ${response.statusCode} ${response.body}');
        return [];
      }
    } catch (e) {
      print('Error getting recommendations: $e');
      return [];
    }
  }
}

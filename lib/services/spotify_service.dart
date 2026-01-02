import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter_dotenv/flutter_dotenv.dart';
import '../models/track_model.dart';
import 'itunes_search_service.dart';
import 'spotify_auth_service.dart';

/// Spotify Web API サービス
class SpotifyService {
  static final SpotifyService _instance = SpotifyService._internal();
  factory SpotifyService() => _instance;
  SpotifyService._internal();

  String? _clientCredentialsToken;
  DateTime? _tokenExpiry;

  // iTunes Search APIのフォールバック
  final ITunesSearchService _itunesService = ITunesSearchService();

  // OAuth認証サービス
  final SpotifyAuthService _authService = SpotifyAuthService();

  /// Client IDとClient Secretを取得
  String get _clientId => dotenv.env['SPOTIFY_CLIENT_ID'] ?? '';
  String get _clientSecret => dotenv.env['SPOTIFY_CLIENT_SECRET'] ?? '';

  /// アクセストークンを取得（OAuth優先、フォールバックでClient Credentials）
  Future<String?> _getAccessToken() async {
    // OAuth認証トークンがあればそれを使用（Recommendations APIやプレイリストにアクセス可能）
    if (await _authService.isAuthenticated()) {
      final oauthToken = await _authService.getAccessToken();
      if (oauthToken != null) {
        return oauthToken;
      }
    }

    // OAuth認証がない場合は、Client Credentials Flowにフォールバック
    // トークンがまだ有効な場合は再利用
    if (_clientCredentialsToken != null &&
        _tokenExpiry != null &&
        DateTime.now().isBefore(_tokenExpiry!)) {
      return _clientCredentialsToken;
    }

    try {
      final credentials =
          base64.encode(utf8.encode('$_clientId:$_clientSecret'));

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
        _clientCredentialsToken = data['access_token'];
        // トークンは通常3600秒（1時間）有効
        final expiresIn = data['expires_in'] as int;
        _tokenExpiry = DateTime.now().add(Duration(seconds: expiresIn - 60));
        return _clientCredentialsToken;
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
      // より多くの結果を取得してフィルタリング（Spotify APIの最大値は50）
      final searchLimit = (limit * 3).clamp(1, 50);
      final response = await http.get(
        Uri.parse(
            'https://api.spotify.com/v1/search?q=$encodedQuery&type=track&limit=$searchLimit'),
        headers: {
          'Authorization': 'Bearer $token',
        },
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final tracks = data['tracks']['items'] as List;

        if (tracks.isEmpty) {
          print('🎵 Spotify: No results found for "$query"');
          return [];
        }

        print('🎵 Spotify: Found ${tracks.length} results, filtering for original versions...');

        // スコアリングしてオリジナル版を優先
        final scoredTracks = _scoreAndFilterTracks(tracks, query);

        // 上位limit件を返す
        final results = scoredTracks.take(limit).map((scoredTrack) {
          final trackData = scoredTrack['track'];

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

        print('✅ Spotify: Returning ${results.length} filtered tracks');
        return results;
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

  /// 楽曲名を正規化（括弧や特別版の情報を除去）
  String _normalizeTrackName(String trackName) {
    String normalized = trackName.toLowerCase();

    // 括弧内の情報を除去
    normalized = normalized.replaceAll(RegExp(r'\[.*?\]'), '');
    normalized = normalized.replaceAll(RegExp(r'\(.*?\)'), '');
    normalized = normalized.replaceAll(RegExp(r'【.*?】'), '');
    normalized = normalized.replaceAll(RegExp(r'（.*?）'), '');

    // ハイフン以降を除去（"Song - Remix" → "Song"）
    normalized = normalized.split('-').first;

    // 余分な空白を除去
    normalized = normalized.trim().replaceAll(RegExp(r'\s+'), ' ');

    return normalized;
  }

  /// 検索結果をスコアリングしてオリジナル版を優先
  List<Map<String, dynamic>> _scoreAndFilterTracks(List<dynamic> tracks, String query) {
    // 除外するキーワード（カバー版や特別版）
    final excludeKeywords = [
      'cover',
      'remix',
      'acoustic',
      'live',
      'instrumental',
      'karaoke',
      'tribute',
      'remaster',
      'demo',
      'session',
      'edit',
      'mix',
      'deluxe',
      'special',
      'limited',
      'bonus',
      '8bit',
      '16bit',
      'カバー',
      '限定',
      'ライブ',
      'リミックス',
      'アコースティック',
      '原曲',
      'より',
      'メドレー',  // メドレーを除外
      '詰め合わせ',
      '～',  // メドレーでよく使われる記号
    ];

    // 1. 各トラックをスコアリング
    final scoredTracks = tracks.map((trackData) {
      final trackName = (trackData['name'] ?? '').toString();
      final trackNameLower = trackName.toLowerCase();
      final albumName = (trackData['album']['name'] ?? '').toString().toLowerCase();
      final artists = trackData['artists'] as List;
      final artistName = artists.isNotEmpty
          ? artists.map((a) => a['name']).join(', ')
          : '';

      int score = 100; // 基本スコア

      // 除外キーワードが含まれている場合は大幅減点
      for (final keyword in excludeKeywords) {
        if (trackNameLower.contains(keyword) || albumName.contains(keyword)) {
          score -= 50;
        }
      }

      // 括弧が含まれている場合は減点（特別版の可能性）
      if (trackNameLower.contains('(') || trackNameLower.contains('[') ||
          trackNameLower.contains('（') || trackNameLower.contains('【')) {
        score -= 20;
      }

      // トラック名が短いほうが良い（余計な情報が少ない）
      if (trackName.length > 50) {
        score -= 10;
      }

      // トラック名の長さに応じたペナルティ（検索クエリより大幅に長い場合）
      final queryLength = query.length;
      final trackNameLength = trackName.length;
      if (trackNameLength > queryLength * 2) {
        // 検索クエリの2倍以上の長さの場合、大幅減点
        score -= 30;
      } else if (trackNameLength > queryLength * 1.5) {
        // 1.5倍以上の場合、中程度の減点
        score -= 15;
      }

      // 人気度（popularity）が高いものを優先
      final popularity = (trackData['popularity'] ?? 0) as int;
      score += (popularity / 10).round().toInt(); // 0-10点の範囲で加点

      // 検索クエリとの関連性スコア（重要！）
      final queryLower = query.toLowerCase();
      final queryWords = queryLower.split(' ');

      // 楽曲名が検索クエリの単語を含んでいるか
      int relevanceScore = 0;
      for (final word in queryWords) {
        if (word.length > 2) { // 短すぎる単語は無視
          if (trackNameLower.contains(word)) {
            relevanceScore += 30; // 楽曲名に含まれる場合は大幅加点
          }
          if (artistName.toLowerCase().contains(word)) {
            relevanceScore += 20; // アーティスト名に含まれる場合も加点
          }
        }
      }

      score += relevanceScore;

      // 正規化された楽曲名
      final normalizedName = _normalizeTrackName(trackName);

      return {
        'track': trackData,
        'score': score,
        'normalizedName': normalizedName,
        'trackName': trackName,
        'artistName': artistName,
        'popularity': popularity,
        'relevanceScore': relevanceScore,
      };
    }).toList();

    // 2. 正規化された楽曲名でグループ化
    final Map<String, List<Map<String, dynamic>>> groupedTracks = {};
    for (final scoredTrack in scoredTracks) {
      final normalizedName = scoredTrack['normalizedName'] as String;
      groupedTracks.putIfAbsent(normalizedName, () => []);
      groupedTracks[normalizedName]!.add(scoredTrack);
    }

    // 3. 各グループから最高スコアの版を選択
    final bestVersions = <Map<String, dynamic>>[];
    for (final entry in groupedTracks.entries) {
      final groupName = entry.key;
      final versions = entry.value;

      // グループ内でスコアでソート
      versions.sort((a, b) => (b['score'] as int).compareTo(a['score'] as int));

      final bestVersion = versions.first;

      print('📊 Group "$groupName" has ${versions.length} version(s):');
      for (int i = 0; i < versions.length && i < 3; i++) {
        final v = versions[i];
        final marker = i == 0 ? '✅' : '  ';
        print('   $marker "${v['trackName']}" by ${v['artistName']} - Score: ${v['score']} (Pop: ${v['popularity']}, Rel: ${v['relevanceScore']})');
      }

      bestVersions.add(bestVersion);
    }

    // 4. 各グループの代表をスコアでソート
    bestVersions.sort((a, b) => (b['score'] as int).compareTo(a['score'] as int));

    // スコアが0以上のものだけ返す
    return bestVersions.where((item) => (item['score'] as int) > 0).toList();
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
        print(
            'Spotify get track error: ${response.statusCode} ${response.body}');
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
        print(
            'Spotify recommendations error: ${response.statusCode} ${response.body}');
        return [];
      }
    } catch (e) {
      print('Error getting recommendations: $e');
      return [];
    }
  }

  /// プレイリストから楽曲を取得
  Future<List<TrackModel>> getPlaylistTracks(String playlistId,
      {int limit = 50}) async {
    final token = await _getAccessToken();
    if (token == null) {
      print('Failed to get access token for playlist');
      return [];
    }

    try {
      final response = await http.get(
        Uri.parse(
            'https://api.spotify.com/v1/playlists/$playlistId/tracks?limit=$limit'),
        headers: {
          'Authorization': 'Bearer $token',
        },
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final items = data['items'] as List;

        return items.where((item) => item['track'] != null).map((item) {
          final trackData = item['track'];

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
            previewUrl: '', // プレビューURLは後でiTunesから取得
          );
        }).toList();
      } else {
        print(
            'Spotify playlist error: ${response.statusCode} ${response.body}');
        return [];
      }
    } catch (e) {
      print('Error getting playlist tracks: $e');
      return [];
    }
  }

  /// ユーザーのお気に入り楽曲（Saved Tracks）を取得
  /// OAuth認証が必要（user-library-readスコープ）
  Future<List<TrackModel>> getSavedTracks({int limit = 50}) async {
    final token = await _getAccessToken();
    if (token == null) {
      print('Failed to get access token for saved tracks');
      return [];
    }

    // OAuth認証トークンが必要（Client Credentialsでは不可）
    if (!await _authService.isAuthenticated()) {
      print('OAuth authentication required for saved tracks');
      return [];
    }

    try {
      final response = await http.get(
        Uri.parse('https://api.spotify.com/v1/me/tracks?limit=$limit'),
        headers: {
          'Authorization': 'Bearer $token',
        },
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final items = data['items'] as List;

        return items.where((item) => item['track'] != null).map((item) {
          final trackData = item['track'];

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
            previewUrl: '', // プレビューURLは後でiTunesから取得
          );
        }).toList();
      } else {
        print(
            'Spotify saved tracks error: ${response.statusCode} ${response.body}');
        return [];
      }
    } catch (e) {
      print('Error getting saved tracks: $e');
      return [];
    }
  }
}

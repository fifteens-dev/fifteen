import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter_dotenv/flutter_dotenv.dart';
import '../models/track_model.dart';
import 'spotify_auth_service.dart';

/// Spotify Web API サービス
class SpotifyService {
  static final SpotifyService _instance = SpotifyService._internal();
  factory SpotifyService() => _instance;
  SpotifyService._internal();

  String? _clientCredentialsToken;
  DateTime? _tokenExpiry;
  final Map<String, String?> _artistImageCache = {};
  // artistId → (imageUrl, followerCount) のキャッシュ
  final Map<String, ({String? imageUrl, int followerCount})> _artistByIdCache = {};

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
        print('✅ Spotify OAuth トークンを使用');
        return oauthToken;
      }
    }

    // OAuthがない場合はClient Credentialsにフォールバック
    return await _getClientCredentialsToken();
  }

  /// Client Credentialsトークンを取得（ユーザー認証不要）
  Future<String?> _getClientCredentialsToken() async {
    // キャッシュが有効ならそれを使用
    if (_clientCredentialsToken != null &&
        _tokenExpiry != null &&
        DateTime.now().isBefore(_tokenExpiry!)) {
      print('✅ Spotify キャッシュされたClient Credentialsトークンを使用');
      return _clientCredentialsToken;
    }

    print('🔑 Spotify Client Credentials トークンを取得中...');
    try {
      if (_clientId.isEmpty || _clientSecret.isEmpty) {
        print('❌ Spotify認証情報が.envファイルに設定されていません');
        return null;
      }

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
        final expiresIn = data['expires_in'] as int;
        _tokenExpiry = DateTime.now().add(Duration(seconds: expiresIn - 60));
        print('✅ Spotify Client Credentials トークン取得成功');
        return _clientCredentialsToken;
      } else {
        print('❌ Spotify token error: ${response.statusCode} ${response.body}');
        return null;
      }
    } catch (e) {
      print('❌ Error getting Spotify access token: $e');
      return null;
    }
  }

  /// Spotify APIで検索を実行（内部用）
  Future<http.Response> _executeSearch(String token, String encodedQuery, int searchLimit) {
    return http.get(
      Uri.parse(
          'https://api.spotify.com/v1/search?q=$encodedQuery&type=track&limit=$searchLimit&market=JP'),
      headers: {
        'Authorization': 'Bearer $token',
      },
    );
  }

  /// レスポンスからTrackModelリストを生成
  List<TrackModel> _parseSearchResponse(http.Response response, String query, int limit) {
    final data = json.decode(response.body);
    final tracks = data['tracks']['items'] as List;

    if (tracks.isEmpty) {
      print('🎵 Spotify: No results found for "$query"');
      return [];
    }

    print('🎵 Spotify: Found ${tracks.length} results, filtering for original versions...');

    final scoredTracks = _scoreAndFilterTracks(tracks, query);

    final results = scoredTracks.take(limit).map((scoredTrack) {
      final trackData = scoredTrack['track'];

      final images = trackData['album']['images'] as List;
      String albumImageUrl = '';
      if (images.isNotEmpty) {
        albumImageUrl = images[0]['url'];
      }

      final artists = trackData['artists'] as List;
      String artistName = '';
      String? spotifyArtistId;
      if (artists.isNotEmpty) {
        artistName = artists.map((a) => a['name']).join(', ');
        spotifyArtistId = artists[0]['id']?.toString();
      }

      final previewUrl = trackData['preview_url'] as String? ?? '';

      return TrackModel(
        trackId: trackData['id'],
        trackName: trackData['name'],
        artistName: artistName,
        albumImageUrl: albumImageUrl,
        previewUrl: previewUrl,
        spotifyArtistId: spotifyArtistId,
      );
    }).toList();

    print('✅ Spotify: Returning ${results.length} filtered tracks');
    return results;
  }

  /// 楽曲を検索（403時はClient Credentialsで再試行）
  Future<List<TrackModel>> searchTracks(String query, {int limit = 20}) async {
    if (query.isEmpty) return [];

    final token = await _getAccessToken();
    if (token == null) {
      print('❌ Spotifyトークン取得失敗');
      throw Exception('Spotifyトークンを取得できません');
    }

    final encodedQuery = Uri.encodeComponent(query);
    final searchLimit = (limit * 3).clamp(1, 50);
    final response = await _executeSearch(token, encodedQuery, searchLimit);

    if (response.statusCode == 200) {
      return _parseSearchResponse(response, query, limit);
    }

    // 403エラー: OAuthトークンがDevelopment mode制限 → Client Credentialsで再試行
    if (response.statusCode == 403) {
      print('⚠️ Spotify OAuth 403エラー - Client Credentialsトークンで再試行');
      final ccToken = await _getClientCredentialsToken();
      if (ccToken != null) {
        final retryResponse = await _executeSearch(ccToken, encodedQuery, searchLimit);
        if (retryResponse.statusCode == 200) {
          return _parseSearchResponse(retryResponse, query, limit);
        }
        print('❌ Spotify Client Credentials再試行も失敗: ${retryResponse.statusCode}');
      }
    }

    print('❌ Spotify search error: ${response.statusCode} ${response.body}');
    throw Exception('Spotify API error: ${response.statusCode}');
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

  /// アーティスト名からSpotifyのアーティスト画像URLを取得（結果はキャッシュ）
  Future<String?> getArtistImageUrl(String artistName) async {
    if (_artistImageCache.containsKey(artistName)) {
      return _artistImageCache[artistName];
    }

    final token = await _getAccessToken();
    if (token == null) return null;

    try {
      final encoded = Uri.encodeComponent(artistName);
      final response = await http.get(
        Uri.parse(
            'https://api.spotify.com/v1/search?q=$encoded&type=artist&limit=1&market=JP'),
        headers: {'Authorization': 'Bearer $token'},
      ).timeout(const Duration(seconds: 8));

      if (response.statusCode != 200) {
        _artistImageCache[artistName] = null;
        return null;
      }

      final data = json.decode(response.body);
      final items = data['artists']?['items'] as List?;
      if (items == null || items.isEmpty) {
        _artistImageCache[artistName] = null;
        return null;
      }

      final images = items[0]['images'] as List?;
      if (images == null || images.isEmpty) {
        _artistImageCache[artistName] = null;
        return null;
      }

      // imagesは大きい順に並んでいるので先頭が最高解像度
      final url = images[0]['url'] as String?;
      _artistImageCache[artistName] = url;
      return url;
    } catch (e) {
      print('❌ Spotify getArtistImageUrl error: $e');
      _artistImageCache[artistName] = null;
      return null;
    }
  }

  /// Spotify アーティストIDからアーティスト情報（画像URL + フォロワー数）を取得する。
  /// 名前検索より正確（同名アーティストや表記揺れの問題が無い）。
  Future<({String? imageUrl, int followerCount})> getArtistById(String artistId) async {
    if (artistId.isEmpty) return (imageUrl: null, followerCount: 0);
    final cached = _artistByIdCache[artistId];
    if (cached != null) return cached;

    final token = await _getAccessToken();
    if (token == null) return (imageUrl: null, followerCount: 0);

    try {
      final response = await http.get(
        Uri.parse('https://api.spotify.com/v1/artists/$artistId'),
        headers: {'Authorization': 'Bearer $token'},
      ).timeout(const Duration(seconds: 8));

      if (response.statusCode != 200) {
        final result = (imageUrl: null, followerCount: 0);
        _artistByIdCache[artistId] = result;
        return result;
      }

      final data = json.decode(response.body) as Map<String, dynamic>;
      final images = data['images'] as List?;
      final imageUrl = (images != null && images.isNotEmpty)
          ? images[0]['url'] as String?
          : null;
      final followerCount =
          ((data['followers'] as Map?)?['total'] as num?)?.toInt() ?? 0;

      final result = (imageUrl: imageUrl, followerCount: followerCount);
      _artistByIdCache[artistId] = result;
      return result;
    } catch (e) {
      print('❌ Spotify getArtistById error: $e');
      final result = (imageUrl: null, followerCount: 0);
      _artistByIdCache[artistId] = result;
      return result;
    }
  }

  /// 画像URLのみ欲しい時のショートカット
  Future<String?> getArtistImageUrlById(String artistId) async {
    final info = await getArtistById(artistId);
    return info.imageUrl;
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
        return _parseTrackData(trackData);
      } else {
        print('Spotify get track error: ${response.statusCode} ${response.body}');
        return null;
      }
    } catch (e) {
      print('Error getting track: $e');
      return null;
    }
  }

  /// Spotifyトラックデータから TrackModel を生成（共通パーサー）
  TrackModel _parseTrackData(Map<String, dynamic> trackData) {
    final images = trackData['album']?['images'] as List? ?? [];
    String albumImageUrl = '';
    if (images.isNotEmpty) {
      albumImageUrl = images[0]['url'] ?? '';
    }

    final artists = trackData['artists'] as List? ?? [];
    String artistName = '';
    String? spotifyArtistId;
    if (artists.isNotEmpty) {
      artistName = artists.map((a) => a['name']).join(', ');
      spotifyArtistId = artists[0]['id']?.toString();
    }

    final previewUrl = trackData['preview_url'] as String? ?? '';

    return TrackModel(
      trackId: trackData['id'],
      trackName: trackData['name'],
      artistName: artistName,
      albumImageUrl: albumImageUrl,
      previewUrl: previewUrl,
      spotifyArtistId: spotifyArtistId,
    );
  }

  /// Spotify検索でトラックIDを取得（楽曲名+アーティスト名から）
  /// Apple Musicトラック等のSpotify ID取得に使用
  Future<String?> searchTrackId(String trackName, String artistName) async {
    final token = await _getAccessToken();
    if (token == null) return null;

    try {
      final query = Uri.encodeComponent('track:$trackName artist:$artistName');
      final response = await http.get(
        Uri.parse('https://api.spotify.com/v1/search?q=$query&type=track&limit=1&market=JP'),
        headers: {
          'Authorization': 'Bearer $token',
        },
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final tracks = data['tracks']['items'] as List;
        if (tracks.isNotEmpty) {
          return tracks[0]['id'] as String;
        }
      }
      return null;
    } catch (e) {
      print('❌ Error searching track ID: $e');
      return null;
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
        return items
            .where((item) => item['track'] != null)
            .map((item) => _parseTrackData(item['track']))
            .toList();
      } else {
        print('Spotify playlist error: ${response.statusCode} ${response.body}');
        return [];
      }
    } catch (e) {
      print('Error getting playlist tracks: $e');
      return [];
    }
  }

  /// プレイリスト名で検索してトラックを取得
  Future<List<TrackModel>> searchPlaylistTracks(String playlistName,
      {int limit = 20}) async {
    final token = await _getAccessToken();
    if (token == null) return [];

    try {
      final encodedQuery = Uri.encodeComponent(playlistName);
      final searchResponse = await http.get(
        Uri.parse(
            'https://api.spotify.com/v1/search?q=$encodedQuery&type=playlist&limit=1&market=JP'),
        headers: {'Authorization': 'Bearer $token'},
      );

      if (searchResponse.statusCode == 200) {
        final data = json.decode(searchResponse.body);
        final items = data['playlists']?['items'] as List?;
        if (items == null || items.isEmpty) return [];
        final playlistId = items[0]['id'] as String;
        return await getPlaylistTracks(playlistId, limit: limit);
      }
      return [];
    } catch (e) {
      print('Error searching Spotify playlist: $e');
      return [];
    }
  }

  /// ユーザーの最近再生した楽曲を取得
  /// OAuth認証が必要（user-read-recently-playedスコープ）
  Future<List<TrackModel>> getRecentlyPlayedTracks({int limit = 30}) async {
    if (!await _authService.isAuthenticated()) {
      print('❌ OAuth authentication required for recently played');
      return [];
    }

    final token = await _authService.getAccessToken();
    if (token == null) {
      print('❌ Failed to get OAuth access token for recently played');
      return [];
    }

    print('🎵 Spotify getRecentlyPlayedTracks: 最近再生した曲を取得中...');

    try {
      final response = await http.get(
        Uri.parse('https://api.spotify.com/v1/me/player/recently-played?limit=$limit'),
        headers: {
          'Authorization': 'Bearer $token',
        },
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final items = data['items'] as List;
        // 重複を除外（同じ曲が複数回再生されている場合）
        final Map<String, TrackModel> uniqueTracks = {};
        for (final item in items) {
          if (item['track'] != null) {
            final track = _parseTrackData(item['track']);
            uniqueTracks.putIfAbsent(track.trackId, () => track);
          }
        }
        return uniqueTracks.values.toList();
      } else {
        print('Spotify recently played error: ${response.statusCode} ${response.body}');
        return [];
      }
    } catch (e) {
      print('Error getting recently played tracks: $e');
      return [];
    }
  }

  /// ユーザーのお気に入り楽曲（Saved Tracks）を取得
  /// OAuth認証が必要（user-library-readスコープ）
  Future<List<TrackModel>> getSavedTracks({int limit = 50}) async {
    // OAuth認証トークンが必要（Client Credentialsでは不可）
    if (!await _authService.isAuthenticated()) {
      print('❌ OAuth authentication required for saved tracks');
      return [];
    }

    // OAuthトークンを直接取得（Client Credentialsではなく）
    final token = await _authService.getAccessToken();
    if (token == null) {
      print('❌ Failed to get OAuth access token for saved tracks');
      return [];
    }

    print('🎵 Spotify getSavedTracks: OAuthトークンでライブラリ取得中...');

    try {
      final response = await http.get(
        Uri.parse('https://api.spotify.com/v1/me/tracks?limit=$limit'),
        headers: {
          'Authorization': 'Bearer $token',
        },
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final items = data['items'] as List;
        return items
            .where((item) => item['track'] != null)
            .map((item) => _parseTrackData(item['track']))
            .toList();
      } else {
        print('Spotify saved tracks error: ${response.statusCode} ${response.body}');
        return [];
      }
    } catch (e) {
      print('Error getting saved tracks: $e');
      return [];
    }
  }
}

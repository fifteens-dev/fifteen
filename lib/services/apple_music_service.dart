import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../models/track_model.dart';
import 'musickit_service.dart';

/// Apple Music API サービス
class AppleMusicService {
  static final AppleMusicService _instance = AppleMusicService._internal();
  factory AppleMusicService() => _instance;
  AppleMusicService._internal();

  final _storage = const FlutterSecureStorage();
  final _musicKit = MusicKitService();

  static const String _developerTokenKey = 'apple_music_developer_token';
  static const String _userTokenKey = 'apple_music_user_token';

  String? _developerToken;
  String? _userToken;

  /// Developer Tokenを取得（.envまたはバックエンドから）
  String get _envDeveloperToken => dotenv.env['APPLE_MUSIC_DEVELOPER_TOKEN'] ?? '';

  /// Developer Tokenを確実にロードする
  Future<void> _ensureDeveloperToken() async {
    if (_developerToken != null && _developerToken!.isNotEmpty) return;

    // .envから読み込み
    if (_envDeveloperToken.isNotEmpty) {
      _developerToken = _envDeveloperToken;
      return;
    }

    // ストレージから読み込み
    _developerToken = await _storage.read(key: _developerTokenKey);
  }

  /// Developer Tokenが利用可能かチェック（検索・カタログAPI用）
  Future<bool> _checkDeveloperToken() async {
    await _ensureDeveloperToken();
    return _developerToken != null && _developerToken!.isNotEmpty;
  }

  /// ユーザー認証状態を確認（User Token必要なAPI用）
  /// User Tokenが存在する場合のみtrueを返す
  Future<bool> isAuthenticated() async {
    if (_userToken != null) return true;
    _userToken = await _storage.read(key: _userTokenKey);
    return _userToken != null;
  }

  /// User Token認証（MusicKit使用）
  /// iOS: User Token認証を試みる
  /// Android/Web: Developer Tokenのみで動作（User Token認証はスキップ）
  Future<bool> login() async {
    try {
      // iOSでのみUser Token認証を試みる
      if (_musicKit.isSupported) {
        print('📱 iOS環境: MusicKit User Token認証を試みます');
        // MusicKit認証をリクエスト
        final status = await _musicKit.requestAuthorization();

        if (status == 'authorized') {
          // Developer Tokenを確認（User Token取得に必要）
          await _ensureDeveloperToken();
          if (_developerToken == null || _developerToken!.isEmpty) {
            print('❌ Developer Tokenが設定されていないため、User Token取得不可');
            return false;
          }

          // User Tokenを取得（失敗した場合はサブスクリプション未加入として扱う）
          final userToken = await _musicKit.getUserToken(developerToken: _developerToken);

          if (userToken != null) {
            _userToken = userToken;
            await _storage.write(key: _userTokenKey, value: userToken);
            print('✅ Apple Music User Token取得成功');
            return true;
          } else {
            // authorized後のトークン失敗 = サブスクリプション未加入
            print('❌ User Token取得失敗（サブスクリプション未加入の可能性）');
            throw AppleMusicNoSubscriptionException('Apple Musicのサブスクリプションが必要です');
          }
        } else {
          print('❌ MusicKit認証が拒否されました: $status');
          return false;
        }
      } else {
        // Android/WebではDeveloper Tokenのみで動作
        print('🌐 Android/Web環境: Developer Tokenのみで動作します');

        // Developer Tokenの確認
        if (_developerToken == null) {
          _developerToken = _envDeveloperToken.isNotEmpty
              ? _envDeveloperToken
              : await _storage.read(key: _developerTokenKey);
        }

        if (_developerToken != null && _developerToken!.isNotEmpty) {
          print('✅ Apple Music Developer Token確認成功');
          return true;
        } else {
          print('❌ Apple Music Developer Tokenが設定されていません');
          return false;
        }
      }
    } on AppleMusicNoSubscriptionException {
      rethrow;
    } catch (e) {
      print('❌ Apple Music login error: $e');
      return false;
    }
  }

  /// ログアウト
  Future<void> logout() async {
    _userToken = null;
    await _storage.delete(key: _userTokenKey);
  }

  /// Apple Music有料サブスクリプションの利用可能状態を確認
  /// 個人データAPIを試し、403が返れば未加入と判定
  Future<bool> checkSubscriptionAccess() async {
    if (_userToken == null) {
      _userToken = await _storage.read(key: _userTokenKey);
    }
    if (_userToken == null) return false;

    await _ensureDeveloperToken();
    if (_developerToken == null || _developerToken!.isEmpty) return false;

    try {
      final response = await http.get(
        Uri.parse('https://api.music.apple.com/v1/me/recent/played/tracks?limit=1'),
        headers: {
          'Authorization': 'Bearer $_developerToken',
          'Music-User-Token': _userToken!,
        },
      );
      // 403はサブスクリプション未加入
      final hasSubscription = response.statusCode != 403;
      print(hasSubscription
          ? '✅ Apple Music サブスクリプション確認: 加入済み'
          : '⚠️ Apple Music サブスクリプション確認: 未加入 (${response.statusCode})');
      return hasSubscription;
    } catch (e) {
      print('❌ Subscription check error: $e');
      return false;
    }
  }

  /// 楽曲を検索
  Future<List<TrackModel>> searchTracks(String query, {int limit = 20}) async {
    if (query.isEmpty) return [];

    if (!await _checkDeveloperToken()) {
      print('Apple Music Developer Tokenが設定されていません');
      return [];
    }

    try {
      // Apple Music APIのlimit上限は25
      final apiLimit = limit.clamp(1, 25);
      final encodedQuery = Uri.encodeComponent(query);
      final response = await http.get(
        Uri.parse(
            'https://api.music.apple.com/v1/catalog/jp/search?term=$encodedQuery&types=songs&limit=$apiLimit&l=ja-JP'),
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
    if (!await _checkDeveloperToken()) {
      print('Apple Music Developer Tokenが設定されていません');
      return [];
    }

    try {
      final response = await http.get(
        Uri.parse(
            'https://api.music.apple.com/v1/catalog/jp/playlists/$playlistId?l=ja-JP'),
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
  /// プレイリスト名で検索してトラックを取得
  Future<List<TrackModel>> searchPlaylistTracks(String playlistName,
      {int limit = 20}) async {
    if (!await _checkDeveloperToken()) return [];

    try {
      final encodedQuery = Uri.encodeComponent(playlistName);
      final searchResponse = await http.get(
        Uri.parse(
            'https://api.music.apple.com/v1/catalog/jp/search?term=$encodedQuery&types=playlists&limit=1&l=ja-JP'),
        headers: {'Authorization': 'Bearer $_developerToken'},
      );

      if (searchResponse.statusCode == 200) {
        final data = json.decode(searchResponse.body);
        final playlists =
            data['results']?['playlists']?['data'] as List?;
        if (playlists == null || playlists.isEmpty) return [];
        final playlistId = playlists[0]['id'] as String;
        return await getPlaylistTracks(playlistId, limit: limit);
      }
      return [];
    } catch (e) {
      print('Error searching Apple Music playlist: $e');
      return [];
    }
  }

  Future<List<TrackModel>> getTopCharts({int limit = 50}) async {
    if (!await _checkDeveloperToken()) {
      print('Apple Music Developer Tokenが設定されていません');
      return [];
    }

    try {
      final response = await http.get(
        Uri.parse(
            'https://api.music.apple.com/v1/catalog/jp/charts?types=songs&limit=$limit&l=ja-JP'),
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
        return charts.map((d) => _trackFromChartData(d)).toList();
      } else {
        print('Apple Music charts error: ${response.statusCode} ${response.body}');
        return [];
      }
    } catch (e) {
      print('Error getting Apple Music charts: $e');
      return [];
    }
  }

  /// 日本の急上昇プレイリスト（Hot Hits Japan）から楽曲を取得
  Future<List<TrackModel>> getHotHitsJapan({int limit = 50}) async {
    if (!await _checkDeveloperToken()) return [];
    try {
      // types=playlists で日本の編集プレイリストチャートを取得
      final response = await http.get(
        Uri.parse(
            'https://api.music.apple.com/v1/catalog/jp/charts?types=playlists&limit=5&l=ja-JP'),
        headers: {'Authorization': 'Bearer $_developerToken'},
      );
      if (response.statusCode != 200) {
        print('getHotHitsJapan error: ${response.statusCode}');
        return [];
      }
      final data = json.decode(response.body);
      final playlists = data['results']?['playlists'] as List?;
      if (playlists == null || playlists.isEmpty) return [];
      final playlistId = playlists[0]['data']?[0]?['id'] as String?;
      print('📊 急上昇プレイリストID: $playlistId (${playlists[0]['name']})');
      if (playlistId == null) return [];
      return await getPlaylistTracks(playlistId, limit: limit);
    } catch (e) {
      print('Error getHotHitsJapan: $e');
      return [];
    }
  }

  /// ジャンル別日本チャートを取得（Developer Tokenのみ）
  Future<List<TrackModel>> getTopChartsByGenre(String genreId,
      {int limit = 50}) async {
    if (!await _checkDeveloperToken()) return [];
    try {
      final response = await http.get(
        Uri.parse(
            'https://api.music.apple.com/v1/catalog/jp/charts?types=songs&genre=$genreId&limit=$limit&l=ja-JP'),
        headers: {'Authorization': 'Bearer $_developerToken'},
      );
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final songs = data['results']?['songs'] as List?;
        if (songs == null || songs.isEmpty) return [];
        final charts = songs[0]['data'] as List;
        return charts.map((d) => _trackFromChartData(d)).toList();
      }
      print('getTopChartsByGenre error: ${response.statusCode}');
      return [];
    } catch (e) {
      print('Error getTopChartsByGenre: $e');
      return [];
    }
  }

  /// 日次グローバルTop100プレイリストから楽曲を取得（Developer Tokenのみ）
  Future<List<TrackModel>> getDailyTopChartTracks({int limit = 50}) async {
    if (!await _checkDeveloperToken()) return [];
    try {
      // Step1: dailyGlobalTopCharts プレイリスト一覧を取得
      final response = await http.get(
        Uri.parse(
            'https://api.music.apple.com/v1/catalog/jp/charts?types=playlists&with=dailyGlobalTopCharts&limit=10&l=ja-JP'),
        headers: {'Authorization': 'Bearer $_developerToken'},
      );
      if (response.statusCode != 200) {
        print('getDailyTopChartTracks step1 error: ${response.statusCode} ${response.body}');
        return [];
      }
      final data = json.decode(response.body);
      final results = data['results'] as Map<String, dynamic>?;
      if (results == null) return [];

      // with=dailyGlobalTopCharts の場合、レスポンスキーを確認
      print('📊 getDailyTopChartTracks results keys: ${results.keys.toList()}');

      // dailyGlobalTopCharts キーを優先して探す
      String? playlistId;
      final dailyCharts = results['dailyGlobalTopCharts'] as List?;
      if (dailyCharts != null && dailyCharts.isNotEmpty) {
        playlistId = dailyCharts[0]['data']?[0]?['id'] as String?;
        print('📊 dailyGlobalTopCharts playlist id: $playlistId');
      }

      // フォールバック: playlists キーから探す
      if (playlistId == null) {
        final playlists = results['playlists'] as List?;
        if (playlists != null && playlists.isNotEmpty) {
          playlistId = playlists[0]['data']?[0]?['id'] as String?;
          print('📊 playlists fallback playlist id: $playlistId');
        }
      }

      if (playlistId == null) {
        print('⚠️ getDailyTopChartTracks: playlist id not found');
        return [];
      }

      // Step2: プレイリストから楽曲を取得
      return await getPlaylistTracks(playlistId, limit: limit);
    } catch (e) {
      print('Error getDailyTopChartTracks: $e');
      return [];
    }
  }

  /// チャートデータから TrackModel を生成する共通ヘルパー
  TrackModel _trackFromChartData(Map<String, dynamic> chartData) {
    final attributes = chartData['attributes'] as Map<String, dynamic>;
    String albumImageUrl = '';
    if (attributes['artwork'] != null) {
      final url = attributes['artwork']['url'] as String;
      albumImageUrl = url.replaceAll('{w}', '640').replaceAll('{h}', '640');
    }
    String previewUrl = '';
    final previews = attributes['previews'] as List?;
    if (previews != null && previews.isNotEmpty) {
      previewUrl = (previews[0]['url'] as String?) ?? '';
    }
    return TrackModel(
      trackId: chartData['id'] as String,
      trackName: attributes['name'] as String,
      artistName: attributes['artistName'] as String,
      albumImageUrl: albumImageUrl,
      previewUrl: previewUrl,
    );
  }

  /// ユーザーのお気に入り楽曲を取得
  /// User Token認証が必要
  Future<List<TrackModel>> getRecentlyPlayedTracks({int limit = 30}) async {
    if (_userToken == null) {
      _userToken = await _storage.read(key: _userTokenKey);
    }
    if (_userToken == null) {
      print('❌ User Token not found for recently played.');
      return [];
    }
    if (_developerToken == null) {
      _developerToken = _envDeveloperToken.isNotEmpty
          ? _envDeveloperToken
          : await _storage.read(key: _developerTokenKey);
    }
    if (_developerToken == null || _developerToken!.isEmpty) {
      print('❌ Developer Token not found for recently played.');
      return [];
    }

    try {
      final response = await http.get(
        Uri.parse('https://api.music.apple.com/v1/me/recent/played/tracks?limit=$limit&l=ja-JP'),
        headers: {
          'Authorization': 'Bearer $_developerToken',
          'Music-User-Token': _userToken!,
        },
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['data'] == null || (data['data'] as List).isEmpty) {
          print('⚠️ No recently played tracks found');
          return [];
        }

        final songs = data['data'] as List;
        final Map<String, TrackModel> uniqueTracks = {};
        for (final songData in songs) {
          final attributes = songData['attributes'];
          String albumImageUrl = '';
          if (attributes['artwork'] != null) {
            final artworkUrl = attributes['artwork']['url'] as String;
            albumImageUrl = artworkUrl.replaceAll('{w}', '640').replaceAll('{h}', '640');
          }
          String previewUrl = '';
          if (attributes['previews'] != null && attributes['previews'].isNotEmpty) {
            previewUrl = attributes['previews'][0]['url'] ?? '';
          }
          final track = TrackModel(
            trackId: songData['id'],
            trackName: attributes['name'] ?? 'Unknown',
            artistName: attributes['artistName'] ?? 'Unknown Artist',
            albumImageUrl: albumImageUrl,
            previewUrl: previewUrl,
          );
          uniqueTracks.putIfAbsent(track.trackId, () => track);
        }
        return uniqueTracks.values.toList();
      } else {
        print('❌ Apple Music recently played error: ${response.statusCode}');
        return [];
      }
    } catch (e) {
      print('❌ Error getting Apple Music recently played: $e');
      return [];
    }
  }

  Future<List<TrackModel>> getSavedTracks({int limit = 50}) async {
    // User Tokenがない場合は取得できない
    if (_userToken == null) {
      _userToken = await _storage.read(key: _userTokenKey);
    }

    if (_userToken == null) {
      print('❌ User Token not found. Please login first.');
      return [];
    }

    // Developer Tokenも必要
    if (_developerToken == null) {
      _developerToken = _envDeveloperToken.isNotEmpty
          ? _envDeveloperToken
          : await _storage.read(key: _developerTokenKey);
    }

    if (_developerToken == null || _developerToken!.isEmpty) {
      print('❌ Developer Token not found.');
      return [];
    }

    try {
      // Library API: ユーザーのライブラリから楽曲を取得
      final response = await http.get(
        Uri.parse('https://api.music.apple.com/v1/me/library/songs?limit=$limit&l=ja-JP'),
        headers: {
          'Authorization': 'Bearer $_developerToken',
          'Music-User-Token': _userToken!,
        },
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);

        if (data['data'] == null || (data['data'] as List).isEmpty) {
          print('⚠️ No saved tracks found in user library');
          return [];
        }

        final songs = data['data'] as List;

        return songs.map((songData) {
          final attributes = songData['attributes'];

          // アルバムアートワークURL
          String albumImageUrl = '';
          if (attributes['artwork'] != null) {
            final artworkUrl = attributes['artwork']['url'] as String;
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
            trackName: attributes['name'] ?? 'Unknown',
            artistName: attributes['artistName'] ?? 'Unknown Artist',
            albumImageUrl: albumImageUrl,
            previewUrl: previewUrl,
          );
        }).toList();
      } else if (response.statusCode == 401) {
        print('❌ Authentication failed. User Token may be expired.');
        // User Tokenをクリア
        _userToken = null;
        await _storage.delete(key: _userTokenKey);
        return [];
      } else {
        print('❌ Apple Music library error: ${response.statusCode} ${response.body}');
        return [];
      }
    } catch (e) {
      print('❌ Error getting Apple Music saved tracks: $e');
      return [];
    }
  }

  /// 楽曲の歌詞を取得
  /// trackId: Apple MusicのトラックID（例: "1234567890"）
  /// storefront: ストアフロント（デフォルト: "jp"）
  Future<String?> getLyrics(String trackId, {String storefront = 'jp'}) async {
    if (trackId.isEmpty) {
      print('Track ID is empty');
      return null;
    }

    if (!await _checkDeveloperToken()) {
      print('Apple Music Developer Tokenが設定されていません');
      return null;
    }

    try {
      // 歌詞APIエンドポイント
      final response = await http.get(
        Uri.parse(
            'https://api.music.apple.com/v1/catalog/$storefront/songs/$trackId/lyrics'),
        headers: {
          'Authorization': 'Bearer $_developerToken',
        },
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);

        // レスポンス構造: data[0].attributes.ttml
        if (data['data'] != null && data['data'].isNotEmpty) {
          final attributes = data['data'][0]['attributes'];

          // TTMLフォーマットの歌詞テキストを取得
          if (attributes['ttml'] != null) {
            final ttmlText = attributes['ttml'] as String;
            // TTMLタグを除去してプレーンテキストを抽出
            final lyrics = _parseTTML(ttmlText);
            return lyrics;
          }
        }

        print('歌詞が見つかりませんでした（Track ID: $trackId）');
        return null;
      } else if (response.statusCode == 404) {
        print('この楽曲には歌詞がありません（Track ID: $trackId）');
        return null;
      } else {
        print('Apple Music lyrics error: ${response.statusCode} ${response.body}');
        return null;
      }
    } catch (e) {
      print('Error fetching Apple Music lyrics: $e');
      return null;
    }
  }

  /// TTMLフォーマットの歌詞からプレーンテキストを抽出
  String _parseTTML(String ttml) {
    // TTMLはXML形式なので、<p>タグ内のテキストを抽出
    final RegExp pTagPattern = RegExp(r'<p[^>]*>(.*?)</p>', dotAll: true);
    final matches = pTagPattern.allMatches(ttml);

    final lyrics = matches.map((match) {
      String line = match.group(1) ?? '';
      // <span>タグなどの子要素を除去
      line = line.replaceAll(RegExp(r'<[^>]+>'), '');
      // HTMLエンティティをデコード
      line = _decodeHtmlEntities(line);
      return line.trim();
    }).where((line) => line.isNotEmpty).join('\n');

    return lyrics;
  }

  /// HTMLエンティティをデコード
  String _decodeHtmlEntities(String text) {
    return text
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"')
        .replaceAll('&#39;', "'")
        .replaceAll('&apos;', "'");
  }
}

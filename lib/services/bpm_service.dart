import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter_dotenv/flutter_dotenv.dart';

/// BPM（テンポ）取得・キャッシュサービス
/// GetSongBPM API を利用してBPMを取得する
/// https://getsongbpm.com/api
class BpmService {
  static final BpmService _instance = BpmService._internal();
  factory BpmService() => _instance;
  BpmService._internal();

  String get _apiKey => dotenv.env['GETSONGBPM_API_KEY'] ?? '';

  // trackId → tempo のキャッシュ
  final Map<String, double?> _cache = {};

  // 現在取得中のトラックID（重複リクエスト防止）
  final Set<String> _fetching = {};

  /// BPMを取得（キャッシュ優先）
  Future<double?> getTempo({
    required String trackId,
    String? trackName,
    String? artistName,
  }) async {
    if (_cache.containsKey(trackId)) {
      return _cache[trackId];
    }

    if (_fetching.contains(trackId)) {
      return null;
    }

    if (_apiKey.isEmpty) {
      print('⚠️ GETSONGBPM_API_KEY が .env に設定されていません');
      return null;
    }

    if (trackName == null || trackName.isEmpty) {
      return null;
    }

    _fetching.add(trackId);

    try {
      final tempo = await _fetchBpm(trackName, artistName);
      _cache[trackId] = tempo;

      if (tempo != null) {
        print('🎵 BPM取得成功: $trackName - ${tempo}BPM');
      } else {
        print('⚠️ BPM取得失敗: $trackName');
      }

      return tempo;
    } catch (e) {
      print('❌ BpmService error: $e');
      _cache[trackId] = null;
      return null;
    } finally {
      _fetching.remove(trackId);
    }
  }

  /// GetSongBPM APIで楽曲のBPMを取得
  Future<double?> _fetchBpm(String trackName, String? artistName) async {
    // 1. 楽曲を検索
    final songId = await _searchSong(trackName, artistName);
    if (songId == null) return null;

    // 2. BPMを取得
    return await _getSongTempo(songId);
  }

  /// GetSongBPM 検索API
  Future<String?> _searchSong(String trackName, String? artistName) async {
    try {
      final lookup = Uri.encodeComponent(trackName);
      final url =
          'https://api.getsongbpm.com/search/?api_key=$_apiKey&type=song&lookup=$lookup';

      final response = await http.get(
        Uri.parse(url),
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode != 200) {
        print('⚠️ GetSongBPM search error: ${response.statusCode}');
        return null;
      }

      final data = json.decode(response.body);
      final searchResults = data['search'] as List?;
      if (searchResults == null || searchResults.isEmpty) {
        print('⚠️ GetSongBPM: "$trackName" の検索結果なし');
        return null;
      }

      // アーティスト名でマッチング
      if (artistName != null && artistName.isNotEmpty) {
        final artistLower = artistName.toLowerCase();
        for (final result in searchResults) {
          final resultArtist =
              (result['artist']?['name'] ?? '').toString().toLowerCase();
          if (resultArtist.contains(artistLower) ||
              artistLower.contains(resultArtist)) {
            return result['id']?.toString();
          }
        }
      }

      // マッチしない場合は最初の結果を使用
      return searchResults[0]['id']?.toString();
    } catch (e) {
      print('❌ GetSongBPM search error: $e');
      return null;
    }
  }

  /// GetSongBPM 楽曲詳細APIからBPMを取得
  Future<double?> _getSongTempo(String songId) async {
    try {
      final url =
          'https://api.getsongbpm.com/song/?api_key=$_apiKey&id=$songId';

      final response = await http.get(
        Uri.parse(url),
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode != 200) {
        print('⚠️ GetSongBPM song error: ${response.statusCode}');
        return null;
      }

      final data = json.decode(response.body);
      final song = data['song'];
      if (song == null) return null;

      final tempoStr = song['tempo']?.toString();
      if (tempoStr == null || tempoStr.isEmpty) return null;

      return double.tryParse(tempoStr);
    } catch (e) {
      print('❌ GetSongBPM song error: $e');
      return null;
    }
  }

  /// キャッシュをクリア
  void clearCache() {
    _cache.clear();
  }
}

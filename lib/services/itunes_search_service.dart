import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/track_model.dart';

/// iTunes Search API サービス
class ITunesSearchService {
  static final ITunesSearchService _instance = ITunesSearchService._internal();
  factory ITunesSearchService() => _instance;
  ITunesSearchService._internal();

  /// 楽曲のプレビューURLを取得
  ///
  /// [trackName] 楽曲名
  /// [artistName] アーティスト名
  /// 戻り値: プレビューURL（取得できない場合はnull）
  Future<String?> getPreviewUrl({
    required String trackName,
    required String artistName,
  }) async {
    try {
      // 検索クエリを構築（楽曲名 + アーティスト名）
      final query = '$trackName $artistName'.trim();
      final encodedQuery = Uri.encodeComponent(query);

      // iTunes Search API エンドポイント
      final url = Uri.parse(
        'https://itunes.apple.com/search?term=$encodedQuery&country=JP&media=music&entity=song&limit=5'
      );

      print('🍎 iTunes Search API request: $query');

      final response = await http.get(url);

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final results = data['results'] as List;

        if (results.isEmpty) {
          print('🍎 iTunes: No results found for "$query"');
          return null;
        }

        // 最初の結果からpreviewUrlを取得
        final firstResult = results[0];
        final previewUrl = firstResult['previewUrl'];

        if (previewUrl != null && previewUrl.toString().isNotEmpty) {
          // HTTPをHTTPSに変換（Mixed Content対策 - モバイルWeb対応）
          final secureUrl = previewUrl.toString().replaceFirst('http://', 'https://');
          print('🍎 iTunes: Found preview URL for "${firstResult['trackName']}"');
          print('🔒 Secured URL: $secureUrl');
          return secureUrl;
        } else {
          print('🍎 iTunes: No preview URL in result');
          return null;
        }
      } else {
        print('🍎 iTunes Search API error: ${response.statusCode}');
        return null;
      }
    } catch (e) {
      print('🍎 iTunes Search API exception: $e');
      return null;
    }
  }

  /// 楽曲名とアーティスト名の類似度をチェック
  /// より正確なマッチングのための補助関数（将来の改善用）
  bool _isSimilarTrack(String searchTrack, String resultTrack) {
    final search = searchTrack.toLowerCase().trim();
    final result = resultTrack.toLowerCase().trim();

    // 完全一致
    if (search == result) return true;

    // 含まれているか
    if (result.contains(search) || search.contains(result)) return true;

    return false;
  }

  /// 楽曲を検索
  ///
  /// [query] 検索クエリ
  /// [limit] 取得する楽曲数
  /// 戻り値: 楽曲のリスト
  Future<List<TrackModel>> searchTracks(String query, {int limit = 20}) async {
    if (query.isEmpty) return [];

    try {
      final encodedQuery = Uri.encodeComponent(query);
      final url = Uri.parse(
        'https://itunes.apple.com/search?term=$encodedQuery&country=JP&media=music&entity=song&limit=$limit'
      );

      print('🍎 iTunes Search API: $query');

      final response = await http.get(url);

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final results = data['results'] as List;

        if (results.isEmpty) {
          print('🍎 iTunes: No results found for "$query"');
          return [];
        }

        // 結果をTrackModelに変換
        final trackModels = <TrackModel>[];
        for (final result in results) {
          final trackName = result['trackName'] ?? '';
          final artistName = result['artistName'] ?? '';
          final albumImageUrl = result['artworkUrl100'] ?? '';
          final previewUrl = result['previewUrl'] ?? '';
          // HTTPをHTTPSに変換（Mixed Content対策 - モバイルWeb対応）
          final securePreviewUrl = previewUrl.isNotEmpty
              ? previewUrl.toString().replaceFirst('http://', 'https://')
              : '';
          // trackIdとしてtrackIdを使用（iTunesのID）
          final trackId = result['trackId']?.toString() ?? '';

          if (trackName.isNotEmpty) {
            trackModels.add(TrackModel(
              trackId: trackId,
              trackName: trackName,
              artistName: artistName,
              albumImageUrl: albumImageUrl,
              previewUrl: securePreviewUrl,
            ));
            print('🍎 iTunes: Added track "$trackName" by $artistName');
          }
        }

        print('🍎 iTunes: Found ${trackModels.length} tracks');
        return trackModels;
      } else {
        print('🍎 iTunes Search API error: ${response.statusCode}');
        return [];
      }
    } catch (e) {
      print('🍎 iTunes Search API exception: $e');
      return [];
    }
  }
}

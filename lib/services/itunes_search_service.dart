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

      // iTunes Search API エンドポイント（検索結果を増やして最適な版を選ぶ）
      final url = Uri.parse(
        'https://itunes.apple.com/search?term=$encodedQuery&country=JP&media=music&entity=song&limit=20'
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

        // メインバージョンを優先的に選択
        final bestResult = _selectBestVersion(results, trackName, artistName);

        if (bestResult == null) {
          print('🍎 iTunes: No suitable result found');
          return null;
        }

        final previewUrl = bestResult['previewUrl'];

        if (previewUrl != null && previewUrl.toString().isNotEmpty) {
          // HTTPをHTTPSに変換（Mixed Content対策 - モバイルWeb対応）
          final secureUrl = previewUrl.toString().replaceFirst('http://', 'https://');
          print('🍎 iTunes: Found preview URL for "${bestResult['trackName']}" (Collection: ${bestResult['collectionName']})');
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

  /// 検索結果から最適なバージョンを選択
  /// 特別版（Live、Remix、Acoustic等）を除外し、メインバージョンを優先
  Map<String, dynamic>? _selectBestVersion(
    List<dynamic> results,
    String trackName,
    String artistName,
  ) {
    // 除外するキーワード（特別版や一時的な版）
    final excludeKeywords = [
      'live',
      'remix',
      'acoustic',
      'instrumental',
      'karaoke',
      'cover',
      'tribute',
      'version',
      'ver.',
      'remaster',
      'demo',
      'session',
      'edit',
      'mix',
      'deluxe',
      'special',
      'limited',
      'bonus',
      '限定',
      'ライブ',
      'リミックス',
      'アコースティック',
    ];

    // スコアリング: より標準的なバージョンほど高スコア
    final scoredResults = results.map((result) {
      final resultTrackName = (result['trackName'] ?? '').toString().toLowerCase();
      final resultCollectionName = (result['collectionName'] ?? '').toString().toLowerCase();
      final resultArtistName = (result['artistName'] ?? '').toString().toLowerCase();

      int score = 100; // 基本スコア

      // 除外キーワードが含まれている場合はスコアを大幅に減点
      for (final keyword in excludeKeywords) {
        if (resultTrackName.contains(keyword) || resultCollectionName.contains(keyword)) {
          score -= 50;
        }
      }

      // トラック名の類似度でスコア加算
      if (resultTrackName.contains(trackName.toLowerCase())) {
        score += 30;
      }

      // アーティスト名の類似度でスコア加算
      if (resultArtistName.contains(artistName.toLowerCase())) {
        score += 20;
      }

      // プレビューURLがある場合は加点
      if (result['previewUrl'] != null && result['previewUrl'].toString().isNotEmpty) {
        score += 10;
      }

      return {
        'result': result,
        'score': score,
      };
    }).toList();

    // スコアでソート（降順）
    scoredResults.sort((a, b) => (b['score'] as int).compareTo(a['score'] as int));

    // スコアが0以上の最良の結果を返す
    final best = scoredResults.firstWhere(
      (item) => (item['score'] as int) > 0,
      orElse: () => scoredResults.first, // 見つからない場合は最初の結果
    );

    print('🏆 Selected version with score ${best['score']}: ${best['result']['trackName']}');

    return best['result'] as Map<String, dynamic>;
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
      // より多くの結果を取得してフィルタリング
      final url = Uri.parse(
        'https://itunes.apple.com/search?term=$encodedQuery&country=JP&media=music&entity=song&limit=${limit * 2}'
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

        // 特別版を除外したいキーワード
        final excludeKeywords = [
          'live', 'remix', 'acoustic', 'instrumental', 'karaoke',
          'ライブ', 'リミックス', 'アコースティック',
        ];

        // 結果をTrackModelに変換（特別版を優先度低く）
        final trackModels = <TrackModel>[];
        final seenTracks = <String>{};

        for (final result in results) {
          final trackName = result['trackName'] ?? '';
          final artistName = result['artistName'] ?? '';
          final albumImageUrl = result['artworkUrl100'] ?? '';
          final previewUrl = result['previewUrl'] ?? '';
          final collectionName = (result['collectionName'] ?? '').toString().toLowerCase();

          // 重複チェック（同じ曲名+アーティスト名の組み合わせ）
          final trackKey = '${trackName.toLowerCase()}_${artistName.toLowerCase()}';

          // 既に追加済みの曲はスキップ
          if (seenTracks.contains(trackKey)) {
            continue;
          }

          // 特別版は優先度を下げる（後で追加）
          bool isSpecialVersion = false;
          for (final keyword in excludeKeywords) {
            if (trackName.toLowerCase().contains(keyword) ||
                collectionName.contains(keyword)) {
              isSpecialVersion = true;
              break;
            }
          }

          // HTTPをHTTPSに変換（Mixed Content対策 - モバイルWeb対応）
          final securePreviewUrl = previewUrl.isNotEmpty
              ? previewUrl.toString().replaceFirst('http://', 'https://')
              : '';
          // trackIdとしてtrackIdを使用（iTunesのID）
          final trackId = result['trackId']?.toString() ?? '';

          if (trackName.isNotEmpty && !isSpecialVersion) {
            trackModels.add(TrackModel(
              trackId: trackId,
              trackName: trackName,
              artistName: artistName,
              albumImageUrl: albumImageUrl,
              previewUrl: securePreviewUrl,
            ));
            seenTracks.add(trackKey);
            print('🍎 iTunes: Added track "$trackName" by $artistName');
          }

          // 指定された件数に達したら終了
          if (trackModels.length >= limit) {
            break;
          }
        }

        print('🍎 iTunes: Found ${trackModels.length} tracks (filtered from ${results.length})');
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

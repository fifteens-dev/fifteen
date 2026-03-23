import 'dart:convert';
import 'package:http/http.dart' as http;

/// Wikipediaから大学の画像URLを取得するサービス
class WikipediaImageService {
  WikipediaImageService._();

  // メモリキャッシュ（アプリ起動中は再取得しない）
  static final Map<String, String?> _cache = {};

  /// 大学名に対応するWikipediaサムネイルURLを取得
  /// 見つからない場合は null を返す
  static Future<String?> fetchUniversityImageUrl(String universityName) async {
    if (_cache.containsKey(universityName)) {
      return _cache[universityName];
    }

    final url = await _fetchViaMediaWiki(universityName);
    _cache[universityName] = url;
    return url;
  }

  /// MediaWiki API（prop=pageimages）で画像URLを取得
  /// REST summary API より網羅率が高く、全大学で同じ仕様で動作する
  static Future<String?> _fetchViaMediaWiki(String universityName) async {
    try {
      final uri = Uri.parse('https://ja.wikipedia.org/w/api.php').replace(
        queryParameters: {
          'action': 'query',
          'titles': universityName,
          'prop': 'pageimages',
          'format': 'json',
          'pithumbsize': '600',
          'pilicense': 'any',
        },
      );
      final response = await http
          .get(uri, headers: {'Accept': 'application/json'})
          .timeout(const Duration(seconds: 8));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final pages = (data['query']?['pages'] as Map<String, dynamic>?) ?? {};
        for (final page in pages.values) {
          final thumbnail = page['thumbnail'] as Map<String, dynamic>?;
          final url = thumbnail?['source'] as String?;
          if (url != null) return url;
        }
      }
    } catch (_) {}
    return null;
  }
}

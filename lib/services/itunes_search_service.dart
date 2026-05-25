import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/track_model.dart';

/// iTunes Search API サービス
class ITunesSearchService {
  static final ITunesSearchService _instance = ITunesSearchService._internal();
  factory ITunesSearchService() => _instance;
  ITunesSearchService._internal();

  /// 楽曲のプレビューURLとアルバムアートを取得
  ///
  /// Step1: 「曲名 + アーティスト名」で検索
  /// Step2: 曲名のみで検索（アーティスト名フィルターあり）
  /// Step3: サブタイトル除去した曲名 + アーティスト名で再検索
  Future<Map<String, String?>?> getPreviewUrlWithArt({
    required String trackName,
    required String artistName,
  }) async {
    // Step1: 曲名 + アーティスト名で検索
    final result1 = await _searchAndMatch('$trackName $artistName', trackName, artistName: artistName);
    if (result1 != null) return result1;

    // Step2: 曲名のみで検索（アーティスト名フィルターは維持）
    print('🍎 Step2: 曲名のみで検索 "$trackName"');
    final result2 = await _searchAndMatch(trackName, trackName, artistName: artistName);
    if (result2 != null) return result2;

    // Step3: サブタイトル（括弧・バージョン情報等）を除去して再検索
    final baseName = _stripSubtitle(trackName);
    if (baseName != null) {
      print('🍎 Step3: サブタイトル除去して再検索 "$baseName $artistName"');
      return await _searchAndMatch('$baseName $artistName', baseName, artistName: artistName);
    }

    return null;
  }

  /// 括弧・記号で囲まれたサブタイトルを末尾から除去した曲名を返す
  /// サブタイトルが見つからない場合は null を返す
  String? _stripSubtitle(String trackName) {
    final patterns = [
      RegExp(r'\s*[\(（][^\)）]*[\)）]\s*$'),  // (xxx) または （xxx）
      RegExp(r'\s*[\[【][^\]】]*[\]】]\s*$'),   // [xxx] または 【xxx】
      RegExp(r'\s*〜[^〜]+〜\s*$'),             // 〜xxx〜
      RegExp(r'\s*～[^～]+～\s*$'),             // ～xxx～
      RegExp(r'\s+-\s+.+$'),                    // - subtitle
    ];

    for (final pattern in patterns) {
      final cleaned = trackName.replaceFirst(pattern, '').trim();
      if (cleaned.isNotEmpty && cleaned != trackName) {
        print('🍎 サブタイトル除去: "$trackName" → "$cleaned"');
        return cleaned;
      }
    }
    return null;
  }

  /// iTunes を検索し、[trackName] と一致する最初の結果を返す
  Future<Map<String, String?>?> _searchAndMatch(
    String query,
    String trackName, {
    String? artistName,
  }) async {
    try {
      final encodedQuery = Uri.encodeComponent(query);
      final url = Uri.parse(
        'https://itunes.apple.com/search?term=$encodedQuery&country=JP&lang=ja_JP&media=music&entity=song&limit=30'
      );

      print('🍎 iTunes Search API request: $query');
      final response = await http.get(url);

      if (response.statusCode != 200) {
        print('🍎 iTunes Search API error: ${response.statusCode}');
        return null;
      }

      final results = json.decode(response.body)['results'] as List;
      if (results.isEmpty) {
        print('🍎 iTunes: No results found for "$query"');
        return null;
      }

      // 選択した曲名と一致するものだけに絞り込む
      final trackNameLower = trackName.toLowerCase();
      final matches = results.where((r) {
        final name = (r['trackName'] ?? '').toString().toLowerCase();
        return name.contains(trackNameLower);
      }).toList();

      if (matches.isEmpty) {
        print('🍎 iTunes: 曲名一致なし for "$trackName" in "$query" results');
        return null;
      }

      // アーティスト名が一致する候補を優先。一致なければ全候補を使う
      List<dynamic> candidates = matches;
      if (artistName != null && artistName.isNotEmpty) {
        final artistLower = artistName.toLowerCase();
        final artistMatches = matches.where((r) {
          final artist = (r['artistName'] ?? '').toString().toLowerCase();
          return artist.contains(artistLower);
        }).toList();
        if (artistMatches.isNotEmpty) candidates = artistMatches;
      }

      // 候補からプレビューURLを持つ最初のものを選ぶ
      final best = candidates.firstWhere(
        (r) => r['previewUrl'] != null && r['previewUrl'].toString().isNotEmpty,
        orElse: () => candidates.first,
      );

      print('✅ iTunes: "${best['trackName']}" を選択');

      final previewUrl = best['previewUrl']?.toString();
      final artLarge = best['artworkUrl600']?.toString();
      final artSmall = best['artworkUrl100']?.toString();
      final albumArtUrl = (artLarge?.isNotEmpty == true ? artLarge : artSmall);

      return {
        'previewUrl': previewUrl?.replaceFirst('http://', 'https://'),
        'albumArtUrl': albumArtUrl?.replaceFirst('http://', 'https://'),
      };
    } catch (e) {
      print('🍎 iTunes Search API exception: $e');
      return null;
    }
  }

  /// 楽曲のプレビューURLのみを取得（後方互換性のため）
  ///
  /// [trackName] 楽曲名
  /// [artistName] アーティスト名
  /// 戻り値: プレビューURL（取得できない場合はnull）
  Future<String?> getPreviewUrl({
    required String trackName,
    required String artistName,
  }) async {
    final result = await getPreviewUrlWithArt(
      trackName: trackName,
      artistName: artistName,
    );
    return result?['previewUrl'];
  }

  /// アーティスト名でiTunes artistIdを検索
  Future<({int artistId, String artistName})?> searchArtistInfo(
      String artistName) async {
    try {
      final encoded = Uri.encodeComponent(artistName);
      final url = Uri.parse(
        'https://itunes.apple.com/search?term=$encoded&country=JP&media=music&entity=musicArtist&limit=5',
      );
      final response = await http.get(url).timeout(const Duration(seconds: 8));
      if (response.statusCode != 200) return null;
      final results =
          (json.decode(response.body)['results'] as List?) ?? [];
      for (final r in results) {
        if (r['wrapperType'] == 'artist') {
          final id = r['artistId'] as int?;
          final name = r['artistName'] as String?;
          if (id != null && name != null) {
            return (artistId: id, artistName: name);
          }
        }
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  /// iTunes の artworkUrl を 600×600 高解像度 URL に変換
  static String _toHiResArtwork(String url) {
    if (url.isEmpty) return url;
    // 末尾の "{n}x{n}bb" パターンを 600x600bb に置換
    return url.replaceFirstMapped(
      RegExp(r'\d+x\d+bb(\.(jpg|png))$'),
      (m) => '600x600bb${m[1] ?? '.jpg'}',
    );
  }

  /// iTunes artistId からアーティストの楽曲一覧を取得（最新リリース順）
  Future<List<TrackModel>> getArtistTracks(int itunesArtistId,
      {int limit = 100}) async {
    try {
      final url = Uri.parse(
        'https://itunes.apple.com/lookup?id=$itunesArtistId&entity=song&limit=$limit&country=JP&lang=ja_JP',
      );
      final response =
          await http.get(url).timeout(const Duration(seconds: 10));
      if (response.statusCode != 200) return [];
      final results =
          (json.decode(response.body)['results'] as List?) ?? [];

      // track のみ抽出して releaseDate 降順にソート
      final songResults = results
          .whereType<Map<String, dynamic>>()
          .where((r) => r['wrapperType'] == 'track')
          .toList()
        ..sort((a, b) {
          final da = DateTime.tryParse(
                  (a['releaseDate'] as String?) ?? '') ??
              DateTime(0);
          final db = DateTime.tryParse(
                  (b['releaseDate'] as String?) ?? '') ??
              DateTime(0);
          return db.compareTo(da); // 降順
        });

      final tracks = <TrackModel>[];
      final seen = <String>{};
      for (final r in songResults) {
        final id = r['trackId']?.toString() ?? '';
        final name = (r['trackName'] as String?) ?? '';
        final artist = (r['artistName'] as String?) ?? '';
        var art = (r['artworkUrl100'] as String?) ?? '';
        if (art.startsWith('http://')) art = 'https://${art.substring(7)}';
        art = _toHiResArtwork(art);
        var preview = (r['previewUrl'] as String?) ?? '';
        if (preview.startsWith('http://')) {
          preview = 'https://${preview.substring(7)}';
        }
        if (name.isEmpty) continue;
        final key = '${name.toLowerCase()}_${artist.toLowerCase()}';
        if (seen.contains(key)) continue;
        seen.add(key);
        tracks.add(TrackModel(
          trackId: id,
          trackName: name,
          artistName: artist,
          albumImageUrl: art,
          previewUrl: preview.isEmpty ? null : preview,
        ));
      }
      return tracks;
    } catch (_) {
      return [];
    }
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
        'https://itunes.apple.com/search?term=$encodedQuery&country=JP&lang=ja_JP&media=music&entity=song&limit=${limit * 2}'
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

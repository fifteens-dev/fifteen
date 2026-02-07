import 'package:flutter/foundation.dart';

/// トラックのフィルタリングとスコアリングを行うサービス
///
/// 検索結果からオリジナル版を優先するためのスコアリングアルゴリズムを提供。
/// SpotifyService、ITunesSearchServiceなどで共通利用可能。
class TrackFilteringService {
  // シングルトンパターン
  static final TrackFilteringService _instance = TrackFilteringService._internal();
  factory TrackFilteringService() => _instance;
  TrackFilteringService._internal();

  /// 除外するキーワード（カバー版や特別版）
  static const List<String> excludeKeywords = [
    'cover',
    'tribute',
    'karaoke',
    'instrumental',
    'remix',
    'live',
    'acoustic',
    'version',
    'edit',
    'カバー',
    'ライブ',
    'リミックス',
    'アコースティック',
    'ver.',
    'Ver.',
    'feat.',
  ];

  /// スコアリング設定
  static const int baseScore = 100;
  static const int excludeKeywordPenalty = 50;
  static const int bracketPenalty = 20;
  static const int longNamePenalty = 10;
  static const int doubleLengthPenalty = 30;
  static const int oneAndHalfLengthPenalty = 15;
  static const int exactMatchBonus = 50;
  static const int wordMatchBonus = 30;
  static const int containsMatchBonus = 20;
  static const int trackNameMatchBonus = 30;
  static const int artistNameMatchBonus = 20;
  static const int previewUrlBonus = 10;

  /// トラック検索結果をスコアリング
  ///
  /// [trackName] トラック名
  /// [artistName] アーティスト名（オプション）
  /// [albumName] アルバム名（オプション）
  /// [popularity] 人気度（0-100、オプション）
  /// [hasPreviewUrl] プレビューURLがあるか
  /// [searchQuery] 検索クエリ
  ///
  /// 戻り値: スコア（高いほど良い）
  int calculateScore({
    required String trackName,
    String? artistName,
    String? albumName,
    int? popularity,
    bool hasPreviewUrl = false,
    required String searchQuery,
  }) {
    final trackNameLower = trackName.toLowerCase();
    final albumNameLower = albumName?.toLowerCase() ?? '';
    final artistNameLower = artistName?.toLowerCase() ?? '';
    final queryLower = searchQuery.toLowerCase();

    int score = baseScore;

    // 除外キーワードが含まれている場合は大幅減点
    for (final keyword in excludeKeywords) {
      if (trackNameLower.contains(keyword) || albumNameLower.contains(keyword)) {
        score -= excludeKeywordPenalty;
      }
    }

    // 括弧が含まれる場合は減点（余計な情報が含まれている可能性）
    if (_hasBrackets(trackNameLower)) {
      score -= bracketPenalty;
    }

    // トラック名が長すぎる場合は減点
    if (trackName.length > 50) {
      score -= longNamePenalty;
    }

    // 検索クエリと比較した長さによる減点
    final queryLength = searchQuery.length;
    final trackNameLength = trackName.length;

    if (trackNameLength > queryLength * 2) {
      score -= doubleLengthPenalty;
    } else if (trackNameLength > queryLength * 1.5) {
      score -= oneAndHalfLengthPenalty;
    }

    // 人気度による加点（0-10点の範囲）
    if (popularity != null) {
      score += (popularity / 10).round();
    }

    // 検索クエリとの関連性スコア
    score += _calculateRelevanceScore(trackNameLower, artistNameLower, queryLower);

    // トラック名の一致による加点
    if (trackNameLower.contains(queryLower) || queryLower.contains(trackNameLower)) {
      score += trackNameMatchBonus;
    }

    // アーティスト名の一致による加点
    if (artistNameLower.isNotEmpty && queryLower.contains(artistNameLower)) {
      score += artistNameMatchBonus;
    }

    // プレビューURLがある場合は加点
    if (hasPreviewUrl) {
      score += previewUrlBonus;
    }

    return score;
  }

  /// 括弧が含まれているか確認
  bool _hasBrackets(String text) {
    return text.contains('(') ||
        text.contains('[') ||
        text.contains('（') ||
        text.contains('【');
  }

  /// 検索クエリとの関連性スコアを計算
  int _calculateRelevanceScore(String trackName, String artistName, String query) {
    // 完全一致
    if (trackName == query) {
      return exactMatchBonus;
    }

    // 単語単位での一致確認
    final queryWords = query.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
    final trackWords = trackName.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();

    int matchedWords = 0;
    for (final word in queryWords) {
      if (trackWords.any((tw) => tw.contains(word) || word.contains(tw))) {
        matchedWords++;
      }
    }

    if (matchedWords == queryWords.length && queryWords.isNotEmpty) {
      return wordMatchBonus;
    }

    // 部分一致
    if (trackName.contains(query) || query.contains(trackName)) {
      return containsMatchBonus;
    }

    return 0;
  }

  /// トラック名を正規化（グループ化用）
  ///
  /// 括弧内の情報を除去し、小文字に変換
  String normalizeTrackName(String trackName) {
    String normalized = trackName;

    // 各種括弧とその中身を削除
    normalized = normalized.replaceAll(RegExp(r'\([^)]*\)'), '');
    normalized = normalized.replaceAll(RegExp(r'\[[^\]]*\]'), '');
    normalized = normalized.replaceAll(RegExp(r'（[^）]*）'), '');
    normalized = normalized.replaceAll(RegExp(r'【[^】]*】'), '');

    // 余分なスペースを削除
    normalized = normalized.replaceAll(RegExp(r'\s+'), ' ').trim();

    return normalized.toLowerCase();
  }

  /// スコア付きトラックリストをフィルタリング
  ///
  /// 同じ楽曲名の重複を排除し、最もスコアの高いバージョンを選択
  List<T> filterDuplicates<T>({
    required List<T> tracks,
    required String Function(T) getTrackName,
    required int Function(T) getScore,
    bool debug = false,
  }) {
    // トラック名でグループ化
    final Map<String, List<T>> groupedTracks = {};

    for (final track in tracks) {
      final normalizedName = normalizeTrackName(getTrackName(track));
      groupedTracks.putIfAbsent(normalizedName, () => []);
      groupedTracks[normalizedName]!.add(track);
    }

    // 各グループから最もスコアの高いものを選択
    final List<T> bestVersions = [];

    for (final entry in groupedTracks.entries) {
      final versions = entry.value;
      versions.sort((a, b) => getScore(b).compareTo(getScore(a)));

      final bestVersion = versions.first;
      bestVersions.add(bestVersion);

      if (debug && kDebugMode) {
        print('\n📊 Group: "${entry.key}" (${versions.length} versions)');
        for (int i = 0; i < versions.length && i < 3; i++) {
          final v = versions[i];
          final marker = i == 0 ? '✅' : '  ';
          print('   $marker "${getTrackName(v)}" - Score: ${getScore(v)}');
        }
      }
    }

    // スコアでソート
    bestVersions.sort((a, b) => getScore(b).compareTo(getScore(a)));

    return bestVersions;
  }

  /// スコアが閾値以上のトラックのみをフィルタリング
  List<T> filterByMinScore<T>({
    required List<T> tracks,
    required int Function(T) getScore,
    int minScore = 0,
  }) {
    return tracks.where((t) => getScore(t) >= minScore).toList();
  }
}

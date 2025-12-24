import 'track_model.dart';

/// Vibeランキングアイテムを表すモデル
class VibeRankingItem {
  final int rank; // ランク順位（1位、2位、3位...）
  final TrackModel track; // 楽曲情報
  final int postCount; // この楽曲が投稿された回数
  final List<String> userIds; // 投稿したユーザーIDの一覧

  VibeRankingItem({
    required this.rank,
    required this.track,
    required this.postCount,
    this.userIds = const [],
  });

  // Mapから作成
  factory VibeRankingItem.fromMap(Map<String, dynamic> map) {
    return VibeRankingItem(
      rank: map['rank'] ?? 0,
      track: TrackModel.fromMap(map['track'] ?? {}),
      postCount: map['postCount'] ?? 0,
      userIds: List<String>.from(map['userIds'] ?? []),
    );
  }

  // Mapに変換
  Map<String, dynamic> toMap() {
    return {
      'rank': rank,
      'track': track.toMap(),
      'postCount': postCount,
      'userIds': userIds,
    };
  }

  // コピーを作成（一部のフィールドを更新）
  VibeRankingItem copyWith({
    int? rank,
    TrackModel? track,
    int? postCount,
    List<String>? userIds,
  }) {
    return VibeRankingItem(
      rank: rank ?? this.rank,
      track: track ?? this.track,
      postCount: postCount ?? this.postCount,
      userIds: userIds ?? this.userIds,
    );
  }
}

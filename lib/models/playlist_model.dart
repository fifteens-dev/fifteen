import 'package:cloud_firestore/cloud_firestore.dart';

/// ユーザーが作成するプレイリスト（自分の投稿を集めたもの）。
class PlaylistModel {
  final String id;
  final String userId;
  final String name;

  /// カバー画像URL（選択した投稿の写真/ジャケットから採用）。
  final String coverImageUrl;

  /// 収録した投稿IDリスト（＝プレイリストに入れた曲）。
  final List<String> postIds;

  /// 曲数（= postIds.length）。
  final int trackCount;

  final DateTime createdAt;
  final DateTime updatedAt;

  const PlaylistModel({
    required this.id,
    required this.userId,
    required this.name,
    this.coverImageUrl = '',
    this.postIds = const [],
    this.trackCount = 0,
    required this.createdAt,
    required this.updatedAt,
  });

  factory PlaylistModel.fromFirestore(DocumentSnapshot doc) {
    final data = (doc.data() as Map<String, dynamic>?) ?? {};
    DateTime ts(String key) {
      final v = data[key];
      return v is Timestamp ? v.toDate() : DateTime.now();
    }

    final ids =
        (data['postIds'] as List<dynamic>? ?? []).whereType<String>().toList();
    return PlaylistModel(
      id: doc.id,
      userId: data['userId']?.toString() ?? '',
      name: data['name']?.toString() ?? '',
      coverImageUrl: data['coverImageUrl']?.toString() ?? '',
      postIds: ids,
      trackCount: (data['trackCount'] as num?)?.toInt() ?? ids.length,
      createdAt: ts('createdAt'),
      updatedAt: ts('updatedAt'),
    );
  }

  Map<String, dynamic> toMap() => {
        'userId': userId,
        'name': name,
        'coverImageUrl': coverImageUrl,
        'postIds': postIds,
        'trackCount': trackCount,
        'createdAt': Timestamp.fromDate(createdAt),
        'updatedAt': Timestamp.fromDate(updatedAt),
      };
}

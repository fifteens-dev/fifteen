import 'package:cloud_firestore/cloud_firestore.dart';
import 'track_model.dart';
import 'post_theme.dart';

/// 投稿情報を表すモデル
class PostModel {
  final String postId;
  final String userId;
  final String username;
  final String? userIconUrl;
  final TrackModel track;
  final int likeCount;
  final int commentCount;
  final List<String> likedUserIds; // いいねしたユーザーのIDリスト
  final DateTime createdAt;
  final DateTime updatedAt;
  final PostTheme theme; // カラーテーマ

  PostModel({
    required this.postId,
    required this.userId,
    required this.username,
    this.userIconUrl,
    required this.track,
    this.likeCount = 0,
    this.commentCount = 0,
    this.likedUserIds = const [],
    required this.createdAt,
    required this.updatedAt,
    this.theme = PostTheme.defaultTheme,
  });

  // Firestoreドキュメントから作成
  factory PostModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;

    return PostModel(
      postId: doc.id,
      userId: data['userId'] ?? '',
      username: data['username'] ?? '',
      userIconUrl: data['userIconUrl'],
      track: TrackModel.fromMap(data['track'] ?? {}),
      likeCount: data['likeCount'] ?? 0,
      commentCount: data['commentCount'] ?? 0,
      likedUserIds: List<String>.from(data['likedUserIds'] ?? []),
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      updatedAt: (data['updatedAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      theme: data['theme'] != null
          ? PostTheme.fromMap(data['theme'] as Map<String, dynamic>)
          : PostTheme.defaultTheme,
    );
  }

  // Firestoreに保存する形式に変換
  Map<String, dynamic> toMap() {
    return {
      'userId': userId,
      'username': username,
      'userIconUrl': userIconUrl,
      'track': track.toMap(),
      'likeCount': likeCount,
      'commentCount': commentCount,
      'likedUserIds': likedUserIds,
      'createdAt': Timestamp.fromDate(createdAt),
      'updatedAt': Timestamp.fromDate(updatedAt),
      'theme': theme.toMap(),
    };
  }

  // コピーを作成（一部のフィールドを更新）
  PostModel copyWith({
    String? postId,
    String? userId,
    String? username,
    String? userIconUrl,
    TrackModel? track,
    int? likeCount,
    int? commentCount,
    List<String>? likedUserIds,
    DateTime? createdAt,
    DateTime? updatedAt,
    PostTheme? theme,
  }) {
    return PostModel(
      postId: postId ?? this.postId,
      userId: userId ?? this.userId,
      username: username ?? this.username,
      userIconUrl: userIconUrl ?? this.userIconUrl,
      track: track ?? this.track,
      likeCount: likeCount ?? this.likeCount,
      commentCount: commentCount ?? this.commentCount,
      likedUserIds: likedUserIds ?? this.likedUserIds,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      theme: theme ?? this.theme,
    );
  }

  // いいねを追加
  PostModel toggleLike(String userId) {
    final isLiked = likedUserIds.contains(userId);
    final newLikedUserIds = List<String>.from(likedUserIds);

    if (isLiked) {
      newLikedUserIds.remove(userId);
    } else {
      newLikedUserIds.add(userId);
    }

    return copyWith(
      likedUserIds: newLikedUserIds,
      likeCount: newLikedUserIds.length,
      updatedAt: DateTime.now(),
    );
  }

  // いいねしているかチェック
  bool isLikedBy(String userId) {
    return likedUserIds.contains(userId);
  }
}

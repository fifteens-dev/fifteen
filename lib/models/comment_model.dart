import 'package:cloud_firestore/cloud_firestore.dart';

/// コメント情報を表すモデル
class CommentModel {
  final String commentId;
  final String postId;
  final String userId;
  final String username;
  final String? userIconUrl;
  final String content;
  final DateTime createdAt;
  final DateTime updatedAt;

  CommentModel({
    required this.commentId,
    required this.postId,
    required this.userId,
    required this.username,
    this.userIconUrl,
    required this.content,
    required this.createdAt,
    required this.updatedAt,
  });

  /// Firestoreドキュメントから作成
  factory CommentModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;

    return CommentModel(
      commentId: doc.id,
      postId: data['postId'] ?? '',
      userId: data['userId'] ?? '',
      username: data['username'] ?? '',
      userIconUrl: data['userIconUrl'],
      content: data['content'] ?? '',
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      updatedAt: (data['updatedAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  /// Firestoreに保存する形式に変換
  Map<String, dynamic> toMap() {
    return {
      'postId': postId,
      'userId': userId,
      'username': username,
      'userIconUrl': userIconUrl,
      'content': content,
      'createdAt': Timestamp.fromDate(createdAt),
      'updatedAt': Timestamp.fromDate(updatedAt),
    };
  }

  /// コピーを作成（一部のフィールドを更新）
  CommentModel copyWith({
    String? commentId,
    String? postId,
    String? userId,
    String? username,
    String? userIconUrl,
    String? content,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return CommentModel(
      commentId: commentId ?? this.commentId,
      postId: postId ?? this.postId,
      userId: userId ?? this.userId,
      username: username ?? this.username,
      userIconUrl: userIconUrl ?? this.userIconUrl,
      content: content ?? this.content,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import '../models/comment_model.dart';
import '../models/notification_model.dart';
import 'notification_service.dart';
import 'post_service.dart';
import 'user_service.dart';

/// コメント管理サービス
class CommentService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final NotificationService _notificationService = NotificationService();
  final PostService _postService = PostService();
  final UserService _userService = UserService();

  /// コメントを作成
  Future<void> createComment({
    required String postId,
    required String userId,
    required String username,
    String? userIconUrl,
    required String content,
  }) async {
    try {
      final comment = CommentModel(
        commentId: '', // Firestoreが自動生成
        postId: postId,
        userId: userId,
        username: username,
        userIconUrl: userIconUrl,
        content: content,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      // コメントを保存
      await _firestore.collection('comments').add(comment.toMap());

      // 投稿のコメント数を更新
      await _incrementCommentCount(postId);

      // 投稿情報を取得して通知を作成
      final post = await _postService.getPost(postId);
      if (post != null) {
        // コメントテキストを50文字に制限
        final truncatedComment = content.length > 50
            ? '${content.substring(0, 50)}...'
            : content;

        await _notificationService.createNotification(
          type: NotificationType.comment,
          recipientId: post.userId,
          senderId: userId,
          senderUsername: username,
          senderIconUrl: userIconUrl,
          postId: postId,
          albumArtUrl: post.track.albumImageUrl,
          trackName: post.track.trackName,
          commentText: truncatedComment,
        );

        if (kDebugMode) {
          print('✅ コメント通知作成: postId=$postId, recipient=${post.userId}');
        }

        // @メンション検出・通知
        await _processMentions(
          content: content,
          postId: postId,
          senderId: userId,
          senderUsername: username,
          senderIconUrl: userIconUrl,
          postOwnerId: post.userId,
          albumArtUrl: post.track.albumImageUrl,
          trackName: post.track.trackName,
        );
      }
    } catch (e) {
      throw Exception('コメントの作成に失敗しました: $e');
    }
  }

  /// コメント内の@メンションを検出し通知を送信
  Future<void> _processMentions({
    required String content,
    required String postId,
    required String senderId,
    required String senderUsername,
    String? senderIconUrl,
    required String postOwnerId,
    String? albumArtUrl,
    String? trackName,
  }) async {
    // @username を抽出（英数字・アンダースコア・ドット）
    final mentionRegex = RegExp(r'@([a-zA-Z0-9_][a-zA-Z0-9_.]*[a-zA-Z0-9_]|[a-zA-Z0-9_])');
    final matches = mentionRegex.allMatches(content);
    if (matches.isEmpty) return;

    final mentionedUsernames = matches.map((m) => m.group(1)!).toSet();

    for (final username in mentionedUsernames) {
      try {
        // usernameからユーザーを検索
        final users = await _userService.searchUsers(query: username, limit: 5);
        final target = users.where((u) => u.username == username).firstOrNull;
        if (target == null) continue;

        // 自分自身・投稿者へのメンションは通知しない（投稿者はコメント通知で受け取る）
        if (target.uid == senderId) continue;

        await _notificationService.createNotification(
          type: NotificationType.mention,
          recipientId: target.uid,
          senderId: senderId,
          senderUsername: senderUsername,
          senderIconUrl: senderIconUrl,
          postId: postId,
          albumArtUrl: albumArtUrl,
          trackName: trackName,
          commentText: content.length > 50 ? '${content.substring(0, 50)}...' : content,
        );

        if (kDebugMode) {
          print('✅ メンション通知: @$username → ${target.uid}');
        }
      } catch (e) {
        if (kDebugMode) print('メンション通知エラー (@$username): $e');
      }
    }
  }

  /// 投稿のコメント数をインクリメント
  Future<void> _incrementCommentCount(String postId) async {
    try {
      final postRef = _firestore.collection('posts').doc(postId);
      await postRef.update({
        'commentCount': FieldValue.increment(1),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      print('コメント数の更新に失敗しました: $e');
    }
  }

  /// 投稿のコメント数をデクリメント
  Future<void> _decrementCommentCount(String postId) async {
    try {
      final postRef = _firestore.collection('posts').doc(postId);
      await postRef.update({
        'commentCount': FieldValue.increment(-1),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      print('コメント数の更新に失敗しました: $e');
    }
  }

  /// コメントを削除
  Future<void> deleteComment(String commentId, String postId) async {
    try {
      await _firestore.collection('comments').doc(commentId).delete();

      // 投稿のコメント数を更新
      await _decrementCommentCount(postId);
    } catch (e) {
      throw Exception('コメントの削除に失敗しました: $e');
    }
  }

  /// 特定の投稿のコメント一覧を取得（リアルタイム）
  Stream<List<CommentModel>> getCommentsStream(String postId) {
    return _firestore
        .collection('comments')
        .where('postId', isEqualTo: postId)
        .orderBy('createdAt', descending: false)
        .snapshots()
        .map((snapshot) {
      return snapshot.docs
          .map((doc) => CommentModel.fromFirestore(doc))
          .toList();
    });
  }

  /// 特定の投稿のコメント一覧を取得（一度だけ）
  Future<List<CommentModel>> getComments(String postId) async {
    try {
      final snapshot = await _firestore
          .collection('comments')
          .where('postId', isEqualTo: postId)
          .orderBy('createdAt', descending: false)
          .get();

      return snapshot.docs
          .map((doc) => CommentModel.fromFirestore(doc))
          .toList();
    } catch (e) {
      throw Exception('コメントの取得に失敗しました: $e');
    }
  }

  /// コメントを更新
  Future<void> updateComment({
    required String commentId,
    required String content,
  }) async {
    try {
      await _firestore.collection('comments').doc(commentId).update({
        'content': content,
        'updatedAt': Timestamp.fromDate(DateTime.now()),
      });
    } catch (e) {
      throw Exception('コメントの更新に失敗しました: $e');
    }
  }
}

import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/comment_model.dart';

/// コメント管理サービス
class CommentService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

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
    } catch (e) {
      throw Exception('コメントの作成に失敗しました: $e');
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

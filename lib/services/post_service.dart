import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import '../models/post_model.dart';

/// 投稿データを管理するサービス
class PostService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final String _postsCollection = 'posts';

  /// 投稿を作成
  Future<String> createPost({
    required String userId,
    required String username,
    String? userIconUrl,
    required Map<String, dynamic> trackData,
    String? photoUrl,
    int selectedLayoutIndex = 0,
    double cardPositionX = 0.0,
    double cardPositionY = 0.0,
  }) async {
    try {
      final postRef = _firestore.collection(_postsCollection).doc();

      final postData = {
        'userId': userId,
        'username': username,
        'userIconUrl': userIconUrl,
        'track': trackData,
        'likeCount': 0,
        'commentCount': 0,
        'likedUserIds': [],
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
        'photoUrl': photoUrl,
        'selectedLayoutIndex': selectedLayoutIndex,
        'cardPositionX': cardPositionX,
        'cardPositionY': cardPositionY,
      };

      await postRef.set(postData);
      return postRef.id;
    } catch (e) {
      if (kDebugMode) {
        print('Error creating post: $e');
      }
      rethrow;
    }
  }

  /// 投稿を取得（ページネーション付き）
  Future<List<PostModel>> getPosts({
    int limit = 20,
    DocumentSnapshot? startAfter,
  }) async {
    try {
      Query query = _firestore
          .collection(_postsCollection)
          .orderBy('createdAt', descending: true)
          .limit(limit);

      if (startAfter != null) {
        query = query.startAfterDocument(startAfter);
      }

      final snapshot = await query.get();
      return snapshot.docs
          .map((doc) => PostModel.fromFirestore(doc))
          .toList();
    } catch (e) {
      if (kDebugMode) {
        print('Error getting posts: $e');
      }
      return [];
    }
  }

  /// 投稿のリアルタイムストリームを取得
  ///
  /// このメソッドはFirestoreのsnapshotsを使用して、リアルタイムで投稿データを取得します。
  /// 他のユーザーがいいねを押したり、新しい投稿を作成した場合、
  /// 自動的にStreamが更新され、すべてのクライアントに変更が反映されます。
  ///
  /// [limit] 取得する投稿の最大数（デフォルト: 20）
  ///
  /// 使用例：
  /// ```dart
  /// StreamBuilder<List<PostModel>>(
  ///   stream: postService.getPostsStream(limit: 20),
  ///   builder: (context, snapshot) {
  ///     // UIを構築
  ///   },
  /// )
  /// ```
  Stream<List<PostModel>> getPostsStream({int limit = 20}) {
    return _firestore
        .collection(_postsCollection)
        .orderBy('createdAt', descending: true)
        .limit(limit)
        .snapshots() // リアルタイム更新を受信
        .map((snapshot) {
      return snapshot.docs
          .map((doc) => PostModel.fromFirestore(doc))
          .toList();
    });
  }

  /// 特定のユーザーの投稿を取得（Future版）
  Future<List<PostModel>> getPostsByUserId(String userId, {int limit = 20}) async {
    try {
      final snapshot = await _firestore
          .collection(_postsCollection)
          .where('userId', isEqualTo: userId)
          .orderBy('createdAt', descending: true)
          .limit(limit)
          .get();

      return snapshot.docs
          .map((doc) => PostModel.fromFirestore(doc))
          .toList();
    } catch (e) {
      if (kDebugMode) {
        print('Error getting posts by userId: $e');
      }
      return [];
    }
  }

  /// 特定のユーザーの投稿を取得（Stream版）
  Stream<List<PostModel>> getUserPostsStream(String userId, {int limit = 20}) {
    return _firestore
        .collection(_postsCollection)
        .where('userId', isEqualTo: userId)
        .orderBy('createdAt', descending: true)
        .limit(limit)
        .snapshots()
        .map((snapshot) {
      return snapshot.docs
          .map((doc) => PostModel.fromFirestore(doc))
          .toList();
    });
  }

  /// いいねをトグル（追加/削除）
  Future<void> toggleLike({
    required String postId,
    required String userId,
  }) async {
    try {
      final postRef = _firestore.collection(_postsCollection).doc(postId);

      await _firestore.runTransaction((transaction) async {
        final postDoc = await transaction.get(postRef);

        if (!postDoc.exists) {
          throw Exception('Post not found');
        }

        final data = postDoc.data()!;
        final likedUserIds = List<String>.from(data['likedUserIds'] ?? []);
        final isLiked = likedUserIds.contains(userId);

        if (isLiked) {
          // いいねを削除
          likedUserIds.remove(userId);
        } else {
          // いいねを追加
          likedUserIds.add(userId);
        }

        transaction.update(postRef, {
          'likedUserIds': likedUserIds,
          'likeCount': likedUserIds.length,
          'updatedAt': FieldValue.serverTimestamp(),
        });
      });
    } catch (e) {
      if (kDebugMode) {
        print('Error toggling like: $e');
      }
      rethrow;
    }
  }

  /// コメント数を更新
  Future<void> updateCommentCount(String postId, int commentCount) async {
    try {
      await _firestore.collection(_postsCollection).doc(postId).update({
        'commentCount': commentCount,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      if (kDebugMode) {
        print('Error updating comment count: $e');
      }
      rethrow;
    }
  }

  /// 投稿を削除
  Future<void> deletePost(String postId) async {
    try {
      await _firestore.collection(_postsCollection).doc(postId).delete();
    } catch (e) {
      if (kDebugMode) {
        print('Error deleting post: $e');
      }
      rethrow;
    }
  }

  /// 特定の投稿を取得
  Future<PostModel?> getPost(String postId) async {
    try {
      final doc = await _firestore.collection(_postsCollection).doc(postId).get();

      if (doc.exists) {
        return PostModel.fromFirestore(doc);
      }
      return null;
    } catch (e) {
      if (kDebugMode) {
        print('Error getting post: $e');
      }
      return null;
    }
  }

  /// 投稿のストリームを取得
  Stream<PostModel?> getPostStream(String postId) {
    return _firestore
        .collection(_postsCollection)
        .doc(postId)
        .snapshots()
        .map((doc) {
      if (doc.exists) {
        return PostModel.fromFirestore(doc);
      }
      return null;
    });
  }

  /// 特定ユーザーの今日の投稿を取得
  Future<List<PostModel>> getTodaysPosts(String userId) async {
    try {
      // 今日の0時0分0秒
      final now = DateTime.now();
      final startOfDay = DateTime(now.year, now.month, now.day);
      // 今日の23時59分59秒
      final endOfDay = DateTime(now.year, now.month, now.day, 23, 59, 59);

      final snapshot = await _firestore
          .collection(_postsCollection)
          .where('userId', isEqualTo: userId)
          .where('createdAt', isGreaterThanOrEqualTo: Timestamp.fromDate(startOfDay))
          .where('createdAt', isLessThanOrEqualTo: Timestamp.fromDate(endOfDay))
          .orderBy('createdAt', descending: true)
          .get();

      return snapshot.docs
          .map((doc) => PostModel.fromFirestore(doc))
          .toList();
    } catch (e) {
      if (kDebugMode) {
        print('Error getting today\'s posts: $e');
      }
      return [];
    }
  }

  /// 特定ユーザーの今日以外の投稿を取得
  Future<List<PostModel>> getPostsExcludingToday(String userId, {int limit = 20}) async {
    try {
      // 今日の0時0分0秒
      final now = DateTime.now();
      final startOfDay = DateTime(now.year, now.month, now.day);

      final snapshot = await _firestore
          .collection(_postsCollection)
          .where('userId', isEqualTo: userId)
          .where('createdAt', isLessThan: Timestamp.fromDate(startOfDay))
          .orderBy('createdAt', descending: true)
          .limit(limit)
          .get();

      return snapshot.docs
          .map((doc) => PostModel.fromFirestore(doc))
          .toList();
    } catch (e) {
      if (kDebugMode) {
        print('Error getting posts excluding today: $e');
      }
      return [];
    }
  }
}

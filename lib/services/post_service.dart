import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import '../models/post_model.dart';
import '../models/post_theme.dart';
import '../models/vibe_ranking_item.dart';
import '../models/track_model.dart';
import '../models/notification_model.dart';
import 'notification_service.dart';
import 'user_service.dart';

/// 投稿データを管理するサービス
class PostService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final String _postsCollection = 'posts';
  final NotificationService _notificationService = NotificationService();
  final UserService _userService = UserService();

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
    double cardScale = 1.0,
    double cardRotation = 0.0,
    bool isVibe = false,
    String? vibeTopicId,
    String? vibeTopicTitle,
    String? emotionTag,
    PostTheme? theme, // アルバムアートから抽出した色テーマ
  }) async {
    try {
      final postRef = _firestore.collection(_postsCollection).doc();

      // Vibe投稿の日付（年月日のみ、時刻は00:00:00）
      final now = DateTime.now();
      final vibeDate = isVibe
          ? DateTime(now.year, now.month, now.day)
          : null;

      final postData = {
        'userId': userId,
        'username': username,
        'userIconUrl': userIconUrl,
        'track': trackData,
        'likeCount': 0,
        'commentCount': 0,
        'likedUserIds': [],
        'likedByUserIconUrls': [],
        'savedByUserIds': [],
        'savedByUserIconUrls': [],
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
        'photoUrl': photoUrl,
        'selectedLayoutIndex': selectedLayoutIndex,
        'cardPositionX': cardPositionX,
        'cardPositionY': cardPositionY,
        'cardScale': cardScale,
        'cardRotation': cardRotation,
        'isVibe': isVibe,
        'vibeTopicId': vibeTopicId,
        'vibeTopicTitle': vibeTopicTitle,
        'vibeDate': vibeDate != null ? Timestamp.fromDate(vibeDate) : null,
        'emotionTag': emotionTag,
        'theme': theme != null ? theme.toMap() : null, // 抽出した色テーマを保存
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

  /// 特定のユーザーが保存した投稿を取得
  Future<List<PostModel>> getPostsSavedByUser(String userId, {int limit = 50}) async {
    try {
      // arrayContainsとorderByの組み合わせは複合インデックスが必要なため
      // クライアント側でソートする
      final snapshot = await _firestore
          .collection(_postsCollection)
          .where('savedByUserIds', arrayContains: userId)
          .limit(limit)
          .get();

      // クライアント側でソート
      final posts = snapshot.docs
          .map((doc) => PostModel.fromFirestore(doc))
          .toList();

      posts.sort((a, b) => b.createdAt.compareTo(a.createdAt));

      return posts;
    } catch (e) {
      if (kDebugMode) {
        print('Error getting saved posts by userId: $e');
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

      String? postOwnerId;
      String? postOwnerUsername;
      String? albumArtUrl;
      String? trackName;
      bool wasLiked = false;

      // ユーザー情報を事前に取得（トランザクション外）
      final currentUser = await _userService.getUser(userId);
      final userIconUrl = currentUser?.profileImageUrl ?? '';

      await _firestore.runTransaction((transaction) async {
        final postDoc = await transaction.get(postRef);

        if (!postDoc.exists) {
          throw Exception('Post not found');
        }

        final data = postDoc.data()!;
        final likedUserIds = List<String>.from(data['likedUserIds'] ?? []);
        final likedByUserIconUrls =
            List<String>.from(data['likedByUserIconUrls'] ?? []);
        final isLiked = likedUserIds.contains(userId);

        // いいね追加時のみ投稿者情報を保存（通知用）
        if (!isLiked) {
          postOwnerId = data['userId'];
          postOwnerUsername = data['username'];
          final trackData = data['track'] as Map<String, dynamic>?;
          albumArtUrl = trackData?['albumArtUrl'];
          trackName = trackData?['trackName'];
        }

        wasLiked = isLiked;

        if (isLiked) {
          // いいねを削除
          final index = likedUserIds.indexOf(userId);
          likedUserIds.remove(userId);
          if (index >= 0 && index < likedByUserIconUrls.length) {
            likedByUserIconUrls.removeAt(index);
          }
        } else {
          // いいねを追加
          likedUserIds.add(userId);
          likedByUserIconUrls.add(userIconUrl);
        }

        transaction.update(postRef, {
          'likedUserIds': likedUserIds,
          'likedByUserIconUrls': likedByUserIconUrls,
          'likeCount': likedUserIds.length,
          'updatedAt': FieldValue.serverTimestamp(),
        });
      });

      // トランザクション外で通知を作成（いいね追加時のみ）
      if (!wasLiked && postOwnerId != null) {

        await _notificationService.createNotification(
          type: NotificationType.like,
          recipientId: postOwnerId!,
          senderId: userId,
          senderUsername: currentUser?.username ?? 'Unknown',
          senderIconUrl: currentUser?.profileImageUrl,
          postId: postId,
          albumArtUrl: albumArtUrl,
          trackName: trackName,
        );

        if (kDebugMode) {
          print('✅ いいね通知作成: postId=$postId, recipient=$postOwnerId');
        }
      }
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

  /// 特定のお題のVibe投稿を取得
  Future<List<PostModel>> getVibePostsByTopic(
    String topicId,
    DateTime date,
  ) async {
    try {
      // 日付を正規化（時刻を00:00:00に設定）
      final normalizedDate = DateTime(date.year, date.month, date.day);
      final nextDay = normalizedDate.add(const Duration(days: 1));

      final snapshot = await _firestore
          .collection(_postsCollection)
          .where('isVibe', isEqualTo: true)
          .where('vibeTopicId', isEqualTo: topicId)
          .where('vibeDate', isGreaterThanOrEqualTo: Timestamp.fromDate(normalizedDate))
          .where('vibeDate', isLessThan: Timestamp.fromDate(nextDay))
          .get();

      return snapshot.docs
          .map((doc) => PostModel.fromFirestore(doc))
          .toList();
    } catch (e) {
      if (kDebugMode) {
        print('Error getting vibe posts by topic: $e');
      }
      return [];
    }
  }

  /// ランキング計算（投稿数でグループ化＆ソート）
  Future<List<VibeRankingItem>> calculateVibeRanking(
    String topicId,
    DateTime date, {
    int limit = 10,
  }) async {
    try {
      // Vibe投稿を取得
      final vibePosts = await getVibePostsByTopic(topicId, date);

      if (vibePosts.isEmpty) {
        return [];
      }

      // trackId（またはtrackName + artistName）でグループ化
      final Map<String, List<PostModel>> groupedPosts = {};

      for (final post in vibePosts) {
        // trackIdがある場合はtrackIdを使用、ない場合はtrackName + artistNameを使用
        final trackKey = post.track.trackId.isNotEmpty
            ? post.track.trackId
            : '${post.track.trackName}_${post.track.artistName}';

        if (!groupedPosts.containsKey(trackKey)) {
          groupedPosts[trackKey] = [];
        }
        groupedPosts[trackKey]!.add(post);
      }

      // 各グループの投稿数をカウント＆ソート
      final List<Map<String, dynamic>> rankingData = [];

      for (final entry in groupedPosts.entries) {
        final posts = entry.value;
        final postCount = posts.length;
        final userIds = posts.map((p) => p.userId).toList();

        // 代表的なトラック情報を使用（最初の投稿のトラック）
        final representativeTrack = posts.first.track;

        rankingData.add({
          'track': representativeTrack,
          'postCount': postCount,
          'userIds': userIds,
        });
      }

      // 投稿数の降順でソート
      rankingData.sort((a, b) => (b['postCount'] as int).compareTo(a['postCount'] as int));

      // 上位limit件をVibeRankingItemに変換
      final List<VibeRankingItem> ranking = [];
      for (int i = 0; i < rankingData.length && i < limit; i++) {
        final data = rankingData[i];
        ranking.add(VibeRankingItem(
          rank: i + 1,
          track: data['track'] as TrackModel,
          postCount: data['postCount'] as int,
          userIds: List<String>.from(data['userIds']),
        ));
      }

      return ranking;
    } catch (e) {
      if (kDebugMode) {
        print('Error calculating vibe ranking: $e');
      }
      return [];
    }
  }

}

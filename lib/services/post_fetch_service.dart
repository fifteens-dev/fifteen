import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import '../models/post_model.dart';
import 'user_service.dart';

/// 投稿データの取得を担当するサービス
class PostFetchService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final String _postsCollection = 'posts';
  final UserService _userService = UserService();

  // ユーザー情報のインメモリキャッシュ（TTL: 30分）
  // PostService の static キャッシュを共有するため、外部から渡すか同じ参照を持つ
  static final Map<String, ({String? username, String? iconUrl, DateTime fetchedAt})> _userInfoCache = {};
  static const Duration _userCacheTtl = Duration(minutes: 30);

  /// 投稿リストのユーザー名・アイコンを最新のプロフィール情報で更新
  Future<List<PostModel>> applyLatestUserInfo(List<PostModel> posts) async {
    if (posts.isEmpty) return posts;

    // 投稿者 + いいねユーザー全員のIDを収集
    final allUserIds = <String>{};
    for (final post in posts) {
      allUserIds.add(post.userId);
      allUserIds.addAll(post.likedUserIds);
    }

    final userMap = <String, ({String? username, String? iconUrl})>{};
    final now = DateTime.now();

    // 全ユーザー情報を並列取得（キャッシュ済みの場合はFirestoreスキップ）
    final futures = allUserIds.map((uid) async {
      final cached = _userInfoCache[uid];
      if (cached != null && now.difference(cached.fetchedAt) < _userCacheTtl) {
        return MapEntry(uid, (username: cached.username, iconUrl: cached.iconUrl));
      }
      try {
        final user = await _userService.getUser(uid);
        if (user != null) {
          _userInfoCache[uid] = (
            username: user.username,
            iconUrl: user.profileImageUrl,
            fetchedAt: DateTime.now(),
          );
          return MapEntry(uid, (username: user.username, iconUrl: user.profileImageUrl));
        }
      } catch (_) {}
      return null;
    }).toList();

    final results = await Future.wait(futures);
    for (final entry in results) {
      if (entry != null) {
        userMap[entry.key] = entry.value;
      }
    }

    return posts.map((post) {
      final userInfo = userMap[post.userId];

      // いいねユーザーのアイコンURLを最新に更新
      final updatedLikedByIconUrls = post.likedUserIds.map((uid) {
        final info = userMap[uid];
        return info?.iconUrl ?? '';
      }).toList();

      return post.copyWith(
        username: userInfo?.username ?? post.username,
        userIconUrl: userInfo?.iconUrl ?? post.userIconUrl,
        likedByUserIconUrls: updatedLikedByIconUrls,
      );
    }).toList();
  }

  /// 投稿を取得（ページネーション付き、24時間以内のみ）
  Future<List<PostModel>> getPosts({
    int limit = 20,
    DocumentSnapshot? startAfter,
  }) async {
    try {
      final cutoff = DateTime.now().subtract(const Duration(hours: 24));

      Query query = _firestore
          .collection(_postsCollection)
          .where('createdAt', isGreaterThan: Timestamp.fromDate(cutoff))
          .orderBy('createdAt', descending: true)
          .limit(limit);

      if (startAfter != null) {
        query = query.startAfterDocument(startAfter);
      }

      final snapshot = await query.get();
      final posts = snapshot.docs
          .map((doc) => PostModel.fromFirestore(doc))
          .toList();

      return await applyLatestUserInfo(posts);
    } catch (e) {
      if (kDebugMode) {
        print('Error getting posts: $e');
      }
      return [];
    }
  }

  /// フォロー中のユーザーの投稿を取得（Firestore whereIn のバッチ処理）
  Future<List<PostModel>> getPostsForFollowing(List<String> userIds, {int limit = 50}) async {
    if (userIds.isEmpty) return [];

    try {
      final cutoff = DateTime.now().subtract(const Duration(hours: 24));
      final allPosts = <PostModel>[];

      // Firestore whereIn は最大30件制限のためバッチ処理
      for (int i = 0; i < userIds.length; i += 30) {
        final batch = userIds.skip(i).take(30).toList();
        final snapshot = await _firestore
            .collection(_postsCollection)
            .where('userId', whereIn: batch)
            .where('createdAt', isGreaterThan: Timestamp.fromDate(cutoff))
            .orderBy('createdAt', descending: true)
            .limit(limit)
            .get();

        allPosts.addAll(
          snapshot.docs.map((doc) => PostModel.fromFirestore(doc)),
        );
      }

      allPosts.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      final limited = allPosts.take(limit).toList();
      return await applyLatestUserInfo(limited);
    } catch (e) {
      if (kDebugMode) {
        print('Error getting posts for following: $e');
      }
      return [];
    }
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

      final posts = snapshot.docs
          .map((doc) => PostModel.fromFirestore(doc))
          .toList();
      return await applyLatestUserInfo(posts);
    } catch (e) {
      if (kDebugMode) {
        print('Error getting posts by userId: $e');
      }
      return [];
    }
  }

  /// ユーザーの投稿をカーソルページネーション付きで取得
  Future<({List<PostModel> posts, DocumentSnapshot? lastDoc, bool hasMore})>
      getPostsWithPagination(
    String userId, {
    int limit = 20,
    DocumentSnapshot? startAfter,
  }) async {
    try {
      var query = _firestore
          .collection(_postsCollection)
          .where('userId', isEqualTo: userId)
          .orderBy('createdAt', descending: true)
          .limit(limit);

      if (startAfter != null) {
        query = query.startAfterDocument(startAfter);
      }

      final snapshot = await query.get();
      final posts = snapshot.docs
          .map((doc) => PostModel.fromFirestore(doc))
          .toList();

      return (
        posts: await applyLatestUserInfo(posts),
        lastDoc: snapshot.docs.isNotEmpty ? snapshot.docs.last : null,
        hasMore: snapshot.docs.length == limit,
      );
    } catch (e) {
      if (kDebugMode) {
        print('Error getting posts with pagination: $e');
      }
      return (posts: <PostModel>[], lastDoc: null, hasMore: false);
    }
  }

  /// 特定のユーザーが保存した投稿を取得
  Future<List<PostModel>> getPostsSavedByUser(String userId, {int limit = 50}) async {
    try {
      final snapshot = await _firestore
          .collection(_postsCollection)
          .where('savedByUserIds', arrayContains: userId)
          .limit(limit)
          .get();

      final posts = snapshot.docs
          .map((doc) => PostModel.fromFirestore(doc))
          .toList();

      posts.sort((a, b) => b.createdAt.compareTo(a.createdAt));

      return await applyLatestUserInfo(posts);
    } catch (e) {
      if (kDebugMode) {
        print('Error getting saved posts by userId: $e');
      }
      return [];
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
}

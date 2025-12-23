import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import '../models/user_model.dart';

class UserService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final String _usersCollection = 'users';

  // ユーザーデータを作成
  Future<void> createUser({
    required String uid,
    required String phoneNumber,
    String? name,
    String? username,
    String? profileImageUrl,
  }) async {
    try {
      final userDoc = _firestore.collection(_usersCollection).doc(uid);

      final userData = {
        'uid': uid,
        'phoneNumber': phoneNumber,
        'name': name,
        'username': username,
        'profileImageUrl': profileImageUrl,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      };

      await userDoc.set(userData);
    } catch (e) {
      if (kDebugMode) {
        print('Error creating user: $e');
      }
      rethrow;
    }
  }

  // ユーザーデータを更新
  Future<void> updateUser({
    required String uid,
    String? name,
    String? username,
    String? profileImageUrl,
  }) async {
    try {
      final userDoc = _firestore.collection(_usersCollection).doc(uid);

      final updates = <String, dynamic>{
        'updatedAt': FieldValue.serverTimestamp(),
      };

      if (name != null) updates['name'] = name;
      if (username != null) updates['username'] = username;
      if (profileImageUrl != null) updates['profileImageUrl'] = profileImageUrl;

      await userDoc.update(updates);
    } catch (e) {
      if (kDebugMode) {
        print('Error updating user: $e');
      }
      rethrow;
    }
  }

  // ユーザーデータを取得
  Future<UserModel?> getUser(String uid) async {
    try {
      final doc = await _firestore.collection(_usersCollection).doc(uid).get();

      if (doc.exists) {
        return UserModel.fromFirestore(doc);
      }
      return null;
    } catch (e) {
      if (kDebugMode) {
        print('Error getting user: $e');
      }
      return null;
    }
  }

  // ユーザー名が使用可能かチェック
  Future<bool> isUsernameAvailable(String username) async {
    try {
      final query = await _firestore
          .collection(_usersCollection)
          .where('username', isEqualTo: username)
          .limit(1)
          .get();

      return query.docs.isEmpty;
    } catch (e) {
      if (kDebugMode) {
        print('Error checking username: $e');
      }
      return false;
    }
  }

  // ユーザーデータのストリームを取得
  Stream<UserModel?> getUserStream(String uid) {
    return _firestore
        .collection(_usersCollection)
        .doc(uid)
        .snapshots()
        .map((doc) {
      if (doc.exists) {
        return UserModel.fromFirestore(doc);
      }
      return null;
    });
  }

  // ユーザーをフォローする
  Future<void> followUser({
    required String currentUserId,
    required String targetUserId,
  }) async {
    if (currentUserId == targetUserId) {
      throw Exception('自分自身をフォローすることはできません');
    }

    try {
      final batch = _firestore.batch();

      // 現在のユーザーのfollowingリストに追加
      final currentUserDoc = _firestore.collection(_usersCollection).doc(currentUserId);
      batch.update(currentUserDoc, {
        'following': FieldValue.arrayUnion([targetUserId]),
        'updatedAt': FieldValue.serverTimestamp(),
      });

      // ターゲットユーザーのfollowersリストに追加
      final targetUserDoc = _firestore.collection(_usersCollection).doc(targetUserId);
      batch.update(targetUserDoc, {
        'followers': FieldValue.arrayUnion([currentUserId]),
        'updatedAt': FieldValue.serverTimestamp(),
      });

      await batch.commit();
    } catch (e) {
      if (kDebugMode) {
        print('Error following user: $e');
      }
      rethrow;
    }
  }

  // ユーザーのフォローを解除する
  Future<void> unfollowUser({
    required String currentUserId,
    required String targetUserId,
  }) async {
    try {
      final batch = _firestore.batch();

      // 現在のユーザーのfollowingリストから削除
      final currentUserDoc = _firestore.collection(_usersCollection).doc(currentUserId);
      batch.update(currentUserDoc, {
        'following': FieldValue.arrayRemove([targetUserId]),
        'updatedAt': FieldValue.serverTimestamp(),
      });

      // ターゲットユーザーのfollowersリストから削除
      final targetUserDoc = _firestore.collection(_usersCollection).doc(targetUserId);
      batch.update(targetUserDoc, {
        'followers': FieldValue.arrayRemove([currentUserId]),
        'updatedAt': FieldValue.serverTimestamp(),
      });

      await batch.commit();
    } catch (e) {
      if (kDebugMode) {
        print('Error unfollowing user: $e');
      }
      rethrow;
    }
  }

  // フォロワー一覧を取得
  Future<List<UserModel>> getFollowers(String uid) async {
    try {
      final user = await getUser(uid);
      if (user == null || user.followers.isEmpty) {
        return [];
      }

      final List<UserModel> followers = [];
      for (final followerId in user.followers) {
        final follower = await getUser(followerId);
        if (follower != null) {
          followers.add(follower);
        }
      }

      return followers;
    } catch (e) {
      if (kDebugMode) {
        print('Error getting followers: $e');
      }
      return [];
    }
  }

  // フォロー中のユーザー一覧を取得
  Future<List<UserModel>> getFollowing(String uid) async {
    try {
      final user = await getUser(uid);
      if (user == null || user.following.isEmpty) {
        return [];
      }

      final List<UserModel> following = [];
      for (final followingId in user.following) {
        final followingUser = await getUser(followingId);
        if (followingUser != null) {
          following.add(followingUser);
        }
      }

      return following;
    } catch (e) {
      if (kDebugMode) {
        print('Error getting following: $e');
      }
      return [];
    }
  }

  // 投稿を保存する
  Future<void> savePost({
    required String userId,
    required String postId,
  }) async {
    try {
      final userDoc = _firestore.collection(_usersCollection).doc(userId);
      await userDoc.update({
        'savedPosts': FieldValue.arrayUnion([postId]),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      if (kDebugMode) {
        print('Error saving post: $e');
      }
      rethrow;
    }
  }

  // 投稿の保存を解除する
  Future<void> unsavePost({
    required String userId,
    required String postId,
  }) async {
    try {
      final userDoc = _firestore.collection(_usersCollection).doc(userId);
      await userDoc.update({
        'savedPosts': FieldValue.arrayRemove([postId]),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      if (kDebugMode) {
        print('Error unsaving post: $e');
      }
      rethrow;
    }
  }

  // 投稿を保存/保存解除する（トグル）
  Future<void> toggleSavePost({
    required String userId,
    required String postId,
  }) async {
    try {
      final user = await getUser(userId);
      if (user == null) {
        throw Exception('User not found');
      }

      if (user.hasSavedPost(postId)) {
        await unsavePost(userId: userId, postId: postId);
      } else {
        await savePost(userId: userId, postId: postId);
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error toggling save post: $e');
      }
      rethrow;
    }
  }
}

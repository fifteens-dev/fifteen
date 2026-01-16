import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import '../models/user_model.dart';
import '../models/notification_model.dart';
import 'notification_service.dart';

class UserService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final String _usersCollection = 'users';
  final NotificationService _notificationService = NotificationService();

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

  /// ユーザーを検索（usernameとnameの両方で検索）
  ///
  /// [query] 検索クエリ文字列
  /// [limit] 取得する最大件数（デフォルト: 20）
  ///
  /// Returns: 検索結果のUserModelリスト
  Future<List<UserModel>> searchUsers({
    required String query,
    int limit = 20,
  }) async {
    try {
      // 空のクエリは早期リターン
      if (query.trim().isEmpty) {
        return [];
      }

      final searchTerm = query.toLowerCase().trim();
      final endTerm = '$searchTerm\uf8ff'; // Unicode最大文字（前方一致用）

      if (kDebugMode) {
        print('🔍 Searching users with query: "$searchTerm"');
      }

      // usernameフィールドで前方一致検索
      final snapshot = await _firestore
          .collection(_usersCollection)
          .where('username', isGreaterThanOrEqualTo: searchTerm)
          .where('username', isLessThanOrEqualTo: endTerm)
          .limit(limit * 2) // クライアント側フィルタ前に多めに取得
          .get();

      if (kDebugMode) {
        print('📥 Fetched ${snapshot.docs.length} users from Firestore');
      }

      // UserModelに変換してクライアント側でフィルタリング
      final users = snapshot.docs
          .map((doc) => UserModel.fromFirestore(doc))
          .where((user) {
        final username = (user.username ?? '').toLowerCase();
        final name = (user.name ?? '').toLowerCase();

        // usernameまたはnameに検索語が含まれているか
        return username.contains(searchTerm) || name.contains(searchTerm);
      }).take(limit) // 最終的にlimit件に制限
          .toList();

      if (kDebugMode) {
        print('✅ Filtered to ${users.length} matching users');
      }

      return users;
    } catch (e) {
      if (kDebugMode) {
        print('❌ Error searching users: $e');
      }
      return [];
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

      // フォロー通知を作成
      final currentUser = await getUser(currentUserId);
      if (currentUser != null) {
        await _notificationService.createNotification(
          type: NotificationType.follow,
          recipientId: targetUserId,
          senderId: currentUserId,
          senderUsername: currentUser.username ?? 'unknown',
          senderIconUrl: currentUser.profileImageUrl,
        );

        if (kDebugMode) {
          print('✅ フォロー通知作成: follower=$currentUserId, followee=$targetUserId');
        }
      }
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

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
}

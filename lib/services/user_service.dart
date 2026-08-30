import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import '../models/user_model.dart';
import '../models/notification_model.dart';
import 'notification_service.dart';
import 'milfolha_service.dart';

class UserService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final String _usersCollection = 'users';
  final NotificationService _notificationService = NotificationService();

  final String _inviteCodesCollection = 'invite_codes';

  /// 7文字のランダムな英数字招待コードを生成
  String _generateInviteCode() {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789'; // 紛らわしい文字(O,0,I,1)を除外
    final random = Random.secure();
    return List.generate(7, (_) => chars[random.nextInt(chars.length)]).join();
  }

  /// invite_codesコレクションにエントリを作成（回数制限なし）
  Future<void> _createInviteCodeEntry(String code, String ownerUid, WriteBatch batch) async {
    final inviteDoc = _firestore.collection(_inviteCodesCollection).doc(code);
    batch.set(inviteDoc, {
      'code': code,
      'usedCount': 0,
      'ownerUid': ownerUid,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  // ユーザーデータを作成
  Future<void> createUser({
    required String uid,
    required String phoneNumber,
    String? name,
    String? username,
    String? profileImageUrl,
  }) async {
    try {
      final inviteCode = _generateInviteCode();
      final batch = _firestore.batch();

      // ユーザードキュメント
      final userDoc = _firestore.collection(_usersCollection).doc(uid);
      batch.set(userDoc, {
        'uid': uid,
        'phoneNumber': phoneNumber,
        'name': name,
        'username': username,
        'profileImageUrl': profileImageUrl,
        'inviteCode': inviteCode,
        'followers': [],
        'following': [],
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });

      // 招待コードエントリ（maxUses: 3）
      await _createInviteCodeEntry(inviteCode, uid, batch);

      await batch.commit();
    } catch (e) {
      if (kDebugMode) {
        print('Error creating user: $e');
      }
      rethrow;
    }
  }

  /// 既存ユーザーの招待コードを取得（なければ生成して保存）
  /// invite_codesエントリも同期する
  Future<String> ensureInviteCode(String uid) async {
    try {
      final doc = await _firestore.collection(_usersCollection).doc(uid).get();
      final data = doc.data();
      final existing = data?['inviteCode'] as String?;

      if (existing != null && existing.isNotEmpty) {
        // invite_codesエントリが存在しない場合は作成
        final inviteDoc = await _firestore
            .collection(_inviteCodesCollection)
            .doc(existing)
            .get();
        if (!inviteDoc.exists) {
          final batch = _firestore.batch();
          await _createInviteCodeEntry(existing, uid, batch);
          await batch.commit();
        }
        return existing;
      }

      // コードを新規生成
      final code = _generateInviteCode();
      final batch = _firestore.batch();
      batch.update(_firestore.collection(_usersCollection).doc(uid), {
        'inviteCode': code,
      });
      await _createInviteCodeEntry(code, uid, batch);
      await batch.commit();
      return code;
    } catch (e) {
      if (kDebugMode) {
        print('Error ensuring invite code: $e');
      }
      rethrow;
    }
  }

  /// 招待コードの使用回数を取得
  Future<int> getInviteCodeUsedCount(String code) async {
    try {
      final doc = await _firestore
          .collection(_inviteCodesCollection)
          .doc(code)
          .get();
      return (doc.data()?['usedCount'] as int?) ?? 0;
    } catch (e) {
      return 0;
    }
  }

  /// アクティブを記録（DAU/MAU 計測用）
  /// ドキュメントID = "{uid}_{YYYY-MM-DD}" で 1ユーザー1日1件に制限
  Future<void> updateLastActive(String uid) async {
    try {
      final now = DateTime.now();
      final dateStr =
          '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
      final monthKey =
          '${now.year}-${now.month.toString().padLeft(2, '0')}';

      // set() はべき等（同じドキュメントIDに何度呼んでも1件のまま）
      await _firestore
          .collection('app_open_events')
          .doc('${uid}_$dateStr')
          .set({
        'userId': uid,
        'date': dateStr,
        'monthKey': monthKey,
        'createdAt': FieldValue.serverTimestamp(),
      });
    } catch (_) {}
  }

  // ユーザーデータを更新
  Future<void> updateUser({
    required String uid,
    String? name,
    String? username,
    String? profileImageUrl,
    String? bio,
    String? university,
  }) async {
    try {
      final userDoc = _firestore.collection(_usersCollection).doc(uid);

      final updates = <String, dynamic>{
        'updatedAt': FieldValue.serverTimestamp(),
      };

      if (name != null) updates['name'] = name;
      if (username != null) updates['username'] = username;
      if (profileImageUrl != null) updates['profileImageUrl'] = profileImageUrl;
      if (bio != null) updates['bio'] = bio;
      if (university != null) updates['university'] = university;

      await userDoc.set(updates, SetOptions(merge: true));
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

  /// [getUser] と同じだが、読み取りエラー時に**例外を投げる**版。
  /// 呼び出し側で「一時的な読み取り失敗（例外）」と「ドキュメント無し（null）」を
  /// 区別したい場合に使う（例: 起動時の認証チェック）。
  /// ドキュメントが存在しない場合のみ null を返す（＝確定で未登録）。
  Future<UserModel?> getUserOrThrow(String uid) async {
    final doc = await _firestore.collection(_usersCollection).doc(uid).get();
    if (doc.exists) {
      return UserModel.fromFirestore(doc);
    }
    return null;
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

      final trimmed = query.trim();
      final searchTerm = trimmed.toLowerCase();

      // Firestore の文字列比較はバイト単位で大文字小文字を区別する。
      // 小文字化した searchTerm だけで range 検索すると "Suga.xxx" のような
      // 大文字始まりの username がヒットしない。ケース variant 4 種で
      // それぞれ範囲検索し、結果を uid でマージ&dedup することで対応する。
      final variants = <String>{
        trimmed,
        searchTerm,
        _capitalizeFirst(searchTerm),
        trimmed.toUpperCase(),
      }..removeWhere((v) => v.isEmpty);

      if (kDebugMode) {
        print('🔍 Searching users with variants: $variants');
      }

      final merged = <String, UserModel>{};
      for (final v in variants) {
        final endTerm = '$v\uf8ff';
        try {
          final snap = await _firestore
              .collection(_usersCollection)
              .where('username', isGreaterThanOrEqualTo: v)
              .where('username', isLessThanOrEqualTo: endTerm)
              .limit(limit * 2)
              .get();
          for (final doc in snap.docs) {
            merged.putIfAbsent(doc.id, () => UserModel.fromFirestore(doc));
          }
        } catch (e) {
          if (kDebugMode) {
            print('⚠️ variant "$v" query failed: $e');
          }
        }
      }

      if (kDebugMode) {
        print('📥 Merged ${merged.length} unique users across variants');
      }

      // クライアント側の case-insensitive contains フィルタで再確認
      final users = merged.values.where((user) {
        final username = (user.username ?? '').toLowerCase();
        final name = (user.name ?? '').toLowerCase();
        return username.contains(searchTerm) || name.contains(searchTerm);
      }).take(limit).toList();

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

  /// 先頭 1 文字だけを大文字にする ("suga.xxx" → "Suga.xxx")。
  /// 検索でのケース variant 生成に使う。
  String _capitalizeFirst(String s) {
    if (s.isEmpty) return s;
    return s[0].toUpperCase() + s.substring(1);
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

  /// フォロー中のユーザー一覧を取得（UserModelのリスト）
  Future<List<UserModel>> getFollowingUsers(String userId) async {
    try {
      final doc = await _firestore.collection(_usersCollection).doc(userId).get();
      if (!doc.exists) return [];
      final data = doc.data()!;
      final followingIds = List<String>.from(data['following'] ?? []);
      if (followingIds.isEmpty) return [];
      final results = await Future.wait(
        followingIds.map((id) => _firestore.collection(_usersCollection).doc(id).get()),
      );
      return results
          .where((d) => d.exists)
          .map((d) => UserModel.fromFirestore(d))
          .toList();
    } catch (e) {
      if (kDebugMode) print('getFollowingUsers error: $e');
      return [];
    }
  }

  Future<List<UserModel>> getFollowerUsers(String userId) async {
    try {
      final doc = await _firestore.collection(_usersCollection).doc(userId).get();
      if (!doc.exists) return [];
      final data = doc.data()!;
      final followerIds = List<String>.from(data['followers'] ?? []);
      if (followerIds.isEmpty) return [];
      final results = await Future.wait(
        followerIds.map((id) => _firestore.collection(_usersCollection).doc(id).get()),
      );
      return results
          .where((d) => d.exists)
          .map((d) => UserModel.fromFirestore(d))
          .toList();
    } catch (e) {
      if (kDebugMode) print('getFollowerUsers error: $e');
      return [];
    }
  }

  // ユーザーをフォローする
  Future<void> followUser({
    required String currentUserId,
    required String targetUserId,
    bool skipNotification = false,
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

      if (skipNotification) return;

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

  // フォロワーを削除する（自分のフォロワーリストから指定ユーザーを除去）
  Future<void> removeFollower({
    required String currentUserId,
    required String followerUserId,
  }) async {
    try {
      final batch = _firestore.batch();

      // 自分のfollowersリストから削除
      final currentUserDoc = _firestore.collection(_usersCollection).doc(currentUserId);
      batch.update(currentUserDoc, {
        'followers': FieldValue.arrayRemove([followerUserId]),
        'updatedAt': FieldValue.serverTimestamp(),
      });

      // 相手のfollowingリストから自分を削除
      final followerUserDoc = _firestore.collection(_usersCollection).doc(followerUserId);
      batch.update(followerUserDoc, {
        'following': FieldValue.arrayRemove([currentUserId]),
        'updatedAt': FieldValue.serverTimestamp(),
      });

      await batch.commit();
    } catch (e) {
      if (kDebugMode) {
        print('Error removing follower: $e');
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

      // 逐次ではなく並列取得でN+1問題を解消
      final results = await Future.wait(
        user.followers.map((followerId) => getUser(followerId)),
      );
      return results.whereType<UserModel>().toList();
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

      // 逐次ではなく並列取得でN+1問題を解消
      final results = await Future.wait(
        user.following.map((followingId) => getUser(followingId)),
      );
      return results.whereType<UserModel>().toList();
    } catch (e) {
      if (kDebugMode) {
        print('Error getting following: $e');
      }
      return [];
    }
  }

  /// アカウント削除: Firestoreのユーザーデータを削除
  Future<void> deleteUserData(String userId) async {
    try {
      // WATERFALLS の所属は users とは別コレクションなので、users を消す前に
      // 後始末する（残すと集計だけに載る孤児メンバーシップになる）。
      await MilfolhaService().cleanupMembershipForDeletedUser(userId);

      final batch = _firestore.batch();

      // ユーザードキュメントを削除
      final userDoc = _firestore.collection(_usersCollection).doc(userId);
      batch.delete(userDoc);

      // FCMトークンを削除
      final fcmDoc = _firestore.collection('user_fcm_tokens').doc(userId);
      batch.delete(fcmDoc);

      // post_notification_states は Admin SDK 管理のためクライアントからは削除不可

      await batch.commit();

      // 投稿を削除（件数が多い可能性があるため個別に処理）
      final postsSnapshot = await _firestore
          .collection('posts')
          .where('userId', isEqualTo: userId)
          .get();
      for (final doc in postsSnapshot.docs) {
        await doc.reference.delete();
      }

      // 受信した通知を削除
      final notificationsSnapshot = await _firestore
          .collection('notifications')
          .where('recipientId', isEqualTo: userId)
          .get();
      for (final doc in notificationsSnapshot.docs) {
        await doc.reference.delete();
      }

      // push_notification_requests は管理者のみ削除可のためクライアントからはスキップ

    } catch (e) {
      if (kDebugMode) {
        print('Error deleting user data: $e');
      }
      rethrow;
    }
  }
}

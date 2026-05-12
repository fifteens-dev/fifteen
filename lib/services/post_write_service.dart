import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import '../models/post_theme.dart';
import '../models/notification_model.dart';
import 'notification_service.dart';
import 'user_service.dart';

/// 投稿データの書き込み（作成・更新・削除）を担当するサービス
class PostWriteService {
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
    double imageOffsetX = 0.0,
    double imageOffsetY = 0.0,
    double imageScale = 1.0,
    double imageNaturalWidth = 0.0,
    double imageNaturalHeight = 0.0,
    int selectedLayoutIndex = 0,
    double cardPositionX = 0.0,
    double cardPositionY = 0.0,
    double cardScale = 1.0,
    double cardRotation = 0.0,
    bool isVibe = false,
    String? vibeTopicId,
    String? vibeTopicTitle,
    String? emotionTag,
    PostTheme? theme,
    String? lyricsText,
    int audioStartMs = 0,
    int audioDurationSec = 15,
    String? university,
    bool campusVibeParticipating = true,
    String? adlTeamId,
  }) async {
    try {
      final postRef = _firestore.collection(_postsCollection).doc();

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
        'imageOffsetX': imageOffsetX,
        'imageOffsetY': imageOffsetY,
        'imageScale': imageScale,
        'imageNaturalWidth': imageNaturalWidth,
        'imageNaturalHeight': imageNaturalHeight,
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
        'theme': theme != null ? theme.toMap() : null,
        'lyricsText': lyricsText,
        'audioStartMs': audioStartMs,
        'audioDurationSec': audioDurationSec,
        'university': university,
        'campusVibeParticipating': campusVibeParticipating,
        // 作成時の参加状態を永続保持（archiveで上書きされない）
        'campusVibePost': campusVibeParticipating == true && university != null,
        'adlTeamId': adlTeamId,
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

  /// 投稿の写真URLを更新（分割アップロード後にバックグラウンドで呼ぶ）
  Future<void> updatePostPhotoUrl({
    required String postId,
    required String photoUrl,
  }) async {
    try {
      await _firestore.collection(_postsCollection).doc(postId).update({
        'photoUrl': photoUrl,
      });
    } catch (e) {
      if (kDebugMode) {
        print('Error updating post photoUrl: $e');
      }
      rethrow;
    }
  }

  /// 投稿の歌詞テキストを更新（フォールバック取得後の保存用）
  Future<void> updateLyricsText({
    required String postId,
    required String lyricsText,
  }) async {
    try {
      await _firestore.collection(_postsCollection).doc(postId).update({
        'lyricsText': lyricsText,
      });
      if (kDebugMode) {
        print('✅ 歌詞をFirebaseに保存しました: postId=$postId');
      }
    } catch (e) {
      if (kDebugMode) {
        print('❌ 歌詞の保存エラー: $e');
      }
      // エラーは無視（次回また取得すればいい）
    }
  }

  /// いいねをトグル（追加/削除）
  Future<void> toggleLike({
    required String postId,
    required String userId,
  }) async {
    try {
      final postRef = _firestore.collection(_postsCollection).doc(postId);

      String? postOwnerId;
      String? albumArtUrl;
      String? trackName;
      bool wasLiked = false;

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

        if (!isLiked) {
          postOwnerId = data['userId'];
          final trackData = data['track'] as Map<String, dynamic>?;
          albumArtUrl = trackData?['albumImageUrl'];
          trackName = trackData?['trackName'];
        }

        wasLiked = isLiked;

        if (isLiked) {
          final index = likedUserIds.indexOf(userId);
          likedUserIds.remove(userId);
          if (index >= 0 && index < likedByUserIconUrls.length) {
            likedByUserIconUrls.removeAt(index);
          }
        } else {
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

  /// アナリティクスイベントを記録（analytics_events コレクション）
  Future<void> trackAnalyticsEvent({required String uid, required String type}) async {
    await _firestore.collection('analytics_events').add({
      'userId': uid,
      'type': type,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }
}

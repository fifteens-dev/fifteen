import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import '../models/post_theme.dart';
import '../models/notification_model.dart';
import 'notification_service.dart';
import 'user_service.dart';
import 'music_memory_cycle_service.dart';
import '../models/profile_snapshot.dart';
import 'profile_snapshot_service.dart';
import '../utils/app_log.dart';

/// 投稿データの書き込み（作成・更新・削除）を担当するサービス
class PostWriteService {
  /// 投稿が作られたことを知らせる。値は作成のたびに増える。
  ///
  /// 画面をまたいで「自分の投稿一覧を読み直す必要があるか」を判断するのに
  /// 使う。Music Memory のカレンダーがこれを見ている。
  ///
  /// このクラスは呼び出しごとに生成されるので static で持つ。
  static final ValueNotifier<int> postCreated = ValueNotifier<int>(0);

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final String _postsCollection = 'posts';
  final NotificationService _notificationService = NotificationService();
  final UserService _userService = UserService();

  /// 投稿カード裏面用のスナップショットを、作成済みの投稿に後追いで書き込む。
  ///
  /// 失敗しても投稿自体は成立しているので握りつぶす（裏面が空になるだけ）。
  /// 直近の投稿を材料にするため、作成した投稿自身も recent choice に入る。
  /// [skipSnapshot] のときは集計せず、authorName だけ入れる。
  /// 投稿を書き込むときに既にスナップショットを入れてある場合に使う。
  Future<void> _writeProfileSnapshot(
    String postId,
    String userId, {
    bool skipSnapshot = false,
  }) async {
    try {
      final snapshot = skipSnapshot
          ? ProfileSnapshot.empty
          : await ProfileSnapshotService.instance.build(uid: userId);
      final user = await _userService.getUser(userId);
      final update = <String, dynamic>{
        if (!snapshot.isEmpty) 'profileSnapshot': snapshot.toMap(),
        if (user?.name != null && user!.name!.isNotEmpty) 'authorName': user.name,
      };
      if (update.isEmpty) return;
      await _firestore.collection(_postsCollection).doc(postId).update(update);
    } catch (e) {
      if (kDebugMode) AppLog.debug('_writeProfileSnapshot error: $e');
    }
  }

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
    bool isMoodPost = false,
    bool hideBackOverlays = false,
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
    String audience = 'public',
    ProfileSnapshot? profileSnapshot,
    /// 1 サイクル 1 投稿の制限を受けないか（管理者）。
    ///
    /// true のときは引換券を取らない。券は 1 サイクルに 1 枚しか置けず、
    /// 2 回目は書き込みごと失敗してしまうため。ルール側も管理者には券を
    /// 要求しない。
    bool exemptFromCycleLimit = false,
  }) async {
    try {
      final postRef = _firestore.collection(_postsCollection).doc();

      final now = DateTime.now();
      final vibeDate = isVibe
          ? DateTime(now.year, now.month, now.day)
          : null;

      // Music Memory 投稿のサイクル情報。作成時点の通知時刻を cycleStart に、
      // 締切（翌1:00）超過なら isLate=true を付与する。通知未発火(null)なら通常扱い。
      final mmCycle = MusicMemoryCycleService();
      final DateTime? cycleStart = isMoodPost ? mmCycle.notifiedAt : null;
      final bool isLate = isMoodPost ? mmCycle.isLate(now) : false;

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
        'isMoodPost': isMoodPost,
        'hideBackOverlays': hideBackOverlays,
        'vibeTopicId': vibeTopicId,
        'vibeTopicTitle': vibeTopicTitle,
        'vibeDate': vibeDate != null ? Timestamp.fromDate(vibeDate) : null,
        'cycleStart': cycleStart != null ? Timestamp.fromDate(cycleStart) : null,
        'isLate': isLate,
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
        'audience': audience,
        // 投稿前に用意できていれば最初から入れる。入れずに後追いすると、
        // 書き込み直後に読み直す画面（ホーム）で裏面が空のまま出る。
        if (profileSnapshot != null && !profileSnapshot.isEmpty)
          'profileSnapshot': profileSnapshot.toMap(),
      };

      // Music Memory の投稿は 1 サイクル 1 回。投稿と同じバッチで
      // 「引換券」を取る。券は ID が '<uid>_<サイクルの鍵>' で固定されて
      // おり、create は 2 回目が必ず失敗する（ルールで update/delete も
      // 禁じている）。したがって 2 投稿目はバッチごと落ちる。
      //
      // サイクルの鍵が分からないときは券を取らない。ルール側もその場合は
      // 制限を掛けないようにしてある（締めると誰も投稿できなくなる）。
      final cycleKey =
          (isMoodPost && !exemptFromCycleLimit) ? mmCycle.cycleKey : null;
      if (cycleKey != null && cycleKey.isNotEmpty) {
        final batch = _firestore.batch();
        batch.set(postRef, postData);
        batch.set(
          _firestore.collection('post_claims').doc('${userId}_$cycleKey'),
          {
            'userId': userId,
            'postId': postRef.id,
            'createdAt': FieldValue.serverTimestamp(),
          },
        );
        await batch.commit();
      } else {
        await postRef.set(postData);
      }
      postCreated.value++;

      // カード裏面に出す「その時点の音楽の顔」。
      //
      // 呼び出し側が用意していればそれを使い（上の postData に入っている）、
      // 名前だけ追いかけて入れる。用意が無い経路では従来どおりここで集計する。
      // 集計は Spotify を叩くので、投稿の完了は待たせない。
      unawaited(
        _writeProfileSnapshot(
          postRef.id,
          userId,
          skipSnapshot: profileSnapshot != null && !profileSnapshot.isEmpty,
        ),
      );

      return postRef.id;
    } catch (e) {
      if (kDebugMode) {
        AppLog.debug('Error creating post: $e');
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
        AppLog.debug('Error deleting post: $e');
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
        AppLog.debug('Error updating post photoUrl: $e');
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
        AppLog.debug('✅ 歌詞をFirebaseに保存しました: postId=$postId');
      }
    } catch (e) {
      if (kDebugMode) {
        AppLog.debug('❌ 歌詞の保存エラー: $e');
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
          AppLog.debug('✅ いいね通知作成: postId=$postId, recipient=$postOwnerId');
        }
      }
    } catch (e) {
      if (kDebugMode) {
        AppLog.debug('Error toggling like: $e');
      }
      rethrow;
    }
  }

  /// 絵文字リアクションを設定/変更/解除する（1ユーザー＝1つ）。
  /// - 同じ絵文字を再指定 → 解除（トグルオフ）
  /// - 別の絵文字を指定 → 変更
  /// - 未リアクション → 追加
  /// 追加・変更時のみ、投稿者へ通知する（自分の投稿は除く）。
  Future<void> setReaction({
    required String postId,
    required String emoji,
    required String userId,
  }) async {
    try {
      final postRef = _firestore.collection(_postsCollection).doc(postId);

      String? postOwnerId;
      String? albumArtUrl;
      String? trackName;
      bool shouldNotify = false; // 追加/変更のときだけ true

      final currentUser = await _userService.getUser(userId);
      final userIconUrl = currentUser?.profileImageUrl ?? '';

      await _firestore.runTransaction((transaction) async {
        final postDoc = await transaction.get(postRef);
        if (!postDoc.exists) {
          throw Exception('Post not found');
        }
        final data = postDoc.data()!;
        final reactions = <String, dynamic>{
          ...((data['reactions'] as Map?)?.cast<String, dynamic>() ?? {}),
        };

        final existing = reactions[userId];
        final existingEmoji =
            existing is Map ? existing['emoji']?.toString() : null;

        if (existingEmoji == emoji) {
          // 同じ絵文字 → 解除
          reactions.remove(userId);
        } else {
          // 追加 or 変更
          reactions[userId] = {
            'emoji': emoji,
            'iconUrl': userIconUrl,
            'ts': DateTime.now().millisecondsSinceEpoch,
          };
          shouldNotify = true;
          postOwnerId = data['userId']?.toString();
          final trackData = data['track'] as Map<String, dynamic>?;
          albumArtUrl = trackData?['albumImageUrl']?.toString();
          trackName = trackData?['trackName']?.toString();
        }

        transaction.update(postRef, {
          'reactions': reactions,
          'reactionCount': reactions.length,
          'updatedAt': FieldValue.serverTimestamp(),
        });
      });

      if (shouldNotify && postOwnerId != null && postOwnerId != userId) {
        await _notificationService.createNotification(
          type: NotificationType.like, // リアクションは like 種別を再利用
          recipientId: postOwnerId!,
          senderId: userId,
          senderUsername: currentUser?.username ?? 'Unknown',
          senderIconUrl: currentUser?.profileImageUrl,
          postId: postId,
          albumArtUrl: albumArtUrl,
          trackName: trackName,
          body: '「$emoji」でリアクションしました',
        );
        if (kDebugMode) {
          AppLog.debug('✅ リアクション通知作成: postId=$postId, emoji=$emoji, recipient=$postOwnerId');
        }
      }
    } catch (e) {
      if (kDebugMode) {
        AppLog.debug('Error setting reaction: $e');
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
        AppLog.debug('Error updating comment count: $e');
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

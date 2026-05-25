import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/track_model.dart';

/// 投稿・楽曲の保存機能を一元管理するサービス。
///
/// - 投稿保存: users/{uid}.savedPosts と posts/{postId}.savedByUserIds を
///   バッチで同時更新（両コレクション常に同期）
/// - 楽曲保存: users/{uid}.savedTracksData マップを更新
///
/// 呼び出し元は現在の保存状態 [currentlySaved] を渡すことで、
/// サービス側の余分な Firestore 読み取りを省略する。
class SaveService {
  static final SaveService _instance = SaveService._internal();
  factory SaveService() => _instance;
  SaveService._internal();

  final FirebaseFirestore _db = FirebaseFirestore.instance;

  static const _colUsers = 'users';
  static const _colPosts = 'posts';

  // ── 投稿保存 ───────────────────────────────────────────────

  /// 投稿の保存/解除をトグルする。
  ///
  /// [currentlySaved] は呼び出し元が楽観的UIのために既に把握している
  /// 現在の保存状態。これにより余分な Firestore 読み取りを省略できる。
  Future<void> toggleSavePost({
    required String userId,
    required String postId,
    required bool currentlySaved,
  }) async {
    final userRef = _db.collection(_colUsers).doc(userId);
    final postRef = _db.collection(_colPosts).doc(postId);
    final batch = _db.batch();

    if (currentlySaved) {
      batch.update(userRef, {
        'savedPosts': FieldValue.arrayRemove([postId]),
        'savedPostsAt.$postId': FieldValue.delete(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
      batch.update(postRef, {
        'savedByUserIds': FieldValue.arrayRemove([userId]),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } else {
      batch.update(userRef, {
        'savedPosts': FieldValue.arrayUnion([postId]),
        'savedPostsAt.$postId': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
      batch.update(postRef, {
        'savedByUserIds': FieldValue.arrayUnion([userId]),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    }

    await batch.commit();
  }

  // ── 楽曲保存 ───────────────────────────────────────────────

  /// 楽曲の保存/解除をトグルする。
  ///
  /// 保存時は trackId をキーに楽曲メタデータ全体を savedTracksData に格納する。
  /// これにより、保存済み楽曲をアーティストプロフィール・投稿作成画面の
  /// 両方で追加の API コールなしに表示できる。
  Future<void> toggleSaveTrack({
    required String userId,
    required TrackModel track,
    required bool currentlySaved,
  }) async {
    final userRef = _db.collection(_colUsers).doc(userId);

    if (currentlySaved) {
      await userRef.update({
        'savedTracksData.${track.trackId}': FieldValue.delete(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } else {
      await userRef.update({
        'savedTracksData.${track.trackId}': {
          'trackId': track.trackId,
          'trackName': track.trackName,
          'artistName': track.artistName,
          'albumImageUrl': track.albumImageUrl,
          if (track.previewUrl != null && track.previewUrl!.isNotEmpty)
            'previewUrl': track.previewUrl,
          'savedAt': FieldValue.serverTimestamp(),
        },
        'updatedAt': FieldValue.serverTimestamp(),
      });
    }
  }
}

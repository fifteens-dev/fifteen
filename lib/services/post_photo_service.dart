import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import '../utils/photo_helper.dart';
import 'music_memory_cycle_service.dart';
import 'storage_service.dart';

/// 投稿に添える写真。**本人しか見られない**。
///
/// ## なぜ posts に入れないか
/// posts は `allow list: if isAuthenticated()` で、ログインしていれば一覧を
/// 引ける。photoUrl を posts に入れると、URL を読めてしまう以上「非公開」に
/// ならない。そこで `post_photos/{postId}` に分け、ルールで本人だけに絞る。
///
/// 写真そのものは Storage に置く。URL を知られても困らないよう、パスに
/// 推測しにくい postId を使い、Storage 側のルールでも本人に限定する。
class PostPhotoService {
  PostPhotoService._();
  static final PostPhotoService instance = PostPhotoService._();

  static const String _collection = 'post_photos';

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final StorageService _storage = StorageService();

  /// 写真を足せる時間帯か（投稿した日の 24:00 まで）。
  ///
  /// 24 時を過ぎたら投稿はできても写真は足せない。境界は投稿と同じ
  /// [MusicMemoryCycleService] の締切を使う。
  bool get canAddPhotoNow {
    final deadline = MusicMemoryCycleService().currentDeadline;
    if (deadline == null) return false;
    return DateTime.now().isBefore(deadline);
  }

  /// その写真が「今日撮ったもの」か。
  ///
  /// 判定はサイクル（通知 21:00）ではなく暦日で行う。ユーザーの感覚が
  /// 「今日撮った写真」であり、20 時に撮った写真を弾くと理屈に合わないため。
  static bool isTakenToday(DateTime? createdAt) {
    if (createdAt == null) return false;
    final now = DateTime.now();
    return createdAt.year == now.year &&
        createdAt.month == now.month &&
        createdAt.day == now.day;
  }

  /// 写真を保存する。成功したら true。
  Future<bool> attach({
    required String postId,
    required Uint8List imageBytes,
  }) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return false;

    try {
      final (processed, width, height) =
          await PhotoHelper.compressForUpload(imageBytes);
      final result = await PhotoHelper.uploadCompressedSplit(
        imageBytes: processed,
        userId: uid,
        storageService: _storage,
        // 本人しか見られない写真なので、公開画像とは別のパスに置く。
        private: true,
      );
      final url = await result.storageRef?.getDownloadURL();
      if (url == null) return false;

      await _firestore.collection(_collection).doc(postId).set({
        'userId': uid,
        'photoUrl': url,
        'width': width,
        'height': height,
        'createdAt': FieldValue.serverTimestamp(),
      });
      return true;
    } catch (e) {
      if (kDebugMode) print('PostPhotoService.attach error: $e');
      return false;
    }
  }

  /// 自分の投稿に付いている写真の URL を引く。
  /// 他人の投稿を渡してもルールで弾かれ、null が返る。
  Future<String?> photoUrl(String postId) async {
    try {
      final doc = await _firestore.collection(_collection).doc(postId).get();
      final url = doc.data()?['photoUrl'];
      return url is String && url.isNotEmpty ? url : null;
    } catch (_) {
      return null;
    }
  }

  /// 複数の投稿ぶんまとめて引く（Music Memory のカレンダー用）。
  /// 返すのは postId → URL。写真の無い投稿は含まれない。
  Future<Map<String, String>> photoUrls(List<String> postIds) async {
    if (postIds.isEmpty) return const {};
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return const {};

    final out = <String, String>{};
    // whereIn は 30 件まで。
    for (var i = 0; i < postIds.length; i += 30) {
      final chunk = postIds.skip(i).take(30).toList();
      try {
        final snap = await _firestore
            .collection(_collection)
            .where(FieldPath.documentId, whereIn: chunk)
            .get();
        for (final d in snap.docs) {
          final url = d.data()['photoUrl'];
          if (url is String && url.isNotEmpty) out[d.id] = url;
        }
      } catch (e) {
        if (kDebugMode) print('PostPhotoService.photoUrls chunk failed: $e');
      }
    }
    return out;
  }

  /// 写真を消す。投稿の削除に合わせて呼ぶ。
  Future<void> remove(String postId) async {
    try {
      await _firestore.collection(_collection).doc(postId).delete();
    } catch (e) {
      if (kDebugMode) print('PostPhotoService.remove error: $e');
    }
  }
}

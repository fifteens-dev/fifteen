import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import '../models/playlist_model.dart';

/// プレイリストの作成・取得を担当するサービス（Firestore `playlists`）。
class PlaylistService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  static const String _col = 'playlists';

  /// 新しいプレイリストを作成し、作成した ID を返す。
  Future<String> createPlaylist({
    required String userId,
    required String name,
    required List<String> postIds,
    String coverImageUrl = '',
  }) async {
    final ref = await _firestore.collection(_col).add({
      'userId': userId,
      'name': name,
      'coverImageUrl': coverImageUrl,
      'postIds': postIds,
      'trackCount': postIds.length,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    return ref.id;
  }

  /// 指定ユーザーのプレイリストを新しい順で取得する。
  /// （複合インデックス不要にするためソートはクライアント側で行う）
  Future<List<PlaylistModel>> getPlaylistsByUserId(String userId) async {
    try {
      final snap = await _firestore
          .collection(_col)
          .where('userId', isEqualTo: userId)
          .get();
      final list =
          snap.docs.map((d) => PlaylistModel.fromFirestore(d)).toList();
      list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return list;
    } catch (e) {
      if (kDebugMode) print('getPlaylistsByUserId error: $e');
      return [];
    }
  }

  /// プレイリストを削除する。
  Future<void> deletePlaylist(String playlistId) async {
    await _firestore.collection(_col).doc(playlistId).delete();
  }
}

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import '../models/artist_model.dart';

class ArtistService {
  static final ArtistService _instance = ArtistService._internal();
  factory ArtistService() => _instance;
  ArtistService._internal();

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  static const _col = 'artists';

  /// アーティスト名 → フォロワー数 の in-memory キャッシュ
  final Map<String, int> _followerCountCache = {};

  Future<ArtistModel?> getArtist(String artistId) async {
    try {
      final doc = await _firestore.collection(_col).doc(artistId).get();
      if (!doc.exists) return null;
      return ArtistModel.fromFirestore(doc);
    } catch (e) {
      if (kDebugMode) print('ArtistService.getArtist error: $e');
      return null;
    }
  }

  /// アーティスト名でフォロワー数を取得する。
  /// 同名で artists コレクションを検索し、ヒットしたドキュメントの followerIds.length を返す。
  /// 見つからない場合は 0 を返す。
  Future<int> getFollowerCountByName(String artistName) async {
    if (artistName.isEmpty) return 0;
    final cached = _followerCountCache[artistName];
    if (cached != null) return cached;
    try {
      final snap = await _firestore
          .collection(_col)
          .where('artistName', isEqualTo: artistName)
          .limit(1)
          .get();
      if (snap.docs.isEmpty) {
        _followerCountCache[artistName] = 0;
        return 0;
      }
      final data = snap.docs.first.data();
      final ids = (data['followerIds'] as List?)?.whereType<String>().toList() ?? const [];
      final count = ids.length;
      _followerCountCache[artistName] = count;
      return count;
    } catch (e) {
      if (kDebugMode) print('ArtistService.getFollowerCountByName error: $e');
      return 0;
    }
  }

  /// フォロー/アンフォローの後にキャッシュを無効化する。
  void invalidateFollowerCountCache(String artistName) {
    _followerCountCache.remove(artistName);
  }

  Future<void> followArtist({
    required String userId,
    required String artistId,
    required String artistName,
  }) async {
    final ref = _firestore.collection(_col).doc(artistId);
    final doc = await ref.get();
    if (!doc.exists) {
      await ref.set({
        'artistId': artistId,
        'artistName': artistName,
        'followerIds': [userId],
        'createdAt': FieldValue.serverTimestamp(),
      });
    } else {
      await ref.update({'followerIds': FieldValue.arrayUnion([userId])});
    }
  }

  Future<void> unfollowArtist({
    required String userId,
    required String artistId,
  }) async {
    try {
      await _firestore.collection(_col).doc(artistId).update({
        'followerIds': FieldValue.arrayRemove([userId]),
      });
    } catch (e) {
      if (kDebugMode) print('ArtistService.unfollowArtist error: $e');
    }
  }
}

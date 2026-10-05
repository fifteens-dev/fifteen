import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

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
  ///
  /// 通知時刻が未取得なら取りに行く。アプリを開いた直後は未取得で、
  /// そのまま見ると締切が不明＝「追加できない」になってしまう
  /// （実際にそれで写真追加のバーが出なかった）。
  Future<bool> canAddPhotoNow() async {
    final cycle = MusicMemoryCycleService();
    // 延長の判定より先に取る。写真の絞り込み（どの日の写真を出すか）が
    // notifiedAt を見るので、先に return すると null のままになる。
    if (cycle.notifiedAt == null) await cycle.fetchNotifiedAt();
    if (_temporaryExtensionActive) return true;
    final deadline = cycle.currentDeadline;
    if (deadline == null) return false;
    return DateTime.now().isBefore(deadline);
  }

  /// 取りに行かずに判定する。既に取得済みの前提で、描画のたびに
  /// 呼ばれる場所（カードのバーを出すか）で使う。
  bool get canAddPhotoNowSync {
    if (_temporaryExtensionActive) return true;
    final deadline = MusicMemoryCycleService().currentDeadline;
    if (deadline == null) return false;
    return DateTime.now().isBefore(deadline);
  }

  /// 一時的な制限解除中か（動作確認用・2026-10-05 中）。
  /// 期限や意図は [MusicMemoryCycleService.limitsLifted] に書いてある。
  static bool get _temporaryExtensionActive =>
      MusicMemoryCycleService.limitsLifted;

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
      _cache = null; // 次の取得で入れ直す
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

  /// 自分の写真をまとめて引く（Music Memory のカレンダー用）。
  /// 返すのは postId → URL。
  ///
  /// postId で絞らず、自分のぶんを丸ごと取る。documentId の whereIn を使うと、
  /// **存在しないドキュメント ID が 1 つでも混ざった時点でクエリ全体が
  /// permission-denied になる**（実機と同じクライアント SDK で確認）。
  /// カレンダーは写真の無い日も含めて問い合わせるので、必ずそこに当たる。
  ///
  /// 件数は 1 ユーザーの投稿数ぶんなので、まとめて引いても重くない。
  /// 結果はキャッシュして、画面を開き直すたびに取り直さない。
  Future<Map<String, String>> photoUrls(List<String> postIds) async {
    final all = await _allPhotos();
    if (postIds.isEmpty) return all;
    return {
      for (final id in postIds)
        if (all[id] case final url?) id: url,
    };
  }

  /// 自分の写真すべて。postId → URL。
  Map<String, String>? _cache;
  DateTime? _cachedAt;
  static const Duration _cacheTtl = Duration(minutes: 5);

  Future<Map<String, String>> _allPhotos({bool force = false}) async {
    final cached = _cache;
    final at = _cachedAt;
    if (!force &&
        cached != null &&
        at != null &&
        DateTime.now().difference(at) < _cacheTtl) {
      return cached;
    }

    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return const {};

    try {
      final snap = await _firestore
          .collection(_collection)
          .where('userId', isEqualTo: uid)
          .get();
      final out = <String, String>{};
      for (final d in snap.docs) {
        final url = d.data()['photoUrl'];
        if (url is String && url.isNotEmpty) out[d.id] = url;
      }
      _cache = out;
      _cachedAt = DateTime.now();
      await _log('自分の写真 ${out.length} 件を取得');
      return out;
    } catch (e) {
      // 失敗を黙って捨てると「写真が無い」と見分けが付かない。
      await _log('取得に失敗: $e');
      return cached ?? const {};
    }
  }

  /// Live Activity と同じログに残す。写真が出ない原因は実機でしか追えない。
  /// 画面側からも呼べるよう公開している。
  Future<void> log(String message) => _log(message);

  Future<void> _log(String message) async {
    if (kDebugMode) print('PostPhoto: $message');
    try {
      await const MethodChannel('com.fifteen.liveactivity')
          .invokeMethod('log', {'tag': 'postPhoto', 'message': message});
    } catch (_) {/* ログが出せなくても本体は続ける */}
  }

  /// 取得済みの写真を捨てる。次に見るとき取り直す。
  ///
  /// 投稿したあとにカレンダーへ戻るような、裏で増えている場面で呼ぶ。
  void invalidate() {
    _cache = null;
    _cachedAt = null;
  }

  /// 写真を消す。投稿の削除に合わせて呼ぶ。
  Future<void> remove(String postId) async {
    try {
      await _firestore.collection(_collection).doc(postId).delete();
      _cache = null;
    } catch (e) {
      if (kDebugMode) print('PostPhotoService.remove error: $e');
    }
  }
}

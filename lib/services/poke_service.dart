import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../models/group_model.dart';
import '../utils/app_log.dart';
import 'music_memory_cycle_service.dart';

/// 自分に届いたつつき 1 件。
class PokeEntry {
  final String fromUid;
  final String fromName;
  final String groupId;
  final String groupName;
  final DateTime createdAt;

  const PokeEntry({
    required this.fromUid,
    required this.fromName,
    required this.groupId,
    required this.groupName,
    required this.createdAt,
  });

  factory PokeEntry.fromMap(Map<String, dynamic> d) => PokeEntry(
        fromUid: (d['fromUid'] as String?) ?? '',
        fromName: (d['fromName'] as String?) ?? '',
        groupId: (d['groupId'] as String?) ?? '',
        groupName: (d['groupName'] as String?) ?? '',
        createdAt: (d['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      );
}

/// つつく（未投稿のグループメンバーに投稿を促す）。
///
/// `pokes/{サイクルの鍵}_{送った人}_{送られた人}` を 1 枚置くだけ。同じ相手には
/// 1 サイクルに 1 回しか置けない（ルールで縛っている）。通知は Functions の
/// onPokeCreated / pokeDigestNotification が送る（初回は即時、以降はまとめて）。
class PokeService {
  PokeService._();
  static final PokeService instance = PokeService._();

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  static const String _collection = 'pokes';

  Future<String?> _cycleKey() async {
    final cycle = MusicMemoryCycleService();
    if (cycle.cycleKey == null) await cycle.fetchNotifiedAt();
    return cycle.cycleKey;
  }

  /// 今のサイクルに自分がつついた相手の uid。
  Future<Set<String>> pokedTargets(String uid) async {
    final key = await _cycleKey();
    if (key == null) return const {};
    try {
      final snap = await _firestore
          .collection(_collection)
          .where('fromUid', isEqualTo: uid)
          .where('cycleKey', isEqualTo: key)
          .get();
      return {for (final d in snap.docs) d.data()['toUid'] as String};
    } catch (e) {
      if (kDebugMode) AppLog.debug('PokeService.pokedTargets error: $e');
      return const {};
    }
  }

  /// [toUid] をつつく。置けたら true（もうつついていた等で弾かれたら false）。
  Future<bool> poke({
    required String fromUid,
    required String fromName,
    required String toUid,
    required GroupModel group,
  }) async {
    final key = await _cycleKey();
    if (key == null) return false;
    try {
      await _firestore.collection(_collection).doc('${key}_${fromUid}_$toUid').set({
        'fromUid': fromUid,
        'fromName': fromName,
        'toUid': toUid,
        'groupId': group.groupId,
        'groupName': group.name,
        'cycleKey': key,
        'notified': false,
        'createdAt': FieldValue.serverTimestamp(),
      });
      return true;
    } catch (e) {
      if (kDebugMode) AppLog.debug('PokeService.poke error: $e');
      return false;
    }
  }

  /// 今のサイクルに自分に届いたつつき。新しい順。
  Stream<List<PokeEntry>> watchPokesToMe(String uid, String cycleKey) {
    return _firestore
        .collection(_collection)
        .where('toUid', isEqualTo: uid)
        .where('cycleKey', isEqualTo: cycleKey)
        .snapshots()
        .map((snap) => snap.docs.map((d) => PokeEntry.fromMap(d.data())).toList()
          ..sort((a, b) => b.createdAt.compareTo(a.createdAt)))
        .handleError((Object e) {
      if (kDebugMode) AppLog.debug('PokeService.watchPokesToMe error: $e');
    });
  }
}

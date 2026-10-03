import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import 'now_playing_service.dart';

/// 「今 Apple Music で聴いている曲」を友達に見せるための共有。
///
/// ## 取れないものと、取れるもの
/// 友達の端末で何が鳴っているかを直接知る API は無い（Apple Music にも
/// Spotify にも無い）。分かるのは**自分の端末の再生状態**だけ。
/// そこで各自が自分の now playing を Firestore に書き、友達はそれを読む。
///
/// つまり「今」は厳密には「その人の端末が最後に報告した時点」。古い情報を
/// 「今聴いている」として出すと嘘になるので、[freshness] を過ぎたものは
/// 聴いていない扱いにする。
///
/// 書き込みはアプリを開いたときに加えて、バックグラウンド更新からも行う
/// （[BackgroundRefreshService]）。
class NowPlayingShareService {
  NowPlayingShareService._();
  static final NowPlayingShareService instance = NowPlayingShareService._();

  static const String _collection = 'now_playing';

  /// これより古い報告は「聴いていない」とみなす。
  ///
  /// iOS のバックグラウンド更新は OS の裁量で、間隔が開くことがある。
  /// 短くしすぎると大半が「聴いていません」になり、長くすると何時間も前の曲を
  /// 「今」と言うことになる。その折り合いで 30 分にしている。
  static const Duration freshness = Duration(minutes: 30);

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// 自分の再生状態を書き込む。再生していなければ「停止」として書く。
  ///
  /// 書かずに黙っていると、友達側には前の曲が残り続けてしまう。
  Future<void> publish() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    try {
      // アートワークは重いので取らない（ウィジェットには曲名だけ渡す）。
      final np = await NowPlayingService().getNowPlaying(includeArtwork: false);
      final playing = np != null && np.isPlaying && np.title.isNotEmpty;

      await _firestore.collection(_collection).doc(uid).set({
        'isPlaying': playing,
        'trackName': playing ? np.title : null,
        'artistName': playing ? np.artist : null,
        'storeId': playing ? np.storeId : null,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      if (kDebugMode) print('NowPlayingShare.publish error: $e');
    }
  }

  /// 友達たちの再生状態を読む。[freshness] を過ぎたものは返さない。
  ///
  /// 返すのは uid → 曲。聴いていない人・報告が古い人は含まれない。
  Future<Map<String, NowPlayingEntry>> fetch(List<String> uids) async {
    if (uids.isEmpty) return const {};

    final cutoff = DateTime.now().subtract(freshness);
    final out = <String, NowPlayingEntry>{};

    // whereIn は 30 件まで。
    for (var i = 0; i < uids.length; i += 30) {
      final chunk = uids.skip(i).take(30).toList();
      try {
        final snap = await _firestore
            .collection(_collection)
            .where(FieldPath.documentId, whereIn: chunk)
            .get();
        for (final doc in snap.docs) {
          final d = doc.data();
          if (d['isPlaying'] != true) continue;

          final at = (d['updatedAt'] as Timestamp?)?.toDate();
          if (at == null || at.isBefore(cutoff)) continue;

          final name = d['trackName'];
          if (name is! String || name.isEmpty) continue;

          out[doc.id] = NowPlayingEntry(
            trackName: name,
            artistName: d['artistName'] is String ? d['artistName'] as String : '',
            storeId: d['storeId'] is String ? d['storeId'] as String : null,
            updatedAt: at,
          );
        }
      } catch (e) {
        if (kDebugMode) print('NowPlayingShare.fetch chunk failed: $e');
      }
    }
    return out;
  }
}

/// 友達 1 人ぶんの再生状態。
class NowPlayingEntry {
  final String trackName;
  final String artistName;

  /// Apple Music のカタログ ID。アートワークを引くのに使う。
  final String? storeId;

  final DateTime updatedAt;

  const NowPlayingEntry({
    required this.trackName,
    required this.artistName,
    required this.storeId,
    required this.updatedAt,
  });
}

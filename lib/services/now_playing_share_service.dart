import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import 'now_playing_service.dart';
import '../utils/app_log.dart';

/// 「今 Apple Music で聴いている曲」を友達に見せるための共有。
///
/// ## 取れないものと、取れるもの
/// 友達の端末で何が鳴っているかを直接知る API は無い（Apple Music にも
/// Spotify にも無い）。分かるのは**自分の端末の再生状態**だけ。
/// そこで各自が自分の now playing を Firestore に書き、友達はそれを読む。
///
/// つまり「今」は厳密には「その人の端末が最後に報告した時点」。古い情報を
/// 「今聴いている」として出すと嘘になるので、[freshness] を過ぎたものは
/// 「今」とは言わず、「◯時間前に聴いた」として扱う。
///
/// 止めたあとも直前の曲は `last*` に残す（`trackName` などは再生中だけ）。
/// これで「今」聴いている人がいなくても、最近聴いた曲を出せる。
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

  /// 最近聴いた曲として出す範囲。これより前のものは出さない。
  static const Duration recentWindow = Duration(hours: 24);

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

      // merge で書き、止めたときは last* を消さずに残す。
      await _firestore.collection(_collection).doc(uid).set({
        'isPlaying': playing,
        'trackName': playing ? np.title : null,
        'artistName': playing ? np.artist : null,
        'storeId': playing ? np.storeId : null,
        'updatedAt': FieldValue.serverTimestamp(),
        if (playing) ...{
          'lastTrackName': np.title,
          'lastArtistName': np.artist,
          'lastStoreId': np.storeId,
          'lastPlayedAt': FieldValue.serverTimestamp(),
        },
      }, SetOptions(merge: true));
    } catch (e) {
      if (kDebugMode) AppLog.debug('NowPlayingShare.publish error: $e');
    }
  }

  /// 友達たちの今の曲、または最近聴いた曲を読む。
  ///
  /// 返すのは uid → 曲。[recentWindow] より前にしか聴いていない人は含まれない。
  Future<Map<String, NowPlayingEntry>> fetch(List<String> uids) async {
    if (uids.isEmpty) return const {};

    final now = DateTime.now();
    final nowCutoff = now.subtract(freshness);
    final recentCutoff = now.subtract(recentWindow);
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
          final entry = _entryFrom(doc.data(), nowCutoff);
          if (entry == null || entry.playedAt.isBefore(recentCutoff)) continue;
          out[doc.id] = entry;
        }
      } catch (e) {
        if (kDebugMode) AppLog.debug('NowPlayingShare.fetch chunk failed: $e');
      }
    }
    return out;
  }

  /// 1 人ぶんの文書から曲を取り出す。
  ///
  /// 再生中で報告が新しければ「今」。そうでなければ最後に聴いた曲と時刻。
  /// last* が無い文書（古いアプリが書いたもの）は、再生中の報告だけを使う。
  static NowPlayingEntry? _entryFrom(
      Map<String, dynamic> d, DateTime nowCutoff) {
    String? str(String key) {
      final v = d[key];
      return v is String && v.isNotEmpty ? v : null;
    }

    final updatedAt = (d['updatedAt'] as Timestamp?)?.toDate();
    final playingName = str('trackName');
    if (d['isPlaying'] == true && playingName != null && updatedAt != null) {
      return NowPlayingEntry(
        trackName: playingName,
        artistName: str('artistName') ?? '',
        storeId: str('storeId'),
        playedAt: updatedAt,
        isNow: !updatedAt.isBefore(nowCutoff),
      );
    }

    final lastName = str('lastTrackName');
    final lastAt = (d['lastPlayedAt'] as Timestamp?)?.toDate();
    if (lastName == null || lastAt == null) return null;
    return NowPlayingEntry(
      trackName: lastName,
      artistName: str('lastArtistName') ?? '',
      storeId: str('lastStoreId'),
      playedAt: lastAt,
      isNow: false,
    );
  }
}

/// 友達 1 人ぶんの再生状態。
class NowPlayingEntry {
  final String trackName;
  final String artistName;

  /// Apple Music のカタログ ID。アートワークを引くのに使う。
  final String? storeId;

  /// 最後に聴いていたと分かっている時刻。
  final DateTime playedAt;

  /// 今まさに聴いている（報告が [NowPlayingShareService.freshness] 以内）。
  final bool isNow;

  const NowPlayingEntry({
    required this.trackName,
    required this.artistName,
    required this.storeId,
    required this.playedAt,
    required this.isNow,
  });
}

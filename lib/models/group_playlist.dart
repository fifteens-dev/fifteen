import 'package:cloud_firestore/cloud_firestore.dart';

import 'track_model.dart';

/// グループの週のプレイリスト（groups/{groupId}/playlists/{weekKey}）。
///
/// 毎週月曜 21:00 の通知のあと、Functions（weeklyGroupPlaylists）が先週
/// （月曜 21:00〜今日の 21:00）にメンバーが投稿した曲をまとめて作る。
/// 週の途中で抜けた人の曲も入る。
class GroupPlaylist {
  final String groupId;

  /// 週の始まりの月曜（'YYYY-MM-DD'）。ドキュメント ID と同じ。
  final String weekKey;

  /// 週の終わりの日曜（'YYYY-MM-DD'）。
  final String endKey;

  /// 届いた時刻（翌週の月曜の 21:00 の通知）。
  final DateTime deliveredAt;

  /// 届いた時点のメンバーの人数。
  final int memberCount;
  final int dayCount;
  final List<GroupPlaylistTrack> tracks;

  const GroupPlaylist({
    required this.groupId,
    required this.weekKey,
    required this.endKey,
    required this.deliveredAt,
    required this.memberCount,
    required this.dayCount,
    required this.tracks,
  });

  int get trackCount => tracks.length;

  /// 次の週のプレイリストと入れ替わる時刻（届いてから 7 日後の 21:00）。
  DateTime get replacedAt => deliveredAt.add(const Duration(days: 7));

  /// 「10/19-10/25」。
  String get rangeLabel => '${_md(weekKey)}-${_md(endKey)}';

  static String _md(String key) {
    final p = key.split('-');
    if (p.length != 3) return key;
    return '${int.parse(p[1])}/${int.parse(p[2])}';
  }

  factory GroupPlaylist.fromFirestore(String groupId, DocumentSnapshot doc) {
    final data = (doc.data() as Map<String, dynamic>?) ?? {};
    final delivered = data['deliveredAt'];
    return GroupPlaylist(
      groupId: groupId,
      weekKey: data['weekKey']?.toString() ?? doc.id,
      endKey: data['endKey']?.toString() ?? '',
      deliveredAt: delivered is Timestamp ? delivered.toDate() : DateTime.now(),
      memberCount: (data['memberCount'] as num?)?.toInt() ?? 0,
      dayCount: (data['dayCount'] as num?)?.toInt() ?? 7,
      tracks: [
        for (final t in data['tracks'] as List? ?? const [])
          if (t is Map<String, dynamic>) GroupPlaylistTrack.fromMap(t),
      ],
    );
  }
}

/// プレイリストの 1 曲（元の投稿の写し）。
class GroupPlaylistTrack {
  final String postId;
  final String userId;
  final String username;
  final String? userIconUrl;

  /// 投稿したサイクルの日（21:00 に始まった日、'YYYY-MM-DD'）。
  final String cycleKey;
  final DateTime createdAt;

  /// 投稿に写真があったか（写真そのものは post_photos から引く）。
  final bool hasPhoto;
  final TrackModel track;

  const GroupPlaylistTrack({
    required this.postId,
    required this.userId,
    required this.username,
    required this.userIconUrl,
    required this.cycleKey,
    required this.createdAt,
    required this.hasPhoto,
    required this.track,
  });

  factory GroupPlaylistTrack.fromMap(Map<String, dynamic> m) {
    final at = m['createdAt'];
    return GroupPlaylistTrack(
      postId: m['postId']?.toString() ?? '',
      userId: m['userId']?.toString() ?? '',
      username: m['username']?.toString() ?? '',
      userIconUrl: m['userIconUrl']?.toString(),
      cycleKey: m['cycleKey']?.toString() ?? '',
      createdAt: at is Timestamp ? at.toDate() : DateTime.now(),
      hasPhoto: m['hasPhoto'] == true,
      track: TrackModel.fromMap(
        Map<String, dynamic>.from(m['track'] as Map? ?? const {}),
      ),
    );
  }
}

/// 「その時点でよく聴いていた音楽」の記録。
///
/// プロフィール画面の top artists / recent choice と同じ中身で、投稿カードの
/// 裏面にも出す。カード裏面は**投稿した時点**を見せるものなので、投稿時に
/// この形で Firestore へ書き込んで固定する（あとから集計し直さない）。
class ProfileSnapshot {
  /// よく聴いているアーティスト（多い順、最大 3）。
  final List<SnapshotArtist> topArtists;

  /// 直近に選んだ曲（新しい順、最大 3）。
  final List<SnapshotTrack> recentTracks;

  const ProfileSnapshot({
    required this.topArtists,
    required this.recentTracks,
  });

  static const empty = ProfileSnapshot(topArtists: [], recentTracks: []);

  bool get isEmpty => topArtists.isEmpty && recentTracks.isEmpty;

  Map<String, dynamic> toMap() => {
        'topArtists': [for (final a in topArtists) a.toMap()],
        'recentTracks': [for (final t in recentTracks) t.toMap()],
      };

  /// Firestore から読む。欠けていても落ちないよう、型が違う要素は捨てる。
  static ProfileSnapshot? fromMap(Object? raw) {
    if (raw is! Map) return null;
    return ProfileSnapshot(
      topArtists: [
        for (final a in _list(raw['topArtists']))
          if (SnapshotArtist.fromMap(a) case final v?) v,
      ],
      recentTracks: [
        for (final t in _list(raw['recentTracks']))
          if (SnapshotTrack.fromMap(t) case final v?) v,
      ],
    );
  }

  static List<dynamic> _list(Object? v) => v is List ? v : const [];
}

/// top artists の 1 人。
class SnapshotArtist {
  final String name;

  /// アーティスト画像。投稿時に解決しておく（表示のたびに Spotify を
  /// 叩かないため）。取れなければ null。
  final String? imageUrl;

  const SnapshotArtist({required this.name, this.imageUrl});

  Map<String, dynamic> toMap() => {'name': name, 'imageUrl': imageUrl};

  static SnapshotArtist? fromMap(Object? raw) {
    if (raw is! Map) return null;
    final name = raw['name'];
    if (name is! String || name.isEmpty) return null;
    final url = raw['imageUrl'];
    return SnapshotArtist(name: name, imageUrl: url is String ? url : null);
  }
}

/// recent choice の 1 曲。
class SnapshotTrack {
  final String trackName;
  final String artistName;
  final String albumImageUrl;

  const SnapshotTrack({
    required this.trackName,
    required this.artistName,
    required this.albumImageUrl,
  });

  Map<String, dynamic> toMap() => {
        'trackName': trackName,
        'artistName': artistName,
        'albumImageUrl': albumImageUrl,
      };

  static SnapshotTrack? fromMap(Object? raw) {
    if (raw is! Map) return null;
    final name = raw['trackName'];
    if (name is! String) return null;
    return SnapshotTrack(
      trackName: name,
      artistName: raw['artistName'] is String ? raw['artistName'] as String : '',
      albumImageUrl:
          raw['albumImageUrl'] is String ? raw['albumImageUrl'] as String : '',
    );
  }
}

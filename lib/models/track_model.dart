/// 音楽トラック情報を表すモデル
class TrackModel {
  final String trackId;
  final String trackName;
  final String artistName;
  final String albumImageUrl;
  final String? trackUrl; // 音楽ファイルのURL（将来的に実装）
  final String? previewUrl; // プレビューURL（将来的に実装）
  final String? lyrics; // 歌詞
  final double? tempo; // テンポ（BPM）
  final String? spotifyArtistId; // SpotifyアーティストID（アイコン・フォロワー数の正確な取得用）

  TrackModel({
    required this.trackId,
    required this.trackName,
    required this.artistName,
    required this.albumImageUrl,
    this.trackUrl,
    this.previewUrl,
    this.lyrics,
    this.tempo,
    this.spotifyArtistId,
  });

  // Mapから作成
  factory TrackModel.fromMap(Map<String, dynamic> map) {
    return TrackModel(
      trackId: map['trackId'] ?? '',
      trackName: map['trackName'] ?? '',
      artistName: map['artistName'] ?? '',
      albumImageUrl: map['albumImageUrl'] ?? '',
      trackUrl: map['trackUrl'],
      previewUrl: map['previewUrl'],
      lyrics: map['lyrics'],
      tempo: (map['tempo'] as num?)?.toDouble(),
      spotifyArtistId: map['spotifyArtistId']?.toString(),
    );
  }

  // Mapに変換
  Map<String, dynamic> toMap() {
    return {
      'trackId': trackId,
      'trackName': trackName,
      'artistName': artistName,
      'albumImageUrl': albumImageUrl,
      'trackUrl': trackUrl,
      'previewUrl': previewUrl,
      'lyrics': lyrics,
      'tempo': tempo,
      'spotifyArtistId': spotifyArtistId,
    };
  }

  // コピーを作成
  TrackModel copyWith({
    String? trackId,
    String? trackName,
    String? artistName,
    String? albumImageUrl,
    String? trackUrl,
    String? previewUrl,
    String? lyrics,
    double? tempo,
    String? spotifyArtistId,
  }) {
    return TrackModel(
      trackId: trackId ?? this.trackId,
      trackName: trackName ?? this.trackName,
      artistName: artistName ?? this.artistName,
      albumImageUrl: albumImageUrl ?? this.albumImageUrl,
      trackUrl: trackUrl ?? this.trackUrl,
      previewUrl: previewUrl ?? this.previewUrl,
      lyrics: lyrics ?? this.lyrics,
      tempo: tempo ?? this.tempo,
      spotifyArtistId: spotifyArtistId ?? this.spotifyArtistId,
    );
  }
}

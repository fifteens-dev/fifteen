/// 音楽サービスの種類
enum MusicServiceType {
  spotify,
  appleMusic,
  none,
}

/// 音楽サービスの拡張メソッド
extension MusicServiceTypeExtension on MusicServiceType {
  String get displayName {
    switch (this) {
      case MusicServiceType.spotify:
        return 'Spotify';
      case MusicServiceType.appleMusic:
        return 'Apple Music';
      case MusicServiceType.none:
        return '未連携';
    }
  }

  String get iconPath {
    switch (this) {
      case MusicServiceType.spotify:
        return 'assets/icons/Spotify.png';
      case MusicServiceType.appleMusic:
        return 'assets/icons/Apple_Music.png';
      case MusicServiceType.none:
        return '';
    }
  }
}

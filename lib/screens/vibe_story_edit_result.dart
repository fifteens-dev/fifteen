import '../services/lyrics_service.dart';

/// Vibe ストーリープレビュー → MusicTrim → LyricsCardSelection と辿った編集チェーンが
/// プレビューへ戻ってくるときに持ち帰る値のセット。
///
/// カード位置 (cardCenter/Scale/Rotation) はプレビュー画面側で pan/pinch 操作されるので
/// この result には含めない。歌詞カードのレイアウト・アルバムアート透明度・音楽再生位置は
/// 編集チェーンで確定するため入っている。
class VibeStoryEditResult {
  final int audioStartMs;
  final int audioDurationSec;
  final int selectedLayoutIndex;
  final double albumArtOpacity;
  final LyricsData? lyricsData;

  const VibeStoryEditResult({
    required this.audioStartMs,
    required this.audioDurationSec,
    required this.selectedLayoutIndex,
    required this.albumArtOpacity,
    required this.lyricsData,
  });
}

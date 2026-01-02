import 'package:flutter/material.dart';
import '../../models/track_model.dart';

/// 歌詞カードレイアウトの種類
enum LyricsCardLayoutType {
  standard, // レイアウト1: 歌詞 + トラック情報
  largeAlbumArt, // レイアウト2: アルバムアートワーク大
  horizontalBar, // レイアウト3: 横長トラック情報バー
  albumArtOnly, // レイアウト4: アルバムアートワークのみ
  musicPlayer, // レイアウト5: 音楽プレイヤーUI
}

/// 歌詞カードレイアウト共通ウィジェット
/// 投稿フロー全体で使用される5種類のレイアウトを提供
class LyricsCardLayout extends StatelessWidget {
  final LyricsCardLayoutType layoutType;
  final TrackModel track;
  final String? lyricsText; // オプション：歌詞テキスト

  const LyricsCardLayout({
    super.key,
    required this.layoutType,
    required this.track,
    this.lyricsText,
  });

  /// レイアウトタイプからインデックスを取得
  static int getLayoutIndex(LyricsCardLayoutType type) {
    return type.index;
  }

  /// インデックスからレイアウトタイプを取得
  static LyricsCardLayoutType getLayoutType(int index) {
    return LyricsCardLayoutType.values[index];
  }

  @override
  Widget build(BuildContext context) {
    switch (layoutType) {
      case LyricsCardLayoutType.standard:
        return _buildStandardLayout();
      case LyricsCardLayoutType.largeAlbumArt:
        return _buildLargeAlbumArtLayout();
      case LyricsCardLayoutType.horizontalBar:
        return _buildHorizontalBarLayout();
      case LyricsCardLayoutType.albumArtOnly:
        return _buildAlbumArtOnlyLayout();
      case LyricsCardLayoutType.musicPlayer:
        return _buildMusicPlayerLayout();
    }
  }

  /// レイアウト1：標準（歌詞 + トラック情報）
  Widget _buildStandardLayout() {
    return Container(
      width: 196,
      height: 126,
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.52),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        children: [
          // 上部：歌詞エリア
          Expanded(
            flex: 60,
            child: Container(
              decoration: const BoxDecoration(
                color: Color.fromRGBO(0, 0, 0, 0.29),
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(10),
                  topRight: Radius.circular(10),
                ),
              ),
              padding: const EdgeInsets.all(11),
              child: Center(
                child: Text(
                  lyricsText ?? '今宵涙こらえて奏でる愛のSerenade\n今も忘れない恋の歌',
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                    height: 1.2,
                  ),
                  textAlign: TextAlign.left,
                ),
              ),
            ),
          ),

          // 下部：トラック情報エリア
          Expanded(
            flex: 40,
            child: Container(
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.52),
                borderRadius: const BorderRadius.only(
                  bottomLeft: Radius.circular(10),
                  bottomRight: Radius.circular(10),
                ),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
              child: Row(
                children: [
                  // アルバムアートワーク
                  _buildAlbumArt(width: 36, height: 40, borderRadius: 3),
                  const SizedBox(width: 10),
                  // 楽曲情報
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          track.trackName,
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: Colors.white,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          track.artistName,
                          style: const TextStyle(
                            fontSize: 7,
                            color: Colors.white,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// レイアウト2：アルバムアートワーク大
  Widget _buildLargeAlbumArtLayout() {
    return SizedBox(
      width: 105,
      height: 147,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // アルバムアートワーク
          _buildAlbumArt(width: 105, height: 115, borderRadius: 3),
          const SizedBox(height: 5), // 7から5に減らして余裕を持たせる
          // トラック情報
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                track.trackName,
                style: const TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                  height: 1.2, // 1.388から1.2に減らして高さを抑える
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
              ),
              Text(
                track.artistName,
                style: const TextStyle(
                  fontSize: 7,
                  color: Colors.white,
                  height: 1.2, // 1.5から1.2に減らして高さを抑える
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// レイアウト3：横長トラック情報バー
  Widget _buildHorizontalBarLayout() {
    return Container(
      width: 172,
      height: 42,
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.52),
        borderRadius: BorderRadius.circular(7),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      child: Row(
        children: [
          // アルバムアートワーク
          _buildAlbumArt(width: 33, height: 35, borderRadius: 3),
          const SizedBox(width: 9),
          // トラック情報
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  track.trackName,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  track.artistName,
                  style: const TextStyle(
                    fontSize: 7,
                    color: Colors.white,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// レイアウト4：アルバムアートワークのみ
  Widget _buildAlbumArtOnlyLayout() {
    return _buildAlbumArt(width: 140, height: 152, borderRadius: 2);
  }

  /// レイアウト5：音楽プレイヤーUI
  Widget _buildMusicPlayerLayout() {
    return Container(
      width: 130,
      height: 61,
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.5),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Stack(
        children: [
          // アルバムアートワーク
          Positioned(
            left: 11,
            top: 8,
            child: _buildAlbumArt(width: 41, height: 45, borderRadius: 3),
          ),
          // トラック情報
          Positioned(
            left: 60,
            top: 6,
            right: 6,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  track.trackName,
                  style: const TextStyle(
                    fontSize: 6,
                    color: Colors.white,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  track.artistName,
                  style: const TextStyle(
                    fontSize: 5,
                    color: Color(0xFF999999),
                    height: 0.957,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          // 再生コントロール
          Positioned(
            left: 66,
            top: 28,
            child: Row(
              children: [
                // スキップバック
                Transform.rotate(
                  angle: 3.14159, // 180度回転
                  child: const Icon(
                    Icons.skip_next,
                    color: Colors.white,
                    size: 10,
                  ),
                ),
                const SizedBox(width: 7),
                // 一時停止ボタン
                Row(
                  children: [
                    Container(
                      width: 2.948,
                      height: 9.579,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(0.4),
                      ),
                    ),
                    const SizedBox(width: 1),
                    Container(
                      width: 2.948,
                      height: 9.579,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(0.4),
                      ),
                    ),
                  ],
                ),
                const SizedBox(width: 13),
                // スキップフォワード
                const Icon(
                  Icons.skip_next,
                  color: Colors.white,
                  size: 10,
                ),
              ],
            ),
          ),
          // 再生バー
          Positioned(
            left: 61,
            bottom: 14,
            child: Stack(
              children: [
                // 背景バー
                Container(
                  width: 63,
                  height: 3,
                  decoration: BoxDecoration(
                    color: const Color(0xFF474747).withOpacity(0.8),
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
                // 進行バー
                Container(
                  width: 42.195,
                  height: 3,
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.8),
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(3),
                      bottomLeft: Radius.circular(3),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// アルバムアート共通ウィジェット
  Widget _buildAlbumArt({
    required double width,
    required double height,
    required double borderRadius,
  }) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: const Color(0xFF9F9F9F),
        borderRadius: BorderRadius.circular(borderRadius),
      ),
      child: track.albumImageUrl.isNotEmpty
          ? ClipRRect(
              borderRadius: BorderRadius.circular(borderRadius),
              child: Image.network(
                track.albumImageUrl,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) {
                  return Container(
                    color: const Color(0xFF9F9F9F),
                  );
                },
              ),
            )
          : null,
    );
  }
}

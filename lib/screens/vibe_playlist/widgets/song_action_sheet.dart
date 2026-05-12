import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import '../../../models/vibe_ranking_item.dart';

/// 曲行タップで表示されるアクションシート（Figma 3870:6805）
/// - 上部: 曲情報バー（アルバム / 曲名 / アーティスト / Vibe追加カウント / +保存）
/// - 中段: アクションボタン2つ
/// - 下部: その楽曲を使った投稿写真の3列グリッド（スクロール）
class SongActionSheet extends StatefulWidget {
  final VibeRankingItem item;
  final List<String> photos;
  final VoidCallback onPlayFull;
  final VoidCallback onAddToVibe;
  final VoidCallback onSave;
  final bool isSaved;

  const SongActionSheet({
    super.key,
    required this.item,
    required this.photos,
    required this.onPlayFull,
    required this.onAddToVibe,
    required this.onSave,
    this.isSaved = false,
  });

  @override
  State<SongActionSheet> createState() => _SongActionSheetState();
}

class _SongActionSheetState extends State<SongActionSheet> {
  late bool _isSaved;

  @override
  void initState() {
    super.initState();
    _isSaved = widget.isSaved;
  }

  @override
  Widget build(BuildContext context) {
    final bottomPadding = MediaQuery.of(context).padding.bottom;
    final screenH = MediaQuery.of(context).size.height;
    // モーダル全体の高さ = 画面の85%（残り15%は背景の曲リストが見える余白）
    final modalHeight = screenH * 0.85;

    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF313131),
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(11),
          topRight: Radius.circular(11),
        ),
      ),
      child: SizedBox(
        height: modalHeight,
        child: Column(
          children: [
            // 固定ヘッダー（ハンドル + 曲情報バー + アクションボタン）
            // = top=9(handle) + 20+72(barまで) + 残り余白で 152 高さ
            SizedBox(
              height: 153,
              child: _buildHeader(),
            ),
            // 写真グリッド（3列、スクロール）
            Expanded(
              child: _buildPhotoGrid(bottomPadding),
            ),
          ],
        ),
      ),
    );
  }

  /// 写真3列グリッド（Figma: 各セル 133×178、左から left=0,134/135,269）
  /// 画面幅 402 想定。実機ではセルを画面幅に合わせて等分し、aspect 133:178 を維持。
  Widget _buildPhotoGrid(double bottomPadding) {
    if (widget.photos.isEmpty) {
      return Padding(
        padding: EdgeInsets.only(bottom: bottomPadding),
        child: const Center(
          child: Text(
            'まだこの曲で投稿された写真はありません',
            style: TextStyle(color: Color(0xFF858585), fontSize: 12),
          ),
        ),
      );
    }
    return GridView.builder(
      padding: EdgeInsets.only(
        left: 0,
        right: 0,
        top: 0,
        bottom: bottomPadding,
      ),
      physics: const ClampingScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        mainAxisSpacing: 1,
        crossAxisSpacing: 1,
        childAspectRatio: 133 / 178,
      ),
      itemCount: widget.photos.length,
      itemBuilder: (context, index) {
        return CachedNetworkImage(
          imageUrl: widget.photos[index],
          fit: BoxFit.cover,
          errorWidget: (_, __, ___) => Container(color: Colors.grey[900]),
        );
      },
    );
  }

  Widget _buildHeader() {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        // ドラッグハンドル（line133: 中央, 幅44, top=9 / 高さ4）
        Positioned(
          top: 9,
          left: 0,
          right: 0,
          child: Center(
            child: Container(
              width: 44,
              height: 4,
              decoration: BoxDecoration(
                color: const Color(0xFF6E6E6E),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
        ),
        // 曲情報バー（left=14, top=20, w=374, h=72, rounded=16）
        Positioned(
          left: 14,
          top: 20,
          right: 14,
          height: 72,
          child: Container(
            decoration: BoxDecoration(
              color: const Color(0xFF1F1F1F),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Stack(
              children: [
                // アルバム（left=8 top=8 size=56 rounded=7）
                Positioned(
                  left: 8,
                  top: 8,
                  width: 56,
                  height: 56,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(7),
                    child: CachedNetworkImage(
                      imageUrl: widget.item.track.albumImageUrl,
                      fit: BoxFit.cover,
                      errorWidget: (_, __, ___) => Container(
                        color: Colors.grey[800],
                        child:
                            const Icon(Icons.album, color: Colors.white54),
                      ),
                    ),
                  ),
                ),
                // 曲名（left=72 top=13 fontSize=13 bold）
                Positioned(
                  left: 72,
                  top: 13,
                  right: 60,
                  child: Text(
                    widget.item.track.trackName,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                      height: 1.0,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                // アーティスト（left=72 top=29 fontSize=11）
                Positioned(
                  left: 72,
                  top: 29,
                  right: 60,
                  child: Text(
                    widget.item.track.artistName,
                    style: const TextStyle(
                      fontSize: 11,
                      color: Colors.white,
                      height: 1.0,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                // Vibe追加カウント（left=72 top=46 fontSize=11 #858585）
                Positioned(
                  left: 72,
                  top: 46,
                  right: 60,
                  child: Text(
                    '🔥${widget.item.postCount}人がVibeにこの曲を追加',
                    style: const TextStyle(
                      fontSize: 11,
                      color: Color(0xFF858585),
                      letterSpacing: -0.22,
                      height: 1.0,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                // +保存（left=327 top=19 size=34）
                Positioned(
                  right: 13,
                  top: 19,
                  width: 34,
                  height: 34,
                  child: GestureDetector(
                    onTap: () {
                      setState(() => _isSaved = !_isSaved);
                      widget.onSave();
                    },
                    behavior: HitTestBehavior.opaque,
                    child: _isSaved
                        ? Stack(
                            alignment: Alignment.center,
                            children: [
                              Container(
                                width: 30,
                                height: 30,
                                decoration: const BoxDecoration(
                                  color: Colors.lightGreen,
                                  shape: BoxShape.circle,
                                ),
                              ),
                              Icon(Icons.check,
                                  size: 18, color: Colors.grey[700]),
                            ],
                          )
                        : const Icon(
                            Icons.add_circle_outline,
                            color: Colors.white,
                            size: 30,
                          ),
                  ),
                ),
              ],
            ),
          ),
        ),
        // 「楽曲をフルで聴く」（left=14 top=102 w=181 h=40 rounded=30 bg=#454545）
        Positioned(
          left: 14,
          top: 102,
          width: 181,
          height: 40,
          child: GestureDetector(
            onTap: widget.onPlayFull,
            child: Container(
              decoration: BoxDecoration(
                color: const Color(0xFF454545),
                borderRadius: BorderRadius.circular(30),
              ),
              alignment: Alignment.center,
              child: const Text(
                '楽曲をフルで聴く',
                style: TextStyle(
                  fontSize: 13,
                  color: Colors.white,
                  letterSpacing: -0.26,
                  height: 1.0,
                ),
              ),
            ),
          ),
        ),
        // 「楽曲をVibeに追加」（left=207 top=103 w=181 h=40 rounded=30 グラデ）
        //   Vibeアイコン枠 left=23 top=8 size=24（内部19×19）
        //   テキスト left=54 top=12 fontSize=13
        Positioned(
          left: 207,
          top: 103,
          width: 181,
          height: 40,
          child: GestureDetector(
            onTap: widget.onAddToVibe,
            child: Container(
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF1937EF), Color(0xFFFE1F56)],
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                ),
                borderRadius: BorderRadius.circular(30),
              ),
              child: Stack(
                children: [
                  Positioned(
                    left: 23,
                    top: 8,
                    width: 24,
                    height: 24,
                    child: Center(
                      child: Image.asset(
                        'assets/icons/Vibe.png',
                        width: 19,
                        height: 19,
                        fit: BoxFit.contain,
                        errorBuilder: (_, __, ___) => const Icon(
                            Icons.music_note,
                            color: Colors.white,
                            size: 19),
                      ),
                    ),
                  ),
                  const Positioned(
                    left: 54,
                    top: 12,
                    child: Text(
                      '楽曲をVibeに追加',
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.white,
                        letterSpacing: -0.26,
                        height: 1.0,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

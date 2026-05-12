import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../../../models/vibe_ranking_item.dart';

/// 曲リストタブの1行アイテム (Figma: 幅374, 高さ48)
///   album left=0 top=0 size=48 rounded=3
///   track name left=61 top=0 fontSize=12 letterSpacing=-0.12
///   artist name left=61 top=14 fontSize=10
///   count left=61 top=33 fontSize=10 color=#858585 letterSpacing=-0.2
///   add_circle left=307 top=14 size=20
///   post button left=334 top=4 size=40
class VibeSongListItem extends StatelessWidget {
  final VibeRankingItem item;

  /// 楽曲に紐づく投稿が保存済みか。投稿がない場合は false を渡す。
  final bool isSaved;

  /// アイテム全体タップ（楽曲モーダル表示）
  final VoidCallback onTap;

  /// 保存ボタンタップ。投稿が存在しない場合は null を渡して操作不可にする。
  final VoidCallback? onSaveTap;

  /// 投稿ボタンタップ（楽曲指定の投稿フローへ）
  final VoidCallback onPostTap;

  const VibeSongListItem({
    super.key,
    required this.item,
    required this.isSaved,
    required this.onTap,
    required this.onPostTap,
    this.onSaveTap,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        // 行全体タップ領域（モーダル起動）— 後続の Positioned 子（アイコン等）が前面に来るので
        // それらのタップは行モーダルより優先される
        Positioned.fill(
          child: GestureDetector(
            onTap: onTap,
            behavior: HitTestBehavior.opaque,
            child: const SizedBox.expand(),
          ),
        ),
        // アルバムアート（48×48, rounded=3）
        Positioned(
          left: 0,
          top: 0,
          width: 48,
          height: 48,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: CachedNetworkImage(
              imageUrl: item.track.albumImageUrl,
              width: 48,
              height: 48,
              imageBuilder: (context, imageProvider) => Container(
                decoration: BoxDecoration(
                  image: DecorationImage(
                    image: imageProvider,
                    fit: BoxFit.cover,
                  ),
                ),
              ),
              placeholder: (_, __) => const SizedBox.shrink(),
              errorWidget: (_, __, ___) => Container(
                color: const Color(0xFF121212),
                child: const Icon(Icons.album, color: Colors.white54, size: 24),
              ),
            ),
          ),
        ),
        // トラック名（left=61, top=0, fontSize=12）
        Positioned(
          left: 61,
          top: 0,
          right: 75,
          child: Text(
            item.track.trackName,
            style: const TextStyle(
              fontSize: 12,
              color: Colors.white,
              letterSpacing: -0.12,
              height: 1.2,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        // アーティスト名（left=61, top=15, fontSize=10）
        Positioned(
          left: 61,
          top: 15,
          right: 75,
          child: Text(
            item.track.artistName,
            style: const TextStyle(
              fontSize: 10,
              color: Colors.white,
              letterSpacing: -0.12,
              height: 1.2,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        // Vibe追加カウント（left=61, top=33, fontSize=10, #858585）
        Positioned(
          left: 61,
          top: 33,
          right: 75,
          child: Text(
            '🔥${item.postCount}人がVibeにこの曲を追加',
            style: const TextStyle(
              fontSize: 10,
              color: Color(0xFF858585),
              letterSpacing: -0.2,
              height: 1.0,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        // add_circle（left=307, top=14, size=20）
        Positioned(
          left: 307,
          top: 14,
          width: 20,
          height: 20,
          child: GestureDetector(
            onTap: onSaveTap,
            behavior: HitTestBehavior.opaque,
            child: isSaved
                ? Stack(
                    alignment: Alignment.center,
                    children: [
                      Container(
                        width: 20,
                        height: 20,
                        decoration: const BoxDecoration(
                          color: Colors.lightGreen,
                          shape: BoxShape.circle,
                        ),
                      ),
                      Icon(Icons.check, size: 14, color: Colors.grey[700]),
                    ],
                  )
                : const Icon(
                    Icons.add_circle_outline,
                    color: Colors.white,
                    size: 20,
                  ),
          ),
        ),
        // 投稿ボタン（left=334, top=4, size=40）
        // 既存ナビバーと同じ post_icon.svg を使用（28×28 white）
        // 仕様: その楽曲で投稿フロー（カード反転起点）を開始
        Positioned(
          left: 334,
          top: 4,
          width: 40,
          height: 40,
          child: GestureDetector(
            onTap: onPostTap,
            behavior: HitTestBehavior.opaque,
            child: Center(
              child: SvgPicture.asset(
                'assets/icons/post_icon.svg',
                width: 28,
                height: 28,
                colorFilter: const ColorFilter.mode(
                  Colors.white,
                  BlendMode.srcIn,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

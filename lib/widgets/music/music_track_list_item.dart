import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../models/track_model.dart';

/// 楽曲選択画面のリスト表示用トラックアイテムウィジェット
class MusicTrackListItem extends StatelessWidget {
  final TrackModel track;
  final bool isSelected;
  final VoidCallback onTap;

  const MusicTrackListItem({
    super.key,
    required this.track,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        height: 59,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        color: isSelected ? const Color(0xFF2A2A2A) : Colors.transparent,
        child: Row(
          children: [
            // アルバムアート
            ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: CachedNetworkImage(
                imageUrl: track.albumImageUrl,
                width: 47,
                height: 47,
                fit: BoxFit.cover,
                errorWidget: (context, url, error) {
                  return Container(
                    width: 47,
                    height: 47,
                    color: Colors.grey[800],
                    child: const Icon(
                      Icons.music_note,
                      color: Colors.white54,
                      size: 24,
                    ),
                  );
                },
              ),
            ),
            const SizedBox(width: 11),

            // 楽曲情報
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    track.trackName,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    track.artistName,
                    style: const TextStyle(
                      fontSize: 10,
                      color: Colors.white,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),

            // 選択ボタン
            Container(
              width: 19,
              height: 19,
              decoration: BoxDecoration(
                color: isSelected ? const Color(0xFF4CAF50) : Colors.transparent,
                shape: BoxShape.circle,
                border: Border.all(
                  color: isSelected
                      ? const Color(0xFF4CAF50)
                      : const Color(0xFF9F9F9F),
                  width: 2,
                ),
              ),
              child: isSelected
                  ? const Icon(
                      Icons.check,
                      color: Colors.white,
                      size: 12,
                    )
                  : null,
            ),
          ],
        ),
      ),
    );
  }
}

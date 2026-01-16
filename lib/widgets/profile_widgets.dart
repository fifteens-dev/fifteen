import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import '../models/post_model.dart';
import '../services/audio_player_service.dart';
import '../services/itunes_search_service.dart';
import '../screens/post_detail_screen.dart';

/// プロフィール画面で使用する共通ウィジェット

/// 統計アイテム（Tracks, Followers, Following）
class ProfileStatItem extends StatelessWidget {
  final String count;
  final String label;

  const ProfileStatItem({
    super.key,
    required this.count,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          count,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
        Text(
          label,
          style: const TextStyle(
            color: Color(0xFF919191),
            fontSize: 12,
          ),
        ),
      ],
    );
  }
}

/// 投稿グリッドアイテム
class ProfilePostGridItem extends StatelessWidget {
  final PostModel post;

  const ProfilePostGridItem({
    super.key,
    required this.post,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        // アルバムアートをタップした時は表面から表示して0.5秒後に自動反転
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => PostDetailScreen(
              post: post,
              autoFlipAfterDelay: true,
            ),
          ),
        );
      },
      child: Container(
        padding: const EdgeInsets.all(0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // アルバムアート
            AspectRatio(
              aspectRatio: 1,
              child: Container(
                margin: const EdgeInsets.all(0.5),
                decoration: BoxDecoration(
                  color: Colors.grey[800],
                  borderRadius: BorderRadius.circular(3),
                ),
                child: post.track.albumImageUrl.isNotEmpty
                    ? ClipRRect(
                        borderRadius: BorderRadius.circular(3),
                        child: Image.network(
                          post.track.albumImageUrl,
                          width: double.infinity,
                          height: double.infinity,
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) {
                            return const Icon(
                              Icons.album,
                              size: 50,
                              color: Colors.white54,
                            );
                          },
                        ),
                      )
                    : const Icon(
                        Icons.album,
                        size: 50,
                        color: Colors.white54,
                      ),
              ),
            ),
            // 曲名
            Padding(
              padding: const EdgeInsets.only(left: 6, top: 4),
              child: Text(
                post.track.trackName,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            // アーティスト名
            Padding(
              padding: const EdgeInsets.only(left: 6),
              child: Text(
                post.track.artistName,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 10,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            // 追加ボタン
            Padding(
              padding: const EdgeInsets.only(left: 6, top: 2),
              child: Container(
                width: 13,
                height: 13,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 1),
                ),
                child: const Icon(
                  Icons.add,
                  color: Colors.white,
                  size: 10,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// オーディオ再生ボタンと時間表示
class AudioPlayButton extends StatefulWidget {
  final PostModel post;
  final AudioPlayerService audioService;
  final Map<String, String> previewUrlCache;

  const AudioPlayButton({
    super.key,
    required this.post,
    required this.audioService,
    required this.previewUrlCache,
  });

  @override
  State<AudioPlayButton> createState() => _AudioPlayButtonState();
}

class _AudioPlayButtonState extends State<AudioPlayButton> {
  final ITunesSearchService _itunesService = ITunesSearchService();

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        StreamBuilder<PlayerState>(
          stream: widget.audioService.playerStateStream,
          builder: (context, snapshot) {
            final previewUrl = widget.previewUrlCache[widget.post.postId];
            final isThisTrackPlaying = previewUrl != null &&
                widget.audioService.isPlayingUrl(previewUrl);
            final isPaused = widget.audioService.isPaused;

            return GestureDetector(
              onTap: () async {
                if (isThisTrackPlaying) {
                  // 再生中の場合は一時停止
                  widget.audioService.pause();
                } else if (isPaused && previewUrl != null) {
                  // 一時停止中の場合は再開
                  widget.audioService.resume();
                } else {
                  // 停止中の場合は再生開始
                  String? urlToPlay = previewUrl;

                  // preview URLがまだ取得されていない場合は取得
                  if (urlToPlay == null) {
                    print(
                        '🍎 Fetching preview URL for ${widget.post.track.trackName}...');
                    urlToPlay = await _itunesService.getPreviewUrl(
                      trackName: widget.post.track.trackName,
                      artistName: widget.post.track.artistName,
                    );

                    if (urlToPlay != null) {
                      setState(() {
                        widget.previewUrlCache[widget.post.postId] = urlToPlay!;
                      });
                      print('✅ Preview URL obtained and cached');
                    } else {
                      print('❌ Failed to obtain preview URL');
                      return;
                    }
                  }

                  // 再生開始（ループ再生は自動的に有効）
                  await widget.audioService.playPreview(urlToPlay);
                }
              },
              child: Container(
                width: 50,
                height: 50,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: isThisTrackPlaying ? Colors.greenAccent : Colors.white,
                    width: 2,
                  ),
                ),
                child: Icon(
                  isThisTrackPlaying ? Icons.pause : Icons.play_arrow,
                  color: isThisTrackPlaying ? Colors.greenAccent : Colors.white,
                  size: 28,
                ),
              ),
            );
          },
        ),
        const SizedBox(height: 4),
        StreamBuilder<Duration>(
          stream: widget.audioService.positionStream,
          builder: (context, positionSnapshot) {
            return StreamBuilder<Duration?>(
              stream: widget.audioService.durationStream,
              builder: (context, durationSnapshot) {
                final duration = durationSnapshot.data;
                final position = positionSnapshot.data ?? Duration.zero;

                // 残り時間を計算
                final remaining = duration != null
                    ? duration - position
                    : const Duration(seconds: 30);

                // フォーマット
                final minutes = remaining.inMinutes;
                final seconds = remaining.inSeconds % 60;
                final timeText = '$minutes:${seconds.toString().padLeft(2, '0')}';

                return Text(
                  timeText,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                );
              },
            );
          },
        ),
      ],
    );
  }
}

/// 今日の楽曲カード
class TodaysTrackCard extends StatelessWidget {
  final PostModel post;
  final AudioPlayerService audioService;
  final Map<String, String> previewUrlCache;

  const TodaysTrackCard({
    super.key,
    required this.post,
    required this.audioService,
    required this.previewUrlCache,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: const Color(0xFF3C3C3C)),
        borderRadius: BorderRadius.circular(4),
        color: const Color(0xFF121212),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          children: [
            // アルバムアート（タップで投稿詳細を表面から表示して0.5秒後に自動反転）
            GestureDetector(
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => PostDetailScreen(
                      post: post,
                      autoFlipAfterDelay: true,
                    ),
                  ),
                );
              },
              child: Container(
                width: 60,
                height: 60,
                decoration: BoxDecoration(
                  color: Colors.grey[800],
                  borderRadius: BorderRadius.circular(4),
                ),
                child: post.track.albumImageUrl.isNotEmpty
                    ? ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: Image.network(
                          post.track.albumImageUrl,
                          width: 60,
                          height: 60,
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) {
                            return const Icon(
                              Icons.album,
                              size: 30,
                              color: Colors.white54,
                            );
                          },
                        ),
                      )
                    : const Icon(
                        Icons.album,
                        size: 30,
                        color: Colors.white54,
                      ),
              ),
            ),
            const SizedBox(width: 12),
            // 曲名とアーティスト
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    post.track.trackName,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    post.track.artistName,
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.7),
                      fontSize: 14,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            // 再生ボタンと時間
            AudioPlayButton(
              post: post,
              audioService: audioService,
              previewUrlCache: previewUrlCache,
            ),
          ],
        ),
      ),
    );
  }
}

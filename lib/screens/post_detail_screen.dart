import 'package:flutter/material.dart';
import '../models/post_model.dart';
import '../widgets/post_card.dart';
import '../services/audio_player_service.dart';

/// 投稿カード単体表示画面
class PostDetailScreen extends StatefulWidget {
  final PostModel post;
  final bool autoFlipAfterDelay; // trueの場合、0.5秒後に自動で裏返す

  const PostDetailScreen({
    super.key,
    required this.post,
    this.autoFlipAfterDelay = false, // デフォルトは自動反転なし
  });

  @override
  State<PostDetailScreen> createState() => _PostDetailScreenState();
}

class _PostDetailScreenState extends State<PostDetailScreen> {
  final AudioPlayerService _audioService = AudioPlayerService();

  @override
  void dispose() {
    // 画面を閉じる時に音楽を停止
    _audioService.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      body: SafeArea(
        child: Stack(
          children: [
            // 投稿カード（中央配置）
            Center(
              child: PostCard(
                post: widget.post,
                audioService: _audioService,
                autoFlipAfterDelay: widget.autoFlipAfterDelay,
              ),
            ),
            // 閉じるボタン（左上）
            Positioned(
              top: 16,
              left: 16,
              child: GestureDetector(
                onTap: () {
                  // 音楽を停止してから画面を閉じる
                  _audioService.stop();
                  Navigator.pop(context);
                },
                child: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.5),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.close,
                    color: Colors.white,
                    size: 24,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import '../models/post_model.dart';
import '../services/audio_player_service.dart';
import '../widgets/post_card.dart';

/// 投稿カード共有画面
/// カード1枚のみを表示し、画像として保存・シェアできる
class CardShareScreen extends StatefulWidget {
  final PostModel post;
  final String? currentUserId;
  final String? currentUserIconUrl;
  final bool isSaved;

  const CardShareScreen({
    super.key,
    required this.post,
    this.currentUserId,
    this.currentUserIconUrl,
    this.isSaved = false,
  });

  @override
  State<CardShareScreen> createState() => _CardShareScreenState();
}

class _CardShareScreenState extends State<CardShareScreen> {
  late final AudioPlayerService _audioService;
  final _cardKey = GlobalKey<PostCardState>();

  @override
  void initState() {
    super.initState();
    _audioService = AudioPlayerService();
  }

  @override
  void dispose() {
    _audioService.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      body: SafeArea(
        child: Column(
          children: [
            // ヘッダー
            SizedBox(
              height: 50,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    // 閉じるボタン（左）
                    IconButton(
                      icon: const Icon(Icons.close, color: Colors.white, size: 24),
                      onPressed: () => Navigator.pop(context),
                    ),

                    // 共有ボタン（右）
                    TextButton(
                      onPressed: () => _cardKey.currentState?.shareCard(),
                      child: const Text(
                        '共有',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // カード（タップで表裏反転）
            Expanded(
              child: Center(
                child: PostCard(
                  key: _cardKey,
                  post: widget.post,
                  currentUserId: null, // 共有ボタンを非表示にするため null
                  currentUserIconUrl: widget.currentUserIconUrl,
                  audioService: _audioService,
                  isSaved: widget.isSaved,
                  hideReactionCounts: true,
                  backSideEnabled: true,
                ),
              ),
            ),

            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}

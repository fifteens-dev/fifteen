import 'package:flutter/material.dart';
import '../models/post_model.dart';
import '../services/audio_player_service.dart';
import '../services/instagram_stories_service.dart';
import '../widgets/common/app_toast.dart';
import '../widgets/post_card.dart';

/// 投稿カード共有ボトムシートを表示
Future<void> showCardShareSheet(
  BuildContext context, {
  required PostModel post,
  String? currentUserId,
  String? currentUserIconUrl,
  bool isSaved = false,
}) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _CardShareSheet(
      post: post,
      currentUserId: currentUserId,
      currentUserIconUrl: currentUserIconUrl,
      isSaved: isSaved,
    ),
  );
}

class _CardShareSheet extends StatefulWidget {
  final PostModel post;
  final String? currentUserId;
  final String? currentUserIconUrl;
  final bool isSaved;

  const _CardShareSheet({
    required this.post,
    this.currentUserId,
    this.currentUserIconUrl,
    this.isSaved = false,
  });

  @override
  State<_CardShareSheet> createState() => _CardShareSheetState();
}

class _CardShareSheetState extends State<_CardShareSheet> {
  late final AudioPlayerService _audioService;
  final _cardKey = GlobalKey<PostCardState>();
  bool _isSharingInstagram = false;

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

  Future<void> _shareToInstagram() async {
    setState(() => _isSharingInstagram = true);
    try {
      final bytes = await _cardKey.currentState?.captureAsImage();
      if (!mounted) return;
      if (bytes == null) {
        AppToast.show(context, '画像の取得に失敗しました');
        return;
      }
      final success = await InstagramStoriesService.share(bytes, postId: widget.post.postId);
      if (!mounted) return;
      if (!success) {
        AppToast.show(context, 'Instagramが見つかりません');
      }
    } finally {
      if (mounted) setState(() => _isSharingInstagram = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomPadding = MediaQuery.of(context).padding.bottom;

    return Container(
      height: MediaQuery.of(context).size.height * 0.92,
      decoration: const BoxDecoration(
        color: Color(0xFF212327),
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(20),
          topRight: Radius.circular(20),
        ),
      ),
      child: Column(
        children: [
          // ドラッグハンドル
          Padding(
            padding: const EdgeInsets.only(top: 7),
            child: Container(
              width: 50,
              height: 3,
              decoration: BoxDecoration(
                color: const Color(0xFFD9D9D9),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),

          // ヘッダー
          Padding(
            padding: const EdgeInsets.only(left: 14, right: 14, top: 20),
            child: Stack(
              alignment: Alignment.center,
              children: [
                // キャンセル（左）
                Align(
                  alignment: Alignment.centerLeft,
                  child: GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: const Text(
                      'キャンセル',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: Color(0xFF99999B),
                        letterSpacing: -0.13,
                      ),
                    ),
                  ),
                ),
                // タイトル（中央）
                const Text(
                  '投稿を共有',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: Colors.white,
                    letterSpacing: -0.13,
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // 投稿カード（裏面から表示）
          // FittedBox で 363×645 を維持しながら利用可能スペースに収める
          Expanded(
            child: Center(
              child: FittedBox(
                fit: BoxFit.contain,
                child: PostCard(
                  key: _cardKey,
                  post: widget.post,
                  currentUserId: null,
                  currentUserIconUrl: widget.currentUserIconUrl,
                  audioService: _audioService,
                  isSaved: widget.isSaved,
                  hideReactionCounts: true,
                  backSideEnabled: true,
                  startFromBack: true,
                ),
              ),
            ),
          ),

          // 共有ボタン群
          Padding(
            padding: EdgeInsets.only(bottom: bottomPadding + 16, top: 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // 保存ボタン
                GestureDetector(
                  onTap: () => _cardKey.currentState?.shareCard(),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Image.asset(
                        'assets/icons/save_button.png',
                        width: 55,
                        height: 55,
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        '保存',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w500,
                          color: Colors.white,
                          letterSpacing: -0.1,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 32),
                // Instagramストーリーズボタン
                GestureDetector(
                  onTap: _isSharingInstagram ? null : _shareToInstagram,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _isSharingInstagram
                          ? const SizedBox(
                              width: 55,
                              height: 55,
                              child: Center(
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              ),
                            )
                          : Container(
                              width: 55,
                              height: 55,
                              decoration: BoxDecoration(
                                gradient: const LinearGradient(
                                  begin: Alignment.topRight,
                                  end: Alignment.bottomLeft,
                                  colors: [
                                    Color(0xFF833AB4),
                                    Color(0xFFFD1D1D),
                                    Color(0xFFF77737),
                                  ],
                                ),
                                borderRadius: BorderRadius.circular(14),
                              ),
                              child: const Icon(
                                Icons.camera_alt_rounded,
                                color: Colors.white,
                                size: 26,
                              ),
                            ),
                      const SizedBox(height: 4),
                      const Text(
                        'Instagram',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w500,
                          color: Colors.white,
                          letterSpacing: -0.1,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

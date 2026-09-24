import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:provider/provider.dart';
import '../constants/app_colors.dart';
import '../models/post_model.dart';
import '../providers/current_user_provider.dart';
import '../providers/post_ui_state.dart';
import '../providers/saved_items_provider.dart';
import '../widgets/post_card.dart';
import '../services/audio_player_service.dart';
import '../services/itunes_search_service.dart';
import '../services/post_service.dart';
import 'comment_screen.dart';

/// 投稿カード単体表示画面（通知タップ時など）
/// VibeTrackPostsScreen と同じ見え方・音楽挙動に統一
class PostDetailScreen extends StatefulWidget {
  final PostModel post;
  final String? currentUserId;
  final bool autoFlipAfterDelay;
  final bool disableInteractions;

  /// true のとき hasUserPostedOnDate チェックをスキップして常にカード裏面を表示
  /// ※ 通知タップ時は false を渡し、通常の投稿チェックを行うこと
  final bool alwaysShowBack;

  const PostDetailScreen({
    super.key,
    required this.post,
    this.currentUserId,
    this.autoFlipAfterDelay = false,
    this.disableInteractions = false,
    this.alwaysShowBack = false,
  });

  @override
  State<PostDetailScreen> createState() => _PostDetailScreenState();
}

class _PostDetailScreenState extends State<PostDetailScreen> {
  // VibeTrackPostsScreen と同じパターン: 画面側で音楽を管理
  final AudioPlayerService _audioService = AudioPlayerService();
  final ITunesSearchService _itunesService = ITunesSearchService();
  final PostService _postService = PostService();

  String? _previewUrl;

  // 再生リクエストの競合防止
  bool _playRequested = false;

  String get _currentUserId =>
      widget.currentUserId ?? FirebaseAuth.instance.currentUser?.uid ?? '';

  String? get _currentUserIconUrl =>
      context.read<CurrentUserProvider>().iconUrl;

  @override
  void initState() {
    super.initState();
    // VibeTrackPostsScreen と同様に開いた瞬間に音楽取得＆自動再生
    _fetchAndPlayMusic();
  }

  /// VibeTrackPostsScreen._playMusicForPage と同パターンで音楽を取得＆自動再生
  Future<void> _fetchAndPlayMusic() async {
    _playRequested = true;
    final post = widget.post;
    String? url;

    if (post.track.previewUrl != null && post.track.previewUrl!.isNotEmpty) {
      url = post.track.previewUrl;
    } else {
      final result = await _itunesService.getPreviewUrlWithArt(
        trackName: post.track.trackName,
        artistName: post.track.artistName,
      );
      if (!mounted) return;
      url = result?['previewUrl'];
    }

    if (!mounted || !_playRequested) return;

    if (url != null) {
      setState(() => _previewUrl = url);
      try {
        await _audioService.playPreview(
          url,
          startFrom: Duration(milliseconds: post.audioStartMs),
          durationSeconds: post.audioDurationSec,
        );
      } catch (_) {
        // 再生エラーは無視
      }
    }
  }

  Future<void> _handleSave() async {
    await SavedItemsProvider.togglePostWithToast(context, widget.post);
  }

  Future<void> _handleComment() async {
    // VibeTrackPostsScreen は音楽を継続したままコメント画面を表示
    await CommentScreen.show(context, post: widget.post);
  }

  @override
  void dispose() {
    _playRequested = false;
    _audioService.stopIfOwner(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, color: Colors.white),
          onPressed: () {
            _audioService.stop();
            Navigator.pop(context);
          },
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Text(
              widget.post.track.trackName,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: Colors.white,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            Text(
              widget.post.track.artistName,
              style: TextStyle(
                fontSize: 12,
                color: Colors.white.withValues(alpha: 0.7),
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
        centerTitle: true,
      ),
      body: Center(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: PostCard(
              post: context.watch<PostUIState>().getDisplayPost(
                    widget.post,
                    currentUserId: _currentUserId,
                    currentUserIconUrl: _currentUserIconUrl,
                  ),
              currentUserId: _currentUserId,
              currentUserIconUrl: _currentUserIconUrl,
              audioService: _audioService,
              // VibeTrackPostsScreen と同様に画面側で音楽を管理
              audioManagedExternally: true,
              externalPreviewUrl: _previewUrl,
              // 裏面は写真ではなくプロフィールになったので、投稿の
              // 有無で出し分ける理由がない。常に表面から。
              startFromBack: false,
              backSideEnabled: true, // 裏返し制限は廃止
              isSaved: context
                  .watch<SavedItemsProvider>()
                  .isPostOrTrackSaved(widget.post),
              disableInteractions: widget.disableInteractions,
              onLike: _currentUserId.isEmpty
                  ? () {}
                  : () => PostUIState.handleLike(
                        context: context,
                        post: widget.post,
                        userId: _currentUserId,
                        postService: _postService,
                      ),
              onReaction: _currentUserId.isEmpty
                  ? null
                  : (emoji) => PostUIState.handleReaction(
                        postId: widget.post.postId,
                        emoji: emoji,
                        userId: _currentUserId,
                        postService: _postService,
                      ),
              onComment: _handleComment,
              onAdd: _handleSave,
            ),
          ),
        ),
      ),
    );
  }
}

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../constants/app_colors.dart';
import '../models/post_model.dart';
import '../providers/post_ui_state.dart';
import '../services/audio_player_service.dart';
import '../widgets/post_card.dart';

/// Vibe ストーリーバーで1ユーザーをタップしたときに開く画面。
///
/// VibePlaylistScreen と同じ「縦スワイプの全画面 PageView」構造のシンプル版。
/// - 該当ユーザーの直近 24h の投稿（既にフィルタ済み）を渡す
/// - PostCard を1枚ずつページとして並べ、上下スワイプで次/前へ
/// - audience フィルタ（鍵投稿の可視性）は呼び出し元で済ませる
class VibeUserStoryScreen extends StatefulWidget {
  final List<PostModel> posts;
  final String currentUserId;
  final int initialIndex;
  final String? displayUsername;

  /// 閲覧者が今日投稿済みか。
  /// タイムラインと同じく「今日投稿していないと裏面が見れない」制限をここでも適用する。
  /// true なら全投稿の裏面が解放、false なら 1 度フリップした投稿のみ解放。
  final bool hasPostedToday;

  const VibeUserStoryScreen({
    super.key,
    required this.posts,
    required this.currentUserId,
    this.initialIndex = 0,
    this.displayUsername,
    this.hasPostedToday = false,
  });

  @override
  State<VibeUserStoryScreen> createState() => _VibeUserStoryScreenState();
}

class _VibeUserStoryScreenState extends State<VibeUserStoryScreen> {
  late final PageController _pageController;
  final AudioPlayerService _audioService = AudioPlayerService();
  int _currentIndex = 0;

  /// 一度裏面を見た postId の永続化セット（SharedPreferences）。
  /// ホーム画面と同じキー `revealed_posts_{uid}` を共有し、整合性を保つ。
  Set<String> _revealedPostIds = {};

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex.clamp(0, widget.posts.length - 1);
    _pageController = PageController(initialPage: _currentIndex);
    _loadRevealedPostIds();
  }

  Future<void> _loadRevealedPostIds() async {
    if (widget.currentUserId.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    final ids = prefs.getStringList('revealed_posts_${widget.currentUserId}') ??
        const <String>[];
    if (!mounted) return;
    setState(() => _revealedPostIds = ids.toSet());
  }

  Future<void> _markPostRevealed(String postId) async {
    if (_revealedPostIds.contains(postId)) return;
    setState(() => _revealedPostIds.add(postId));
    if (widget.currentUserId.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
      'revealed_posts_${widget.currentUserId}',
      _revealedPostIds.toList(),
    );
  }

  @override
  void dispose() {
    _audioService.stopIfOwner(this);
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.posts.isEmpty) {
      return Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          backgroundColor: AppColors.background,
          foregroundColor: Colors.white,
          title: Text(widget.displayUsername ?? ''),
        ),
        body: const Center(
          child: Text(
            '表示できる投稿がありません',
            style: TextStyle(color: Colors.white70),
          ),
        ),
      );
    }

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: AppColors.background,
        body: SafeArea(
          child: Stack(
            children: [
              PageView.builder(
                scrollDirection: Axis.vertical,
                controller: _pageController,
                onPageChanged: (i) => setState(() => _currentIndex = i),
                itemCount: widget.posts.length,
                itemBuilder: (context, index) => _buildPostPage(widget.posts[index]),
              ),
              // 戻るボタン
              Positioned(
                top: 8,
                left: 8,
                child: IconButton(
                  icon: const Icon(Icons.arrow_back, color: Colors.white),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ),
              // ページインジケータ（複数投稿あるとき）
              if (widget.posts.length > 1)
                Positioned(
                  top: 12,
                  left: 56,
                  right: 16,
                  child: _buildSegments(),
                ),
            ],
          ),
        ),
      ),
    );
  }

  /// 投稿1枚分（VibePlaylist と違いここは PostCard をそのまま全画面で見せる）
  Widget _buildPostPage(PostModel post) {
    // PostUIState を購読して、いいね数等の楽観的更新を反映
    context.watch<PostUIState>();
    // 自分の投稿は常に裏面解放、それ以外は「今日投稿済み or 一度フリップ済み」のみ
    final backSideEnabled = post.userId == widget.currentUserId ||
        widget.hasPostedToday ||
        _revealedPostIds.contains(post.postId);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 11),
      child: Center(
        child: PostCard(
          post: post,
          audioService: _audioService,
          currentUserId: widget.currentUserId,
          backSideEnabled: backSideEnabled,
          onFlipToBack: () => _markPostRevealed(post.postId),
        ),
      ),
    );
  }

  /// インスタストーリー風の上部セグメントバー（現在位置を白、他はグレー）
  Widget _buildSegments() {
    return Row(
      children: [
        for (int i = 0; i < widget.posts.length; i++) ...[
          Expanded(
            child: Container(
              height: 2.5,
              decoration: BoxDecoration(
                color: i <= _currentIndex
                    ? Colors.white
                    : Colors.white.withValues(alpha: 0.35),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          if (i < widget.posts.length - 1) const SizedBox(width: 4),
        ],
      ],
    );
  }
}

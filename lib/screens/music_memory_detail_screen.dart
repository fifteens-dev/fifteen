import 'dart:ui';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/post_model.dart';
import '../providers/current_user_provider.dart';
import '../providers/saved_items_provider.dart';
import '../services/audio_player_service.dart';
import '../services/itunes_search_service.dart';
import '../services/post_service.dart';
import '../widgets/dialogs/delete_post_dialog.dart';
import '../widgets/post_card.dart';
import 'card_share_screen.dart';

/// Music Memory（カレンダー）から開く投稿詳細画面。
///
/// - 「日」単位の横カルーセル（[posts] は各日の代表1件・新しい→古い順は呼び出し側で決める）。
/// - 前後の日は横スワイプ or 下部ジャケットのタップで移動。中央カードは拡大、左右は縮小。
/// - カードは裏面（写真）がデフォルト。タップで表裏フリップ。両面ともコメントバー非表示。
/// - 背景は #121212＋現在の投稿写真をぼかしたもの。ヘッダーに日付・時刻、右上に共有。
class MusicMemoryDetailScreen extends StatefulWidget {
  final List<PostModel> posts;
  final int initialIndex;

  /// 遅延ロード用（月画面と同じ仕組み）。端まで来たら 3ヶ月前を追加取得する。
  /// userId が null の場合は追加ロードしない（渡された posts のみ表示）。
  final String? userId;

  /// 新しい→古い順の全月キー ("YYYY-MM")。読み込み範囲の骨格。
  final List<String> monthsNewToOld;

  /// すでにロード済みのチャンク数（1チャンク=3ヶ月）。
  final int loadedChunks;

  /// 投稿が削除されたときに postId を通知する（呼び出し元のカレンダー更新用）。
  final ValueChanged<String>? onPostDeleted;

  const MusicMemoryDetailScreen({
    super.key,
    required this.posts,
    required this.initialIndex,
    this.userId,
    this.monthsNewToOld = const [],
    this.loadedChunks = 0,
    this.onPostDeleted,
  });

  static Future<void> push(
    BuildContext context, {
    required List<PostModel> posts,
    required int initialIndex,
    String? userId,
    List<String> monthsNewToOld = const [],
    int loadedChunks = 0,
    ValueChanged<String>? onPostDeleted,
  }) {
    return Navigator.of(context).push(
      PageRouteBuilder(
        opaque: true,
        transitionDuration: const Duration(milliseconds: 320),
        reverseTransitionDuration: const Duration(milliseconds: 240),
        pageBuilder: (_, __, ___) => MusicMemoryDetailScreen(
          posts: posts,
          initialIndex: initialIndex,
          userId: userId,
          monthsNewToOld: monthsNewToOld,
          loadedChunks: loadedChunks,
          onPostDeleted: onPostDeleted,
        ),
        // ジャケット→写真の「ズームで表示」を近似する scale + fade。
        transitionsBuilder: (_, animation, __, child) {
          final curved = CurvedAnimation(
            parent: animation,
            curve: Curves.easeOutCubic,
            reverseCurve: Curves.easeInCubic,
          );
          return FadeTransition(
            opacity: curved,
            child: ScaleTransition(
              scale: Tween<double>(begin: 0.82, end: 1.0).animate(curved),
              child: child,
            ),
          );
        },
      ),
    );
  }

  @override
  State<MusicMemoryDetailScreen> createState() =>
      _MusicMemoryDetailScreenState();
}

class _MusicMemoryDetailScreenState extends State<MusicMemoryDetailScreen> {
  static const double _viewportFraction = 0.84;
  static const double _sideScale = 0.88;

  final AudioPlayerService _audioService = AudioPlayerService();
  final ITunesSearchService _itunes = ITunesSearchService();
  final PostService _postService = PostService();
  final Map<String, String> _previewCache = {}; // postId -> previewUrl
  int _playGen = 0;

  /// 表示中の日代表（新しい→古い）。端まで来たら古い方に追記していく。
  late List<PostModel> _days;
  late int _loadedChunks;
  bool _loadingMore = false;

  late PageController _controller;
  late int _index;
  double _page = 0;

  int get _monthCount => widget.monthsNewToOld.length;
  bool get _hasMore =>
      widget.userId != null &&
      widget.userId!.isNotEmpty &&
      _loadedChunks * 3 < _monthCount;

  @override
  void initState() {
    super.initState();
    _days = List<PostModel>.from(widget.posts);
    _loadedChunks = widget.loadedChunks;
    _index = widget.initialIndex.clamp(0, _days.length - 1);
    _page = _index.toDouble();
    _controller =
        PageController(viewportFraction: _viewportFraction, initialPage: _index);
    _controller.addListener(_onScroll);
    // 初期表示（中央）の曲を再生 + 端に近ければ先読み。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _playCurrent();
      _maybeLoadMore();
    });
  }

  /// 端（最古の読み込み済み）に近づいたら次の 3ヶ月チャンクを先読みする。
  void _maybeLoadMore() {
    if (_index >= _days.length - 2) _loadOlderChunk();
  }

  Future<void> _loadOlderChunk() async {
    if (_loadingMore || !_hasMore) return;
    _loadingMore = true;
    final months = widget.monthsNewToOld;
    final chunk = _loadedChunks;
    final newestIdx = chunk * 3;
    if (newestIdx >= months.length) {
      _loadingMore = false;
      return;
    }
    final oldestIdx = ((chunk + 1) * 3 - 1).clamp(0, months.length - 1);
    final rangeStart = _firstDayOfMonthKey(months[oldestIdx]);
    final rangeEnd = _firstDayOfNextMonth(months[newestIdx]);

    try {
      final fetched = await _postService.getUserPostsInRange(
        widget.userId!,
        rangeStart,
        rangeEnd,
      );
      if (!mounted) return;

      final existingDays = <String>{
        for (final p in _days) _dayKey(p.createdAt),
      };
      final repByDay = <String, PostModel>{};
      for (final p in fetched.where((p) => !p.isVibe)) {
        final key = _dayKey(p.createdAt);
        if (existingDays.contains(key)) continue;
        final ex = repByDay[key];
        if (ex == null || p.createdAt.isAfter(ex.createdAt)) repByDay[key] = p;
      }
      setState(() {
        _days.addAll(repByDay.values);
        _days.sort((a, b) => b.createdAt.compareTo(a.createdAt)); // 新→古
        _loadedChunks++;
      });
    } finally {
      _loadingMore = false;
    }
  }

  String _dayKey(DateTime d) => '${d.year}-${d.month}-${d.day}';

  DateTime _firstDayOfMonthKey(String key) {
    final parts = key.split('-');
    return DateTime(int.parse(parts[0]), int.parse(parts[1]), 1);
  }

  DateTime _firstDayOfNextMonth(String key) {
    final parts = key.split('-');
    return DateTime(int.parse(parts[0]), int.parse(parts[1]) + 1, 1);
  }

  /// 中央に来ている投稿のプレビュー音源を再生する。
  /// スクロール settle 時と初期表示で呼ぶ。連打・スワイプ中の競合は世代番号で無効化。
  Future<void> _playCurrent() async {
    final gen = ++_playGen;
    final posts = _days;
    if (posts.isEmpty) return;
    final post = posts[_index.clamp(0, posts.length - 1)];

    String? url = post.track.previewUrl;
    if (url == null || url.isEmpty) url = _previewCache[post.postId];
    if (url == null || url.isEmpty) {
      final r = await _itunes.getPreviewUrlWithArt(
        trackName: post.track.trackName,
        artistName: post.track.artistName,
      );
      url = r?['previewUrl'];
      if (url != null && url.isNotEmpty) _previewCache[post.postId] = url;
    }
    if (!mounted || gen != _playGen || url == null || url.isEmpty) return;
    await _audioService.playPreview(
      url,
      startFrom: Duration(milliseconds: post.audioStartMs),
      durationSeconds: post.audioDurationSec,
      owner: this,
    );
  }

  void _onScroll() {
    final p = _controller.page;
    if (p == null) return;
    final rounded = p.round();
    final changed = rounded != _index;
    setState(() {
      _page = p;
      if (changed) _index = rounded;
    });
    if (changed) _maybeLoadMore();
  }

  @override
  void dispose() {
    _controller.removeListener(_onScroll);
    _controller.dispose();
    _audioService.stopIfOwner(this);
    super.dispose();
  }

  /// 自分の投稿を削除する（タイムラインと同じ 3点メニュー → 確認ダイアログ）。
  /// 削除後はカルーセルから外し、残り 0 件なら画面を閉じる。
  Future<void> _handleDelete(PostModel post) async {
    final confirmed = await showDeletePostConfirmDialog(context);
    if (!confirmed || !mounted) return;
    try {
      await _postService.deletePost(post.postId);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('削除に失敗しました')),
        );
      }
      return;
    }
    if (!mounted) return;

    widget.onPostDeleted?.call(post.postId);

    final removedAt = _days.indexWhere((p) => p.postId == post.postId);
    if (removedAt < 0) return;
    if (_days.length <= 1) {
      Navigator.of(context).pop();
      return;
    }

    // PageController は残り件数に合わせて作り直す（reverse の PageView は
    // itemCount だけ減らすと現在ページがずれるため）。
    final nextIndex = removedAt.clamp(0, _days.length - 2);
    final oldController = _controller;
    oldController.removeListener(_onScroll);
    setState(() {
      _days.removeAt(removedAt);
      _index = nextIndex;
      _page = nextIndex.toDouble();
      _controller = PageController(
        viewportFraction: _viewportFraction,
        initialPage: nextIndex,
      )..addListener(_onScroll);
    });
    // 旧コントローラは PageView が新しい方に差し替わってから破棄する。
    WidgetsBinding.instance
        .addPostFrameCallback((_) => oldController.dispose());
    _playCurrent();
  }

  void _goTo(int i) {
    // 範囲チェックは実データ(_days)で行う。追加ロード後も正しく移動できるように
    // widget.posts（初期分のみ）ではなく _days.length を使う。
    if (i < 0 || i >= _days.length) return;
    _controller.animateToPage(
      i,
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOutCubic,
    );
  }

  String _dateLabel(DateTime d) => '${d.year} / ${d.month} / ${d.day}';
  String _timeLabel(DateTime d) =>
      '${d.hour}:${d.minute.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final posts = _days;
    final current = posts[_index.clamp(0, posts.length - 1)];
    final currentUserId = FirebaseAuth.instance.currentUser?.uid;
    final currentUserIconUrl = context.watch<CurrentUserProvider>().iconUrl;
    final savedItems = context.watch<SavedItemsProvider>();

    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      body: Stack(
        children: [
          // 背景: #121212 + 現在の写真をぼかしたもの。
          Positioned.fill(child: _blurredBackground(current)),

          SafeArea(
            child: Column(
              children: [
                _header(current),
                Expanded(
                  child: NotificationListener<ScrollNotification>(
                    onNotification: (n) {
                      // スクロールが止まった＝中央にカードが収まったら再生。
                      if (n is ScrollEndNotification) _playCurrent();
                      return false;
                    },
                    child: PageView.builder(
                    controller: _controller,
                    // _days は新しい→古い順（index 0 が最新）。reverse:true で
                    // 高インデックス（古い投稿）を画面左に配置する。
                    reverse: true,
                    itemCount: posts.length,
                    itemBuilder: (context, i) {
                      final scale = (1 -
                              ((_page - i).abs() * (1 - _sideScale)))
                          .clamp(_sideScale, 1.0);
                      final post = posts[i];
                      return Center(
                        child: Transform.scale(
                          scale: scale,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            child: AspectRatio(
                              aspectRatio: 363 / 645,
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(18),
                                child: PostCard(
                                  key: ValueKey('mm-detail-${post.postId}'),
                                  post: post,
                                  currentUserId: currentUserId,
                                  currentUserIconUrl: currentUserIconUrl,
                                  audioService: _audioService,
                                  isSaved: savedItems.isPostOrTrackSaved(post),
                                  startFromBack: true, // 裏面(写真)がデフォルト
                                  backSideEnabled: true, // タップでフリップ
                                  hideCommentBar: true, // 表裏ともコメントバー非表示
                                  // カード上の共有ボタンは非表示（共有はヘッダー右上）。
                                  hideShareButton: true,
                                  // 音源は画面側で中央カードを再生管理する。
                                  audioManagedExternally: true,
                                  onShare: () => _share(post),
                                  // 過去の投稿もタイムラインと同じ 3点メニューから削除できる。
                                  onDelete: (currentUserId != null &&
                                          post.userId == currentUserId)
                                      ? () => _handleDelete(post)
                                      : null,
                                ),
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                    ),
                  ),
                ),
                _bottomJackets(posts),
                const SizedBox(height: 16),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _blurredBackground(PostModel post) {
    final url = post.photoUrl;
    return Stack(
      fit: StackFit.expand,
      children: [
        const ColoredBox(color: Color(0xFF121212)),
        if (url != null && url.isNotEmpty)
          ImageFiltered(
            imageFilter: ImageFilter.blur(sigmaX: 40, sigmaY: 40),
            child: CachedNetworkImage(
              imageUrl: url,
              fit: BoxFit.cover,
              // ちらつき回避のため即時。エラー時は透明。
              errorWidget: (_, __, ___) => const SizedBox.shrink(),
            ),
          ),
        // 暗くして #121212 に馴染ませる。
        const ColoredBox(color: Color(0xCC121212)),
      ],
    );
  }

  Widget _header(PostModel current) {
    return SizedBox(
      height: 56,
      width: double.infinity, // 全幅にして戻る/共有を画面の左右端へ
      child: Stack(
        alignment: Alignment.center,
        children: [
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                _dateLabel(current.createdAt),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                ),
              ),
              Text(
                _timeLabel(current.createdAt),
                style: const TextStyle(
                  color: Color(0xFF9A9A9A),
                  fontSize: 13,
                ),
              ),
            ],
          ),
          Positioned(
            left: 16,
            child: _circleButton(
              icon: CupertinoIcons.chevron_left,
              onTap: () => Navigator.of(context).maybePop(),
            ),
          ),
          Positioned(
            right: 16,
            child: _circleButton(
              icon: CupertinoIcons.share,
              onTap: () => _share(current),
            ),
          ),
        ],
      ),
    );
  }

  Widget _circleButton({required IconData icon, required VoidCallback onTap}) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        width: 40,
        height: 40,
        decoration: const BoxDecoration(
          shape: BoxShape.circle,
          color: Color(0x33FFFFFF),
        ),
        alignment: Alignment.center,
        child: Icon(icon, color: Colors.white, size: 20),
      ),
    );
  }

  /// 下部の前/現/次ジャケット（Figma 4974:10898 準拠・209×58 の固定寸法）。
  /// 中央=現在（白枠3px）、左右=前/次。左右タップでその日へ移動。
  Widget _bottomJackets(List<PostModel> posts) {
    // 絶対座標ジャケット（左右・中央画像）。範囲外は非表示。
    Positioned jacket(
      int i, {
      required double left,
      required double top,
      required double w,
      required double h,
      bool center = false,
    }) {
      final valid = i >= 0 && i < posts.length;
      final url = valid ? posts[i].track.albumImageUrl : '';
      return Positioned(
        left: left,
        top: top,
        width: w,
        height: h,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: (center || !valid) ? null : () => _goTo(i),
          child: (valid && url.isNotEmpty)
              ? ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: CachedNetworkImage(imageUrl: url, fit: BoxFit.cover),
                )
              : const SizedBox.shrink(),
        ),
      );
    }

    return SizedBox(
      height: 58,
      child: Center(
        child: SizedBox(
          width: 209,
          height: 58,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: const Color(0xFF09090A),
              borderRadius: BorderRadius.circular(15),
              border: Border.all(color: const Color(0xFF272627), width: 1),
            ),
            child: Stack(
              clipBehavior: Clip.hardEdge,
              children: [
                // 本編を reverse 表示（古いほど左）にしたので、下部バーも合わせる。
                // 左＝古い日（_index+1）、右＝新しい日（_index-1）。
                jacket(_index + 1, left: 20, top: 8, w: 43, h: 42),
                jacket(_index - 1, left: 147, top: 8, w: 43, h: 42),
                // 中央の白枠（3px・角丸16・58×58）
                const Positioned(
                  left: 76,
                  top: 0,
                  width: 58,
                  height: 58,
                  child: IgnorePointer(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.all(Radius.circular(16)),
                        border: Border.fromBorderSide(
                          BorderSide(color: Colors.white, width: 3),
                        ),
                      ),
                    ),
                  ),
                ),
                // 中央のジャケ画像（48×48・角丸10・白枠の中で5px インセット）
                jacket(_index, left: 81, top: 5, w: 48, h: 48, center: true),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _share(PostModel post) {
    final currentUserId = FirebaseAuth.instance.currentUser?.uid;
    final currentUserIconUrl = context.read<CurrentUserProvider>().iconUrl;
    final saved = context.read<SavedItemsProvider>().isPostOrTrackSaved(post);
    showCardShareSheet(
      context,
      post: post,
      currentUserId: currentUserId,
      currentUserIconUrl: currentUserIconUrl,
      isSaved: saved,
    );
  }
}

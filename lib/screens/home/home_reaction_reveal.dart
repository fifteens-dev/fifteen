part of '../home_screen.dart';

// setState は State の protected メンバー。extension から呼ぶと警告が出るが、
// 同じ State の一部として切り出しただけなので問題ない。
// ignore_for_file: invalid_use_of_protected_member

/// リアクション通知をタップしたときの演出。
///
/// ホームのタイムラインで自分のカードまでスクロールし、リアクションした側と
/// 同じ絵文字のアニメーションを流す。依頼は [ReactionRevealService] に
/// 置かれるので、ホームが後から立ち上がっても取りこぼさない。
extension HomeReactionReveal on _HomeScreenState {
  /// 依頼が置かれたとき・投稿を読み終えたときに呼ぶ。
  void _onReactionRevealRequested() {
    if (!mounted) return;
    if (ReactionRevealService.instance.pending.value == null) return;
    // 投稿をまだ読んでいなければ、読み終えたところでもう一度呼ばれる。
    if (_cachedPosts == null) return;
    final req = ReactionRevealService.instance.take();
    if (req != null) {
      // ignore: discarded_futures
      _revealReaction(req);
    }
  }

  Future<void> _revealReaction(ReactionRevealRequest req) async {
    // スクロール位置を見積もるのは 1 列表示が前提。
    setState(() {
      _selectedIndex = 1;
      _isGridView = false;
    });

    // 手元の投稿は古いことがある（リアクションは通知の直前に付いたもの）。
    // 読み直して、その人の絵文字が入った状態にする。
    await _loadPosts();
    if (!mounted) return;

    final posts = _cachedPosts ?? const <PostModel>[];
    final index = posts.indexWhere((p) => p.postId == req.postId);
    if (index < 0) {
      // 前のサイクルの投稿などでタイムラインに無い。投稿詳細で見せる。
      await _openPostDetailFor(req.postId);
      return;
    }

    await _scrollToPostAt(index, req.postId);
    if (!mounted) return;

    final emoji = posts[index].reactionOf(req.senderId);
    if (emoji == null) return; // いいね通知、または取り消された
    HapticFeedback.lightImpact();
    late final OverlayEntry entry;
    entry = OverlayEntry(
      builder: (_) => ReactionBurstOverlay(
        origin: MediaQuery.sizeOf(context).center(Offset.zero),
        emoji: emoji,
        onDone: () => entry.remove(),
      ),
    );
    Overlay.of(context, rootOverlay: true).insert(entry);
  }

  /// [index] 番目のカードを画面に収める。
  ///
  /// SliverList は見えている付近しか作らないので、遠いカードは GlobalKey に
  /// context がまだ無い。カードの高さから位置を見積もって近くまで動かし、
  /// 作られたところで ensureVisible で合わせ直す。
  Future<void> _scrollToPostAt(int index, String postId) async {
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted || !_scrollController.hasClients) return;

    BuildContext? cardContext() => _postCardKeys[postId]?.currentContext;

    if (cardContext() == null) {
      // 1 列表示のカード: 左右 15 の余白、縦横比 363:645、下に 24 の間隔。
      final cardWidth = MediaQuery.sizeOf(context).width - 30;
      final extent = cardWidth * 645 / 363 + 24;
      final pos = _scrollController.position;
      final target = (index * extent).clamp(0.0, pos.maxScrollExtent);
      try {
        await _scrollController.animateTo(
          target,
          duration: const Duration(milliseconds: 450),
          curve: Curves.easeOut,
        );
      } catch (_) {}
      await WidgetsBinding.instance.endOfFrame;
    }

    final ctx = cardContext();
    if (ctx == null || !ctx.mounted) return;
    await Scrollable.ensureVisible(
      ctx,
      alignment: 0.1,
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeOut,
    );
  }

  Future<void> _openPostDetailFor(String postId) async {
    final post = await PostService().getPost(postId);
    if (!mounted || post == null) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PostDetailScreen(
          post: post,
          currentUserId: _auth.currentUser?.uid ?? '',
        ),
      ),
    );
  }
}

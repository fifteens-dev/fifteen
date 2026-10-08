part of '../home_screen.dart';

// setState は State の protected メンバー。extension から呼ぶと警告が出るが、
// 同じ State の一部として切り出しただけなので問題ない。
// ignore_for_file: invalid_use_of_protected_member

/// ホームの描画のうち、build() から切り出せる部分。
///
/// ヘッダのオーバーレイ、タイムラインの Sliver、投稿カードの組み立て、
/// 投稿が無いときの案内。build() 本体はライフサイクルと同じ場所に残す。
extension HomeBuild on _HomeScreenState {

  /// グラデーション幕の上に浮かせるヘッダー（"15s" + 通知ベル）。
  /// 背景色を持たず（＝タッチを吸わない）、タイトルは IgnorePointer、ベルのみ操作可能。
  /// これによりヘッダー領域でもスクロール/プル更新のジェスチャーが背後のリストへ通る。
  Widget _homeHeaderOverlay(double headerHeight, double topPadding) {
    return SizedBox(
      height: headerHeight,
      child: Padding(
        padding: EdgeInsets.only(left: 16, right: 16, top: topPadding),
        child: Stack(
          children: [
            const Center(
              child: IgnorePointer(
                child: Text(
                  '15s',
                  style: TextStyle(
                    fontSize: 30,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                    fontFamily: 'SFPro',
                  ),
                ),
              ),
            ),
            // 左上: 友達追加ボタン → 友達追加シート（Figma 5539:11181）。
            // Figma 5189:11175: グリフ箱 42×29 @x=23。素材は4x書き出しのタイト画像
            // (155×102) なので実寸 38.75×25.5。ヘッダー左padding16を差し引き left=8。
            Positioned(
              left: 8,
              top: 0,
              bottom: 0,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () {
                  _homeAudioService.stop();
                  FriendAddSheet.show(context);
                },
                child: Center(
                  child: Image.asset(
                    'assets/icons/friend_add.png',
                    width: 38.75,
                    height: 25.5,
                    fit: BoxFit.fill,
                    color: Colors.white,
                    colorBlendMode: BlendMode.srcIn,
                  ),
                ),
              ),
            ),
            // 右上: グリッド切替 + 通知ベル。
            Positioned(
              right: 0,
              top: 0,
              bottom: 0,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // グリッド切替（1列 ⇔ 2列）。表示中の列数に応じてアイコンを切替。
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => setState(() => _isGridView = !_isGridView),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 8),
                      child: Image.asset(
                        _isGridView
                            ? 'assets/icons/grid_1col.png'
                            : 'assets/icons/grid_2col.png',
                        width: 24,
                        height: 24,
                        color: Colors.white,
                        colorBlendMode: BlendMode.srcIn,
                      ),
                    ),
                  ),
                  ValueListenableBuilder<double>(
                    valueListenable: _bellOpacity,
                    builder: (_, opacity, child) => Opacity(
                      opacity: opacity,
                      child:
                          IgnorePointer(ignoring: opacity < 0.1, child: child),
                    ),
                    child: NotificationBadge(
                      child: IconButton(
                        icon: const Icon(Icons.notifications_outlined,
                            color: Colors.white),
                        onPressed: () {
                          _homeAudioService.stop();
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                                builder: (_) => const NotificationListScreen()),
                          );
                        },
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Music Memory タブ（カレンダー）。プロフィールから開く月画面を
  /// ルートタブとして埋め込む（戻るボタンは非表示）。
  Widget _buildMusicMemoryTab() {
    final user = _auth.currentUser;
    return MusicMemoryMonthScreen(
      key: _musicMemoryKey,
      embedded: true,
      userId: user?.uid,
      accountCreatedAt: user?.metadata.creationTime,
    );
  }

  /// タイムライン（投稿カードリスト）- Sliver版
  /// 1件分の PostCard を構築（1列・2列グリッド共用）。
  PostCard _buildPostCardFor({
    required PostModel post,
    required int index,
    required PostUIState postUIState,
    required SavedItemsProvider savedItems,
    required String? currentUserIconUrl,
    required GlobalKey<PostCardState> cardKey,
    bool externalFlipControl = false,
    VoidCallback? onCardTap,
    // 共有/コメント/削除など別シート・ダイアログを開く直前に呼ぶ。
    // 2列グリッドの拡大オーバーレイを閉じ、シートの上に残らないようにする。
    VoidCallback? onBeforeSheet,
  }) {
    final currentUserId = _auth.currentUser?.uid ?? 'test_user_temp';
    final displayPost = postUIState.getDisplayPost(
      post,
      currentUserId: currentUserId,
      currentUserIconUrl: currentUserIconUrl,
    );

    // 裏面の閲覧もリアクションも、投稿の有無で制限しない
    // （「投稿しないと裏返せない / 反応できない」は廃止）。

    return PostCard(
      key: cardKey,
      post: displayPost,
      currentUserId: currentUserId,
      currentUserIconUrl: currentUserIconUrl,
      audioService: _homeAudioService,
      externalPreviewUrl: _previewUrlCache[post.postId],
      externalFlipControl: externalFlipControl,
      onCardTap: onCardTap,
      onLike: () => _handleLike(post),
      onComment: () {
        onBeforeSheet?.call();
        _handleComment(post);
      },
      onReaction: (emoji) => _handleReaction(post, emoji),
      onAdd: () => _handleAdd(post),
      onDelete: post.userId == currentUserId
          ? () {
              onBeforeSheet?.call();
              _handleDelete(post);
            }
          : null,
      isSaved: savedItems.isPostOrTrackSaved(post),
      backSideEnabled: true,
      // 写真は自分の投稿に、24:00 まで、まだ無いときだけ足せる。
      onAddPhoto: (post.userId == currentUserId &&
              _canAddPhoto &&
              !_postsWithPhoto.contains(post.postId))
          ? () => _addPhoto(post.postId)
          : null,
      onPlayStarted: () {
        _playingPostId = post.postId;
        // 2列グリッドの拡大プレビューでは隣接プリロードをしない。
        // 隣の音声用に別 AudioPlayer を生成すると、iOS の共有オーディオセッション経由で
        // メイン再生の setUrl が中断され（"Loading interrupted"）音が鳴らないため。
        if (!externalFlipControl) _preloadNeighborAudio(index);
      },
      onShare: () {
        onBeforeSheet?.call();
        showCardShareSheet(
          context,
          post: post,
          currentUserId: currentUserId,
          currentUserIconUrl: currentUserIconUrl,
          isSaved: savedItems.isPostOrTrackSaved(post),
        );
      },
    );
  }

  /// タイムライン0件時の投稿促しカード（Figma 5227:10820 / 5231:11175）。
  /// 投稿カードと同じ 363:645 の暗いカードに、中央の文言＋白ピルボタンを配置。
  Widget _buildEmptyTimelinePromptSliver() {
    const grey = Color(0xFF9D9D9D);
    return SliverPadding(
      padding: const EdgeInsets.fromLTRB(15, 9, 15, 0),
      sliver: SliverToBoxAdapter(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final w = constraints.maxWidth;
            final h = w * 645 / 363;
            return Container(
              width: w,
              height: h,
              decoration: BoxDecoration(
                color: const Color(0xFF141414),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFF2A2A2A), width: 1),
              ),
              alignment: Alignment.center,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    '今日のMusic Memory',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 22,
                      fontWeight: FontWeight.w600,
                      height: 1.5,
                    ),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'まだ投稿していません',
                    style: TextStyle(color: grey, fontSize: 11, height: 1.5),
                  ),
                  const SizedBox(height: 21),
                  const Text(
                    'あなたの今日を彩る1曲を\n残してみましょう',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: grey, fontSize: 11, height: 1.5),
                  ),
                  const SizedBox(height: 26),
                  // 白ピルボタン 174×46（＋アイコン + テキスト）→ 投稿フロー。
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: _openPostFlow,
                    child: Container(
                      width: 174,
                      height: 46,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(49),
                      ),
                      child: const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.add, color: Colors.black, size: 22),
                          SizedBox(width: 8),
                          Text(
                            '今日の1曲を残す',
                            style: TextStyle(
                              color: Colors.black,
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildTimelineSliver(PostUIState postUIState, SavedItemsProvider savedItems, String? currentUserIconUrl) {
    final posts = _cachedPosts!;

    // タイムラインに投稿が0件のとき、投稿を促すカードを表示（Figma 5227:10820）。
    if (posts.isEmpty) {
      return _buildEmptyTimelinePromptSliver();
    }

    if (_isGridView) {
      // 2列グリッド。タップで「その場拡大 → 0.2秒後に自動反転」。
      return SliverPadding(
        padding: const EdgeInsets.symmetric(horizontal: 15),
        sliver: SliverGrid(
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            crossAxisSpacing: 11,
            mainAxisSpacing: 16,
            // PostCard 前面の縦横比 363:645 に合わせる。
            childAspectRatio: 363 / 645,
          ),
          delegate: SliverChildBuilderDelegate(
            (context, index) {
              final post = posts[index];
              final cardKey = _postCardKeys.putIfAbsent(
                  post.postId, () => GlobalKey<PostCardState>());
              return _GridPostCell(
                key: ValueKey('grid_${post.postId}'),
                cardKey: cardKey,
                onEnlargedChanged: (v) => _gridEnlargedActive = v,
                builder: (key, onTap, requestClose) => _buildPostCardFor(
                  post: post,
                  index: index,
                  postUIState: postUIState,
                  savedItems: savedItems,
                  currentUserIconUrl: currentUserIconUrl,
                  cardKey: key,
                  externalFlipControl: true,
                  onCardTap: onTap,
                  onBeforeSheet: requestClose,
                ),
              );
            },
            childCount: posts.length,
          ),
        ),
      );
    }

    return SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: 15),
      sliver: SliverList(
        delegate: SliverChildBuilderDelegate(
          (context, index) {
            final post = posts[index];
            final cardKey = _postCardKeys.putIfAbsent(
                post.postId, () => GlobalKey<PostCardState>());

            return Padding(
              padding: const EdgeInsets.only(bottom: 24),
              child: RepaintBoundary(
                child: _buildPostCardFor(
                  post: post,
                  index: index,
                  postUIState: postUIState,
                  savedItems: savedItems,
                  currentUserIconUrl: currentUserIconUrl,
                  cardKey: cardKey,
                ),
              ),
            );
          },
          childCount: posts.length,
        ),
      ),
    );
  }
}

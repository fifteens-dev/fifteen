part of '../home_screen.dart';

// setState は State の protected メンバー。extension から呼ぶと警告が出るが、
// 同じ State の一部として切り出しただけなので問題ない。
// ignore_for_file: invalid_use_of_protected_member

/// Vibe ストーリーバー。機能は一時的に全面非表示だが、取得と既読管理は
/// 残してある（復活時にそのまま使う）。
extension HomeStories on _HomeScreenState {

  /// Vibe ストーリー既読 postId を読み込む
  Future<void> _loadViewedStoryPostIds() async {
    final currentUserId = _auth.currentUser?.uid;
    if (currentUserId == null) return;
    final prefs = await SharedPreferences.getInstance();
    final ids = prefs.getStringList('viewed_story_posts_$currentUserId') ?? [];
    if (mounted) {
      setState(() => _viewedStoryPostIds = ids.toSet());
    }
  }

  /// Vibe ストーリー閲覧時に呼ぶ: 渡された postId 群を既読セットに追加 + 永続化。
  /// 既読のリング表示（グレー化）にも即時反映するため _storyItems も再構成する。
  Future<void> _markStoryPostsViewed(Iterable<String> postIds) async {
    final newIds = postIds.where((id) => !_viewedStoryPostIds.contains(id));
    if (newIds.isEmpty) return;
    final updated = {..._viewedStoryPostIds, ...newIds};
    setState(() {
      _viewedStoryPostIds = updated;
      // unread フラグを再評価して即時反映
      _storyItems = _storyItems
          .map((s) => VibeStoryItem(
                userId: s.userId,
                username: s.username,
                iconUrl: s.iconUrl,
                posts: s.posts,
                unread: _isStoryUnread(s, updated),
              ))
          .toList();
    });
    final currentUserId = _auth.currentUser?.uid;
    if (currentUserId == null) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
      'viewed_story_posts_$currentUserId',
      updated.toList(),
    );
  }

  /// ストーリーアイテムの全投稿が既読セットに含まれていれば既読扱い（false）
  bool _isStoryUnread(VibeStoryItem story, Set<String> viewedIds) {
    return story.posts.any((p) => !viewedIds.contains(p.postId));
  }

  /// Vibe ストーリーバー用に、フォロー先 + 自分の 24h 投稿をユーザー単位で取得する。
  ///
  /// 仕様（[VibeStoryBarSection]）:
  /// - 24時間以内に投稿があるユーザーだけを並べる
  /// - 鍵投稿（audience=followers）は閲覧権限がない人には見えない
  ///   → そのユーザーに公開可能な投稿が0件なら、ストーリー円自体も出さない
  /// - 並びは「最新投稿の createdAt 降順」（左 = 最新、右 = 古い順）
  Future<List<VibeStoryItem>> _fetchStoryItems({
    required UserModel? viewer,
    required List<String> targetUserIds,
  }) async {
    if (targetUserIds.isEmpty) return const [];
    try {
      // viewer がフォローしている UID 集合（鍵投稿の可視判定に使う）
      final followingSet = (viewer?.following ?? const []).toSet();
      final viewerUid = viewer?.uid;
      bool viewerFollowsAuthor(String authorUid) {
        if (authorUid == viewerUid) return true; // 自分の投稿は常に可視
        return followingSet.contains(authorUid);
      }

      final grouped = await _postService.getRecentPostsGroupedByUser(
        userIds: targetUserIds,
        viewerFollowsAuthor: viewerFollowsAuthor,
      );

      return grouped
          .where((posts) => posts.isNotEmpty)
          .map((posts) {
            final head = posts.first;
            final tmp = VibeStoryItem(
              userId: head.userId,
              username: head.username,
              iconUrl: head.userIconUrl,
              posts: posts,
              unread: true,
            );
            return VibeStoryItem(
              userId: tmp.userId,
              username: tmp.username,
              iconUrl: tmp.iconUrl,
              posts: tmp.posts,
              // 既読セットに全 postId が含まれていればグレー枠（unread=false）
              unread: _isStoryUnread(tmp, _viewedStoryPostIds),
            );
          })
          .toList();
    } catch (e) {
      AppLog.debug('⚠️ ストーリーアイテム取得エラー: $e');
      return const [];
    }
  }

  /// ストーリーバー用の周期タイマーを (再) 開始する。
  /// 即時に 1 回 fire (fire-and-forget) してから 30 秒間隔でポーリング。
  ///
  /// アプリ起動時: initState から呼ばれ、prefetch データで initialPosts が
  /// 埋まっているケースでも即時にストーリーを更新する (prefetch はストーリーを
  /// 含まないため、これが無いと最初の 30 秒間ストーリーが空になる)。
  /// フォアグラウンド復帰時: didChangeAppLifecycleState から呼ばれ、停止した
  /// タイマーを再開しつつ即時同期する。
  void _startStoryRefreshTimer() {
    _storyRefreshTimer?.cancel();
    // ignore: discarded_futures
    _refreshStoriesOnly();
    _storyRefreshTimer =
        Timer.periodic(_HomeScreenState._kStoryRefreshInterval, (_) => _refreshStoriesOnly());
  }

  /// ストーリーバー用のデータだけを再取得 (タイムライン等のフェッチはしない)。
  /// [_loadPosts] に比べて Firestore 読み込みは 1 バッチのみで軽量。
  Future<void> _refreshStoriesOnly() async {
    if (!mounted) return;
    final currentUser = _auth.currentUser;
    if (currentUser == null) return;
    try {
      // 対象 UID: フォロー中 + 自分。CurrentUserProvider には following が
      // 無いので Firestore から取り直す。バッチ 1 回 + createdAt 24h 制約なので軽量。
      UserModel? viewer;
      List<String> followingIds = const [];
      try {
        viewer = await _userService.getUser(currentUser.uid);
        followingIds = viewer?.following ?? const [];
      } catch (_) {}
      final targetIds = [...followingIds, currentUser.uid];
      final allStories = await _fetchStoryItems(
        viewer: viewer,
        targetUserIds: targetIds,
      );
      if (!mounted) return;
      VibeStoryItem? own;
      final followingStories = <VibeStoryItem>[];
      for (final s in allStories) {
        if (s.userId == currentUser.uid) {
          own = s;
        } else {
          followingStories.add(s);
        }
      }
      setState(() {
        _storyItems = followingStories;
        _ownStoryItem = (own != null && own.posts.isNotEmpty) ? own : null;
      });
    } catch (e) {
      // 静かに失敗させる。次回ティックで再試行。
      if (kDebugMode) {
        AppLog.debug('⚠️ ストーリー自動更新エラー: $e');
      }
    }
  }

  /// Vibeデータを読み込み（今日のお題とランキング）
  Future<Map<String, dynamic>> _loadVibeData() async {
    try {
      final forAdl = await AdlService().isCurrentUserAdlParticipant();
      final topic = await _vibeTopicService.getTodaysTopic(forAdl: forAdl);
      if (topic == null) {
        return {'topic': null, 'ranking': []};
      }

      final ranking = await _postService.calculateVibeRanking(
        topic.topicId,
        DateTime.now(),
        limit: 1000,
      );

      return {'topic': topic, 'ranking': ranking};
    } catch (e) {
      AppLog.debug('Error loading vibe data: $e');
      return {'topic': null, 'ranking': []};
    }
  }
}

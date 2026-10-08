part of '../home_screen.dart';

// setState は State の protected メンバー。extension から呼ぶと警告が出るが、
// 同じ State の一部として切り出しただけなので問題ない。
// ignore_for_file: invalid_use_of_protected_member

/// タイムラインのカードに対する操作。いいね・コメントは機能を切って
/// いるが、呼び出し口は残してある。
extension HomePostActions on _HomeScreenState {

  /// ランキングアイテムがタップされたときの処理
  Future<void> _handleRankingItemTap(VibeRankingItem item) async {
    try {
      // 今日のお題を取得
      final forAdl = await AdlService().isCurrentUserAdlParticipant();
      final topic = await _vibeTopicService.getTodaysTopic(forAdl: forAdl);
      if (topic == null) {
        _showMessage('お題が見つかりませんでした');
        return;
      }

      // そのお題の全投稿を取得
      final allPosts = await _postService.getVibePostsByTopic(
        topic.topicId,
        DateTime.now(),
      );

      // タップされたトラックに一致する投稿のみをフィルタ
      final trackKey = item.track.trackId.isNotEmpty
          ? item.track.trackId
          : '${item.track.trackName}_${item.track.artistName}';

      final matchingPosts = allPosts.where((post) {
        final postTrackKey = post.track.trackId.isNotEmpty
            ? post.track.trackId
            : '${post.track.trackName}_${post.track.artistName}';
        return postTrackKey == trackKey;
      }).toList();

      if (matchingPosts.isEmpty) {
        _showMessage('投稿が見つかりませんでした');
        return;
      }

      // ホーム画面の音楽を停止
      _homeAudioService.stop();

      // 投稿一覧画面に遷移（hasPostedTodayを渡してローディングをスキップ）
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => VibeTrackPostsScreen(
            track: item.track,
            posts: matchingPosts,
            currentUserId: _auth.currentUser?.uid ?? 'test_user_temp',
            initialHasPostedToday: _hasPostedToday,
            onTabSwitch: (i) {
              if (mounted) setState(() => _selectedIndex = i);
            },
          ),
        ),
      );
    } catch (e) {
      AppLog.debug('Error handling ranking item tap: $e');
      _showMessage('投稿の読み込みに失敗しました');
    }
  }

  /// いいねボタンが押されたときの処理
  Future<void> _handleLike(PostModel post) async {
    final currentUser = _auth.currentUser;
    final userId = currentUser?.uid ?? 'test_user_temp';
    final postUIState = context.read<PostUIState>();

    final currentLikeCount = postUIState.getLikeCount(post.postId) ?? post.likeCount;
    final wasLiked = postUIState.isLiked(post.postId);

    // 楽観的UI更新（notifyListeners → build再実行）
    postUIState.toggleLike(post.postId, currentLikeCount: currentLikeCount);

    try {
      await _postService.toggleLike(
        postId: post.postId,
        userId: userId,
      );
    } catch (e) {
      // エラー時はロールバック
      if (mounted) {
        postUIState.revertLikeToggle(
          post.postId,
          originalLikeCount: currentLikeCount,
          wasLiked: wasLiked,
        );
      }
      _showMessage('いいねに失敗しました');
    }
  }

  /// 絵文字リアクションが選ばれたときの処理（1ユーザー＝1つ・変更/取消可）。
  /// カード側で楽観的UI・アニメを済ませているので、ここでは Firestore 書き込みのみ。
  Future<void> _handleReaction(PostModel post, String emoji) async {
    final userId = _auth.currentUser?.uid;
    if (userId == null) return;
    try {
      await _postService.setReaction(
        postId: post.postId,
        emoji: emoji,
        userId: userId,
      );
    } catch (e) {
      _showMessage('リアクションに失敗しました');
    }
  }

  /// コメント数を更新（コメント画面から呼ばれる）
  void _updateCommentCount(String postId, int count) {
    if (mounted) {
      context.read<PostUIState>().updateCommentCount(postId, count);
    }
  }

  /// コメントボタンが押されたときの処理
  Future<void> _handleComment(PostModel post) async {
    // コメント画面をボトムシートで表示（音楽は継続）
    await CommentScreen.show(
      context,
      post: post,
      onCommentCountChanged: (count) =>
          _updateCommentCount(post.postId, count),
    );

    // 戻ってきた後、投稿データを更新
    if (mounted) {
      final updatedPost = await _postService.getPost(post.postId);
      if (updatedPost != null && _cachedPosts != null) {
        setState(() {
          final index = _cachedPosts!.indexWhere((p) => p.postId == post.postId);
          if (index != -1) {
            _cachedPosts![index] = updatedPost;
          }
        });
      }
    }
  }

  /// 追加ボタンが押されたときの処理（投稿を保存）
  Future<void> _handleAdd(PostModel post) async {
    await SavedItemsProvider.togglePostWithToast(context, post);
  }

  /// 削除ボタンが押されたときの処理
  Future<void> _handleDelete(PostModel post) async {
    final confirmed = await showDeletePostConfirmDialog(context);

    if (!confirmed) return;

    try {
      await _postService.deletePost(post.postId);
      if (mounted) {
        setState(() {
          _cachedPosts?.removeWhere((p) => p.postId == post.postId);
        });
        _showMessage('投稿を削除しました');
      }
    } catch (e) {
      if (mounted) _showMessage('削除に失敗しました');
    }
  }

  /// メッセージを表示
  void _showMessage(String message) {
    if (mounted) {
      AppToast.show(context, message);
    }
  }
}

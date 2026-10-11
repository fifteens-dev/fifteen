part of '../home_screen.dart';

// setState は State の protected メンバー。extension から呼ぶと警告が出るが、
// 同じ State の一部として切り出しただけなので問題ない。
// ignore_for_file: invalid_use_of_protected_member

/// ホームのデータ取得。タイムラインの投稿と、それに付随する
/// プリフェッチ（音源 URL・裏面の画像）をまとめている。
extension HomeData on _HomeScreenState {

  /// PostUIState / SavedItemsProvider を投稿リストから初期化する
  Future<void> _initializePostUIState(List<PostModel> posts, {UserModel? userModel}) async {
    final currentUser = _auth.currentUser;
    if (currentUser == null) return;
    UserModel? user = userModel;
    if (user == null) {
      try {
        user = await _userService.getUser(currentUser.uid);
      } catch (_) {}
    }
    if (mounted) {
      context.read<PostUIState>().resetAndInitialize(
        posts: posts,
        currentUserId: currentUser.uid,
      );
      if (user != null) {
        context.read<SavedItemsProvider>().initialize(
          userId: currentUser.uid,
          user: user,
        );
      }
    }
  }

  /// プルダウン更新（投稿リスト＋ユーザー情報＋Vibeを再取得）
  /// setState を1回にまとめてカクつきを防止
  Future<void> _onRefresh() async {
    final refreshStart = DateTime.now();
    // Vibe / 投稿 / ユーザーを並列取得。
    // 旧データを表示し続けたいので _vibeDataFuture は即時には差し替えず、
    // 完了済みデータと差し替える。
    final vibeDataFuture = _loadVibeData();
    final postsFuture = _fetchPostsData();
    final userRefreshFuture = context.read<CurrentUserProvider>().refresh();

    final postsResult = await postsFuture;
    await userRefreshFuture;
    final vibeData = await vibeDataFuture;

    // 最低1秒間はリフレッシュインジケーターを表示
    final elapsed = DateTime.now().difference(refreshStart);
    if (elapsed < const Duration(seconds: 1)) {
      await Future.delayed(Duration(seconds: 1) - elapsed);
    }

    if (mounted) {
      // ignore: discarded_futures
      _loadPhotoFlags(postsResult.posts);
      setState(() {
        _cachedPosts = postsResult.posts;
        _hasPostedToday = postsResult.hasPostedToday;
        _previewUrlCache.clear(); // リフレッシュ時はキャッシュをリセット
        // 完了済みFutureに差し替えればFutureBuilderはwaitingにならず暗転しない
        _vibeDataFuture = Future.value(vibeData);
      });
      final uid = _auth.currentUser?.uid ?? '';
      context.read<PostUIState>().resetAndInitialize(
        posts: postsResult.posts,
        currentUserId: uid,
      );
      if (postsResult.user != null && uid.isNotEmpty) {
        context.read<SavedItemsProvider>().initialize(
          userId: uid,
          user: postsResult.user!,
        );
      }
      _prefetchBacksideImages(postsResult.posts);
      _prefetchPreviewUrls(postsResult.posts);
    }
  }

/// 投稿データをFirestoreから取得して返す（setState なし・_loadPosts/_onRefresh 共用）
  Future<({List<PostModel> posts, bool hasPostedToday, UserModel? user})>
      _fetchPostsData() async {
    try {
      final currentUser = _auth.currentUser;

      // 自分の投稿状況とユーザー情報。互いに依存しないので同時に投げる
      // （1 つずつ await していた頃は、タイムラインが出るまでに往復が
      //  直列に並んでいた）。
      //
      // 以前はここで「期限内投稿済みか（リアクション可否）」「Late 含め
      // 投稿済みか（裏面閲覧可否）」も引いていたが、**戻り値を誰も読んで
      // いなかった**ので外した。ゲートを効かせるときは
      // [PostService.postStatusInCurrentCycle] を呼んで PostCard へ渡す。
      bool hasPostedToday = false;
      List<String> followingIds = [];
      UserModel? userModel;

      if (currentUser != null) {
        final uid = currentUser.uid;
        final results = await Future.wait([
          _postService.hasUserPostedToday(uid),
          _userService.getUser(uid).catchError((Object e) {
            AppLog.debug('⚠️ フォロー一覧取得エラー: $e');
            return null;
          }),
        ]);
        hasPostedToday = results[0] as bool;
        userModel = results[1] as UserModel?;
        followingIds = userModel?.following ?? [];
      }
      final allTargetIds = currentUser != null
          ? [...followingIds, currentUser.uid]
          : followingIds;

      List<PostModel> firestorePosts = [];
      try {
        firestorePosts = allTargetIds.isEmpty
            ? []
            : await _postService.getPostsForFollowing(allTargetIds, limit: 50);
        AppLog.debug('📥 Firestoreから取得した投稿数: ${firestorePosts.length}');
      } catch (e) {
        AppLog.debug('⚠️ Firestore取得エラー（権限エラーの可能性）: $e');
      }

      // 【重要】Vibe ストーリーバーは現在非表示のため、その取得（_fetchStoryItems=
      // getRecentPostsGroupedByUser: limit なしで24h全投稿＋全ユーザー情報を逐次取得）は
      // 行わない。これを await で挟むと、重い/遅い場合にタイムライン表示が丸ごと
      // ブロックされ、_cachedPosts がセットされずスピナーのまま固まる不具合になる。
      // ストーリーバー復活時は、タイムライン表示をブロックしない別 Future で取得すること。

      final postsToUse = firestorePosts;
      AppLog.debug('📊 表示する投稿数: ${postsToUse.length} (Firestore)');

      // アルバムアートワークが空の投稿はSpotifyで補完（並列実行）
      final postsNeedingArt = <int>[];
      for (int i = 0; i < postsToUse.length; i++) {
        if (postsToUse[i].track.albumImageUrl.isEmpty) {
          postsNeedingArt.add(i);
        }
      }

      final updatedPosts = List<PostModel>.from(postsToUse);
      if (postsNeedingArt.isNotEmpty) {
        final futures = postsNeedingArt.map((i) async {
          final post = postsToUse[i];
          try {
            final searchQuery = '${post.track.trackName} ${post.track.artistName}';
            final tracks = await _spotifyService.searchTracks(searchQuery, limit: 1);
            if (tracks.isNotEmpty) {
              final updatedTrack = post.track.copyWith(
                albumImageUrl: tracks.first.albumImageUrl,
              );
              return MapEntry(i, post.copyWith(track: updatedTrack));
            }
          } catch (e) {
            AppLog.debug('⚠️ Spotifyアルバムアートワーク取得エラー: $e');
          }
          return MapEntry(i, post);
        }).toList();

        final artResults = await Future.wait(futures);
        for (final entry in artResults) {
          updatedPosts[entry.key] = entry.value;
        }
      }

      return (posts: updatedPosts, hasPostedToday: hasPostedToday, user: userModel);
    } catch (e) {
      AppLog.debug('❌ 投稿読み込みエラー: $e');
      return (posts: <PostModel>[], hasPostedToday: false, user: null);
    }
  }

  /// 投稿リストを読み込み（Firestoreから取得）
  Future<void> _loadPosts() async {
    AppLog.debug('📥 _loadPosts()開始');
    final result = await _fetchPostsData();
    if (mounted) {
      AppLog.debug('✅ 投稿読み込み完了: ${result.posts.length}件の投稿をセット');
      // 新しい投稿リストに存在しないキー・キャッシュを削除してメモリ節約
      final newPostIds = result.posts.map((p) => p.postId).toSet();
      _postCardKeys.removeWhere((id, _) => !newPostIds.contains(id));
      _previewUrlCache.removeWhere((id, _) => !newPostIds.contains(id));
      // 写真の有無も一緒に読む。これを忘れると、既に写真が付いている
      // 自分の投稿に「写真を追加する」バーが出てしまう。
      //
      // 投稿フローはホームを作り直してから上に載るので、投稿直後や
      // 最終確認画面から戻ったときは新しいホームになっている。そこで
      // 読んでいないと、引っ張って更新するまでバーが残っていた。
      // ignore: discarded_futures
      _loadPhotoFlags(result.posts);

      setState(() {
        _cachedPosts = result.posts;
        _hasPostedToday = result.hasPostedToday;
      });
      AppLog.debug('🔄 setState()完了');
      final uid = _auth.currentUser?.uid ?? '';
      context.read<PostUIState>().resetAndInitialize(
        posts: result.posts,
        currentUserId: uid,
      );
      if (result.user != null && uid.isNotEmpty) {
        context.read<SavedItemsProvider>().initialize(
          userId: uid,
          user: result.user!,
        );
      }
      _prefetchBacksideImages(result.posts);
      _prefetchPreviewUrls(result.posts);
    } else {
      AppLog.debug('⚠️ mountedがfalseのため、setStateをスキップ');
    }
  }

  /// 全投稿の音楽プレビューURLをバックグラウンドで先取りする
  /// カードタップ時の遅延をなくすため、投稿読み込み直後にiTunes APIを叩いておく
  /// 3件ずつバッチで並列処理してAPIレート制限を緩和する
  Future<void> _prefetchPreviewUrls(List<PostModel> posts) async {
    const batchSize = 3;
    for (int i = 0; i < posts.length; i += batchSize) {
      if (!mounted) return;
      final batch = posts.skip(i).take(batchSize).toList();
      final futures = <Future<void>>[];

      for (final post in batch) {
        // 既にキャッシュ済みならスキップ
        if (_previewUrlCache.containsKey(post.postId)) continue;

        // post自身にpreviewUrlが入っていればそれを使う（API不要）
        if (post.track.previewUrl != null && post.track.previewUrl!.isNotEmpty) {
          _previewUrlCache[post.postId] = post.track.previewUrl;
          continue;
        }

        // iTunes APIでURL取得（バッチ内は並列）
        futures.add(() async {
          try {
            final result = await _itunesService.getPreviewUrlWithArt(
              trackName: post.track.trackName,
              artistName: post.track.artistName,
            );
            if (mounted) {
              _previewUrlCache[post.postId] = result?['previewUrl'];
            }
          } catch (_) {
            _previewUrlCache[post.postId] = null;
          }
        }());
      }

      // バッチ内の全URL取得が完了するまで待ってから次の3件へ
      await Future.wait(futures, eagerError: false);
    }
    // キャッシュが更新されたらPostCardに反映
    if (mounted) setState(() {});
  }

  /// 全投稿の裏面画像を3件ずつバッチでバックグラウンドプリフェッチ
  Future<void> _prefetchBacksideImages(List<PostModel> posts) async {
    const batchSize = 3;
    for (int i = 0; i < posts.length; i += batchSize) {
      if (!mounted) return;
      final batch = posts.skip(i).take(batchSize);
      final futures = <Future<void>>[];
      for (final post in batch) {
        // アルバムアート
        final albumUrl = post.track.albumImageUrl;
        if (albumUrl.isNotEmpty && albumUrl.startsWith('http')) {
          futures.add(precacheImage(CachedNetworkImageProvider(albumUrl), context));
        }
        // ユーザーアイコン
        final iconUrl = post.userIconUrl;
        if (iconUrl != null && iconUrl.isNotEmpty && iconUrl.startsWith('http')) {
          futures.add(precacheImage(CachedNetworkImageProvider(iconUrl), context));
        }
        // 投稿写真
        final photoUrl = post.photoUrl;
        if (photoUrl != null && photoUrl.isNotEmpty && photoUrl.startsWith('http')) {
          futures.add(precacheImage(CachedNetworkImageProvider(photoUrl), context));
        }
        // いいねユーザーアイコン（表示上限の3件のみ）
        for (final likedIconUrl in post.likedByUserIconUrls.take(3)) {
          if (likedIconUrl.isNotEmpty && likedIconUrl.startsWith('http')) {
            futures.add(precacheImage(CachedNetworkImageProvider(likedIconUrl), context));
          }
        }
      }
      // バッチ内の全画像が完了するまで待ってから次の3件へ
      await Future.wait(futures, eagerError: false);
    }
  }
}

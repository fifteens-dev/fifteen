part of '../home_screen.dart';

// setState は State の protected メンバー。extension から呼ぶと警告が出るが、
// 同じ State の一部として切り出しただけなので問題ない。
// ignore_for_file: invalid_use_of_protected_member

/// 投稿フローへの導線と、投稿に写真を足す導線。
///
/// 通知の時刻（21:00）より前は開けない、未投稿なら自動で開く、といった
/// サイクルの判定もここに寄せている。
extension HomePostFlow on _HomeScreenState {

  /// 写真を足せる時間帯かを調べる。通知時刻の取得を含むので非同期。
  Future<void> _loadCanAddPhoto() async {
    final can = await PostPhotoService.instance.canAddPhotoNow();
    if (mounted && can != _canAddPhoto) setState(() => _canAddPhoto = can);
  }

  /// 自分の投稿に既に写真が付いているかを調べる。
  /// 付いている投稿では「写真を追加する」バーを出さない。
  Future<void> _loadPhotoFlags(List<PostModel> posts) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return;
    final mine = [
      for (final p in posts)
        if (p.userId == uid) p.postId,
    ];
    if (mine.isEmpty) return;
    final photos = await PostPhotoService.instance.photoUrls(mine);
    if (mounted && photos.isNotEmpty) {
      setState(() => _postsWithPhoto = {..._postsWithPhoto, ...photos.keys});
    }
  }

  /// 投稿カードのバーから写真を足す。
  ///
  /// バーを消すのは [_onPhotoAdded] に任せる。追加の経路はここだけでなく
  /// 投稿完了シートからもあるので、消す側を一本にしておく。
  Future<void> _addPhoto(String postId) async {
    await AddPhotoFlow.start(context, postId: postId);
  }

  /// 投稿されたら、サイクルの投稿済み判定と温めた履歴を入れ直す。
  void _onPostCreated() {
    _postedThisCycle = true;
    _postedThisCycleFor = MusicMemoryCycleService().notifiedAt;
    _warmTracks = null; // 次のサイクルで取り直す
  }

  /// 覚えてある「投稿済み」が、今のサイクルのものか。
  /// 違えば調べ直す（アプリを開いたまま 21:00 をまたいだとき）。
  bool _postedKnownFor(DateTime? cycleStart) =>
      _postedThisCycle != null && _postedThisCycleFor == cycleStart;

  /// 写真が付いた投稿を覚えて「写真を追加する」バーを消す（1 投稿に 1 枚）。
  void _onPhotoAdded() {
    final added = PostPhotoService.instance.photoAdded.value;
    if (!mounted || added.isEmpty) return;
    if (added.every(_postsWithPhoto.contains)) return;
    setState(() => _postsWithPhoto = {..._postsWithPhoto, ...added});
  }

  /// 起動時・フォアグラウンド復帰時に画面へ割り込む処理を順番に走らせる。
  ///
  /// どちらも全画面なので、同時に出すと重なってしまう。投稿フローを開いた
  /// ときは友達成立のお祝いを見送り、次にアプリを開いたときに回す。
  /// 曲選びのモーダルに渡す再生履歴を先に取っておく。
  ///
  /// モーダルは開いてから Apple Music に聞きに行くので、その間スピナーに
  /// なる。投稿できる時間帯なら、押される前に取っておく。
  /// 失敗しても黙って諦める（モーダル側が従来どおり取りに行く）。
  Future<void> _warmUpTracks() async {
    if (_warmTracks != null) return;
    try {
      final service = await _musicServiceManager.getSelectedService();
      if (service != MusicServiceType.appleMusic) return;
      final tracks = await AppleMusicService().getRecentlyPlayedTracks(limit: 15);
      if (mounted && tracks.isNotEmpty) _warmTracks = tracks;
    } catch (_) {/* 温められなくても本体は動く */}
  }

  Future<void> _runStartupFlows() async {
    final openedPostFlow = await _maybeOpenPostFlowForCycle();
    // 自動で開かなかった＝投稿ボタンから入る可能性がある。履歴を温めておく。
    if (!openedPostFlow && _postedThisCycle == false) {
      // ignore: discarded_futures
      _warmUpTracks();
    }
    if (openedPostFlow || !mounted) return;
    await FriendMatchService.instance.maybeCelebrate(context);
  }

  // ボトムナビゲーションのタップ処理
  /// VibeバーのVibeアイコン円タップでVibeプレイリスト画面へ遷移
  Future<void> _navigateToVibePost() async {
    // データ未ロード/失敗時は強制的に再読み込み
    _vibeDataFuture ??= _loadVibeData();
    final data = await _vibeDataFuture!;
    if (!mounted) return;
    final topic = data['topic'] as VibeTopicModel?;
    final ranking =
        (data['ranking'] as List?)?.cast<VibeRankingItem>() ?? <VibeRankingItem>[];

    // トピックが取れなかった場合は再読み込みしてもう一度試す
    if (topic == null) {
      _vibeDataFuture = _loadVibeData();
      final retry = await _vibeDataFuture!;
      if (!mounted) return;
      final retryTopic = retry['topic'] as VibeTopicModel?;
      final retryRanking = (retry['ranking'] as List?)
              ?.cast<VibeRankingItem>() ??
          <VibeRankingItem>[];
      if (retryTopic == null) {
        _showMessage('お題が見つかりませんでした');
        return;
      }
      _navigateToVibePlaylistInternal(retryTopic, retryRanking);
      return;
    }

    _navigateToVibePlaylistInternal(topic, ranking);
  }

  /// VibePlaylistScreen への実遷移
  Future<void> _navigateToVibePlaylistInternal(
    VibeTopicModel topic,
    List<VibeRankingItem> ranking,
  ) async {
    _homeAudioService.stop();
    if (TutorialController.instance.step == TutorialStep.showVibePlaylistHint) {
      await TutorialController.instance.goTo(TutorialStep.swipeUpInPlaylist);
    }
    if (!mounted) return;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => VibePlaylistScreen(
          topic: topic,
          ranking: ranking,
          currentUserId: _auth.currentUser?.uid ?? '',
          hasPostedToday: _hasPostedToday,
        ),
      ),
    );
  }

  /// 「楽曲をVibeに追加」ボタンタップで投稿フロー（楽曲選択）へ遷移
  Future<void> _navigateToPostFlow() async {
    _homeAudioService.stop();

    final targetIndex = await Navigator.push<int>(
      context,
      PageRouteBuilder(
        pageBuilder: (_, __, ___) => const MusicSelectionScreen(initialCategoryType: 'vibe', fromVibePlaylist: true),
        transitionDuration: Duration.zero,
        reverseTransitionDuration: Duration.zero,
      ),
    );
    if (targetIndex != null && mounted) {
      setState(() => _selectedIndex = targetIndex);
    }
  }

  /// 通知（21:00）以降まだ投稿していないユーザーは、アプリを開いた時点で
  /// 投稿フローを開く。
  ///
  /// 締切（翌 01:00）を過ぎたら促さない。1 サイクルにつき 1 回だけで、
  /// 閉じたあとに何度も開き直すことはない（記録は端末に残す）。
  /// 締切前で未投稿なら投稿フローを開く。
  /// 戻り値は「この呼び出しで投稿フローを開いたか」。開いたときに
  /// 別の全画面表示を重ねないよう、呼び出し側が見る。
  Future<bool> _maybeOpenPostFlowForCycle() async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return false;
    try {
      final cycle = MusicMemoryCycleService();
      // 開いたまま 21:00 をまたいでいることがあるので、古ければ取り直す。
      final cycleStart = await cycle.ensureFreshNotifiedAt();
      if (cycleStart == null) return false;

      final now = DateTime.now();
      if (now.isBefore(cycleStart)) return false; // まだ通知前
      final deadline = MusicMemoryCycleService.deadlineFor(cycleStart);
      if (!now.isBefore(deadline)) return false; // 締切超過

      // まだ投稿していなければ開く。
      //
      // 以前は「1 サイクルに 1 回だけ」にしていたが、開いて閉じてしまうと
      // その日はもう出ず、「出る時と出ない時がある」と見えていた。
      // 投稿を済ませれば出なくなるので、回数で止める必要はない。
      final posted = await _postService.hasAnyPostInCurrentCycle(uid);
      _postedThisCycle = posted;
      _postedThisCycleFor = cycleStart;
      if (posted) return false;
      if (!mounted) return false;

      // 画面が組み上がってから開く（initState から呼ばれる経路があるため）。
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _openPostFlow();
      });
      return true;
    } catch (e) {
      if (kDebugMode) AppLog.debug('_maybeOpenPostFlowForCycle error: $e');
      return false;
    }
  }

  /// 投稿フローの起点（ホームの FAB から呼ぶ）。
  /// - Apple Music: 「今日のMusic Memory」カルーセル(MusicMemoryModal)。
  /// - Spotify / 未連携: ログが取れないため Vibe 楽曲選択シート（お題非表示）→
  ///   曲決定で Apple と同じく最終確認(MoodPostFinalPreviewScreen)へ。
  /// 投稿フローを開く。投稿できるのは通知（21:00）から 24:00 までの間だけで、
  /// それ以外の時間は開かずに理由を出す。
  /// 投稿フローを開く。
  ///
  /// 投稿できるのは 21:00 以降。24:00 を過ぎても投稿はできる（写真だけ足せない）。
  Future<void> _openPostFlow() async {
    final cycle = MusicMemoryCycleService();
    // 開いたまま 21:00 をまたいでいることがあるので、古ければ取り直す。
    final start = await cycle.ensureFreshNotifiedAt();
    if (start == null || DateTime.now().isBefore(start)) {
      if (!mounted) return;
      AppToast.show(context, '21時から投稿できます');
      return;
    }

    // 1 サイクル（通知から翌日の通知まで）に投稿できるのは 1 回だけ。
    // 全員が同じ 1 曲を出し合う場なので、何度も出せると意味が薄れる。
    // 管理者は動作確認のために制限しない。
    //
    // 判定は起動時に調べた [_postedThisCycle] を使う。ここで毎回 Firestore へ
    // 聞くと、その往復ぶんモーダルが出るのが遅れる。まだ調べていないとき
    // （起動直後にすぐ押した等）だけ聞きに行く。
    if (!context.read<CurrentUserProvider>().isAdmin) {
      final uid = _auth.currentUser?.uid;
      var posted = _postedKnownFor(start) ? _postedThisCycle : null;
      if (posted == null && uid != null) {
        posted = await _postService.hasAnyPostInCurrentCycle(uid);
        _postedThisCycle = posted;
        _postedThisCycleFor = start;
      }
      if (posted == true) {
        if (!mounted) return;
        AppToast.show(context, '今日はもう投稿しています');
        return;
      }
    }
    if (!mounted) return;

    _homeAudioService.stop();
    final service = await _musicServiceManager.getSelectedService();
    if (!mounted) return;
    if (service == MusicServiceType.appleMusic) {
      // 温めてある履歴があれば渡す。モーダルはそれを即座に並べ、裏で
      // 取り直して差し替える（[MusicMemoryModal]）。
      await MusicMemoryModal.open(context, tracks: _warmTracks);
    } else {
      VibeStoryPostSheet.show(
        context,
        moodPostMode: true,
        // Apple Music 側と同じく、写真の工程は挟まず最終確認へ直行する。
        onTrackChosen: (track) =>
            MoodPostFinalPreviewScreen.open(context, track),
      );
    }
  }
}

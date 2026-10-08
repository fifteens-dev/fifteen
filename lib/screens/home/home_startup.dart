part of '../home_screen.dart';

// setState は State の protected メンバー。extension から呼ぶと警告が出るが、
// 同じ State の一部として切り出しただけなので問題ない。
// ignore_for_file: invalid_use_of_protected_member

/// 起動まわりの細々した処理と、チュートリアルの受け口。
///
/// チュートリアルは実装保留中で導線が無いが、呼ばれる側は残してある。
extension HomeStartup on _HomeScreenState {

  /// 招待コードによる自動フォローの通知を遅延送信（認証フロー完了後）
  Future<void> _processPendingFollowNotification() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final ownerUid = prefs.getString('pending_follow_owner_uid');
      if (ownerUid == null || ownerUid.isEmpty) return;

      final currentUser = _auth.currentUser;
      if (currentUser == null) return;

      // ユーザー情報が揃ってから通知を送信
      final senderUser = await _userService.getUser(currentUser.uid);
      if (senderUser == null) return;

      final username = senderUser.username;
      if (username == null || username.isEmpty || username == 'unknown') return;

      // 通知を送信
      final notificationService = NotificationService();
      await notificationService.createNotification(
        type: NotificationType.follow,
        recipientId: ownerUid,
        senderId: currentUser.uid,
        senderUsername: username,
        senderIconUrl: senderUser.profileImageUrl,
      );

      // 送信済みのpendingを削除
      await prefs.remove('pending_follow_owner_uid');
    } catch (_) {}
  }

  /// lastActiveAt を Firestore に書き込む（DAU/MAU 計測）
  /// 併せて、端末ローカルにしか無い「選択中の音楽サービス」を users doc へ同期する
  /// （管理者パネルのサービス別集計用）。同期は**そのユーザーを一度も刻んで
  /// いないときだけ**走り、既存ユーザーを埋め終われば起動時の処理は無くなる。
  Future<void> _updateLastActive() async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return;
    await _userService.updateLastActive(uid);
    await _musicServiceManager.syncSelectedServiceToProfile();
  }

  /// チュートリアル Frame628 でアクティブカードが変わったときに呼ばれる
  Future<void> _onTutorialAlbumChanged(int index) async {
    _tutorialActiveIndex = index;
    final items = TutorialAlbumCarousel.defaultItems;
    if (index >= items.length) return;
    final item = items[index];
    final cacheKey = '${item.title}__${item.artist}';
    await TutorialPrefetchService.instance.ensureReady(cacheKey, item);
    if (!mounted || _tutorialActiveIndex != index) return;
    final previewUrl = TutorialPrefetchService.instance.previewCache[cacheKey];
    if (previewUrl != null && previewUrl.isNotEmpty) {
      // owner: this を渡すことで、他画面の dispose() が呼ぶ
      // stopIfOwner() に巻き添えで止められないようにする
      _homeAudioService
          .playPreview(previewUrl, owner: this)
          .catchError((_) {});
    }
    // 次のカードを2秒遅延で preload する。
    // 即座に preload するとメインプレイヤーの再生が iOS 側で中断される現象が発生したため、
    // 現在再生中の音声が安定してから preload を開始する。
    final nextIndex = (index + 1) % items.length;
    Future.delayed(const Duration(seconds: 2), () {
      if (!mounted || _tutorialActiveIndex != index) return;
      TutorialPrefetchService.instance
          .preloadAudio(items[nextIndex])
          .catchError((_) {});
    });
  }

  /// チュートリアル Frame628 で曲が確定されたときに呼ばれる
  Future<void> _onTutorialSongConfirmed(TutorialAlbumItem item) async {
    _homeAudioService.stop();
    final cacheKey = '${item.title}__${item.artist}';
    await TutorialPrefetchService.instance.ensureReady(cacheKey, item);
    if (!mounted) return;
    final cache = TutorialPrefetchService.instance;
    final albumArtUrl = cache.artCache[cacheKey]?.isNotEmpty == true
        ? cache.artCache[cacheKey]!
        : item.assetPath;
    _tutorialTrack = TrackModel(
      trackId: 'tutorial_${item.title.hashCode}',
      trackName: item.title,
      artistName: item.artist,
      albumImageUrl: albumArtUrl,
      previewUrl: cache.previewCache[cacheKey],
    );
    await TutorialController.instance.goTo(TutorialStep.takingPhoto);
  }
}

part of '../home_screen.dart';

// setState は State の protected メンバー。extension から呼ぶと警告が出るが、
// 同じ State の一部として切り出しただけなので問題ない。
// ignore_for_file: invalid_use_of_protected_member

/// スクロールに連動する処理。再生中のカードが画面から外れたら止める、
/// 隣のカードの音源を先読みする、ヘッダのベルを薄くする。
extension HomePlayback on _HomeScreenState {

  /// 再生開始した index の隣接（i+1）投稿の音声を AudioPlayerService にプリロード。
  /// 次にタップされる可能性が高いカードの setUrl を先行実行し、
  /// タップ→再生までのネットワーク待ちをスキップする。
  void _preloadNeighborAudio(int currentIndex) {
    final posts = _cachedPosts;
    if (posts == null) return;
    final nextIndex = currentIndex + 1;
    if (nextIndex >= posts.length) return;
    final next = posts[nextIndex];
    final url = _previewUrlCache[next.postId];
    if (url == null || url.isEmpty) return;
    _homeAudioService.preload(
      url,
      startFrom: Duration(milliseconds: next.audioStartMs),
      durationSeconds: next.audioDurationSec,
    );
  }

  /// スクロール時に各カードの可視性を確認し、
  /// 最も多く見えているカード（50%超）以外の裏面カードを表面に戻す
  void _checkPlayingCardVisibility() {
    // 2列グリッドの拡大オーバーレイ表示中は、再生カードがグリッド上で
    // プレースホルダ扱いになり「画面外」と誤判定されるため、停止処理をスキップ。
    if (_gridEnlargedActive) return;
    final screenHeight = MediaQuery.of(context).size.height;

    String? dominantPostId;
    double bestVisibleFraction = 0;

    // 全カードの可視割合を計算し、最も多く見えているカードを特定
    for (final entry in _postCardKeys.entries) {
      final postId = entry.key;
      final key = entry.value;
      final renderBox = key.currentContext?.findRenderObject() as RenderBox?;
      if (renderBox == null || !renderBox.attached) continue;

      final cardTop = renderBox.localToGlobal(Offset.zero).dy;
      final cardHeight = renderBox.size.height;
      final cardBottom = cardTop + cardHeight;

      // 完全に画面外のカードはスキップ
      if (cardBottom <= 0 || cardTop >= screenHeight) continue;

      final visibleTop = cardTop.clamp(0.0, screenHeight.toDouble());
      final visibleBottom = cardBottom.clamp(0.0, screenHeight.toDouble());
      final visibleFraction = (visibleBottom - visibleTop) / cardHeight;

      if (visibleFraction > 0.5 && visibleFraction > bestVisibleFraction) {
        bestVisibleFraction = visibleFraction;
        dominantPostId = postId;
      }
    }

    // 再生中カードが画面外 or dominant以外になったら音楽を停止し、同時に表面に戻す
    if (_playingPostId != null && _playingPostId != dominantPostId) {
      _homeAudioService.stop();
      _postCardKeys[_playingPostId]?.currentState?.flipToFront();
      _playingPostId = null;
    }

    // dominant以外のカードをすべて表面に戻す（音楽停止と同タイミング）
    for (final entry in _postCardKeys.entries) {
      final postId = entry.key;
      final key = entry.value;
      if (postId != dominantPostId) {
        key.currentState?.flipToFront();
      }
    }
  }

  /// スクロール量に応じてベルアイコンの透明度を更新
  void _updateBellOpacity() {
    if (!_scrollController.hasClients) return;
    final offset = _scrollController.offset;
    _bellOpacity.value = (1.0 - (offset / 80.0)).clamp(0.0, 1.0);
  }
}

part of '../../post_card.dart';

extension PostCardAudioMethods on PostCardState {
  /// 音楽を非同期で再生（UIをブロックしない）
  ///
  /// 速度優先方針: 初回タップは「キャッシュ済URL」「外部から渡されたURL」のいずれかが
  /// あれば即 play。なければ iTunes 取得を待つが、失敗時のリトライは
  /// バックグラウンド実行（fire-and-forget）にして次回タップで拾う。
  Future<void> _playAudioAsync() async {
    // 二重呼び出し防止（自動再生とフリップが競合するケース）
    if (_isPlayAudioInProgress) return;
    _isPlayAudioInProgress = true;

    try {
      // 内部キャッシュ → 外部から渡されたURL（ホーム画面がプリフェッチ済み）の順で使う
      String? previewUrl = _cachedPreviewUrl ?? widget.externalPreviewUrl;

      // どちらもない場合、iTunes APIから取得
      if (previewUrl == null) {
        if (kDebugMode) print('🍎 Fetching preview URL from iTunes...');
        final result = await _itunesService.getPreviewUrlWithArt(
          trackName: widget.post.track.trackName,
          artistName: widget.post.track.artistName,
        );
        if (!mounted) return;

        if (result != null) {
          previewUrl = result['previewUrl'];
          // setState で更新し、波形ウィジェットにURLを反映
          setState(() { _cachedPreviewUrl = previewUrl; });
          if (kDebugMode) print('✅ iTunes preview URL obtained and cached');
        } else {
          // 1回目失敗 → リトライはバックグラウンド（初回タップは待たない）
          if (kDebugMode) print('⚠️ iTunes returned null, retry in background');
          unawaited(_retryItunesInBackground());
        }
      } else {
        if (kDebugMode) print('📦 Using cached preview URL');
      }

      if (!mounted) return;

      // プレビューURLがあれば再生
      if (previewUrl != null && previewUrl.isNotEmpty) {
        if (kDebugMode) print('▶️  Starting playback...');
        try {
          // playPreview はプリロード済みなら即スワップ→play、無ければ通常パス
          await widget.audioService.playPreview(
            previewUrl,
            startFrom: Duration(milliseconds: widget.post.audioStartMs),
            durationSeconds: widget.post.audioDurationSec,
          );
        } catch (e) {
          if (kDebugMode) print('❌ Playback error: $e');
          if (mounted) {
            AppToast.show(context, '音楽の再生に失敗しました: ${e.toString()}');
          }
        }
      } else {
        if (kDebugMode) print('⚠️  No preview URL available (retry in background)');
      }
    } finally {
      _isPlayAudioInProgress = false;
    }
  }

  /// iTunes 取得失敗時の遅延リトライ（バックグラウンド）
  /// 次回タップ時に取得済みURLを拾えるよう、結果を _cachedPreviewUrl に書く
  Future<void> _retryItunesInBackground() async {
    await Future.delayed(const Duration(seconds: 1));
    if (!mounted) return;
    try {
      final retryResult = await _itunesService.getPreviewUrlWithArt(
        trackName: widget.post.track.trackName,
        artistName: widget.post.track.artistName,
      );
      if (!mounted) return;
      if (retryResult != null) {
        final url = retryResult['previewUrl'];
        if (url != null && url.isNotEmpty) {
          setState(() { _cachedPreviewUrl = url; });
          if (kDebugMode) print('✅ iTunes background retry succeeded');
        }
      }
    } catch (e) {
      if (kDebugMode) print('❌ Background retry error: $e');
    }
  }
}

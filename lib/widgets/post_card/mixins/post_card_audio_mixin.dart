part of '../../post_card.dart';

extension PostCardAudioMethods on PostCardState {
  /// 音楽を非同期で再生（UIをブロックしない）
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
          // 1回目が失敗した場合、1秒後にリトライ
          if (kDebugMode) print('⚠️ iTunes returned null, retrying in 1s...');
          await Future.delayed(const Duration(seconds: 1));
          if (!mounted) return;
          final retryResult = await _itunesService.getPreviewUrlWithArt(
            trackName: widget.post.track.trackName,
            artistName: widget.post.track.artistName,
          );
          if (!mounted) return;
          if (retryResult != null) {
            previewUrl = retryResult['previewUrl'];
            setState(() { _cachedPreviewUrl = previewUrl; });
            if (kDebugMode) print('✅ iTunes retry succeeded');
          } else {
            if (kDebugMode) print('❌ iTunes retry also failed');
          }
        }
      } else {
        if (kDebugMode) print('📦 Using cached preview URL');
      }

      if (!mounted) return;

      // プレビューURLがあれば再生
      if (previewUrl != null && previewUrl.isNotEmpty) {
        if (kDebugMode) print('▶️  Starting playback...');
        try {
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
        if (kDebugMode) print('⚠️  No preview URL available');
        if (mounted) {
          AppToast.show(context, 'この曲のプレビューURLが見つかりません');
        }
      }
    } finally {
      _isPlayAudioInProgress = false;
    }
  }

}

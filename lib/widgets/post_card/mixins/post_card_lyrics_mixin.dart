part of '../../post_card.dart';

extension PostCardLyricsMethods on PostCardState {
  /// 歌詞を動的に取得（lyricsTextがない場合のフォールバック）
  Future<void> _fetchLyricsIfNeeded() async {
    // 既に歌詞がある場合、または取得中/取得済みの場合はスキップ
    if (widget.post.lyricsText != null || _isLyricsFetching || _lyricsFetchAttempted) {
      return;
    }

    if (!mounted) return;
    setState(() {
      _isLyricsFetching = true;
    });

    try {
      final lyricsData = await _lyricsService.getLyrics(
        trackName: widget.post.track.trackName,
        artistName: widget.post.track.artistName,
      );

      if (mounted && lyricsData != null) {
        final truncatedLyrics = _lyricsService.truncateLyrics(
          lyricsData.plainLyrics,
          maxLines: 4,
        );
        setState(() {
          _fetchedLyricsText = truncatedLyrics;
        });
        debugPrint('✅ PostCard: 歌詞を動的に取得しました');

        // Firebaseに保存（テスト投稿以外の場合）
        final postId = widget.post.postId;
        if (!postId.startsWith('test_post_') && !postId.startsWith('preview_')) {
          await _postService.updateLyricsText(
            postId: postId,
            lyricsText: truncatedLyrics,
          );
        }
      }
    } catch (e) {
      debugPrint('❌ PostCard: 歌詞取得エラー: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isLyricsFetching = false;
          _lyricsFetchAttempted = true;
        });
      }
    }
  }
}

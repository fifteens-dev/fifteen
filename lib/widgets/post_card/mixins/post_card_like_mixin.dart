part of '../../post_card.dart';

extension PostCardLikeMethods on PostCardState {
  /// いいねボタンが押された時の処理（楽観的UI更新）
  void _handleLikeTap() {
    if (widget.disableInteractions) {
      RestrictionNotification.show(context, message: 'いいねができません');
      return;
    }
    if (widget.onLike != null) {
      setState(() {
        final currentIsLiked = _isLikedOptimistic ??
            (widget.currentUserId != null &&
                widget.post.isLikedBy(widget.currentUserId!));
        final currentLikeCount = _likeCountOptimistic ?? widget.post.likeCount;
        final currentIconUrls = _likedByUserIconUrlsOptimistic ??
            List<String>.from(widget.post.likedByUserIconUrls);

        _isLikedOptimistic = !currentIsLiked;
        _likeCountOptimistic =
            currentIsLiked ? currentLikeCount - 1 : currentLikeCount + 1;

        // アイコンURLリストも楽観的に更新
        if (currentIsLiked) {
          // いいね解除：自分のアイコンを削除
          if (widget.currentUserIconUrl != null) {
            currentIconUrls.remove(widget.currentUserIconUrl);
          } else if (currentIconUrls.isNotEmpty) {
            // アイコンURLがない場合は最後の要素を削除
            currentIconUrls.removeLast();
          }
        } else {
          // いいね追加：自分のアイコンを追加
          final iconUrl = widget.currentUserIconUrl ?? '';
          currentIconUrls.add(iconUrl);
        }
        _likedByUserIconUrlsOptimistic = currentIconUrls;
      });

      widget.onLike!();
    }
  }

  /// 楽観的UI状態をクリア（postIdが変わった場合）
  void _clearLikeOptimistic() {
    _isLikedOptimistic = null;
    _likeCountOptimistic = null;
    _likedByUserIconUrlsOptimistic = null;
  }

  /// Firestoreの値と楽観的UI状態が一致したらクリア
  void _syncLikeOptimisticWithActual() {
    if (_isLikedOptimistic != null || _likeCountOptimistic != null || _likedByUserIconUrlsOptimistic != null) {
      final actualIsLiked = widget.currentUserId != null &&
          widget.post.isLikedBy(widget.currentUserId!);
      final actualLikeCount = widget.post.likeCount;

      if (_isLikedOptimistic == actualIsLiked &&
          _likeCountOptimistic == actualLikeCount) {
        _isLikedOptimistic = null;
        _likeCountOptimistic = null;
        _likedByUserIconUrlsOptimistic = null;
      }
    }
  }
}

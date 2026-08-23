part of '../../post_card.dart';

/// 絵文字リアクション（1ユーザー＝1つ）のUI制御。
/// スマイルボタン → 絵文字ピッカー吹き出し → 選択で「ふわっと上がる」アニメ、
/// および楽観的なリアクション状態を扱う。
extension PostCardReactionMethods on PostCardState {
  /// 楽観的上書きを考慮した「自分のリアクション」絵文字（無ければ null）。
  String? get effectiveMyReaction {
    if (_hasReactionOverride) return _reactionOverride;
    return widget.post.reactionOf(widget.currentUserId);
  }

  /// 楽観的上書きを反映したリアクション一覧（新しい順）。
  List<PostReaction> get effectiveReactions {
    final base = List<PostReaction>.from(widget.post.reactions);
    final me = widget.currentUserId;
    if (!_hasReactionOverride || me == null) return base;
    base.removeWhere((r) => r.userId == me);
    if (_reactionOverride != null) {
      base.insert(
        0,
        PostReaction(
          userId: me,
          emoji: _reactionOverride!,
          iconUrl: widget.currentUserIconUrl ?? '',
          ts: DateTime.now().millisecondsSinceEpoch,
        ),
      );
    }
    return base;
  }

  /// スマイルボタンタップ → ピッカー吹き出しを表示。
  void _showReactionPicker(BuildContext anchorContext) {
    if (widget.disableInteractions) {
      RestrictionNotification.show(context, message: 'リアクションができません');
      return;
    }
    _dismissReactionPicker();

    final box = anchorContext.findRenderObject() as RenderBox?;
    final overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox?;
    if (box == null || overlay == null) return;

    final topLeft = box.localToGlobal(Offset.zero, ancestor: overlay);
    final rect = topLeft & box.size;
    _reactionAnchorRect = rect;

    // カード表示倍率 s（スマイル実寸 / Figma上のスマイル幅32 = cardWidth/363）。
    final double s = rect.width / 32.0;
    final double bubbleW = 331.0 * s;
    final double screenW = overlay.size.width;
    const double margin = 6.0;

    // 尻尾の先端(左下)がスマイル中心を指す。吹き出しは先端が左寄りになるよう配置し、
    // 画面内に収める。
    double left = rect.center.dx - 22.0 * s; // 先端を吹き出し左寄りに
    final double maxLeft = screenW - bubbleW - margin;
    left = left.clamp(margin, maxLeft > margin ? maxLeft : margin);
    // クランプ後も先端はスマイル中心を指す（吹き出し内クランプは Bubble 側で実施）。
    final double tailTipX = rect.center.dx - left;
    final double bottomFromTop = rect.top - 2.0 * s;

    HapticFeedback.selectionClick();
    _reactionPickerEntry = OverlayEntry(
      builder: (ctx) {
        final size = MediaQuery.of(ctx).size;
        return Stack(
          children: [
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: _dismissReactionPicker,
              ),
            ),
            Positioned(
              left: left,
              bottom: size.height - bottomFromTop,
              // Overlay 直下は Material が無く Text に黄色い二重下線が付くため、
              // 透明 Material で包んで DefaultTextStyle を供給する。
              child: Material(
                type: MaterialType.transparency,
                child: ReactionPickerBubble(
                  scale: s,
                  tailTipX: tailTipX,
                  onSelected: _onReactionEmojiSelected,
                ),
              ),
            ),
          ],
        );
      },
    );
    Overlay.of(context).insert(_reactionPickerEntry!);
  }

  void _dismissReactionPicker() {
    _reactionPickerEntry?.remove();
    _reactionPickerEntry = null;
  }

  /// 絵文字が選ばれたとき: ピッカーを閉じ → 楽観更新 → ふわっとアニメ → コールバック。
  void _onReactionEmojiSelected(String emoji) {
    _dismissReactionPicker();

    // 楽観的更新（同じ絵文字なら解除、違えば変更、無ければ追加）
    final current = effectiveMyReaction;
    setState(() {
      _hasReactionOverride = true;
      _reactionOverride = (current == emoji) ? null : emoji;
    });

    // 追加/変更のときだけ、ふわっと上がるアニメを出す（解除時は出さない）。
    if (_reactionOverride != null) {
      _showReactionBurst(emoji);
      HapticFeedback.lightImpact();
    }

    widget.onReaction?.call(emoji);
  }

  /// タップした絵文字が上へふわっと上がって消えるアニメを Overlay で再生。
  void _showReactionBurst(String emoji) {
    final rect = _reactionAnchorRect;
    if (rect == null) return;
    _reactionBurstEntry?.remove();
    final origin = Offset(rect.center.dx, rect.top);
    late final OverlayEntry entry;
    entry = OverlayEntry(
      builder: (ctx) => ReactionBurstOverlay(
        origin: origin,
        emoji: emoji,
        onDone: () {
          entry.remove();
          if (_reactionBurstEntry == entry) _reactionBurstEntry = null;
        },
      ),
    );
    _reactionBurstEntry = entry;
    Overlay.of(context).insert(entry);
  }

  /// postId が変わった/破棄時に、開いているオーバーレイを片付ける。
  void _clearReactionOverlays() {
    _reactionPickerEntry?.remove();
    _reactionPickerEntry = null;
    _reactionBurstEntry?.remove();
    _reactionBurstEntry = null;
  }

  /// postId が変わったら楽観的リアクションをリセット。
  void _clearReactionOptimistic() {
    _reactionOverride = null;
    _hasReactionOverride = false;
  }

  /// Firestore の実データが楽観的上書きに追いついたらクリアする（同一投稿の更新時）。
  void _syncReactionOptimistic() {
    if (!_hasReactionOverride) return;
    final actual = widget.post.reactionOf(widget.currentUserId);
    if (actual == _reactionOverride) {
      _reactionOverride = null;
      _hasReactionOverride = false;
    }
  }
}

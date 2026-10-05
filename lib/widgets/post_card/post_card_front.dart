part of '../post_card.dart';

/// 投稿カードの表面。
///
/// アルバムアートの上に、下 294px ぶんのグラデーションを敷いて
/// ユーザー・曲名・リアクション・波形を重ねる。座標は Figma の
/// 363×645 を基準に、枠の比で持っている（カードは拡縮される）。
///
/// 裏面は中身ごとに別ファイルに分かれている（post_card_back_photo /
/// _profile / _info）。表面もそれに揃えてここへ出した。本体の
/// post_card.dart には、表裏の切り替えと両面で使うものだけが残る。
extension PostCardFront on PostCardState {

  /// カード表面（アルバムカバー全表示）
  Widget _buildFront() {
    final theme = _getDynamicTheme();

    return GestureDetector(
      onTap: _flipCard,
      child: LayoutBuilder(
        builder: (context, constraints) {
          // 実際のレンダリングサイズを使用（制約を受けた場合でも正確）
          final cardWidth = constraints.maxWidth > 0 ? constraints.maxWidth : 363.0;
          final cardHeight = constraints.maxHeight > 0 ? constraints.maxHeight : 645.0;
          final albumSize = cardWidth; // アルバムカバーは正方形（カード幅と同じ）
          final contentHeight = cardHeight * (295.0 / 645.0); // タイトルエリア

          return Container(
            width: cardWidth,
            height: cardHeight,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(PostCardConstants.cardBorderRadius),
              color: theme.gradientEnd,
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(PostCardConstants.cardBorderRadius),
              child: Stack(
            children: [
              // アルバムカバー（全表示）
              Positioned(
                left: 0,
                top: 0,
                child: Container(
                  width: albumSize,
                  height: albumSize,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(3),
                  ),
                  child: _displayAlbumArtUrl.isNotEmpty
                      ? _buildAlbumArt(
                          _displayAlbumArtUrl,
                          fit: BoxFit.cover,
                          errorWidget: _buildAlbumPlaceholder(),
                        )
                      : _buildAlbumPlaceholder(),
                ),
              ),

              // 公開範囲バッジ（地球儀/鍵）は廃止。投稿は自動でフォロワー限定判定のため不要。

              // グラデーションオーバーレイ（下部3/7）
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                height: contentHeight,
                child: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        theme.gradientStart
                            .withOpacity(0.0), // 上端は透明（アルバムと重なる部分）
                        theme.gradientEnd, // 13px以降は不透明
                      ],
                      stops: const [
                        0.0,
                        0.0442
                      ], // 上部4.42% (13px/294px) でグラデーション完了
                    ),
                  ),
                ),
              ),

              // コンテンツ（下部）- Figmaに合わせて絶対配置
              // Figmaは下から計測（Y軸反転）なので、294px基準で変換
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                height: contentHeight,
                child: Stack(
                  children: [
                    // ユーザー情報 - Figma: bottom: 238px → top: 56px (294-238), left: 12px
                    Positioned(
                      left: cardWidth * (12 / 363),
                      top: contentHeight * (24 / 294),
                      child: _buildUserInfo(theme),
                    ),

                    // 曲名とアーティスト名 - ボタン有無で right を動的調整
                    // menu(32) + rightMargin(11) = 43px
                    // hideCommentBar 時はコメントバー分を詰めて中央寄りに(Figma 4947:10749)。
                    Positioned(
                      left: cardWidth * (11 / 363),
                      top: contentHeight * ((_effHideCommentBar ? 79 : 63) / 294),
                      right: _showMoreButton
                          ? cardWidth * (43 / 363)
                          : cardWidth * (12 / 363),
                      child: _buildTrackInfo(theme),
                    ),

                    // 共有ボタン（3点メニューのすぐ左・自分の投稿のみ）
                    if (_isOwner && !widget.hideShareButton)
                      Positioned(
                        right: cardWidth * (47 / 363),
                        top: contentHeight * (63 / 294),
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: widget.onShare ?? _handleShare,
                          child: () {
                            final hsl = HSLColor.fromColor(theme.gradientEnd);
                            final newL = hsl.lightness > 0.5
                                ? (hsl.lightness - 0.1).clamp(0.0, 1.0)
                                : (hsl.lightness + 0.1).clamp(0.0, 1.0);
                            return Container(
                              width: 36,
                              height: 36,
                              decoration: BoxDecoration(
                                color: hsl.withLightness(newL).toColor(),
                                shape: BoxShape.circle,
                              ),
                              child: Center(
                                child: Image.asset(
                                  'assets/icons/share_button.png',
                                  width: 36,
                                  height: 36,
                                  color: theme.textColor,
                                  colorBlendMode: BlendMode.srcIn,
                                ),
                              ),
                            );
                          }(),
                        ),
                      ),

                    // 3点メニューボタン
                    if (_showMoreButton)
                    Positioned(
                      right: cardWidth * (11 / 363),
                      top: contentHeight * (63 / 294),
                      child: _buildMoreButton(theme),
                    ),

                    // リアクション行 - Figma 5111/4947: top 153px, スマイル left12 /
                    // プラス left82、リアクションアバターは右端 x348（right 15px）。
                    Positioned(
                      left: cardWidth * (12 / 363),
                      right: cardWidth * (15 / 363),
                      top: contentHeight * ((_effHideCommentBar ? 153 : 128) / 294),
                      child: _buildReactions(theme),
                    ),

                    // 音楽波形 - Figma 5111:10598: left 18px, top 205px（コメントバー無し時）
                    Positioned(
                      left: cardWidth * (18 / 363),
                      top: contentHeight * ((_effHideCommentBar ? 205 : 166) / 294),
                      child: _buildWaveform(theme),
                    ),

                    // コメント入力欄 - コメント機能を切っている間は非表示。
                    if (PostCardState.kCommentsEnabled && !widget.hideCommentBar)
                      Positioned(
                        left: cardWidth * (12 / 363),
                        right: cardWidth * (12 / 363),
                        top: contentHeight * (211 / 294),
                        child: _buildCommentButton(theme),
                      ),

                    // 「写真を追加する」バー（Figma 5858-11628）。
                    // コメント入力欄と同じ枠（top 211px, left 13 / right 12）。
                    // カード下端に置くと著作表示に重なる。
                    if (widget.onAddPhoto != null)
                      Positioned(
                        left: cardWidth * (13 / 363),
                        right: cardWidth * (12 / 363),
                        top: contentHeight * (211 / 294),
                        child: AddPhotoBar(
                          // 色の元はカード本体（グラデーションの終端）。
                          background:
                              AddPhotoBar.backgroundFor(theme.gradientEnd),
                          foreground: theme.textColor,
                          onTap: widget.onAddPhoto,
                          label: widget.addPhotoLabel,
                        ),
                      ),

                    // "Provided courtesy of Apple Music" - Figma: bottom: 12px → top: 282px (294-12), left: 17px
                    Positioned(
                      left: cardWidth * (17 / 363),
                      top: contentHeight * (268 / 294),
                      child: Text(
                        'Provided courtesy of Apple Music',
                        style: TextStyle(
                          fontSize: 10,
                          color: theme.secondaryTextColor.withOpacity(0.7),
                        ),
                      ),
                    ),
                  ],
                ),
              ),

            ],
          ),
        ),
      );
        },
      ),
    );
  }

  /// アルバムプレースホルダー
  Widget _buildAlbumPlaceholder() {
    return Container(
      color: Colors.grey[800],
      child: const Center(
        child: Icon(
          Icons.album,
          size: 120,
          color: Colors.white54,
        ),
      ),
    );
  }

  /// コメントボタン
  Widget _buildCommentButton(PostTheme theme) {
    if (widget.disableInteractions) {
      // 制限中：グレーアウト表示してタップ時に通知
      return GestureDetector(
        onTap: () => RestrictionNotification.show(context, message: 'コメントができません'),
        child: Opacity(
          opacity: 0.35,
          child: Container(
            height: 43,
            decoration: BoxDecoration(
              color: theme.commentButtonColor,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                const SizedBox(width: 12),
                Text(
                  'コメントする',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: theme.textColor,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }
    return GestureDetector(
      onTap: widget.onComment,
      child: Container(
        height: 43,
        decoration: BoxDecoration(
          color: theme.commentButtonColor,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            const SizedBox(width: 12),
            Text(
              'コメントする',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: theme.textColor,
              ),
            ),
            const Spacer(),
            Image.asset(
              'assets/icons/comment_send_button.png',
              width: 20,
              height: 20,
              color: theme.textColor.withOpacity(0.6),
            ),
            const SizedBox(width: 12),
          ],
        ),
      ),
    );
  }

  /// 音楽波形
  /// 大、小、大のパターン（各投稿でpostIdをシードとして微妙に異なるパターン）
  Widget _buildWaveform(PostTheme theme) {
    return RepaintBoundary(
      child: AnimatedWaveform(
        postId: widget.post.postId,
        barColor: theme.iconColor,
        audioService: widget.audioService,
        previewUrl: _cachedPreviewUrl ?? widget.externalPreviewUrl,
        tempo: _tempo,
      ),
    );
  }

  /// 曲名とアーティスト名（表面）
  Widget _buildTrackInfo(PostTheme theme) {
    // Positionedで配置されているため、利用可能な幅を計算
    // left: 11px, right: 66px → 利用可能幅: 363 - 11 - 66 = 286px
    const availableWidth = 286.0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        MarqueeText(
          textSpan: PostCardState._buildWeightAdjustedSpan(
            widget.post.track.trackName,
            baseStyle: TextStyle(
              fontSize: 21,
              fontWeight: FontWeight.w700,
              color: theme.textColor,
            ),
          ),
          width: availableWidth,
        ),
        const SizedBox(height: 4),
        GestureDetector(
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => ArtistProfileScreen(
                artistName: widget.post.track.artistName,
                spotifyArtistId: widget.post.track.spotifyArtistId,
              ),
            ),
          ),
          child: Opacity(
            opacity: 0.8,
            child: PostCardState._buildWeightAdjustedText(
              widget.post.track.artistName,
              fontSize: 11,
              baseWeight: FontWeight.w400,
              color: theme.textColor,
            ),
          ),
        ),
      ],
    );
  }

  /// リアクション（スマイル＝絵文字リアクション、追加）
  Widget _buildReactions(PostTheme theme) {
    // Figma 5111:10598: スマイル left12・プラス left82（ともに 32×32）。
    // 行の起点は left12 なので、スマイル(32)→隙間(38)→プラス(32) で left82 に合う。
    return Row(
      children: [
        // スマイル（絵文字リアクション）。背景に応じて白/黒が切り替わる。
        _buildSmileyButton(size: 32, color: theme.iconColor),
        const SizedBox(width: 38),

        // コメント（接続を切っている。PostCardState.kCommentsEnabled=false で復活可）
        if (PostCardState.kCommentsEnabled) ...[
          _buildCommentReaction(
            count: widget.post.commentCount,
            onTap: widget.onComment,
            theme: theme,
          ),
          const SizedBox(width: 38),
        ],

        // 追加（保存ボタン）
        _buildSaveButton(theme: theme, size: 32),

        if (!widget.hideReactionCounts) ...[
          const Spacer(),
          // リアクションしたユーザーのアバター＋絵文字（最大2人）
          _buildReactorAvatars(),
        ],
      ],
    );
  }

  /// スマイル（リアクション）ボタン。タップで絵文字ピッカーを開く。
  /// [color] を渡すと白黒の PNG を srcIn で着色（他アイコンと同じく背景に応じて
  /// 白/黒が切り替わるよう、表面では theme.iconColor を渡す）。
  Widget _buildSmileyButton({required double size, Color? color}) {
    return Builder(
      builder: (btnCtx) => GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => _showReactionPicker(btnCtx),
        child: Image.asset(
          'assets/icons/reaction_smile.png',
          width: size,
          height: size,
          color: color,
          colorBlendMode: color != null ? BlendMode.srcIn : null,
        ),
      ),
    );
  }

  /// リアクションアバター（裏面用 - 相対サイズ 32/363）
  Widget _buildReactorAvatars() {
    return _buildReactorAvatarsCommon(iconSize: 32);
  }

  /// ユーザー情報（表面の下部）
  Widget _buildUserInfo(PostTheme theme) {
    final teamId = widget.post.adlTeamId;
    // 同日2投稿目以降（countsForAdl == false）はハンドル非表示。
    final hasTeam = teamId != null &&
        teamId.isNotEmpty &&
        widget.post.countsForAdl != false;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // ユーザーアイコン + 名前（タップでユーザープロフィール）
        GestureDetector(
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => OtherUserProfileScreen(
                  userId: widget.post.userId,
                ),
              ),
            );
          },
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.grey[400],
                ),
                child: ClipOval(
                  child: ProfileImage(
                    imageUrl: widget.post.userIconUrl,
                    size: 32,
                  ),
                ),
              ),
              const SizedBox(width: 9), // Figma: アイコン right44 → 名前 left53
              PostCardState._buildWeightAdjustedText(
                widget.post.username,
                fontSize: 12,
                baseWeight: FontWeight.w600,
                color: theme.textColor,
              ),
            ],
          ),
        ),

        // 班ハンドル（@◯◯班）。タップで班プロフィールへ。ADLハンドルは非表示。
        if (hasTeam && _showAdlTeamHandle) ...[
          const SizedBox(width: 6),
          GestureDetector(
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => AdlTeamPlaylistScreen(teamId: teamId),
                ),
              );
            },
            child: Text(
              '@${AdlTeamDefinitions.displayNameOf(teamId)}',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                // 背景色に合わせて黒/白が切り替わる（ユーザー名と同じ規則）
                // ややトーンダウンさせて補助情報として馴染ませる
                color: theme.textColor.withValues(alpha: 0.7),
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildMoreButton(PostTheme theme, {Color? color}) {
    final _moreButtonColor = color;
    return NativePullDownButton(
      items: [
        if (_isOwner && widget.onDelete != null)
          const NativeMenuItem(id: 'delete', title: '削除', type: 'destructive', icon: 'trash'),
        if (!_isOwner)
          const NativeMenuItem(id: 'report', title: '通報', type: 'destructive', icon: 'exclamationmark.triangle'),
      ],
      onSelected: (id) async {
        if (id == 'delete') widget.onDelete?.call();
        if (id == 'report') {
          await showReportDialog(
            context,
            reportedUserId: widget.post.userId,
            postId: widget.post.postId,
          );
        }
      },
      child: SizedBox(
        width: 32,
        height: 36,
        child: Icon(Icons.more_vert, color: _moreButtonColor ?? theme.iconColor, size: 22),
      ),
    );
  }

  Widget _buildSaveButton({
    required PostTheme theme,
    Color? color,
    double size = 32,
  }) {
    return GestureDetector(
      onTap: widget.onAdd,
      child: widget.isSaved
          ? _buildSavedIcon(size: size)
          : Icon(
              Icons.add_circle_outline,
              size: size,
              color: color ?? theme.iconColor,
            ),
    );
  }

  /// 保存済みアイコン（緑色の円 + 灰色のチェックマーク）
  Widget _buildSavedIcon({double size = 32}) {
    return Stack(
      alignment: Alignment.center,
      children: [
        // 背景：明るい緑色の塗りつぶし円
        Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            color: Colors.lightGreen,
            shape: BoxShape.circle,
          ),
        ),
        // 前景：灰色のチェックマーク
        Icon(
          Icons.check,
          size: size * 0.72,
          color: Colors.grey[700],
        ),
      ],
    );
  }
}

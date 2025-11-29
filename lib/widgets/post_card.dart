import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../models/post_model.dart';
import '../models/post_theme.dart';

/// 投稿カードウィジェット（表裏反転アニメーション付き）
class PostCard extends StatefulWidget {
  final PostModel post;
  final VoidCallback? onLike;
  final VoidCallback? onComment;
  final VoidCallback? onAdd;
  final String? currentUserId;

  const PostCard({
    super.key,
    required this.post,
    this.onLike,
    this.onComment,
    this.onAdd,
    this.currentUserId,
  });

  @override
  State<PostCard> createState() => _PostCardState();
}

class _PostCardState extends State<PostCard> with SingleTickerProviderStateMixin {
  late AnimationController _flipController;
  late Animation<double> _flipAnimation;
  bool _showFront = true;

  // 楽観的UI更新用のローカル状態
  bool? _isLikedOptimistic;
  int? _likeCountOptimistic;

  @override
  void initState() {
    super.initState();
    _flipController = AnimationController(
      duration: const Duration(milliseconds: 600),
      vsync: this,
    );
    _flipAnimation = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _flipController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _flipController.dispose();
    super.dispose();
  }

  /// カードをタップして裏返す
  void _flipCard() {
    if (_showFront) {
      _flipController.forward();
    } else {
      _flipController.reverse();
    }
    setState(() {
      _showFront = !_showFront;
    });
  }

  /// いいねボタンが押された時の処理（楽観的UI更新）
  void _handleLikeTap() {
    if (widget.onLike != null) {
      setState(() {
        final currentIsLiked = _isLikedOptimistic ??
            (widget.currentUserId != null && widget.post.isLikedBy(widget.currentUserId!));
        final currentLikeCount = _likeCountOptimistic ?? widget.post.likeCount;

        _isLikedOptimistic = !currentIsLiked;
        _likeCountOptimistic = currentIsLiked ? currentLikeCount - 1 : currentLikeCount + 1;
      });

      widget.onLike!();
    }
  }

  @override
  void didUpdateWidget(PostCard oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.post.postId != widget.post.postId) {
      _isLikedOptimistic = null;
      _likeCountOptimistic = null;
    } else if (_isLikedOptimistic != null || _likeCountOptimistic != null) {
      final actualIsLiked = widget.currentUserId != null &&
          widget.post.isLikedBy(widget.currentUserId!);
      final actualLikeCount = widget.post.likeCount;

      if (_isLikedOptimistic == actualIsLiked &&
          _likeCountOptimistic == actualLikeCount) {
        _isLikedOptimistic = null;
        _likeCountOptimistic = null;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _flipAnimation,
      builder: (context, child) {
        final angle = _flipAnimation.value * pi;
        final isFront = angle < pi / 2;

        return Transform(
          alignment: Alignment.center,
          transform: Matrix4.identity()
            ..setEntry(3, 2, 0.001)
            ..rotateY(angle),
          child: isFront ? _buildFront() : _buildBack(),
        );
      },
    );
  }

  /// カード表面（アルバムカバー全表示）
  Widget _buildFront() {
    final theme = widget.post.theme;
    final screenWidth = MediaQuery.of(context).size.width;
    final cardWidth = screenWidth - 30; // 左右15pxずつの余白を引く
    final albumSize = cardWidth; // アルバムカバーは正方形（4部分）
    final contentHeight = cardWidth * (3 / 4); // コンテンツエリア（3部分）
    final cardHeight = albumSize + contentHeight; // 4:3の比率

    return GestureDetector(
      onTap: _flipCard,
      child: Container(
        width: cardWidth,
        height: cardHeight,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          color: theme.gradientEnd,
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(18),
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
                  child: widget.post.track.albumImageUrl.isNotEmpty
                      ? Image.network(
                          widget.post.track.albumImageUrl,
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) {
                            return _buildAlbumPlaceholder();
                          },
                        )
                      : _buildAlbumPlaceholder(),
                ),
              ),

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
                      theme.gradientStart,
                      theme.gradientEnd,
                    ],
                    stops: const [0.0377, 1.0],
                  ),
                ),
              ),
            ),

            // コンテンツ（下部）
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              height: contentHeight,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const SizedBox(height: 1),
                    // ユーザー情報（一番上）
                    _buildUserInfo(theme),
                    const SizedBox(height: 3),

                    // 曲名とアーティスト名
                    _buildTrackInfo(theme),
                    const SizedBox(height: 4),

                    // リアクション（いいね、コメント、追加）といいねした人のアイコン
                    _buildReactions(theme),
                    const SizedBox(height: 4),

                    // 音楽波形
                    _buildWaveform(theme),
                    const SizedBox(height: 4),

                    // コメント入力欄
                    _buildCommentButton(theme),
                    const Spacer(),

                    // "Provided courtesy of Apple Music"（一番下）
                    Padding(
                      padding: const EdgeInsets.only(left: 5, bottom: 2),
                      child: Text(
                        'Provided courtesy of Apple Music',
                        style: TextStyle(
                          fontSize: 10,
                          color: theme.secondaryTextColor,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    ),
    );
  }

  /// カード裏面（写真+アルバムカード+下部セクション）
  Widget _buildBack() {
    final theme = widget.post.theme;
    final screenWidth = MediaQuery.of(context).size.width;
    final cardWidth = screenWidth - 30; // 左右15pxずつの余白を引く
    final photoHeight = cardWidth * (4 / 3); // 写真エリア（大きめ）
    final contentHeight = cardWidth * (7 / 12); // コンテンツエリア
    final cardHeight = cardWidth * (7 / 4); // 表面と同じ長方形（7:4の比率）

    return Transform(
      alignment: Alignment.center,
      transform: Matrix4.identity()..rotateY(pi),
      child: GestureDetector(
        onTap: _flipCard,
        child: Container(
        width: cardWidth,
        height: cardHeight,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          color: theme.gradientEnd,
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(18),
          child: Stack(
            children: [
              // 写真エリア（上部）
              Positioned(
                left: 0,
                top: 0,
                child: Container(
                  width: cardWidth,
                  height: photoHeight,
                  child: widget.post.track.albumImageUrl.isNotEmpty
                      ? Image.network(
                          widget.post.track.albumImageUrl,
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) {
                            return _buildPhotoPlaceholder();
                          },
                        )
                      : _buildPhotoPlaceholder(),
                ),
              ),

              // ユーザー情報（左上）
              Positioned(
                left: 15,
                top: 15,
                child: _buildUserInfoTopLeft(theme),
              ),

              // 小さなアルバムカード（写真の上部中央）
              Positioned(
                left: cardWidth * 0.25,
                top: 20,
                child: _buildMiniAlbumCard(),
              ),

              // 下部コンテンツセクション
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
                        theme.gradientStart,
                        theme.gradientEnd,
                      ],
                      stops: const [0.0, 1.0],
                    ),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // 曲名（大きく）
                        Text(
                          widget.post.track.trackName,
                          style: const TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),

                        // アーティスト名
                        Text(
                          widget.post.track.artistName,
                          style: TextStyle(
                            fontSize: 16,
                            color: theme.secondaryTextColor,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 12),

                        // リアクションとユーザーアバター
                        Row(
                          children: [
                            // いいね
                            _buildReactionButton(
                              icon: _isLikedOptimistic ??
                                (widget.currentUserId != null && widget.post.isLikedBy(widget.currentUserId!))
                                ? Icons.favorite
                                : Icons.favorite_border,
                              color: _isLikedOptimistic ??
                                (widget.currentUserId != null && widget.post.isLikedBy(widget.currentUserId!))
                                ? Colors.red
                                : Colors.white,
                              count: _likeCountOptimistic ?? widget.post.likeCount,
                              onTap: _handleLikeTap,
                            ),
                            const SizedBox(width: 16),

                            // コメント
                            _buildCommentReactionBack(
                              count: widget.post.commentCount,
                              onTap: widget.onComment,
                            ),
                            const SizedBox(width: 16),

                            // 追加
                            _buildReactionButton(
                              icon: Icons.add_circle_outline,
                              color: Colors.white,
                              count: null,
                              onTap: widget.onAdd,
                            ),

                            const Spacer(),

                            // ユーザーアバター
                            Container(
                              width: 40,
                              height: 40,
                              decoration: const BoxDecoration(
                                shape: BoxShape.circle,
                                color: Colors.grey,
                              ),
                              child: widget.post.userIconUrl != null && widget.post.userIconUrl!.isNotEmpty
                                  ? ClipOval(
                                      child: Image.network(
                                        widget.post.userIconUrl!,
                                        fit: BoxFit.cover,
                                        errorBuilder: (context, error, stackTrace) {
                                          return const Icon(Icons.person, size: 24, color: Colors.white);
                                        },
                                      ),
                                    )
                                  : const Icon(Icons.person, size: 24, color: Colors.white),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),

                        // コメントボタン
                        _buildCommentButton(theme),
                        const Spacer(),

                        // "Provided courtesy of Apple Music"
                        Text(
                          'Provided courtesy of Apple Music',
                          style: TextStyle(
                            fontSize: 10,
                            color: theme.secondaryTextColor,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
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

  /// 写真プレースホルダー
  Widget _buildPhotoPlaceholder() {
    return Container(
      color: Colors.grey[900],
      child: const Center(
        child: Icon(
          Icons.photo,
          size: 120,
          color: Colors.white54,
        ),
      ),
    );
  }

  /// 歌詞カード（裏面の中央オーバーレイ）
  Widget _buildLyricsCard() {
    return Column(
      children: [
        // 歌詞情報
        Container(
          width: 240.153,
          height: 73.893,
          decoration: BoxDecoration(
            color: const Color(0x4A000000), // rgba(0,0,0,0.29)
          ),
          child: const Padding(
            padding: EdgeInsets.symmetric(horizontal: 14, vertical: 18),
            child: Text(
              '笑ってもっとbaby\nむじゃきにon my mind',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.white,
                height: 1.39,
              ),
            ),
          ),
        ),
        // トラック情報
        Container(
          width: 240.153,
          height: 64.656,
          decoration: BoxDecoration(
            color: const Color(0x85000000), // rgba(0,0,0,0.52) opacity:80
          ),
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Row(
              children: [
                // ミニアルバムカバー
                Container(
                  width: 50,
                  height: 50,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(3),
                    color: Colors.grey[800],
                  ),
                  child: widget.post.track.albumImageUrl.isNotEmpty
                      ? ClipRRect(
                          borderRadius: BorderRadius.circular(3),
                          child: Image.network(
                            widget.post.track.albumImageUrl,
                            fit: BoxFit.cover,
                            errorBuilder: (context, error, stackTrace) {
                              return const Icon(Icons.album, color: Colors.white54, size: 30);
                            },
                          ),
                        )
                      : const Icon(Icons.album, color: Colors.white54, size: 30),
                ),
                const SizedBox(width: 7),
                // トラック名とアーティスト名
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        widget.post.track.trackName,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        widget.post.track.artistName,
                        style: const TextStyle(
                          fontSize: 9,
                          color: Colors.white,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  /// ユーザー情報（裏面の左上）
  Widget _buildUserInfoTopLeft(PostTheme theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        // ユーザー名
        Text(
          widget.post.username,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: Colors.white,
            shadows: [
              Shadow(
                offset: Offset(0, 1),
                blurRadius: 3,
                color: Colors.black54,
              ),
            ],
          ),
        ),
        const SizedBox(height: 2),

        // ハッシュタグ/質問テキスト
        const Text(
          '#ドライブの時に聴きたい曲は？',
          style: TextStyle(
            fontSize: 12,
            color: Colors.white,
            shadows: [
              Shadow(
                offset: Offset(0, 1),
                blurRadius: 3,
                color: Colors.black54,
              ),
            ],
          ),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }

  /// 小さなアルバムカード（裏面の写真上部）
  Widget _buildMiniAlbumCard() {
    return Container(
      width: 200,
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: const Color(0xB3000000), // 半透明の黒背景
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          // アルバムカバー
          Container(
            width: 50,
            height: 50,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(6),
              color: Colors.grey[800],
            ),
            child: widget.post.track.albumImageUrl.isNotEmpty
                ? ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: Image.network(
                      widget.post.track.albumImageUrl,
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) {
                        return const Icon(Icons.album, color: Colors.white54, size: 30);
                      },
                    ),
                  )
                : const Icon(Icons.album, color: Colors.white54, size: 30),
          ),
          const SizedBox(width: 10),

          // トラック情報
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  widget.post.track.trackName,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  widget.post.track.artistName,
                  style: const TextStyle(
                    fontSize: 11,
                    color: Colors.white70,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// リアクションボタン（いいね、コメント、追加）
  Widget _buildReactionButton({
    required IconData icon,
    required Color color,
    required int? count,
    required VoidCallback? onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 24,
            color: color,
          ),
          if (count != null) ...[
            const SizedBox(width: 4),
            Text(
              count.toString(),
              style: const TextStyle(
                fontSize: 14,
                color: Colors.white,
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// コメントリアクションボタン（裏面用・SVGアイコン使用）
  Widget _buildCommentReactionBack({
    required int count,
    required VoidCallback? onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SvgPicture.asset(
            'assets/icons/message_circle.svg',
            width: 24,
            height: 24,
            colorFilter: const ColorFilter.mode(
              Colors.white,
              BlendMode.srcIn,
            ),
          ),
          const SizedBox(width: 4),
          Text(
            count.toString(),
            style: const TextStyle(
              fontSize: 14,
              color: Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  /// コメントボタン
  Widget _buildCommentButton(PostTheme theme) {
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
            Icon(
              Icons.send,
              size: 20,
              color: theme.textColor.withOpacity(0.7),
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
    // postIdをシードとしてランダムな変動を追加
    final seed = widget.post.postId.hashCode;
    final random = Random(seed);

    // カードの幅を取得
    final screenWidth = MediaQuery.of(context).size.width;
    final cardWidth = screenWidth - 30; // 左右15pxずつの余白を引く
    final availableWidth = cardWidth - 24; // カード内のpadding（左右12pxずつ）を引く

    // バーの幅とマージンから必要なバーの数を計算
    const barWidth = 2.5;
    const barMargin = 1.2 * 2; // 左右のマージン
    const totalBarWidth = barWidth + barMargin;
    final barCount = (availableWidth / totalBarWidth).floor();

    return Container(
      height: 50,
      child: Row(
        children: List.generate(barCount, (index) {
          // 大、小、大のパターン（-π/4〜5π/4の範囲）
          // 0〜(barCount-1)のインデックスを-π/4〜5π/4の範囲にマッピング
          final normalizedIndex = index / (barCount - 1).toDouble(); // 0〜1の範囲
          final angle = -pi / 4 + normalizedIndex * 1.5 * pi; // -π/4〜5π/4の範囲（1.5π）

          // sin(angle)で波形を作成（-1〜1の範囲）
          // 絶対値を取って、0〜1の範囲にする
          final waveValue = sin(angle).abs();

          // 0〜1の範囲を0.3〜1.0の範囲にマッピング
          final baseHeight = 0.3 + waveValue * 0.7;

          // 15〜48の範囲にスケーリング + ランダムな変動（±3px）
          final randomVariation = (random.nextDouble() - 0.5) * 6;
          final height = 15.0 + (baseHeight * 33.0) + randomVariation;

          return Container(
            width: barWidth,
            height: height.clamp(10.0, 48.0),
            margin: const EdgeInsets.symmetric(horizontal: 1.2),
            decoration: BoxDecoration(
              color: theme.iconColor,
              borderRadius: BorderRadius.circular(2),
            ),
          );
        }),
      ),
    );
  }

  /// 曲名とアーティスト名（表面）
  Widget _buildTrackInfo(PostTheme theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          widget.post.track.trackName,
          style: TextStyle(
            fontSize: 25,
            fontWeight: FontWeight.bold,
            color: theme.textColor,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: 4),
        Text(
          widget.post.track.artistName,
          style: TextStyle(
            fontSize: 13,
            color: theme.textColor,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }

  /// 曲名とアーティスト名（裏面・小さめ）
  Widget _buildTrackInfoBack(PostTheme theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          widget.post.track.trackName,
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.bold,
            color: theme.textColor,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: 2),
        Text(
          widget.post.track.artistName,
          style: TextStyle(
            fontSize: 13,
            color: theme.textColor,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }

  /// リアクション（いいね、コメント、追加）
  Widget _buildReactions(PostTheme theme) {
    final isLiked = _isLikedOptimistic ??
        (widget.currentUserId != null && widget.post.isLikedBy(widget.currentUserId!));
    final likeCount = _likeCountOptimistic ?? widget.post.likeCount;

    return Row(
      children: [
        // いいね
        _buildReactionItem(
          icon: isLiked ? Icons.favorite : Icons.favorite_border,
          count: likeCount,
          onTap: _handleLikeTap,
          isActive: isLiked,
          theme: theme,
        ),
        const SizedBox(width: 12),

        // コメント
        _buildCommentReaction(
          count: widget.post.commentCount,
          onTap: widget.onComment,
          theme: theme,
        ),
        const SizedBox(width: 12),

        // 追加
        GestureDetector(
          onTap: widget.onAdd,
          child: Container(
            width: 23,
            height: 23,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.add_circle_outline,
              size: 23,
              color: theme.iconColor,
            ),
          ),
        ),

        const Spacer(),

        // いいねした人のアイコン（最大3人）
        _buildLikedUsersIcons(),
      ],
    );
  }

  /// リアクションアイテム
  Widget _buildReactionItem({
    required IconData icon,
    required int count,
    VoidCallback? onTap,
    bool isActive = false,
    required PostTheme theme,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Row(
        children: [
          Icon(
            icon,
            size: 25,
            color: isActive ? Colors.red : theme.iconColor,
          ),
          const SizedBox(width: 6),
          Text(
            '$count',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: isActive ? Colors.red : theme.textColor,
            ),
          ),
        ],
      ),
    );
  }

  /// コメントリアクションアイテム（SVGアイコン使用）
  Widget _buildCommentReaction({
    required int count,
    VoidCallback? onTap,
    required PostTheme theme,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Row(
        children: [
          SvgPicture.asset(
            'assets/icons/message_circle.svg',
            width: 25,
            height: 25,
            colorFilter: ColorFilter.mode(
              theme.iconColor,
              BlendMode.srcIn,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            '$count',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: theme.textColor,
            ),
          ),
        ],
      ),
    );
  }

  /// いいねした人のアイコン（最大3人表示）
  Widget _buildLikedUsersIcons() {
    return Row(
      children: List.generate(
        3,
        (index) => Container(
          width: 25,
          height: 25,
          margin: EdgeInsets.only(left: index > 0 ? 4 : 0),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.grey[400],
          ),
          child: const Icon(
            Icons.person,
            size: 14,
            color: Colors.white,
          ),
        ),
      ),
    );
  }

  /// ユーザー情報（表面の下部）
  Widget _buildUserInfo(PostTheme theme) {
    return Row(
      children: [
        // ユーザーアイコン
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.grey[400],
          ),
          child: widget.post.userIconUrl != null && widget.post.userIconUrl!.isNotEmpty
              ? ClipOval(
                  child: Image.network(
                    widget.post.userIconUrl!,
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) {
                      return const Icon(Icons.person, size: 20, color: Colors.white);
                    },
                  ),
                )
              : const Icon(Icons.person, size: 20, color: Colors.white),
        ),
        const SizedBox(width: 8),

        // ユーザー名
        Text(
          widget.post.username,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: theme.textColor,
          ),
        ),
      ],
    );
  }
}

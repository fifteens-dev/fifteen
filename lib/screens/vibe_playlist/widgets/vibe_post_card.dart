import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../../../models/post_model.dart';
import '../../../models/vibe_ranking_item.dart';
import '../../../models/track_model.dart';
import '../../../services/artist_service.dart';
import '../../../services/spotify_service.dart';
import '../../../widgets/profile_widgets.dart';
import '../../artist_profile_screen.dart';
import '../../other_user_profile_screen.dart';

/// Vibeプレイリスト投稿タブの全画面PageView用カード。
///
/// Figmaの各ページは 822px (card 814 + gap 8) で、上 547px が写真背景、下 275px が情報領域。
class VibePostCard extends StatelessWidget {
  final PostModel post;
  final VibeRankingItem? rankingItem;
  final bool isLiked;
  final int likeCount;
  final bool isSaved;
  final VoidCallback onLikeTap;
  final VoidCallback onCommentTap;
  final VoidCallback onSaveTap;
  final VoidCallback onCuratorBarTap;
  final VoidCallback onPostNoteTap;

  const VibePostCard({
    super.key,
    required this.post,
    required this.rankingItem,
    required this.isLiked,
    required this.likeCount,
    required this.isSaved,
    required this.onLikeTap,
    required this.onCommentTap,
    required this.onSaveTap,
    required this.onCuratorBarTap,
    required this.onPostNoteTap,
  });

  String _fmt(int n) {
    if (n >= 10000) {
      return '${(n / 10000).toStringAsFixed(n % 10000 != 0 ? 1 : 0)}万';
    }
    if (n >= 1000) {
      return '${(n / 1000).toStringAsFixed(n % 1000 != 0 ? 1 : 0)}K';
    }
    return n.toString();
  }

  /// 投稿者のプロフィール画面へ遷移
  void _openUserProfile(BuildContext context, String userId) {
    if (userId.isEmpty) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => OtherUserProfileScreen(userId: userId),
      ),
    );
  }

  /// 公開範囲バッジ（アルバム/写真下部の円形アイコン）
  Widget _buildAudienceBadge(PostModel post) {
    final isFollowers = post.audience == PostAudience.followers;
    return Container(
      width: 30,
      height: 30,
      decoration: const BoxDecoration(
        color: Color(0xCC1F1F1F),
        shape: BoxShape.circle,
      ),
      child: Center(
        child: Image.asset(
          isFollowers
              ? 'assets/icons/audience_badge_lock.png'
              : 'assets/icons/audience_badge_globe.png',
          width: 16,
          height: 16,
        ),
      ),
    );
  }

  /// 投稿時刻からの経過時間を「6時間前」形式で返す。
  /// 6時間36分前 → 「6時間前」（分は切り捨て）。
  String _formatTimeAgo(DateTime createdAt) {
    final diff = DateTime.now().difference(createdAt);
    if (diff.inMinutes < 1) return 'たった今';
    if (diff.inHours < 1) return '${diff.inMinutes}分前';
    if (diff.inDays < 1) return '${diff.inHours}時間前';
    return '${diff.inDays}日前';
  }

  /// アーティスト画像URLを取得する。spotifyArtistId があれば by-ID（正確）で、
  /// なければ名前ベースのSpotify検索にフォールバック。
  Future<String?> _fetchArtistImageUrl(TrackModel track) async {
    final id = track.spotifyArtistId;
    if (id != null && id.isNotEmpty) {
      return SpotifyService().getArtistImageUrlById(id);
    }
    return SpotifyService().getArtistImageUrl(track.artistName);
  }

  /// アーティストのフォロワー数を取得する。
  /// このアプリ内（Firestore artists.followerIds）の値を返す
  /// — ArtistProfileScreen に表示される数と一致させる。
  Future<int> _fetchFollowerCount(TrackModel track) async {
    return ArtistService().getFollowerCountByName(track.artistName);
  }

  @override
  Widget build(BuildContext context) {
    // Figma の各「ページ」は 822px (card 814 + gap 8)。下部 8px は次カードへの余白。
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(23),
        child: Stack(
          children: [
            Positioned.fill(child: _buildPhotoBackground(post)),
            // 公開範囲バッジ（カード下部情報領域のすぐ上、右側）
            Positioned(
              bottom: 275 + 12,
              right: 14,
              child: _buildAudienceBadge(post),
            ),
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              height: 275,
              child: _buildCardBottom(context, post),
            ),
          ],
        ),
      ),
    );
  }

  /// 投稿写真／アルバムアートを背景表示
  static Widget _buildPhotoBackground(PostModel post) {
    final hasPhoto = post.photoUrl != null &&
        post.photoUrl!.isNotEmpty &&
        post.photoUrl!.startsWith('http');
    final url = hasPhoto ? post.photoUrl! : post.track.albumImageUrl;

    if (url.isEmpty) return Container(color: Colors.grey[900]);

    // アルバムアートはレイアウト情報なし → BoxFit.cover のみ
    if (!hasPhoto) {
      return CachedNetworkImage(
        imageUrl: url,
        fit: BoxFit.cover,
        errorWidget: (_, __, ___) => Container(color: Colors.grey[900]),
      );
    }

    // 投稿写真: 投稿カード裏面と同じレイアウトを再現
    return LayoutBuilder(
      builder: (context, constraints) {
        final cardW = constraints.maxWidth;
        final cardH = constraints.maxHeight;
        final imgScale = post.imageScale != 0 ? post.imageScale : 1.0;
        final natW = post.imageNaturalWidth;
        final natH = post.imageNaturalHeight;

        final image = CachedNetworkImage(
          imageUrl: url,
          fit: BoxFit.fill,
          errorWidget: (_, __, ___) => Container(color: Colors.grey[900]),
        );

        if (natW > 0 && natH > 0) {
          // 新方式: 投稿カード裏面と同じ計算（363基準スケール）
          final scaleFactor = cardW / 363.0;
          final baseScale = cardH / natH;
          final displayW = natW * baseScale;
          final displayH = natH * baseScale;

          return Stack(
            clipBehavior: Clip.hardEdge,
            children: [
              Positioned(
                left: post.imageOffsetX * scaleFactor,
                top: post.imageOffsetY * scaleFactor,
                child: Transform.scale(
                  scale: imgScale,
                  alignment: Alignment.topLeft,
                  child: SizedBox(
                    width: displayW,
                    height: displayH,
                    child: image,
                  ),
                ),
              ),
            ],
          );
        } else {
          // 旧方式: BoxFit.cover + オフセット + スケール
          return ClipRect(
            child: Transform.translate(
              offset: Offset(post.imageOffsetX, post.imageOffsetY),
              child: Transform.scale(
                scale: imgScale,
                child: CachedNetworkImage(
                  imageUrl: url,
                  fit: BoxFit.cover,
                  width: cardW,
                  height: cardH,
                  errorWidget: (_, __, ___) => Container(color: Colors.grey[900]),
                ),
              ),
            ),
          );
        }
      },
    );
  }

  /// 公開: タブ「投稿」へのジャンプボタン等から再利用するため static で expose
  static Widget photoBackgroundOf(PostModel post) => _buildPhotoBackground(post);

  /// ── カード下部（275px Stack, Figma: top=539 height=275, w=402） ──
  Widget _buildCardBottom(BuildContext context, PostModel post) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        // ユーザー情報（icon left=18 top=46 size=32, name left=59 top=52）
        // タップで投稿者のプロフィールへ遷移
        Positioned(
          left: 18,
          top: 46,
          width: 32,
          height: 32,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => _openUserProfile(context, post.userId),
            child: ClipOval(
              child: ProfileImage(imageUrl: post.userIconUrl, size: 32),
            ),
          ),
        ),
        Positioned(
          left: 59,
          top: 46,
          right: 60,
          height: 32,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => _openUserProfile(context, post.userId),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Flexible(
                    child: Text(
                      post.username,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                        letterSpacing: -0.12,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    _formatTimeAgo(post.createdAt),
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFFA8A8A8),
                      letterSpacing: -0.12,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        // 楽曲タイトル（left=18, top=90, fontSize=24 bold）
        Positioned(
          left: 18,
          top: 90,
          right: 60,
          child: Text(
            post.track.trackName,
            style: const TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: Colors.white,
              height: 1.0,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        // アーティスト名（left=18, top=119）
        Positioned(
          left: 18,
          top: 119,
          right: 60,
          child: GestureDetector(
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) =>
                    ArtistProfileScreen(
                      artistName: post.track.artistName,
                      spotifyArtistId: post.track.spotifyArtistId,
                    ),
              ),
            ),
            child: Text(
              post.track.artistName,
              style: const TextStyle(
                fontSize: 12,
                color: Color(0xFFA7ACB1),
                letterSpacing: 0.36,
                height: 1.0,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
        // アーティスト行（left=0, top=147, w=402, h=32）
        Positioned(
          left: 0,
          right: 0,
          top: 147,
          height: 32,
          child: _buildArtistRow(context, post),
        ),
        // 曲リストバー（left=14, top=191, w=374, h=72）
        Positioned(
          left: 14,
          right: 14,
          top: 191,
          height: 72,
          child: _buildCuratorBar(post),
        ),
        // 右サイドバー（Figma: left=347 top=5 w=30 h=165, → right=25）
        Positioned(
          right: 25,
          top: 5,
          width: 30,
          height: 165,
          child: _buildRightSidebar(post),
        ),
      ],
    );
  }

  /// アーティスト行 (Figma: container left=0 top=147 w=402 h=32)
  Widget _buildArtistRow(BuildContext context, PostModel post) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        // アーティストアイコン（白背景円, 32x32）
        Positioned(
          left: 16,
          top: 0,
          width: 32,
          height: 32,
          child: GestureDetector(
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) =>
                    ArtistProfileScreen(
                      artistName: post.track.artistName,
                      spotifyArtistId: post.track.spotifyArtistId,
                    ),
              ),
            ),
            child: Container(
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white,
              ),
              child: ClipOval(
                child: FutureBuilder<String?>(
                  future: _fetchArtistImageUrl(post.track),
                  builder: (context, snapshot) {
                    final url = snapshot.data?.isNotEmpty == true
                        ? snapshot.data!
                        : post.track.albumImageUrl;
                    return CachedNetworkImage(
                      imageUrl: url,
                      width: 32,
                      height: 32,
                      fit: BoxFit.cover,
                      errorWidget: (_, __, ___) => const Icon(
                          Icons.music_note,
                          color: Colors.grey,
                          size: 18),
                    );
                  },
                ),
              ),
            ),
          ),
        ),
        // アーティスト名
        Positioned(
          left: 56,
          top: 1,
          right: 252,
          child: GestureDetector(
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) =>
                    ArtistProfileScreen(
                      artistName: post.track.artistName,
                      spotifyArtistId: post.track.spotifyArtistId,
                    ),
              ),
            ),
            child: Text(
              post.track.artistName,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: Colors.white,
                letterSpacing: -0.78,
                height: 1.0,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
        // フォロワー数（アーティストの実フォロワー）
        Positioned(
          left: 56,
          top: 17,
          right: 252,
          child: FutureBuilder<int>(
            future: _fetchFollowerCount(post.track),
            builder: (context, snapshot) {
              final count = snapshot.data ?? 0;
              return Text(
                '${_fmt(count)}人のフォロワー',
                style: const TextStyle(
                  fontSize: 10,
                  color: Colors.white,
                  height: 1.0,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              );
            },
          ),
        ),
        // フォローするボタン
        Positioned(
          left: 158,
          top: 7,
          width: 83,
          height: 19,
          child: GestureDetector(
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) =>
                    ArtistProfileScreen(
                      artistName: post.track.artistName,
                      spotifyArtistId: post.track.spotifyArtistId,
                    ),
              ),
            ),
            child: Container(
              decoration: BoxDecoration(
                border: Border.all(color: Colors.white, width: 1),
                borderRadius: BorderRadius.circular(25),
              ),
              alignment: Alignment.center,
              child: const Text(
                'フォローする',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                  height: 1.0,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// キュレーターバー (left=14 top=191 w=374 h=72 rounded=16)
  Widget _buildCuratorBar(PostModel post) {
    final postCount = rankingItem?.postCount ?? 0;
    return GestureDetector(
      onTap: onCuratorBarTap,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Stack(
          clipBehavior: Clip.hardEdge,
          children: [
            // アルバムアート
            Positioned(
              left: 8,
              top: 8,
              width: 56,
              height: 56,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(7),
                child: CachedNetworkImage(
                  imageUrl: post.track.albumImageUrl,
                  width: 56,
                  height: 56,
                  fit: BoxFit.cover,
                  errorWidget: (_, __, ___) => Container(
                    color: Colors.grey[800],
                    child: const Icon(Icons.album, color: Colors.white54),
                  ),
                ),
              ),
            ),
            // 楽曲タイトル
            Positioned(
              left: 72,
              top: 13,
              right: 60,
              child: Text(
                post.track.trackName,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                  height: 1.0,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            // アーティスト名
            Positioned(
              left: 72,
              top: 29,
              right: 60,
              child: Text(
                post.track.artistName,
                style: const TextStyle(
                  fontSize: 11,
                  color: Colors.white,
                  height: 1.0,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            // Vibe追加カウント
            Positioned(
              left: 72,
              top: 46,
              right: 60,
              child: Text(
                '🔥$postCount人がVibeにこの曲を追加',
                style: const TextStyle(
                  fontSize: 11,
                  color: Color(0xFF858585),
                  letterSpacing: -0.22,
                  height: 1.0,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            // 投稿ボタン
            Positioned(
              left: 328,
              top: 16,
              width: 40,
              height: 40,
              child: GestureDetector(
                onTap: onPostNoteTap,
                behavior: HitTestBehavior.opaque,
                child: Center(
                  child: SvgPicture.asset(
                    'assets/icons/post_icon.svg',
                    width: 28,
                    height: 28,
                    colorFilter: const ColorFilter.mode(
                      Colors.white,
                      BlendMode.srcIn,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 右サイドバー（heart / count / message / save）
  Widget _buildRightSidebar(PostModel post) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        // ♡ いいねアイコン
        Positioned(
          left: 2,
          top: 0,
          width: 27,
          height: 27,
          child: GestureDetector(
            onTap: onLikeTap,
            behavior: HitTestBehavior.opaque,
            child: Transform.scale(
              scale: 1.2,
              child: Icon(
                isLiked ? Icons.favorite : Icons.favorite_border,
                color: isLiked ? Colors.red : Colors.white,
                size: 27,
              ),
            ),
          ),
        ),
        // いいね数
        Positioned(
          left: 0,
          right: 0,
          top: 35,
          child: Text(
            _fmt(likeCount),
            style: const TextStyle(
              fontSize: 10,
              color: Colors.white,
              height: 1.0,
            ),
            textAlign: TextAlign.center,
          ),
        ),
        // 💬 コメントボタン
        Positioned(
          left: 0,
          top: 66,
          width: 30,
          height: 30,
          child: GestureDetector(
            onTap: onCommentTap,
            behavior: HitTestBehavior.opaque,
            child: SvgPicture.asset(
              'assets/icons/message_circle.svg',
              width: 30,
              height: 30,
              colorFilter: const ColorFilter.mode(
                Colors.white,
                BlendMode.srcIn,
              ),
            ),
          ),
        ),
        // 保存ボタン
        Positioned(
          left: 0,
          top: 135,
          width: 30,
          height: 30,
          child: GestureDetector(
            onTap: onSaveTap,
            behavior: HitTestBehavior.opaque,
            child: Center(
              child: _buildSaveIcon(),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSaveIcon() {
    if (isSaved) {
      return Stack(
        alignment: Alignment.center,
        children: [
          Container(
            width: 30,
            height: 30,
            decoration: const BoxDecoration(
              color: Colors.lightGreen,
              shape: BoxShape.circle,
            ),
          ),
          Icon(Icons.check, size: 18, color: Colors.grey[700]),
        ],
      );
    }
    return const Icon(Icons.add_circle_outline, size: 32, color: Colors.white);
  }
}

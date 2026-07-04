import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import '../../constants/app_colors.dart';
import '../../models/post_model.dart';
import '../../models/vibe_topic_model.dart';

/// 1人分の Vibe ストーリーアイテム
class VibeStoryItem {
  final String userId;
  final String? username;
  final String? iconUrl;

  /// このユーザーの Vibe ストーリーを当アカウントが未閲覧か。
  /// 未閲覧 = グラデ枠（アクティブ）、閲覧済 = グレー枠（ノンアクティブ）
  final bool unread;

  /// このユーザーの直近 24h の投稿（新しい順、可視性フィルタ済み）
  final List<PostModel> posts;

  const VibeStoryItem({
    required this.userId,
    this.username,
    this.iconUrl,
    this.unread = true,
    this.posts = const [],
  });
}

/// 新 Vibe ストーリーバー（インスタストーリー風、ユーザー単位）。
///
/// 旧 [VibeBarSection] は曲ベースのランキングだったが、本バーはユーザーベース。
/// フォロワー限定で投稿された Vibe（鍵投稿）が、フォロー中ユーザーのストーリー
/// として並ぶ想定。第一段階として UI のみ構築（データ配線は別タスク）。
///
/// レイアウト基準は Figma 402×158（node 4530:9650）:
///   - ヘッダー: 50px
///   - ストーリー行: 各円 93×93、横スクロール
///     - 1番目「Vibe」: 「Vibe 追加ロゴ」（ダーク背景+白+）= 投稿フロー入口
///     - 2番目「プレイリスト」: アクティブ枠 + Vibe ロゴ = 既存 Vibe プレイリスト
///     - 3番目以降: フォロー中ユーザーの Vibe ストーリー（アクティブ/ノンアクティブ枠）
class VibeStoryBarSection extends StatelessWidget {
  final VibeTopicModel? topic;

  /// 1番目「Vibe」円に出す自分のアイコン URL
  final String? myIconUrl;

  /// フォロー中ユーザーの Vibe ストーリー（並び替え済み想定）
  final List<VibeStoryItem> stories;

  /// 「Vibe」円タップ — ストーリー投稿フローへ
  final VoidCallback? onAddVibeTap;

  /// 「プレイリスト」円タップ — 今日の Vibe プレイリストへ
  final VoidCallback? onPlaylistTap;

  /// 個別ストーリータップ — そのユーザーのストーリー閲覧画面へ
  final ValueChanged<VibeStoryItem>? onStoryTap;

  const VibeStoryBarSection({
    super.key,
    required this.topic,
    this.myIconUrl,
    this.stories = const [],
    this.onAddVibeTap,
    this.onPlaylistTap,
    this.onStoryTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.background,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildHeader(),
          SizedBox(height: 120, child: _buildStoryRow()),
        ],
      ),
    );
  }

  // ──────────────────────────────────────────────
  // ヘッダー
  // ──────────────────────────────────────────────

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(13, 5, 13, 5),
      child: SizedBox(
        height: 40,
        child: Row(
          children: [
            Image.asset(
              'assets/icons/Vibe.png',
              width: 40,
              height: 40,
              fit: BoxFit.contain,
              errorBuilder: (_, __, ___) => const Icon(
                Icons.music_note,
                color: Colors.white,
                size: 28,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: RichText(
                overflow: TextOverflow.ellipsis,
                text: TextSpan(
                  children: [
                    const TextSpan(
                      text: 'Vibe',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                    if (topic != null)
                      TextSpan(
                        text: '【#${topic!.title}】',
                        style: const TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w500,
                          color: Colors.white,
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ──────────────────────────────────────────────
  // ストーリー行
  // ──────────────────────────────────────────────

  Widget _buildStoryRow() {
    return ListView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 13),
      children: [
        _buildAddVibeCircle(),
        const SizedBox(width: 12),
        _buildPlaylistCircle(),
        for (final story in stories) ...[
          const SizedBox(width: 12),
          _buildUserStoryCircle(story),
        ],
        const SizedBox(width: 13),
      ],
    );
  }

  /// 1番目「Vibe」: アクティブ枠 + 自分のアバター + 右下に「+」バッジ。
  Widget _buildAddVibeCircle() {
    return _StoryCircle(
      label: 'Vibe',
      onTap: onAddVibeTap,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.center,
        children: [
          _RingedAvatar(
            ringAsset: 'assets/icons/vibe_story_ring_active.png',
            inner: ClipOval(
              child: SizedBox(
                width: 79,
                height: 79,
                child: (myIconUrl != null && myIconUrl!.isNotEmpty)
                    ? CachedNetworkImage(
                        imageUrl: myIconUrl!,
                        fit: BoxFit.cover,
                        errorWidget: (_, __, ___) => _placeholderAvatar(),
                      )
                    : _placeholderAvatar(),
              ),
            ),
          ),
          // 右下の「+」バッジ
          Positioned(
            right: 4,
            bottom: 4,
            child: Image.asset(
              'assets/icons/vibe_story_add_badge.png',
              width: 26,
              height: 26,
              fit: BoxFit.contain,
              errorBuilder: (_, __, ___) => Container(
                width: 26,
                height: 26,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(0xFF1F1F1F),
                  border: Border.all(color: AppColors.background, width: 2),
                ),
                alignment: Alignment.center,
                child: const Icon(Icons.add, color: Colors.white, size: 14),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 2番目「プレイリスト」: アクティブ枠 + 中央に Vibe ロゴ
  Widget _buildPlaylistCircle() {
    return _StoryCircle(
      label: 'プレイリスト',
      onTap: onPlaylistTap,
      child: _RingedAvatar(
        ringAsset: 'assets/icons/vibe_story_ring_active.png',
        inner: Container(
          width: 79,
          height: 79,
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            color: Color(0xFF000000),
          ),
          alignment: Alignment.center,
          child: Image.asset(
            'assets/icons/Vibe.png',
            width: 67,
            height: 67,
            fit: BoxFit.contain,
            errorBuilder: (_, __, ___) => const Icon(
              Icons.play_arrow,
              color: Colors.white,
              size: 32,
            ),
          ),
        ),
      ),
    );
  }

  /// 3番目以降: 個別ユーザーの Vibe ストーリー
  Widget _buildUserStoryCircle(VibeStoryItem story) {
    return _StoryCircle(
      label: story.username ?? '',
      onTap: onStoryTap == null ? null : () => onStoryTap!(story),
      child: _RingedAvatar(
        ringAsset: story.unread
            ? 'assets/icons/vibe_story_ring_active.png'
            : 'assets/icons/vibe_story_ring_inactive.png',
        inner: ClipOval(
          child: SizedBox(
            width: 79,
            height: 79,
            child: (story.iconUrl != null && story.iconUrl!.isNotEmpty)
                ? CachedNetworkImage(
                    imageUrl: story.iconUrl!,
                    fit: BoxFit.cover,
                    errorWidget: (_, __, ___) => _placeholderAvatar(),
                  )
                : _placeholderAvatar(),
          ),
        ),
      ),
    );
  }

  Widget _placeholderAvatar() {
    return Container(
      width: 79,
      height: 79,
      color: const Color(0xFF2A2A2A),
      alignment: Alignment.center,
      child: const Icon(Icons.person, color: Colors.white54, size: 32),
    );
  }
}

/// 個別ストーリー円の共通レイアウト（93×93 の枠 + 下にラベル）
class _StoryCircle extends StatelessWidget {
  final String label;
  final VoidCallback? onTap;
  final Widget child;

  const _StoryCircle({
    required this.label,
    required this.onTap,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        width: 93,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(width: 93, height: 93, child: child),
            const SizedBox(height: 6),
            SizedBox(
              width: 93,
              child: Text(
                label,
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                  color: Colors.white,
                  height: 1.1,
                ),
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 枠アセット（93×93）の上に中央寄せで小さい inner widget を重ねるレイアウト。
/// 枠と inner（79×79）の間に 7px の隙間が出るが、その隙間を #121212 で塗る。
class _RingedAvatar extends StatelessWidget {
  final String ringAsset;
  final Widget inner;

  const _RingedAvatar({required this.ringAsset, required this.inner});

  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: Alignment.center,
      children: [
        // ring 内側の下地。inner が透過でもリング内に地色が抜けないよう
        // 79×79 の #121212 円を先に置く（Figma: リング 93×93 + 中身 79×79@7,7）。
        Container(
          width: 79,
          height: 79,
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            color: Color(0xFF121212),
          ),
        ),
        Image.asset(
          ringAsset,
          width: 93,
          height: 93,
          fit: BoxFit.contain,
          errorBuilder: (_, __, ___) => Container(
            width: 93,
            height: 93,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              color: Color(0xFF3A3A3A),
            ),
          ),
        ),
        inner,
      ],
    );
  }
}

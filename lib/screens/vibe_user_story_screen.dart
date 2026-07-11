import 'dart:math' as math;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:provider/provider.dart';

import '../models/post_model.dart';
import '../providers/post_ui_state.dart';
import '../services/audio_player_service.dart';
import '../services/itunes_search_service.dart';
import '../services/post_service.dart';
import '../widgets/post_creation/lyrics_card_layouts.dart';
import 'comment_screen.dart';
import 'home/vibe_story_bar_section.dart';

/// Vibe ストーリーバーで 1 ユーザーをタップしたときに開くストーリー閲覧画面。
///
/// Figma 4587:7840 に忠実:
/// - フルブリード写真 (BoxFit.cover) の 402×715 rounded 8 の枠
/// - 上端: セグメント進行バー (top:10)
/// - 上端 (top:17): アバター 32×32 + ユーザー名 12px SemiBold + "1時間" 12px Regular
///                + 2 行目に "【#topic】" 10px Regular
/// - 右上 (top:25): 閉じる X ボタン 18×18
/// - 下部 (top:777, h:97): メッセージ入力 (244×44 rounded 28 border #6D6F72)
///                        + ハート / メッセージ / 送信アイコン 48×48
///
/// 402 × 874 の Figma 座標をベースに [_kFigmaW], [_kFigmaH] でスケール。
class VibeUserStoryScreen extends StatefulWidget {
  /// 表示対象のユーザー全員のストーリー。左端が最初、右端が最後の並び順で
  /// この配列内の順序どおりに横スクロールで飛び越えられる。
  final List<VibeStoryItem> stories;
  final String currentUserId;
  /// 起動時にフォーカスするユーザーの index (stories 内)。
  final int initialUserIndex;
  /// 起動時にフォーカスするそのユーザー内の投稿 index。
  final int initialPostIndex;
  final bool hasPostedToday;

  /// ユーザーが 1 人のストーリーだけを開く場合のショートカット。
  /// 既存の呼び出し側の互換性のため posts / displayUsername から VibeStoryItem を
  /// 合成する形にできる (現状は home_screen から `stories:` で直接渡す)。
  const VibeUserStoryScreen({
    super.key,
    required this.stories,
    required this.currentUserId,
    this.initialUserIndex = 0,
    this.initialPostIndex = 0,
    this.hasPostedToday = false,
  });

  @override
  State<VibeUserStoryScreen> createState() => _VibeUserStoryScreenState();
}

class _VibeUserStoryScreenState extends State<VibeUserStoryScreen>
    with SingleTickerProviderStateMixin {
  static const double _kFigmaW = 402.0;
  static const double _kFigmaH = 874.0;

  late final PageController _pageController;
  final AudioPlayerService _audioService = AudioPlayerService();
  final PostService _postService = PostService();
  final ITunesSearchService _itunesService = ITunesSearchService();

  /// 全ユーザーの投稿を並び順で flatten したもの。PageView の 1 ページ = _allPosts[i]。
  late final List<PostModel> _allPosts;
  /// _allPosts[i] がどの stories の index に対応するかのマップ。
  late final List<int> _userIndexOfPost;
  /// stories[u] の最初の post が _allPosts のどこにあるか (進行バーの現在 index 計算に使う)。
  late final List<int> _firstPostAllIdxOfUser;
  /// 現在の PageView position (flat index) と、そこから導出される user index。
  int _currentAllIdx = 0;
  int _currentUserIdx = 0;

  /// track.trackId → プレビュー音源 URL のキャッシュ。
  /// 各投稿ごとに iTunes から取得する分の重複リクエストを避ける。
  final Map<String, String?> _previewUrlCache = {};

  /// 上部進行バーのアニメーション。
  /// 現在の投稿の `audioDurationSec` を duration にして 0→1 を線形に走らせる。
  /// 完了時に次の投稿へ自動遷移する (最後なら画面を閉じる)。
  late final AnimationController _progressCtrl;

  @override
  void initState() {
    super.initState();
    // 投稿を全ユーザーぶん flatten し、ユーザー境界を跨いで横スクロールで
    // 移動できるようにする。stories[u].posts が空のユーザーは飛ばす。
    _allPosts = <PostModel>[];
    _userIndexOfPost = <int>[];
    _firstPostAllIdxOfUser = List<int>.filled(widget.stories.length, -1);
    for (int u = 0; u < widget.stories.length; u++) {
      final posts = widget.stories[u].posts;
      if (posts.isEmpty) continue;
      _firstPostAllIdxOfUser[u] = _allPosts.length;
      for (final p in posts) {
        _allPosts.add(p);
        _userIndexOfPost.add(u);
      }
    }

    // 起動時の初期位置を flat index に変換
    final safeUserIdx =
        widget.initialUserIndex.clamp(0, widget.stories.length - 1);
    final userPosts = widget.stories[safeUserIdx].posts;
    final safePostIdx = userPosts.isEmpty
        ? 0
        : widget.initialPostIndex.clamp(0, userPosts.length - 1);
    _currentAllIdx = _firstPostAllIdxOfUser[safeUserIdx] < 0
        ? 0
        : _firstPostAllIdxOfUser[safeUserIdx] + safePostIdx;
    _currentUserIdx = safeUserIdx;
    _pageController = PageController(initialPage: _currentAllIdx);

    _progressCtrl = AnimationController(vsync: this)
      ..addStatusListener((status) {
        if (status == AnimationStatus.completed) {
          _advanceToNext();
        }
      });

    // 初期表示中の投稿の音源とアニメーションを起動。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _playCurrentPost();
        _restartProgress();
      }
    });
  }

  /// 現在ページ用にアニメーションをリセットし、`audioDurationSec` かけて 0→1 で走らせる。
  void _restartProgress() {
    if (_allPosts.isEmpty) return;
    final sec = _allPosts[_currentAllIdx].audioDurationSec;
    final safeSec = sec > 0 ? sec : 15;
    _progressCtrl.stop();
    _progressCtrl.duration = Duration(seconds: safeSec);
    _progressCtrl.forward(from: 0);
  }

  /// 同一ユーザー内は瞬時 jump、ユーザー間はキューブ回転付きの animate。
  /// [target] が範囲外 (前後がない) の場合は挙動なし。
  void _goToIndex(int target) {
    if (!mounted) return;
    if (target < 0 || target >= _allPosts.length) return;
    final crossUser =
        _userIndexOfPost[_currentAllIdx] != _userIndexOfPost[target];
    if (crossUser) {
      _pageController.animateToPage(
        target,
        duration: const Duration(milliseconds: 500),
        curve: Curves.easeInOut,
      );
    } else {
      _pageController.jumpToPage(target);
    }
  }

  /// アニメーション完了時: 次ページがあれば進む、なければ画面を閉じる。
  void _advanceToNext() {
    if (!mounted) return;
    if (_currentAllIdx + 1 < _allPosts.length) {
      _goToIndex(_currentAllIdx + 1);
    } else {
      Navigator.of(context).maybePop();
    }
  }

  /// ストーリー枠右側タップ: 次のストーリーへ進む (最後なら画面を閉じる)。
  void _tapNext() => _advanceToNext();

  /// ストーリー枠左側タップ: 前のストーリーへ戻る。先頭ならリスタート。
  void _tapPrevious() {
    if (!mounted) return;
    if (_currentAllIdx > 0) {
      _goToIndex(_currentAllIdx - 1);
    } else {
      // 先頭で戻ろうとしたときは、進行バーを最初からやり直し (Instagram 風)
      _restartProgress();
      _playCurrentPost();
    }
  }

  /// 現在ページの投稿の [audioStartMs] から [audioDurationSec] 秒だけ再生する。
  Future<void> _playCurrentPost() async {
    if (_allPosts.isEmpty) return;
    final post = _allPosts[_currentAllIdx];
    final id = post.track.trackId;
    String? url = _previewUrlCache[id];
    if (url == null) {
      url = post.track.previewUrl;
      if (url == null || url.isEmpty) {
        try {
          url = await _itunesService.getPreviewUrl(
            trackName: post.track.trackName,
            artistName: post.track.artistName,
          );
        } catch (_) {
          url = null;
        }
      }
      _previewUrlCache[id] = url;
    }
    if (!mounted || url == null || url.isEmpty) return;
    try {
      await _audioService.playPreview(
        url,
        startFrom: Duration(milliseconds: post.audioStartMs),
        durationSeconds: post.audioDurationSec,
        // owner: this にすることで他画面 dispose の stopIfOwner に巻き添えで止められない
        owner: this,
      );
    } catch (_) {}
  }

  @override
  void dispose() {
    _progressCtrl.dispose();
    _audioService.stopIfOwner(this);
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_allPosts.isEmpty) {
      return const Scaffold(
        backgroundColor: Color(0xFF121212),
        body: Center(
          child: Text(
            '表示できる投稿がありません',
            style: TextStyle(color: Colors.white70),
          ),
        ),
      );
    }

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: const Color(0xFF121212),
        body: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final w = constraints.maxWidth;
              final h = constraints.maxHeight;
              // Figma 402×874 に対する縮尺。両軸別々に見て、より小さい方を使う
              // → 縦横比が変わっても Figma と同じレイアウトを維持しつつ画面内に収める。
              final scale = _computeUniformScale(w, h);
              final storyTop = 62.0 * scale;
              final storyH = 715.0 * scale;
              final bottomTop = 777.0 * scale;
              final bottomH = 97.0 * scale;
              return Stack(
                children: [
                  // ストーリー枠 (フルブリード写真 + 上部情報 + 進行バー + X)
                  Positioned(
                    left: 0,
                    right: 0,
                    top: storyTop,
                    height: storyH,
                    child: PageView.builder(
                      // Instagram Story 風のキューブ回転で 2 つ目の投稿へ切り替わる
                      // ため、スクロールは水平方向。
                      // 遷移は左右タップまたは進行バー完了トリガーのみに絞り、
                      // 同一ユーザー内は jumpToPage で瞬時、ユーザー間だけ
                      // animateToPage でキューブ回転を実行する。
                      scrollDirection: Axis.horizontal,
                      physics: const NeverScrollableScrollPhysics(),
                      controller: _pageController,
                      onPageChanged: (i) {
                        setState(() {
                          _currentAllIdx = i;
                          _currentUserIdx = _userIndexOfPost[i];
                        });
                        // 新ページの投稿の再生位置に切り替え + 進行バーを再スタート
                        _playCurrentPost();
                        _restartProgress();
                      },
                      itemCount: _allPosts.length,
                      itemBuilder: (context, index) => _buildCubePage(
                        index: index,
                        child: _buildStoryFrame(_allPosts[index], scale, w),
                      ),
                    ),
                  ),
                  // 下枠 (メッセージ入力 + リアクション)
                  Positioned(
                    left: 0,
                    right: 0,
                    top: bottomTop,
                    height: bottomH,
                    child: _buildBottomBar(scale),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  /// Figma 402×874 → 実際の viewport (w×h) 用の縮尺を計算。
  /// 縦横で異なる場合は小さい方を採用 (デザイン内容が切れないようにする)。
  double _computeUniformScale(double w, double h) {
    final sx = w / _kFigmaW;
    final sy = h / _kFigmaH;
    return sx < sy ? sx : sy;
  }

  // ────────────────────────────────────────────────────────────
  // ストーリー枠
  // ────────────────────────────────────────────────────────────

  /// キューブ横回転で各ページを描画するラッパー。
  ///
  /// 「キューブを外から見た」視点になるように角度符号を反転している。
  /// 具体的には共有エッジ(隣接ページの境界)が視覚上「奥」に落ち込み、
  /// ページの外側エッジは手前に来るという 凸コーナー 描写。
  ///
  /// `_pageController.page` (0.0〜N.0 の連続値) を毎フレーム読み、
  /// 各ページの相対位置 `delta = index - page` を [-1, 1] の範囲で使う。
  ///
  /// - `delta = 0`: 正面 (回転なし)
  /// - `delta > 0` (右から入ってくるページ): 左端を軸に、外側エッジ (右端) が
  ///   手前に来るように回転
  /// - `delta < 0` (左へ抜けていくページ): 右端を軸に、外側エッジ (左端) が
  ///   手前に来るように回転
  ///
  /// `Matrix4.setEntry(3, 2, 0.001)` で控えめに遠近感を入れる。
  Widget _buildCubePage({required int index, required Widget child}) {
    return AnimatedBuilder(
      animation: _pageController,
      builder: (context, c) {
        double page = _currentAllIdx.toDouble();
        if (_pageController.hasClients &&
            _pageController.position.haveDimensions) {
          page = _pageController.page ?? _currentAllIdx.toDouble();
        }

        // 現在アクティブな遷移境界 = (leftIdx, leftIdx+1)。
        // その境界が「ユーザー間」の場合だけキューブ回転を適用する。
        // 同一ユーザー内は jumpToPage で瞬時遷移なので、そもそも中間 page 値が
        // 生じず、Transform も rotation 0 のままとなる。
        final leftIdx = page.floor();
        final rightIdx = leftIdx + 1;
        final isBoundaryPage = index == leftIdx || index == rightIdx;
        bool isUserBoundary = false;
        if (leftIdx >= 0 && rightIdx < _allPosts.length) {
          isUserBoundary =
              _userIndexOfPost[leftIdx] != _userIndexOfPost[rightIdx];
        }
        if (!isBoundaryPage || !isUserBoundary) {
          return c ?? const SizedBox.shrink();
        }

        final delta = (index - page).clamp(-1.0, 1.0);
        // 「外からキューブを見る」ため、`delta * π/2` に対して符号反転。
        // 共有エッジ側 (delta≥0 なら左端、delta<0 なら右端) を軸にし、
        // 逆側エッジが手前 (+Z) へ迫り出す方向へ回す。
        final angle = -delta * (math.pi / 2);
        final alignment =
            delta >= 0 ? Alignment.centerLeft : Alignment.centerRight;
        return Transform(
          alignment: alignment,
          transform: Matrix4.identity()
            ..setEntry(3, 2, 0.001)
            ..rotateY(angle),
          child: c,
        );
      },
      child: child,
    );
  }

  Widget _buildStoryFrame(PostModel post, double scale, double screenW) {
    // 進行バーは「現在ユーザーの投稿数ぶんのセグメントを均等に切り分け、
    // 現在ページのぶんがアニメで塗られる」表示 (Instagram 準拠)。
    // ユーザー境界を跨いだら、新ユーザーの post count / index に切り替わる。
    final userPosts = widget.stories[_currentUserIdx].posts;
    final segments = userPosts.length;
    final userStart = _firstPostAllIdxOfUser[_currentUserIdx];
    final currentSegIdx =
        (_currentAllIdx - userStart).clamp(0, segments - 1);
    return Padding(
      // Figma のストーリー枠は viewport 幅 402 に対して 402 なので水平 0。
      // ただし縮尺により左右に余白ができる場合、中央に置くため親 Positioned が
      // left:0 / right:0 で伸縮する。中身は 402 幅を想定。
      padding: EdgeInsets.zero,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8 * scale),
        child: Stack(
          fit: StackFit.expand,
          children: [
            // 1) 写真フルブリード
            _buildPhotoLayer(post),

            // 1.5) 歌詞カードオーバーレイ (投稿者が編集した位置 / スケール / 回転を反映)
            _buildLyricsCardOverlay(post, scale),

            // 1.75) 左右タップゾーン (画面右半分タップで次、左半分タップで前)。
            //      Stack の後段の X ボタン / ユーザー情報より下に配置してあるので、
            //      それらのタップは優先される。
            Positioned.fill(
              child: Row(
                children: [
                  Expanded(
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: _tapPrevious,
                    ),
                  ),
                  Expanded(
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: _tapNext,
                    ),
                  ),
                ],
              ),
            ),

            // 2) 上端: セグメント進行バー (top:10, left:8, w:386, h:2)
            Positioned(
              left: 8 * scale,
              right: 8 * scale,
              top: 10 * scale,
              height: 2 * scale,
              child: _buildProgressSegments(segments, currentSegIdx),
            ),

            // 3) ユーザー情報 (top:17, left:12)。Figma では 170×33 固定だが、
            //    Vibe お題が長いと切れるので `right` で X ボタン手前まで広げ、
            //    height はインリンシック (Column が中身のぶんだけ縦に伸びる)。
            Positioned(
              left: 12 * scale,
              top: 17 * scale,
              right: 40 * scale,
              child: _buildUserInfo(post, scale),
            ),

            // 4) X ボタン (top:25, right: 402-(372.96+18)=11.04 → ≈11, size 18×18)
            Positioned(
              right: 11 * scale,
              top: 25 * scale,
              width: 18 * scale,
              height: 18 * scale,
              child: _buildCloseButton(),
            ),
          ],
        ),
      ),
    );
  }

  /// 歌詞カードオーバーレイ。
  ///
  /// 投稿保存時の座標系は PostCard 裏面 (363×645)。ストーリー枠は Figma 402×715
  /// なので `402/363 ≈ 1.108` を掛けて座標変換し、さらに outer [scale] を
  /// 掛けて実画素にする。回転はそのまま。
  Widget _buildLyricsCardOverlay(PostModel post, double scale) {
    // cardScale が 0 (＝気分投稿で無効化されているケース) は描画しない
    if (post.cardScale <= 0) return const SizedBox.shrink();
    const coordFactor = 402.0 / 363.0;
    final storyPosX = post.cardPositionX * coordFactor * scale;
    final storyPosY = post.cardPositionY * coordFactor * scale;
    final storyScale = post.cardScale * coordFactor * scale;
    final layoutType =
        LyricsCardLayout.getLayoutType(post.selectedLayoutIndex);
    return Positioned(
      left: storyPosX,
      top: storyPosY,
      child: Transform.scale(
        scale: storyScale,
        alignment: Alignment.topLeft,
        child: Transform.rotate(
          angle: post.cardRotation,
          alignment: Alignment.center,
          child: LyricsCardLayout(
            layoutType: layoutType,
            track: post.track,
            lyricsText: post.lyricsText,
          ),
        ),
      ),
    );
  }

  Widget _buildPhotoLayer(PostModel post) {
    final url = (post.photoUrl != null && post.photoUrl!.isNotEmpty)
        ? post.photoUrl!
        : post.track.albumImageUrl;
    if (url.isEmpty) {
      return const ColoredBox(color: Color(0xFF1F1F1F));
    }
    return CachedNetworkImage(
      imageUrl: url,
      fit: BoxFit.cover,
      placeholder: (_, __) => const ColoredBox(color: Color(0xFF1F1F1F)),
      errorWidget: (_, __, ___) => const ColoredBox(color: Color(0xFF1F1F1F)),
    );
  }

  Widget _buildProgressSegments(int count, int currentIdx) {
    if (count <= 1) {
      return _AnimatedSegmentBar(
        state: _SegmentState.current,
        progress: _progressCtrl,
      );
    }
    return Row(
      children: [
        for (int i = 0; i < count; i++) ...[
          Expanded(
            child: _AnimatedSegmentBar(
              state: i < currentIdx
                  ? _SegmentState.past
                  : (i == currentIdx
                      ? _SegmentState.current
                      : _SegmentState.future),
              progress: _progressCtrl,
            ),
          ),
          if (i < count - 1) const SizedBox(width: 4),
        ],
      ],
    );
  }

  Widget _buildUserInfo(PostModel post, double scale) {
    return Row(
      children: [
        // アイコン (32×32 円)
        SizedBox(
          width: 32 * scale,
          height: 32 * scale,
          child: ClipOval(
            child: (post.userIconUrl != null && post.userIconUrl!.isNotEmpty)
                ? CachedNetworkImage(
                    imageUrl: post.userIconUrl!,
                    fit: BoxFit.cover,
                    errorWidget: (_, __, ___) =>
                        const ColoredBox(color: Color(0xFF3A3A3A)),
                  )
                : const ColoredBox(color: Color(0xFF3A3A3A)),
          ),
        ),
        SizedBox(width: 12 * scale),
        // ユーザー名 + 時間 + Vibe お題
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              RichText(
                overflow: TextOverflow.ellipsis,
                text: TextSpan(
                  children: [
                    TextSpan(
                      text: '${post.username}　',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 12 * scale,
                        fontWeight: FontWeight.w600,
                        letterSpacing: -0.12,
                        height: 1.0,
                      ),
                    ),
                    TextSpan(
                      text: _formatTimeAgoShort(post.createdAt),
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 12 * scale,
                        fontWeight: FontWeight.w400,
                        letterSpacing: -0.12,
                        height: 1.0,
                      ),
                    ),
                  ],
                ),
              ),
              if (post.vibeTopicTitle != null &&
                  post.vibeTopicTitle!.isNotEmpty) ...[
                SizedBox(height: 2 * scale),
                Text(
                  '【#${post.vibeTopicTitle}】',
                  // 省略なし。長いお題は折り返して全文表示する。
                  softWrap: true,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 10 * scale,
                    fontWeight: FontWeight.w400,
                    height: 1.5,
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildCloseButton() {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => Navigator.of(context).maybePop(),
      child: const Center(
        child: Icon(
          CupertinoIcons.xmark,
          color: Colors.white,
          size: 18,
        ),
      ),
    );
  }

  // ────────────────────────────────────────────────────────────
  // 下枠 (メッセージ + リアクション)
  // ────────────────────────────────────────────────────────────

  Widget _buildBottomBar(double scale) {
    // アイコンを 2 個 (Heart + Comment) に減らし、その分メッセージ入力欄を右へ広げる。
    // 元 Figma: message 244w + 3 icons (48×3=144, spaceAround)
    //   → 変更: message 292w (=244+48) + 2 icons (48×2=96)
    // 402 - 16(left) - 292 = 94 が右側スペース → 2 アイコンが余裕を持って収まる。
    final iconRight = 8 * scale;
    return SizedBox(
      height: 97 * scale,
      child: Stack(
        children: [
          // メッセージ入力 (left:16, top:11, size 292×44, rounded 28, border #6D6F72)
          Positioned(
            left: 16 * scale,
            top: 11 * scale,
            width: 292 * scale,
            height: 44 * scale,
            child: _buildMessageField(scale),
          ),
          // Heart + Comment のリアクション 2 個 (PostCard 裏面と同じデザインを流用)。
          // Icons.favorite / message_circle.svg 24×24 白。ラベル・カウントは表示しない。
          Positioned(
            left: 308 * scale,
            right: iconRight,
            top: 8 * scale,
            height: 48 * scale,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _heartIcon(scale),
                _commentIcon(scale),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMessageField(double scale) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(28 * scale),
        border: Border.all(color: const Color(0xFF6D6F72)),
      ),
      alignment: Alignment.centerLeft,
      padding: EdgeInsets.only(left: 20 * scale, right: 12 * scale),
      child: Text(
        'メッセージを送信',
        style: TextStyle(
          color: Colors.white,
          fontSize: 13 * scale,
          fontWeight: FontWeight.w400,
          letterSpacing: -0.13,
        ),
      ),
    );
  }

  /// PostCard 裏面と同じハート (Icons.favorite / favorite_border)。
  /// Figma bbox は 24×24 だが 400w 画面では小さく見えるので +4px。
  Widget _heartIcon(double scale) {
    final liked = _currentIsLiked();
    return GestureDetector(
      onTap: _handleLike,
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        width: 48 * scale,
        height: 48 * scale,
        child: Center(
          child: Icon(
            liked ? Icons.favorite : Icons.favorite_border,
            size: 28 * scale,
            color: liked ? Colors.red : Colors.white,
          ),
        ),
      ),
    );
  }

  /// PostCard 裏面と同じ吹き出し (assets/icons/message_circle.svg)。
  /// Figma bbox は 26×26 (Heart より少し大きい) — 比率を保って +4px の 30×30 に。
  Widget _commentIcon(double scale) {
    return GestureDetector(
      onTap: _openComments,
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        width: 48 * scale,
        height: 48 * scale,
        child: Center(
          child: SvgPicture.asset(
            'assets/icons/message_circle.svg',
            width: 30 * scale,
            height: 30 * scale,
            colorFilter: const ColorFilter.mode(
              Colors.white,
              BlendMode.srcIn,
            ),
          ),
        ),
      ),
    );
  }

  // ────────────────────────────────────────────────────────────
  // アクション
  // ────────────────────────────────────────────────────────────

  bool _currentIsLiked() {
    if (_allPosts.isEmpty) return false;
    final post = _allPosts[_currentAllIdx];
    final ui = context.read<PostUIState>();
    return ui.isLiked(post.postId) ||
        (widget.currentUserId.isNotEmpty &&
            post.isLikedBy(widget.currentUserId));
  }

  Future<void> _handleLike() async {
    if (_allPosts.isEmpty) return;
    final post = _allPosts[_currentAllIdx];
    final uid = FirebaseAuth.instance.currentUser?.uid ?? widget.currentUserId;
    if (uid.isEmpty) return;
    await PostUIState.handleLike(
      context: context,
      post: post,
      userId: uid,
      postService: _postService,
    );
    if (mounted) setState(() {});
  }

  void _openComments() {
    if (_allPosts.isEmpty) return;
    final post = _allPosts[_currentAllIdx];
    CommentScreen.show(context, post: post);
  }

  // ────────────────────────────────────────────────────────────
  // ヘルパー
  // ────────────────────────────────────────────────────────────

  /// Figma の「1時間」表記 (単位のみ、"前" は付けない)。
  String _formatTimeAgoShort(DateTime createdAt) {
    final raw = DateTime.now().difference(createdAt);
    final d = raw.isNegative ? Duration.zero : raw;
    if (d.inMinutes < 1) return 'たった今';
    if (d.inHours < 1) return '${d.inMinutes}分';
    if (d.inDays < 1) return '${d.inHours}時間';
    return '${d.inDays}日';
  }
}

enum _SegmentState { past, current, future }

/// セグメント進行バー 1 個分。
///
/// - past  : 白満(前景 100%)
/// - current: 背景 35% 白 + 前景 白バーが 0→100% で伸びるアニメ
/// - future : 背景 35% 白のみ
class _AnimatedSegmentBar extends StatelessWidget {
  final _SegmentState state;
  final AnimationController progress;

  const _AnimatedSegmentBar({
    required this.state,
    required this.progress,
  });

  @override
  Widget build(BuildContext context) {
    final borderRadius = BorderRadius.circular(2);
    // 半透明バーの背景色。alpha を上げて明るい写真の上でも視認できるよう
    // Instagram に寄せる。future / current の背景 + past 経過分下地に共通で使う。
    final bg = Colors.white.withValues(alpha: 0.55);

    switch (state) {
      case _SegmentState.past:
        // 100% 白の背景。角丸あり。
        return Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: borderRadius,
          ),
        );
      case _SegmentState.future:
        // 55% 白の半透明背景 (アニメ無し、常時表示)。角丸あり。
        return Container(
          decoration: BoxDecoration(
            color: bg,
            borderRadius: borderRadius,
          ),
        );
      case _SegmentState.current:
        // 背景 = 55% 白 (常時可視)、前景 = 100% 白 (幅が progress に応じて 0→100%)。
        // LayoutBuilder で親から実サイズを取り、Container(width: ...) で明示的に
        // 幅を制御するので、FractionallySizedBox 起因のレイアウト曖昧さを避ける。
        return ClipRRect(
          borderRadius: borderRadius,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final maxW = constraints.maxWidth;
              return Stack(
                children: [
                  Positioned.fill(child: ColoredBox(color: bg)),
                  AnimatedBuilder(
                    animation: progress,
                    builder: (context, _) {
                      final p = progress.value.clamp(0.0, 1.0);
                      return Align(
                        alignment: Alignment.centerLeft,
                        child: Container(
                          width: maxW * p,
                          height: double.infinity,
                          color: Colors.white,
                        ),
                      );
                    },
                  ),
                ],
              );
            },
          ),
        );
    }
  }
}

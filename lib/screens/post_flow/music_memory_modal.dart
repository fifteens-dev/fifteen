import 'dart:math' as math;
import 'dart:ui';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../constants/profile_fonts.dart';
import '../../models/post_model.dart';
import '../../models/track_model.dart';
import '../../models/user_model.dart';
import '../../services/audio_player_service.dart';
import '../../services/music_service_manager.dart';
import '../../services/now_playing_service.dart';
import '../../services/post_service.dart';
import '../../services/user_service.dart';
import '../../utils/color_extractor.dart';
import '../../widgets/post_card.dart';
import '../post_photo_selection_screen.dart';

/// アルバムアートから抽出したグラデーション色の**プロセス寿命**キャッシュ。
///
/// 投稿ボタンを押したときに 1 度だけ抽出 → 以降どのモーダル open からも即座に
/// 同じ色を使い回す。モーダルの再オープンや deck の再構築で消えない。
///
/// - [get] : 同期取得。無ければ null
/// - [ensureAll] : 与えられた全 track の色抽出を並列で開始し、全部完了するまで await
class _DeckColorCache {
  static final Map<String, (Color, Color)> _cache = {};
  static final Map<String, Future<void>> _inflight = {};

  static (Color, Color)? get(String trackId) => _cache[trackId];

  static Future<void> _ensureOne(TrackModel track) {
    final id = track.trackId;
    if (_cache.containsKey(id)) return Future.value();
    final inflight = _inflight[id];
    if (inflight != null) return inflight;
    if (track.albumImageUrl.isEmpty) return Future.value();

    final f = () async {
      try {
        final c = await ColorExtractor.extractGradientColors(
          track.albumImageUrl,
        );
        _cache[id] = c;
      } catch (_) {
        // 抽出失敗はキャッシュに残さず、PostCard 側 fallback に委ねる
      } finally {
        _inflight.remove(id);
      }
    }();
    _inflight[id] = f;
    return f;
  }

  /// 与えられた全 track の色抽出を並列で開始し、全部完了するまで await。
  /// すでに全部キャッシュ済みなら 1 マイクロタスクで解決。
  static Future<void> ensureAll(Iterable<TrackModel> tracks) {
    return Future.wait(tracks.map(_ensureOne));
  }
}

/// 「今日のMusic Memory」投稿フローモーダル（Apple Music ユーザー向け）。
///
/// - タイトル「今日のMusic Memory」＋サブタイトル（Now Playing / ○時間前）。
/// - カードは中央スナップの横スクロール・カルーセル（[_CardCarousel]）。中央に
///   来るたびハプティック。中央のカードが選択対象。
/// - 初回投稿（その日まだ未投稿）: 中央カードが緩く横揺れ＋「←左スワイプで曲を変更」
///   ＋直下に「この曲で続ける」。次回以降: 揺れ無し・文言無しでボタンのみ中央。
/// - 「この曲で続ける」で PostPhotoSelectionScreen（写真フロー）へ。
///
/// ※ Spotify ユーザーはこのモーダルではなく VibeStoryPostSheet（お題非表示）から
///   楽曲選択し、同じ写真フローへ合流する（home_screen 側で分岐）。
class MusicMemoryModal extends StatefulWidget {
  /// 表示するトラック。null の場合は内部で MusicServiceManager から
  /// 最近再生履歴を取得する。
  final List<TrackModel>? tracks;

  const MusicMemoryModal({super.key, this.tracks});

  static Future<void> open(
    BuildContext context, {
    List<TrackModel>? tracks,
  }) {
    return Navigator.of(context).push(
      PageRouteBuilder(
        opaque: false,
        barrierDismissible: true,
        barrierColor: Colors.black.withValues(alpha: 0.45),
        transitionDuration: const Duration(milliseconds: 280),
        reverseTransitionDuration: const Duration(milliseconds: 200),
        pageBuilder: (_, __, ___) => MusicMemoryModal(tracks: tracks),
        transitionsBuilder: (_, animation, __, child) {
          final curved = CurvedAnimation(
            parent: animation,
            curve: Curves.easeOutCubic,
            reverseCurve: Curves.easeInCubic,
          );
          return FadeTransition(
            opacity: curved,
            child: ScaleTransition(
              scale: Tween<double>(begin: 0.9, end: 1.0).animate(curved),
              child: child,
            ),
          );
        },
      ),
    );
  }

  @override
  State<MusicMemoryModal> createState() => _MusicMemoryModalState();
}

class _MusicMemoryModalState extends State<MusicMemoryModal> {
  final MusicServiceManager _music = MusicServiceManager();
  final UserService _userService = UserService();
  final PostService _postService = PostService();
  final AudioPlayerService _audioService = AudioPlayerService();
  List<TrackModel> _tracks = const [];
  bool _loading = true;
  // 色抽出まで含めてカード描画可能かどうか。
  bool _colorsReady = false;

  // 現在中央にあるカードの index（サブタイトル・確定対象）。
  int _centerIndex = 0;

  // その日（現サイクル）まだ投稿していない = 初回投稿フロー。
  // 初回はカード横揺れ＋「←左スワイプで曲を変更」を出す。判定確定まで false。
  bool _isFirstPost = false;

  // カード内 PostCard 描画用のユーザー情報 (プロフィール表示・楽観 UI 用)
  UserModel? _me;

  @override
  void initState() {
    super.initState();
    // 引数で tracks が渡されていればそれを使う。無ければ内部でフェッチ。
    final provided = widget.tracks;
    if (provided != null) {
      _applyTracks(provided);
    } else {
      _loadTracks();
    }
    _loadMe();
    _loadFirstPostFlag();
  }

  /// 取得したトラックに端末の再生情報（Now Playing / 最終再生時刻）を付与してから
  /// state に反映し、色抽出を開始する。
  Future<void> _applyTracks(List<TrackModel> tracks) async {
    final enriched = await NowPlayingService().enrich(tracks);
    if (!mounted) return;
    setState(() {
      _tracks = enriched;
      _loading = false;
    });
    await _prepareColors(enriched);
  }

  Future<void> _loadFirstPostFlag() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    try {
      final posted = await _postService.hasAnyPostInCurrentCycle(uid);
      if (mounted) setState(() => _isFirstPost = !posted);
    } catch (_) {}
  }

  Future<void> _loadTracks() async {
    try {
      final tracks = await _music.getRecentlyPlayedTracks(limit: 15);
      if (!mounted) return;
      await _applyTracks(tracks);
    } catch (_) {
      if (mounted) {
        setState(() {
          _loading = false;
          _colorsReady = true;
        });
      }
    }
  }

  /// 表示前に全 track の色をプロセス寿命キャッシュへ乗せる。
  /// キャッシュに既にあるものは瞬時に返るので、2 回目以降のモーダルオープンは
  /// 実質ゼロレイテンシで deck が出る。
  Future<void> _prepareColors(List<TrackModel> tracks) async {
    await _DeckColorCache.ensureAll(tracks);
    if (!mounted) return;
    setState(() => _colorsReady = true);
  }

  Future<void> _loadMe() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    try {
      final me = await _userService.getUser(uid);
      if (mounted) setState(() => _me = me);
    } catch (_) {}
  }

  /// 白ボタン「この曲で続ける」→ 以前の投稿フローと同じカメラ画面へ。
  /// PostPhotoSelectionScreen が上下 2 ページの Vertical PageView (カメラ / 写真グリッド) を持ち、
  /// 撮影・写真選択の後 PostCardEditScreen → PostFinalPreviewScreen へ進む。
  ///
  /// カメラ画面左上のくの字ボタンで曲選択に戻れるよう、モーダル自体は
  /// pop せずスタックに残しておく (カメラは fullscreenDialog で上に被さる)。
  void _confirmAndProceed(TrackModel track) {
    Navigator.of(context).push(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => PostPhotoSelectionScreen(
          track: track,
          isMoodPost: true,
        ),
      ),
    );
  }

  /// 中央カードのサブタイトル。Now Playing / ○時間前。データ無しは空文字（非表示）。
  String _centerSubtitle() {
    if (_tracks.isEmpty) return '';
    final t = _tracks[_centerIndex.clamp(0, _tracks.length - 1)];
    if (t.isNowPlaying) return 'Now Playing';
    final at = t.playedAt;
    if (at == null) return '';
    final diff = DateTime.now().difference(at);
    if (diff.inMinutes < 1) return 'たった今';
    if (diff.inMinutes < 60) return '${diff.inMinutes}分前';
    if (diff.inHours < 24) return '${diff.inHours}時間前';
    return '${diff.inDays}日前';
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      type: MaterialType.transparency,
      child: Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => Navigator.of(context).maybePop(),
            ),
          ),
          Center(
            child: SizedBox(
              width: 360,
              height: 640,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(20),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
                  child: Container(
                    decoration: BoxDecoration(
                      color: const Color(0xFF1B1B1B).withValues(alpha: 0.55),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.10),
                        width: 1,
                      ),
                    ),
                    child: Stack(
                      children: [
                        // 左上: 閉じる X (Figma: (22, 31), 32×32)
                        Positioned(
                          left: 22,
                          top: 31,
                          width: 32,
                          height: 32,
                          child: GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: () => Navigator.of(context).maybePop(),
                            child: Container(
                              decoration: const BoxDecoration(
                                shape: BoxShape.circle,
                                color: Color(0xFF2B2B2B),
                              ),
                              alignment: Alignment.center,
                              child: const Icon(
                                CupertinoIcons.xmark,
                                color: Colors.white,
                                size: 16,
                              ),
                            ),
                          ),
                        ),
                        // タイトル (Figma: (99, 37) 175×21)
                        const Positioned(
                          left: 0,
                          right: 0,
                          top: 37,
                          child: Center(
                            child: Text(
                              '今日のMusic Memory',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 18,
                                fontWeight: FontWeight.w700,
                                fontFamily: kSfProRounded,
                              ),
                            ),
                          ),
                        ),
                        // サブタイトル: Now Playing / ○時間前（データが無ければ非表示）。
                        Positioned(
                          left: 0,
                          right: 0,
                          top: 63,
                          child: Center(
                            child: Text(
                              _centerSubtitle(),
                              style: const TextStyle(
                                color: Color(0xFF9A9A9A),
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                                fontFamily: kSfProRounded,
                              ),
                            ),
                          ),
                        ),
                        // カード（中央スナップの横スクロール・カルーセル）。
                        Positioned(
                          left: 0,
                          right: 0,
                          top: 92,
                          height: 452,
                          child: (_loading || !_colorsReady)
                              ? const Center(
                                  child: CupertinoActivityIndicator(
                                    color: Colors.white,
                                    radius: 12,
                                  ),
                                )
                              : _tracks.isEmpty
                                  ? const Center(
                                      child: Text(
                                        '最近再生した曲がありません',
                                        style: TextStyle(
                                          color: Colors.white70,
                                          fontSize: 13,
                                        ),
                                      ),
                                    )
                                  : _CardCarousel(
                                      tracks: _tracks,
                                      audioService: _audioService,
                                      currentUserId: _me?.uid ?? '',
                                      currentUsername: _me?.username ?? '',
                                      currentUserIconUrl:
                                          _me?.profileImageUrl,
                                      wobble: _isFirstPost,
                                      onCenterChanged: (i) {
                                        if (_centerIndex != i && mounted) {
                                          setState(() => _centerIndex = i);
                                        }
                                      },
                                    ),
                        ),
                        // 下部: 初回は「←左スワイプで曲を変更」＋その下にボタン、
                        // 次回以降はボタンのみを中央配置。
                        Positioned(
                          left: 0,
                          right: 0,
                          bottom: 34,
                          child: Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (_isFirstPost) ...[
                                  const Text(
                                    '←　左スワイプで曲を変更',
                                    style: TextStyle(
                                      color: Color(0xFF8D8D8D),
                                      fontSize: 15,
                                      fontWeight: FontWeight.w500,
                                      fontFamily: kSfProRounded,
                                    ),
                                  ),
                                  const SizedBox(height: 12),
                                ],
                                _ContinueButton(
                                  onTap: () {
                                    if (_tracks.isEmpty) return;
                                    final i = _centerIndex
                                        .clamp(0, _tracks.length - 1);
                                    _confirmAndProceed(_tracks[i]);
                                  },
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// カード カルーセル（中央スナップ + スナップ毎ハプティック + 初回のみ横揺れ）
// ─────────────────────────────────────────────────────────────

class _CardCarousel extends StatefulWidget {
  final List<TrackModel> tracks;
  final AudioPlayerService audioService;
  final String currentUserId;
  final String currentUsername;
  final String? currentUserIconUrl;

  /// 初回投稿フロー時 true → 中央カードが左右に緩く揺れる。
  final bool wobble;

  /// 中央に来ているカードの index が変わったとき通知。
  final ValueChanged<int> onCenterChanged;

  const _CardCarousel({
    required this.tracks,
    required this.audioService,
    required this.currentUserId,
    required this.currentUsername,
    required this.currentUserIconUrl,
    required this.wobble,
    required this.onCenterChanged,
  });

  @override
  State<_CardCarousel> createState() => _CardCarouselState();
}

class _CardCarouselState extends State<_CardCarousel>
    with SingleTickerProviderStateMixin {
  late final PageController _controller;
  late final AnimationController _wobbleCtrl;
  int _lastCenter = 0;

  // 仮 PostModel の createdAt をフレーム間で安定にするための固定値。
  static final DateTime _stableTs = DateTime(2026);

  @override
  void initState() {
    super.initState();
    _controller = PageController();
    _controller.addListener(_onScroll);
    _wobbleCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );
    if (widget.wobble) _wobbleCtrl.repeat();
  }

  @override
  void didUpdateWidget(covariant _CardCarousel old) {
    super.didUpdateWidget(old);
    if (widget.wobble && !_wobbleCtrl.isAnimating) {
      _wobbleCtrl.repeat();
    } else if (!widget.wobble && _wobbleCtrl.isAnimating) {
      _wobbleCtrl
        ..stop()
        ..value = 0;
    }
  }

  void _onScroll() {
    final page = _controller.page;
    if (page == null) return;
    final center = page.round();
    if (center != _lastCenter) {
      _lastCenter = center;
      HapticFeedback.selectionClick(); // 中心に来るたび「カチッ」
      widget.onCenterChanged(center);
    }
  }

  @override
  void dispose() {
    _controller.removeListener(_onScroll);
    _controller.dispose();
    _wobbleCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        return PageView.builder(
          controller: _controller,
          physics: const BouncingScrollPhysics(),
          itemCount: widget.tracks.length,
          itemBuilder: (context, index) {
            Widget card = _CardBody(
              track: widget.tracks[index],
              audioService: widget.audioService,
              currentUserId: widget.currentUserId,
              currentUsername: widget.currentUsername,
              currentUserIconUrl: widget.currentUserIconUrl,
              stableTs: _stableTs,
              maxWidth: c.maxWidth,
              maxHeight: c.maxHeight,
            );
            // 初回のみ、中央のカードだけを緩く左右に揺らす（隣接は減衰）。
            if (widget.wobble) {
              card = AnimatedBuilder(
                animation: _wobbleCtrl,
                builder: (context, child) {
                  final page = _controller.hasClients
                      ? (_controller.page ?? index.toDouble())
                      : index.toDouble();
                  final amp = (1 - (page - index).abs()).clamp(0.0, 1.0);
                  final angle =
                      math.sin(_wobbleCtrl.value * 2 * math.pi) * 0.045 * amp;
                  return Transform.rotate(
                    angle: angle,
                    alignment: Alignment.center,
                    child: child,
                  );
                },
                child: card,
              );
            }
            return Center(child: card);
          },
        );
      },
    );
  }
}

/// カード 1 枚（既存 [PostCard] を表面のみでレンダリングし、利用可能領域に
/// アスペクト比 363:645 を保って収める）。色は [_DeckColorCache] から同期取得。
class _CardBody extends StatelessWidget {
  final TrackModel track;
  final AudioPlayerService audioService;
  final String currentUserId;
  final String currentUsername;
  final String? currentUserIconUrl;
  final DateTime stableTs;
  final double maxWidth;
  final double maxHeight;

  const _CardBody({
    required this.track,
    required this.audioService,
    required this.currentUserId,
    required this.currentUsername,
    required this.currentUserIconUrl,
    required this.stableTs,
    required this.maxWidth,
    required this.maxHeight,
  });

  @override
  Widget build(BuildContext context) {
    const nativeW = 363.0;
    const nativeH = 645.0;
    // 影ぶんの余白を残して高さ基準でフィット、幅超過時は幅基準。
    final availH = (maxHeight - 20).clamp(0.0, double.infinity);
    final availW = (maxWidth - 44).clamp(0.0, double.infinity);
    double cardH = availH;
    double cardW = cardH * nativeW / nativeH;
    if (cardW > availW) {
      cardW = availW;
      cardH = cardW * nativeH / nativeW;
    }

    final colors = _DeckColorCache.get(track.trackId);
    final post = PostModel(
      postId: '__deck_preview_${track.trackId}__',
      userId: currentUserId.isNotEmpty ? currentUserId : '__preview__',
      username: currentUsername.isNotEmpty ? currentUsername : 'ユーザー',
      userIconUrl: currentUserIconUrl,
      track: track,
      createdAt: stableTs,
      updatedAt: stableTs,
    );

    return SizedBox(
      width: cardW,
      height: cardH,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(15),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.24),
              blurRadius: 30,
              offset: const Offset(0, 20),
            ),
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.14),
              blurRadius: 80,
              offset: const Offset(0, 50),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(15),
          child: FittedBox(
            fit: BoxFit.fill,
            child: SizedBox(
              width: nativeW,
              height: nativeH,
              child: IgnorePointer(
                child: PostCard(
                  key: ValueKey('deck-preview-${track.trackId}'),
                  post: post,
                  audioService: audioService,
                  showFrontOnly: true,
                  hideReactionCounts: true,
                  hideAudienceBadge: true,
                  disableInteractions: true,
                  backSideEnabled: false,
                  currentUserId: currentUserId,
                  currentUserIconUrl: currentUserIconUrl,
                  preExtractedGradientStart: colors?.$1,
                  preExtractedGradientEnd: colors?.$2,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 白ピル「この曲で続ける」ボタン（既存 UI を踏襲: 258×42・角丸36・グレー文字）。
class _ContinueButton extends StatelessWidget {
  final VoidCallback onTap;
  const _ContinueButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        width: 258,
        height: 42,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(36),
        ),
        alignment: Alignment.center,
        child: const Text(
          'この曲で続ける',
          style: TextStyle(
            color: Color(0xFF8D8D8D),
            fontSize: 15,
            fontWeight: FontWeight.w500,
            fontFamily: kSfProRounded,
          ),
        ),
      ),
    );
  }
}

import 'dart:math' as math;
import 'dart:ui';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../../constants/profile_fonts.dart';
import '../../models/post_model.dart';
import '../../models/track_model.dart';
import '../../models/user_model.dart';
import '../../services/audio_player_service.dart';
import '../../services/music_service_manager.dart';
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

/// 「今日のMusic Memory」カード束モーダル。
///
/// Figma 4697:9576 / Component 128 (Component 123 / 124) 準拠。
///
/// 2 つの状態を持つ:
///   - **browsing (Component 123)**: カード束が扇状に重なり、下部に
///     「← スワイプして曲を変更 →」のグレーテキスト
///   - **confirming (Component 124)**: 前面カードが 10.9% 拡大 + 少し左上へ、
///     背面カードは同一サイズ 177×314.5 に統一されて右側にまっすぐ縦積み
///     (117〜142 の 5px 間隔)、全て回転 0°・不透明 0.84・blur 1px。
///     下部が白ピル「この曲で続ける」ボタンに変化。
///
/// 前面カード タップで browsing → confirming、
/// 白ボタン タップで投稿プレビューへ遷移する。confirming で再度タップ or スワイプ
/// すると browsing に戻る。
///
/// browsing モードで前面カードを左右に大きくスワイプすると、
/// カードが退場して次のトラックが前面に上がる (Tinder 風)。
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

enum _DeckMode { browsing, confirming }

class _MusicMemoryModalState extends State<MusicMemoryModal>
    with SingleTickerProviderStateMixin {
  _DeckMode _mode = _DeckMode.browsing;
  late final AnimationController _modeCtrl;

  final MusicServiceManager _music = MusicServiceManager();
  final UserService _userService = UserService();
  final AudioPlayerService _audioService = AudioPlayerService();
  List<TrackModel> _tracks = const [];
  bool _loading = true;
  // 色抽出まで含めて deck 描画可能かどうか。
  // これが true になって初めて _CardDeck を作る。
  bool _colorsReady = false;

  // カード内 PostCard 描画用のユーザー情報 (プロフィール表示・楽観 UI 用)
  UserModel? _me;

  @override
  void initState() {
    super.initState();
    _modeCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 320),
    );
    // 引数で tracks が渡されていればそれを使う。無ければ内部でフェッチ。
    final provided = widget.tracks;
    if (provided != null) {
      _tracks = provided;
      _loading = false;
      _prepareColors(provided);
    } else {
      _loadTracks();
    }
    _loadMe();
  }

  Future<void> _loadTracks() async {
    try {
      final tracks = await _music.getRecentlyPlayedTracks(limit: 15);
      if (!mounted) return;
      setState(() {
        _tracks = tracks;
        _loading = false;
      });
      await _prepareColors(tracks);
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

  @override
  void dispose() {
    _modeCtrl.dispose();
    super.dispose();
  }

  void _toBrowsing() {
    if (_mode == _DeckMode.browsing) return;
    setState(() => _mode = _DeckMode.browsing);
    _modeCtrl.reverse();
  }

  void _toConfirming() {
    if (_mode == _DeckMode.confirming) return;
    setState(() => _mode = _DeckMode.confirming);
    _modeCtrl.forward();
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
                        // カード束 (Figma: (54, 123), 319×458)
                        // 中身は Stack + Positioned で絶対配置するのでサイズ固定。
                        Positioned(
                          left: 20,
                          top: 123,
                          width: 320,
                          height: 458,
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
                                  : _CardDeck(
                                      tracks: _tracks,
                                      modeCtrl: _modeCtrl,
                                      isConfirming:
                                          _mode == _DeckMode.confirming,
                                      audioService: _audioService,
                                      currentUserId: _me?.uid ?? '',
                                      currentUsername: _me?.username ?? '',
                                      currentUserIconUrl:
                                          _me?.profileImageUrl,
                                      onTapFront: () {
                                        if (_mode == _DeckMode.browsing) {
                                          _toConfirming();
                                        } else {
                                          _toBrowsing();
                                        }
                                      },
                                      onSwipedAway: () {
                                        // browsing での スワイプで次カードへ。
                                        // confirming なら状態を browsing に戻す。
                                        if (_mode ==
                                            _DeckMode.confirming) {
                                          _toBrowsing();
                                        }
                                      },
                                    ),
                        ),
                        // 下部: 状態でボタンを差替 (Figma Component 125 / 126)
                        Positioned(
                          left: 0,
                          right: 0,
                          bottom: 55,
                          child: Center(
                            child: _BottomBar(
                              modeCtrl: _modeCtrl,
                              isConfirming: _mode == _DeckMode.confirming,
                              onConfirm: () {
                                if (_tracks.isNotEmpty) {
                                  _confirmAndProceed(_tracks[0]);
                                }
                              },
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
// カード束 (2 状態間の morph + Tinder 風スワイプ)
// ─────────────────────────────────────────────────────────────

class _CardDeck extends StatefulWidget {
  final List<TrackModel> tracks;
  final AnimationController modeCtrl;
  final bool isConfirming;
  final AudioPlayerService audioService;
  final String currentUserId;
  final String currentUsername;
  final String? currentUserIconUrl;
  final VoidCallback onTapFront;
  final VoidCallback onSwipedAway;

  const _CardDeck({
    required this.tracks,
    required this.modeCtrl,
    required this.isConfirming,
    required this.audioService,
    required this.currentUserId,
    required this.currentUsername,
    required this.currentUserIconUrl,
    required this.onTapFront,
    required this.onSwipedAway,
  });

  @override
  State<_CardDeck> createState() => _CardDeckState();
}

class _CardDeckState extends State<_CardDeck>
    with SingleTickerProviderStateMixin {
  static const int _kMaxVisible = 7;

  int _topIndex = 0;
  Offset _drag = Offset.zero;

  late final AnimationController _swipeCtrl;
  Animation<Offset>? _swipeTween;
  bool _isSwiping = false;

  // ── アルバムアートからの色抽出キャッシュ ──
  //
  // 色はモーダル open 前に [_DeckColorCache] へ全部乗せてある前提。
  // ここでは同期取得のみを行い、抽出そのものは走らせない。
  //
  // これによりカードごとに:
  //   1. PostCard がフレーム 1 目から preExtracted 色を受け取れる
  //   2. PostCard 側の初回 initState で内部の runtime 抽出が発動しない
  //   3. スワイプで新規カードが deck に入ってきても再抽出が走らない

  // ── Figma 実測値 (Component 123 = state A / Component 124 = state B) ──
  //
  // depth 0 = 前面カード
  // depth 1〜6 = 背面カード (奥ほど depth 大)

  // State A (browsing) — Component 123
  // 位置は「flex コンテナの左上」。flex 内は中央配置なので、実際は
  // rotate 前の card の中心 = flex コンテナの中央。
  // Figma は rotate 後の bounding box を left/top で保存しているので
  // card 実サイズと flex コンテナサイズが少し異なる。
  //   → 描画位置 = flex left + (flex width - card width) / 2
  //              , flex top  + (flex height - card height) / 2
  //   これで rotate 前のカード左上が求まる。
  //
  // Card 1 (depth 0, front): flex 0,0 237.53×388.8 → wait, Card 1 is at (0,0), 215.46×382.26.
  // 正確には depth 0 = Card 1 (最前面) と Card 2 (depth 1) など。
  static const _cardWA = [215.0, 210.7, 204.123, 196.457, 188.474, 188.282, 177.0];
  static const _cardHA = [382.0, 374.384, 362.697, 349.077, 334.892, 334.55, 314.0];
  // Figma flex コンテナの (x, y, w, h)
  static const _flexA = [
    [0.0, 0.0, 215.456, 382.256],
    [0.0, 0.0, 237.534, 388.8],
    [24.0, 10.0, 238.014, 380.625],
    [58.0, 22.0, 228.958, 366.274],
    [89.0, 37.0, 208.858, 345.924],
    [110.0, 46.0, 198.773, 340.34],
    [133.98, 56.77, 185.051, 318.467],
  ];
  static const _rotDegA = [-0.07, -4.2, -5.51, -5.49, -3.55, -1.81, -1.48];
  static const _opacityA = [1.0, 0.95, 0.88, 0.78, 0.65, 0.52, 0.5];

  // State B (confirming) — Component 124
  // 前面カードは flex (7, -25) 235.749×418.287、rotation -0.07°
  //   ボタンコンテナ自体が left 13 に shift するので、実際の deck 原点からは
  //   x = 13 + 7 = 20, y = -25。
  // 背面カードは全て 177×314.5 rotation 0、位置は left [117..142] top 59
  //   (5px 間隔で 6 枚)。デバイス上の位置は左 +13 → 130..155。
  static const _cardWB = [235.25, 177.0, 177.0, 177.0, 177.0, 177.0, 177.0];
  static const _cardHB = [418.006, 314.504, 314.504, 314.504, 314.504, 314.504, 314.504];
  // 「State B の描画位置(rotate 前の左上)」を直接指定。
  static const _drawXB = [20.0, 130.0, 135.0, 140.0, 145.0, 150.0, 155.0];
  static const _drawYB = [-25.0, 59.0, 59.0, 59.0, 59.0, 59.0, 59.0];
  static const _rotDegB = [-0.07, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0];
  static const _opacityB = [1.0, 0.84, 0.84, 0.84, 0.84, 0.84, 0.84];
  static const _blurB = [0.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0];

  @override
  void initState() {
    super.initState();
    _swipeCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 260),
    );
  }

  @override
  void dispose() {
    _swipeCtrl.dispose();
    super.dispose();
  }

  // ── ジェスチャー ──

  void _onPanUpdate(DragUpdateDetails d) {
    if (_isSwiping) return;
    // confirming モードではドラッグを弱く反映 (視覚的なフィードバックはある
    // が閾値超で「browsing に戻る」だけ)。
    setState(() {
      _drag += d.delta;
    });
  }

  /// 右ドラッグ量 → 逆再生プログレス (0..1)。左ドラッグ時 / 確定モード時は 0。
  double _computeReverseProgress(double width) {
    if (widget.isConfirming || _drag.dx <= 0) return 0.0;
    return (_drag.dx / (width * 0.35)).clamp(0.0, 1.0);
  }

  void _onPanEnd(DragEndDetails d, double width) {
    if (_isSwiping) return;
    final vx = d.velocity.pixelsPerSecond.dx;

    if (widget.isConfirming) {
      _snapBackDrag();
      widget.onSwipedAway();
      return;
    }

    if (_drag.dx > 20) {
      // 右ドラッグ: 逆再生 — 進捗が閾値超なら _topIndex-- を確定、以下ならスナップバック
      final revP = _computeReverseProgress(width);
      if (revP > 0.5 || vx > 500) {
        _animateReverseComplete(width);
      } else {
        _snapBackDrag();
      }
    } else if (_drag.dx < -20 || vx < -500) {
      // 左ドラッグ: 通常の Tinder 風 exit
      final overThreshold = _drag.dx.abs() > width * 0.28;
      final fastFlick = vx < -800;
      if (overThreshold || fastFlick) {
        _animateForwardSwipe(width);
      } else {
        _snapBackDrag();
      }
    } else {
      _snapBackDrag();
    }
  }

  /// 左スワイプ: 前面カードが左に退場 → 次のトラック (_topIndex + 1) が前面へ。
  void _animateForwardSwipe(double width) {
    _isSwiping = true;
    _swipeCtrl.duration = const Duration(milliseconds: 260);
    final target = Offset(-(width + 200), _drag.dy);
    _swipeTween = Tween<Offset>(begin: _drag, end: target).animate(
      CurvedAnimation(parent: _swipeCtrl, curve: Curves.easeOut),
    );
    _swipeCtrl
      ..reset()
      ..addListener(_onSwipeTick)
      ..forward().whenComplete(() {
        if (!mounted) return;
        setState(() {
          _topIndex = (_topIndex + 1) % widget.tracks.length;
          _drag = Offset.zero;
          _isSwiping = false;
          _swipeTween = null;
        });
        _swipeCtrl.removeListener(_onSwipeTick);
      });
  }

  /// 右スワイプ確定: 逆再生プログレスを 100% (drag = width*0.35) までアニメで進めて
  /// commit (_topIndex--)、drag を 0 に戻す。
  ///   commit 時に「進捗 1 の見た目」と「進捗 0 の見た目 (_topIndex 変更後)」が
  ///   一致するのでビジュアルポップは起きない。
  void _animateReverseComplete(double width) {
    _isSwiping = true;
    _swipeCtrl.duration = const Duration(milliseconds: 200);
    final target = Offset(width * 0.35, 0);
    _swipeTween = Tween<Offset>(begin: _drag, end: target).animate(
      CurvedAnimation(parent: _swipeCtrl, curve: Curves.easeOutCubic),
    );
    _swipeCtrl
      ..reset()
      ..addListener(_onSwipeTick)
      ..forward().whenComplete(() {
        if (!mounted) return;
        setState(() {
          final n = widget.tracks.length;
          _topIndex = (_topIndex - 1 + n) % n;
          _drag = Offset.zero;
          _isSwiping = false;
          _swipeTween = null;
        });
        _swipeCtrl.removeListener(_onSwipeTick);
      });
  }

  void _snapBackDrag() {
    _swipeCtrl.duration = const Duration(milliseconds: 220);
    final start = _drag;
    _swipeTween = Tween<Offset>(begin: start, end: Offset.zero).animate(
      CurvedAnimation(parent: _swipeCtrl, curve: Curves.easeOutCubic),
    );
    _swipeCtrl
      ..reset()
      ..addListener(_onSwipeTick)
      ..forward().whenComplete(() {
        if (!mounted) return;
        setState(() {
          _drag = Offset.zero;
          _swipeTween = null;
        });
        _swipeCtrl.removeListener(_onSwipeTick);
      });
  }

  void _onSwipeTick() {
    if (_swipeTween == null) return;
    setState(() => _drag = _swipeTween!.value);
  }

  @override
  Widget build(BuildContext context) {
    if (widget.tracks.isEmpty) return const SizedBox.shrink();

    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth;
        // GestureDetector は束全体で受ける (前面カードが逆再生中も位置を
        // 変えないので、個別カードにアタッチすると reversal で追従できないため)。
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onTapFront,
          onPanUpdate: _onPanUpdate,
          onPanEnd: (d) => _onPanEnd(d, w),
          child: AnimatedBuilder(
            animation: widget.modeCtrl,
            builder: (context, _) {
              final modeT = widget.modeCtrl.value.clamp(0.0, 1.0);
              final revP = _computeReverseProgress(w);
              final isReverse = revP > 0.001;
              final visibleCount =
                  math.min(_kMaxVisible, widget.tracks.length);

              final children = <Widget>[];

              // 背面 (深い) から前面 (浅い) の順に描画。
              // 逆再生 中は baseDepth -1 (画面外左から入場する前のトラック) も
              // 最後に描画して最前面に。
              for (int d = visibleCount - 1; d >= 0; d--) {
                children.add(_positionedCard(
                  baseDepth: d,
                  visualDepth: d + revP,
                  modeT: modeT,
                  isFront: d == 0 && !isReverse,
                  width: w,
                ));
              }
              if (isReverse) {
                children.add(_positionedCard(
                  baseDepth: -1,
                  visualDepth: -1 + revP,
                  modeT: modeT,
                  isFront: revP >= 0.5,
                  width: w,
                ));
              }

              return Stack(clipBehavior: Clip.none, children: children);
            },
          ),
        );
      },
    );
  }

  /// baseDepth 番目のカードを visualDepth (=baseDepth + 逆再生プログレス) の
  /// 位置で描画する。
  ///   - visualDepth < 0 : 進入カード。stateA[0] と画面外左の間を補間。
  ///   - 0 <= visualDepth <= 6 : stateA の depth ぶんを実数で補間。
  ///   - modeT > 0 (確定モード) の時は stateB[baseDepth] とも補間。
  ///     ※ 逆再生と確定モードは同時に発生しないので、この時 visualDepth は
  ///        baseDepth と等しい。
  Widget _positionedCard({
    required int baseDepth,
    required double visualDepth,
    required double modeT,
    required bool isFront,
    required double width,
  }) {
    final n = widget.tracks.length;
    final trackIdx = (_topIndex + baseDepth + n) % n;
    final track = widget.tracks[trackIdx];

    // stateA 側のパラメータを visualDepth の実数で計算
    final a = _stateAParamsAt(visualDepth, width);

    // stateB との補間 (確定モードのみ、baseDepth が有効な範囲のとき)
    double x = a.x, y = a.y, w = a.w, h = a.h;
    double rotDeg = a.rotDeg, opacity = a.opacity, blur = a.blur;
    if (modeT > 0.001 && baseDepth >= 0 && baseDepth < _kMaxVisible) {
      x = _lerp(a.x, _drawXB[baseDepth], modeT);
      y = _lerp(a.y, _drawYB[baseDepth], modeT);
      w = _lerp(a.w, _cardWB[baseDepth], modeT);
      h = _lerp(a.h, _cardHB[baseDepth], modeT);
      rotDeg = _lerp(a.rotDeg, _rotDegB[baseDepth], modeT);
      opacity = _lerp(a.opacity, _opacityB[baseDepth], modeT);
      blur = _lerp(a.blur, _blurB[baseDepth], modeT);
    }

    // 左ドラッグ (drag.dx < 0) は前面カードにのみ translation を加える。
    // 右ドラッグは visualDepth に既に反映されているのでここでは 0。
    // 確定モード遷移中も個別ドラッグは適用しない。
    double dragX = 0, dragY = 0, dragRot = 0;
    if (baseDepth == 0 && _drag.dx < 0 && modeT < 0.001) {
      dragX = _drag.dx;
      dragY = _drag.dy;
      dragRot = (_drag.dx / width) * 0.35;
    }

    Widget card = _cardBody(track: track, isFront: isFront);
    if (blur > 0.01) {
      card = ImageFiltered(
        imageFilter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
        child: card,
      );
    }
    if (opacity < 0.999) {
      card = Opacity(opacity: opacity, child: card);
    }
    card = Transform.rotate(
      angle: rotDeg * math.pi / 180 + dragRot,
      child: SizedBox(width: w, height: h, child: card),
    );
    // GestureDetector は束全体で受けるので個別カードには不要。
    // 背面カードでタッチが吸われないよう IgnorePointer で通り抜けさせる。
    card = IgnorePointer(child: card);

    return Positioned(
      left: x + dragX,
      top: y + dragY,
      width: w,
      height: h,
      child: card,
    );
  }

  /// visualDepth (実数) の stateA パラメータ。
  ///   visualDepth in [-1, 0]: 画面外左 → depth 0 の補間 (進入カード)。
  ///   visualDepth in [0, 6]:  隣接する 2 つの stateA[depth] を補間。
  ///   visualDepth > 6:        stateA[6] にクランプ (最深)。
  _CardParams _stateAParamsAt(double visualDepth, double width) {
    // depth 0 の stateA を予め計算
    final flexA0 = _flexA[0];
    final xA0 = flexA0[0] + (flexA0[2] - _cardWA[0]) / 2;
    final yA0 = flexA0[1] + (flexA0[3] - _cardHA[0]) / 2;

    if (visualDepth < 0) {
      // 進入カード: -1 → 0 の間で画面外左から中央へ
      final t = math.max(0.0, visualDepth + 1);
      return _CardParams(
        x: _lerp(-width - 200, xA0, t),
        y: yA0,
        w: _cardWA[0],
        h: _cardHA[0],
        rotDeg: _rotDegA[0],
        opacity: 1.0,
        blur: 0,
      );
    }

    const maxD = _kMaxVisible - 1;
    final clamped = visualDepth.clamp(0.0, maxD.toDouble());
    final floor = clamped.floor();
    final ceil = math.min(floor + 1, maxD);
    final frac = clamped - floor;

    final flexF = _flexA[floor];
    final flexC = _flexA[ceil];
    final xF = flexF[0] + (flexF[2] - _cardWA[floor]) / 2;
    final yF = flexF[1] + (flexF[3] - _cardHA[floor]) / 2;
    final xC = flexC[0] + (flexC[2] - _cardWA[ceil]) / 2;
    final yC = flexC[1] + (flexC[3] - _cardHA[ceil]) / 2;

    return _CardParams(
      x: _lerp(xF, xC, frac),
      y: _lerp(yF, yC, frac),
      w: _lerp(_cardWA[floor], _cardWA[ceil], frac),
      h: _lerp(_cardHA[floor], _cardHA[ceil], frac),
      rotDeg: _lerp(_rotDegA[floor], _rotDegA[ceil], frac),
      opacity: _lerp(_opacityA[floor], _opacityA[ceil], frac),
      blur: 0,
    );
  }

  /// カード内は既存の [PostCard] を「表面のみ」でレンダリング。
  /// - TrackModel から仮 PostModel を合成、いいね/コメント/共有等は無効化。
  /// - グラデーション色は [_DeckColorCache] から**同期取得**し preExtracted で渡す。
  ///   (deck 表示前に modal 側で色抽出が完了しているため、初回描画から色が乗る)
  /// - PostCard を **363×645 の native サイズ** で描画したものを [FittedBox] で
  ///   deck カード実サイズに均等スケール。楽曲情報のフォントも同じ倍率で自動縮小。
  /// - タップ・スワイプは束レベルの GestureDetector で受けるため、内部の
  ///   タップハンドラは [IgnorePointer] で吸わせて no-op に。
  Widget _cardBody({required TrackModel track, required bool isFront}) {
    // PostCard を native サイズ (投稿カード本来の座標系) で構築する。
    // FittedBox の親が deck カード実サイズ (variable) を持つので、
    // 中身は変わらず外側だけスケール。
    const nativeW = 363.0;
    const nativeH = 645.0;

    final colors = _DeckColorCache.get(track.trackId);
    final post = PostModel(
      postId: '__deck_preview_${track.trackId}__',
      userId: widget.currentUserId.isNotEmpty
          ? widget.currentUserId
          : '__preview__',
      username: widget.currentUsername.isNotEmpty
          ? widget.currentUsername
          : 'ユーザー',
      userIconUrl: widget.currentUserIconUrl,
      track: track,
      createdAt: _stableTs,
      updatedAt: _stableTs,
    );

    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(15),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isFront ? 0.24 : 0.10),
            blurRadius: isFront ? 30 : 70,
            offset: Offset(0, isFront ? 20 : 28),
          ),
          BoxShadow(
            color: Colors.black.withValues(alpha: isFront ? 0.14 : 0.18),
            blurRadius: isFront ? 80 : 22,
            offset: Offset(0, isFront ? 50 : 8),
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
                // ValueKey でトラック毎に独立した State を確保。
                // Flutter の reconciliation でカードの位置が変わっても
                // State が同じ key に紐付けて移動するため、色 (State に
                // キャッシュ) と track の対応が崩れない。
                key: ValueKey('deck-preview-${track.trackId}'),
                post: post,
                audioService: widget.audioService,
                showFrontOnly: true,
                hideReactionCounts: true,
                hideAudienceBadge: true,
                disableInteractions: true,
                backSideEnabled: false,
                currentUserId: widget.currentUserId,
                currentUserIconUrl: widget.currentUserIconUrl,
                preExtractedGradientStart: colors?.$1,
                preExtractedGradientEnd: colors?.$2,
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// 仮 PostModel の createdAt/updatedAt をフレーム間で安定にするための固定値。
  /// (build 毎に DateTime.now() を渡すと PostCard 側で "変わった" と判定されてしまう)
  static final DateTime _stableTs = DateTime(2026);

  double _lerp(double a, double b, double t) => a + (b - a) * t;
}

// ─────────────────────────────────────────────────────────────
// 下部ボタン: 状態でグレー text / 白ピル をクロスフェード
// ─────────────────────────────────────────────────────────────

class _BottomBar extends StatelessWidget {
  final AnimationController modeCtrl;
  final bool isConfirming;
  final VoidCallback onConfirm;

  const _BottomBar({
    required this.modeCtrl,
    required this.isConfirming,
    required this.onConfirm,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: modeCtrl,
      builder: (context, _) {
        final t = modeCtrl.value.clamp(0.0, 1.0);
        // browsing (t=0) 時にグレーテキスト、confirming (t=1) 時に白ピル。
        return SizedBox(
          height: 42,
          child: Stack(
            alignment: Alignment.center,
            children: [
              // グレーテキスト
              Opacity(
                opacity: (1 - t).clamp(0.0, 1.0),
                child: IgnorePointer(
                  ignoring: isConfirming,
                  child: const Text(
                    '←　スワイプして曲を変更　→',
                    style: TextStyle(
                      color: Color(0xFF8D8D8D),
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                      fontFamily: kSfProRounded,
                    ),
                  ),
                ),
              ),
              // 白ピル「この曲で続ける」
              Opacity(
                opacity: t,
                child: IgnorePointer(
                  ignoring: !isConfirming,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: isConfirming ? onConfirm : null,
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
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// カード 1 枚ぶんのビジュアルパラメータ (rotate 前の左上位置 x/y、サイズ w/h、
/// 回転 rotDeg°、不透明度 opacity、blur px)。
class _CardParams {
  final double x, y, w, h, rotDeg, opacity, blur;
  const _CardParams({
    required this.x,
    required this.y,
    required this.w,
    required this.h,
    required this.rotDeg,
    required this.opacity,
    required this.blur,
  });
}


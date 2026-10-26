import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../constants/profile_fonts.dart';
import '../models/post_model.dart';
import '../providers/current_user_provider.dart';
import '../services/audio_player_service.dart';
import '../services/instagram_stories_service.dart';
import '../services/weekly_recap_service.dart';
import '../widgets/common/app_toast.dart';
import '../widgets/post_card.dart';
import 'music_memory_detail_screen.dart';

/// Weekly Recap（Figma 6147:11641）。通知「Your Weekly Recap is here🎧」から開く。
///
/// 1 週間（日曜〜土曜）の各日の投稿カードを散らして並べる。どこかを押すと
/// カードが整列した配置（Figma 5996:11609）へ滑らかに移り、整列後にカードを
/// 押すと Music Memory と同じ詳細画面（日カルーセル）で開く。整列中に余白を
/// 押すと散らした配置に戻る。右上の共有では、画面とは別に組んだ 9:16 の
/// 共有画像（署名入り）を Instagram / X / その他へ送る。
///
/// レイアウトは Figma の 402×874 の座標をそのまま使い、画面幅に合わせて縮める。
class WeeklyRecapScreen extends StatefulWidget {
  /// 表示する週の日曜。null なら直近で終わった週。
  final DateTime? weekStart;

  const WeeklyRecapScreen({super.key, this.weekStart});

  @override
  State<WeeklyRecapScreen> createState() => _WeeklyRecapScreenState();
}

/// Figma のフレーム寸法。
const double _kCanvasW = 402;
const double _kCanvasH = 874;

/// 投稿カード（363×645）を縮めたときの寸法。
const double _kCardW = 125;
const double _kCardH = 222.107;

/// カード 1 枚の置き場所。中心座標と傾き（度）。
class _Slot {
  final double cx;
  final double cy;
  final double deg;
  const _Slot(this.cx, this.cy, this.deg);
}

/// 曜日（DateTime.weekday: 月=1 … 日=7）ごとの置き場所。Figma のレイヤー名が曜日。
const Map<int, _Slot> _kSlots = {
  1: _Slot(100.2, 344.2, -5.14), // 月
  2: _Slot(305.3, 470.2, 6.3), // 火
  3: _Slot(222.3, 309.7, 2.49), // 水
  4: _Slot(172.3, 517.2, 2), // 木
  5: _Slot(88.3, 536.2, -2), // 金
  6: _Slot(129.4, 676.5, -10.35), // 土
  7: _Slot(260.8, 613.4, 11.74), // 日
};

/// 整列した配置（Figma 5996:11609）。カードは 109.744×195 に縮む。
const Map<int, _Slot> _kArrangedSlots = {
  1: _Slot(85.9, 276.2, 3), // 月
  2: _Slot(318.1, 271.8, -2.5), // 火
  3: _Slot(198.2, 423.0, -0.5), // 水
  4: _Slot(83.2, 517.4, 2), // 木
  5: _Slot(318.2, 512.4, -2), // 金
  6: _Slot(88.1, 720.8, 2.5), // 土
  7: _Slot(315.4, 715.9, -1.5), // 日
};
const double _kArrangedScale = 109.744 / _kCardW;

/// 共有画像（Figma 6181:11291）の寸法。Instagram ストーリーズの 9:16。
const double _kShareH = 715;

/// 共有画像でのカードの置き場所。見出しと署名の間に収まるよう、
/// 散らした配置を少し縮めて上に寄せたもの。傾きは画面と同じ。
const Map<int, _Slot> _kShareSlots = {
  1: _Slot(116.0, 286.0, -5.14), // 月
  2: _Slot(301.0, 380.0, 6.3), // 火
  3: _Slot(218.5, 273.6, 2.49), // 水
  4: _Slot(195.0, 429.0, 2), // 木
  5: _Slot(96.0, 446.0, -2), // 金
  6: _Slot(146.7, 557.0, -10.35), // 土
  7: _Slot(266.5, 524.0, 11.74), // 日
};
const double _kShareScale = 0.775;

/// 重なり順（奥→手前）。Figma のレイヤー順。
const List<int> _kPaintOrder = [4, 1, 3, 2, 5, 7, 6];

class _WeeklyRecapScreenState extends State<WeeklyRecapScreen>
    with SingleTickerProviderStateMixin {
  final AudioPlayerService _audioService = AudioPlayerService();

  /// 0 = 散らした配置、1 = 整列した配置。
  late final AnimationController _arrange = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 720),
  );

  /// 共有画像（画面の裏に描いておき、共有時に切り出す）。
  final GlobalKey _shareKey = GlobalKey();
  WeeklyRecap? _recap;
  bool _isSharing = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _arrange.dispose();
    super.dispose();
  }

  bool get _isArranged => _arrange.status == AnimationStatus.completed;

  /// 余白のタップ。散らした配置⇄整列した配置を行き来する。
  void _toggleArrange() {
    if (_arrange.status == AnimationStatus.completed ||
        _arrange.status == AnimationStatus.forward) {
      _arrange.reverse();
    } else {
      _arrange.forward();
    }
  }

  /// カードのタップ。整列していれば詳細へ、まだなら整列させる。
  void _onCardTap(PostModel post) {
    if (_isArranged) {
      _openPost(post);
    } else {
      _arrange.forward();
    }
  }

  Future<void> _load() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    final recap =
        await WeeklyRecapService().load(uid, weekStart: widget.weekStart);
    if (!mounted) return;
    setState(() => _recap = recap);
  }

  void _openPost(PostModel post) {
    final recap = _recap;
    if (recap == null) return;
    // 詳細画面は新しい→古い順で受け取る。
    final posts = recap.posts.reversed.toList();
    final idx = posts.indexWhere((p) => p.postId == post.postId);
    MusicMemoryDetailScreen.push(
      context,
      posts: posts,
      initialIndex: idx < 0 ? 0 : idx,
      // 整列画面をぼかして、その上に重ねる。
      blurBehind: true,
    );
  }

  Future<void> _openShare() async {
    if (_isSharing) return;
    setState(() => _isSharing = true);
    try {
      final boundary = _shareKey.currentContext?.findRenderObject()
          as RenderRepaintBoundary?;
      if (boundary == null) return;
      final image = await boundary.toImage(pixelRatio: 3);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      final bytes = data?.buffer.asUint8List();
      if (!mounted) return;
      if (bytes == null) {
        AppToast.show(context, '画像の取得に失敗しました');
        return;
      }
      await showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (_) => _RecapShareSheet(imageBytes: bytes),
      );
    } finally {
      if (mounted) setState(() => _isSharing = false);
    }
  }

  /// Figma の座標系（402×874）を画面幅に合わせて縮めて置く。
  Widget _canvas(List<Widget> children) {
    return Positioned.fill(
      child: FittedBox(
        fit: BoxFit.contain,
        alignment: Alignment.topCenter,
        child: SizedBox(
          width: _kCanvasW,
          height: _kCanvasH,
          child: Stack(clipBehavior: Clip.hardEdge, children: children),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final recap = _recap;
    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      body: Stack(
        children: [
          // 共有画像。画面の下に敷いて隠しておく（描画はされるので切り出せる）。
          if (recap != null && recap.posts.isNotEmpty)
            Positioned(
              left: 0,
              top: 0,
              width: _kCanvasW,
              height: _kShareH,
              child: _shareComposition(recap),
            ),
          Positioned.fill(
            child: RepaintBoundary(
              child: Container(
                color: const Color(0xFF121212),
                child: Stack(
                  children: [
                    _canvas([
                      if (recap != null && recap.posts.isNotEmpty)
                        _background(recap.posts.last),
                      if (recap != null) _title(recap),
                      if (recap != null && recap.posts.isNotEmpty)
                        Positioned.fill(
                          child: GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: _toggleArrange,
                          ),
                        ),
                      if (recap != null)
                        for (final (i, weekday) in _kPaintOrder.indexed)
                          ..._cardFor(recap, weekday, i),
                      if (recap != null && recap.posts.isEmpty) _emptyMessage(),
                    ]),
                    if (recap == null)
                      const Center(
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
          _canvas([
            _glassButton(
              left: 22,
              icon: const Icon(Icons.arrow_back_ios_new,
                  color: Colors.white, size: 17),
              onTap: () => Navigator.of(context).maybePop(),
            ),
            if (recap != null && recap.posts.isNotEmpty)
              _glassButton(
                left: 328,
                // Figma: Share は (16,12) の 20×20。プロフィールの共有ボタンと同じ。
                icon: _isSharing
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(CupertinoIcons.share,
                        color: Colors.white, size: 19),
                onTap: _openShare,
              ),
          ]),
        ],
      ),
    );
  }

  /// 背景: 最新の投稿のジャケットを大きくぼかして薄く敷く。
  Widget _background(PostModel post) {
    return Positioned(
      left: -240,
      top: 0,
      width: 874,
      height: 874,
      child: ImageFiltered(
        imageFilter: ui.ImageFilter.blur(sigmaX: 21.6, sigmaY: 21.6),
        child: Opacity(
          opacity: 0.35,
          child: CachedNetworkImage(
            imageUrl: post.track.albumImageUrl,
            fit: BoxFit.cover,
            errorWidget: (_, __, ___) => const SizedBox.shrink(),
          ),
        ),
      ),
    );
  }

  Widget _title(WeeklyRecap recap) {
    final n = recap.posts.length;
    const heading = TextStyle(
      fontFamily: kSfProRounded,
      fontWeight: FontWeight.w800,
      fontSize: 36,
      letterSpacing: 0.36,
      color: Colors.white,
    );
    return Positioned(
      left: 0,
      right: 0,
      top: 52,
      child: Column(
        children: [
          const Text('Your week', style: heading, textAlign: TextAlign.center),
          if (n > 0)
            Text('in $n ${n == 1 ? 'Choice' : 'Choices'}',
                style: heading, textAlign: TextAlign.center),
          Text(
            recap.rangeLabel(),
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontFamily: kSfProRounded,
              fontWeight: FontWeight.w800,
              fontSize: 16,
              height: 2,
              letterSpacing: 0.36,
              color: Color(0xFFBBBBBB),
            ),
          ),
        ],
      ),
    );
  }

  Widget _emptyMessage() {
    return const Positioned(
      left: 0,
      right: 0,
      top: 400,
      child: Text(
        'この週の投稿はまだありません',
        textAlign: TextAlign.center,
        style: TextStyle(fontSize: 15, color: Color(0xFF99999B)),
      ),
    );
  }

  /// その曜日の投稿があれば、置き場所に傾けて置く。
  ///
  /// 散らした配置と整列した配置の間を [_arrange] で補間する。[order] ぶん
  /// 少しずつ遅らせて動かし、全部が一斉に動くより柔らかく見せる。
  List<Widget> _cardFor(WeeklyRecap recap, int weekday, int order) {
    final post =
        recap.posts.where((p) => p.createdAt.weekday == weekday).firstOrNull;
    if (post == null) return const [];
    final from = _kSlots[weekday]!;
    final to = _kArrangedSlots[weekday]!;
    final start = order * 0.05;
    final t = CurvedAnimation(
      parent: _arrange,
      curve: Interval(start, start + 0.7, curve: Curves.easeInOutCubic),
    );
    return [
      AnimatedBuilder(
        animation: t,
        builder: (context, child) {
          final v = t.value;
          final cx = ui.lerpDouble(from.cx, to.cx, v)!;
          final cy = ui.lerpDouble(from.cy, to.cy, v)!;
          final deg = ui.lerpDouble(from.deg, to.deg, v)!;
          final scale = ui.lerpDouble(1, _kArrangedScale, v)!;
          return Positioned(
            left: cx - _kCardW / 2,
            top: cy - _kCardH / 2,
            width: _kCardW,
            height: _kCardH,
            child: Transform.rotate(
              angle: deg * math.pi / 180,
              child: Transform.scale(scale: scale, child: child),
            ),
          );
        },
        child: GestureDetector(
          onTap: () => _onCardTap(post),
          child: _cardVisual(post, 'recap'),
        ),
      ),
    ];
  }

  /// 共有画像（Figma 6181:11291）。見出し・カード・署名（@ユーザー名 と 15s）。
  Widget _shareComposition(WeeklyRecap recap) {
    final username = context.read<CurrentUserProvider>().username;
    const footer = TextStyle(
      fontFamily: kSfProRounded,
      fontWeight: FontWeight.w800,
      color: Color(0xFFA8A8A8),
    );
    return RepaintBoundary(
      key: _shareKey,
      child: Container(
        color: const Color(0xFF121212),
        child: Stack(
          clipBehavior: Clip.hardEdge,
          children: [
            _background(recap.posts.last),
            _title(recap),
            for (final weekday in _kPaintOrder)
              if (recap.posts
                      .where((p) => p.createdAt.weekday == weekday)
                      .firstOrNull
                  case final post?)
                Positioned(
                  left: _kShareSlots[weekday]!.cx - _kCardW / 2,
                  top: _kShareSlots[weekday]!.cy - _kCardH / 2,
                  width: _kCardW,
                  height: _kCardH,
                  child: Transform.rotate(
                    angle: _kShareSlots[weekday]!.deg * math.pi / 180,
                    child: Transform.scale(
                      scale: _kShareScale,
                      child: _cardVisual(post, 'share'),
                    ),
                  ),
                ),
            Positioned(
              left: 0,
              right: 0,
              top: 648,
              child: Column(
                children: [
                  if (username.isNotEmpty)
                    Text('@$username',
                        style: footer.copyWith(fontSize: 20, height: 1.2)),
                  Text('15s',
                      style: footer.copyWith(
                          fontSize: 28,
                          fontWeight: FontWeight.w900,
                          height: 1.1)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 投稿カードを 125×222 に縮めて、枠と影を付けたもの。
  Widget _cardVisual(PostModel post, String keyPrefix) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: const Color(0x1AFFFFFF)),
        boxShadow: const [
          BoxShadow(
              color: Color(0x47000000), offset: Offset(0, 2), blurRadius: 6),
          BoxShadow(
            color: Color(0x6B000000),
            offset: Offset(0, 8),
            blurRadius: 24,
            spreadRadius: -2,
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: IgnorePointer(
          child: FittedBox(
            fit: BoxFit.fill,
            child: SizedBox(
              width: 363,
              height: 645,
              child: PostCard(
                key: ValueKey('$keyPrefix-${post.postId}'),
                post: post,
                currentUserId: uid,
                audioService: _audioService,
                showFrontOnly: true,
                backSideEnabled: false,
                hideCommentBar: true,
                hideShareButton: true,
                hideAudienceBadge: true,
                disableInteractions: true,
                audioManagedExternally: true,
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// プロフィールと同じガラスの丸ボタン（52×45）。
  Widget _glassButton({
    required double left,
    required Widget icon,
    required VoidCallback onTap,
  }) {
    return Positioned(
      left: left,
      top: 54,
      width: 52,
      height: 45,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Stack(
          children: [
            Image.asset(
              'assets/profile_v2/glass_button.png',
              width: 52,
              height: 45,
              fit: BoxFit.fill,
            ),
            Positioned(
              left: 16,
              top: 12,
              width: 20,
              height: 20,
              child: Center(child: icon),
            ),
          ],
        ),
      ),
    );
  }
}

/// 共有シート（Figma 6181:11370）。上に共有する画像、下に共有先。
class _RecapShareSheet extends StatefulWidget {
  final Uint8List imageBytes;

  const _RecapShareSheet({required this.imageBytes});

  @override
  State<_RecapShareSheet> createState() => _RecapShareSheetState();
}

class _RecapShareSheetState extends State<_RecapShareSheet> {
  bool _busy = false;

  static const _shareText = 'My Weekly Recap on 15s 🎧';

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _shareToInstagram() => _run(() async {
        final ok = await InstagramStoriesService.share(widget.imageBytes);
        if (!ok && mounted) AppToast.show(context, 'Instagramが見つかりません');
      });

  /// X は外からアプリへ画像を直接渡す手段が無いので、OS の共有シートで渡す。
  /// その他も同じシート。iPad では表示位置の指定が必須なので、シートの矩形を渡す。
  Future<void> _shareWithSystemSheet() => _run(() async {
        try {
          final box = context.findRenderObject() as RenderBox?;
          await Share.shareXFiles(
            [
              XFile.fromData(
                widget.imageBytes,
                mimeType: 'image/png',
                name: 'weekly_recap.png',
              ),
            ],
            text: _shareText,
            sharePositionOrigin:
                box == null ? null : box.localToGlobal(Offset.zero) & box.size,
          );
        } catch (_) {
          if (mounted) AppToast.show(context, '共有に失敗しました');
        }
      });

  @override
  Widget build(BuildContext context) {
    final bottomPadding = MediaQuery.of(context).padding.bottom;
    return Container(
      height: MediaQuery.of(context).size.height * 803 / _kCanvasH,
      decoration: const BoxDecoration(
        color: Color(0xFF1A1A1A),
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(38),
          topRight: Radius.circular(38),
        ),
      ),
      child: Column(
        children: [
          const SizedBox(height: 46),
          Expanded(
            child: Center(
              child: AspectRatio(
                aspectRatio: 319 / 567,
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0xF5000000),
                        offset: Offset(0, 4),
                        blurRadius: 26.7,
                      ),
                      BoxShadow(
                        color: Color(0xBA000000),
                        offset: Offset(0, 16),
                        blurRadius: 40,
                        spreadRadius: -1,
                      ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: Image.memory(widget.imageBytes, fit: BoxFit.cover),
                  ),
                ),
              ),
            ),
          ),
          Padding(
            padding: EdgeInsets.only(top: 59, bottom: bottomPadding + 24),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _target(
                  label: 'Instagram',
                  icon: SvgPicture.asset(
                    'assets/weekly_recap/share_instagram.svg',
                    width: 58,
                    height: 58,
                  ),
                  onTap: _shareToInstagram,
                ),
                const SizedBox(width: 42),
                _target(
                  label: 'X',
                  icon: Container(
                    width: 58,
                    height: 58,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border:
                          Border.all(color: const Color(0xFF080808), width: 2),
                    ),
                    padding: const EdgeInsets.all(2),
                    child: Stack(
                      children: [
                        SvgPicture.asset(
                          'assets/weekly_recap/share_x_circle.svg',
                          width: 50,
                          height: 50,
                        ),
                        Positioned(
                          left: 5,
                          top: 5,
                          width: 40,
                          height: 40,
                          child: ClipOval(
                            child: Image.asset(
                              'assets/weekly_recap/x_logo.jpg',
                              fit: BoxFit.cover,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  onTap: _shareWithSystemSheet,
                ),
                const SizedBox(width: 42),
                _target(
                  label: 'その他',
                  labelSize: 13,
                  icon: Container(
                    width: 58,
                    height: 58,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border:
                          Border.all(color: const Color(0xFF3E3E3D), width: 2),
                    ),
                    padding: const EdgeInsets.all(2),
                    child: SvgPicture.asset(
                      'assets/weekly_recap/share_other.svg',
                      width: 50,
                      height: 50,
                    ),
                  ),
                  onTap: _shareWithSystemSheet,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _target({
    required String label,
    required Widget icon,
    required VoidCallback onTap,
    double labelSize = 15,
  }) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _busy ? null : onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          icon,
          const SizedBox(height: 6),
          Text(
            label,
            style: TextStyle(
              fontFamily: kSfProRounded,
              fontWeight: FontWeight.w600,
              fontSize: labelSize,
              color: const Color(0xFFE9E9E9),
            ),
          ),
        ],
      ),
    );
  }
}

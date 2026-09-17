import 'dart:math' as math;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../constants/profile_fonts.dart';
import '../widgets/profile_widgets.dart';

/// 友達が成立したときのお祝い画面（Figma 5749-11468）。
///
/// 2 つのアイコンが画面の両端から近づいてきて中央で重なり、そのまわりを
/// 音符とハートが漂う。最初の数人だけに出す想定で、出す / 出さないの判断は
/// [FriendMatchService] が持つ。この画面は渡された内容を描くだけ。
///
/// ## 座標について
/// Figma の 402×874（iPhone 16/17 Pro）をそのまま数値で持ち、
/// [FittedBox] で実機の画面に合わせて拡大縮小する。こうするとどの端末でも
/// デザイン通りの比率になり、個々の Positioned を端末幅で割る必要がない。
class FriendMatchScreen extends StatefulWidget {
  /// 左側（自分）のアイコン画像。
  final String? meImageUrl;

  /// 左側に出す表示名。
  final String meName;

  /// 右側（友達になった相手）のアイコン画像。
  final String? friendImageUrl;

  /// 右側に出す表示名。
  final String friendName;

  /// 何人目の友達か。下部のピルに「N人目の15s Friends」として出す。
  final int ordinal;

  const FriendMatchScreen({
    super.key,
    required this.meImageUrl,
    required this.meName,
    required this.friendImageUrl,
    required this.friendName,
    required this.ordinal,
  });

  /// お祝い画面をフルスクリーンで表示し、閉じられるまで待つ。
  ///
  /// アイコンは開く前に読み込んでおく。間に合わないと、灰色の丸が飛んできて
  /// 途中で写真に差し替わることになるため。
  static Future<void> show(
    BuildContext context, {
    required String? meImageUrl,
    required String meName,
    required String? friendImageUrl,
    required String friendName,
    required int ordinal,
  }) async {
    await _precacheAvatars(context, [meImageUrl, friendImageUrl]);
    if (!context.mounted) return;

    return Navigator.of(context, rootNavigator: true).push<void>(
      PageRouteBuilder<void>(
        opaque: false,
        barrierColor: _bg,
        transitionDuration: const Duration(milliseconds: 320),
        reverseTransitionDuration: const Duration(milliseconds: 260),
        pageBuilder: (_, __, ___) => FriendMatchScreen(
          meImageUrl: meImageUrl,
          meName: meName,
          friendImageUrl: friendImageUrl,
          friendName: friendName,
          ordinal: ordinal,
        ),
        transitionsBuilder: (_, animation, __, child) =>
            FadeTransition(opacity: animation, child: child),
      ),
    );
  }

  /// アイコン画像をキャッシュに載せてから戻る。
  ///
  /// 読めない画像や遅い回線で待たされ続けないよう、失敗は無視して上限も切る。
  /// 間に合わなければ [ProfileImage] のプレースホルダに落ちるだけで害はない。
  static Future<void> _precacheAvatars(
    BuildContext context,
    List<String?> urls,
  ) async {
    final futures = <Future<void>>[];
    for (final url in urls) {
      if (url == null || url.isEmpty) continue;
      final ImageProvider provider = url.startsWith('assets/')
          ? AssetImage(url)
          : CachedNetworkImageProvider(url);
      futures.add(precacheImage(provider, context).catchError((Object _) {}));
    }
    if (futures.isEmpty) return;
    await Future.wait(futures).timeout(
      const Duration(seconds: 3),
      onTimeout: () => const <void>[],
    );
  }

  @override
  State<FriendMatchScreen> createState() => _FriendMatchScreenState();
}

// ── デザイン定数（Figma 5749-11468 の実数値）─────────────────────

const Color _bg = Color(0xFF121212);

/// アクセント（&）と相手側グローの緑。
const Color _accent = Color(0xFFB7FF4A);
const Color _glowGreen = Color(0xFFD5FB4B);

const double _designW = 402;
const double _designH = 874;

/// アイコンの直径と中心。Figma の外枠（174 角）ではなく画像本体の値。
const double _avatarSize = 142;
const Offset _meCenter = Offset(130.2, 447.4);
const Offset _friendCenter = Offset(261.9, 485.3);

/// 最終的な傾き。左は反時計回り、右は時計回り。
const double _meTiltDeg = -15.76;
const double _friendTiltDeg = 14.81;

/// アイコンの背後に敷くグローの直径（Figma: 167 + はみ出し 35.93% × 2）。
const double _glowSize = 287;

class _FriendMatchScreenState extends State<FriendMatchScreen>
    with TickerProviderStateMixin {
  /// 登場アニメーション。1 回だけ再生する。
  late final AnimationController _intro;

  /// 音符とハートの漂い。登場後もずっと往復させる。
  late final AnimationController _float;

  /// アイコンが出会った瞬間の触覚を 1 度だけ出すためのフラグ。
  bool _didImpact = false;

  /// 登場が終わるまではタップで閉じられないようにする。
  bool _canDismiss = false;

  @override
  void initState() {
    super.initState();
    _intro = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2400),
    )..addListener(_onIntroTick);
    _float = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3200),
    )..repeat(reverse: true);
    _intro.forward();
  }

  void _onIntroTick() {
    // アイコンが中央で重なるのが 0.46。そこに合わせて「くっついた」触覚を出す。
    if (!_didImpact && _intro.value >= 0.44) {
      _didImpact = true;
      HapticFeedback.mediumImpact();
    }
    if (!_canDismiss && _intro.value >= 0.92) {
      _canDismiss = true;
    }
  }

  @override
  void dispose() {
    _intro
      ..removeListener(_onIntroTick)
      ..dispose();
    _float.dispose();
    super.dispose();
  }

  void _dismiss() {
    if (!_canDismiss) return;
    Navigator.of(context).maybePop();
  }

  /// [begin]〜[end]（0〜1 の進行度）だけを切り出した 0〜1 の値。
  double _phase(double begin, double end, {Curve curve = Curves.easeOutCubic}) {
    final t = ((_intro.value - begin) / (end - begin)).clamp(0.0, 1.0);
    return curve.transform(t);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      body: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _dismiss,
        child: Center(
          child: FittedBox(
            fit: BoxFit.contain,
            child: SizedBox(
              width: _designW,
              height: _designH,
              child: AnimatedBuilder(
                animation: Listenable.merge([_intro, _float]),
                // 飛んでくるアイコンがデザイン枠の外にはみ出して見えないよう、
                // ここで切る（端末によっては枠の外側にも余白が出るため）。
                builder: (_, __) => Stack(
                  clipBehavior: Clip.hardEdge,
                  children: [
                    ..._decorations(),
                    _glow(_meCenter, Colors.white, 0.40),
                    _glow(_friendCenter, _glowGreen, 0.243),
                    // 重なりは Figma と同じく左（自分）が手前。
                    _avatar(isMe: false),
                    _avatar(isMe: true),
                    _title(),
                    _subtitle(),
                    _names(),
                    _pill(),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ── アイコンとグロー ─────────────────────────────────────

  /// アイコンの現在位置。両端の画面外から最終位置へ寄ってくる。
  ///
  /// 「近づいてくる」ことが見えてほしいので、位置は加速して減速する
  /// easeInOutCubic で動かす。easeOut 系だと最初の 0.2 秒でほぼ着いてしまい、
  /// 残りが止まって見える。
  ///
  /// 傾きは位置より少し遅れて決まり、触れた瞬間にわずかに弾む。
  Widget _avatar({required bool isMe}) {
    final center = isMe ? _meCenter : _friendCenter;
    final slide = _phase(0.02, 0.46, curve: Curves.easeInOutCubic);
    final tilt = _phase(0.06, 0.58);
    // 重なった瞬間の小さな跳ね返り。1 を中心に減衰しながら揺れる。
    final settle =
        1 + 0.05 * (1 - _phase(0.44, 0.78, curve: Curves.elasticOut));

    // 画面外（アイコンが完全に隠れる位置）からのオフセット。
    final fromX = isMe
        ? -(center.dx + _avatarSize)
        : (_designW - center.dx + _avatarSize);
    final dx = fromX * (1 - slide);

    // 飛んでくる間は大きく傾けておき、着地で最終角度に収める。
    final startDeg = isMe ? -40.0 : 38.0;
    final endDeg = isMe ? _meTiltDeg : _friendTiltDeg;
    final deg = startDeg + (endDeg - startDeg) * tilt;

    return Positioned(
      left: center.dx - _avatarSize / 2 + dx,
      top: center.dy - _avatarSize / 2,
      child: Transform.scale(
        scale: settle,
        child: Transform.rotate(
          angle: deg * math.pi / 180,
          child: ClipOval(
            child: SizedBox(
              width: _avatarSize,
              height: _avatarSize,
              child: ColoredBox(
                color: const Color(0xFF3A3A3A),
                child: ProfileImage(
                  imageUrl: isMe ? widget.meImageUrl : widget.friendImageUrl,
                  size: _avatarSize,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// アイコン背後のやわらかい光。
  ///
  /// 素材（ロゴ背景色自分 / 他人）は中心から外へなめらかに薄くなるだけの
  /// 円形グラデーションなので、同じ減衰を [RadialGradient] で再現している。
  /// 画像のままだと 1.6MB あり、拡大時に粗も出る。
  Widget _glow(Offset center, Color color, double peakAlpha) {
    // 素材の中心からの不透明度を 10% 刻みで実測した値（最大を 1 とした比率）。
    const falloff = <double>[
      1.0,
      1.0,
      0.96,
      0.91,
      0.79,
      0.62,
      0.42,
      0.23,
      0.09,
      0.02,
      0.0,
    ];
    final appear = _phase(0.30, 0.62, curve: Curves.easeOut);

    return Positioned(
      left: center.dx - _glowSize / 2,
      top: center.dy - _glowSize / 2,
      child: IgnorePointer(
        child: Opacity(
          opacity: appear,
          child: Container(
            width: _glowSize,
            height: _glowSize,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                stops: [for (var i = 0; i < falloff.length; i++) i / 10],
                colors: [
                  for (final f in falloff)
                    color.withValues(alpha: peakAlpha * f),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ── テキスト ───────────────────────────────────────────

  Widget _title() {
    final t = _phase(0.34, 0.60);
    return Positioned(
      top: 226,
      left: 0,
      right: 0,
      child: Opacity(
        opacity: t,
        child: Transform.scale(
          scale: 0.88 + 0.12 * t,
          child: const Text(
            'you’re\nconnected',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white,
              fontSize: 57.6,
              height: 0.86,
              letterSpacing: -1.5,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
      ),
    );
  }

  Widget _subtitle() {
    final t = _phase(0.46, 0.70);
    return Positioned(
      top: 337,
      left: 0,
      right: 0,
      child: Opacity(
        opacity: t,
        child: Transform.translate(
          offset: Offset(0, 12 * (1 - t)),
          child: const Text(
            '今日の1曲を、一緒に。',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white,
              fontSize: 24,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }

  /// 「name & name」。名前は長くても崩れないよう幅を抑えて省略する。
  Widget _names() {
    final t = _phase(0.58, 0.80);
    // & だけ弾ませる。跳ねるぶん終わりを遅らせている。
    final amp = _phase(0.60, 0.94, curve: Curves.elasticOut);

    return Positioned(
      top: 601,
      left: 0,
      right: 0,
      height: 48,
      child: Opacity(
        opacity: t,
        child: Transform.translate(
          offset: Offset(0, 10 * (1 - t)),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _name(widget.meName),
              const SizedBox(width: 18),
              Transform.translate(
                offset: const Offset(0, -6),
                child: Transform.scale(
                  scale: amp,
                  child: Image.asset(
                    'assets/friend_match/ampersand.png',
                    height: 40,
                    color: _accent,
                  ),
                ),
              ),
              const SizedBox(width: 18),
              _name(widget.friendName),
            ],
          ),
        ),
      ),
    );
  }

  Widget _name(String text) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 118),
      child: Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        textAlign: TextAlign.center,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 18,
          fontWeight: FontWeight.w500,
          fontFamily: kSfProRounded,
        ),
      ),
    );
  }

  Widget _pill() {
    final t = _phase(0.72, 0.92);
    return Positioned(
      top: 663,
      left: 0,
      right: 0,
      child: Opacity(
        opacity: t,
        child: Transform.translate(
          offset: Offset(0, 8 * (1 - t)),
          child: Center(
            child: Container(
              height: 31,
              padding: const EdgeInsets.symmetric(horizontal: 18),
              decoration: BoxDecoration(
                border: Border.all(color: const Color(0xFFBDBDBD)),
                borderRadius: BorderRadius.circular(34),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Image.asset(
                    'assets/friend_match/friends.png',
                    height: 12,
                  ),
                  const SizedBox(width: 9),
                  Text(
                    '${widget.ordinal}人目の15s Friends',
                    style: const TextStyle(
                      color: Color(0xFFBDBDBD),
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ── 装飾（音符とハート）─────────────────────────────────

  /// Figma に置かれている 6 個。位置とサイズはデザインの実測値。
  static const _decorSpecs = <_Decor>[
    _Decor('music_note.png', Offset(65, 172), 22, 0.10),
    _Decor('music_double.png', Offset(98, 213), 34, 0.18),
    _Decor('heart.png', Offset(320, 228), 48, 0.26),
    _Decor('music_note.png', Offset(148, 578), 26, 0.34),
    _Decor('heart.png', Offset(70, 627), 30, 0.42),
    _Decor('heart.png', Offset(325, 640), 48, 0.50),
  ];

  List<Widget> _decorations() {
    return [
      for (var i = 0; i < _decorSpecs.length; i++)
        _decoration(_decorSpecs[i], i),
    ];
  }

  /// ふわふわと上下しながら少し傾く。個体ごとに位相をずらして、
  /// 全部が同時に動いて見えないようにしている。
  Widget _decoration(_Decor d, int index) {
    final appear = _phase(d.delay, d.delay + 0.26);

    // 位相をずらした 0〜1 の往復。
    final phase = (_float.value + index / _decorSpecs.length) % 1.0;
    final wave = math.sin(phase * 2 * math.pi);

    final isHeart = d.asset == 'heart.png';
    final dy = wave * 6;
    final rotate = wave * (isHeart ? 0.05 : 0.10);
    // ハートだけ、鼓動のようにわずかに伸び縮みさせる。
    final scale = isHeart ? 1 + wave.abs() * 0.07 : 1.0;

    return Positioned(
      left: d.center.dx - d.size / 2,
      top: d.center.dy - d.size / 2 + dy,
      child: IgnorePointer(
        child: Opacity(
          opacity: appear,
          child: Transform.rotate(
            angle: rotate,
            child: Transform.scale(
              scale: scale * (0.7 + 0.3 * appear),
              child: Image.asset(
                'assets/friend_match/${d.asset}',
                width: d.size,
                height: d.size,
                fit: BoxFit.contain,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 装飾 1 個分の配置。
class _Decor {
  final String asset;
  final Offset center;
  final double size;

  /// 登場アニメーション全体（0〜1）のどこで出てくるか。
  final double delay;

  const _Decor(this.asset, this.center, this.size, this.delay);
}

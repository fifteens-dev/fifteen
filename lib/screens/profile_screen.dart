import 'dart:async';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import 'package:flutter_svg/flutter_svg.dart';

import '../constants/profile_fonts.dart';
import '../models/post_model.dart';
import '../models/user_model.dart';
import '../services/friend_service.dart';
import '../services/milfolha_service.dart';
import '../services/laneige_service.dart';
import '../services/music_memory_cycle_service.dart';
import '../services/post_service.dart';
import '../services/profile_snapshot_service.dart';
import '../services/user_service.dart';
import '../utils/album_image.dart';
import '../widgets/common/glass_circle_button.dart';
import '../widgets/common/liquid_glass.dart';
import '../widgets/profile_widgets.dart';
import 'invite_share_sheet.dart';
import 'profile_share_screen.dart';
import 'milfolha_ranking_screen.dart';
import 'laneige_ranking_screen.dart';
import 'settings_screen.dart';

/// プロフィール画面（自分）— Figma 5761:12112。
///
/// ## 座標について
/// Figma の 402×874（iPhone 16/17 Pro）をそのまま数値で持ち、画面幅に対する
/// 倍率をかけて描く。要素が全て絶対座標で置かれた「ポスター」型のデザインなので、
/// 個々の値を端末幅で割るより崩れにくい。縦に入り切らない端末ではスクロールする。
class ProfileScreen extends StatefulWidget {
  /// 渡すとホームの上に重ねるガラスのカード（Figma 6672:12190）で描き、
  /// 左上のバツで呼ぶ。null なら今までの全画面のプロフィール。
  final VoidCallback? onClose;

  const ProfileScreen({super.key, this.onClose});

  /// ホーム右上のプロフィールボタンから、ホームの上にカードで開く。
  static Future<void> showCard(BuildContext context) {
    return Navigator.of(context).push(PageRouteBuilder<void>(
      opaque: false,
      barrierColor: Colors.transparent,
      transitionDuration: const Duration(milliseconds: 260),
      reverseTransitionDuration: const Duration(milliseconds: 200),
      pageBuilder: (context, _, __) =>
          ProfileScreen(onClose: () => Navigator.of(context).pop()),
      transitionsBuilder: (_, animation, __, child) {
        final curved =
            CurvedAnimation(parent: animation, curve: Curves.easeOutCubic);
        return FadeTransition(
          opacity: curved,
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.94, end: 1).animate(curved),
            child: child,
          ),
        );
      },
    ));
  }

  @override
  State<ProfileScreen> createState() => ProfileScreenState();
}

// ── デザイン定数（Figma 5761:12112 の実数値）─────────────────────

const Color _bg = Color(0xFF121212);
const Color _pillBg = Color(0xFF262626);
const Color _statsBg = Color(0xFF09090A);
const Color _statsBorder = Color(0xFF272627);
const Color _statsText = Color(0xFF5C5656);
const Color _handleColor = Color(0xFFA3A3A3);
const Color _trackArtistColor = Color(0xFF898989);

/// 集計に使う投稿の件数。top artists は直近 7 日ぶんしか見ないので、
/// 60 件も取ると回線が細いときに無駄が大きい。
const int _postsForAggregation = 30;

const double _designW = 402;
const double _designH = 874;

/// ホームに重ねるカード（Figma 6672:12122）。画面 402×874 の (9,117) に置く。
const double _cardW = 384;
const double _cardH = 703;
const Offset _cardOrigin = Offset(9, 117);

/// カードでは top artists / recent choice を全画面の座標からこれだけずらす
/// （横は 402→384 の中央合わせ、縦はヘッダーを詰めたぶん）。
const Offset _cardSectionShift = Offset(-(_designW - _cardW) / 2, -160);

/// 3 つ並ぶタイルの寸法。left は Figma の並び（0 / 116 / 232）。
const double _tile = 105;
const List<double> _tileLefts = [0, 116, 232];

/// top artists / recent choice セクションの左上。
const Offset _artistsOrigin = Offset(36, 418);
const Offset _recentOrigin = Offset(37, 641);

/// タイルに共通の落ち影。1 位だけこれに黄緑の光を足す。
const List<BoxShadow> _tileShadow = [
  BoxShadow(color: Color(0x2E000000), offset: Offset(0, 4), blurRadius: 12),
  BoxShadow(color: Color(0x47000000), offset: Offset(0, 14), blurRadius: 32),
];

class ProfileScreenState extends State<ProfileScreen> {
  final UserService _userService = UserService();
  final PostService _postService = PostService();
  final FriendService _friendService = FriendService();
  final MilfolhaService _milfolhaService = MilfolhaService();
  final LaneigeService _laneigeService = LaneigeService();

  UserModel? _user;
  bool _loading = true;

  /// カードのネイティブのガラスを出してよいか。開くアニメの最中に作ると
  /// 一瞬画面が真っ黒になることがあるので、アニメが終わってから出し、
  /// 閉じ始めたら引っ込める。
  bool _glassReady = false;
  Animation<double>? _routeAnimation;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (widget.onClose == null) return;
    final anim = ModalRoute.of(context)?.animation;
    if (anim == _routeAnimation) return;
    _routeAnimation?.removeStatusListener(_onRouteStatus);
    _routeAnimation = anim?..addStatusListener(_onRouteStatus);
    _onRouteStatus(anim?.status ?? AnimationStatus.completed);
  }

  void _onRouteStatus(AnimationStatus status) {
    final ready = status == AnimationStatus.completed;
    if (ready != _glassReady && mounted) setState(() => _glassReady = ready);
  }

  @override
  void dispose() {
    _routeAnimation?.removeStatusListener(_onRouteStatus);
    super.dispose();
  }

  /// 集計のもとになる自分の投稿（新しい順）。
  List<PostModel> _posts = const [];
  int _postCount = 0;

  /// 友達の人数と、ピルに出すアイコン（先頭 2 人）。
  int _friendCount = 0;
  List<String?> _friendIcons = const [];

  /// 連続投稿日数（15s Day 基準）。
  int _streakDays = 0;

  /// top artists（多い順に最大 3 名）。集計元は連携中のサービスで変わる。
  List<String> _topArtistNames = const [];

  /// WATERFALLS 参加中のときだけランキング導線を出す。
  bool _showMilfolhaRanking = false;

  /// LANEIGE 参加中のときだけランキング導線を出す。WATERFALLS と同じ
  /// ボタンを使い、両方に参加していれば LANEIGE（新しい方）を開く。
  bool _showLaneigeRanking = false;

  String? get _uid => FirebaseAuth.instance.currentUser?.uid;

  @override
  void initState() {
    super.initState();
    _load();
  }

  /// 画面を出すまでに待つのは名前とアイコンだけ。
  ///
  /// 以前は友達・投稿・top artists まで全部揃うまでローディングだった。
  /// どれも別々のクエリで、回線が細いと待ち時間が足し算になる。
  /// 枠はすぐ出して、取れたものから順に埋める。
  Future<void> _load() async {
    final uid = _uid;
    if (uid == null) {
      if (mounted) setState(() => _loading = false);
      return;
    }

    await _loadUser(uid);
    if (mounted) setState(() => _loading = false);

    // 残りは背景で。互いに独立なので同時に走らせる。
    unawaited(_loadPosts(uid));
    unawaited(_loadFriends(uid));
    unawaited(_loadMilfolhaEntry(uid));
    unawaited(_loadLaneigeEntry(uid));
  }

  Future<void> _refresh() async {
    final uid = _uid;
    if (uid == null) return;
    // 友達一覧は自分の following / followers から作るので、先に自分を取り直す。
    // 並列にすると古い関係のまま描いてしまう。
    // top artists は _loadPosts が投稿を取ったあとに自分で走らせる。
    await Future.wait([_loadUser(uid), _loadPosts(uid)]);
    await _loadFriends(uid);
  }

  Future<void> _loadUser(String uid) async {
    try {
      final user = await _userService.getUser(uid);
      if (mounted) setState(() => _user = user);
    } catch (_) {/* 表示は既存値のまま */}
  }

  /// top artists / recent choice / 連続日数の材料をまとめて取る。
  /// 1 回のページングで足りる範囲（直近 60 件）だけを見る。
  Future<void> _loadPosts(String uid) async {
    try {
      // 投稿一覧と件数は独立なので同時に取る。
      final (result, count) = await (
        _postService.getPostsByUserIdPaged(uid, limit: _postsForAggregation),
        _postService.getPostCountByUserId(uid),
      ).wait;
      if (!mounted) return;
      setState(() {
        _posts = result.posts;
        _postCount = count;
      });

      // 連続日数と top artists は投稿が要るのでここから。どちらも待たない。
      unawaited(_calcStreak(result.posts).then((streak) {
        if (mounted) setState(() => _streakDays = streak);
      }));
      unawaited(_loadTopArtists());
    } catch (_) {/* 表示は既存値のまま */}
  }

  Future<void> _loadFriends(String uid) async {
    try {
      // 既に取得済みの自分の情報を渡して、同じ読み取りを 2 回走らせない。
      final friends = await _friendService.loadFriends(uid, me: _user);
      if (!mounted) return;
      setState(() {
        _friendCount = friends.length;
        _friendIcons = [
          for (final f in friends.take(2)) f.user.profileImageUrl,
        ];
      });
    } catch (_) {/* 表示は既存値のまま */}
  }

  Future<void> _loadMilfolhaEntry(String uid) async {
    try {
      final active = await _milfolhaService.isActive();
      final membership =
          active ? await _milfolhaService.getMembership(uid) : null;
      final show = active && membership?['teamId'] != null;
      if (mounted && show != _showMilfolhaRanking) {
        setState(() => _showMilfolhaRanking = show);
      }
    } catch (_) {/* 導線を出さないだけ */}
  }

  Future<void> _loadLaneigeEntry(String uid) async {
    try {
      final active = await _laneigeService.isActive();
      final membership =
          active ? await _laneigeService.getMembership(uid) : null;
      final show = active && membership?['teamId'] != null;
      if (mounted && show != _showLaneigeRanking) {
        setState(() => _showLaneigeRanking = show);
      }
    } catch (_) {/* 導線を出さないだけ */}
  }

  /// 招待カードの共有シートを開く（Figma 5779-12975）。
  Future<void> _openShareSheet() async {
    final uid = _uid;
    final user = _user;
    final handle = user?.username;
    if (uid == null || handle == null || handle.isEmpty) return;
    await InviteShareSheet.show(
      context,
      username: handle,
      uid: uid,
      inviteCode: user?.inviteCode,
    );
  }

  /// カードの共有ボタン。以前の共有シートと同じ招待カードを、グループの
  /// 共有画面と同じ形の画面で見せる（2026-11-17）。
  Future<void> _openShareScreen() async {
    final uid = _uid;
    final user = _user;
    final handle = user?.username;
    if (uid == null || handle == null || handle.isEmpty) return;
    await ProfileShareScreen.push(
      context,
      username: handle,
      uid: uid,
      inviteCode: user?.inviteCode,
    );
  }

  /// 連続投稿日数を数える。
  ///
  /// 暦日ではなく 15s Day（通知 〜 次の通知）で数える。進行中のサイクルに
  /// まだ投稿していない場合はそこを飛ばして 1 つ前から数える。今日まだ
  /// 投稿していないだけで連続が途切れたことにはしないため。
  /// 連続投稿日数。規則は他人のプロフィールと同じものを使う
  /// （[MusicMemoryCycleService.streakDays]）。
  Future<int> _calcStreak(List<PostModel> posts) => MusicMemoryCycleService()
      .streakDays([for (final p in posts) p.createdAt]);

  /// top artists を集計する。中身は [ProfileSnapshotService] に寄せてある。
  /// 投稿カードの裏面も同じ集計を出すので、ここで独自には持たない。
  Future<void> _loadTopArtists() async {
    final uid = _uid;
    if (uid == null) return;
    final names = await ProfileSnapshotService.instance
        .topArtistNames(uid: uid, posts: _posts);
    if (mounted) setState(() => _topArtistNames = names);
  }

  /// アーティスト名から Spotify のアーティスト ID を引く（分かる範囲で）。
  String? _artistIdOf(String name) {
    for (final p in _posts) {
      if (p.track.artistName.trim() == name) {
        final id = p.track.spotifyArtistId;
        if (id != null && id.isNotEmpty) return id;
      }
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        backgroundColor: _bg,
        body: Center(
          child: CupertinoActivityIndicator(color: Colors.white, radius: 14),
        ),
      );
    }

    if (widget.onClose != null) return _buildCard(context);

    // デザインは画面の最上端（y=0）から始まるので、リロードのインジケータを
    // 既定のまま出すとノッチ / ステータスバーの裏に入って見えない。
    // その高さぶん下げて描き、引っ張る距離も同じだけ伸ばす。
    final topInset = MediaQuery.paddingOf(context).top;

    return Scaffold(
      backgroundColor: _bg,
      body: SafeArea(
        top: false,
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(
            parent: BouncingScrollPhysics(),
          ),
          slivers: [
            CupertinoSliverRefreshControl(
              onRefresh: _refresh,
              refreshTriggerPullDistance: 100 + topInset,
              refreshIndicatorExtent: 60 + topInset,
              // 既定の見た目のまま、位置だけ下げる。引数を加工すると
              // CupertinoActivityIndicator の radius > 0 の assert に触れる。
              builder: (ctx, mode, pulled, trigger, extent) => Padding(
                padding: EdgeInsets.only(top: topInset),
                child: CupertinoSliverRefreshControl.buildRefreshIndicator(
                    ctx, mode, pulled, trigger, extent),
              ),
            ),
            SliverToBoxAdapter(
              child: ProfileView(
                name: _user?.name?.isNotEmpty == true
                    ? _user!.name!
                    : (_user?.username ?? ''),
                username: _user?.username,
                avatarUrl: _user?.profileImageUrl,
                friendCount: _friendCount,
                friendIcons: _friendIcons,
                postCount: _postCount,
                streakDays: _streakDays,
                topArtists: [
                  for (final name in _topArtistNames)
                    (name: name, artistId: _artistIdOf(name)),
                ],
                recentPosts: [
                  for (final p in _posts.take(3))
                    (
                      albumImageUrl: p.track.albumImageUrl,
                      trackName: p.track.trackName,
                      artistName: p.track.artistName,
                    ),
                ],
                showMilfolhaRanking:
                    _showMilfolhaRanking || _showLaneigeRanking,
                onOpenShare: _openShareSheet,
                onOpenSettings: () async {
                  await Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const SettingsScreen()),
                  );
                  final uid = _uid;
                  if (uid != null) await _loadUser(uid);
                },
                onOpenMilfolhaRanking: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => _showLaneigeRanking
                          ? const LaneigeRankingScreen()
                          : const MilfolhaRankingScreen()),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String get _displayName =>
      _user?.name?.isNotEmpty == true ? _user!.name! : (_user?.username ?? '');

  List<({String name, String? artistId})> get _topArtists => [
        for (final name in _topArtistNames)
          (name: name, artistId: _artistIdOf(name)),
      ];

  List<({String albumImageUrl, String trackName, String artistName})>
      get _recentPosts => [
            for (final p in _posts.take(3))
              (
                albumImageUrl: p.track.albumImageUrl,
                trackName: p.track.trackName,
                artistName: p.track.artistName,
              ),
          ];

  Future<void> _openSettings() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const SettingsScreen()),
    );
    final uid = _uid;
    if (uid != null) await _loadUser(uid);
  }

  /// ホームに重ねるカード。画面幅に合わせて拡大し、縦に入り切らない端末では
  /// さらに縮めて、下の安全領域の上に収める。
  Widget _buildCard(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final padding = MediaQuery.paddingOf(context);
    final scale = size.width / _designW;
    final top = _cardOrigin.dy * scale;
    final available = size.height - top - padding.bottom - 8;
    final s = (_cardH * scale > available) ? available / _cardH : scale;

    return Material(
      type: MaterialType.transparency,
      child: Stack(
        children: [
          // カードの外をタップしても閉じる。
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: widget.onClose,
            ),
          ),
          Positioned(
            left: (size.width - _cardW * s) / 2,
            top: top,
            width: _cardW * s,
            height: _cardH * s,
            // カードの中の空いたところのタップは、外へ抜けて閉じないよう止める。
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () {},
              child: FittedBox(
                fit: BoxFit.fill,
                child: SizedBox(
                  width: _cardW,
                  height: _cardH,
                  child: LiquidGlass(
                    radius: 39,
                    native: _glassReady,
                    child: _loading
                        ? const Center(
                            child: CupertinoActivityIndicator(
                                color: Colors.white, radius: 14),
                          )
                        : ProfileView.card(
                            name: _displayName,
                            username: _user?.username,
                            avatarUrl: _user?.profileImageUrl,
                            topArtists: _topArtists,
                            recentPosts: _recentPosts,
                            onClose: widget.onClose!,
                            // 中身は以前の招待カード、見た目はグループの共有画面と同じ。
                            onOpenShare: _openShareScreen,
                            // 新しい設定画面は別途作る。それまでは今の設定画面。
                            onOpenSettings: _openSettings,
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

/// プロフィールの見た目だけを持つ層。
///
/// 読み込みと描画を分けてあるのは、Figma との突き合わせを Firebase 抜きで
/// できるようにするため（座標が多く、実機だけで確かめるのは手間が大きい）。
class ProfileView extends StatelessWidget {
  final String name;
  final String? username;
  final String? avatarUrl;
  final int friendCount;

  /// ピルに重ねて出す友達アイコン（先頭 2 人ぶん）。
  final List<String?> friendIcons;
  final int postCount;
  final int streakDays;

  /// 上位アーティスト（最大 3）。画像は名前 / ID から引く。
  final List<({String name, String? artistId})> topArtists;

  /// 直近の投稿（最大 3）。
  final List<({String albumImageUrl, String trackName, String artistName})>
      recentPosts;

  final bool showMilfolhaRanking;

  /// ピルの文言。null なら「友達 N人」。
  ///
  /// Figma は「2人の共通」（共通の友達）で、これは他人のプロフィールの
  /// 話。自分のプロフィールでは成り立たないので、既定は友達の人数にして
  /// ある。他人を見るときは呼び出し側が共通の人数を渡す。
  final String? pillLabel;

  /// 友達のピルを出すか。他人のプロフィールでは出さない
  /// （友達機能の廃止、2026-11-01）。
  final bool showFriendsPill;

  /// 左上のボタン。招待カードの共有シートを開く。
  /// **自分のプロフィールのときだけ**渡す。null なら出さない。
  final VoidCallback? onOpenShare;

  /// 右上の設定。**自分のプロフィールのときだけ**渡す。null なら出さない。
  final VoidCallback? onOpenSettings;
  final VoidCallback? onOpenMilfolhaRanking;

  /// 戻る。他人のプロフィールのように、前の画面がある場合に渡す。
  /// 共有ボタンと同じ左上に、同じガラスの見た目で出す
  /// （他人を見ているときは共有が無いので場所が空く）。
  final VoidCallback? onBack;

  /// ホームに重ねるカードの見た目（[ProfileView.card]）か。
  final bool card;

  /// カードの左上のバツ。
  final VoidCallback? onClose;

  const ProfileView({
    super.key,
    required this.name,
    required this.username,
    required this.avatarUrl,
    required this.friendCount,
    required this.friendIcons,
    required this.postCount,
    required this.streakDays,
    required this.topArtists,
    required this.recentPosts,
    this.showMilfolhaRanking = false,
    this.pillLabel,
    this.showFriendsPill = true,
    this.onOpenShare,
    this.onOpenSettings,
    this.onOpenMilfolhaRanking,
    this.onBack,
  })  : card = false,
        onClose = null;

  /// ホームに重ねるガラスのカード（Figma 6672:12190）。
  ///
  /// 出すのはアイコン・名前・ID・top artists・recent choice だけ。地はガラスなので
  /// 中身に背景色は敷かない。カードの座標（384×703）で描く。
  const ProfileView.card({
    super.key,
    required this.name,
    required this.username,
    required this.avatarUrl,
    required this.topArtists,
    required this.recentPosts,
    required VoidCallback this.onClose,
    required VoidCallback this.onOpenShare,
    required VoidCallback this.onOpenSettings,
  })  : card = true,
        friendCount = 0,
        friendIcons = const [],
        postCount = 0,
        streakDays = 0,
        showMilfolhaRanking = false,
        pillLabel = null,
        showFriendsPill = false,
        onOpenMilfolhaRanking = null,
        onBack = null;

  @override
  Widget build(BuildContext context) {
    if (card) {
      return SizedBox(
        width: _cardW,
        height: _cardH,
        child: Stack(children: _cardContent()),
      );
    }
    final width = MediaQuery.sizeOf(context).width;
    final scale = width / _designW;
    return SizedBox(
      width: width,
      height: _designH * scale,
      child: Transform.scale(
        scale: scale,
        alignment: Alignment.topLeft,
        child: SizedBox(
          width: _designW,
          height: _designH,
          child: Stack(children: _content(context)),
        ),
      ),
    );
  }

  List<Widget> _content(BuildContext context) => [
        // 左上のガラスボタン。自分のときは共有（招待カードを配る導線）、
        // 他人を見ているときは戻る。両方出ることはない。
        if (onOpenShare != null) _shareButton(),
        if (onOpenShare == null && onBack != null) _backButton(),
        _settingsButton(),
        _avatar(),
        _name(),
        _handle(),
        if (showFriendsPill) _friendsPill(),
        _statsPill(),
        ..._topArtistsSection(),
        ..._recentChoiceSection(),
      ];

  // ── カード（Figma 6672:12122）─────────────────────────────

  List<Widget> _cardContent() => [
        // 上のガラスの丸ボタン（45 角）。左からバツ / 共有 / 設定。
        _cardButton(
          left: 22,
          onTap: onClose!,
          child: SvgPicture.asset('assets/profile_v3/close.svg',
              width: 17, height: 16),
        ),
        _cardButton(
          left: 270,
          onTap: onOpenShare!,
          child:
              const Icon(CupertinoIcons.share, color: Colors.white, size: 21),
        ),
        _cardButton(
          left: 322,
          onTap: onOpenSettings!,
          child: const Icon(CupertinoIcons.gear_alt,
              color: Colors.white, size: 23),
        ),
        Positioned(
          left: (_cardW - 84) / 2,
          top: 80,
          child: ClipOval(
            child: Container(
              width: 84,
              height: 84,
              color: const Color(0x33FFFFFF),
              child: ProfileImage(imageUrl: avatarUrl, size: 84),
            ),
          ),
        ),
        Positioned(
          left: 20,
          right: 20,
          top: 176,
          child: Text(
            name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 22,
              height: 1.2,
              fontWeight: FontWeight.w600,
              fontFamily: kSfProRounded,
            ),
          ),
        ),
        Positioned(
          left: 20,
          right: 20,
          top: 204,
          child: Text(
            (username == null || username!.isEmpty) ? '' : '@$username',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: const TextStyle(
              // ガラスの上では #A3A3A3 だと沈むので、白を薄くして載せる。
              color: Color(0xB3FFFFFF),
              fontSize: 14,
              height: 1.2,
              fontWeight: FontWeight.w600,
              fontFamily: kSfProRounded,
            ),
          ),
        ),
        ..._topArtistsSection(shift: _cardSectionShift),
        ..._recentChoiceSection(shift: _cardSectionShift),
      ];

  Widget _cardButton({
    required double left,
    required VoidCallback onTap,
    required Widget child,
  }) {
    return Positioned(
      left: left,
      top: 19,
      child: GlassCircleButton(size: 45, onTap: onTap, child: child),
    );
  }

  // ── ヘッダー ───────────────────────────────────────────

  /// 左上のガラスボタン。Figma: Frame 840 (16,62) 52×45。
  /// 招待カードの共有シート（Figma 5779-12975）を開く。
  /// 左上の戻る。共有ボタンと同じガラスの台座に、矢印を載せる
  /// （他人のプロフィールでは共有を出さないので、この場所が空く）。
  Widget _backButton() {
    return Positioned(
      left: 16,
      top: 62,
      width: 52,
      height: 45,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onBack,
        child: Stack(
          children: [
            Image.asset(
              'assets/profile_v2/glass_button.png',
              width: 52,
              height: 45,
              fit: BoxFit.fill,
            ),
            const Positioned(
              left: 16,
              top: 12,
              width: 20,
              height: 20,
              child: Center(
                child: Icon(Icons.arrow_back_ios_new,
                    color: Colors.white, size: 17),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _shareButton() {
    return Positioned(
      left: 16,
      top: 62,
      width: 52,
      height: 45,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onOpenShare,
        child: Stack(
          children: [
            // 素材は書き出し時に影のぶんの余白が付いていたので、ノード枠
            // （52×45）だけを切り出したものを入れてある。4x なので等倍で敷く。
            Image.asset(
              'assets/profile_v2/glass_button.png',
              width: 52,
              height: 45,
              fit: BoxFit.fill,
            ),
            // Figma: Share は (16,12) の 20×20、グリフの実寸は 14×18。
            // CupertinoIcons.share はインク比 0.785（目標 0.778）で、
            // size 19 のとき 14.1×18.0 とほぼ一致する
            // （Icons.ios_share は 0.728 で細長すぎる）。
            const Positioned(
              left: 16,
              top: 12,
              width: 20,
              height: 20,
              child: Center(
                child:
                    Icon(CupertinoIcons.share, color: Colors.white, size: 19),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 設定（と WATERFALLS ランキング）への導線。
  ///
  /// Figma の右上は空いているが、タブを無くした結果ここが設定への唯一の
  /// 入口になる。消すと account 編集やログアウトに辿り着けなくなるため残す。
  Widget _settingsButton() {
    return Positioned(
      right: 16,
      top: 62,
      height: 45,
      child: Row(
        children: [
          if (showMilfolhaRanking)
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onOpenMilfolhaRanking,
              child: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 8),
                child: Icon(Icons.emoji_events,
                    color: Color(0xFFFFD700), size: 22),
              ),
            ),
          // 設定は自分のプロフィールだけ。他人を見ているときは出さない。
          if (onOpenSettings != null)
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onOpenSettings,
              // 左上の共有ボタンと同じガラス（52×45）に載せる。
              child: Padding(
                padding: const EdgeInsets.only(left: 8),
                child: SizedBox(
                  width: 52,
                  height: 45,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      Image.asset(
                        'assets/profile_v2/glass_button.png',
                        width: 52,
                        height: 45,
                        fit: BoxFit.fill,
                      ),
                      const Icon(Icons.settings_outlined,
                          color: Colors.white, size: 22),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  // ── プロフィール ───────────────────────────────────────

  Widget _avatar() {
    return Positioned(
      left: 156.5,
      top: 109,
      child: ClipOval(
        child: Container(
          width: 89,
          height: 89,
          color: const Color(0xFF3A3A3A),
          child: ProfileImage(imageUrl: avatarUrl, size: 89),
        ),
      ),
    );
  }

  Widget _name() {
    return Positioned(
      left: 20,
      right: 20,
      top: 209,
      child: Text(
        name,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        textAlign: TextAlign.center,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 24,
          height: 1.2,
          fontWeight: FontWeight.w600,
          fontFamily: kSfProRounded,
        ),
      ),
    );
  }

  Widget _handle() {
    final handle = username;
    return Positioned(
      left: 20,
      right: 20,
      top: 238,
      child: Text(
        (handle == null || handle.isEmpty) ? '' : '@$handle',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        textAlign: TextAlign.center,
        style: const TextStyle(
          color: _handleColor,
          fontSize: 15,
          height: 1.2,
          fontWeight: FontWeight.w600,
          fontFamily: kSfProRounded,
        ),
      ),
    );
  }

  /// Figma では「2人の共通」（共通の友達）だが、自分のプロフィールでは
  /// 成り立たないので友達の人数に差し替えている。アイコンの重ね方と傾きは
  /// デザインのまま。
  Widget _friendsPill() {
    return Positioned(
      left: 114,
      top: 277,
      width: 174,
      height: 52,
      child: Container(
        decoration: BoxDecoration(
          color: _pillBg,
          borderRadius: BorderRadius.circular(15),
        ),
        child: Stack(
          children: [
            // 奥側（少し傾いている方）
            Positioned(
              left: 15.9,
              top: 13.8,
              child: Transform.rotate(
                angle: -9.51 * 3.1415926535 / 180,
                child: _pillAvatar(friendIcons.elementAtOrNull(0)),
              ),
            ),
            Positioned(
              left: 44,
              top: 11,
              child: _pillAvatar(friendIcons.elementAtOrNull(1)),
            ),
            Positioned(
              left: 82,
              right: 8,
              top: 17,
              child: Text(
                pillLabel ?? '友達 $friendCount人',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  height: 1.2,
                  fontWeight: FontWeight.w600,
                  fontFamily: kSfProRounded,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _pillAvatar(String? url) {
    return ClipOval(
      child: Container(
        width: 30,
        height: 30,
        color: const Color(0xFF3A3A3A),
        child: ProfileImage(imageUrl: url, size: 30),
      ),
    );
  }

  /// 「💜 N Music ｜ 🔥 Nd 連続」。Figma: Frame 674 (83,350) 236×47。
  Widget _statsPill() {
    return Positioned(
      left: 83,
      top: 350,
      width: 236,
      height: 47,
      child: Container(
        decoration: BoxDecoration(
          color: _statsBg,
          border: Border.all(color: _statsBorder),
          borderRadius: BorderRadius.circular(15),
        ),
        child: Stack(
          children: [
            Positioned(
              left: 14,
              top: 14,
              child: _statsLabel('💜  $postCount ', 'Music'),
            ),
            Positioned(
              left: 118,
              top: 16.5,
              child: Container(width: 1, height: 14, color: _statsBorder),
            ),
            Positioned(
              left: 148,
              top: 14,
              child: _statsLabel('🔥${streakDays}d ', '連続'),
            ),
          ],
        ),
      ),
    );
  }

  /// 絵文字だけ 16px、文字は 14px（Figma の指定通り）。
  Widget _statsLabel(String emojiPart, String textPart) {
    return Text.rich(
      TextSpan(
        children: [
          TextSpan(text: emojiPart, style: const TextStyle(fontSize: 16)),
          TextSpan(text: textPart, style: const TextStyle(fontSize: 14)),
        ],
      ),
      style: const TextStyle(
        color: _statsText,
        height: 1.2,
        fontWeight: FontWeight.w600,
        fontFamily: kSfProRounded,
      ),
    );
  }

  // ── top artists ───────────────────────────────────────

  /// [shift] はカードに載せるときのずらし（全画面では 0）。
  List<Widget> _topArtistsSection({Offset shift = Offset.zero}) {
    final artists = topArtists;
    final origin = _artistsOrigin + shift;
    return [
      // タイトルは 4x 書き出し。影のぶん左右に 16pt ずつ余白が入っているので、
      // 画像幅 = canvas/4 で置けば文字が Figma の位置に来る。
      Positioned(
        left: (_designW - 1395 / 4) / 2 + shift.dx,
        top: 421.9 + shift.dy,
        child: Image.asset(
          'assets/profile_v2/title_top_artists.png',
          width: 1395 / 4,
        ),
      ),
      for (var i = 0; i < 3; i++) ...[
        Positioned(
          left: origin.dx + _tileLefts[i],
          top: origin.dy + 49,
          child: _artistTile(
            artist: i < artists.length ? artists[i] : null,
            isFirst: i == 0,
          ),
        ),
        // 順位の数字はタイルの上に重なる。ベースラインを揃えたいので下端で置く。
        Positioned(
          left: origin.dx + _tileLefts[i],
          top: origin.dy + 49,
          width: _tile,
          child: _rankNumeral(i),
        ),
        Positioned(
          left: origin.dx + _tileLefts[i] - 12,
          top: origin.dy + 169,
          width: _tile + 24,
          child: Text(
            i < artists.length ? artists[i].name : '',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
              height: 1.2,
              letterSpacing: 0.12,
              fontWeight: FontWeight.w700,
              fontFamily: kSfProRounded,
            ),
          ),
        ),
      ],
    ];
  }

  /// 数字は Figma のテキスト枠（幅 30/38/40、中心 95/208/317）に合わせて置く。
  /// 素材は 4x なので高さ = canvas/4、下端をベースライン（相対 153）に揃える。
  Widget _rankNumeral(int index) {
    const heights = [178 / 4, 181 / 4, 184 / 4];
    const centers = [95.0, 208.0, 317.0];
    final h = heights[index];
    return SizedBox(
      height: 105,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            // 中心 - タイル左端 で、このタイル内での中心位置になる。
            left: centers[index] - _tileLefts[index] - 40,
            top: 153 - 49 - h,
            width: 80,
            child: Center(
              child: Image.asset(
                'assets/profile_v2/rank_${index + 1}.png',
                height: h,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _artistTile({
    required ({String name, String? artistId})? artist,
    required bool isFirst,
  }) {
    return Container(
      width: _tile,
      height: _tile,
      decoration: BoxDecoration(
        color: Colors.white,
        shape: BoxShape.circle,
        boxShadow: [
          if (isFirst)
            const BoxShadow(color: Color(0x1FD5F94B), blurRadius: 24),
          ..._tileShadow,
        ],
      ),
      child: ClipOval(
        child: artist == null
            ? const _TilePlaceholder(icon: Icons.person)
            : _ArtistImage(name: artist.name, artistId: artist.artistId),
      ),
    );
  }

  // ── recent choice ─────────────────────────────────────

  List<Widget> _recentChoiceSection({Offset shift = Offset.zero}) {
    final recent = recentPosts;
    final origin = _recentOrigin + shift;
    return [
      Positioned(
        left: (_designW - 1562 / 4) / 2 + shift.dx,
        top: 595.9 + shift.dy,
        child: Image.asset(
          'assets/profile_v2/title_recent_choice.png',
          width: 1562 / 4,
        ),
      ),
      for (var i = 0; i < 3; i++) ...[
        Positioned(
          left: origin.dx + _tileLefts[i],
          top: origin.dy,
          child: Container(
            width: _tile,
            height: _tile,
            decoration: const BoxDecoration(boxShadow: _tileShadow),
            // URL が空の投稿（取り込み曲などでアートが無い）もあるので、
            // 長さだけでなく中身も見てからネットワーク画像にする。
            child: i < recent.length && recent[i].albumImageUrl.isNotEmpty
                ? Image(
                    image: albumImageProvider(recent[i].albumImageUrl),
                    width: _tile,
                    height: _tile,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) =>
                        const _TilePlaceholder(icon: Icons.music_note),
                  )
                : const _TilePlaceholder(icon: Icons.music_note),
          ),
        ),
        Positioned(
          left: origin.dx + _tileLefts[i] - 12,
          top: origin.dy + 114,
          width: _tile + 24,
          child: Text(
            i < recent.length ? recent[i].trackName : '',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 13,
              height: 1.2,
              letterSpacing: 0.13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        Positioned(
          left: origin.dx + _tileLefts[i] - 12,
          top: origin.dy + 133,
          width: _tile + 24,
          child: Text(
            i < recent.length ? recent[i].artistName : '',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: _trackArtistColor,
              fontSize: 12,
              height: 1.2,
              letterSpacing: 0.12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    ];
  }
}

/// 中身がまだ無いタイル。
class _TilePlaceholder extends StatelessWidget {
  final IconData icon;
  const _TilePlaceholder({required this.icon});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFF2A2A2A),
      alignment: Alignment.center,
      child: Icon(icon, color: Colors.white24, size: 34),
    );
  }
}

/// アーティスト画像。投稿には入っていないので Spotify から引く。
/// [artistId] が分かっていればそちらの方が正確（同名アーティスト対策）。
class _ArtistImage extends StatefulWidget {
  final String name;
  final String? artistId;

  const _ArtistImage({required this.name, this.artistId});

  @override
  State<_ArtistImage> createState() => _ArtistImageState();
}

class _ArtistImageState extends State<_ArtistImage> {
  String? _url;

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  @override
  void didUpdateWidget(covariant _ArtistImage old) {
    super.didUpdateWidget(old);
    if (old.name != widget.name || old.artistId != widget.artistId) _fetch();
  }

  Future<void> _fetch() async {
    // 取得とキャッシュは ProfileSnapshotService に寄せてある。
    // 投稿カードの裏面も同じ画像を使うので、別々に引くと往復が倍になる。
    final url = await ProfileSnapshotService.instance
        .artistImage(widget.name, artistId: widget.artistId);
    if (mounted) setState(() => _url = url);
  }

  @override
  Widget build(BuildContext context) {
    final url = _url;
    if (url == null || url.isEmpty) {
      return const _TilePlaceholder(icon: Icons.person);
    }
    return CachedNetworkImage(
      imageUrl: url,
      fit: BoxFit.cover,
      errorWidget: (_, __, ___) => const _TilePlaceholder(icon: Icons.person),
    );
  }
}

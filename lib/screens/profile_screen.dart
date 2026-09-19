import 'package:cached_network_image/cached_network_image.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../constants/profile_fonts.dart';
import '../models/post_model.dart';
import '../models/user_model.dart';
import '../services/friend_service.dart';
import '../services/milfolha_service.dart';
import '../services/music_memory_cycle_service.dart';
import '../services/post_service.dart';
import '../services/profile_snapshot_service.dart';
import '../services/spotify_service.dart';
import '../services/user_service.dart';
import '../utils/album_image.dart';
import '../widgets/profile_widgets.dart';
import 'friend_add_sheet.dart';
import 'milfolha_ranking_screen.dart';
import 'settings_screen.dart';

/// プロフィール画面（自分）— Figma 5761:12112。
///
/// ## 座標について
/// Figma の 402×874（iPhone 16/17 Pro）をそのまま数値で持ち、画面幅に対する
/// 倍率をかけて描く。要素が全て絶対座標で置かれた「ポスター」型のデザインなので、
/// 個々の値を端末幅で割るより崩れにくい。縦に入り切らない端末ではスクロールする。
class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

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

const double _designW = 402;
const double _designH = 874;

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

  UserModel? _user;
  bool _loading = true;

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

  String? get _uid => FirebaseAuth.instance.currentUser?.uid;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final uid = _uid;
    if (uid == null) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    await Future.wait([
      _loadUser(uid),
      _loadPosts(uid),
      _loadFriends(uid),
      _loadMilfolhaEntry(uid),
    ]);
    // 投稿を材料に使うことがあるので、_loadPosts のあとに走らせる。
    await _loadTopArtists();
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _refresh() async {
    final uid = _uid;
    if (uid == null) return;
    await Future.wait([
      _loadUser(uid),
      _loadPosts(uid),
      _loadFriends(uid),
    ]);
    await _loadTopArtists();
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
      final result = await _postService.getPostsByUserIdPaged(uid, limit: 60);
      final count = await _postService.getPostCountByUserId(uid);
      final streak = await _calcStreak(result.posts);
      if (!mounted) return;
      setState(() {
        _posts = result.posts;
        _postCount = count;
        _streakDays = streak;
      });
    } catch (_) {/* 表示は既存値のまま */}
  }

  Future<void> _loadFriends(String uid) async {
    try {
      final friends = await _friendService.loadFriends(uid);
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

  /// 連続投稿日数を数える。
  ///
  /// 暦日ではなく 15s Day（通知 〜 次の通知）で数える。進行中のサイクルに
  /// まだ投稿していない場合はそこを飛ばして 1 つ前から数える。今日まだ
  /// 投稿していないだけで連続が途切れたことにはしないため。
  Future<int> _calcStreak(List<PostModel> posts) async {
    if (posts.isEmpty) return 0;
    try {
      final days = await MusicMemoryCycleService().loadDays(limit: 40);
      if (days.isEmpty) return 0;

      final postedKeys = <String>{};
      for (final p in posts) {
        final key = MusicMemoryCycleService.dayKeyAt(days, p.createdAt);
        if (key != null) postedKeys.add(key);
      }

      var start = 0;
      if (!postedKeys.contains(days.first.key)) start = 1;
      var streak = 0;
      for (var i = start; i < days.length; i++) {
        if (!postedKeys.contains(days[i].key)) break;
        streak++;
      }
      return streak;
    } catch (_) {
      return 0;
    }
  }

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

    return Scaffold(
      backgroundColor: _bg,
      body: SafeArea(
        top: false,
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(
            parent: BouncingScrollPhysics(),
          ),
          slivers: [
            CupertinoSliverRefreshControl(onRefresh: _refresh),
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
                showMilfolhaRanking: _showMilfolhaRanking,
                onOpenFriendAdd: () => FriendAddSheet.show(context),
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
                      builder: (_) => const MilfolhaRankingScreen()),
                ),
              ),
            ),
          ],
        ),
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

  /// 左上のボタン。友達追加シートを開く。
  final VoidCallback? onOpenFriendAdd;
  final VoidCallback? onOpenSettings;
  final VoidCallback? onOpenMilfolhaRanking;

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
    this.onOpenFriendAdd,
    this.onOpenSettings,
    this.onOpenMilfolhaRanking,
  });

  @override
  Widget build(BuildContext context) {
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
        _shareButton(),
        _settingsButton(),
        _avatar(),
        _name(),
        _handle(),
        _friendsPill(),
        _statsPill(),
        ..._topArtistsSection(),
        ..._recentChoiceSection(),
      ];

  // ── ヘッダー ───────────────────────────────────────────

  /// 左上のガラスボタン。Figma: Frame 840 (16,62) 52×45。
  /// 友達追加シート（招待リンクの共有を含む）を開く。
  Widget _shareButton() {
    return Positioned(
      left: 16,
      top: 62,
      width: 52,
      height: 45,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onOpenFriendAdd,
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
                child: Icon(CupertinoIcons.share, color: Colors.white, size: 19),
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
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onOpenSettings,
            child: const Padding(
              padding: EdgeInsets.only(left: 8),
              child:
                  Icon(Icons.settings_outlined, color: Colors.white, size: 24),
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
                '友達 $friendCount人',
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

  List<Widget> _topArtistsSection() {
    final artists = topArtists;
    return [
      // タイトルは 4x 書き出し。影のぶん左右に 16pt ずつ余白が入っているので、
      // 画像幅 = canvas/4 で置けば文字が Figma の位置に来る。
      Positioned(
        left: (_designW - 1395 / 4) / 2,
        top: 421.9,
        child: Image.asset(
          'assets/profile_v2/title_top_artists.png',
          width: 1395 / 4,
        ),
      ),
      for (var i = 0; i < 3; i++) ...[
        Positioned(
          left: _artistsOrigin.dx + _tileLefts[i],
          top: _artistsOrigin.dy + 49,
          child: _artistTile(
            artist: i < artists.length ? artists[i] : null,
            isFirst: i == 0,
          ),
        ),
        // 順位の数字はタイルの上に重なる。ベースラインを揃えたいので下端で置く。
        Positioned(
          left: _artistsOrigin.dx + _tileLefts[i],
          top: _artistsOrigin.dy + 49,
          width: _tile,
          child: _rankNumeral(i),
        ),
        Positioned(
          left: _artistsOrigin.dx + _tileLefts[i] - 12,
          top: _artistsOrigin.dy + 169,
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

  List<Widget> _recentChoiceSection() {
    final recent = recentPosts;
    return [
      Positioned(
        left: (_designW - 1562 / 4) / 2,
        top: 595.9,
        child: Image.asset(
          'assets/profile_v2/title_recent_choice.png',
          width: 1562 / 4,
        ),
      ),
      for (var i = 0; i < 3; i++) ...[
        Positioned(
          left: _recentOrigin.dx + _tileLefts[i],
          top: _recentOrigin.dy,
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
          left: _recentOrigin.dx + _tileLefts[i] - 12,
          top: _recentOrigin.dy + 114,
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
          left: _recentOrigin.dx + _tileLefts[i] - 12,
          top: _recentOrigin.dy + 133,
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
  final SpotifyService _spotify = SpotifyService();
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
    try {
      final id = widget.artistId;
      final url = (id != null && id.isNotEmpty)
          ? await _spotify.getArtistImageUrlById(id)
          : await _spotify.getArtistImageUrl(widget.name);
      if (mounted) setState(() => _url = url);
    } catch (_) {/* プレースホルダのまま */}
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

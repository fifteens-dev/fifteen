import 'dart:async';
import 'dart:ui' as ui;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:provider/provider.dart';

import '../constants/profile_fonts.dart';
import '../models/group_model.dart';
import '../models/post_model.dart';
import '../models/post_theme.dart';
import '../models/user_model.dart';
import '../providers/current_user_provider.dart';
import '../services/audio_player_service.dart';
import '../services/group_service.dart';
import '../services/poke_service.dart';
import '../services/post_flow_request.dart';
import '../services/post_service.dart';
import '../utils/color_extractor.dart';
import '../widgets/common/app_toast.dart';
import 'group_settings_sheet.dart';
import '../widgets/common/glass_circle_button.dart';
import '../widgets/home/group_home_view.dart' show groupReactionEmojis;
import '../widgets/post_card.dart';
import '../widgets/post_card/enlarge_flip_cell.dart';
import '../widgets/profile_widgets.dart';

/// グループ画面（Figma 6308:12346）。
///
/// 2 列のグリッドに、自分（左上）→ 投稿した順のメンバー → まだの人 →
/// 招待、の順に並べる。投稿していなくても入れて、投稿も見られる。
///
/// - 投稿は表面を省略したカードで出し、タップでその場から拡大して裏へ反転する。
/// - リアクションは長押し（タップは反転に使う）。
/// - まだの人には「つつく」。1 サイクルに 1 人 1 回。
/// - グループ名のタップで設定（[GroupSettingsSheet]）。共有・メモリーは別途作る。
///
/// 寸法は Figma の 402 幅のまま持ち、画面幅に合わせて拡縮する。
class GroupScreen extends StatefulWidget {
  final GroupModel group;

  /// Firebase 抜きで見た目を確かめるための差し替え（テスト用）。
  @visibleForTesting
  final GroupCycleStatus? debugStatus;
  @visibleForTesting
  final List<UserModel>? debugUsers;
  @visibleForTesting
  final String? debugUid;

  const GroupScreen({
    super.key,
    required this.group,
    this.debugStatus,
    this.debugUsers,
    this.debugUid,
  });

  static Future<void> push(BuildContext context, GroupModel group) {
    return Navigator.of(context).push(
      CupertinoPageRoute(builder: (_) => GroupScreen(group: group)),
    );
  }

  @override
  State<GroupScreen> createState() => _GroupScreenState();
}

const double _designW = 402;
const double _designTopInset = 62;

const double _cellW = 180;
const double _cellH = 286;
const double _gridLeft = 13;
const double _gridGap = 13;
const double _rowGap = 15;

const Color _bg = Color(0xFF121212);
const Color _dashColor = Color(0xFF5C5762);
const Color _subGrey = Color(0xFF8F8894);

TextStyle _rounded(double size, Color color, double wght) => TextStyle(
      fontFamily: kSfProRounded,
      fontSize: size,
      color: color,
      height: 1.2,
      fontWeight: wght >= 600 ? FontWeight.w600 : FontWeight.normal,
      fontVariations: [ui.FontVariation('wght', wght)],
    );

/// グリッドの 1 マスの中身。
sealed class _Slot {}

class _PostSlot extends _Slot {
  final PostModel post;
  final bool isMe;
  _PostSlot(this.post, {required this.isMe});
}

class _WaitingSlot extends _Slot {
  final String uid;
  final bool isMe;
  _WaitingSlot(this.uid, {required this.isMe});
}

class _InviteSlot extends _Slot {}

class _GroupScreenState extends State<GroupScreen> {
  late final GroupService _groupService = GroupService();
  late final PostService _postService = PostService();
  late final AudioPlayerService _audio = AudioPlayerService();
  bool _audioUsed = false;

  /// 表示中のグループ。設定で名前やメンバーが変わったら差し替わる。
  late GroupModel _group = widget.group;
  StreamSubscription<GroupModel?>? _groupSub;

  GroupCycleStatus? _status;
  Map<String, UserModel> _users = const {};
  Set<String> _poked = const {};

  /// つつく途中の相手（二度押し防止）。
  final Set<String> _poking = {};

  String get _uid =>
      widget.debugUid ?? FirebaseAuth.instance.currentUser?.uid ?? '';

  @override
  void initState() {
    super.initState();
    _load();
    if (widget.debugStatus == null) {
      _groupSub = _groupService.watchGroup(widget.group.groupId).listen((g) {
        if (!mounted || g == null) return;
        final membersChanged = !_sameMembers(g.memberIds, _group.memberIds);
        setState(() => _group = g);
        if (membersChanged) _load();
      });
    }
  }

  static bool _sameMembers(List<String> a, List<String> b) =>
      a.length == b.length && a.toSet().containsAll(b);

  /// グループ名と矢印のタップで、設定を下から出す。抜けたらホームへ戻る。
  Future<void> _openSettings() async {
    final left = await GroupSettingsSheet.show(
      context,
      groupId: _group.groupId,
      uid: _uid,
    );
    if (left && mounted) Navigator.of(context).popUntil((r) => r.isFirst);
  }

  @override
  void dispose() {
    _groupSub?.cancel();
    if (_audioUsed) _audio.stop();
    super.dispose();
  }

  Future<void> _load() async {
    if (widget.debugStatus != null) {
      setState(() {
        _status = widget.debugStatus;
        _users = {
          for (final u in widget.debugUsers ?? const <UserModel>[]) u.uid: u
        };
      });
      return;
    }
    final results = await Future.wait([
      _groupService.loadCycleStatus(_group),
      _groupService.fetchUsers(_group.memberIds),
      PokeService.instance.pokedTargets(_uid),
    ]);
    if (!mounted) return;
    setState(() {
      _status = results[0] as GroupCycleStatus;
      _users = {for (final u in results[1] as List<UserModel>) u.uid: u};
      _poked = results[2] as Set<String>;
    });
  }

  /// 自分 → 投稿した順 → まだの人 → 招待（10 人未満のとき）。
  List<_Slot> _slots(GroupCycleStatus status) {
    final posts = status.postsByMember;
    final mine = posts[_uid];
    final others = [
      for (final e in posts.entries)
        if (e.key != _uid) e.value,
    ]..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    return [
      mine != null
          ? _PostSlot(mine, isMe: true)
          : _WaitingSlot(_uid, isMe: true),
      for (final p in others) _PostSlot(p, isMe: false),
      for (final uid in _group.memberIds)
        if (uid != _uid && !posts.containsKey(uid))
          _WaitingSlot(uid, isMe: false),
      if (_group.memberIds.length < GroupModel.maxMembers) _InviteSlot(),
    ];
  }

  String _nameOf(String uid) {
    final u = _users[uid];
    if (u?.name?.isNotEmpty == true) return u!.name!;
    return u?.username ?? '';
  }

  Future<void> _poke(String toUid) async {
    if (_poking.contains(toUid) || _poked.contains(toUid)) return;
    setState(() => _poking.add(toUid));
    final ok = await PokeService.instance.poke(
      fromUid: _uid,
      fromName: _nameOf(_uid),
      toUid: toUid,
      group: _group,
    );
    if (!mounted) return;
    setState(() {
      _poking.remove(toUid);
      // 失敗はもうつついていた（別のグループから等）ことが多いので、どちらでも押せなくする。
      _poked = {..._poked, toUid};
    });
    if (ok) AppToast.show(context, '${_nameOf(toUid)}をつつきました');
  }

  /// 自分がまだのとき。ホームへ戻って投稿画面を開く。
  void _chooseMine() {
    PostFlowRequest.instance.request();
    Navigator.of(context).popUntil((r) => r.isFirst);
  }

  void _comingSoon() => AppToast.show(context, '準備中です');

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final scale = media.size.width / _designW;
    final status = _status;

    return Scaffold(
      backgroundColor: _bg,
      body: Stack(
        children: [
          if (status == null)
            const Center(child: CupertinoActivityIndicator(color: Colors.white))
          else
            CustomScrollView(
              physics: const BouncingScrollPhysics(
                parent: AlwaysScrollableScrollPhysics(),
              ),
              slivers: [
                // Figma のグリッドは y=125（ヘッダー 57〜101 の下）。
                SliverToBoxAdapter(
                  child: SizedBox(
                      height:
                          media.padding.top + (125 - _designTopInset) * scale),
                ),
                CupertinoSliverRefreshControl(onRefresh: _load),
                SliverPadding(
                  padding: EdgeInsets.only(
                    left: _gridLeft * scale,
                    right:
                        (_designW - _gridLeft - _cellW * 2 - _gridGap) * scale,
                    bottom: 40 * scale + media.padding.bottom,
                  ),
                  sliver: SliverGrid(
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2,
                      crossAxisSpacing: _gridGap * scale,
                      mainAxisSpacing: _rowGap * scale,
                      childAspectRatio: _cellW / _cellH,
                    ),
                    delegate: SliverChildListDelegate([
                      for (final slot in _slots(status)) _cell(slot, status),
                    ]),
                  ),
                ),
              ],
            ),
          _header(media, scale),
        ],
      ),
    );
  }

  // ── ヘッダー（Figma 6308:12366：y=57、44 角のボタン）──────────

  Widget _header(MediaQueryData media, double scale) {
    return Positioned(
      left: 16 * scale,
      right: 16 * scale,
      top: media.padding.top + (57 - _designTopInset) * scale,
      height: 44 * scale,
      child: FittedBox(
        fit: BoxFit.fitWidth,
        alignment: Alignment.topLeft,
        child: SizedBox(
          width: 370,
          height: 44,
          child: Stack(
            children: [
              Positioned(
                left: 0,
                top: 0,
                child: GlassCircleButton(
                  size: 44,
                  onTap: () => Navigator.of(context).maybePop(),
                  child: SvgPicture.asset('assets/home_v2/back_chevron.svg',
                      width: 9, height: 16),
                ),
              ),
              // グループ名と矢印（タップで設定を下から出す）。
              Positioned(
                left: 60,
                right: 110,
                top: 0,
                bottom: 0,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: _openSettings,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Flexible(
                        child: Text(
                          _group.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 15,
                            fontFamily: 'SFPro',
                            fontWeight: FontWeight.w500,
                            fontVariations: [ui.FontVariation('wght', 510)],
                          ),
                        ),
                      ),
                      const SizedBox(width: 13),
                      Transform.rotate(
                        angle: 3.14159265,
                        child: SvgPicture.asset(
                            'assets/home_v2/back_chevron.svg',
                            width: 9,
                            height: 16),
                      ),
                    ],
                  ),
                ),
              ),
              Positioned(
                left: 272,
                top: 0,
                child: GlassCircleButton(
                  size: 44,
                  onTap: _comingSoon,
                  child: const Icon(CupertinoIcons.calendar,
                      color: Colors.white, size: 22),
                ),
              ),
              Positioned(
                left: 326,
                top: 0,
                child: GlassCircleButton(
                  size: 44,
                  onTap: _comingSoon,
                  child: const Icon(CupertinoIcons.share,
                      color: Colors.white, size: 21),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── マス ────────────────────────────────────────────

  /// Figma の 180×286 で組んだものをマスの大きさに拡縮する。
  Widget _fit(Widget child) => FittedBox(
        fit: BoxFit.contain,
        child: SizedBox(width: _cellW, height: _cellH, child: child),
      );

  Widget _cell(_Slot slot, GroupCycleStatus status) {
    switch (slot) {
      case _PostSlot(:final post, :final isMe):
        return EnlargeFlipCell(
          key: ValueKey('post_${post.postId}'),
          cell: _fit(_CompactPostCard(
            post: post,
            isMe: isMe,
            hasPhoto: status.postIdsWithPhoto.contains(post.postId),
            reactionEmojis: groupReactionEmojis(
              post.reactions,
              _group.memberIds.toSet(),
              max: 6,
            ),
          )),
          cardBuilder: (key, onTap, requestClose) {
            _audioUsed = true;
            return PostCard(
              key: key,
              post: post,
              currentUserId: _uid,
              currentUserIconUrl: context.read<CurrentUserProvider>().iconUrl,
              audioService: _audio,
              externalFlipControl: true,
              onCardTap: onTap,
              reactOnLongPress: true,
              onReaction: (emoji) => _react(post, emoji),
              backSideEnabled: true,
              // 写真を付けた人は裏面に写真、付けていない人はプロフィール。
              backPhotoUrl: status.photoUrls[post.postId],
            );
          },
        );
      case _WaitingSlot(:final uid, :final isMe):
        return _fit(_WaitingCard(
          name: isMe ? 'あなた' : _nameOf(uid),
          avatarUrl: _users[uid]?.profileImageUrl,
          action: isMe
              ? _PillAction(label: '選ぶ', emoji: '🎵', onTap: _chooseMine)
              : _poked.contains(uid)
                  ? const _PillAction(label: 'つついた', emoji: '👉', onTap: null)
                  : _PillAction(
                      label: 'つつく',
                      emoji: '👉',
                      onTap: _poking.contains(uid) ? null : () => _poke(uid),
                    ),
        ));
      case _InviteSlot():
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _openSettings,
          child: _fit(const _InviteCard()),
        );
    }
  }

  Future<void> _react(PostModel post, String emoji) async {
    try {
      await _postService.setReaction(
        postId: post.postId,
        emoji: emoji,
        userId: _uid,
      );
    } catch (_) {
      if (mounted) AppToast.show(context, 'リアクションに失敗しました');
    }
  }
}

/// 省略した表面（Figma 6269:12005 / 6308:12462）。180×286。
///
/// ジャケット 180 角の下に、アイコン・名前・曲名・アーティスト・リアクション。
/// 色は本物のカードと同じテーマ（保存済みのものか、ジャケットから抽出）。
class _CompactPostCard extends StatefulWidget {
  final PostModel post;
  final bool isMe;
  final bool hasPhoto;
  final List<String> reactionEmojis;

  const _CompactPostCard({
    required this.post,
    required this.isMe,
    required this.hasPhoto,
    required this.reactionEmojis,
  });

  @override
  State<_CompactPostCard> createState() => _CompactPostCardState();
}

class _CompactPostCardState extends State<_CompactPostCard> {
  PostTheme? _theme;

  @override
  void initState() {
    super.initState();
    if (widget.post.theme != PostTheme.defaultTheme) {
      _theme = widget.post.theme;
    } else {
      ColorExtractor.extractThemeFromAlbumArt(widget.post.track.albumImageUrl)
          .then((t) {
        if (mounted && t != null) setState(() => _theme = t);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = _theme ?? widget.post.theme;
    final post = widget.post;
    // 右上のバッジ。写真があればカメラを右端に、「あなた」はその左。
    final badgeRight = widget.hasPhoto ? 31.0 : 6.0;

    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Stack(
        children: [
          Positioned.fill(child: ColoredBox(color: theme.gradientEnd)),
          Positioned(
            left: 0,
            top: 0,
            width: 180,
            height: 180,
            child: post.track.albumImageUrl.isEmpty
                ? const ColoredBox(color: Color(0xFF3A363E))
                : CachedNetworkImage(
                    imageUrl: post.track.albumImageUrl,
                    fit: BoxFit.cover,
                    errorWidget: (_, __, ___) =>
                        const ColoredBox(color: Color(0xFF3A363E)),
                  ),
          ),
          // ジャケットの下端 5px に重ねて地の色へ溶かす（Figma: 上 3.77% で不透明）。
          Positioned(
            left: 0,
            right: 0,
            top: 175,
            height: 111,
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    theme.gradientEnd.withValues(alpha: 0),
                    theme.gradientEnd
                  ],
                  stops: const [0, 0.0377],
                ),
              ),
            ),
          ),
          Positioned(
            left: 12,
            top: 184,
            child: Container(
              width: 19,
              height: 19,
              decoration: const BoxDecoration(
                  shape: BoxShape.circle, color: Colors.black),
              child: ClipOval(
                child: ProfileImage(imageUrl: post.userIconUrl, size: 19),
              ),
            ),
          ),
          Positioned(
            left: 38,
            top: 186,
            right: badgeRight + 40,
            child: Text(
              post.username,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: theme.textColor,
                fontSize: 10,
                height: 1.2,
                letterSpacing: -0.1,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          if (widget.isMe)
            Positioned(
              right: badgeRight,
              top: 186,
              child: Container(
                width: 34,
                height: 17,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.7),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Text(
                  'あなた',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 7,
                    height: 1.2,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ),
          if (widget.hasPhoto)
            Positioned(
              right: 8,
              top: 186,
              child: SvgPicture.asset('assets/home_v2/camera_badge.svg',
                  width: 17, height: 17),
            ),
          Positioned(
            left: 12,
            top: 210,
            width: 160,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  post.track.trackName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: theme.textColor,
                    fontSize: 15,
                    height: 1.198,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  post.track.artistName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: theme.textColor,
                    fontSize: 12,
                    height: 1.5,
                  ),
                ),
              ],
            ),
          ),
          for (var i = 0; i < widget.reactionEmojis.length; i++)
            Positioned(
              left: 12 + 19.0 * i,
              top: 245,
              child: Text(widget.reactionEmojis[i],
                  style: const TextStyle(fontSize: 14, height: 1.2)),
            ),
          Positioned(
            left: 12,
            top: 268,
            child: Text(
              'Provided courtesy of Apple Music',
              style: TextStyle(
                color: theme.secondaryTextColor.withValues(alpha: 0.7),
                fontSize: 7,
                height: 1.0,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PillAction {
  final String label;
  final String emoji;
  final VoidCallback? onTap;
  const _PillAction(
      {required this.label, required this.emoji, required this.onTap});
}

/// まだ選んでいない人（Figma 6308:12354）。点線の枠にアイコン・名前・ボタン。
class _WaitingCard extends StatelessWidget {
  final String name;
  final String? avatarUrl;
  final _PillAction action;

  const _WaitingCard({
    required this.name,
    required this.avatarUrl,
    required this.action,
  });

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: const _DashedBorderPainter(),
      child: Stack(
        children: [
          Positioned(
            left: 61,
            top: 85,
            child: Container(
              width: 50,
              height: 50,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: Color(0xFFD9D9D9),
              ),
              child:
                  ClipOval(child: ProfileImage(imageUrl: avatarUrl, size: 50)),
            ),
          ),
          Positioned(
            left: 8,
            right: 16,
            top: 143,
            child: Text(
              name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: _rounded(16, Colors.white, 510),
            ),
          ),
          Positioned(
            left: 0,
            right: 4,
            top: 172,
            child: Text(
              'まだ選んでいません',
              textAlign: TextAlign.center,
              style: _rounded(12, _subGrey, 400),
            ),
          ),
          Positioned(
            left: 44,
            top: 199,
            width: 85,
            height: 32,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: action.onTap,
              child: Container(
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: const Color(0xFF252327),
                  borderRadius: BorderRadius.circular(30),
                ),
                child: Text.rich(
                  TextSpan(children: [
                    TextSpan(
                        text: '${action.emoji} ',
                        style: const TextStyle(fontSize: 16, height: 1.2)),
                    TextSpan(
                        text: action.label,
                        style: _rounded(13, Colors.white, 590)),
                  ]),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 友達を招待（Figma 6310:12480）。招待の仕組みは別途。
class _InviteCard extends StatelessWidget {
  const _InviteCard();

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: const _DashedBorderPainter(),
      child: Stack(
        children: [
          Positioned(
            left: 63,
            top: 85,
            child: IgnorePointer(
              child: GlassCircleButton(
                size: 50,
                onTap: () {},
                child: SvgPicture.asset('assets/home_v2/plus.svg',
                    width: 16, height: 16),
              ),
            ),
          ),
          Positioned(
            left: 0,
            right: 4,
            top: 156,
            child: Text(
              '友達を招待',
              textAlign: TextAlign.center,
              style: _rounded(14, Colors.white, 510),
            ),
          ),
        ],
      ),
    );
  }
}

/// 2px の点線の角丸枠（Figma: border-2 dashed #5C5762, radius 8）。
class _DashedBorderPainter extends CustomPainter {
  const _DashedBorderPainter();

  static const double _stroke = 2;
  static const double _dash = 4;
  static const double _gap = 4;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = _dashColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = _stroke;
    final rrect = RRect.fromRectAndRadius(
      Rect.fromLTWH(_stroke / 2, _stroke / 2, size.width - _stroke,
          size.height - _stroke),
      const Radius.circular(8),
    );
    final path = Path()..addRRect(rrect);
    for (final metric in path.computeMetrics()) {
      var d = 0.0;
      while (d < metric.length) {
        canvas.drawPath(metric.extractPath(d, d + _dash), paint);
        d += _dash + _gap;
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

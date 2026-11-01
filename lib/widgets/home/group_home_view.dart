import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../constants/profile_fonts.dart';
import '../../models/group_model.dart';
import '../../models/post_model.dart';
import '../../models/track_model.dart';
import '../../services/group_service.dart';
import '../../services/poke_service.dart';
import '../common/glass_circle_button.dart';
import '../notification_badge.dart';

/// 新しいホーム（グループ一覧）。
///
///   投稿前  Figma 6206:11652  「今日の1曲を選ぼう」＋ぼかしたジャケット
///   投稿後  Figma 6275:12082  「あなたの今日の1曲」＋はっきりしたジャケット
///
/// 投稿したかは自分の今のサイクルの投稿を購読して決める
/// （[GroupService.watchMyCyclePost]）。投稿した瞬間に投稿後へ切り替わる。
///
/// 寸法は Figma の 402 幅のまま持ち、カードごとに画面幅へ拡縮する。
/// 上端は Figma の安全領域（62）を引いて、端末の安全領域に載せ替える。
class GroupHomeView extends StatefulWidget {
  final String uid;

  /// 今のサイクルの始まり（21:00）。変わったら購読を張り直す。
  final DateTime cycleStart;

  /// 今のサイクルの鍵。届いたつつきを引くのに使う。null なら引かない。
  final String? cycleKey;

  /// 投稿前のカードに並べる最近聴いた曲（先頭 3 曲を使う）。
  /// null は読み込み中、空は取れない（Spotify・未連携など）。
  final List<TrackModel>? recentTracks;

  /// 「今日聴いた15曲から選ぶ」。既存の曲選び（左スライドのカルーセル）へ。
  final VoidCallback onChooseTrack;
  final VoidCallback onOpenMusicMemory;
  final VoidCallback onOpenProfile;
  final VoidCallback onOpenNotifications;
  final VoidCallback onCreateGroup;
  final void Function(GroupModel group) onOpenGroup;

  /// Firebase 抜きで見た目を確かめるための差し替え（テスト用）。
  @visibleForTesting
  final Stream<List<GroupModel>>? debugGroups;
  @visibleForTesting
  final Stream<PostModel?>? debugMyPost;
  @visibleForTesting
  final Future<GroupCycleStatus> Function(GroupModel)? debugStatusOf;
  @visibleForTesting
  final Stream<List<PokeEntry>>? debugPokes;

  const GroupHomeView({
    super.key,
    required this.uid,
    required this.cycleStart,
    this.cycleKey,
    required this.recentTracks,
    required this.onChooseTrack,
    required this.onOpenMusicMemory,
    required this.onOpenProfile,
    required this.onOpenNotifications,
    required this.onCreateGroup,
    required this.onOpenGroup,
    this.debugGroups,
    this.debugMyPost,
    this.debugStatusOf,
    this.debugPokes,
  });

  @override
  State<GroupHomeView> createState() => _GroupHomeViewState();
}

// ── デザイン定数（Figma の実数値）────────────────────────────

const double _designW = 402;

/// Figma の上端の安全領域。座標からこれを引いて端末の安全領域に載せる。
const double _designTopInset = 62;

const Color _bg = Color(0xFF121212);
const Color _rowBg = Color(0xFF28262B);
const Color _subGrey = Color(0xFF9B94A0);
const Color _artistGrey = Color(0xFF8F8894);

/// 1 行に重ねるジャケットの最大数（Figma は 6 人のグループで 5 枚）。
const int _maxJackets = 5;

/// 今日の 1 曲のカードに出すリアクションの最大数。
/// 「Music Memoryを見る ›」に重ならない数。
const int _maxReactions = 4;

/// SF Pro Rounded は可変フォントなので fontWeight だけでは細く出る。
/// Figma の太さを wght で渡す（日本語はフォールバックの Hiragino になる）。
TextStyle _rounded(double size, Color color, double wght) => TextStyle(
      fontFamily: kSfProRounded,
      fontSize: size,
      color: color,
      height: 1.2,
      fontWeight: wght >= 700 ? FontWeight.bold : FontWeight.normal,
      fontVariations: [ui.FontVariation('wght', wght)],
    );

/// 日本語の見出し（Figma は Noto Sans。iOS では Hiragino で出す）。
TextStyle _jp(double size, Color color, {bool bold = false}) => TextStyle(
      fontSize: size,
      color: color,
      height: 1.2,
      fontWeight: bold ? FontWeight.bold : FontWeight.normal,
    );

/// グループの人から付いたリアクションを、多い順に絵文字だけ並べる。
///
/// - 数えるのは [groupmates]（自分の全グループのメンバー）からのものだけ。
/// - 同じ絵文字は 1 つにまとめ、数は出さない。
/// - 同数なら新しく付いた方を先にする。
List<String> groupReactionEmojis(
  List<PostReaction> reactions,
  Set<String> groupmates, {
  int max = _maxReactions,
}) {
  final counts = <String, int>{};
  final latest = <String, int>{};
  for (final r in reactions) {
    if (!groupmates.contains(r.userId)) continue;
    counts[r.emoji] = (counts[r.emoji] ?? 0) + 1;
    latest[r.emoji] = math.max(latest[r.emoji] ?? 0, r.ts);
  }
  final emojis = counts.keys.toList()
    ..sort((a, b) {
      final byCount = counts[b]!.compareTo(counts[a]!);
      if (byCount != 0) return byCount;
      return latest[b]!.compareTo(latest[a]!);
    });
  return emojis.take(max).toList();
}

class _GroupHomeViewState extends State<GroupHomeView> {
  late final GroupService _groupService = GroupService();

  late Stream<List<GroupModel>> _groupsStream;
  late Stream<PostModel?> _myPostStream;
  late Stream<List<PokeEntry>> _pokesStream;

  /// グループごとの今のサイクルの状況。引っ張って更新したら作り直す。
  final Map<String, Future<GroupCycleStatus>> _statusFutures = {};

  @override
  void initState() {
    super.initState();
    _subscribe();
  }

  @override
  void didUpdateWidget(GroupHomeView old) {
    super.didUpdateWidget(old);
    if (old.uid != widget.uid ||
        old.cycleStart != widget.cycleStart ||
        old.cycleKey != widget.cycleKey) {
      _subscribe();
    }
  }

  void _subscribe() {
    _groupsStream =
        widget.debugGroups ?? _groupService.watchMyGroups(widget.uid);
    _myPostStream =
        widget.debugMyPost ?? _groupService.watchMyCyclePost(widget.uid);
    final key = widget.cycleKey;
    _pokesStream = widget.debugPokes ??
        (key == null
            ? Stream.value(const <PokeEntry>[])
            : PokeService.instance.watchPokesToMe(widget.uid, key));
    _statusFutures.clear();
  }

  Future<void> _refresh() async {
    setState(_statusFutures.clear);
  }

  Future<GroupCycleStatus> _statusOf(GroupModel g) {
    // メンバーが変わったら取り直す。
    final key = '${g.groupId}:${g.memberIds.join(',')}';
    return _statusFutures.putIfAbsent(
        key,
        () => widget.debugStatusOf?.call(g) ?? _groupService.loadCycleStatus(g));
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final scale = media.size.width / _designW;

    return ColoredBox(
      color: _bg,
      child: StreamBuilder<PostModel?>(
        stream: _myPostStream,
        builder: (context, mySnap) {
          final myPost = mySnap.data;
          final posted = myPost != null;
          return StreamBuilder<List<GroupModel>>(
            stream: _groupsStream,
            builder: (context, groupSnap) {
              final groups = groupSnap.data ?? const <GroupModel>[];
              final mates = {
                for (final g in groups) ...g.memberIds,
              }..remove(widget.uid);

              return Stack(
                children: [
                  CustomScrollView(
                    physics: const BouncingScrollPhysics(
                      parent: AlwaysScrollableScrollPhysics(),
                    ),
                    slivers: [
                      SliverToBoxAdapter(
                        child: SizedBox(height: media.padding.top),
                      ),
                      CupertinoSliverRefreshControl(onRefresh: _refresh),
                      // Figma の y=62〜142（安全領域の下から今日の 1 曲のカードまで）。
                      SliverToBoxAdapter(
                        child: _scaled(scale, _header(), height: 80),
                      ),
                      SliverToBoxAdapter(
                        child: _scaled(
                          scale,
                          posted
                              ? _postedCard(myPost, mates)
                              : StreamBuilder<List<PokeEntry>>(
                                  stream: _pokesStream,
                                  builder: (context, snap) => _chooseCard(
                                    pokedBy: snap.data?.firstOrNull?.fromName,
                                  ),
                                ),
                          height: posted ? 120 : 306,
                        ),
                      ),
                      SliverToBoxAdapter(
                        child: SizedBox(height: (posted ? 27 : 23) * scale),
                      ),
                      SliverToBoxAdapter(
                        child: _scaled(scale, _groupsHeading(posted), height: 26),
                      ),
                      SliverToBoxAdapter(
                        child: SizedBox(height: (posted ? 5 : 11) * scale),
                      ),
                      if (groupSnap.hasData && groups.isEmpty)
                        SliverToBoxAdapter(
                          child: _scaled(scale, _noGroups(), height: 80),
                        ),
                      SliverList.separated(
                        itemCount: groups.length,
                        separatorBuilder: (_, __) =>
                            SizedBox(height: (posted ? 18 : 12) * scale),
                        itemBuilder: (context, i) => _scaled(
                          scale,
                          _groupRow(groups[i], blurJackets: !posted),
                          height: 80,
                        ),
                      ),
                      // 下のボタンに最後の行が隠れないだけの余白。
                      SliverToBoxAdapter(
                        child: SizedBox(height: 120 * scale + media.padding.bottom),
                      ),
                    ],
                  ),
                  _bottomButtons(scale, media.padding.bottom),
                ],
              );
            },
          );
        },
      ),
    );
  }

  /// Figma の 402 幅で組んだものを画面幅に拡縮する。
  Widget _scaled(double scale, Widget child, {required double height}) {
    return SizedBox(
      height: height * scale,
      child: FittedBox(
        fit: BoxFit.fitWidth,
        alignment: Alignment.topLeft,
        // Align で緩めないと、中の幅指定（368 など）が 402 幅に引き伸ばされる。
        child: SizedBox(
          width: _designW,
          height: height,
          child: Align(alignment: Alignment.topLeft, child: child),
        ),
      ),
    );
  }

  // ── ヘッダー（15s ＋ 日付）──────────────────────────────

  /// Figma の y=62〜142。「15s」(16,68)、日付 (16,116)、
  /// 右上にカレンダー（Music Memory）(284,70) とプロフィール (339,70)。
  Widget _header() {
    final now = DateTime.now();
    // 日付は「今日の曲」のサイクルの日（21:00 に始まった日）。
    final d = widget.cycleStart.isAfter(now) ? now : widget.cycleStart;
    const weekdays = ['月', '火', '水', '木', '金', '土', '日'];
    final dateText =
        '${d.month}月${d.day}日 （${weekdays[d.weekday - 1]}）今日の曲が届いています';
    return Stack(
      children: [
        Positioned(
          left: 16,
          top: 68 - _designTopInset,
          child: Text('15s', style: _rounded(40, Colors.white, 700)),
        ),
        Positioned(
          left: 16,
          top: 116 - _designTopInset,
          child: Text(dateText, style: _rounded(14, _subGrey, 400)),
        ),
        Positioned(
          left: 284,
          top: 70 - _designTopInset,
          child: GlassCircleButton(
            size: 44,
            onTap: widget.onOpenMusicMemory,
            child: const Icon(CupertinoIcons.calendar,
                color: Colors.white, size: 22),
          ),
        ),
        Positioned(
          left: 339,
          top: 70 - _designTopInset,
          child: GlassCircleButton(
            size: 44,
            onTap: widget.onOpenProfile,
            child: const Icon(Icons.person_outline_rounded,
                color: Colors.white, size: 26),
          ),
        ),
      ],
    );
  }

  // ── 投稿前：今日の1曲を選ぼう（Figma 6269:12007）───────────

  /// [pokedBy] は直近につついてきた人の名前。右上に小さく出す。
  Widget _chooseCard({String? pokedBy}) {
    final tracks = widget.recentTracks;
    return Padding(
      padding: const EdgeInsets.only(left: 17),
      child: Container(
        width: 368,
        height: 306,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(25),
          gradient: const LinearGradient(
            colors: [Color(0xFF29232F), Color(0xFF211E25)],
          ),
        ),
        child: Stack(
          children: [
            Positioned(
              left: 15,
              top: 18,
              child: Text('今日の1曲を選ぼう', style: _jp(20, Colors.white, bold: true)),
            ),
            if (pokedBy != null && pokedBy.isNotEmpty)
              Positioned(
                right: 15,
                top: 24,
                width: 150,
                child: Text(
                  '$pokedByがつついています👉',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.right,
                  style: _rounded(12, const Color(0xFFB3ABB8), 400),
                ),
              ),
            Positioned(
              left: 15,
              top: 51,
              child: Text('選ぶと、みんなの曲が見れるようになります',
                  style: _jp(13, const Color(0xFFB3ABB8))),
            ),
            for (var i = 0; i < 3; i++)
              Positioned(
                left: 15 + 116.0 * i,
                top: 85,
                width: 105,
                height: 143,
                child: _recentTile(
                  (tracks != null && i < tracks.length) ? tracks[i] : null,
                ),
              ),
            Positioned(
              left: 15,
              top: 244,
              width: 337,
              height: 46,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: widget.onChooseTrack,
                child: Container(
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(33),
                  ),
                  child: Text('今日聴いた15曲から選ぶ',
                      style: _jp(15, Colors.black, bold: true)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 最近聴いた曲 1 曲（105 角＋曲名 11 / アーティスト 10）。
  /// 曲が無いとき（読み込み中・取れない）は枠だけ出す。
  Widget _recentTile(TrackModel? track) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: widget.onChooseTrack,
      child: Stack(
        children: [
          Positioned(
            left: 0,
            top: 0,
            width: 105,
            height: 105,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: _artwork(track?.albumImageUrl, const Color(0xFF3A363E)),
            ),
          ),
          if (track != null) ...[
            Positioned(
              left: 0,
              top: 111,
              width: 105,
              child: Text(track.trackName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: _jp(11, Colors.white)),
            ),
            Positioned(
              left: 0,
              top: 129,
              width: 105,
              child: Text(track.artistName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: _jp(10, _artistGrey)),
            ),
          ],
        ],
      ),
    );
  }

  // ── 投稿後：あなたの今日の1曲（Figma 6275:12289）────────────

  Widget _postedCard(PostModel post, Set<String> mates) {
    final emojis = groupReactionEmojis(post.reactions, mates);
    return Padding(
      padding: const EdgeInsets.only(left: 17),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onOpenMusicMemory,
        child: Container(
          width: 368,
          height: 120,
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(25),
            gradient: const LinearGradient(
              colors: [Color(0xFF293643), Color(0xFF1E1C22)],
            ),
          ),
          child: Stack(
            children: [
              Positioned(
                left: 14,
                top: 20,
                width: 81,
                height: 81,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: _artwork(post.track.albumImageUrl, const Color(0xFF3A363E)),
                ),
              ),
              Positioned(
                left: 107,
                top: 14,
                child: Text('あなたの今日の1曲',
                    style: _jp(12, const Color(0xFF9FC3DC), bold: true)),
              ),
              Positioned(
                left: 107,
                top: 35,
                right: 14,
                child: Text(post.track.trackName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: _jp(20, Colors.white, bold: true)),
              ),
              Positioned(
                left: 107,
                top: 62,
                right: 14,
                child: Text(post.track.artistName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: _jp(13, _artistGrey)),
              ),
              Positioned(
                left: 107,
                top: 88,
                child: Row(
                  children: [
                    Text('Music Memoryを見る',
                        style: _rounded(13, const Color(0xFFD9D3DD), 400)),
                    const SizedBox(width: 6),
                    SvgPicture.asset('assets/home_v2/chevron_small.svg',
                        width: 7, height: 12),
                  ],
                ),
              ),
              // リアクションは右寄せで、左から多い順（Figma は 28 間隔、右端 358）。
              for (var i = 0; i < emojis.length; i++)
                Positioned(
                  left: 338 - 28.0 * (emojis.length - 1 - i),
                  top: 86,
                  child: Text(emojis[i],
                      style: const TextStyle(fontSize: 20, height: 1.2)),
                ),
            ],
          ),
        ),
      ),
    );
  }

  // ── グループ一覧 ─────────────────────────────────────

  /// 「グループ」(26,471)。投稿前は右に鍵＋「投稿するとジャケットがはっきり見えます」。
  Widget _groupsHeading(bool posted) {
    return Stack(
      children: [
        Positioned(
          left: 26,
          top: 0,
          child: Text('グループ', style: _jp(18, Colors.white, bold: true)),
        ),
        if (!posted)
          Positioned(
            right: 21,
            top: 5,
            child: Row(
              children: [
                const Icon(Icons.lock_outline, size: 12, color: _subGrey),
                const SizedBox(width: 2),
                Text('投稿するとジャケットがはっきり見えます',
                    style: _rounded(12, _subGrey, 400)),
              ],
            ),
          ),
      ],
    );
  }

  Widget _noGroups() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Container(
        width: 369,
        height: 80,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: _rowBg,
          borderRadius: BorderRadius.circular(19),
        ),
        child: Text('まだグループがありません', style: _rounded(14, _subGrey, 400)),
      ),
    );
  }

  /// グループ 1 行（Figma 6275:12172）。369×80。
  Widget _groupRow(GroupModel group, {required bool blurJackets}) {
    return Padding(
      padding: const EdgeInsets.only(left: 16),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => widget.onOpenGroup(group),
        child: Container(
          width: 369,
          height: 80,
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: _rowBg,
            borderRadius: BorderRadius.circular(19),
          ),
          child: FutureBuilder<GroupCycleStatus>(
            future: _statusOf(group),
            builder: (context, snap) {
              final status = snap.data;
              final members = group.memberIds.length;
              final postedCount = status?.postedCount ?? 0;
              // 自分の分は数に入れるが、ジャケットには出さない（上のカードにある）。
              final jackets = [
                for (final e in (status?.postsByMember.entries ??
                    const <MapEntry<String, PostModel>>[]))
                  if (e.key != widget.uid) e.value,
              ]..sort((a, b) => a.createdAt.compareTo(b.createdAt));
              final shown = jackets.length > _maxJackets
                  ? jackets.sublist(jackets.length - _maxJackets)
                  : jackets;

              return Stack(
                children: [
                  Positioned(
                    left: 16,
                    top: 14,
                    width: 170,
                    child: Text(group.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: _rounded(16, Colors.white, 700)),
                  ),
                  Positioned(
                    left: 15,
                    top: 38,
                    child: Text.rich(
                      TextSpan(children: [
                        TextSpan(
                            text: '$postedCount',
                            style: _rounded(14, Colors.white, 590)),
                        TextSpan(
                            text: '/$members人が投稿',
                            style: _rounded(12, _subGrey, 400)),
                      ]),
                    ),
                  ),
                  // 人数ぶんの目盛り。投稿した人数だけ明るくする。
                  for (var i = 0; i < members; i++)
                    Positioned(
                      left: 16 + 17.8 * i,
                      top: 64,
                      child: SvgPicture.asset(
                        i < postedCount
                            ? 'assets/home_v2/dash_posted.svg'
                            : 'assets/home_v2/dash_waiting.svg',
                        width: 14,
                        height: 4,
                      ),
                    ),
                  // ジャケットは右端 294 から左へ重ねる。新しい投稿ほど右。
                  for (var i = 0; i < shown.length; i++)
                    Positioned(
                      left: 294 - 25.5 * (shown.length - 1 - i),
                      top: 21,
                      child: _jacket(shown[i].track.albumImageUrl, blur: blurJackets),
                    ),
                  const Positioned(left: 343, top: 33, child: _RowChevron()),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  /// 38 角、枠 2（行の地の色）、角丸 8。投稿前はぼかす（Figma blur 2）。
  Widget _jacket(String url, {required bool blur}) {
    Widget image = ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: _artwork(url, const Color(0xFF3A363E)),
    );
    if (blur) {
      image = ImageFiltered(
        imageFilter: ui.ImageFilter.blur(sigmaX: 2, sigmaY: 2),
        child: image,
      );
    }
    return Container(
      width: 38,
      height: 38,
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: _rowBg,
        borderRadius: BorderRadius.circular(8),
      ),
      child: image,
    );
  }

  Widget _artwork(String? url, Color placeholder) {
    if (url == null || url.isEmpty) return ColoredBox(color: placeholder);
    return CachedNetworkImage(
      imageUrl: url,
      fit: BoxFit.cover,
      placeholder: (_, __) => ColoredBox(color: placeholder),
      errorWidget: (_, __, ___) => ColoredBox(color: placeholder),
    );
  }

  // ── ボタン ──────────────────────────────────────────

  /// 未読バッジは Firebase を読むので、テストの差し替え中は付けない。
  Widget _maybeBadge(Widget child) =>
      widget.debugGroups != null ? child : NotificationBadge(child: child);

  /// 左下：通知 (36,785)、右下：グループ作成 (316,785)。50 角。
  Widget _bottomButtons(double scale, double bottomInset) {
    // Figma は下端から 39（874 - 835）。ホームインジケータの分は Figma に含まれている。
    final bottom = math.max(39 * scale, bottomInset + 5);
    return Positioned(
      left: 36 * scale,
      right: 36 * scale,
      bottom: bottom,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          _maybeBadge(
            GlassCircleButton(
              size: 50 * scale,
              onTap: widget.onOpenNotifications,
              child: Icon(Icons.notifications_none_rounded,
                  color: Colors.white, size: 26 * scale),
            ),
          ),
          GlassCircleButton(
            size: 50 * scale,
            onTap: widget.onCreateGroup,
            child: SvgPicture.asset('assets/home_v2/plus.svg',
                width: 16 * scale, height: 16 * scale),
          ),
        ],
      ),
    );
  }
}

/// 行の右端の「›」。Figma は 9.9 の線 2 本を ±45° に回したもの（7 角の箱）。
class _RowChevron extends StatelessWidget {
  const _RowChevron();

  @override
  Widget build(BuildContext context) {
    Widget line(String asset, double angle) => Transform.rotate(
          angle: angle,
          alignment: Alignment.centerRight,
          child: SvgPicture.asset(asset, width: 10.9, height: 2),
        );
    return SizedBox(
      width: 10.9,
      height: 14,
      child: Stack(
        children: [
          Positioned(top: 6, child: line('assets/home_v2/chevron_line_down.svg', math.pi / 4)),
          Positioned(top: 6, child: line('assets/home_v2/chevron_line_up.svg', -math.pi / 4)),
        ],
      ),
    );
  }
}

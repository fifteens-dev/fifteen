import 'dart:math' as math;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../constants/profile_fonts.dart';
import '../models/profile_snapshot.dart';
import '../utils/album_image.dart';
import 'profile_widgets.dart';

/// 投稿カードの裏面（写真がない日。Figma 6187-11425）。
///
/// 投稿者の「その時点でよく聴いていた音楽」を見せる面。中身はプロフィール画面の
/// top artists / recent choice と同じで、値は投稿時に焼き込んだ
/// [ProfileSnapshot] を使う（あとから集計し直さない）。
///
/// カードは 363×645 固定。表面と同じ寸法なので、呼び出し側で拡縮しない。
class PostCardBackProfile extends StatelessWidget {
  /// 投稿者の表示名。
  final String name;

  /// 投稿者の @ID。
  final String? username;

  /// 投稿者のアイコン。
  final String? avatarUrl;

  /// 投稿時点の top artists / recent choice。
  final ProfileSnapshot snapshot;

  /// ピルに出す文言（「2人の共通」「友達 5人」など）。null なら出さない。
  final String? pillLabel;

  /// ピルに重ねるアイコン（先頭 2 人ぶん）。
  final List<String?> pillAvatars;

  /// 面の地色。表面と同じカード色を渡す。
  final Color background;

  /// 文字・見出しの色。地色に対して読める色を渡す（PostTheme.textColor）。
  final Color foreground;

  /// 曲のアーティスト名など、控えめに出す文字の色。
  final Color mutedForeground;

  const PostCardBackProfile({
    super.key,
    required this.name,
    required this.username,
    required this.avatarUrl,
    required this.snapshot,
    this.pillLabel,
    this.pillAvatars = const [],
    this.background = Colors.black,
    this.foreground = Colors.white,
    this.mutedForeground = _trackArtist,
  });

  static const double cardWidth = 363;
  static const double cardHeight = 645;

  static const double _tile = 105;

  /// top artists の丸タイルの左端。Figma ではグループが 17 から始まる。
  static const List<double> _artistLefts = [17, 133, 249];

  /// recent choice のジャケットの左端。
  static const List<double> _trackLefts = [18, 134, 250];

  /// 見出しの縦グラデーション。Figma は黒 → #3B3437 で、その途中の色を
  /// 黒からの割合に直したもの（#110E10 ≒ 0.29、#241D20 ≒ 0.61）。
  static const List<double> _headingStops = [0.289, 0.443, 0.623, 0.803];
  static const List<double> _headingMix = [0, 0.29, 0.61, 1];
  static const Color _headingFade = Color(0xFF3B3437);

  static const Color _trackArtist = Color(0xFF525252);

  /// タイルに共通の落ち影。1 位だけ黄緑の光を足す。
  static const List<BoxShadow> _tileShadow = [
    BoxShadow(color: Color(0x2E000000), offset: Offset(0, 4), blurRadius: 12),
    BoxShadow(color: Color(0x47000000), offset: Offset(0, 14), blurRadius: 32),
  ];

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: cardWidth,
      height: cardHeight,
      // 角丸は付けない。この面は FittedBox で拡縮されるので、ここで丸めると
      // 半径まで一緒に縮んで表面と合わなくなる。カード側（PostCard）が
      // 拡縮されない半径で切る。
      child: ColoredBox(
        color: background,
        child: Stack(
          children: [
            _avatar(),
            _name(),
            _handle(),
            if (pillLabel != null) _pill(),
            ..._topArtists(),
            ..._recentChoice(),
          ],
        ),
      ),
    );
  }

  // ── 投稿者 ─────────────────────────────────────────────

  Widget _avatar() {
    return Positioned(
      left: 137.5,
      top: 58,
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
      // Figma の中心は 182（アイコン枠 130 + 52）。
      left: 20,
      right: 19,
      top: 154,
      child: Text(
        name,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        textAlign: TextAlign.center,
        style: TextStyle(
          color: foreground,
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
      right: 21,
      top: 183,
      child: Text(
        (handle == null || handle.isEmpty) ? '' : '@$handle',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        textAlign: TextAlign.center,
        style: TextStyle(
          color: foreground,
          fontSize: 15,
          height: 1.2,
          fontWeight: FontWeight.w600,
          fontFamily: kSfProRounded,
        ),
      ),
    );
  }

  /// 共通の友達（他人の投稿）や友達の人数（自分の投稿）を出すピル。
  Widget _pill() {
    return Positioned(
      left: 95,
      top: 184,
      width: 174,
      height: 52,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: const Color(0xFF262626).withValues(alpha: 0.72),
          borderRadius: BorderRadius.circular(15),
        ),
        child: Stack(
          children: [
            // 傾けた 30px の円。Figma は 34.544 の枠の中央に置いており、
            // その中心は (33.17, 26.12)。回転は中心まわりなので、
            // 円の左上を中心 −15 に置く。
            Positioned(
              left: 18.17,
              top: 11.12,
              child: Transform.rotate(
                angle: -9.51 * math.pi / 180,
                child: _pillAvatar(pillAvatars.elementAtOrNull(0)),
              ),
            ),
            Positioned(
              left: 44,
              top: 11,
              child: _pillAvatar(pillAvatars.elementAtOrNull(1)),
            ),
            // Figma はピル内の中心 126.5、上から 18。
            // 幅 174 の中で中心を 126.5 にするには、左右の余白を
            // 79.5 / 0.5 にする（(79.5 + 173.5) / 2 = 126.5）。
            Positioned(
              left: 79.5,
              right: 0.5,
              top: 18,
              child: Text(
                pillLabel!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  // ピルの地色は固定の濃いグレーなので、文字は白のまま。
                  // カードの色に合わせると明るいアルバムで読めなくなる。
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

  /// 見出し（top artists / recent choice）。
  ///
  /// Figma は SF Pro Heavy の文字に、上から下へ少し明るくなる
  /// グラデーションと落ち影を付けている。黒地の色はそのまま、
  /// 地色に合わせて [foreground] から同じ割合で薄めていく
  /// （foreground が黒なら Figma と同じ色になる）。
  ///
  /// [centerX] を中心に置き、幅は切らない（recent choice はカードより
  /// 広く、両端がカードの縁で切れるのが Figma 通り）。
  Widget _heading(
    String text, {
    required double top,
    required double centerX,
    required double fontSize,
  }) {
    final lineHeight = fontSize * 1.2;
    final colors = [
      for (final t in _headingMix) Color.lerp(foreground, _headingFade, t)!,
    ];
    return Positioned(
      left: centerX - 300,
      width: 600,
      top: top,
      child: Text(
        text,
        maxLines: 1,
        softWrap: false,
        overflow: TextOverflow.visible,
        textAlign: TextAlign.center,
        style: TextStyle(
          fontSize: fontSize,
          height: 1.2,
          letterSpacing: fontSize * 0.01,
          fontWeight: FontWeight.w800,
          foreground: Paint()
            ..shader = LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: colors,
              stops: _headingStops,
            ).createShader(Rect.fromLTWH(0, 0, 600, lineHeight)),
          shadows: const [
            Shadow(
              color: Color(0x38000000),
              offset: Offset(0, 6),
              blurRadius: 18,
            ),
          ],
        ),
      ),
    );
  }

  // ── top artists ───────────────────────────────────────

  List<Widget> _topArtists() {
    final artists = snapshot.topArtists;
    return [
      _heading('top artists', top: 212, centerX: 185.5, fontSize: 60),
      for (var i = 0; i < 3; i++) ...[
        Positioned(
          left: _artistLefts[i],
          top: 261,
          child: Container(
            width: _tile,
            height: _tile,
            decoration: BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
              boxShadow: [
                if (i == 0)
                  const BoxShadow(color: Color(0x1FD5F94B), blurRadius: 24),
                ..._tileShadow,
              ],
            ),
            child: ClipOval(
              child: _networkOrPlaceholder(
                i < artists.length ? artists[i].imageUrl : null,
                Icons.person,
              ),
            ),
          ),
        ),
        // 順位の数字。タイルに重なるので後に描く。
        _rankNumeral(i),
        Positioned(
          left: _artistLefts[i] - 12,
          top: 381,
          width: _tile + 24,
          child: Text(
            i < artists.length ? artists[i].name : '',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: foreground,
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

  /// 順位の数字。プロフィール画面と同じ白抜きの素材を、Figma 通り白のまま使う。
  /// 素材は 4x なので高さ = canvas/4、下端をベースライン（365）に揃える。
  /// ベースラインは Figma の数字（60px、上端 308）から求めた値で、
  /// タイルの下端（261 + 105 = 366）とほぼ同じ。
  Widget _rankNumeral(int index) {
    const heights = [178 / 4, 181 / 4, 184 / 4];
    const centers = [112.0, 225.0, 334.0];
    final h = heights[index];
    return Positioned(
      left: centers[index] - 40,
      top: 365 - h,
      width: 80,
      child: Center(
        child: Image.asset(
          'assets/profile_v2/rank_${index + 1}.png',
          height: h,
        ),
      ),
    );
  }

  // ── recent choice ─────────────────────────────────────

  List<Widget> _recentChoice() {
    final tracks = snapshot.recentTracks;
    return [
      // カードより広く、両端が縁で切れる（Figma も同じ）。
      _heading('recent choice', top: 410, centerX: 181.5, fontSize: 55),
      for (var i = 0; i < 3; i++) ...[
        Positioned(
          left: _trackLefts[i],
          top: 457,
          child: Container(
            width: _tile,
            height: _tile,
            decoration: const BoxDecoration(boxShadow: _tileShadow),
            child: _albumOrPlaceholder(
                i < tracks.length ? tracks[i].albumImageUrl : ''),
          ),
        ),
        Positioned(
          left: _trackLefts[i] - 12,
          top: 571,
          width: _tile + 24,
          child: Text(
            i < tracks.length ? tracks[i].trackName : '',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: foreground,
              fontSize: 13,
              height: 1.2,
              letterSpacing: 0.13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        Positioned(
          left: _trackLefts[i] - 12,
          top: 590,
          width: _tile + 24,
          child: Text(
            i < tracks.length ? tracks[i].artistName : '',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: mutedForeground,
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

  // ── 部品 ──────────────────────────────────────────────

  Widget _networkOrPlaceholder(String? url, IconData icon) {
    if (url == null || url.isEmpty) return _placeholder(icon);
    return CachedNetworkImage(
      imageUrl: url,
      fit: BoxFit.cover,
      errorWidget: (_, __, ___) => _placeholder(icon),
    );
  }

  Widget _albumOrPlaceholder(String url) {
    if (url.isEmpty) return _placeholder(Icons.music_note);
    return Image(
      image: albumImageProvider(url),
      width: _tile,
      height: _tile,
      fit: BoxFit.cover,
      errorBuilder: (_, __, ___) => _placeholder(Icons.music_note),
    );
  }

  Widget _placeholder(IconData icon) => Container(
        color: const Color(0xFF2A2A2A),
        alignment: Alignment.center,
        child: Icon(icon, color: Colors.white24, size: 34),
      );
}

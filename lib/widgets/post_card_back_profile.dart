import 'dart:math' as math;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../constants/profile_fonts.dart';
import '../models/profile_snapshot.dart';
import '../utils/album_image.dart';
import 'profile_widgets.dart';

/// 投稿カードの裏面（Figma 5787-12995）。
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

  const PostCardBackProfile({
    super.key,
    required this.name,
    required this.username,
    required this.avatarUrl,
    required this.snapshot,
    this.pillLabel,
    this.pillAvatars = const [],
  });

  static const double cardWidth = 363;
  static const double cardHeight = 645;

  static const double _tile = 105;
  static const List<double> _tileLefts = [18, 134, 250];

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
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: ColoredBox(
          color: Colors.black,
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
      ),
    );
  }

  // ── 投稿者 ─────────────────────────────────────────────

  Widget _avatar() {
    return Positioned(
      left: 137.5,
      top: 36,
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
      top: 132,
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
      top: 161,
      child: Text(
        (handle == null || handle.isEmpty) ? '' : '@$handle',
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
            Positioned(
              left: 15.9,
              top: 13.8,
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
            Positioned(
              left: 82,
              right: 8,
              top: 17,
              child: Text(
                pillLabel!,
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

  // ── top artists ───────────────────────────────────────

  List<Widget> _topArtists() {
    final artists = snapshot.topArtists;
    return [
      // 見出しは書き出し素材をそのまま使う（4x）。位置は Figma の
      // 書き出し（Frame 840）と重ね合わせて割り出した実測値。
      const Positioned(
        left: 25,
        top: 248.5,
        child: Image(
          image: AssetImage('assets/card_back/title_top_artists.png'),
          width: 322.75,
          height: 82,
        ),
      ),
      for (var i = 0; i < 3; i++) ...[
        Positioned(
          left: _tileLefts[i],
          top: 295,
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
          left: _tileLefts[i] - 12,
          top: 415,
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

  /// 白抜きの順位数字。プロフィール画面と同じ素材を使う。
  /// 素材は 4x なので高さ = canvas/4、下端をベースライン（399）に揃える。
  Widget _rankNumeral(int index) {
    const heights = [178 / 4, 181 / 4, 184 / 4];
    const centers = [113.0, 226.0, 335.0];
    final h = heights[index];
    return Positioned(
      left: centers[index] - 40,
      top: 399 - h,
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
      // 左右はカード幅いっぱいで、素材の時点で両端が切れている（Figma も同じ）。
      const Positioned(
        left: 0,
        top: 440,
        child: Image(
          image: AssetImage('assets/card_back/title_recent_choice.png'),
          width: 363,
          height: 68.5,
        ),
      ),
      for (var i = 0; i < 3; i++) ...[
        Positioned(
          left: _tileLefts[i],
          top: 485,
          child: Container(
            width: _tile,
            height: _tile,
            decoration: const BoxDecoration(boxShadow: _tileShadow),
            child: _albumOrPlaceholder(
                i < tracks.length ? tracks[i].albumImageUrl : ''),
          ),
        ),
        Positioned(
          left: _tileLefts[i] - 12,
          top: 599,
          width: _tile + 24,
          child: Text(
            i < tracks.length ? tracks[i].trackName : '',
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
          left: _tileLefts[i] - 12,
          top: 618,
          width: _tile + 24,
          child: Text(
            i < tracks.length ? tracks[i].artistName : '',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: _trackArtist,
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

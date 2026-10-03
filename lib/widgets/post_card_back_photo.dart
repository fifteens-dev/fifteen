import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../utils/album_image.dart';
import 'profile_widgets.dart';

/// 投稿カードの裏面（写真）— Figma 5847-11283。
///
/// 自分のカレンダーから開いたときだけ出る面。写真を全面に敷き、上に
/// 投稿者・曲名・リアクションを重ねる。
///
/// ## 座標について
/// Figma は 1089×1935 で作られている。カード実寸（363×645）のちょうど 3 倍
/// なので、すべての値を 3 で割って持つ。枠が違うときは丸ごと拡縮する。
class PostCardBackPhoto extends StatelessWidget {
  /// 全面に敷く写真。
  final String photoUrl;

  /// 投稿者の表示名（@ は付けない）。
  final String username;

  /// 投稿者のアイコン。
  final String? avatarUrl;

  final String trackName;
  final String artistName;

  /// 絵文字リアクションのボタン。null なら押せない。
  final VoidCallback? onReaction;

  /// 保存（＋）のボタン。null なら押せない。
  final VoidCallback? onAdd;

  const PostCardBackPhoto({
    super.key,
    required this.photoUrl,
    required this.username,
    required this.avatarUrl,
    required this.trackName,
    required this.artistName,
    this.onReaction,
    this.onAdd,
  });

  static const double cardWidth = 363;
  static const double cardHeight = 645;

  /// Figma（1089×1935）から実寸へ。
  static const double _s = 1 / 3;

  static const Color _sub = Color(0xFFD4D0CF);

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: cardWidth,
      height: cardHeight,
      child: ClipRRect(
        // Figma の角丸 54 もカードの 3 倍。実寸では 18。
        borderRadius: BorderRadius.circular(54 * _s),
        child: Stack(
          children: [
            _photo(),
            _header(),
            ..._footer(),
          ],
        ),
      ),
    );
  }

  Widget _photo() {
    return Positioned.fill(
      child: ColoredBox(
        color: const Color(0xFF000000),
        child: Image(
          // 写真は Storage の URL / data URI / ローカルパスのいずれか。
          // 判定は albumImageProvider に任せる（アルバムアートと同じ扱い）。
          image: albumImageProvider(photoUrl),
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => const Center(
            child: Icon(Icons.photo, color: Colors.white24, size: 40),
          ),
        ),
      ),
    );
  }

  /// 上部: アイコン（69,54 の 96 角）と名前（205,85）。
  Widget _header() {
    return Positioned(
      left: 0,
      right: 0,
      top: 0,
      height: 150 * _s,
      child: Stack(
        children: [
          Positioned(
            left: 69 * _s,
            top: 54 * _s,
            child: ClipOval(
              child: Container(
                width: 96 * _s,
                height: 96 * _s,
                color: const Color(0xFF3A3A3A),
                child: ProfileImage(imageUrl: avatarUrl, size: 96 * _s),
              ),
            ),
          ),
          Positioned(
            left: 205 * _s,
            // Figma のテキストは top=85 / 高さ38。中心を合わせる。
            top: 85 * _s,
            height: 38 * _s,
            right: 8,
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                username,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 32 * _s,
                  height: 1.0,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 下部: 曲名・アーティスト・リアクション・著作表示。
  /// Figma では y=1509 から始まる 426 の枠。
  List<Widget> _footer() {
    const base = 1509 * _s;
    return [
      Positioned(
        left: 34 * _s,
        right: 16,
        top: base + 18 * _s,
        height: 84 * _s,
        child: Align(
          alignment: Alignment.centerLeft,
          child: Text(
            trackName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: Colors.white,
              fontSize: 70 * _s,
              height: 1.0,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ),
      Positioned(
        left: 34 * _s,
        right: 16,
        top: base + 117 * _s,
        height: 38 * _s,
        child: Align(
          alignment: Alignment.centerLeft,
          child: Text(
            artistName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: _sub,
              fontSize: 32 * _s,
              height: 1.0,
            ),
          ),
        ),
      ),

      // スマイル（34,215 の 85 角）
      _icon(
        left: 34 * _s,
        top: base + 215 * _s,
        size: 85 * _s,
        asset: 'assets/icons/card_back/smile.svg',
        onTap: onReaction,
      ),

      // ＋（230,223 の 69 角）
      _icon(
        left: 230 * _s,
        top: base + 223 * _s,
        size: 69 * _s,
        asset: 'assets/icons/card_back/add.svg',
        onTap: onAdd,
      ),

      Positioned(
        left: 55 * _s,
        right: 16,
        top: base + 360 * _s,
        height: 36 * _s,
        child: Align(
          alignment: Alignment.centerLeft,
          child: Text(
            'Provided courtesy of Apple Music',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: _sub,
              fontSize: 30 * _s,
              height: 1.0,
            ),
          ),
        ),
      ),
    ];
  }

  /// アイコンを Figma の位置に置く。
  ///
  /// 実寸では 23〜28pt と小さく押しづらいので、タップ範囲だけ 44pt に広げる。
  /// 広げたぶん左上へ戻して、見た目の位置は Figma のままにする。
  Widget _icon({
    required double left,
    required double top,
    required double size,
    required String asset,
    required VoidCallback? onTap,
  }) {
    const minTap = 44.0;
    final box = size < minTap ? minTap : size;
    final offset = (box - size) / 2;

    return Positioned(
      left: left - offset,
      top: top - offset,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: SizedBox(
          width: box,
          height: box,
          child: Center(
            child: SvgPicture.asset(asset, width: size, height: size),
          ),
        ),
      ),
    );
  }
}

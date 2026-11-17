import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../constants/profile_fonts.dart';
import '../models/post_model.dart';
import '../services/audio_player_service.dart';
import 'post_card.dart';

/// グループの共有画像（Figma 6541:12058 / 6672:12225 / 6672:12233 /
/// 6672:12242 / 6672:12252）。
///
/// 「Our day in N Choices」と日付、その日のメンバーの投稿カード、下に 15s。
/// 全員そろった日は上に「FULL HOUSE・全員そろった日」を付ける。
/// 402×715 の座標で描くので、切り出すときはこのウィジェットごと画像にする。
class GroupShareImage extends StatelessWidget {
  static const double width = 402;
  static const double height = 715;

  /// 並べる投稿。先頭から順に置き場所へ入る（後ろほど上に重なる）。
  final List<PostModel> posts;

  /// その回の日付（21 時の通知が来た日）。
  final DateTime day;

  /// メンバー全員が投稿した日か。
  final bool fullHouse;

  const GroupShareImage({
    super.key,
    required this.posts,
    required this.day,
    required this.fullHouse,
  });

  @override
  Widget build(BuildContext context) {
    final slots = shareSlotsFor(posts.length);
    return SizedBox(
      width: width,
      height: height,
      child: ColoredBox(
        color: const Color(0xFF121212),
        child: Stack(
          clipBehavior: Clip.hardEdge,
          children: [
            if (posts.isNotEmpty) _background(posts.first),
            if (fullHouse) _fullHouseBadge(),
            _title(),
            for (var i = 0; i < posts.length && i < slots.length; i++)
              _card(posts[i], slots[i]),
            const Positioned(
              left: 0,
              right: 0,
              top: 643,
              child: Text(
                '15s',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: kSfProRounded,
                  fontWeight: FontWeight.w800,
                  fontSize: 36,
                  height: 2,
                  letterSpacing: 0.36,
                  color: Color(0xFFCDCDCD),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 1 枚目のジャケットを大きくぼかして敷く（週間まとめと同じ）。
  Widget _background(PostModel post) {
    return Positioned(
      left: -236,
      top: -80,
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

  Widget _title() {
    const heading = TextStyle(
      fontFamily: kSfProRounded,
      fontWeight: FontWeight.w800,
      fontSize: 36,
      letterSpacing: 0.36,
      color: Colors.white,
    );
    final n = posts.length;
    return Positioned(
      left: 0,
      right: 0,
      top: 55,
      child: Column(
        children: [
          const Text('Our day', style: heading, textAlign: TextAlign.center),
          Text('in $n ${n == 1 ? 'Choice' : 'Choices'}',
              style: heading, textAlign: TextAlign.center),
          Text(
            dayLabel(day),
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

  /// 「Oct 26, 2026(Mon)」。
  static String dayLabel(DateTime d) {
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    const weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    return '${months[d.month - 1]} ${d.day}, ${d.year}(${weekdays[d.weekday - 1]})';
  }

  /// Figma 6672:12269。224×25 の虹色の帯に黒い文字。
  Widget _fullHouseBadge() {
    const base = TextStyle(
      fontFamily: kSfProRounded,
      fontWeight: FontWeight.w700,
      fontSize: 11,
      color: Colors.black,
    );
    return Positioned(
      left: 89,
      top: 30,
      width: 224,
      height: 25,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(44),
          gradient: const LinearGradient(
            colors: [
              Color(0xFFEDB8FE),
              Color(0xFFB4B5F7),
              Color(0xFF7FB3EC),
              Color(0xFF8CC8BD),
              Color(0xFF99DE8F),
              Color(0xFFBED57E),
              Color(0xFFF1C56C),
            ],
            stops: [0, 0.17308, 0.34615, 0.5, 0.64904, 0.79327, 1],
          ),
        ),
        alignment: Alignment.center,
        child: Text.rich(
          TextSpan(children: [
            TextSpan(
                text: 'FULL HOUS', style: base.copyWith(letterSpacing: 2.53)),
            TextSpan(text: 'E', style: base.copyWith(letterSpacing: 8.96)),
            TextSpan(text: '・', style: base.copyWith(letterSpacing: 8.8)),
            TextSpan(
                text: '全員そろった日', style: base.copyWith(letterSpacing: 2.88)),
          ]),
          maxLines: 1,
          style: base,
        ),
      ),
    );
  }

  Widget _card(PostModel post, ShareSlot slot) {
    return Positioned(
      left: slot.cx - _cardW / 2,
      top: slot.cy - _cardH / 2,
      width: _cardW,
      height: _cardH,
      child: Transform.rotate(
        angle: slot.deg * math.pi / 180,
        child: Transform.scale(
          scale: slot.w / _cardW,
          child: _cardVisual(post),
        ),
      ),
    );
  }

  /// 投稿カードの表を 125×222 に縮め、枠と影を付けたもの（週間まとめと同じ）。
  Widget _cardVisual(PostModel post) {
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
                key: ValueKey('group-share-${post.postId}'),
                post: post,
                currentUserId: FirebaseAuth.instance.currentUser?.uid,
                audioService: AudioPlayerService(),
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
}

const double _cardW = 125;
const double _cardH = 222.107;

/// カード 1 枚の置き場所。402×715 の座標で、中心・幅・傾き（度）。
class ShareSlot {
  final double cx;
  final double cy;
  final double w;
  final double deg;
  const ShareSlot(this.cx, this.cy, this.w, this.deg);
}

/// 枚数ごとの置き場所。後ろほど上に重なる。
///
/// 2・4・5・7 枚は Figma の数値。1・3・6・8〜10 枚はデザインがまだ無いので
/// 仮の配置（11/13 時点）。デザインが来たら差し替える。
List<ShareSlot> shareSlotsFor(int n) {
  switch (n) {
    case <= 0:
      return const [];
    case 1:
      return const [ShareSlot(201, 410, 180, -3)];
    case 2:
      return const [
        ShareSlot(145.66, 400.01, 174.269, -5.14),
        ShareSlot(258.67, 369.31, 172.384, 5.18),
      ];
    case 3:
      return const [
        ShareSlot(130, 345, 150, -6),
        ShareSlot(272, 330, 150, 7),
        ShareSlot(200, 505, 150, -3),
      ];
    case 4:
      return const [
        ShareSlot(122.58, 340.87, 134.318, -5.14),
        ShareSlot(271.82, 317.95, 139.245, 8.85),
        ShareSlot(145.52, 514.29, 125, -11.59),
        ShareSlot(253.53, 519.13, 130.58, 22.37),
      ];
    case 5:
      return const [
        ShareSlot(115.19, 324.15, 125, -5.14),
        ShareSlot(220.26, 298.61, 125, 2.49),
        ShareSlot(286.30, 366.19, 125, 6.3),
        ShareSlot(125.43, 500.42, 125, -10.35),
        ShareSlot(236.42, 526.11, 125, 8.61),
      ];
    case 6:
      // 7 枚から真ん中の 1 枚を抜いたもの。
      return [
        for (final (i, s) in _seven.indexed)
          if (i != 1) s,
      ];
    case 7:
      return _seven;
    default:
      return _rows(n);
  }
}

const List<ShareSlot> _seven = [
  ShareSlot(121.27, 300.54, 97.386, -5.14),
  ShareSlot(191.49, 428.84, 97.019, 2),
  ShareSlot(215.31, 273.35, 97.163, 2.49),
  ShareSlot(94.68, 445.49, 97.385, -2),
  ShareSlot(297.89, 379.60, 97.877, 6.3),
  ShareSlot(144.11, 557.33, 96.838, -10.35),
  ShareSlot(263.99, 524.07, 97.998, 11.47),
];

/// 8〜10 枚の仮の配置。3 段に分け、少しずつ傾ける。
List<ShareSlot> _rows(int n) {
  final perRow = switch (n) {
    8 => [3, 2, 3],
    9 => [3, 3, 3],
    _ => [4, 3, 3],
  };
  const tilts = [-5.0, 3.0, -8.0, 6.0, -3.0, 9.0, -6.0, 2.0, 7.0, -4.0];
  const rowY = [290.0, 420.0, 550.0];
  final slots = <ShareSlot>[];
  for (var r = 0; r < perRow.length; r++) {
    final k = perRow[r];
    final spacing = k >= 4 ? 78.0 : 100.0;
    for (var i = 0; i < k; i++) {
      final x = 201 + (i - (k - 1) / 2) * spacing;
      slots.add(ShareSlot(x, rowY[r], 88, tilts[slots.length % tilts.length]));
    }
  }
  return slots;
}

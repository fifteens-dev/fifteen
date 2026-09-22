import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../widgets/invite_story_card.dart';
import 'instagram_stories_service.dart';

/// 招待カードを画像にして Instagram ストーリーへ渡す。
///
/// カードは画面には出さない。Overlay の画面外に一瞬だけ置いて描画させ、
/// [RepaintBoundary] から PNG を取り出してすぐ外す。プレビュー画面を挟まずに
/// ストーリーの編集画面へ直行するため。
class InviteStoryService {
  InviteStoryService._();

  /// カード内で使う画像・SVG。描画前に読み込んでおかないと、
  /// 1 フレーム目では空のまま撮れてしまう。
  static const _svgAssets = [
    'assets/invite_card/barcode.svg',
    'assets/invite_card/bubble.svg',
    'assets/invite_card/hand.svg',
  ];

  /// 招待カードの QR に埋める URL。読むとそのユーザーのプロフィールが開く。
  /// 招待コードも付けておくと、そこから登録した人の招待元が辿れる。
  static String profileUrl({required String uid, String? inviteCode}) {
    final code = inviteCode;
    return 'https://fifteens-39cfe.web.app/u/$uid'
        '${code != null && code.isNotEmpty ? '?code=$code' : ''}';
  }

  /// 招待コード付きの共有 URL。開くとコードがクリップボードに入り、
  /// App Store へ誘導される。アプリ側は起動時にそれを拾って自動で適用する。
  /// 末尾スラッシュ無し。Firebase Hosting は trailingSlash:false なので
  /// `/invite/` だと 301 を 1 回挟む（一部のメッセージアプリでプレビューが崩れる）。
  static String inviteUrl({String? inviteCode}) =>
      'https://fifteens-39cfe.web.app/invite?code=${inviteCode ?? ''}';

  /// メッセージアプリ等に流す招待文。
  static String shareText({String? inviteCode}) =>
      '15sで友達になろう！\n招待コード：${inviteCode ?? ''}\n'
      '${inviteUrl(inviteCode: inviteCode)}';

  /// 招待カードをストーリーへ送る。開けなければ招待文をコピーして false を返す。
  ///
  /// 友達追加シートとプロフィールの共有シートで挙動を揃えるための入口。
  /// 同じことを両方に書くと、片方だけ直したときに食い違う。
  static Future<bool> shareToInstagramOrCopy(
    BuildContext context, {
    required String username,
    required String uid,
    String? inviteCode,
  }) async {
    final ok = await shareToInstagram(
      context,
      username: username,
      qrUrl: profileUrl(uid: uid, inviteCode: inviteCode),
    );
    if (ok) return true;
    // 画像は作れたが Instagram が入っていない場合もここに来る。
    await Clipboard.setData(
      ClipboardData(text: shareText(inviteCode: inviteCode)),
    );
    return false;
  }

  /// 招待カードを Instagram ストーリーで開く。
  ///
  /// [username] はカードに出す表示名、[qrUrl] は QR に埋める URL。
  /// 画像を作れなかった場合や Instagram を開けなかった場合は false。
  static Future<bool> shareToInstagram(
    BuildContext context, {
    required String username,
    required String qrUrl,
  }) async {
    final bytes = await _render(context, username: username, qrUrl: qrUrl);
    if (bytes == null) return false;
    return InstagramStoriesService.share(bytes, contentUrl: qrUrl);
  }

  /// カードを 1080×1920 の PNG にする。
  static Future<Uint8List?> _render(
    BuildContext context, {
    required String username,
    required String qrUrl,
  }) async {
    final overlay = Overlay.maybeOf(context, rootOverlay: true);
    if (overlay == null) return null;

    await _warmAssets(context);
    if (!context.mounted) return null;

    final boundaryKey = GlobalKey();
    final entry = OverlayEntry(
      builder: (_) => Positioned(
        // 画面の外に置く。Offstage だと描画自体が走らず撮れない。
        left: -InviteStoryCard.designWidth * 2,
        top: 0,
        child: RepaintBoundary(
          key: boundaryKey,
          child: InviteStoryCard.story(username: username, qrData: qrUrl),
        ),
      ),
    );

    overlay.insert(entry);
    try {
      // 1 フレームでは画像のデコードが間に合わないことがあるので数フレーム待つ。
      for (var i = 0; i < 3; i++) {
        await WidgetsBinding.instance.endOfFrame;
      }
      final boundary =
          boundaryKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) return null;
      final image =
          await boundary.toImage(pixelRatio: InviteStoryCard.exportPixelRatio);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      return data?.buffer.asUint8List();
    } catch (e) {
      if (kDebugMode) print('InviteStoryService._render error: $e');
      return null;
    } finally {
      entry.remove();
    }
  }

  /// 画像と SVG を先にキャッシュへ載せる。
  static Future<void> _warmAssets(BuildContext context) async {
    try {
      await precacheImage(
        const AssetImage('assets/invite_card/cd_case.png'),
        context,
      );
    } catch (_) {/* 描けなくても致命的ではない */}

    for (final path in _svgAssets) {
      try {
        final loader = SvgAssetLoader(path);
        await svg.cache
            .putIfAbsent(loader.cacheKey(null), () => loader.loadBytes(null));
      } catch (_) {/* 同上 */}
    }
  }
}

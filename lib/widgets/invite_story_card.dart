import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../constants/profile_fonts.dart';

/// Instagram ストーリーに流す招待カード（Figma 5779-12964）。
///
/// CD ケースの中に QR とユーザー名が入った「身分証」を、グラデーション背景に
/// 置いたもの。QR を読むとそのユーザーのプロフィールへ飛ぶ。
///
/// ## サイズについて
/// Figma は 402×812 のシートだが、ストーリーは 9:16。デザインの内容は
/// y=60（タイトル）〜 y=608（😎 の下端）に収まっているので、幅 402 のまま
/// 高さを 9:16 相当（715）にして、その中で上下中央に寄せている。
/// これを 2.687 倍（=1080/402）で書き出すと 1080×1920 になる。
class InviteStoryCard extends StatelessWidget {
  /// カードに出す表示名。`@` は内部で付ける。
  final String username;

  /// QR に埋め込む URL。
  final String qrData;

  /// 描く高さ。ストーリー用は 9:16 の [storyHeight]、シート用は Figma の
  /// フレームそのままの [sheetHeight]。
  final double height;

  /// 内容を縦にずらす量。Figma の座標に足す。
  final double contentShift;

  const InviteStoryCard({
    super.key,
    required this.username,
    required this.qrData,
    this.height = storyHeight,
    this.contentShift = storyShift,
  });

  /// Instagram ストーリーに流す用。9:16 に合わせ、内容を上下中央へ寄せる。
  const InviteStoryCard.story({
    super.key,
    required this.username,
    required this.qrData,
  })  : height = storyHeight,
        contentShift = storyShift;

  /// アプリ内のシート用。Figma のフレーム（402×812）そのままの座標で描く。
  const InviteStoryCard.sheet({
    super.key,
    required this.username,
    required this.qrData,
  })  : height = sheetHeight,
        contentShift = 0;

  /// デザイン上の幅。書き出し時はこの比率で拡大する。
  static const double designWidth = 402;

  /// 9:16 にするための高さ。
  static const double storyHeight = 715;

  /// Figma のシートの高さ（402×812）。
  static const double sheetHeight = 812;

  /// 1080×1920 で書き出すための倍率。
  static const double exportPixelRatio = 1080 / designWidth;

  /// 内容（y 60〜608）を [storyHeight] の中で上下中央に寄せるための移動量。
  static const double storyShift = (storyHeight - (608 - 60)) / 2 - 60;

  static const Color _cardBlack = Color(0xFF141413);
  static const Color _spine = Color(0xFF161515);
  static const Color _faint = Color(0xFF7B7B7B);

  @override
  Widget build(BuildContext context) {
    // このカードは画面外に置いて画像化するので、Directionality や
    // DefaultTextStyle を親に頼れない。頼ると Flutter の既定
    // （黄色い下線付きテキスト）が出て、そのまま共有画像に焼き付く。
    return Directionality(
      textDirection: TextDirection.ltr,
      child: DefaultTextStyle(
        style: const TextStyle(
          color: Colors.white,
          decoration: TextDecoration.none,
          fontWeight: FontWeight.w400,
        ),
        child: _build(),
      ),
    );
  }

  Widget _build() {
    return SizedBox(
      width: designWidth,
      height: height,
      child: DecoratedBox(
        decoration: const BoxDecoration(
          // Figma: linear-gradient(205.96deg, ...)。CSS の角度をそのまま
          // Alignment に直すと箱の縦横比で傾きが変わるので、実寸（402×715）で
          // 26° 傾くように dx を決めている。
          gradient: LinearGradient(
            begin: Alignment(0.867, -1),
            end: Alignment(-0.867, 1),
            colors: [
              Color(0xFF5C4EFF),
              Color(0xFF00A8A9),
              Color(0xFF978EED),
              Color(0xFFBB70D0),
            ],
            stops: [0.0142, 0.3629, 0.5932, 1.0],
          ),
        ),
        child: Stack(
          children: [
            _emoji('🎶', left: 354.5, top: 150, size: 48, deg: 18.05),
            _emoji('🫶', left: 0.72, top: 340, size: 64, deg: 14.28),
            _emoji('😎', left: 315, top: 508.5, size: 64, deg: -17.72),
            _title(),
            Positioned(left: 21, top: 174 + contentShift, child: _case()),
          ],
        ),
      ),
    );
  }

  Widget _title() {
    return Positioned(
      left: 0,
      right: 0,
      top: 60 + contentShift,
      child: const Text(
        'invite your friends to 15s',
        textAlign: TextAlign.center,
        style: TextStyle(
          color: Colors.white,
          fontSize: 24,
          height: 1.31,
          letterSpacing: 0.24,
          fontWeight: FontWeight.w700,
          fontFamily: kSfProRounded,
        ),
      ),
    );
  }

  /// 背景に散らす絵文字。Figma のボックス左上に合わせて置き、中心で回す。
  Widget _emoji(String char,
      {required double left,
      required double top,
      required double size,
      required double deg}) {
    return Positioned(
      left: left,
      top: top + contentShift,
      child: Transform.rotate(
        angle: deg * math.pi / 180,
        child: Text(
          char,
          style: TextStyle(fontSize: size, height: 1.31),
        ),
      ),
    );
  }

  // ── CD ケース（Figma: Frame 853 / 378×334）─────────────────────

  Widget _case() {
    return SizedBox(
      width: 378,
      height: 334,
      child: Stack(
        children: [
          // 落ち影だけの層。ケース本体より内側に置かれている。
          Positioned(
            left: 17,
            top: 30,
            child: Container(
              width: 344,
              height: 272,
              decoration: const BoxDecoration(
                color: Colors.black,
                boxShadow: [
                  BoxShadow(
                      color: Color(0x29000000),
                      offset: Offset(0, 15),
                      blurRadius: 14.3),
                  BoxShadow(
                      color: Color(0x33000000),
                      offset: Offset(0, 14),
                      blurRadius: 28),
                ],
              ),
            ),
          ),
          // ケースの写真。透明な樹脂なので、黒い盤面はこの上に重ねる
          // （Figma のレイヤー順も同じ）。
          Image.asset('assets/invite_card/cd_case.png',
              width: 378, height: 334, fit: BoxFit.fill),
          const Positioned(
            left: 37,
            top: 36,
            child: SizedBox(width: 279, height: 256, child: ColoredBox(color: _cardBlack)),
          ),
          const Positioned(
            left: 330,
            top: 36,
            child: SizedBox(width: 23, height: 256, child: ColoredBox(color: _spine)),
          ),
          _handleLabel(),
          _scanToAdd(),
          _qr(),
          _divider(),
          _issuedBy(),
          _sideText(),
          _handwriting(),
          _bubble(),
          Positioned(
            left: 332,
            top: 41,
            child: SvgPicture.asset('assets/invite_card/barcode.svg',
                width: 18, height: 58),
          ),
        ],
      ),
    );
  }

  /// 白い角丸ラベル + @ユーザー名。まとめて -4.6° 傾いている。
  Widget _handleLabel() {
    return Positioned(
      left: 110,
      top: 63.79,
      width: 124.08,
      height: 39.92,
      child: Center(
        child: Transform.rotate(
          angle: -4.6 * math.pi / 180,
          child: Container(
            width: 122.045,
            height: 30.231,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(24),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Text(
                '@$username',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.black,
                  fontSize: 14,
                  fontWeight: FontWeight.w900,
                  fontFamily: kSfProRounded,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _scanToAdd() {
    return const Positioned(
      left: 0,
      right: 0,
      top: 106,
      child: Text(
        'SCAN TO ADD',
        textAlign: TextAlign.center,
        style: TextStyle(
          color: Colors.white,
          fontSize: 8,
          letterSpacing: 1.6,
          fontWeight: FontWeight.w600,
          fontFamily: kSfProRounded,
        ),
      ),
    );
  }

  /// QR。Figma では白い角丸(116×114)の中に 98×97 のコードが入っている。
  Widget _qr() {
    return Positioned(
      left: 119,
      top: 120,
      child: Container(
        width: 116,
        height: 114,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(10),
        ),
        child: QrImageView(
          data: qrData,
          version: QrVersions.auto,
          size: 97,
          padding: EdgeInsets.zero,
          backgroundColor: Colors.white,
          // 読み取り精度を優先して誤り訂正は中程度。角を丸めるとカメラが
          // 読みにくくなることがあるので、モジュールは四角のままにする。
          errorCorrectionLevel: QrErrorCorrectLevel.M,
          eyeStyle: const QrEyeStyle(
            eyeShape: QrEyeShape.square,
            color: Colors.black,
          ),
          dataModuleStyle: const QrDataModuleStyle(
            dataModuleShape: QrDataModuleShape.square,
            color: Colors.black,
          ),
        ),
      ),
    );
  }

  Widget _divider() {
    return const Positioned(
      left: 49,
      top: 265,
      child: SizedBox(
        width: 257,
        height: 1,
        child: ColoredBox(color: Color(0x3DFFFFFF)),
      ),
    );
  }

  Widget _issuedBy() {
    return const Positioned(
      left: 0,
      right: 0,
      top: 269,
      child: Text(
        'this identification card is issued by 15s',
        textAlign: TextAlign.center,
        style: TextStyle(color: _faint, fontSize: 6, letterSpacing: 0.3),
      ),
    );
  }

  /// 右端の縦書き 2 つ。Figma では 90° 回転したテキスト。
  Widget _sideText() {
    return Stack(
      children: [
        Positioned(
          left: 344,
          top: 123,
          width: 10,
          height: 88,
          child: Center(
            child: RotatedBox(
              quarterTurns: 1,
              child: Text(
                'Provided courtesy of Apple Music',
                maxLines: 1,
                softWrap: false,
                style: const TextStyle(
                    color: _faint, fontSize: 8, fontFamily: 'Caveat'),
              ),
            ),
          ),
        ),
        Positioned(
          left: 347,
          top: 231,
          width: 13,
          height: 53,
          child: Center(
            child: RotatedBox(
              quarterTurns: 1,
              child: Text(
                'FIFTEENs',
                maxLines: 1,
                softWrap: false,
                style: const TextStyle(
                    color: _faint, fontSize: 11, fontWeight: FontWeight.w700),
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// 左上の手書き 4 行。
  Widget _handwriting() {
    return Positioned(
      left: 41,
      top: 53.82,
      width: 51.24,
      height: 60.67,
      child: Center(
        child: Transform.rotate(
          angle: -16.55 * math.pi / 180,
          child: const Text(
            'good\nmusic\nbrings\nus closer',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Color(0xFF9D9B9B),
              fontSize: 13,
              height: 1.0,
              fontFamily: 'Caveat',
            ),
          ),
        ),
      ),
    );
  }

  /// 「LET'S BE FRIENDS」の吹き出しと指。
  Widget _bubble() {
    return Positioned(
      left: 243,
      top: 206,
      width: 63.14,
      height: 55.49,
      child: Stack(
        children: [
          SvgPicture.asset('assets/invite_card/bubble.svg',
              width: 63.14, height: 48.46),
          Positioned(
            left: 6.2,
            top: 23.19,
            width: 51.25,
            height: 32.68,
            child: Center(
              child: Transform.rotate(
                angle: -19.05 * math.pi / 180,
                child: const Text(
                  'LET’S\nBE FRIENDS',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Color(0xFFB7B8B5),
                    fontSize: 7,
                    height: 1.31,
                    letterSpacing: 0.77,
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            left: 32.76,
            top: 45.37,
            child: SvgPicture.asset('assets/invite_card/hand.svg',
                width: 11.83, height: 10.12),
          ),
        ],
      ),
    );
  }
}

import 'package:flutter/material.dart';

import '../constants/profile_fonts.dart';
import '../services/invite_story_service.dart';
import '../widgets/common/app_toast.dart';
import '../widgets/invite_story_card.dart';

/// 招待カードを見せて Instagram ストーリーへ送るシート（Figma 5779-12975）。
///
/// プロフィール左上の共有ボタンから開く。中のカードは
/// [InviteStoryCard] をそのまま使う（ストーリーに流す画像と同じ見た目を
/// 先に見せる、という趣旨のため、別に組み直さない）。
class InviteShareSheet extends StatefulWidget {
  /// カードに出す表示名。`@` は内部で付ける。
  final String username;

  /// QR に埋める URL。
  final String qrUrl;

  const InviteShareSheet({
    super.key,
    required this.username,
    required this.qrUrl,
  });

  /// 下から出す。Figma ではステータスバーのすぐ下（y=62）から始まる。
  static Future<void> show(
    BuildContext context, {
    required String username,
    required String qrUrl,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.45),
      builder: (_) => InviteShareSheet(username: username, qrUrl: qrUrl),
    );
  }

  @override
  State<InviteShareSheet> createState() => _InviteShareSheetState();
}

class _InviteShareSheetState extends State<InviteShareSheet> {
  /// 画像を作っている間。1 秒ほどかかるのでアイコンを差し替える。
  bool _sharing = false;

  Future<void> _shareToInstagram() async {
    if (_sharing) return;
    setState(() => _sharing = true);
    final ok = await InviteStoryService.shareToInstagram(
      context,
      username: widget.username,
      qrUrl: widget.qrUrl,
    );
    if (!mounted) return;
    setState(() => _sharing = false);
    if (!ok) AppToast.show(context, 'Instagramを開けませんでした');
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    // Figma: シートはフレーム上端から 62 下がった位置に始まる。
    final sheetHeight = size.height - 62;
    // 402 幅のデザインを画面幅に合わせる。
    final scale = size.width / InviteStoryCard.designWidth;

    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(37)),
      child: SizedBox(
        height: sheetHeight,
        width: size.width,
        child: Stack(
          children: [
            // カード本体。デザインの高さ（812）より画面が低いこともあるので、
            // 上端を固定してはみ出したぶんは下で切る。
            Positioned(
              left: 0,
              top: 0,
              child: Transform.scale(
                scale: scale,
                alignment: Alignment.topLeft,
                child: InviteStoryCard.sheet(
                  username: widget.username,
                  qrData: widget.qrUrl,
                ),
              ),
            ),
            _instagramButton(scale),
          ],
        ),
      ),
    );
  }

  /// Figma: アイコン 53×53（角丸16）が (174,648)、ラベルが top 709。
  /// 画面が Figma より低いときは下端から置いて、画面外に出ないようにする。
  Widget _instagramButton(double scale) {
    final size = MediaQuery.sizeOf(context);
    final sheetHeight = size.height - 62;
    final designTop = 648 * scale;
    final blockHeight = (709 + 16 - 648) * scale;
    final top = designTop + blockHeight + 24 <= sheetHeight
        ? designTop
        : sheetHeight - blockHeight - 24;

    return Positioned(
      left: 0,
      right: 0,
      top: top,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _sharing ? null : _shareToInstagram,
            child: Container(
              width: 53 * scale,
              height: 53 * scale,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16 * scale),
              ),
              padding: EdgeInsets.all(6 * scale),
              child: _sharing
                  ? const FittedBox(
                      child: Padding(
                        padding: EdgeInsets.all(8),
                        child: CircularProgressIndicator(
                          strokeWidth: 3,
                          color: Colors.black54,
                        ),
                      ),
                    )
                  : Image.asset('assets/icons/Instagram_Glyph_Gradient.png'),
            ),
          ),
          SizedBox(height: 8 * scale),
          Text(
            'Instagram',
            style: TextStyle(
              color: Colors.white,
              fontSize: 12 * scale,
              height: 1.31,
              letterSpacing: 0.12 * scale,
              fontWeight: FontWeight.w700,
              fontFamily: kSfProRounded,
            ),
          ),
        ],
      ),
    );
  }
}

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../widgets/common/glass_circle_button.dart';

/// グループの招待 QR をアプリの中で読む画面（「コードで参加」から開く）。
///
/// 招待リンク（`https://…/g/<コード>`）か、6 桁のコードそのものを読んだら
/// コードを返して閉じる。参加の確認は呼び出し側（コードで参加）でする。
class QrJoinScannerScreen extends StatefulWidget {
  const QrJoinScannerScreen({super.key});

  /// 読めたコードを返す。閉じたら null。
  static Future<String?> push(BuildContext context) {
    return Navigator.of(context).push<String>(MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => const QrJoinScannerScreen(),
    ));
  }

  /// 読んだ文字列から招待コードを取り出す。招待のものでなければ null。
  static String? inviteCodeFrom(String raw) {
    final text = raw.trim();
    final uri = Uri.tryParse(text);
    if (uri != null && uri.hasScheme) {
      final seg = uri.pathSegments;
      final i = seg.indexOf('g');
      if (i >= 0 && i + 1 < seg.length) return _code(seg[i + 1]);
      return null;
    }
    return _code(text);
  }

  static String? _code(String s) =>
      RegExp(r'^[a-zA-Z0-9]{6}$').hasMatch(s) ? s.toLowerCase() : null;

  @override
  State<QrJoinScannerScreen> createState() => _QrJoinScannerScreenState();
}

class _QrJoinScannerScreenState extends State<QrJoinScannerScreen> {
  final MobileScannerController _controller = MobileScannerController(
    formats: const [BarcodeFormat.qrCode],
  );
  bool _done = false;
  bool _showedWrong = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_done) return;
    for (final b in capture.barcodes) {
      final raw = b.rawValue;
      if (raw == null) continue;
      final code = QrJoinScannerScreen.inviteCodeFrom(raw);
      if (code != null) {
        _done = true;
        Navigator.of(context).pop(code);
        return;
      }
    }
    if (!_showedWrong) setState(() => _showedWrong = true);
  }

  @override
  Widget build(BuildContext context) {
    final padding = MediaQuery.paddingOf(context);
    final side = MediaQuery.sizeOf(context).width * 0.68;
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          Positioned.fill(
            child: MobileScanner(
              controller: _controller,
              onDetect: _onDetect,
              errorBuilder: (context, error) => const Center(
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: 32),
                  child: Text(
                    'カメラを使えません。設定アプリで 15s のカメラを許可してください。',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white, fontSize: 15),
                  ),
                ),
              ),
            ),
          ),
          // 読み取り枠。
          Center(
            child: Container(
              width: side,
              height: side,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: Colors.white, width: 3),
              ),
            ),
          ),
          Positioned(
            left: 24,
            right: 24,
            bottom: padding.bottom + 48,
            child: Text(
              _showedWrong ? 'グループの招待QRではないようです' : '招待のQRコードを枠に合わせてください',
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 15,
                fontWeight: FontWeight.w600,
                shadows: [Shadow(blurRadius: 8, color: Colors.black54)],
              ),
            ),
          ),
          Positioned(
            left: 16,
            top: padding.top + 8,
            child: GlassCircleButton(
              size: 44,
              onTap: () => Navigator.of(context).pop(),
              child: const Icon(CupertinoIcons.xmark,
                  color: Colors.white, size: 20),
            ),
          ),
        ],
      ),
    );
  }
}

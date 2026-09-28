import 'dart:ui';

import 'package:flutter/material.dart';

/// 投稿が終わったあとに出すシート（Figma 5838-11206）。
///
/// 「写真を追加する」か「あとで」を選ばせる。写真は 24:00 まで足せるので、
/// ここで断っても投稿カードのバーから後で足せる。
class PostCompleteSheet extends StatelessWidget {
  const PostCompleteSheet({super.key});

  /// 表示して、「写真を追加する」が押されたら true を返す。
  static Future<bool> show(BuildContext context) async {
    final result = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.45),
      builder: (_) => const PostCompleteSheet(),
    );
    return result ?? false;
  }

  static const Color _panel = Color(0xCC1C1C1E);
  static const Color _border = Color(0x1FFFFFFF);
  static const Color _accent = Color(0xFFC8FF4D);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(27),
        // Figma: backdrop-blur 17.5px。下の画面をぼかして浮かせる。
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 17.5, sigmaY: 17.5),
          child: Container(
            decoration: BoxDecoration(
              color: _panel,
              borderRadius: BorderRadius.circular(27),
              border: Border.all(color: _border),
            ),
            padding: const EdgeInsets.fromLTRB(13, 9, 13, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // ハンドル
                Container(
                  width: 39,
                  height: 5,
                  decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
                const SizedBox(height: 39),
                _check(),
                const SizedBox(height: 22),
                const Text(
                  '投稿完了!',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  '24:00まで写真を追加できます',
                  style: TextStyle(
                    color: Color(0xB8FFFFFF),
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 27),
                SizedBox(
                  width: double.infinity,
                  height: 47,
                  child: ElevatedButton(
                    onPressed: () => Navigator.of(context).pop(true),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(29),
                      ),
                    ),
                    child: const Text(
                      '写真を追加する',
                      style: TextStyle(
                        color: Colors.black,
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 19),
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => Navigator.of(context).pop(false),
                  child: const Padding(
                    padding: EdgeInsets.symmetric(vertical: 4, horizontal: 24),
                    child: Text(
                      'あとで',
                      style: TextStyle(
                        color: Color(0xB8FFFFFF),
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// 黄緑の丸にチェック。まわりに放射状の線が 4 本。
  Widget _check() {
    return SizedBox(
      width: 96,
      height: 60,
      child: Stack(
        alignment: Alignment.center,
        children: [
          for (final line in _rays) _ray(line),
          Container(
            width: 43,
            height: 43,
            decoration: const BoxDecoration(
              color: _accent,
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.check, color: Colors.black, size: 24),
          ),
        ],
      ),
    );
  }

  /// Figma の 4 本（左上・右上・左下・右下）。中心からの向きと距離で置く。
  static const _rays = <({double dx, double dy, double angle})>[
    (dx: -36, dy: -12, angle: 0.84),
    (dx: 36, dy: -12, angle: -0.84),
    (dx: -44, dy: 10, angle: 0.25),
    (dx: 44, dy: 10, angle: -0.25),
  ];

  Widget _ray(({double dx, double dy, double angle}) line) {
    return Transform.translate(
      offset: Offset(line.dx, line.dy),
      child: Transform.rotate(
        angle: line.angle,
        child: Container(
          width: 8,
          height: 2.5,
          decoration: BoxDecoration(
            color: _accent,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
      ),
    );
  }
}

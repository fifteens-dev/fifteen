import 'package:flutter/material.dart';

/// 投稿削除の確認ダイアログ。
/// PNG画像をそのままダイアログとして表示し、「削除」「キャンセル」の
/// 領域だけがタップ可能になっている。
///
/// 戻り値:
///  - `true`  : 「削除」がタップされた
///  - `false` : 「キャンセル」がタップされた / バリアで閉じられた
Future<bool> showDeletePostConfirmDialog(BuildContext context) async {
  final result = await showDialog<bool>(
    context: context,
    barrierDismissible: true,
    barrierColor: Colors.black.withValues(alpha: 0.5),
    builder: (context) => const _DeletePostConfirmDialog(),
  );
  return result == true;
}

/// 投稿削除ダイアログ（delete_post_dialog.png）と同じ見た目の汎用削除確認ダイアログ。
/// 文言（タイトル/本文）だけ差し替えたい場合に使う（例: プレイリスト削除）。
/// 戻り値: true=「削除」, false=「キャンセル」/バリア閉じ。
Future<bool> showDeleteConfirmDialog(
  BuildContext context, {
  required String title,
  required String message,
}) async {
  final result = await showDialog<bool>(
    context: context,
    barrierDismissible: true,
    barrierColor: Colors.black.withValues(alpha: 0.5),
    builder: (ctx) => Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      insetPadding: const EdgeInsets.symmetric(horizontal: 32),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: ColoredBox(
          color: const Color(0xFF5C5C5C),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(22, 26, 22, 22),
                child: Column(
                  children: [
                    Text(
                      title,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 19,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 14),
                    Text(
                      message,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1, thickness: 1, color: Color(0x33000000)),
              InkWell(
                onTap: () => Navigator.of(ctx).pop(true),
                child: Container(
                  height: 56,
                  alignment: Alignment.center,
                  child: const Text(
                    '削除',
                    style: TextStyle(
                      color: Color(0xFFEB5C79),
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
              const Divider(height: 1, thickness: 1, color: Color(0x33000000)),
              InkWell(
                onTap: () => Navigator.of(ctx).pop(false),
                child: Container(
                  height: 56,
                  alignment: Alignment.center,
                  child: const Text(
                    'キャンセル',
                    style: TextStyle(color: Colors.white, fontSize: 16),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
  return result == true;
}

class _DeletePostConfirmDialog extends StatelessWidget {
  const _DeletePostConfirmDialog();

  // PNG実寸（1192 × 848）を基準にした領域割合
  static const double _deleteTopFraction = 0.484;
  static const double _deleteBottomFraction = 0.742;
  static const double _cancelTopFraction = 0.742;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      insetPadding: const EdgeInsets.symmetric(horizontal: 32),
      child: AspectRatio(
        aspectRatio: 1192 / 848,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final h = constraints.maxHeight;
            return Stack(
              children: [
                Positioned.fill(
                  child: Image.asset(
                    'assets/icons/delete_post_dialog.png',
                    fit: BoxFit.fill,
                  ),
                ),
                // 「削除」領域
                Positioned(
                  left: 0,
                  right: 0,
                  top: h * _deleteTopFraction,
                  height: h * (_deleteBottomFraction - _deleteTopFraction),
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => Navigator.of(context).pop(true),
                  ),
                ),
                // 「キャンセル」領域
                Positioned(
                  left: 0,
                  right: 0,
                  top: h * _cancelTopFraction,
                  height: h * (1.0 - _cancelTopFraction),
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => Navigator.of(context).pop(false),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

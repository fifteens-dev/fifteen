import 'package:flutter/material.dart';

/// PNG画像をそのままダイアログとして表示し、「削除」「キャンセル」の
/// 領域だけがタップ可能な削除確認ダイアログ。
///
/// 戻り値:
///  - `true`  : 「削除」がタップされた
///  - `false` : 「キャンセル」がタップされた / バリアで閉じられた

/// 投稿削除の確認ダイアログ（delete_post_dialog.png）。
Future<bool> showDeletePostConfirmDialog(BuildContext context) {
  return _showImageDeleteDialog(context, 'assets/icons/delete_post_dialog.png');
}

/// プレイリスト削除の確認ダイアログ（delete_playlist_dialog.png）。
Future<bool> showDeletePlaylistConfirmDialog(BuildContext context) {
  return _showImageDeleteDialog(
      context, 'assets/icons/delete_playlist_dialog.png');
}

Future<bool> _showImageDeleteDialog(
    BuildContext context, String asset) async {
  final result = await showDialog<bool>(
    context: context,
    barrierDismissible: true,
    barrierColor: Colors.black.withValues(alpha: 0.5),
    builder: (context) => _ImageDeleteConfirmDialog(asset: asset),
  );
  return result == true;
}

class _ImageDeleteConfirmDialog extends StatelessWidget {
  const _ImageDeleteConfirmDialog({required this.asset});

  final String asset;

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
                  child: Image.asset(asset, fit: BoxFit.fill),
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

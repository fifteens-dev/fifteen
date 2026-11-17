import 'dart:ui' as ui;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:share_plus/share_plus.dart';

import '../constants/profile_fonts.dart';
import '../models/post_model.dart';
import '../widgets/common/app_toast.dart';
import '../widgets/common/glass_circle_button.dart';
import '../widgets/group_share_image.dart';

/// グループの共有画像を見せて、OS の共有シートで渡す画面。
///
/// 共有ボタンを押したときの UI は別途デザインが来る（11/13）。それまでの
/// 仮の画面で、画像を大きく見せて「共有する」を置くだけ。
class GroupShareScreen extends StatefulWidget {
  final List<PostModel> posts;
  final DateTime day;
  final bool fullHouse;

  const GroupShareScreen({
    super.key,
    required this.posts,
    required this.day,
    required this.fullHouse,
  });

  static Future<void> push(
    BuildContext context, {
    required List<PostModel> posts,
    required DateTime day,
    required bool fullHouse,
  }) {
    return Navigator.of(context).push(MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) =>
          GroupShareScreen(posts: posts, day: day, fullHouse: fullHouse),
    ));
  }

  @override
  State<GroupShareScreen> createState() => _GroupShareScreenState();
}

class _GroupShareScreenState extends State<GroupShareScreen> {
  final GlobalKey _imageKey = GlobalKey();
  bool _sharing = false;

  Future<void> _share() async {
    if (_sharing) return;
    setState(() => _sharing = true);
    try {
      final boundary = _imageKey.currentContext?.findRenderObject()
          as RenderRepaintBoundary?;
      if (boundary == null) return;
      final image = await boundary.toImage(pixelRatio: 3);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      final bytes = data?.buffer.asUint8List();
      if (!mounted) return;
      if (bytes == null) {
        AppToast.show(context, '画像の取得に失敗しました');
        return;
      }
      // iPad では表示位置の指定が必須なので、画面の矩形を渡す。
      final box = context.findRenderObject() as RenderBox?;
      await Share.shareXFiles(
        [XFile.fromData(bytes, mimeType: 'image/png', name: 'our_day.png')],
        text: 'Our day on 15s 🎧',
        sharePositionOrigin:
            box == null ? null : box.localToGlobal(Offset.zero) & box.size,
      );
    } catch (_) {
      if (mounted) AppToast.show(context, '共有に失敗しました');
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final padding = MediaQuery.paddingOf(context);
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          Positioned(
            left: 16,
            right: 16,
            top: padding.top + 64,
            bottom: padding.bottom + 96,
            child: FittedBox(
              fit: BoxFit.contain,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(24),
                child: RepaintBoundary(
                  key: _imageKey,
                  child: GroupShareImage(
                    posts: widget.posts,
                    day: widget.day,
                    fullHouse: widget.fullHouse,
                  ),
                ),
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
          Positioned(
            left: 40,
            right: 40,
            bottom: padding.bottom + 24,
            height: 52,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _share,
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(26),
                ),
                alignment: Alignment.center,
                child: _sharing
                    ? const CupertinoActivityIndicator(color: Colors.black)
                    : const Text(
                        '共有する',
                        style: TextStyle(
                          fontFamily: kSfProRounded,
                          fontWeight: FontWeight.w700,
                          fontSize: 17,
                          color: Colors.black,
                        ),
                      ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

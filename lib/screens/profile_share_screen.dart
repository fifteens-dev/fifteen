import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../constants/profile_fonts.dart';
import '../services/invite_story_service.dart';
import '../widgets/common/app_toast.dart';
import '../widgets/common/glass_circle_button.dart';
import '../widgets/invite_story_card.dart';

/// 自分のプロフィール（招待カード）を共有する画面。
///
/// 見た目はグループの共有画面（[GroupShareScreen]）にそろえ、中身は以前の
/// 共有シート（[InviteShareSheet]）と同じ。Instagram ストーリーに流すカードを
/// 大きく見せ、下のボタンで Instagram へ送る（開けなければリンクをコピー）。
class ProfileShareScreen extends StatefulWidget {
  /// カードに出す表示名。`@` は中で付ける。
  final String username;
  final String uid;
  final String? inviteCode;

  const ProfileShareScreen({
    super.key,
    required this.username,
    required this.uid,
    this.inviteCode,
  });

  static Future<void> push(
    BuildContext context, {
    required String username,
    required String uid,
    String? inviteCode,
  }) {
    return Navigator.of(context).push(MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => ProfileShareScreen(
        username: username,
        uid: uid,
        inviteCode: inviteCode,
      ),
    ));
  }

  @override
  State<ProfileShareScreen> createState() => _ProfileShareScreenState();
}

class _ProfileShareScreenState extends State<ProfileShareScreen> {
  /// 画像を作っている間（1 秒ほど）。
  bool _sharing = false;

  Future<void> _shareToInstagram() async {
    if (_sharing) return;
    setState(() => _sharing = true);
    final ok = await InviteStoryService.shareToInstagramOrCopy(
      context,
      username: widget.username,
      uid: widget.uid,
      inviteCode: widget.inviteCode,
    );
    if (!mounted) return;
    setState(() => _sharing = false);
    if (!ok) {
      AppToast.show(context, 'Instagramを開けませんでした。リンクをコピーしました');
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
                child: SizedBox(
                  width: InviteStoryCard.designWidth,
                  height: InviteStoryCard.storyHeight,
                  child: InviteStoryCard.story(
                    username: widget.username,
                    qrData: InviteStoryService.profileUrl(
                      uid: widget.uid,
                      inviteCode: widget.inviteCode,
                    ),
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
              onTap: _shareToInstagram,
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(26),
                ),
                alignment: Alignment.center,
                child: _sharing
                    ? const CupertinoActivityIndicator(color: Colors.black)
                    : Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Image.asset(
                              'assets/icons/Instagram_Glyph_Gradient.png',
                              width: 22,
                              height: 22),
                          const SizedBox(width: 8),
                          const Text(
                            'Instagramで共有する',
                            style: TextStyle(
                              fontFamily: kSfProRounded,
                              fontWeight: FontWeight.w700,
                              fontSize: 17,
                              color: Colors.black,
                            ),
                          ),
                        ],
                      ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

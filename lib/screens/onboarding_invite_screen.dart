import 'dart:ui';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../services/invite_story_service.dart';
import '../services/user_service.dart';
import '../widgets/invite_story_card.dart';

/// 登録の最後に出す招待画面（Figma 5861-11705）。
///
/// 音楽サービスを繋いだ直後、ホームに入る前に 1 枚だけ挟む。
/// 15s は友達が居ないと何も起きないので、最初に誘ってもらうのが狙い。
///
/// 「リンクを送信」は OS の共有シート。招待カードそのものは
/// [InviteStoryCard] を使い回す（プロフィールの共有シートと同じ絵）。
class OnboardingInviteScreen extends StatefulWidget {
  /// 「リンクを送信」または「あとで」で先に進むときに呼ぶ。
  final VoidCallback onDone;

  const OnboardingInviteScreen({super.key, required this.onDone});

  @override
  State<OnboardingInviteScreen> createState() => _OnboardingInviteScreenState();
}

class _OnboardingInviteScreenState extends State<OnboardingInviteScreen> {
  static const Color _bg = Color(0xFF161C1F);
  static const Color _panel = Color(0xE618181A);
  static const Color _border = Color(0x1AFFFFFF);

  final UserService _userService = UserService();

  String? _uid;
  String? _username;
  String? _inviteCode;
  bool _sharing = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    try {
      final me = await _userService.getUser(uid);
      if (!mounted) return;
      setState(() {
        _uid = uid;
        _username = me?.username;
        _inviteCode = me?.inviteCode;
      });
      // 登録直後は招待コードがまだ無いことがあるので、その場で発行する。
      if (me?.inviteCode == null || me!.inviteCode!.isEmpty) {
        final code = await _userService.ensureInviteCode(uid);
        if (mounted) setState(() => _inviteCode = code);
      }
    } catch (_) {/* カードは出さずに「あとで」で進める */}
  }

  Future<void> _share() async {
    final uid = _uid;
    final name = _username;
    if (uid == null || name == null || name.isEmpty || _sharing) return;

    setState(() => _sharing = true);
    await InviteStoryService.shareToInstagramOrCopy(
      context,
      username: name,
      uid: uid,
      inviteCode: _inviteCode,
    );
    if (!mounted) return;
    setState(() => _sharing = false);
    widget.onDone();
  }

  @override
  Widget build(BuildContext context) {
    final ready = _uid != null && (_username?.isNotEmpty ?? false);

    return Scaffold(
      backgroundColor: _bg,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(28),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
              child: Container(
                decoration: BoxDecoration(
                  color: _panel,
                  borderRadius: BorderRadius.circular(28),
                  border: Border.all(color: _border),
                ),
                child: Column(
                  children: [
                    const SizedBox(height: 38),
                    _icon(),
                    const SizedBox(height: 26),
                    const Text(
                      '友達と、今日の1曲を。',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      '15sは、友達と毎晩\n'
                      '「今日聞いた1曲」を選ぶ音楽SNS。\n'
                      'まずは一緒に使う友達を招待しよう',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Color(0xFFD4D4D4),
                        fontSize: 13,
                        height: 1.5,
                      ),
                    ),
                    const SizedBox(height: 20),
                    Expanded(child: Center(child: _card(ready))),
                    const SizedBox(height: 12),
                    _sendButton(ready),
                    const SizedBox(height: 16),
                    GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: widget.onDone,
                      child: const Padding(
                        padding:
                            EdgeInsets.symmetric(vertical: 6, horizontal: 32),
                        child: Text(
                          'あとで',
                          style: TextStyle(color: Color(0xFF999999), fontSize: 13),
                        ),
                      ),
                    ),
                    const SizedBox(height: 18),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _icon() {
    return Container(
      width: 64,
      height: 64,
      decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
      alignment: Alignment.center,
      child: const Icon(Icons.people_alt, color: Colors.black, size: 32),
    );
  }

  /// 招待カード（QR 入り）。ストーリーに流すのと同じ絵を見せる。
  /// 中身が揃うまではプレースホルダを出す。
  Widget _card(bool ready) {
    if (!ready) {
      return const SizedBox(
        height: 180,
        child: Center(
          child: CircularProgressIndicator(color: Colors.white24, strokeWidth: 2),
        ),
      );
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        // カードは 378×334 の実寸で組んであるので、枠に合わせて縮める。
        const cardWidth = 378.0;
        final scale = constraints.maxWidth / cardWidth;
        return SizedBox(
          width: constraints.maxWidth,
          height: 334 * scale,
          child: Transform.scale(
            scale: scale,
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: cardWidth,
              height: 334,
              child: InviteStoryCard.caseOnly(
                username: _username!,
                qrData: InviteStoryService.profileUrl(
                  uid: _uid!,
                  inviteCode: _inviteCode,
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _sendButton(bool ready) {
    return SizedBox(
      width: double.infinity,
      height: 43,
      child: ElevatedButton(
        onPressed: ready && !_sharing ? _share : null,
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.white,
          disabledBackgroundColor: Colors.white24,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
        child: Text(
          _sharing ? '準備中...' : 'リンクを送信',
          style: const TextStyle(
            color: Colors.black,
            fontSize: 13,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }
}

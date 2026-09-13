import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../constants/profile_fonts.dart';
import '../models/user_model.dart';
import '../services/friend_service.dart';
import '../widgets/common/app_toast.dart';
import '../widgets/profile_widgets.dart';

/// 登録フローの最後（音楽サービス連携のあと、ホームに入る前）に出す
/// 「知り合いかも」画面。
///
/// 出すのは **自分と同じ人の招待コードで登録したユーザー**だけ。登録直後は
/// 友達も ADL 班も無いため共通の友達では候補が作れず、招待者が同じ人＝同じ
/// コミュニティから来た可能性が高いという根拠だけが使える。
///
/// 候補が 0 人のときはこの画面自体を出さない（[loadCandidates] で事前に判定する）。
class OnboardingFriendsScreen extends StatefulWidget {
  /// 事前に取得済みの候補。呼び出し側が [loadCandidates] で取得したものを渡す。
  final List<FriendSuggestion> suggestions;

  /// 「はじめる」を押した / 候補を処理し終えたときに呼ぶ。
  final VoidCallback onDone;

  const OnboardingFriendsScreen({
    super.key,
    required this.suggestions,
    required this.onDone,
  });

  /// 同じ招待者から入った候補を取得する。空ならこの画面は出さない。
  static Future<List<FriendSuggestion>> loadCandidates() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return const [];
    return FriendService().loadSameInviterSuggestions(uid);
  }

  @override
  State<OnboardingFriendsScreen> createState() =>
      _OnboardingFriendsScreenState();
}

class _OnboardingFriendsScreenState extends State<OnboardingFriendsScreen> {
  static const Color _bg = Color(0xFF161C1F);

  final FriendService _friendService = FriendService();

  /// 「追加」を押した相手（ボタンの見た目を即時に切り替える楽観 UI）。
  final Set<String> _added = {};
  bool _busy = false;

  String? get _uid => FirebaseAuth.instance.currentUser?.uid;

  Future<void> _add(UserModel user) async {
    final uid = _uid;
    if (uid == null) return;
    setState(() => _added.add(user.uid));
    try {
      await _friendService.addFriend(
        currentUserId: uid,
        targetUserId: user.uid,
      );
    } catch (_) {
      if (!mounted) return;
      setState(() => _added.remove(user.uid));
      AppToast.show(context, '追加に失敗しました');
    }
  }

  /// 表示中の候補をまとめて追加する。
  Future<void> _addAll() async {
    final uid = _uid;
    if (uid == null || _busy) return;
    setState(() => _busy = true);
    for (final s in widget.suggestions) {
      if (_added.contains(s.user.uid)) continue;
      try {
        await _friendService.addFriend(
          currentUserId: uid,
          targetUserId: s.user.uid,
        );
        if (mounted) setState(() => _added.add(s.user.uid));
      } catch (_) {/* 1 件失敗しても続ける */}
    }
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final all = widget.suggestions.length;
    final remaining = all - _added.length;

    return Scaffold(
      backgroundColor: _bg,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 24),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 24),
              child: Text(
                '知り合いかも',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 26,
                  fontWeight: FontWeight.w700,
                  fontFamily: kSfProRounded,
                ),
              ),
            ),
            const SizedBox(height: 8),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 24),
              child: Text(
                '同じ人から招待された人たちです。\n友達になると、その日の1曲が見られるようになります。',
                style: TextStyle(
                  color: Color(0xFF9F9F9F),
                  fontSize: 13,
                  height: 1.6,
                ),
              ),
            ),
            const SizedBox(height: 20),
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                itemCount: widget.suggestions.length,
                itemBuilder: (_, i) => _row(widget.suggestions[i]),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
              child: Column(
                children: [
                  if (remaining > 0)
                    SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: ElevatedButton(
                        onPressed: _busy ? null : _addAll,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.white,
                          disabledBackgroundColor: Colors.white24,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(26),
                          ),
                        ),
                        child: Text(
                          _busy ? '追加中...' : 'すべて追加（$remaining人）',
                          style: const TextStyle(
                            color: Color(0xFF161C1F),
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            fontFamily: kSfProRounded,
                          ),
                        ),
                      ),
                    ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: TextButton(
                      onPressed: _busy ? null : widget.onDone,
                      child: Text(
                        remaining == all ? 'あとで' : 'はじめる',
                        style: const TextStyle(
                          color: Color(0xFFBDBDBD),
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          fontFamily: kSfProRounded,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _row(FriendSuggestion s) {
    final u = s.user;
    final added = _added.contains(u.uid);
    final name = (u.name?.isNotEmpty == true) ? u.name! : (u.username ?? 'ユーザー');

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 5),
      child: Row(
        children: [
          Container(
            width: 50,
            height: 50,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              color: Color(0xFF4A4A4A),
            ),
            child: ClipOval(
              child: ProfileImage(imageUrl: u.profileImageUrl, size: 50),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFFE9E9E9),
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    fontFamily: kSfProRounded,
                  ),
                ),
                if ((u.username ?? '').isNotEmpty)
                  Text(
                    '@${u.username}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Color(0xFF9F9F9F),
                      fontSize: 12,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: added || _busy ? null : () => _add(u),
            child: Container(
              width: 68,
              height: 32,
              decoration: BoxDecoration(
                color: added ? const Color(0xFF222224) : Colors.white,
                borderRadius: BorderRadius.circular(25),
              ),
              alignment: Alignment.center,
              child: added
                  ? const Icon(Icons.check, size: 16, color: Colors.white54)
                  : const Text(
                      '追加',
                      style: TextStyle(
                        color: Color(0xFF161C1F),
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../constants/profile_fonts.dart';
import '../models/user_model.dart';
import '../services/friend_service.dart';
import '../services/user_service.dart';
import '../utils/app_log.dart';
import '../widgets/common/app_toast.dart';
import '../widgets/profile_widgets.dart';

/// 他人のプロフィール（Figma 5761-11583）。
///
/// 出すのは「誰か」と「自分との距離」だけ。アイコン・名前・@ID・共通の
/// 友達・追加ボタンで終わり。
///
/// 以前はここに Memories / Saved のタブ、週カード、プレイリスト、保存した
/// 曲とアーティストの一覧まで載せていたが、自分のプロフィールを作り直した
/// ときに揃えて全部落とした。
///
/// 座標は Figma の 402×874 をそのまま持ち、画面幅に合わせて丸ごと拡縮する
/// （自分のプロフィールと同じやり方）。
class OtherUserProfileScreen extends StatefulWidget {
  final String userId;

  const OtherUserProfileScreen({super.key, required this.userId});

  @override
  State<OtherUserProfileScreen> createState() => _OtherUserProfileScreenState();
}

const double _designW = 402;
const double _designH = 874;

class _OtherUserProfileScreenState extends State<OtherUserProfileScreen> {
  static const Color _bg = Color(0xFF121212);
  static const Color _handleColor = Color(0xFFA3A3A3);
  static const Color _pillBg = Color(0xFF262626);
  static const Color _addLabel = Color(0xFF222224);

  final UserService _userService = UserService();

  UserModel? _user;
  bool _loading = true;

  /// 自分がこの人をフォローしているか（＝「追加」済みか）。
  bool _following = false;

  /// 共通の友達。ピルに人数と先頭 2 人のアイコンを出す。
  int _mutualCount = 0;
  List<String?> _mutualIcons = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final myUid = FirebaseAuth.instance.currentUser?.uid;
    try {
      // 相手と自分をまとめて取る。共通の友達は両者の友達 uid の積なので、
      // どちらも揃ってから数える。
      final results = await Future.wait([
        _userService.getUser(widget.userId),
        if (myUid != null) _userService.getUser(myUid),
      ]);
      if (!mounted) return;

      final target = results[0];
      final me = results.length > 1 ? results[1] : null;

      setState(() {
        _user = target;
        _following = me?.isFollowing(widget.userId) ?? false;
        _loading = false;
      });

      if (target != null && me != null) await _loadMutual(me, target);
    } catch (e) {
      AppLog.debug('OtherUserProfile: 読み込みに失敗: $e');
      if (mounted) setState(() => _loading = false);
    }
  }

  /// 共通の友達を数えて、先頭 2 人のアイコンを引く。
  Future<void> _loadMutual(UserModel me, UserModel target) async {
    try {
      final mine = FriendService.friendUidsOf(me).toSet();
      final theirs = FriendService.friendUidsOf(target);
      final shared = [for (final u in theirs) if (mine.contains(u)) u];
      if (shared.isEmpty || !mounted) return;

      final icons = await Future.wait(
        [for (final uid in shared.take(2)) _userService.getUser(uid)],
      );
      if (!mounted) return;
      setState(() {
        _mutualCount = shared.length;
        _mutualIcons = [for (final u in icons) u?.profileImageUrl];
      });
    } catch (e) {
      AppLog.debug('OtherUserProfile: 共通の友達を数えられず: $e');
    }
  }

  Future<void> _toggleFollow() async {
    final myUid = FirebaseAuth.instance.currentUser?.uid;
    if (myUid == null) return;

    HapticFeedback.mediumImpact();
    final before = _following;
    setState(() => _following = !before);

    try {
      if (_following) {
        await _userService.followUser(
          currentUserId: myUid,
          targetUserId: widget.userId,
        );
      } else {
        await _userService.unfollowUser(
          currentUserId: myUid,
          targetUserId: widget.userId,
        );
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _following = before);
      AppToast.show(context, '変更できませんでした');
    }
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final scale = width / _designW;

    return Scaffold(
      backgroundColor: _bg,
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: Colors.white24))
          : SizedBox.expand(
              child: Transform.scale(
                scale: scale,
                alignment: Alignment.topLeft,
                child: SizedBox(
                  width: _designW,
                  height: _designH,
                  child: Stack(children: _content()),
                ),
              ),
            ),
    );
  }

  List<Widget> _content() => [
        _backButton(),
        _avatar(),
        _name(),
        _handle(),
        if (_mutualCount > 0) _mutualPill(),
        _addButton(),
      ];

  /// 戻る。Figma には無いが、無いと前の画面へ戻れない
  /// （スワイプだけに頼らせない）。
  Widget _backButton() {
    return Positioned(
      left: 8,
      top: 56,
      child: IconButton(
        onPressed: () => Navigator.of(context).maybePop(),
        icon: const Icon(Icons.arrow_back_ios_new,
            color: Colors.white, size: 20),
      ),
    );
  }

  Widget _avatar() {
    return Positioned(
      left: 156,
      top: 122,
      child: ClipOval(
        child: Container(
          width: 89,
          height: 89,
          color: const Color(0xFF3A3A3A),
          child: ProfileImage(imageUrl: _user?.profileImageUrl, size: 89),
        ),
      ),
    );
  }

  Widget _name() {
    return Positioned(
      left: 20,
      right: 20,
      top: 239,
      child: Text(
        _user?.name?.isNotEmpty == true
            ? _user!.name!
            : (_user?.username ?? ''),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        textAlign: TextAlign.center,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 24,
          height: 1.2,
          fontWeight: FontWeight.w600,
          fontFamily: kSfProRounded,
        ),
      ),
    );
  }

  Widget _handle() {
    return Positioned(
      left: 20,
      right: 20,
      top: 268,
      child: Text(
        _user?.username != null ? '@${_user!.username}' : '',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        textAlign: TextAlign.center,
        style: const TextStyle(
          color: _handleColor,
          fontSize: 15,
          height: 1.2,
          fontWeight: FontWeight.w600,
          fontFamily: kSfProRounded,
        ),
      ),
    );
  }

  /// 「N人の共通」。アイコンは 2 枚重ね、1 枚目だけ少し傾ける（Figma）。
  Widget _mutualPill() {
    return Positioned(
      left: 114,
      top: 325,
      child: Container(
        width: 174,
        height: 52,
        decoration: BoxDecoration(
          color: _pillBg,
          borderRadius: BorderRadius.circular(15),
        ),
        child: Stack(
          children: [
            Positioned(
              left: 15.9,
              top: 13.8,
              child: Transform.rotate(
                angle: -9.51 * 3.1415926535 / 180,
                child: _mutualAvatar(_mutualIcons.elementAtOrNull(0)),
              ),
            ),
            Positioned(
              left: 44,
              top: 11,
              child: _mutualAvatar(_mutualIcons.elementAtOrNull(1)),
            ),
            Positioned(
              left: 82,
              right: 8,
              top: 17,
              child: Text(
                '$_mutualCount人の共通',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  height: 1.2,
                  fontWeight: FontWeight.w600,
                  fontFamily: kSfProRounded,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _mutualAvatar(String? url) {
    return ClipOval(
      child: Container(
        width: 30,
        height: 30,
        color: const Color(0xFF3A3A3A),
        child: ProfileImage(imageUrl: url, size: 30),
      ),
    );
  }

  /// 「＋ 追加」。追加済みのときは落ち着いた見た目にして、押すと外せる。
  Widget _addButton() {
    final added = _following;
    return Positioned(
      left: 159,
      top: 418,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _toggleFollow,
        child: Container(
          width: 84,
          height: 38,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: added ? _pillBg : Colors.white,
            borderRadius: BorderRadius.circular(25),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (!added) ...[
                const Icon(Icons.add, size: 16, color: _addLabel),
                const SizedBox(width: 4),
              ],
              Text(
                added ? '追加済み' : '追加',
                style: TextStyle(
                  color: added ? Colors.white : _addLabel,
                  fontSize: 14,
                  height: 1.2,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

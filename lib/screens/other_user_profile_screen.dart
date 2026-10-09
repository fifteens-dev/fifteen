import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../constants/profile_fonts.dart';
import '../models/user_model.dart';
import '../models/post_model.dart';
import '../services/friend_service.dart';
import '../services/post_service.dart';
import '../services/profile_snapshot_service.dart';
import '../services/user_service.dart';
import '../utils/app_log.dart';
import '../widgets/common/app_toast.dart';
import '../widgets/profile_widgets.dart';
import 'profile_screen.dart';

/// 相手との関係。見せる中身がまるごと変わる。
enum _Relation {
  /// まだ追加していない。Figma 5761-11583。
  none,

  /// 自分から追加したが、まだ返ってきていない。Figma 5761-11612。
  pending,

  /// 相互。Figma 5761-12112（自分のプロフィールと同じ形）。
  friend,
}

/// 他人のプロフィール。
///
/// 友達かどうかで見せるものが変わる。
///
///   未追加・承認待ち  アイコン / 名前 / @ID / 共通の友達 / ボタン だけ
///   友達            自分のプロフィールと同じ（top artists / recent choice）
///
/// 相手の音楽の顔は、友達になるまで見せない。
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
  static const Color _waitingBg = Color(0xFF222224);

  final UserService _userService = UserService();
  final PostService _postService = PostService();

  UserModel? _user;
  bool _loading = true;

  /// 自分がこの人をフォローしているか（＝「追加」済みか）。
  bool _following = false;

  /// 相手が自分をフォローしているか。両方立っていれば友達。
  bool _followedBy = false;

  _Relation get _relation {
    if (_following && _followedBy) return _Relation.friend;
    if (_following) return _Relation.pending;
    return _Relation.none;
  }

  /// 共通の友達。ピルに人数と先頭 2 人のアイコンを出す。
  int _mutualCount = 0;
  List<String?> _mutualIcons = const [];

  /// 友達のときだけ使う。相手の投稿と、そこから数えた top artists。
  List<PostModel> _posts = const [];
  List<String> _topArtistNames = const [];

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
        _followedBy = target?.following.contains(myUid) ?? false;
        _loading = false;
      });

      if (target != null && me != null) await _loadMutual(me, target);
      if (_relation == _Relation.friend) await _loadFriendContent();
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

  /// 友達のときだけ出す中身（投稿・top artists）。
  ///
  /// top artists は本人の投稿から数える。Apple Music の再生履歴は
  /// **この端末＝自分のもの**なので、他人には使えない。
  Future<void> _loadFriendContent() async {
    try {
      final result =
          await _postService.getPostsByUserIdPaged(widget.userId, limit: 60);
      if (!mounted) return;
      final posts = result.posts;
      final names = ProfileSnapshotService.rankByCount(
        ProfileSnapshotService.artistNamesFromPosts(posts),
      );
      setState(() {
        _posts = posts;
        _topArtistNames = names;
      });
    } catch (e) {
      AppLog.debug('OtherUserProfile: 投稿を読めず: $e');
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

    if (_loading) {
      return const Scaffold(
        backgroundColor: _bg,
        body: Center(child: CircularProgressIndicator(color: Colors.white24)),
      );
    }

    // 友達になったら、自分のプロフィールと同じ形で相手の音楽の顔を出す
    // （Figma 5761-12112）。それまでは名前と共通の友達だけ。
    if (_relation == _Relation.friend) {
      return Scaffold(
        backgroundColor: _bg,
        body: SingleChildScrollView(child: _friendView()),
      );
    }

    return Scaffold(
      backgroundColor: _bg,
      body: SizedBox.expand(
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

  Widget _friendView() {
    return ProfileView(
      name: _user?.name?.isNotEmpty == true
          ? _user!.name!
          : (_user?.username ?? ''),
      username: _user?.username,
      avatarUrl: _user?.profileImageUrl,
      // ピルは共通の友達（Figma の「2人の共通」）。
      friendCount: _mutualCount,
      friendIcons: _mutualIcons,
      pillLabel: '$_mutualCount人の共通',
      postCount: _posts.length,
      streakDays: 0,
      topArtists: [for (final n in _topArtistNames) (name: n, artistId: null)],
      recentPosts: [
        for (final p in _posts.take(3))
          (
            albumImageUrl: p.track.albumImageUrl,
            trackName: p.track.trackName,
            artistName: p.track.artistName,
          ),
      ],
      // 設定は自分のものなので渡さない（渡さなければ出ない）。
      onBack: () => Navigator.of(context).maybePop(),
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

  /// 未追加なら「＋ 追加」（Figma 5761-11583）、押した直後から
  /// 「承認待ち」（Figma 5761-11612）。相手が返してくれたら友達になり、
  /// この面ごと [ProfileView] に変わる。
  ///
  /// 承認待ちを押すと取り消せる。取り消せないと、誤って送ったときに
  /// 相手の承認を待つしかなくなる。
  Widget _addButton() {
    final waiting = _relation == _Relation.pending;
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
            color: waiting ? _waitingBg : Colors.white,
            borderRadius: BorderRadius.circular(25),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (!waiting) ...[
                const Icon(Icons.add, size: 16, color: _addLabel),
                const SizedBox(width: 4),
              ],
              Text(
                waiting ? '承認待ち' : '追加',
                style: TextStyle(
                  color: waiting ? Colors.white : _addLabel,
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

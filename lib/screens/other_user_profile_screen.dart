import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../constants/profile_fonts.dart';
import '../models/user_model.dart';
import '../models/post_model.dart';
import '../services/group_service.dart';
import '../services/music_memory_cycle_service.dart';
import '../services/post_service.dart';
import '../services/profile_snapshot_service.dart';
import '../services/user_service.dart';
import '../utils/app_log.dart';
import '../widgets/profile_widgets.dart';
import 'profile_screen.dart';

/// 他人のプロフィール。
///
/// 同じグループにいるかで見せるものが変わる。
///
///   同じグループでない  アイコン / 名前 / @ID だけ
///   同じグループ        自分のプロフィールと同じ（top artists / recent choice）
///
/// 以前は友達（相互フォロー）かどうかで分け、「＋ 追加」「承認待ち」の
/// ボタンと共通の友達のピルを出していた。友達機能の廃止（2026-11-01）で
/// グループに置き換えた。フォローのデータ自体は Firestore に残してある。
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

  final UserService _userService = UserService();
  final PostService _postService = PostService();

  UserModel? _user;
  bool _loading = true;

  /// 自分と同じグループにいるか。
  bool _isGroupmate = false;

  /// 自分自身を開いたか（自分の投稿カードのアイコンから来る）。
  /// 自分のプロフィールと同じ形で出す。
  bool get _isMe =>
      widget.userId == FirebaseAuth.instance.currentUser?.uid;

  bool get _canSeeContent => _isMe || _isGroupmate;

  /// 同じグループのときだけ使う。相手の投稿と、そこから数えた top artists。
  List<PostModel> _posts = const [];
  List<String> _topArtistNames = const [];

  /// 相手の連続投稿日数。
  int _streakDays = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final myUid = FirebaseAuth.instance.currentUser?.uid;
    try {
      final results = await Future.wait([
        _userService.getUser(widget.userId),
        if (myUid != null) GroupService().isGroupmate(myUid, widget.userId),
      ]);
      if (!mounted) return;

      setState(() {
        _user = results[0] as UserModel?;
        _isGroupmate = results.length > 1 && results[1] == true;
        _loading = false;
      });

      if (_canSeeContent) await _loadContent();
    } catch (e) {
      AppLog.debug('OtherUserProfile: 読み込みに失敗: $e');
      if (mounted) setState(() => _loading = false);
    }
  }

  /// 同じグループのときだけ出す中身（投稿・top artists）。
  ///
  /// top artists は本人の投稿から数える。Apple Music の再生履歴は
  /// **この端末＝自分のもの**なので、他人には使えない。
  Future<void> _loadContent() async {
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

      // 連続日数はサイクルの境界が要るので、投稿が揃ってから数える。
      final streak = await MusicMemoryCycleService()
          .streakDays([for (final p in posts) p.createdAt]);
      if (mounted) setState(() => _streakDays = streak);
    } catch (e) {
      AppLog.debug('OtherUserProfile: 投稿を読めず: $e');
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

    // 同じグループなら、自分のプロフィールと同じ形で相手の音楽の顔を出す
    // （Figma 5761-12112）。そうでなければ名前だけ。
    if (_canSeeContent) {
      return Scaffold(
        backgroundColor: _bg,
        body: SingleChildScrollView(child: _contentView()),
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

  Widget _contentView() {
    return ProfileView(
      name: _user?.name?.isNotEmpty == true
          ? _user!.name!
          : (_user?.username ?? ''),
      username: _user?.username,
      avatarUrl: _user?.profileImageUrl,
      // 友達のピルは友達機能の廃止で出さない。
      friendCount: 0,
      friendIcons: const [],
      showFriendsPill: false,
      postCount: _posts.length,
      streakDays: _streakDays,
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
}

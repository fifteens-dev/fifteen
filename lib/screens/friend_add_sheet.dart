import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../constants/profile_fonts.dart';
import '../models/user_model.dart';
import '../services/friend_match_service.dart';
import '../services/invite_story_service.dart';
import '../services/friend_service.dart';
import '../services/user_service.dart';
import '../widgets/common/app_toast.dart';
import '../widgets/profile_widgets.dart';
import 'other_user_profile_screen.dart';

/// ホームの友達追加ボタンから開くシート（Figma 5539:11181）。
///
/// 構成は上から:
///  - 検索欄「友達を検索」＋ キャンセル
///  - 招待カード（自分の招待コード・共有）
///  - 「15sのリンクを共有」LINE / Instagram / X / その他
///  - 「あなたの友達」（相互フォロー。今日投稿済みなら緑、未投稿はグレーのリング）
///  - 「知り合いかも」（共通の友達 / 同じADL班）
///
/// 検索欄に入力している間は、上記の代わりに検索結果を出す。
class FriendAddSheet extends StatefulWidget {
  const FriendAddSheet({super.key});

  static Future<void> show(BuildContext context) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.45),
      builder: (_) => const FriendAddSheet(),
    );
  }

  @override
  State<FriendAddSheet> createState() => _FriendAddSheetState();
}

class _FriendAddSheetState extends State<FriendAddSheet> {
  static const Color _bg = Color(0xFF161C1F);
  static const Color _card = Color(0xFF2D2D2D);
  static const Color _label = Color(0xFFBDBDBD);
  static const Color _posted = Color(0xFF4CC764); // 今日投稿済みのリング
  static const Color _notPosted = Color(0xFF5A5A5A); // 未投稿のリング

  // 共有アイコン（Figma 5539:11200）: 58px の円に 2px ボーダー、中身は 50px。
  static const double _iconOuter = 58;
  static const double _iconInner = 50;

  final FriendService _friendService = FriendService();
  final UserService _userService = UserService();
  final TextEditingController _searchController = TextEditingController();

  String? _uid;
  String? _inviteCode;
  UserModel? _me;

  /// Instagram 用のカード画像を作っている間。1 秒ほどかかるので、
  /// 押したのに何も起きていないように見えないようアイコンを差し替える。
  bool _sharingToInstagram = false;

  List<FriendEntry> _friends = const [];
  List<FriendSuggestion> _suggestions = const [];
  bool _loading = true;

  // 検索
  String _query = '';
  List<UserModel> _results = const [];
  bool _searching = false;
  Timer? _debounce;

  /// 直近に問い合わせたクエリ。同じ内容の再検索を弾く。
  String? _lastQueried;

  /// 「追加」を押した相手（ボタンの見た目を即時に切り替えるための楽観 UI）。
  final Set<String> _requested = {};

  /// 友達一覧を全件出しているか。既定は [_friendsPreviewCount] 件だけ見せる。
  bool _friendsExpanded = false;
  static const int _friendsPreviewCount = 2;

  @override
  void initState() {
    super.initState();
    _uid = FirebaseAuth.instance.currentUser?.uid;
    _load();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final uid = _uid;
    if (uid == null) {
      setState(() => _loading = false);
      return;
    }
    final results = await Future.wait([
      _userService.getUser(uid),
      _userService.ensureInviteCode(uid),
      _friendService.loadFriends(uid),
      _friendService.loadSuggestions(uid),
    ]);
    if (!mounted) return;
    setState(() {
      _me = results[0] as UserModel?;
      _inviteCode = results[1] as String?;
      _friends = results[2] as List<FriendEntry>;
      _suggestions = results[3] as List<FriendSuggestion>;
      _loading = false;
    });
  }

  // ── 検索 ────────────────────────────────────────────────

  void _onQueryChanged(String value) {
    final q = value.trim();
    setState(() => _query = q);
    _debounce?.cancel();
    if (q.isEmpty) {
      _lastQueried = null;
      setState(() {
        _results = const [];
        _searching = false;
      });
      return;
    }
    setState(() => _searching = true);
    _debounce = Timer(const Duration(milliseconds: 300), () => _runSearch(q));
  }

  Future<void> _runSearch(String q) async {
    // 同じクエリを二重に投げない（SearchScreen の挙動を踏襲）。
    if (_lastQueried == q) {
      if (mounted) setState(() => _searching = false);
      return;
    }
    _lastQueried = q;
    try {
      final users = await _userService.searchUsers(query: q, limit: 30);
      if (!mounted || _query != q) return;
      setState(() {
        _results = users;
        _searching = false;
      });
    } catch (_) {
      if (!mounted || _query != q) return;
      setState(() {
        _results = const [];
        _searching = false;
      });
      AppToast.show(context, '検索中にエラーが発生しました');
    }
  }

  /// 検索結果・友達・知り合いかもの行から遷移する。
  /// 自分自身をタップしたときは自分のプロフィールへ（SearchScreen と同じ分岐）。
  void _openProfile(String userId) {
    Navigator.of(context).pop();
    if (userId == _uid) {
      Navigator.of(context).pushNamed('/profile');
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => OtherUserProfileScreen(userId: userId)),
    );
  }

  // ── 招待リンクの共有 ────────────────────────────────────

  /// 招待コード付きの共有 URL。開くとコードがクリップボードに入り、
  /// App Store へ誘導される。アプリ側は起動時にそれを拾って自動入力する。
  /// 末尾スラッシュ無し。Firebase Hosting は trailingSlash:false なので
  /// `/invite/` だと 301 を 1 回挟む（一部のメッセージアプリでプレビューが崩れる）。
  String get _inviteUrl =>
      'https://fifteens-39cfe.web.app/invite?code=${_inviteCode ?? ''}';

  String get _shareText =>
      '15sで友達になろう！\n招待コード：${_inviteCode ?? ''}\n$_inviteUrl';

  /// 招待カードの QR に埋める URL。組み立ては [InviteStoryService] に置いてある
  /// （プロフィールの共有シートと同じものを使うため）。
  String? get _profileUrl {
    final uid = _uid;
    if (uid == null) return null;
    return InviteStoryService.profileUrl(uid: uid, inviteCode: _inviteCode);
  }

  Future<void> _shareTo(_ShareTarget target) async {
    if (_inviteCode == null) {
      AppToast.show(context, '招待コードを取得中です');
      return;
    }
    final encoded = Uri.encodeComponent(_shareText);

    switch (target) {
      case _ShareTarget.line:
        await _openOrFallback(Uri.parse('https://line.me/R/msg/text/?$encoded'));
        return;
      case _ShareTarget.x:
        await _openOrFallback(
            Uri.parse('https://twitter.com/intent/tweet?text=$encoded'));
        return;
      case _ShareTarget.instagram:
        await _shareToInstagramStory();
        return;
      case _ShareTarget.other:
        await _openSystemShareSheet();
        return;
    }
  }

  /// 招待カード（QR 入り）を画像にして Instagram ストーリーの編集画面を開く。
  ///
  /// Instagram は iOS の共有シートでプレーンテキストを受け取れない
  /// （画像・動画しか受け付けない）ので、テキストを渡す道は元から無い。
  /// 以前は招待文をコピーして Instagram を開くだけだったが、
  /// ストーリー用の画像を渡せばそのまま投稿してもらえる。
  Future<void> _shareToInstagramStory() async {
    final url = _profileUrl;
    final name = _me?.username;
    if (url == null || name == null || name.isEmpty) {
      AppToast.show(context, 'プロフィールを取得中です');
      return;
    }

    setState(() => _sharingToInstagram = true);
    final ok = await InviteStoryService.shareToInstagram(
      context,
      username: name,
      qrUrl: url,
    );
    if (!mounted) return;
    setState(() => _sharingToInstagram = false);
    if (!ok) {
      // 画像は作れたが Instagram が入っていない場合もここに来る。
      await Clipboard.setData(ClipboardData(text: _shareText));
      if (!mounted) return;
      AppToast.show(context, 'Instagramを開けませんでした。リンクをコピーしました');
    }
  }

  /// URL を外部アプリで開く。開けなければ OS の共有シートに逃がす。
  Future<void> _openOrFallback(Uri url) async {
    if (await _tryLaunch(url)) return;
    await _openSystemShareSheet();
  }

  Future<bool> _tryLaunch(Uri url) async {
    try {
      return await launchUrl(url, mode: LaunchMode.externalApplication);
    } catch (_) {
      return false;
    }
  }

  /// OS の共有シート。iPad では表示位置の指定が必須なので、
  /// シート自身の矩形を渡しておく（iPhone では無視される）。
  Future<void> _openSystemShareSheet() async {
    try {
      final box = context.findRenderObject() as RenderBox?;
      await Share.share(
        _shareText,
        sharePositionOrigin: box == null
            ? null
            : box.localToGlobal(Offset.zero) & box.size,
      );
    } catch (e) {
      if (mounted) AppToast.show(context, '共有に失敗しました');
    }
  }

  Future<void> _copyInviteCode() async {
    if (_inviteCode == null) return;
    await Clipboard.setData(ClipboardData(text: _inviteCode!));
    if (mounted) AppToast.show(context, '招待コードをコピーしました');
  }

  Future<void> _addFriend(UserModel user) async {
    final uid = _uid;
    if (uid == null) return;
    setState(() => _requested.add(user.uid));
    try {
      await _friendService.addFriend(
        currentUserId: uid,
        targetUserId: user.uid,
      );
      if (!mounted) return;
      AppToast.show(context, '友達申請を送りました');
      // 相手がすでに自分を追加済みなら、この時点で友達成立になる。
      await FriendMatchService.instance.maybeCelebrate(context);
    } catch (_) {
      if (mounted) {
        setState(() => _requested.remove(user.uid));
        AppToast.show(context, '追加に失敗しました');
      }
    }
  }

  // ── build ───────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final viewInsets = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: viewInsets),
      child: FractionallySizedBox(
        heightFactor: 0.92,
        child: Container(
          decoration: const BoxDecoration(
            color: _bg,
            borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
          ),
          child: Column(
            children: [
              const SizedBox(height: 10),
              // ハンドルバー（Figma: 52×2 / #さらに薄いグレー）
              Container(
                width: 52,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 15),
              _searchBar(),
              Expanded(
                child: _query.isNotEmpty ? _searchResults() : _defaultBody(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _searchBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
      child: Row(
        children: [
          Expanded(
            child: Container(
              height: 40,
              decoration: BoxDecoration(
                color: _card,
                borderRadius: BorderRadius.circular(15),
              ),
              child: Row(
                children: [
                  const SizedBox(width: 18),
                  const Icon(Icons.search, size: 18, color: Color(0xFF727272)),
                  const SizedBox(width: 6),
                  Expanded(
                    child: TextField(
                      controller: _searchController,
                      onChanged: _onQueryChanged,
                      textInputAction: TextInputAction.search,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                      cursorColor: Colors.white,
                      decoration: const InputDecoration(
                        isDense: true,
                        border: InputBorder.none,
                        hintText: '友達を検索',
                        hintStyle: TextStyle(
                          color: Color(0xFF727272),
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                  if (_query.isNotEmpty)
                    GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () {
                        _searchController.clear();
                        _onQueryChanged('');
                      },
                      child: const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 10),
                        child: Icon(Icons.close,
                            size: 16, color: Color(0xFF727272)),
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 15),
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => Navigator.of(context).pop(),
            child: const Text(
              'キャンセル',
              style: TextStyle(
                color: Color(0xFFD3D3D2),
                fontSize: 16,
                fontWeight: FontWeight.w700,
                fontFamily: kSfProRounded,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── 通常表示 ────────────────────────────────────────────

  Widget _defaultBody() {
    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(color: Colors.white24, strokeWidth: 2),
      );
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 19, 16, 40),
      children: [
        _inviteCard(),
        const SizedBox(height: 19),
        _sectionHeader(Icons.add_circle_outline, '15sのリンクを共有',
            emphasizeFirst: '15s'),
        const SizedBox(height: 5),
        _shareRow(),
        const SizedBox(height: 22),
        _sectionHeader(Icons.people_alt, 'あなたの友達'),
        const SizedBox(height: 8),
        if (_friends.isEmpty)
          _emptyNote('まだ友達がいません。上のリンクから招待してみましょう。')
        else ...[
          ...(_friendsExpanded
                  ? _friends
                  : _friends.take(_friendsPreviewCount))
              .map(_friendRow),
          if (_friends.length > _friendsPreviewCount) _friendsToggle(),
        ],
        if (_suggestions.isNotEmpty) ...[
          const SizedBox(height: 22),
          const Padding(
            padding: EdgeInsets.only(left: 10),
            child: Text(
              '知り合いかも',
              style: TextStyle(
                  color: _label, fontSize: 16, fontWeight: FontWeight.w700),
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 182,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 5),
              itemCount: _suggestions.length,
              separatorBuilder: (_, __) => const SizedBox(width: 19),
              itemBuilder: (_, i) => _suggestionCard(_suggestions[i]),
            ),
          ),
        ],
      ],
    );
  }

  /// 「もっと見る」/「閉じる」。友達が多いときにシートが縦に伸びすぎるのを防ぐ。
  Widget _friendsToggle() {
    final hidden = _friends.length - _friendsPreviewCount;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => setState(() => _friendsExpanded = !_friendsExpanded),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(5, 6, 5, 6),
        child: Row(
          children: [
            // 友達アイコン（60px）＋間隔（22px）に合わせて文字位置を揃える。
            const SizedBox(width: 82),
            Text(
              _friendsExpanded ? '閉じる' : 'もっと見る（他 $hidden 人）',
              style: const TextStyle(
                color: Color(0xFF9F9F9F),
                fontSize: 14,
                fontWeight: FontWeight.w600,
                fontFamily: kSfProRounded,
              ),
            ),
            const SizedBox(width: 4),
            Icon(
              _friendsExpanded ? Icons.expand_less : Icons.expand_more,
              size: 18,
              color: const Color(0xFF9F9F9F),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sectionHeader(IconData icon, String text, {String? emphasizeFirst}) {
    return Padding(
      padding: const EdgeInsets.only(left: 10),
      child: Row(
        children: [
          Icon(icon, size: 19, color: const Color(0xFFDFDFDE)),
          const SizedBox(width: 9),
          if (emphasizeFirst == null)
            Text(
              text,
              style: const TextStyle(
                  color: _label, fontSize: 16, fontWeight: FontWeight.w700),
            )
          else
            Text.rich(
              TextSpan(children: [
                TextSpan(
                  text: emphasizeFirst,
                  style: const TextStyle(fontSize: 18),
                ),
                TextSpan(
                  text: text.substring(emphasizeFirst.length),
                  style: const TextStyle(fontSize: 16),
                ),
              ]),
              style: const TextStyle(
                color: Color(0xFFDFDFDE),
                fontWeight: FontWeight.w700,
                fontFamily: kSfProRounded,
              ),
            ),
        ],
      ),
    );
  }

  Widget _emptyNote(String text) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 12, 10, 4),
      child: Text(
        text,
        style: const TextStyle(color: Colors.white38, fontSize: 13, height: 1.6),
      ),
    );
  }

  /// 招待カード。自分のアイコン・招待コード・共有ボタン。
  Widget _inviteCard() {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _copyInviteCode,
      child: Container(
        height: 68,
        decoration: BoxDecoration(
          color: _card,
          borderRadius: BorderRadius.circular(18),
        ),
        child: Row(
          children: [
            const SizedBox(width: 19),
            _avatar(_me?.profileImageUrl, 40),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '友達を15sに招待する',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '招待コード：${_inviteCode ?? '...'}',
                    style: const TextStyle(
                        color: Color(0xFF9F9F9F), fontSize: 12),
                  ),
                ],
              ),
            ),
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => _shareTo(_ShareTarget.other),
              child: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 18),
                child: Icon(Icons.ios_share, size: 20, color: Colors.white),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _shareRow() {
    return Container(
      height: 112,
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(21),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _shareItem(
            label: 'LINE',
            target: _ShareTarget.line,
            child: _ringedIcon(
              ring: const Color(0xFF4CC764),
              child: ClipOval(
                child: Image.asset('assets/icons/share/line.png',
                    width: _iconInner, height: _iconInner, fit: BoxFit.cover),
              ),
            ),
          ),
          _shareItem(
            label: 'Instagram',
            target: _ShareTarget.instagram,
            // Instagram の素材は 58px で自前の円を持っているのでリングを重ねない。
            child: _sharingToInstagram
                ? const SizedBox(
                    width: _iconOuter,
                    height: _iconOuter,
                    child: Center(
                      child: CupertinoActivityIndicator(color: Colors.white),
                    ),
                  )
                : SvgPicture.asset('assets/icons/share/instagram.svg',
                    width: _iconOuter, height: _iconOuter),
          ),
          _shareItem(
            label: 'X',
            target: _ShareTarget.x,
            child: _ringedIcon(
              ring: const Color(0xFF080808),
              child: ClipOval(
                child: Image.asset('assets/icons/share/x.jpg',
                    width: _iconInner, height: _iconInner, fit: BoxFit.cover),
              ),
            ),
          ),
          _shareItem(
            label: 'その他',
            target: _ShareTarget.other,
            child: _ringedIcon(
              ring: const Color(0xFF3E3E3D),
              child: SvgPicture.asset('assets/icons/share/other.svg',
                  width: _iconInner, height: _iconInner),
            ),
          ),
        ],
      ),
    );
  }

  /// 共有アイコンの外周リング（Figma 5539:11200）。
  /// 58px の円に 2px のボーダーを引き、中に 50px のアイコンを中央寄せする。
  Widget _ringedIcon({required Color ring, required Widget child}) {
    return Container(
      width: _iconOuter,
      height: _iconOuter,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: ring, width: 2),
      ),
      child: Center(child: child),
    );
  }

  Widget _shareItem({
    required String label,
    required _ShareTarget target,
    required Widget child,
  }) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _sharingToInstagram ? null : () => _shareTo(target),
      child: SizedBox(
        width: 68,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            child,
            const SizedBox(height: 6),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: const Color(0xFFE9E9E9),
                fontSize: label.length > 3 ? 13 : 15,
                fontWeight: FontWeight.w600,
                fontFamily: kSfProRounded,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 友達 1 行。今日投稿していれば緑、していなければグレーのリングを巻く。
  Widget _friendRow(FriendEntry entry) {
    final u = entry.user;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => _openProfile(u.uid),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8.5, horizontal: 5),
        child: Row(
          children: [
            Container(
              width: 60,
              height: 60,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: entry.postedToday ? _posted : _notPosted,
                  width: 2.5,
                ),
              ),
              child: Center(child: _avatar(u.profileImageUrl, 50)),
            ),
            const SizedBox(width: 22),
            Expanded(
              child: Text(
                _displayName(u),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Color(0xFFE9E9E9),
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  fontFamily: kSfProRounded,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _suggestionCard(FriendSuggestion s) {
    final added = _requested.contains(s.user.uid);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => _openProfile(s.user.uid),
      child: Container(
        width: 140,
        decoration: BoxDecoration(
          color: _card,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Column(
          children: [
            const SizedBox(height: 24),
            _avatar(s.user.profileImageUrl, 50),
            const SizedBox(height: 7),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Text(
                _displayName(s.user),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w500,
                  fontFamily: kSfProRounded,
                ),
              ),
            ),
            const SizedBox(height: 5),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: Text(
                s.reason,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Color(0xFFA3A3A3),
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                  fontFamily: kSfProRounded,
                ),
              ),
            ),
            const Spacer(),
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: added ? null : () => _addFriend(s.user),
              child: Container(
                width: 52,
                height: 29,
                decoration: BoxDecoration(
                  color: const Color(0xFF222224),
                  borderRadius: BorderRadius.circular(25),
                ),
                alignment: Alignment.center,
                child: added
                    ? const Icon(Icons.check, size: 14, color: Colors.white54)
                    : const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.add, size: 12, color: Colors.white),
                          SizedBox(width: 2),
                          Text('追加',
                              style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700)),
                        ],
                      ),
              ),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  // ── 検索結果 ────────────────────────────────────────────

  Widget _searchResults() {
    if (_searching) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.only(top: 40),
          child: CupertinoActivityIndicator(color: Colors.white, radius: 8),
        ),
      );
    }
    if (_results.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(32, 40, 32, 0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.search_off, size: 56, color: Color(0xFF9F9F9F)),
              const SizedBox(height: 14),
              Text(
                '「$_query」に一致する結果が見つかりませんでした',
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 15, color: Color(0xFF9F9F9F)),
              ),
              const SizedBox(height: 8),
              const Text(
                '名前でもユーザーIDでも検索できます',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: Colors.white24),
              ),
            ],
          ),
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 40),
      itemCount: _results.length,
      itemBuilder: (_, i) => _searchRow(_results[i]),
    );
  }

  Widget _searchRow(UserModel u) {
    // 相互フォロー数＝友達の人数。UserModel が両方の配列を持つので追加取得は不要。
    final friendCount = FriendService.friendUidsOf(u).length;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => _openProfile(u.uid),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 5),
        child: Row(
          children: [
            _avatar(u.profileImageUrl, 50),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _displayName(u),
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
                          color: Color(0xFF9F9F9F), fontSize: 12),
                    ),
                ],
              ),
            ),
            if (friendCount > 0)
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: _card,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  '友達 $friendCount',
                  style: const TextStyle(
                      fontSize: 11, color: Color(0xFF9F9F9F)),
                ),
              ),
          ],
        ),
      ),
    );
  }

  // ── 共通パーツ ──────────────────────────────────────────

  static String _displayName(UserModel u) =>
      (u.name?.isNotEmpty == true) ? u.name! : (u.username ?? 'ユーザー');

  Widget _avatar(String? url, double size) {
    return Container(
      width: size,
      height: size,
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        color: Color(0xFF4A4A4A),
      ),
      child: ClipOval(child: ProfileImage(imageUrl: url, size: size)),
    );
  }
}

enum _ShareTarget { line, instagram, x, other }

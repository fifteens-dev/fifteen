import 'dart:ui' as ui;

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../constants/profile_fonts.dart';
import '../models/group_model.dart';
import '../models/user_model.dart';
import '../services/group_service.dart';
import '../widgets/common/app_toast.dart';
import '../widgets/common/glass_circle_button.dart';
import '../widgets/profile_widgets.dart';
import 'group_dialogs.dart' show GroupInviteDialog, QrGlyph;

/// グループの既定アイコン（イラスト）。
///
/// 7 種類を用意する予定で、今あるのは [_assets] のぶんだけ。足りない番号は
/// あるものを繰り返して使う（イラストが揃ったら [_assets] に足すだけでよい）。
class GroupIcons {
  static const List<String> _assets = [
    'assets/group_icons/icon_1.jpg',
    'assets/group_icons/icon_2.jpg',
    'assets/group_icons/icon_3.jpg',
    'assets/group_icons/icon_4.jpg',
    'assets/group_icons/icon_5.jpg',
    'assets/group_icons/icon_6.jpg',
    'assets/group_icons/icon_7.jpg',
  ];

  static String assetFor(int index) => _assets[index % _assets.length];
}

/// グループのアイコン（角丸の正方形）。
class GroupIconImage extends StatelessWidget {
  final int iconIndex;
  final double size;
  final double radius;

  const GroupIconImage({
    super.key,
    required this.iconIndex,
    required this.size,
    required this.radius,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: Container(
        width: size,
        height: size,
        color: Colors.white,
        child: Image.asset(GroupIcons.assetFor(iconIndex), fit: BoxFit.cover),
      ),
    );
  }
}

/// グループ設定（Figma 6314:12876）。下から出るシートで、高さは Figma 6321:13013
/// （874 の画面に対して 798）。
///
/// メンバーなら誰でも変えられる。名前はタップで変更、アイコンはタップで選び直す。
class GroupSettingsSheet extends StatefulWidget {
  final String groupId;
  final String uid;

  /// Firebase 抜きで見た目を確かめるための差し替え（テスト用）。
  @visibleForTesting
  final GroupModel? debugGroup;
  @visibleForTesting
  final List<UserModel>? debugUsers;

  const GroupSettingsSheet({
    super.key,
    required this.groupId,
    required this.uid,
    this.debugGroup,
    this.debugUsers,
  });

  /// シートを出す。グループを抜けたら true を返す。
  static Future<bool> show(
    BuildContext context, {
    required String groupId,
    required String uid,
  }) async {
    final left = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useRootNavigator: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black54,
      builder: (_) => GroupSettingsSheet(groupId: groupId, uid: uid),
    );
    return left == true;
  }

  @override
  State<GroupSettingsSheet> createState() => _GroupSettingsSheetState();
}

const double _designW = 384;
const double _screenH = 874;
const double _sheetH = 798;

const Color _sheetBg = Color(0xFF18171A);
const Color _cardBg = Color(0xFF222025);
const Color _divider = Color(0xFF2C2A30);
const Color _subGrey = Color(0xFF9B94A0);
const Color _labelGrey = Color(0xFF8F8894);

TextStyle _rounded(double size, Color color, double wght) => TextStyle(
      fontFamily: kSfProRounded,
      fontSize: size,
      color: color,
      height: 1.2,
      fontWeight: wght >= 700 ? FontWeight.bold : FontWeight.normal,
      fontVariations: [ui.FontVariation('wght', wght)],
    );

class _GroupSettingsSheetState extends State<GroupSettingsSheet> {
  late final GroupService _groupService = GroupService();
  late final Stream<GroupModel?> _groupStream;
  Map<String, UserModel> _users = const {};
  List<String> _loadedFor = const [];

  @override
  void initState() {
    super.initState();
    _groupStream = widget.debugGroup != null
        ? Stream.value(widget.debugGroup)
        : _groupService.watchGroup(widget.groupId);
    if (widget.debugUsers != null) {
      _users = {for (final u in widget.debugUsers!) u.uid: u};
    }
  }

  /// メンバーが変わったら名前とアイコンを引き直す。
  void _ensureUsers(GroupModel g) {
    if (widget.debugGroup != null || listEquals(_loadedFor, g.memberIds)) return;
    _loadedFor = List.of(g.memberIds);
    _groupService.fetchUsers(g.memberIds).then((users) {
      if (mounted) setState(() => _users = {for (final u in users) u.uid: u});
    });
    // 招待コードを持つ前に作ったグループには、ここで振る。
    if (g.inviteCode == null) {
      _groupService.updateSettings(g.groupId,
          inviteCode: GroupService.newInviteCode());
    }
  }

  String _nameOf(String uid) {
    final u = _users[uid];
    if (u?.name?.isNotEmpty == true) return u!.name!;
    return u?.username ?? '';
  }

  // ── 操作 ────────────────────────────────────────────

  /// 招待のカード（QR・共有・LINE）を出す。締め切り・10 人はそちらで断る。
  Future<void> _invite(GroupModel g) => GroupInviteDialog.show(context, g);

  Future<void> _copyCode(GroupModel g) async {
    final code = g.inviteCode;
    if (code == null) return;
    await Clipboard.setData(ClipboardData(text: code));
    if (mounted) AppToast.show(context, '招待コードをコピーしました');
  }

  void _showQr(GroupModel g) {
    final code = g.inviteCode;
    if (code == null) return;
    showCupertinoDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => Center(
        child: GestureDetector(
          onTap: () => Navigator.of(ctx).pop(),
          child: Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(24),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                QrImageView(data: code, size: 200),
                const SizedBox(height: 8),
                Text(code,
                    style: const TextStyle(
                        color: Colors.black,
                        fontSize: 18,
                        decoration: TextDecoration.none)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _rename(GroupModel g) async {
    final controller = TextEditingController(text: g.name);
    final name = await showCupertinoDialog<String>(
      context: context,
      builder: (ctx) => CupertinoAlertDialog(
        title: const Text('グループ名'),
        content: Padding(
          padding: const EdgeInsets.only(top: 12),
          child: CupertinoTextField(
            controller: controller,
            autofocus: true,
            maxLength: 20,
          ),
        ),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('キャンセル'),
          ),
          CupertinoDialogAction(
            isDefaultAction: true,
            onPressed: () => Navigator.of(ctx).pop(controller.text.trim()),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (name == null || name.isEmpty || name == g.name) return;
    await _guard(() => _groupService.updateSettings(g.groupId, name: name));
  }

  Future<void> _pickIcon(GroupModel g) async {
    final picked = await showModalBottomSheet<int>(
      context: context,
      useRootNavigator: true,
      backgroundColor: _sheetBg,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
          child: Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              for (var i = 0; i < GroupModel.iconCount; i++)
                GestureDetector(
                  onTap: () => Navigator.of(ctx).pop(i),
                  child: Container(
                    padding: const EdgeInsets.all(2),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(
                        color: i == g.iconIndex ? Colors.white : Colors.transparent,
                        width: 2,
                      ),
                    ),
                    child: GroupIconImage(iconIndex: i, size: 70, radius: 15),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
    if (picked == null || picked == g.iconIndex) return;
    await _guard(() => _groupService.updateSettings(g.groupId, iconIndex: picked));
  }

  Future<void> _leave(GroupModel g) async {
    final last = g.memberIds.length <= 1;
    final ok = await showCupertinoDialog<bool>(
      context: context,
      builder: (ctx) => CupertinoAlertDialog(
        title: const Text('グループを退出しますか？'),
        content: Text(last
            ? 'あなたが最後のメンバーなので、グループは削除されます。'
            : 'あなたの投稿はMusic Memoryやプレイリストに残ります。'),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('キャンセル'),
          ),
          CupertinoDialogAction(
            isDestructiveAction: true,
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('退出する'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final done = await _guard(() => _groupService.leaveGroup(g.groupId, widget.uid));
    if (done && mounted) Navigator.of(context).pop(true);
  }

  /// 書き込みの失敗をトーストに出す。成功したら true。
  Future<bool> _guard(Future<void> Function() action) async {
    try {
      await action();
      return true;
    } catch (_) {
      if (mounted) AppToast.show(context, '変更できませんでした');
      return false;
    }
  }

  // ── 描画 ────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final height = media.size.height * _sheetH / _screenH;
    final scale = media.size.width / 402;
    return Padding(
      // Figma のシートは 384 幅（402 の画面の左右に 9 ずつ）。
      padding: EdgeInsets.symmetric(horizontal: 9 * scale),
      child: SizedBox(
        height: height,
        child: ClipRRect(
          borderRadius: BorderRadius.vertical(top: Radius.circular(41 * scale)),
          child: ColoredBox(
            color: _sheetBg,
            child: StreamBuilder<GroupModel?>(
              stream: _groupStream,
              builder: (context, snap) {
                final g = snap.data;
                if (g == null) {
                  return const Center(
                      child: CupertinoActivityIndicator(color: Colors.white));
                }
                _ensureUsers(g);
                final contentH = _contentHeight(g);
                return SingleChildScrollView(
                  padding: EdgeInsets.only(bottom: media.padding.bottom),
                  child: FittedBox(
                    fit: BoxFit.fitWidth,
                    alignment: Alignment.topLeft,
                    child: SizedBox(
                      width: _designW,
                      height: contentH,
                      child: _content(g),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  /// メンバーの行の数で全体の高さが変わる。行は 56（最後の行は 54）。
  static double _membersCardH(GroupModel g) => 56.0 * (g.memberIds.length + 1) - 2;
  static double _contentHeight(GroupModel g) => 528 + _membersCardH(g) + 29 + 54 + 24;

  Widget _content(GroupModel g) {
    final cardH = _membersCardH(g);
    final exitTop = 528 + cardH + 29;
    final created = g.createdAt;
    return Stack(
      children: [
        Positioned(
          left: 21,
          top: 26,
          child: GlassCircleButton(
            size: 44,
            onTap: () => Navigator.of(context).pop(),
            child: SvgPicture.asset('assets/home_v2/close.svg',
                width: 13.5, height: 13.5),
          ),
        ),
        Positioned(
          left: 248,
          top: 26,
          width: 117,
          height: 38,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => _invite(g),
            child: Container(
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(43),
              ),
              child: Text('メンバーを招待', style: _rounded(11, Colors.black, 700)),
            ),
          ),
        ),
        Positioned(
          left: 134,
          top: 75,
          child: GestureDetector(
            onTap: () => _pickIcon(g),
            child: GroupIconImage(iconIndex: g.iconIndex, size: 115, radius: 25),
          ),
        ),
        Positioned(
          left: 20,
          right: 20,
          top: 211,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => _rename(g),
            child: Text(
              g.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: _rounded(22, Colors.white, 700),
            ),
          ),
        ),
        Positioned(
          left: 0,
          right: 0,
          top: 245,
          child: Text(
            '${g.memberIds.length}人のメンバー　${created.month}月${created.day}日から',
            textAlign: TextAlign.center,
            style: _rounded(13, _subGrey, 400),
          ),
        ),
        Positioned(
          left: 37,
          top: 282,
          child: Text('設定', style: _rounded(10, _labelGrey, 700)),
        ),
        Positioned(left: 17, top: 299, child: _settingsCard(g)),
        Positioned(
          left: 33,
          top: 511,
          child: Text(
            'メンバー　${g.memberIds.length} / ${GroupModel.maxMembers}人',
            style: _rounded(10, _labelGrey, 700),
          ),
        ),
        Positioned(left: 17, top: 528, child: _membersCard(g, cardH)),
        Positioned(
          left: 17,
          top: exitTop,
          width: 350,
          height: 54,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => _leave(g),
            child: Container(
              alignment: Alignment.centerLeft,
              padding: const EdgeInsets.only(left: 33),
              decoration: BoxDecoration(
                color: _cardBg,
                borderRadius: BorderRadius.circular(25),
              ),
              child: Text('グループを退出する', style: _rounded(14, Colors.white, 700)),
            ),
          ),
        ),
      ],
    );
  }

  /// 設定（通知・招待コード・参加の締め切り）。350×167。
  Widget _settingsCard(GroupModel g) {
    Widget tile(Color bg, Widget icon, double top) => Positioned(
          left: 19,
          top: top,
          child: Container(
            width: 31,
            height: 31,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(8),
            ),
            child: icon,
          ),
        );
    Widget label(String text, double top) => Positioned(
          left: 74,
          top: top,
          child: Text(text, style: _rounded(15, Colors.white, 400)),
        );
    Widget toggle(bool value, ValueChanged<bool> onChanged, double centerY) =>
        Positioned(
          right: 15,
          top: centerY - 15.5,
          child: CupertinoSwitch(
            value: value,
            activeTrackColor: const Color(0xFF34C759),
            onChanged: onChanged,
          ),
        );

    return Container(
      width: 350,
      height: 167,
      decoration: BoxDecoration(
        color: _cardBg,
        borderRadius: BorderRadius.circular(25),
      ),
      child: Stack(
        children: [
          const Positioned(left: 60, right: 0, top: 55, child: _Divider()),
          const Positioned(left: 60, right: 0, top: 112, child: _Divider()),
          tile(const Color(0xFF3A2A20),
              const Icon(Icons.notifications_none_rounded,
                  color: Color(0xFFF0A05A), size: 19),
              12),
          tile(const Color(0xFF1D2A3D),
              SvgPicture.asset('assets/home_v2/hash.svg', width: 11, height: 13),
              68),
          tile(const Color(0xFF3A321C),
              const Icon(Icons.lock_outline_rounded,
                  color: Color(0xFFE8C04F), size: 17),
              124),
          label('通知を受け取る', 19),
          label('招待コード', 74),
          label('参加を締め切る', 130),
          toggle(
            !g.isMutedFor(widget.uid),
            (on) => _guard(() =>
                _groupService.setNotificationsEnabled(g.groupId, widget.uid, on)),
            27.5,
          ),
          // 招待コード。コードのタップでコピー、QR のタップで QR を出す。
          Positioned(
            left: 200,
            right: 40,
            top: 64,
            height: 36,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => _copyCode(g),
              child: Align(
                alignment: Alignment.centerRight,
                child: Text(g.inviteCode ?? '',
                    style: const TextStyle(
                        color: _subGrey, fontSize: 14, height: 1.2)),
              ),
            ),
          ),
          Positioned(
            left: 314,
            top: 70,
            width: 32,
            height: 31,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => _showQr(g),
              child: const Center(child: QrGlyph(color: _subGrey)),
            ),
          ),
          toggle(
            g.joinClosed,
            (on) => _guard(
                () => _groupService.updateSettings(g.groupId, joinClosed: on)),
            139.5,
          ),
        ],
      ),
    );
  }

  /// メンバー一覧と「招待する」。行は 56 間隔。
  Widget _membersCard(GroupModel g, double height) {
    final rows = <Widget>[];
    for (var i = 0; i <= g.memberIds.length; i++) {
      final top = 56.0 * i;
      if (i > 0) {
        rows.add(Positioned(left: 0, right: 0, top: top - 1, child: const _Divider()));
      }
      if (i < g.memberIds.length) {
        final uid = g.memberIds[i];
        rows.add(Positioned(
          left: 19,
          top: top + 10,
          child: ClipOval(
            child: Container(
              width: 35,
              height: 35,
              color: const Color(0xFF3A3A3A),
              child: ProfileImage(imageUrl: _users[uid]?.profileImageUrl, size: 35),
            ),
          ),
        ));
        rows.add(Positioned(
          left: 76,
          right: 16,
          top: top + 19,
          child: Text(_nameOf(uid),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: _rounded(14, Colors.white, 400)),
        ));
      } else {
        rows.add(Positioned(
          left: 0,
          right: 0,
          top: top,
          height: 54,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => _invite(g),
            child: Stack(
              children: [
                Positioned(
                  left: 19,
                  top: 10,
                  child: IgnorePointer(
                    child: GlassCircleButton(
                      size: 35,
                      onTap: () {},
                      child: SvgPicture.asset('assets/home_v2/plus.svg',
                          width: 16, height: 16),
                    ),
                  ),
                ),
                Positioned(
                  left: 76,
                  top: 19,
                  child: Text('招待する', style: _rounded(14, Colors.white, 400)),
                ),
              ],
            ),
          ),
        ));
      }
    }
    return Container(
      width: 350,
      height: height,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: _cardBg,
        borderRadius: BorderRadius.circular(25),
      ),
      child: Stack(children: rows),
    );
  }
}

class _Divider extends StatelessWidget {
  const _Divider();

  @override
  Widget build(BuildContext context) =>
      const SizedBox(height: 1, child: ColoredBox(color: _divider));
}

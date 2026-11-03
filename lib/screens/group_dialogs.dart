import 'dart:ui' as ui;

import 'package:firebase_auth/firebase_auth.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../constants/profile_fonts.dart';
import '../models/group_model.dart';
import '../models/user_model.dart';
import '../services/group_service.dart';
import '../widgets/common/app_toast.dart';
import '../widgets/common/glass_circle_button.dart';
import 'group_screen.dart';
import 'group_settings_sheet.dart' show GroupIconImage;

// グループの作成・参加・招待のダイアログ。
//
//   ＋ のメニュー      Figma 6321:13187（右下のガラスの吹き出し）
//   新しいグループ     Figma 6373:14064（上に出るガラスのカード＋キーボード）
//   招待               Figma 6394:14203（中央のガラスのカードに QR）
//   コードで参加       デザインなし。新しいグループと同じ形で作っている
//   友達を追加         デザインなし。同じガラスの見た目で一覧から選ぶ
//
// 寸法は Figma の 402×874 のまま持ち、画面幅に合わせて拡縮する。

const double _designW = 402;
const Color _divider = Color(0xFF2C2A30);

TextStyle _rounded(double size, Color color, double wght) => TextStyle(
      fontFamily: kSfProRounded,
      fontSize: size,
      color: color,
      height: 1.2,
      decoration: TextDecoration.none,
      fontWeight: wght >= 700 ? FontWeight.bold : FontWeight.normal,
      fontVariations: [ui.FontVariation('wght', wght)],
    );

/// iOS の Liquid Glass（Regular / Medium / Dark）の代わり。背景をぼかして
/// 暗い半透明を重ね、縁に細い光を入れる（[GlassCircleButton] と同じ考え方）。
class GlassPanel extends StatelessWidget {
  final double width;
  final double height;
  final double radius;
  final Widget child;

  const GlassPanel({
    super.key,
    required this.width,
    required this.height,
    required this.radius,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 24, sigmaY: 24),
        child: Container(
          width: width,
          height: height,
          decoration: BoxDecoration(
            color: const Color(0xFF1E1D21).withValues(alpha: 0.82),
            borderRadius: BorderRadius.circular(radius),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.12),
              width: 0.8,
            ),
          ),
          child: child,
        ),
      ),
    );
  }
}

/// 招待コードの QR の記号（Figma 6321:12963）。16×15 の小さな枠 5 つ。
class QrGlyph extends StatelessWidget {
  final Color color;
  const QrGlyph({super.key, required this.color});

  @override
  Widget build(BuildContext context) {
    Widget box(double l, double t, double s) => Positioned(
          left: l,
          top: t,
          child: Container(
            width: s,
            height: s,
            decoration: BoxDecoration(
              border: Border.all(color: color, width: 1.5),
              borderRadius: BorderRadius.circular(1),
            ),
          ),
        );
    return SizedBox(
      width: 16,
      height: 15,
      child: Stack(
        children: [
          box(0, 0, 7),
          box(9, 0, 7),
          box(0, 8, 7),
          box(9, 8, 4),
          box(12, 11, 4),
        ],
      ),
    );
  }
}

/// Figma の座標系（402 幅）で組んだ [child] を、画面に重ねて拡縮する。
Widget _designOverlay(BuildContext context, Widget child) {
  final scale = MediaQuery.sizeOf(context).width / _designW;
  return Transform.scale(
    scale: scale,
    alignment: Alignment.topLeft,
    child: SizedBox(
      width: _designW,
      height: MediaQuery.sizeOf(context).height / scale,
      child: child,
    ),
  );
}

// ── ＋ のメニュー ─────────────────────────────────────────

/// ホーム右下の＋を押したときのガラスの吹き出し（Figma 6321:13187）。
class GroupAddMenu {
  static Future<void> show(BuildContext context) async {
    final choice = await showGeneralDialog<String>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'close',
      barrierColor: Colors.transparent,
      transitionDuration: const Duration(milliseconds: 160),
      pageBuilder: (ctx, _, __) {
        final bottomInset = MediaQuery.paddingOf(ctx).bottom;
        final scale = MediaQuery.sizeOf(ctx).width / _designW;
        return Stack(
          children: [
            Positioned(
              right: 17 * scale,
              // ＋ ボタンと同じ下端（Figma は下から 39、端末の安全領域を下回らない）。
              bottom: (39 * scale).clamp(bottomInset + 5, double.infinity),
              child: Transform.scale(
                scale: scale,
                alignment: Alignment.bottomRight,
                child: GlassPanel(
                  width: 249,
                  height: 94,
                  radius: 30,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _menuItem(ctx, 'グループを作成', 'create'),
                      _menuItem(ctx, 'コードで参加', 'join'),
                    ],
                  ),
                ),
              ),
            ),
          ],
        );
      },
      transitionBuilder: (ctx, anim, _, child) => FadeTransition(
        opacity: anim,
        child: ScaleTransition(
          scale: Tween(begin: 0.92, end: 1.0).animate(anim),
          alignment: Alignment.bottomRight,
          child: child,
        ),
      ),
    );
    if (!context.mounted) return;
    if (choice == 'create') await CreateGroupDialog.show(context);
    if (choice == 'join') await JoinGroupDialog.show(context);
  }

  static Widget _menuItem(BuildContext ctx, String label, String value) {
    return Expanded(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => Navigator.of(ctx).pop(value),
        child: Padding(
          padding: const EdgeInsets.only(left: 31),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(label, style: _rounded(14, Colors.white, 400)),
          ),
        ),
      ),
    );
  }
}

// ── 新しいグループ / コードで参加 ─────────────────────────────

/// 上に出るガラスのカード（378×294）。新しいグループとコードで参加で共用。
class _TopCardDialog extends StatefulWidget {
  final String title;
  final String placeholder;
  final String note;
  final String? initialText;
  final int? maxLength;

  /// 入力がこれを満たすとチェックが白くなり、押せるようになる。
  final bool Function(String text) canSubmit;

  /// チェックを押したとき。成功したら true を返すとダイアログを閉じる。
  final Future<bool> Function(BuildContext context, String text) onSubmit;

  /// 下の「招待コード・QRで参加する」のような導線。null なら出さない。
  /// 押すとダイアログを閉じてから [onFooter] の結果を呼び出し側が見る。
  final String? footerLabel;
  final VoidCallback? onFooter;

  const _TopCardDialog({
    required this.title,
    required this.placeholder,
    required this.note,
    required this.onSubmit,
    required this.canSubmit,
    this.initialText,
    this.maxLength,
    this.footerLabel,
    this.onFooter,
  });

  @override
  State<_TopCardDialog> createState() => _TopCardDialogState();
}

class _TopCardDialogState extends State<_TopCardDialog> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.initialText);
  bool _busy = false;
  late bool _ready = widget.canSubmit(_controller.text.trim());

  @override
  void initState() {
    super.initState();
    _controller.addListener(() {
      final ready = widget.canSubmit(_controller.text.trim());
      if (ready != _ready) setState(() => _ready = ready);
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy || !_ready) return;
    setState(() => _busy = true);
    final ok = await widget.onSubmit(context, _controller.text.trim());
    if (!mounted) return;
    setState(() => _busy = false);
    if (ok) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final hasFooter = widget.footerLabel != null;
    return _designOverlay(
      context,
      Stack(
        children: [
          Positioned(
            left: 12,
            top: 77,
            child: GlassPanel(
              width: 378,
              height: hasFooter ? 294 : 230,
              radius: 38,
              child: Material(
                type: MaterialType.transparency,
                child: Stack(
                  children: [
                    Positioned(
                      left: 17,
                      top: 25,
                      child: GlassCircleButton(
                        size: 44,
                        onTap: () => Navigator.of(context).pop(false),
                        child: SvgPicture.asset('assets/home_v2/close.svg',
                            width: 13.5, height: 13.5),
                      ),
                    ),
                    Positioned(
                      left: 72,
                      top: 35,
                      child: Text(widget.title,
                          style: _rounded(20, Colors.white, 700)),
                    ),
                    // 決定（Figma: Liquid Glass Light + Check）。入力するまでは
                    // 半透明で押せず、入力すると白くなる。
                    Positioned(
                      left: 317,
                      top: 25,
                      child: GestureDetector(
                        onTap: _submit,
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 150),
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: _ready
                                ? Colors.white
                                : Colors.white.withValues(alpha: 0.55),
                          ),
                          child: _busy
                              ? const CupertinoActivityIndicator(
                                  color: Colors.black)
                              : const Icon(Icons.check_rounded,
                                  color: Color(0xFF2A2A2E), size: 26),
                        ),
                      ),
                    ),
                    Positioned(
                      left: 17,
                      top: 102,
                      width: 344,
                      height: 58,
                      child: Container(
                        decoration: BoxDecoration(
                          color: const Color(0xFF26242A),
                          borderRadius: BorderRadius.circular(19),
                        ),
                        padding: const EdgeInsets.symmetric(horizontal: 24),
                        alignment: Alignment.centerLeft,
                        child: CupertinoTextField(
                          controller: _controller,
                          autofocus: true,
                          maxLength: widget.maxLength,
                          placeholder: widget.placeholder,
                          placeholderStyle:
                              _rounded(16, const Color(0xFF77707C), 400),
                          style: _rounded(16, Colors.white, 400),
                          cursorColor: Colors.white,
                          decoration: null,
                          padding: EdgeInsets.zero,
                          textInputAction: TextInputAction.done,
                          onSubmitted: (_) => _submit(),
                        ),
                      ),
                    ),
                    Positioned(
                      left: 23,
                      right: 17,
                      top: 173,
                      child: Text(widget.note,
                          style: _rounded(13, const Color(0xFF8F8894), 400)),
                    ),
                    if (hasFooter) ...[
                      const Positioned(
                        left: 21,
                        top: 227,
                        width: 336,
                        child: SizedBox(
                            height: 1, child: ColoredBox(color: _divider)),
                      ),
                      Positioned(
                        left: 0,
                        right: 0,
                        top: 228,
                        height: 60,
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: () {
                            widget.onFooter?.call();
                            Navigator.of(context).pop(false);
                          },
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const QrGlyph(color: Color(0xFFE9E3EE)),
                              const SizedBox(width: 10),
                              Text(widget.footerLabel!,
                                  style: _rounded(
                                      15, const Color(0xFFE9E3EE), 700)),
                            ],
                          ),
                        ),
                      ),
                    ],
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

Future<bool?> _showTopCard(BuildContext context, _TopCardDialog dialog) {
  return showGeneralDialog<bool>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'close',
    // Figma: 黒 70% で背景を沈める。
    barrierColor: Colors.black.withValues(alpha: 0.7),
    transitionDuration: const Duration(milliseconds: 200),
    pageBuilder: (_, __, ___) => dialog,
    transitionBuilder: (ctx, anim, _, child) => FadeTransition(
      opacity: anim,
      child: SlideTransition(
        position: Tween(begin: const Offset(0, -0.04), end: Offset.zero)
            .animate(CurvedAnimation(parent: anim, curve: Curves.easeOut)),
        child: child,
      ),
    ),
  );
}

/// 「グループを作成」（Figma 6373:14064）。作ったらそのまま招待のカードを出す。
class CreateGroupDialog {
  static Future<void> show(BuildContext context) async {
    GroupModel? created;
    var openJoin = false;
    await _showTopCard(
      context,
      _TopCardDialog(
        title: '新しいグループ',
        placeholder: 'グループ名',
        note: '最大${GroupModel.maxMembers}人まで。作成後に招待リンクやQRで友達を呼べます。',
        maxLength: 20,
        footerLabel: '招待コード・QRで参加する',
        onFooter: () => openJoin = true,
        canSubmit: (name) => name.isNotEmpty,
        onSubmit: (ctx, name) async {
          try {
            final res = await GroupService().createMyGroup(name);
            final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
            created = GroupModel(
              groupId: res.groupId,
              name: res.name,
              ownerId: uid,
              memberIds: [uid],
              createdAt: DateTime.now(),
              inviteCode: res.inviteCode,
            );
            return true;
          } catch (_) {
            if (ctx.mounted) AppToast.show(ctx, 'グループを作成できませんでした');
            return false;
          }
        },
      ),
    );
    if (!context.mounted) return;
    if (openJoin) {
      await JoinGroupDialog.show(context);
      return;
    }
    final g = created;
    if (g != null) await GroupInviteDialog.show(context, g);
  }
}

/// 「コードで参加」。デザインは無いので新しいグループと同じ形。
/// 招待リンク（QR）から開いたときは [initialCode] が入った状態で出す。
class JoinGroupDialog {
  static Future<void> show(BuildContext context, {String? initialCode}) async {
    ({String groupId, String name, bool alreadyMember})? joined;
    await _showTopCard(
      context,
      _TopCardDialog(
        title: 'コードで参加',
        placeholder: '招待コード（6桁）',
        note: '招待リンクのQRは、iPhoneのカメラで読み取ると参加できます。',
        initialText: initialCode,
        maxLength: 6,
        canSubmit: (code) => code.length == 6,
        onSubmit: (ctx, code) async {
          try {
            joined = await GroupService().joinByCode(code);
            return true;
          } on GroupJoinException catch (e) {
            if (ctx.mounted) AppToast.show(ctx, e.message);
            return false;
          } catch (_) {
            if (ctx.mounted) AppToast.show(ctx, '参加できませんでした');
            return false;
          }
        },
      ),
    );
    final j = joined;
    if (j == null || !context.mounted) return;
    AppToast.show(
        context,
        j.alreadyMember
            ? '「${j.name}」にはもう参加しています'
            : '「${j.name}」に参加しました');
    final group = await GroupService().watchGroup(j.groupId).first;
    if (group != null && context.mounted) await GroupScreen.push(context, group);
  }
}

// ── 招待 ────────────────────────────────────────────────

/// 招待のカード（Figma 6394:14203）。アイコン・名前・QR・共有・LINE。
///
/// QR と共有には招待リンク（[GroupService.inviteUrl]）を入れる。iPhone の
/// カメラで読むと Web を経てアプリが開き、参加の確認が出る。
class GroupInviteDialog {
  static Future<void> show(BuildContext context, GroupModel group) async {
    if (group.joinClosed) {
      AppToast.show(context, '参加を締め切っています');
      return;
    }
    if (group.memberIds.length >= GroupModel.maxMembers) {
      AppToast.show(context, 'グループは${GroupModel.maxMembers}人までです');
      return;
    }
    final code = group.inviteCode;
    if (code == null) {
      AppToast.show(context, '招待コードを準備しています。もう一度お試しください');
      return;
    }
    await showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'close',
      barrierColor: Colors.black.withValues(alpha: 0.7),
      transitionDuration: const Duration(milliseconds: 200),
      pageBuilder: (ctx, _, __) => _designOverlay(
        ctx,
        Stack(
          children: [
            Positioned(
              left: 38,
              top: 162,
              child: _InviteCard(group: group, code: code),
            ),
          ],
        ),
      ),
      transitionBuilder: (ctx, anim, _, child) => FadeTransition(
        opacity: anim,
        child: ScaleTransition(
          scale: Tween(begin: 0.96, end: 1.0).animate(anim),
          child: child,
        ),
      ),
    );
  }
}

class _InviteCard extends StatelessWidget {
  final GroupModel group;
  final String code;

  const _InviteCard({required this.group, required this.code});

  String get _url => GroupService.inviteUrl(code);
  String get _message =>
      '15sのグループ「${group.name}」に参加しよう\n招待コード: $code\n$_url';

  Future<void> _share() => Share.share(_message);

  Future<void> _shareLine(BuildContext context) async {
    final uri = Uri.parse(
        'https://line.me/R/msg/text/?${Uri.encodeComponent(_message)}');
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      if (context.mounted) AppToast.show(context, 'LINEを開けませんでした');
    }
  }

  @override
  Widget build(BuildContext context) {
    Widget row(double top, Widget leading, String label, VoidCallback onTap) =>
        Positioned(
          left: 30,
          width: 266,
          top: top,
          height: 58,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onTap,
            child: Stack(
              children: [
                Positioned(left: 36, top: 15, child: leading),
                Positioned(
                  left: 0,
                  right: 0,
                  top: 18,
                  child: Text(label,
                      textAlign: TextAlign.center,
                      style: _rounded(16, Colors.white, 700)),
                ),
                Positioned(
                  left: 241,
                  top: 21,
                  child: SvgPicture.asset('assets/home_v2/chevron_right.svg',
                      width: 9, height: 14.7),
                ),
              ],
            ),
          ),
        );

    return GlassPanel(
      width: 325,
      height: 548,
      radius: 50,
      child: Stack(
        children: [
          Positioned(
            left: 132,
            top: 44,
            child: Container(
              decoration: BoxDecoration(
                border: Border.all(color: const Color(0xFFDADADE)),
                borderRadius: BorderRadius.circular(14),
              ),
              child: GroupIconImage(iconIndex: group.iconIndex, size: 60, radius: 13),
            ),
          ),
          Positioned(
            left: 16,
            right: 16,
            top: 116,
            child: Text(group.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: _rounded(16, Colors.white, 400)),
          ),
          Positioned(
            left: 72,
            top: 144,
            child: Container(
              width: 182,
              height: 182,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(19),
              ),
              child: QrImageView(data: _url, padding: EdgeInsets.zero),
            ),
          ),
          Positioned(
            left: 86,
            top: 343,
            width: 154,
            height: 44,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _share,
              child: Container(
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(26),
                ),
                child: Text('招待を共有', style: _rounded(16, Colors.black, 510)),
              ),
            ),
          ),
          const Positioned(
            left: 30,
            top: 403,
            width: 266,
            child: SizedBox(height: 1, child: ColoredBox(color: _divider)),
          ),
          row(404, Image.asset('assets/home_v2/line_logo.png', width: 28, height: 28),
              'LINEでシェア', () => _shareLine(context)),
          const Positioned(
            left: 30,
            top: 462,
            width: 266,
            child: SizedBox(height: 1, child: ColoredBox(color: _divider)),
          ),
          row(
              463,
              const Icon(CupertinoIcons.person_add,
                  color: Colors.white, size: 26),
              '友達を追加',
              () => GroupFriendPicker.show(context, group)),
        ],
      ),
    );
  }
}


// ── 友達を追加 ───────────────────────────────────────────

/// 招待カードの「友達を追加」。デザインは無いので、同じガラスのカードに
/// 友達（どこかのグループで一緒の人）を並べ、選んで追加する。
///
/// 追加された人は確認なしでそのまま参加になる（サーバー addGroupMembers）。
class GroupFriendPicker {
  static Future<void> show(BuildContext context, GroupModel group) async {
    final added = await showGeneralDialog<int>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'close',
      barrierColor: Colors.black.withValues(alpha: 0.7),
      transitionDuration: const Duration(milliseconds: 200),
      pageBuilder: (ctx, _, __) => _designOverlay(
        ctx,
        Stack(
          children: [
            Positioned(left: 38, top: 162, child: _FriendPickerCard(group: group)),
          ],
        ),
      ),
      transitionBuilder: (ctx, anim, _, child) =>
          FadeTransition(opacity: anim, child: child),
    );
    if (added != null && added > 0 && context.mounted) {
      AppToast.show(context, '$added人をグループに追加しました');
    }
  }
}

class _FriendPickerCard extends StatefulWidget {
  final GroupModel group;
  const _FriendPickerCard({required this.group});

  @override
  State<_FriendPickerCard> createState() => _FriendPickerCardState();
}

class _FriendPickerCardState extends State<_FriendPickerCard> {
  final GroupService _service = GroupService();
  List<UserModel>? _friends;
  final Set<String> _selected = {};
  bool _busy = false;

  int get _room => GroupModel.maxMembers - widget.group.memberIds.length;

  @override
  void initState() {
    super.initState();
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    _service.fetchFriendsNotIn(widget.group, uid).then((list) {
      if (mounted) setState(() => _friends = list);
    }).catchError((_) {
      if (mounted) setState(() => _friends = const []);
    });
  }

  void _toggle(String uid) {
    setState(() {
      if (_selected.remove(uid)) return;
      if (_selected.length >= _room) {
        AppToast.show(context, 'グループは${GroupModel.maxMembers}人までです');
        return;
      }
      _selected.add(uid);
    });
  }

  Future<void> _add() async {
    if (_busy || _selected.isEmpty) return;
    setState(() => _busy = true);
    try {
      final n = await _service.addMembers(
          widget.group.groupId, _selected.toList());
      if (mounted) Navigator.of(context).pop(n);
    } on GroupJoinException catch (e) {
      if (mounted) AppToast.show(context, e.message);
    } catch (_) {
      if (mounted) AppToast.show(context, '追加できませんでした');
    }
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final friends = _friends;
    return GlassPanel(
      width: 325,
      height: 548,
      radius: 50,
      child: Material(
        type: MaterialType.transparency,
        child: Column(
          children: [
            const SizedBox(height: 32),
            Text('友達を追加', style: _rounded(18, Colors.white, 700)),
            const SizedBox(height: 6),
            Text('追加した友達はそのまま参加します（あと$_room人）',
                style: _rounded(12, const Color(0xFF8F8894), 400)),
            const SizedBox(height: 16),
            Expanded(
              child: friends == null
                  ? const Center(
                      child: CupertinoActivityIndicator(color: Colors.white))
                  : friends.isEmpty
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 32),
                            child: Text(
                              'ほかのグループで一緒の友達がいません。\n招待リンクやQRで呼んでください。',
                              textAlign: TextAlign.center,
                              style: _rounded(13, const Color(0xFF8F8894), 400),
                            ),
                          ),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.symmetric(horizontal: 24),
                          itemCount: friends.length,
                          itemBuilder: (_, i) => _row(friends[i]),
                        ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(86, 12, 86, 32),
              child: GestureDetector(
                onTap: _add,
                child: Container(
                  height: 44,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: _selected.isEmpty
                        ? Colors.white.withValues(alpha: 0.55)
                        : Colors.white,
                    borderRadius: BorderRadius.circular(26),
                  ),
                  child: _busy
                      ? const CupertinoActivityIndicator(color: Colors.black)
                      : Text(
                          _selected.isEmpty ? '追加する' : '${_selected.length}人を追加',
                          style: _rounded(16, Colors.black, 510)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _row(UserModel u) {
    final on = _selected.contains(u.uid);
    final url = u.profileImageUrl ?? '';
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => _toggle(u.uid),
      child: SizedBox(
        height: 56,
        child: Row(
          children: [
            ClipOval(
              child: SizedBox(
                width: 40,
                height: 40,
                child: url.isEmpty
                    ? const ColoredBox(color: Color(0xFF3A363E))
                    : CachedNetworkImage(
                        imageUrl: url,
                        fit: BoxFit.cover,
                        errorWidget: (_, __, ___) =>
                            const ColoredBox(color: Color(0xFF3A363E)),
                      ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                (u.name?.isNotEmpty == true ? u.name : u.username) ?? '',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: _rounded(15, Colors.white, 510),
              ),
            ),
            Icon(
              on
                  ? CupertinoIcons.check_mark_circled_solid
                  : CupertinoIcons.circle,
              color: on ? Colors.white : const Color(0xFF5C5762),
              size: 24,
            ),
          ],
        ),
      ),
    );
  }
}

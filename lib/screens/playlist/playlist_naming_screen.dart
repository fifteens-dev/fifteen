import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../models/post_model.dart';
import '../../services/playlist_service.dart';
import '../../utils/album_image.dart';
import '../../constants/profile_fonts.dart';
import '../../widgets/common/app_toast.dart';

/// プレイリスト作成フロー 画面2: 名前を決める（Figma 5104:10340）。
/// カバープレビュー ＋「カバーを編集」＋ 名前入力。右上✓で作成完了。
class PlaylistNamingScreen extends StatefulWidget {
  final List<PostModel> posts;
  const PlaylistNamingScreen({super.key, required this.posts});

  @override
  State<PlaylistNamingScreen> createState() => _PlaylistNamingScreenState();
}

class _PlaylistNamingScreenState extends State<PlaylistNamingScreen> {
  final TextEditingController _controller = TextEditingController();
  final PlaylistService _playlistService = PlaylistService();
  int _coverIndex = 0; // カバーに使う投稿のインデックス
  bool _saving = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  static String _imageOf(PostModel p) =>
      (p.photoUrl?.isNotEmpty ?? false) ? p.photoUrl! : p.track.albumImageUrl;

  String get _coverUrl {
    if (widget.posts.isEmpty) return '';
    return _imageOf(widget.posts[_coverIndex.clamp(0, widget.posts.length - 1)]);
  }

  /// 「カバーを編集」= 選択した投稿の画像を順に切り替える。
  void _editCover() {
    if (widget.posts.length <= 1) return;
    setState(() => _coverIndex = (_coverIndex + 1) % widget.posts.length);
  }

  Future<void> _create() async {
    if (_saving) return;
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    final name =
        _controller.text.trim().isEmpty ? 'プレイリスト' : _controller.text.trim();
    setState(() => _saving = true);
    try {
      await _playlistService.createPlaylist(
        userId: uid,
        name: name,
        postIds: widget.posts.map((p) => p.postId).toList(),
        coverImageUrl: _coverUrl,
      );
      if (!mounted) return;
      Navigator.pop(context, true); // 作成完了を画面1へ返す
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        AppToast.show(context, 'プレイリストの作成に失敗しました');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final topPad = MediaQuery.of(context).padding.top;
    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      resizeToAvoidBottomInset: true,
      body: Column(
        children: [
          SizedBox(height: topPad + 10),
          _buildHeader(),
          const SizedBox(height: 40),
          _buildCover(),
          const SizedBox(height: 14),
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _editCover,
            child: const Text(
              'カバーを編集',
              style: TextStyle(
                color: Color(0xFF3752FF),
                fontSize: 12,
                fontWeight: FontWeight.w700,
                fontFamily: kSfProRounded,
              ),
            ),
          ),
          const SizedBox(height: 14),
          _buildNameField(),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return SizedBox(
      height: 44,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Row(
          children: [
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => Navigator.pop(context),
              child: const SizedBox(
                width: 44,
                height: 44,
                child: Icon(Icons.arrow_back_ios_new,
                    color: Colors.white, size: 20),
              ),
            ),
            const Expanded(
              child: Center(
                child: Text(
                  '新しいプレイリスト',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    fontFamily: kSfProRounded,
                  ),
                ),
              ),
            ),
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _create,
              child: Container(
                width: 44,
                height: 44,
                alignment: Alignment.center,
                decoration: const BoxDecoration(
                  color: Color(0xFF262625),
                  shape: BoxShape.circle,
                ),
                child: _saving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                            color: Colors.white, strokeWidth: 2),
                      )
                    : const Icon(Icons.check, color: Colors.white, size: 22),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// カバー: 106×151 のカード＋右奥にページの重なり（斜め）。
  Widget _buildCover() {
    final url = _coverUrl;
    return SizedBox(
      width: 160,
      height: 178,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // 奥のページ（斜め）
          Positioned(
            right: 30,
            top: 20,
            child: Transform.rotate(
              angle: 0.14,
              child: Container(
                width: 40,
                height: 125,
                decoration: BoxDecoration(
                  color: const Color(0xFF424242),
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
          ),
          // カバー本体
          Container(
            width: 106,
            height: 151,
            decoration: BoxDecoration(
              color: const Color(0xFF424242),
              border: Border.all(color: const Color(0xFF424242), width: 7),
              borderRadius: BorderRadius.circular(10),
            ),
            clipBehavior: Clip.antiAlias,
            child: url.isNotEmpty
                ? Image(
                    image: albumImageProvider(url),
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) =>
                        Container(color: const Color(0xFF2A2A2A)),
                  )
                : Container(color: const Color(0xFF2A2A2A)),
          ),
        ],
      ),
    );
  }

  Widget _buildNameField() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 40),
      child: TextField(
        controller: _controller,
        textAlign: TextAlign.center,
        cursorColor: const Color(0xFF3752FF),
        style: const TextStyle(
          color: Colors.white,
          fontSize: 15,
          fontWeight: FontWeight.w600,
          fontFamily: kSfProRounded,
        ),
        // タップ範囲を広げるため isCollapsed を外し、上下に余白を持たせる。
        decoration: const InputDecoration(
          border: InputBorder.none,
          contentPadding: EdgeInsets.symmetric(vertical: 18),
          hintText: 'プレイリスト',
          hintStyle: TextStyle(
            color: Color(0xFF6A6A6A),
            fontSize: 15,
            fontWeight: FontWeight.w600,
            fontFamily: kSfProRounded,
          ),
        ),
        onSubmitted: (_) => _create(),
      ),
    );
  }
}

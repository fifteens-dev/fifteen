import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../models/post_model.dart';
import '../../services/post_service.dart';
import '../../utils/album_image.dart';
import '../../constants/profile_fonts.dart';
import 'playlist_naming_screen.dart';

/// プレイリスト作成フロー 画面1: 自分の投稿から曲を選ぶ（Figma 5082:10353）。
/// 3列グリッドで投稿を表示し、右上のチェックで選択。ヘッダーに件数＋「次へ」。
class PlaylistTrackSelectionScreen extends StatefulWidget {
  const PlaylistTrackSelectionScreen({super.key});

  @override
  State<PlaylistTrackSelectionScreen> createState() =>
      _PlaylistTrackSelectionScreenState();
}

class _PlaylistTrackSelectionScreenState
    extends State<PlaylistTrackSelectionScreen> {
  final PostService _postService = PostService();
  List<PostModel> _posts = [];
  final Set<String> _selected = {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      setState(() => _loading = false);
      return;
    }
    final posts = await _postService.getPostsByUserId(uid, limit: 100);
    if (!mounted) return;
    setState(() {
      _posts = posts;
      _loading = false;
    });
  }

  void _toggle(String id) {
    setState(() {
      if (!_selected.remove(id)) _selected.add(id);
    });
  }

  Future<void> _next() async {
    if (_selected.isEmpty) return;
    final selectedPosts =
        _posts.where((p) => _selected.contains(p.postId)).toList();
    final result = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => PlaylistNamingScreen(posts: selectedPosts),
      ),
    );
    // 作成完了(true)ならこの画面も閉じてプロフィールへ戻す。
    if (result == true && mounted) Navigator.pop(context, true);
  }

  static String _imageOf(PostModel p) =>
      (p.photoUrl?.isNotEmpty ?? false) ? p.photoUrl! : p.track.albumImageUrl;

  @override
  Widget build(BuildContext context) {
    final topPad = MediaQuery.of(context).padding.top;
    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      body: Column(
        children: [
          SizedBox(height: topPad + 10),
          _buildHeader(),
          Expanded(
            child: _loading
                ? const Center(
                    child: CircularProgressIndicator(color: Colors.white))
                : _posts.isEmpty
                    ? const Center(
                        child: Text('投稿がありません',
                            style: TextStyle(color: Colors.white54)))
                    : GridView.builder(
                        padding: const EdgeInsets.fromLTRB(12, 8, 12, 32),
                        gridDelegate:
                            const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 3,
                          mainAxisSpacing: 4,
                          crossAxisSpacing: 4,
                          childAspectRatio: 133 / 236,
                        ),
                        itemCount: _posts.length,
                        itemBuilder: (_, i) => _buildTile(_posts[i]),
                      ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    final n = _selected.length;
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
            Expanded(
              child: Center(
                child: Text(
                  n == 0 ? '曲を選択' : '$n件選択済み',
                  style: const TextStyle(
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
              onTap: _next,
              child: Container(
                width: 62,
                height: 44,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: const Color(0xFF262625),
                  borderRadius: BorderRadius.circular(21),
                ),
                child: Text(
                  '次へ',
                  style: TextStyle(
                    color: n == 0 ? Colors.white38 : Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    fontFamily: kSfProRounded,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTile(PostModel post) {
    final selected = _selected.contains(post.postId);
    final img = _imageOf(post);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => _toggle(post.postId),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Stack(
          fit: StackFit.expand,
          children: [
            img.isNotEmpty
                ? Image(
                    image: albumImageProvider(img),
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) =>
                        Container(color: const Color(0xFF2A2A2A)),
                  )
                : Container(color: const Color(0xFF2A2A2A)),
            // 選択時は薄い暗幕を重ねる
            if (selected)
              Container(color: Colors.black.withValues(alpha: 0.25)),
            Positioned(left: 8, top: 8, child: _buildDateBadge(post.createdAt)),
            Positioned(right: 8, top: 8, child: _buildCheckCircle(selected)),
          ],
        ),
      ),
    );
  }

  Widget _buildDateBadge(DateTime d) {
    return Container(
      width: 34,
      height: 34,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(5),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('${d.day}',
              style: const TextStyle(
                  color: Colors.black,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  height: 1.05,
                  fontFamily: kSfProRounded)),
          Text('${d.month}月',
              style: const TextStyle(
                  color: Colors.black,
                  fontSize: 9,
                  height: 1.05,
                  fontFamily: kSfProRounded)),
        ],
      ),
    );
  }

  Widget _buildCheckCircle(bool selected) {
    return Container(
      width: 22,
      height: 22,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: selected ? const Color(0xFF3752FF) : Colors.black.withValues(alpha: 0.25),
        border: Border.all(color: Colors.white, width: 1.5),
      ),
      child: selected
          ? const Icon(Icons.check, color: Colors.white, size: 14)
          : null,
    );
  }
}

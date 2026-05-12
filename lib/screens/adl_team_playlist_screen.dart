import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../constants/app_colors.dart';
import '../models/adl_team_model.dart';
import '../models/post_model.dart';
import '../services/audio_player_service.dart';
import '../widgets/post_card.dart';
import 'post_detail_screen.dart';

/// ADL班プレイリスト画面
/// 指定した班にタグ付けされた投稿を一覧表示する（Instagram ハイライト風）
class AdlTeamPlaylistScreen extends StatefulWidget {
  final AdlTeamModel team;
  final String currentUserId;

  const AdlTeamPlaylistScreen({
    super.key,
    required this.team,
    required this.currentUserId,
  });

  @override
  State<AdlTeamPlaylistScreen> createState() => _AdlTeamPlaylistScreenState();
}

class _AdlTeamPlaylistScreenState extends State<AdlTeamPlaylistScreen> {
  final _db = FirebaseFirestore.instance;
  List<PostModel>? _posts;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadPosts();
  }

  Future<void> _loadPosts() async {
    try {
      final snap = await _db
          .collection('posts')
          .where('adlTeamId', isEqualTo: widget.team.teamId)
          .orderBy('createdAt', descending: true)
          .get();
      if (mounted) {
        setState(() {
          _posts = snap.docs.map(PostModel.fromFirestore).toList();
          _isLoading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        foregroundColor: Colors.white,
        elevation: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.team.name,
              style: const TextStyle(
                  fontSize: 16, fontWeight: FontWeight.w700),
            ),
            Text(
              '${widget.team.likeCount} いいね  ·  ${widget.team.memberCount}人',
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        ),
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: Colors.white))
          : _posts == null || _posts!.isEmpty
              ? const Center(
                  child: Text('投稿がありません',
                      style: TextStyle(color: Colors.grey)))
              : GridView.builder(
                  padding: const EdgeInsets.all(1),
                  gridDelegate:
                      const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 3,
                    mainAxisSpacing: 1,
                    crossAxisSpacing: 1,
                    childAspectRatio: 9 / 16,
                  ),
                  itemCount: _posts!.length,
                  itemBuilder: (_, i) =>
                      _PostThumb(post: _posts![i], onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => PostDetailScreen(
                          post: _posts![i],
                          currentUserId: widget.currentUserId,
                        ),
                      ),
                    );
                  }),
                ),
    );
  }
}

class _PostThumb extends StatelessWidget {
  final PostModel post;
  final VoidCallback onTap;

  const _PostThumb({required this.post, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        color: AppColors.surfaceLight,
        child: post.photoUrl != null
            ? Image.network(post.photoUrl!, fit: BoxFit.cover)
            : Center(
                child: Text(
                  post.track.trackName,
                  style: const TextStyle(
                      color: Colors.white, fontSize: 10),
                  textAlign: TextAlign.center,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
      ),
    );
  }
}

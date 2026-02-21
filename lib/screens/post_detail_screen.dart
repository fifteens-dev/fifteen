import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/post_model.dart';
import '../widgets/post_card.dart';
import '../services/audio_player_service.dart';
import '../services/user_service.dart';
import '../utils/current_user_helper.dart';

/// 投稿カード単体表示画面
class PostDetailScreen extends StatefulWidget {
  final PostModel post;
  final bool autoFlipAfterDelay; // trueの場合、0.5秒後に自動で裏返す
  final bool disableInteractions; // いいね/コメント無効化

  const PostDetailScreen({
    super.key,
    required this.post,
    this.autoFlipAfterDelay = false, // デフォルトは自動反転なし
    this.disableInteractions = false,
  });

  @override
  State<PostDetailScreen> createState() => _PostDetailScreenState();
}

class _PostDetailScreenState extends State<PostDetailScreen> {
  final AudioPlayerService _audioService = AudioPlayerService();
  final UserService _userService = UserService();
  String? _currentUserIconUrl;
  bool _isSaved = false;

  @override
  void initState() {
    super.initState();
    _loadCurrentUserIconUrl();
    _checkSaveState();
  }

  Future<void> _checkSaveState() async {
    final userId = FirebaseAuth.instance.currentUser?.uid;
    if (userId != null) {
      setState(() {
        _isSaved = widget.post.savedByUserIds.contains(userId);
      });
    }
  }

  Future<void> _handleSave() async {
    final userId = FirebaseAuth.instance.currentUser?.uid;
    if (userId == null) return;

    setState(() {
      _isSaved = !_isSaved;
    });

    try {
      await _userService.toggleSavePost(userId: userId, postId: widget.post.postId);
    } catch (e) {
      if (mounted) {
        setState(() {
          _isSaved = !_isSaved;
        });
      }
    }
  }

  Future<void> _loadCurrentUserIconUrl() async {
    final userInfo = await CurrentUserHelper.load();
    if (mounted) {
      setState(() {
        _currentUserIconUrl = userInfo.iconUrl;
      });
    }
  }

  @override
  void dispose() {
    // 画面を閉じる時に音楽を停止
    _audioService.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      body: SafeArea(
        child: Stack(
          children: [
            // 投稿カード（中央配置）
            Center(
              child: PostCard(
                post: widget.post,
                currentUserIconUrl: _currentUserIconUrl,
                audioService: _audioService,
                autoFlipAfterDelay: widget.autoFlipAfterDelay,
                disableInteractions: widget.disableInteractions,
                isSaved: _isSaved,
                onAdd: _handleSave,
              ),
            ),
            // 閉じるボタン（左上）
            Positioned(
              top: 16,
              left: 16,
              child: GestureDetector(
                onTap: () {
                  // 音楽を停止してから画面を閉じる
                  _audioService.stop();
                  Navigator.pop(context);
                },
                child: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.5),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.close,
                    color: Colors.white,
                    size: 24,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

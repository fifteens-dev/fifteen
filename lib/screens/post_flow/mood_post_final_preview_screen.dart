import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../models/post_model.dart';
import '../../models/post_theme.dart';
import '../../models/track_model.dart';
import '../../models/user_model.dart';
import '../../services/audio_player_service.dart';
import '../../services/live_activity_service.dart';
import '../../services/post_service.dart';
import '../../services/storage_service.dart';
import '../../services/user_service.dart';
import '../../utils/color_extractor.dart';
import '../../utils/photo_helper.dart';
import '../../widgets/common/app_toast.dart';
import '../../widgets/post_card.dart';
import '../../widgets/post_card_back_info.dart';
import '../../widgets/shared/user_info_badge.dart';

/// 気分投稿 (Music Memory から始まる投稿フロー) 用の最終プレビュー画面。
///
/// - 中央に投稿カードが宙に浮いて 2 秒ごとに表裏反転
/// - 画面下部に「投稿する」ボタン
/// - タップすると:
///     1. ボタン非表示 → 画面上部に「楽曲を追加しています...」テキスト
///     2. 裏でアップロード (Storage + Firestore) 実行
///     3. 完了 (or 失敗) 後、ホーム画面へ遷移
///
/// 歌詞カードは表示せず、写真は BoxFit.cover でカード裏面いっぱいに敷く。
/// isVibe: false, vibeTopicId/Title: null で気分投稿として保存する。
class MoodPostFinalPreviewScreen extends StatefulWidget {
  final TrackModel track;
  final XFile selectedImage;

  const MoodPostFinalPreviewScreen({
    super.key,
    required this.track,
    required this.selectedImage,
  });

  @override
  State<MoodPostFinalPreviewScreen> createState() =>
      _MoodPostFinalPreviewScreenState();
}

class _MoodPostFinalPreviewScreenState extends State<MoodPostFinalPreviewScreen>
    with SingleTickerProviderStateMixin {
  // ── 反転アニメーション ──
  late final AnimationController _flipCtrl;
  late final Animation<double> _flip;
  Timer? _flipTimer;
  // false = 裏面 (プレビュー画面と同じく裏面から開始)
  bool _showFront = false;

  // ── サービス ──
  final AudioPlayerService _audioService = AudioPlayerService();
  final PostService _postService = PostService();
  final StorageService _storageService = StorageService();
  final UserService _userService = UserService();

  // ── ユーザー / 色 ──
  UserModel? _me;
  Color? _gradientStart;
  Color? _gradientEnd;

  // ── 投稿状態 ──
  bool _isPosting = false;

  @override
  void initState() {
    super.initState();
    _flipCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
      value: 1.0, // 裏面から
    );
    _flip = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _flipCtrl, curve: Curves.easeInOut),
    );
    _flipTimer = Timer.periodic(const Duration(seconds: 2), (_) => _doFlip());
    _loadMe();
    _extractColors();
    WidgetsBinding.instance.addPostFrameCallback((_) => _playPreview());
  }

  @override
  void dispose() {
    _flipTimer?.cancel();
    _flipCtrl.dispose();
    _audioService.stopIfOwner(this);
    super.dispose();
  }

  Future<void> _loadMe() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    try {
      final me = await _userService.getUser(uid);
      if (mounted) setState(() => _me = me);
    } catch (_) {}
  }

  Future<void> _extractColors() async {
    if (widget.track.albumImageUrl.isEmpty) return;
    try {
      final (start, end) =
          await ColorExtractor.extractGradientColors(widget.track.albumImageUrl);
      if (mounted) {
        setState(() {
          _gradientStart = start;
          _gradientEnd = end;
        });
      }
    } catch (_) {}
  }

  Future<void> _playPreview() async {
    final url = widget.track.previewUrl;
    if (url == null || url.isEmpty) return;
    try {
      await _audioService.playPreview(url, durationSeconds: 15);
    } catch (_) {}
  }

  void _doFlip() {
    if (!mounted) return;
    setState(() => _showFront = !_showFront);
    if (_showFront) {
      _flipCtrl.reverse();
    } else {
      _flipCtrl.forward();
      _playPreview();
    }
  }

  /// 「投稿する」ボタン押下 → 気分投稿として保存。
  /// 画面はそのまま留まり、上部に「楽曲を追加しています...」を表示、
  /// 完了後にホームへ pushNamedAndRemoveUntil する。
  Future<void> _submit() async {
    if (_isPosting) return;
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      AppToast.show(context, 'ログインが必要です');
      return;
    }
    setState(() => _isPosting = true);

    try {
      // 表示に必要な値をキャプチャ
      final me = _me;
      final username =
          me?.username ?? user.displayName ?? 'ユーザー';
      final userIconUrl = me?.profileImageUrl;
      final adlTeamId = me?.adlTeamId;
      final university = me?.university;

      // 写真圧縮 → アップロード (VibeStoryPreviewScreen と同じ軽量パス)
      final imgBytes = await widget.selectedImage.readAsBytes();
      final (processedBytes, width, height) =
          await PhotoHelper.compressForUpload(imgBytes);
      final uploadResult = await PhotoHelper.uploadCompressedSplit(
        imageBytes: processedBytes,
        userId: user.uid,
        storageService: _storageService,
      );

      // URL 取得 + Firestore 書き込みを並列
      final urlFuture = uploadResult.storageRef!
          .getDownloadURL()
          .then<String?>((u) => u)
          .catchError((_) => null);

      final postIdFuture = _postService.createPost(
        userId: user.uid,
        username: username,
        userIconUrl: userIconUrl,
        trackData: widget.track.toMap(),
        photoUrl: null, // 後追い update
        imageOffsetX: 0.0,
        imageOffsetY: 0.0,
        imageScale: 1.0,
        imageNaturalWidth: width.toDouble(),
        imageNaturalHeight: height.toDouble(),
        // 歌詞カードは非表示 → PostCard 側は selectedLayoutIndex=1 の
        //   largeAlbumArt レイアウトを使うと詞なしでもアルバム丸配置になり
        //   気分投稿らしい表現になる。
        selectedLayoutIndex: 1,
        cardPositionX: 0,
        cardPositionY: 0,
        cardScale: 0, // 0 にしてカード自体を実質非表示に
        cardRotation: 0,
        isVibe: false,
        // 気分投稿マーカー。ストーリーバー等の集約先ではこのフラグを見て
        // 明示的にスキップする。
        isMoodPost: true,
        adlTeamId: adlTeamId,
        audience: 'public',
        audioStartMs: 0,
        audioDurationSec: 15,
        university: university,
      );

      final results = await Future.wait<dynamic>([urlFuture, postIdFuture]);
      final photoUrl = results[0] as String?;
      final postId = results[1] as String;

      if (photoUrl != null) {
        // ignore: unawaited_futures
        _postService.updatePostPhotoUrl(postId: postId, photoUrl: photoUrl);
      }

      // ロック画面の Live Activity を「投稿が完了しました🎉」へ切り替え、
      // 今日の枠に今の投稿のジャケットを入れる。
      // ignore: unawaited_futures
      LiveActivityService().markPosted();

      if (!mounted) return;
      AppToast.show(context, '投稿しました');
      // このプレビュー画面はホームの上に opaque: false で載っているため、
      // pop すればそのままホームが表に出る。
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      AppToast.show(context, '投稿に失敗しました');
      setState(() => _isPosting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final topPadding = MediaQuery.of(context).padding.top;
    return PopScope(
      canPop: !_isPosting, // 投稿中は戻る不可
      child: Scaffold(
        // Route を opaque: false で push している前提。
        // Scaffold 自体は透明にして下のホーム画面を透けさせ、上に半透明黒の
        // ディムを敷いてカードを浮かび上がらせる (PostingCardOverlay と同じ体裁)。
        backgroundColor: Colors.transparent,
        body: Stack(
          children: [
            // 70% 黒ディム
            const Positioned.fill(
              child: ColoredBox(color: Color(0xB3000000)),
            ),
            // 中央: 反転カード
            Center(
              child: SizedBox(
                width: 324,
                height: 576,
                child: FittedBox(
                  fit: BoxFit.fill,
                  child: SizedBox(
                    width: 363,
                    height: 645,
                    child: AnimatedBuilder(
                      animation: _flip,
                      builder: (context, _) {
                        final angle = _flip.value * pi;
                        final isFront = angle < pi / 2;
                        return Transform(
                          alignment: Alignment.center,
                          transform: Matrix4.identity()
                            ..setEntry(3, 2, 0.001)
                            ..rotateY(angle),
                          child: isFront ? _buildFront() : _buildBack(),
                        );
                      },
                    ),
                  ),
                ),
              ),
            ),

            // 上部: 戻るボタン (投稿前のみ)
            if (!_isPosting)
              Positioned(
                left: 16,
                top: topPadding + 8,
                child: GestureDetector(
                  onTap: () => Navigator.pop(context),
                  child: Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.5),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.chevron_left,
                      color: Colors.white,
                      size: 26,
                    ),
                  ),
                ),
              ),

            // 上部: 投稿中テキスト (投稿中のみ、PostingCardOverlay と同じ位置・体裁)
            if (_isPosting)
              Positioned(
                top: topPadding + 48,
                left: 0,
                right: 0,
                child: const Text(
                  '楽曲を追加しています...',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Color(0xFFFFFFFF),
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    decoration: TextDecoration.none,
                  ),
                ),
              ),

            // 下部: 「投稿する」ボタン (投稿前のみ)
            if (!_isPosting)
              Positioned(
                left: 0,
                right: 0,
                bottom: 40,
                child: Center(
                  child: GestureDetector(
                    onTap: _submit,
                    behavior: HitTestBehavior.opaque,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 48,
                        vertical: 14,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(28),
                      ),
                      child: const Text(
                        '投稿する',
                        style: TextStyle(
                          color: Colors.black,
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildFront() {
    final now = DateTime.now();
    final post = PostModel(
      postId: '__mood_preview__',
      userId: _me?.uid ?? '__preview__',
      username: (_me?.username?.isNotEmpty ?? false)
          ? _me!.username!
          : 'ユーザー',
      userIconUrl: _me?.profileImageUrl,
      track: widget.track,
      likeCount: 3,
      commentCount: 3,
      createdAt: now,
      updatedAt: now,
    );
    return PostCard(
      post: post,
      audioService: _audioService,
      showFrontOnly: true,
      hideReactionCounts: true,
      hideAudienceBadge: true,
      preExtractedGradientStart: _gradientStart,
      preExtractedGradientEnd: _gradientEnd,
    );
  }

  Widget _buildBack() {
    // 反転後の裏面: 左右反転を戻すため rotateY(pi) をかける
    PostTheme theme = PostTheme.defaultTheme;
    if (_gradientStart != null && _gradientEnd != null) {
      theme = ColorExtractor.createThemeFromColors(
        _gradientStart!,
        _gradientEnd!,
      );
    }
    return Transform(
      alignment: Alignment.center,
      transform: Matrix4.identity()..rotateY(pi),
      child: Container(
        width: 363,
        height: 645,
        decoration: BoxDecoration(
          color: const Color(0xFF121212),
          borderRadius: BorderRadius.circular(18),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(18),
          child: Stack(
            children: [
              // 写真 (横幅フィット + 縦中央、上下の余白は真っ黒 #000000)
              Positioned.fill(
                child: ColoredBox(
                  color: const Color(0xFF000000),
                  child: kIsWeb
                      ? Image.network(
                          widget.selectedImage.path,
                          fit: BoxFit.fitWidth,
                        )
                      : Image.file(
                          File(widget.selectedImage.path),
                          fit: BoxFit.fitWidth,
                        ),
                ),
              ),
              // 楽曲情報 (下部)
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: PostCardBackInfo(
                  track: widget.track,
                  theme: theme,
                  likeCount: 3,
                  commentCount: 3,
                  isLiked: false,
                  showCounts: false,
                  onLike: () {},
                  onComment: () {},
                  onAdd: () {},
                ),
              ),
              // ユーザー情報 (左上)
              if (_me != null)
                Positioned(
                  left: 23,
                  top: 18,
                  child: UserInfoBadge(
                    username: (_me!.username?.isNotEmpty ?? false)
                        ? _me!.username!
                        : 'ユーザー',
                    iconUrl: _me!.profileImageUrl,
                    showBackground: false,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../models/post_model.dart';
import '../../models/profile_snapshot.dart';
import '../../models/track_model.dart';
import '../../models/user_model.dart';
import '../../services/audio_player_service.dart';
import '../../services/friend_widget_service.dart';

import '../../services/post_photo_service.dart';
import 'add_photo_flow.dart';
import 'post_complete_sheet.dart';
import '../../services/live_activity_service.dart';
import '../../services/post_service.dart';
import '../../services/storage_service.dart';
import '../../services/user_service.dart';
import '../../services/profile_snapshot_service.dart';
import '../../services/post_submission.dart';
import '../../utils/color_extractor.dart';
import '../../utils/photo_helper.dart';
import '../../widgets/common/app_toast.dart';
import '../../widgets/post_card.dart';

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

  /// 投稿に添える**公開**画像。旧フロー（写真を選んでから確認へ来る）で
  /// 使っていたもので、通常は null。
  final XFile? selectedImage;

  const MoodPostFinalPreviewScreen({
    super.key,
    required this.track,
    this.selectedImage,
  });

  /// ホーム画面の上にシートとして重ねて開く。
  ///
  /// この画面は **ホームが下に透けている前提**で作られている
  /// （Scaffold は透明、上に 70% の黒ディムを敷いてカードを浮かせる。
  ///  投稿完了時も pop するだけでホームに戻る）。
  /// 不透明なルートで push すると下が描画されず背景が真っ黒になるので、
  /// 遷移の作法をここに閉じ込めて呼び出し側が間違えられないようにしている。
  ///
  /// 曲選択のモーダル等はスタックから外し、ホームの直上に置く。
  static void open(BuildContext context, TrackModel track, {XFile? photo}) {
    final nav = Navigator.of(context);
    nav.pushNamedAndRemoveUntil('/home', (route) => false);
    nav.push(
      PageRouteBuilder<void>(
        opaque: false,
        barrierDismissible: false,
        transitionDuration: const Duration(milliseconds: 400),
        pageBuilder: (_, __, ___) =>
            MoodPostFinalPreviewScreen(track: track, selectedImage: photo),
        transitionsBuilder: (_, animation, __, child) => FadeTransition(
          opacity: CurvedAnimation(parent: animation, curve: Curves.easeOut),
          child: child,
        ),
      ),
    );
  }

  @override
  State<MoodPostFinalPreviewScreen> createState() =>
      _MoodPostFinalPreviewScreenState();
}

class _MoodPostFinalPreviewScreenState extends State<MoodPostFinalPreviewScreen>
    with SingleTickerProviderStateMixin {
  // ── 反転アニメーション ──
  // false = 裏面 (プレビュー画面と同じく裏面から開始)

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

  /// 投稿前に選んでおいた写真。投稿が終わってから紐づける
  /// （この時点では postId がまだ無い）。
  XFile? _pendingPhoto;

  /// 今が写真を足せる時間帯か（24:00 まで）。
  bool _canAddPhoto = false;

  /// カード裏面に焼き込む top artists / recent choice。
  ///
  /// 集計は Spotify や再生履歴を叩くので時間がかかる。投稿してから追いかけて
  /// 書くと、書き込み直後に読み直すホームでは裏面が空のまま出てしまう。
  /// この画面を開いた時点で走らせておき、投稿のときには出来上がっている
  /// 状態にする。間に合わなければそこで待つ。
  Future<ProfileSnapshot>? _snapshot;

  /// 投稿ボタンを押してから、集計を待つ上限。
  ///
  /// 画面を開いてから押すまでに普通は終わっている。終わっていないのは
  /// 回線が遅いときなので、そこで投稿を止めない方がよい。
  static const Duration _snapshotWait = Duration(seconds: 3);

  void _startSnapshot() {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    _snapshot = ProfileSnapshotService.instance.build(
      uid: uid,
      // 今まさに投稿する曲も「直近に選んだ曲」に入れる。投稿のあとに
      // 集計していた頃は自分の投稿も材料に入っていたので、それに揃える。
      pendingTrack: SnapshotTrack(
        trackName: widget.track.trackName,
        artistName: widget.track.artistName,
        albumImageUrl: widget.track.albumImageUrl,
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    _startSnapshot();
    _loadMe();
    // ignore: discarded_futures
    _loadCanAddPhoto();
    _extractColors();
    WidgetsBinding.instance.addPostFrameCallback((_) => _playPreview());
  }

  @override
  void dispose() {
    _audioService.stopIfOwner(this);
    super.dispose();
  }

  Future<void> _loadCanAddPhoto() async {
    final can = await PostPhotoService.instance.canAddPhotoNow();
    if (mounted) setState(() => _canAddPhoto = can);
  }

  /// 投稿前に写真を選んでおく。実際の保存は投稿が終わってから。
  Future<void> _pickPhoto() async {
    final photo = await AddPhotoFlow.pick(context);
    if (photo != null && mounted) setState(() => _pendingPhoto = photo);
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
      final (start, end) = await ColorExtractor.extractGradientColors(
          widget.track.albumImageUrl);
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
      final username = me?.username ?? user.displayName ?? 'ユーザー';
      final userIconUrl = me?.profileImageUrl;
      final adlTeamId = me?.adlTeamId;
      final university = me?.university;

      final publicPhoto = await _compressPublicPhoto();

      // 画面を開いた時点で走らせてある集計。まだ終わっていなければ少し待つ。
      // 投稿のあとに追いかけて書くと、書き込み直後に読み直すホームで裏面が
      // 空のまま出てしまう。
      //
      // ただし無期限には待たない。集計は再生履歴のページングと Spotify の
      // 画像取得を伴い、回線が詰まると終わらないことがある。投稿そのものを
      // 人質に取らせないため上限を切り、間に合わなければ空で進める。
      // 空で渡すと createPost 側が従来どおり後追いで集計して入れてくれる
      // （[PostWriteService._writeProfileSnapshot]）。
      final snapshot = await _snapshot
          ?.timeout(_snapshotWait, onTimeout: () => ProfileSnapshot.empty);

      final postId = await PostSubmission.submit(
        userId: user.uid,
        photoBytes: publicPhoto?.bytes,
        storage: _storageService,
        postService: _postService,
        createPost: () => _postService.createPost(
          userId: user.uid,
          username: username,
          userIconUrl: userIconUrl,
          trackData: widget.track.toMap(),
          photoUrl: null, // 後追い update
          imageNaturalWidth: (publicPhoto?.width ?? 0).toDouble(),
          imageNaturalHeight: (publicPhoto?.height ?? 0).toDouble(),
          // 歌詞カードの配置。気分投稿に歌詞カードは無いので、本来どれも
          // 要らない。ただし描画側（PostCard の _buildLyricsCardOverlay）は
          // 残してあり、工程を戻すと動き出す。そのとき過去の気分投稿に
          // 歌詞カードが生えないよう、縮尺 0＝描かれない状態で保存しておく。
          // 他の値（位置・回転・写真のオフセット）は既定のままでよい。
          selectedLayoutIndex: 1, // largeAlbumArt
          cardScale: 0,
          isVibe: false,
          // 気分投稿マーカー。ストーリーバー等の集約先ではこのフラグを見て
          // 明示的にスキップする。
          isMoodPost: true,
          adlTeamId: adlTeamId,
          audience: 'public',
          audioStartMs: 0,
          audioDurationSec: 15,
          university: university,
          profileSnapshot: snapshot,
        ),
      );

      _notifyPosted();

      if (!mounted) return;
      await _closeAndOfferPhoto(postId);
    } catch (e) {
      if (!mounted) return;
      AppToast.show(context, '投稿に失敗しました');
      setState(() => _isPosting = false);
    }
  }

  /// 旧フローから写真付きで来たときだけ、公開画像を圧縮して渡す。
  ///
  /// 今の投稿フローでは写真を選ばない（カード裏面がプロフィールに変わり、
  /// 出す場所が無くなったため）。カードに添える非公開の写真は別物で、
  /// そちらは投稿が済んでから [AddPhotoFlow.attach] で紐づける。
  Future<({Uint8List bytes, int width, int height})?>
      _compressPublicPhoto() async {
    final photo = widget.selectedImage;
    if (photo == null) return null;
    final (bytes, w, h) =
        await PhotoHelper.compressForUpload(await photo.readAsBytes());
    return (bytes: bytes, width: w, height: h);
  }

  /// 投稿できたことを、画面の外へ知らせる。待たない。
  void _notifyPosted() {
    // ロック画面の Live Activity を「投稿が完了しました🎉」へ切り替え、
    // 今日の枠に今の投稿のジャケットを入れる。
    // Music Memory のサイクルに紐づく処理なので、Vibe 投稿では呼ばない。
    // ignore: discarded_futures
    LiveActivityService().markPosted();
    // 自分の投稿は友達側のウィジェットに出るものなので、ここでは
    // 自分のウィジェットを更新するだけ（友達の最新を取り直す）。
    // ignore: discarded_futures
    FriendWidgetService.instance.refresh(force: true);
  }

  /// この画面を閉じて、写真を足す導線を出す。
  ///
  /// 完了シートはホームの上に出す。この画面を閉じる前に出すと、pop で
  /// シートごと消えてしまうため、閉じたあとに root の navigator から出す。
  Future<void> _closeAndOfferPhoto(String postId) async {
    // この画面はホームの上に opaque: false で載っているため、
    // pop すればそのままホームが表に出る。
    Navigator.of(context).pop();

    final ctx = Navigator.of(context, rootNavigator: true).context;
    if (!ctx.mounted) return;

    // 投稿前に選んでおいた写真があれば、二度聞かずにそのまま紐づける。
    final chosen = _pendingPhoto;
    if (chosen != null) {
      await AddPhotoFlow.attach(postId: postId, photo: chosen);
      return;
    }

    final wantsPhoto = await PostCompleteSheet.show(ctx);
    if (wantsPhoto && ctx.mounted) {
      await AddPhotoFlow.start(ctx, postId: postId);
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
                    // 最終確認では裏返さない。投稿されるのは 1 枚のカードで、
                    // ここで見せたいのは「どの曲を出すか」だけ。
                    child: _buildFront(),
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
      username: (_me?.username?.isNotEmpty ?? false) ? _me!.username! : 'ユーザー',
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
      // 24:00 までなら写真を選べる。投稿が終わってから紐づける。
      onAddPhoto: (_canAddPhoto && !_isPosting) ? _pickPhoto : null,
      addPhotoLabel: _pendingPhoto != null ? '写真を変更する' : null,
    );
  }
}
